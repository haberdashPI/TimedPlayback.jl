using LRUCache
export play, stream, stop, setup_sound, current_sound_latency, resume_sounds,
  pause_sounds, tick, sound_is_setup, clear_sound_cache

const weber_sound_version = 4

let
  version_in_file =
    match(r"libweber-sound\.([0-9]+)\.(dylib|dll)",weber_sound).captures[1]
  if parse(Int,version_in_file) != weber_sound_version
    error("Versions for sound driver do not match. Please run ",
          "Pkg.build(\"TimedPlayback\").")
  end
end

const default_sample_rate = 44100Hz

abstract type Hooks end
struct DefaultHooks <: Hooks end

mutable struct SoundSetupState
  samplerate::Freq{Int}
  cache::Bool
  playing::LRU{UInt,Sound}
  state::Ptr{Void}
  num_channels::Int
  queue_size::Int
  stream_unit::Int
  hooks::Hooks
end

const default_stream_unit = 2^12
const sound_setup_state =
    SoundSetupState(0Hz,false,LRU{UInt,Sound}(1),C_NULL,0,0,default_stream_unit,
                    DefaultHooks())
sound_is_setup() = sound_setup_state.samplerate != 0Hz

"""
With no argument samplerate reports the current playback sample rate, as
defined by [`setup_sound`](@ref).
"""
function samplerate(s::SoundSetupState=sound_setup_state)
  if s.samplerate == 0Hz
    default_sample_rate
  else
    s.samplerate
  end
end



# Give some time after the sound stops playing to clean it up.
# This ensures that even when there is some latency
# the sound will not be GC'ed until it is done playing.
const sound_cleanup_wait = 2

# register_sound: ensures that sounds are not GC'ed while they are
# playing. Whenever a new sound is registered it removes sounds that are no
# longer playing. This is called internally by all methods that send requests to
# play sounds to the weber-sound library (implemented in weber_sound.c)
function register_sound(current::Sound,done_at::Float64,wait=sound_cleanup_wait)
  setstate = sound_setup_state
  setstate.playing[object_id(current)] = current
end

show_latency_warnings() = show_latency_warnings(sound_setup_state.hooks)
show_latency_warnings(::Hooks) = false

function ws_if_error(msg)
  if sound_setup_state.state != C_NULL
    str = unsafe_string(ccall((:ws_error_str,weber_sound),Cstring,
                              (Ptr{Void},),sound_setup_state.state))
    if !isempty(str) error(msg*" - "*str) end

    str = unsafe_string(ccall((:ws_warn_str,weber_sound),Cstring,
                              (Ptr{Void},),sound_setup_state.state))
    if !isempty(str) && show_latency_warnings()
      warn(msg*" - "*str)
    end
  end
end

