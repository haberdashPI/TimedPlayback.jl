# How to create sounds

There are two primary ways to create sounds: loading a file and composing sound primitives.

## Loading a file

You can play or create sounds from files by directly playing the filename, or creating a sound first

```julia
play("mysound_file.wav")

x = sound("mysound_file.wav")
play(x)
```


If you need to manipulate the sound before playing it, you can load it using [`sound`](@ref).  For example, to remove any frequencies from `"mysound.wav"` above 400Hz before playing the sound, you could do the following.

```julia
mysound = lowpass(sound("mysound.wav"),400Hz)
play(mysound)
```

## Sound Primitives

There are several primitives you can use to generate simple sounds. They are [`tone`](@ref) (to create a pure), [`noise`](@ref) (to generate white noise), [`silence`](@ref) (for a silent period) and [`harmonic_complex`](@ref) (to create multiple pure tones with integer frequency ratios).

These primitives can then be combined and manipulated to generate more interesting sounds. You can filter sounds ([`bandpass`](@ref), [`bandstop`](@ref), [`lowpass`](@ref), [`highpass`](@ref) and [`lowpass`](@ref)), mix them together ([`mix`](@ref)) and set an appropriate decibel level ([`attenuate`](@ref)). You can also manipulate the envelope of the sound ([`ramp`](@ref), [`rampon`](@ref), [`rampoff`](@ref), [`fadeto`](@ref), [`envelope`](@ref) and [`mult`](@ref)).

For instance, to play a 1 kHz tone for 1 second inside of a noise with a notch from 0.5 to 1.5 kHz, with 5 dB SNR you could call the following.

```julia
mysound = tone(1kHz,1s)
mysound = ramp(mysound)
mysound = attenuate(mysound,20)

mynoise = noise(1s)
mynoise = bandstop(mynoise,0.5kHz,1.5kHz)
mynoise = attenuate(mynoise,25)

play(mix(mysound,mynoise))
```

TimedSound exports the macro `@>` (from [Lazy.jl](https://github.com/MikeInnes/Lazy.jl#macros)) to simplify this pattern. It is easiest to understand the macro by example: the below code yields the same result as the code above.

```juila
mytone = @> tone(1kHz,1s) ramp attenuate(20)
mynoise = @> noise(1s) bandstop(0.5kHz,1.5kHz) attenuate(25)
play(mix(mytone,mynoise))
```

TimedSound also exports `@>>`, and `@_` (refer to [Lazy.jl](https://github.com/MikeInnes/Lazy.jl#macros) for details).

### Sounds are arrays

Sounds are just a specific kind of array of real numbers. The amplitudes
of a sound are represented as real numbers between -1 and 1 in sequence at a
sampling rate specific to the sound's type. They can be manipulated in the same way that any array can be manipulated in Julia, with some additional support for indexing sounds using time units. For instance, to get the first 5 seconds of a sound you can do the following.

```julia
mytone = tone(1kHz,10s)
mytone[0s .. 5s]
```

To represent the end of a sound using this special indexing, you can use `ends`. For instance, to get the last 5 seconds of `mysound` you can do the following.

```julia
mytone[5s .. ends]
```

We can concatenate multiple sounds, to play them in sequence. The
following code plays two tones in sequence, with a 100 ms gap between them.

```julia
interval = [tone(400Hz,50ms); silence(100ms); tone(400Hz * 2^(5/12),50ms)]
play(interval)
```

### Stereo Sounds

You can create stereo sounds with [`leftright`](@ref), and reference the left and right channel using `:left` or `:right` as a second index, like so.

```julia
stereo_sound = leftright(tone(1kHz,2s),tone(2kHz,2s))
play(stereo_sound[:,:left])
play(stereo_sound[:,:right])
```

The functions [`left`](@ref) and [`right`](@ref) can also extract the left and right channel, but work on both sounds and streams.

# Timing Sounds

A key fature of TimedSounds is that you can time the presentation of the sounds. This is done using the `at` function to get a specific time stamp and the `time` keyword argument to `play`, as follows.

```julia
using TimedSound

reference = at(1s) # 1 second from now

sound1_time = reference
sound2_time = reference + 200ms
sound3_time = reference + 2s

sound1 = @> tone(1kHz) attenuate(20) # an unending 1 kHz pure tone
sound2 = @> sound("mysound.wav") attenuate(10)
sound3 = @> audible(t -> 1000t .% 1,2s) # 2 second, 1 kHz saw tooth 

play(sound1,time=sound1_time)
play(sound2,time=sound2_time)
play(sound3,time=sound3_time)
```

TimedSound will carefully track the actually time the sound was played and issue a warning if need be.

# Streams

In addition to the discrete sounds that have been discussed so far, TimedSound also supports sound streams. Streams are arbitrarily long: you need not decide when they should stop until after they start playing. All of the primitives described so far can apply to streams (including concatenation), except that streams cannot be indexed.

!!! note "Streaming operations are lazy"

    All manipulations of streams are lazy: they are applied just as the stream
    is played. The more operators you apply to a stream the more processing that
    has to occur during playback. If you have a particularly complicated stream
    you may have to increase streaming latency by changing the `stream_unit`
    parameter of [`setup_sound`](@ref), or consider an alternative approach
    (e.g. [`audible`](@ref)).

To create a stream you can use one of the standard primitives, leaving out the length parameter. For example, the following will play a 1 kHz pure tone until julia quits.

```julia
play(tone(1kHz))
```

Streams always play on a specific stream channel, so if you want to stop the stream at some point you can request that the channel stop. The following plays a pure tone until something_happened() returns true.

```julia
play(tone(1kHz),channel=1)
while !something_happened()
end
stop(1)
```

Streams can be manipulated as they are playing as well, so if you wanted to have a ramp at the start and end of the stream to avoid clicks, you could change the example above, to the following.

```julia
ongoing_tone = @> tone(1kHz) rampon
play(ongoing_tone,channel=1)
while !something_happened()
end
play(rampoff(ongoing_tone),channel=1)
```

!!! warning "Streams are stateful"

    This example also demonstrates the stateful nature of streams. Once some
    part of a stream has been played it is forever consumed, and cannot be
    played again. After the stream is played, subsequent modifications only apply
    to unplayed frames of the stream. *BEWARE*: this means that you cannot
    play two different modifications of the same stream.

Just as with sound, manipulations to streams can be precisely timed. The following will turn the sound off precisely 1 second after something_happened() returns true.


```julia
ongoing_tone = @> tone(1kHz) rampon
play(ongoing_tone,channel=1)
while !something_happened()
end
reference = at(1s)
play(rampoff(ongoing_tone),channel=1,time=reference + 1s))
```

If you wish to turn the entirety of a finite stream into a sound, you can use [`sound`](@ref). You can also grab the next section of an infinite stream using [`sound`](@ref) if you provide a second parameter specifying the length of the stream you want to turn into a sound.

Some manipulations of streams require that the stream be treated as a sound. You can modify individual sound segments as they play from the stream using [`audiofn`](@ref). (Calling [`audiofn`](@ref) on a sound, rather than a stream, is the same as applying the given function to the sound directly).

## Low-level Sound/Stream Generation

Finally, if none of the functions above suit your purposes for generating sounds or streams, there are two more low-level approachs. You can use the function [`audible`](@ref) to define a sound or stream using a function `f(t)` or `f(i)` defining the amplitudes for any given time or index. Alternatively you can convert any array to a sound using [`sound`](@ref).