"""
    setup_sound(;[sample_rate=samplerate()],[num_channels=8],[queue_size=8],
                [stream_unit=2^11],[caching=false]
                [hooks=TimedPlayback.DefaultHooks()])

Initialize format and capacity of audio playback.

This function is called automatically (using the default settings) the first
time a `Sound` object is created (e.g. during [`play`](@ref)).  It need not
normally be called explicitly, unless you wish to change one of the default
settings.

# Sample Rate

Sample rate determines the maximum playable frequency (max freq is ≈
sample_rate/2). Changing the sample rate from the default 44100 to a new value
will also change the default sample rate sounds will be created at, to match
this new sample rate.

# Channel Number

The number of channels determines the number of sounds and streams that can be
played concurrently. Note that discrete sounds and streams use a distinct set of
channels.

# Queue Size

Sounds can be queued to play ahead of time (using the `time` parameter of
[`play`](@ref)). When you request that a sound be played it may be queued to
play on a channel where a sound is already playing. The number of sounds that
can be queued to play at once is determined by queue size. The number of
channels times the queue size determines the number of sounds that you can queue
up to play ahead of time.

# Stream Unit

The stream unit determines the number of samples that are streamed at one time.
If this value is too small for your hardware, streams will sound jumpy. However
the latency of streams will increase as the stream unit increases.

# Caching

If you enable caching, by default, loading or converting the same object into a
sound after the first time will result in the same sound object. You can always
disable caching for a specific call to generate a sound (see documentation for
[`sound`](@ref) and [`playable`](@ref)).

# Playback Hooks

There are a number of hooks into the playback mechanism
which you can use to customize playback. To do so, define a
child of the type `TimedPlayback.Hooks` and define as many of the following
methods on this type as you wish. All methods have default fallbacks.

* `show_latency_warnings(hooks)` - true if you wish warnings about slow
playback latency to be displayed. (Default is `false`)
* `on_high_latency(hooks,latency)` - called following a high latency warning;
  specified the latency of playback. (Default does nothing)
* `on_play(hooks)` - called each `play` is called (Default does nothing)
* `tick` - returns the current time in seconds since epochs (Default uses
  `TimedPlayback.precise_time()`)
* `on_no_timing(hooks)` - called when there is no timing specified during
   `play`. (Default does nothing)
* `get_streamers` - returns a dictionary of channel numbers to streamers. See
   documentation for `Streamer`. Currently undocumented.
   (Default manages streamers internally)
"""
function setup_sound(;sample_rate=samplerate(),
                     buffer_size=nothing,queue_size=8,num_channels=8,
                     stream_unit=default_stream_unit,
                     caching=false,
                     hooks=DefaultHooks())
  sound_setup_state.hooks = hooks
  sample_rate_Hz = inHz(Int,sample_rate)
  empty!(sound_cache)

  if sound_is_setup()
    ccall((:ws_close,weber_sound),Void,(Ptr{Void},),sound_setup_state.state)
    ws_if_error("While closing old audio stream during setup")
    ccall((:ws_free,weber_sound),Void,(Ptr{Void},),sound_setup_state.state)
  else
    if !sound_is_initialized[]
      sound_is_initialized[] = true
      atexit() do
        sleep(0.1)
        ccall((:ws_close,weber_sound),Void,
              (Ptr{Void},),sound_setup_state.state)
        ws_if_error("While closing audio stream at exit.")
        ccall((:ws_free,weber_sound),Void,
              (Ptr{Void},),sound_setup_state.state)
      end
    end
  end

  sound_setup_state.samplerate = sample_rate_Hz
  sound_setup_state.cache = caching
  sound_setup_state.state = ccall((:ws_setup,weber_sound),Ptr{Void},
                                  (Cint,Cint,Cint,),ustrip(sample_rate_Hz),
                                  num_channels,queue_size)
  sound_setup_state.playing =
    LRU{UInt,Sound}(2 * (queue_size*num_channels + 2*num_channels))
  sound_setup_state.num_channels = num_channels
  sound_setup_state.queue_size = queue_size
  sound_setup_state.stream_unit = stream_unit
  ws_if_error("While trying to initialize sound")
end
const sound_is_initialized = fill(false)

"""
    TimedPlayback.usecache()

Reports the default state of caching. If true, then sounds will be cached when
created through [`sound`](@ref) or [`playable`](@ref) by default.
"""
usecache() = sound_setup_state.cache

"""
    current_sound_latency()

Reports the current, minimum latency of audio playback.

The current latency depends on your hardware and software drivers. This
estimate does not include the time it takes for a sound to travel from
your sound card to speakers or headphones. This latency estimate is used
internally by [`play`](@ref) to present sounds at accurate times.
"""
function current_sound_latency()
  ccall((:ws_cur_latency,weber_sound),Cdouble,
        (Ptr{Void},),sound_setup_state.state)
end

"""
    play(x;[channel=0],[time=0s])

Plays a sound (created via [`sound`](@ref)).

For convenience, play can also can be called on any object that can be turned
into a sound (via `sound`).

If a time is specified, it indicates the amount of time since epoch that the
sound should start playing (see [`precise_time`](@ref)).

This function returns immediately with the channel the sound is playing on. You
may provide a specific channel that the sound plays on: only one sound can be
played per channel. Normally it is unecessary to specify a channel, because an
appropriate channel is selected for you. However, pausing and resuming of
sounds occurs on a per channel basis, so if you plan to pause a specific
sound, you can do so by specifying its channel.

# Streams

Play can also be used to present a continuous stream of sound.  In this case,
the channel defaults to channel 1 (there is no automatic selection of channels
for streams). Streams are usually created by specifying an infinite length
during sound generation using [`tone`](@ref), [`noise`](@ref),
[`harmonic_complex`](@ref) or [`audible`](@ref).
"""
function play(x;time=0.0s,channel=0)
  if !sound_is_setup()
    setup_sound()
  end

  on_play(sound_setup_state.hooks)
  play_(playable(x),ustrip(inseconds(time,samplerate(x))),channel)
end
on_play(::Hooks) = nothing

immutable WS_Sound
  buffer::Ptr{Void}
  len::Cint
end
WS_Sound{R}(x::Sound{R,Q0f15,2}) = WS_Sound(pointer(x.data),size(x,1))

tick(::Hooks) = precise_time()
tick(x::SoundSetupState) = tick(x.hooks)
tick() = tick(sound_setup_state)

"""
    at(offset)

Returns a precise time since epoch (in seconds) plus some offset.

Use this method to help specify exactly when a given sound should be played. You
can subsently add aditional offsets via
[`Unitful`](https://github.com/ajkeller34/Unitful.jl) values, e.g.

    sound1_time = at(10s) # 10 seconds from now
    sound2_time = sound1_time + 200ms # 10.2 seconds from now

In addition to adding a specificied onset, This differs from [`Base.time`](@ref)
in that it is generally more precise on windows machines (as of Julia v0.6), and
in that it makes use of the `Unitful` seconds type.

"""
at(time) = time + s*tick()

function play_{R}(x::Sound{R,Q0f15,2},time::Float64=0.0,channel::Int=0)
  if R != ustrip(samplerate())
    error("Sample rate of sound ($(R*Hz)) and audio playback ($(samplerate()))",
          " do not match. Please resample this sound by calling `resample` ",
          "or `playable`.")
  end
  if !(1 <= channel <= sound_setup_state.num_channels || channel <= 0)
    error("Channel $channel does not exist. Must fall between 1 and",
          " $(sound_setup_state.num_channels)")
  end

  # first, verify the sound can be played when we want to
  if time > 0.0
    latency = current_sound_latency()
    now = tick()
    if now + latency > time && show_latency_warnings()
      if latency > 0
        warn("Requested timing of sound cannot be achieved. ",
             "With your hardware you cannot request the playback of a sound ",
             "< $(round(1000*latency,2))ms before it begins.")
      else
        warn("Requested timing of sound cannot be achieved. ",
             "Give more time for the sound to be played.")
      end
      on_high_latency(sound_setup_state.hooks,(now + latency) - time)
    end
  else
    on_no_timing(sound_setup_state.hooks)
  end

  # play the sound
  channel = ccall((:ws_play,weber_sound),Cint,
                  (Cdouble,Cdouble,Cint,Ref{WS_Sound},Ptr{Void}),
                  tick(),time,channel-1,WS_Sound(x),
                  sound_setup_state.state) + 1
  ws_if_error("While playing sound")
  register_sound(x,(time > 0.0 ? time : tick()) +
                 ustrip(duration(x)))

  channel
end

on_high_latency(::Hooks,latency) = nothing
on_no_timing(::Hooks) = nothing

"""
    play(fn::Function)

Play the sound that's returned by calling `fn`.
"""
function play(fn::Function;keys...)
  play(fn();keys...)
end

"""
    Streamer

TODO: document streamer implementation
"""
mutable struct Streamer
  next_stream::Float64
  channel::Int
  stream::AbstractStream
  cache::Nullable{Sound}
  done_at::Float64
  start_at::Float64
end

const num_channels = 8
const streamers = Dict{Int,Streamer}()

function setup_streamers()
  empty = EmptyStream{ustrip(samplerate()),Q0f15}()
  streamers[-1] = Streamer(0.0,1,empty,Nullable(),0.0,0.0)
  Timer(t -> map(process,values(streamers)),1/60,1/60)
end

function get_streamers(::Hooks)
  if isempty(streamers)
    setup_streamers()
  end
  streamers
end

function play_{R}(stream::AbstractStream{R},time::Float64=0.0,channel::Int=1)
  channel = channel == 0 ? 1 : channel
  @assert 1 <= channel <= sound_setup_state.num_channels
  if R != ustrip(samplerate())
    error("Sample rate of sound ($(R*Hz)) and audio playback ($(samplerate()))",
          " do not match. Please resample this sound by calling `resample`.")
  end

  cur_streamers = get_streamers(sound_setup_state.hooks)
  unit_s = sound_setup_state.stream_unit / R

  if channel in keys(cur_streamers)
    streamer = cur_streamers[channel]

    if time > 0
      if streamer.done_at < time && show_latency_warnings()
        offset = time - streamer.done_at

        cat_stream = [limit(streamer.stream,offset*s); stream]
        cur_streamers[channel] =
          Streamer(streamer.next_stream,channel,cat_stream,Nullable(),
                   streamer.done_at,-1)
      else
        warn("Requested timing of stream cannot be achieved. ",
             "With the current streaming settings you cannot request playback ",
             "more than $(round(1000*unit_s,2))ms beforehand.")
        on_high_latency(sound_setup_state.hooks,streamer.done_at - time)
        cur_streamers[channel] = Streamer(tick(),channel,stream,Nullable(),
                                          streamer.done_at + unit_s,-1)
      end
    else
      cur_streamers[channel] = Streamer(tick(),channel,stream,Nullable(),
                                        streamer.done_at + unit_s,-1)
    end
  else
    cur_streamers[channel] = Streamer(tick(),channel,stream,Nullable(),
                                      tick()+unit_s,time)
  end
end

"""
    stop(channel)

Stop the stream that is playing on the given channel.
"""
function stop(channel::Int,stream::Bool=false)
  @assert 1 <= channel <= sound_setup_state.num_channels
  if stream
    delete!(get_streamers(sound_setup_state.hooks),channel)
  else
    ccall((:ws_stop,weber_sound),Void,(Ptr{Void},Cint),
          sound_setup_state.state,channel-1)
  end
  nothing
end

function process(streamer::Streamer)
  if streamer.stream isa EmptyStream
    return
  elseif done(streamer.stream) && isnull(streamer.cache)
    stop(streamer.channel)
    return
  end

  toplay = if !isnull(streamer.cache) get(streamer.cache) else
    x = sound(streamer.stream,sound_setup_state.stream_unit)
    result = playable(x)
    streamer.cache = Nullable(result)
    result
  end

  done_at = ccall((:ws_play_next,weber_sound),Cdouble,
                  (Cdouble,Cdouble,Cint,Ref{WS_Sound},Ptr{Void}),
                  tick(),streamer.start_at,streamer.channel-1,WS_Sound(toplay),
                  sound_setup_state.state)

  ws_if_error("While playing sound")
  if done_at < 0
    # sound not ready to be queued for playing, wait a bit and try again
    streamer.next_stream += ustrip(0.05duration(toplay))
  else
    # sound was queued to play, wait until this queued sound actually
    # starts playing to queue the next stream unit
    streamer.cache = Nullable()
    register_sound(toplay,done_at,4sound_setup_state.stream_unit / samplerate())
    streamer.next_stream += ustrip(0.75duration(toplay))
    streamer.done_at = done_at
    streamer.start_at = -1
  end
end

"""
    pause_sounds([channel],[isstream=false])

Pause all sounds (or a stream) playing on a given channel.

If no channel is specified, then all sounds are paused.
"""
function pause_sounds(channel=-1,isstream=false)
  if sound_is_setup()
    @assert 1 <= channel <= sound_setup_state.num_channels || channel <= 0
    ccall((:ws_pause,weber_sound),Void,(Ptr{Void},Cint,Cint,Cint),
          sound_setup_state.state,channel-1,isstream,true)
    ws_if_error("While pausing sounds")
  end
end

"""
    resume_sounds([channel],[isstream=false])

Resume all sounds (or a stream) playing on a given channel.

If no channel is specified, then all sounds are resumed.
"""
function resume_sounds(channel=-1,isstream=false)
  if sound_is_setup()
    @assert 1 <= channel <= sound_setup_state.num_channels || channel <= 0
    ccall((:ws_pause,weber_sound),Void,(Ptr{Void},Cint,Cint,Cint),
        sound_setup_state.state,channel-1,isstream,false)
    ws_if_error("While resuming audio playback")
  end
end
