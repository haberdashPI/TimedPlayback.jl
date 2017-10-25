# TimedPlayback

[![Project Status: WIP – Initial development is in progress, but there has not yet been a stable, usable release suitable for the public.](http://www.repostatus.org/badges/latest/wip.svg)](http://www.repostatus.org/#wip) [![](https://img.shields.io/badge/docs-latest-blue.svg)](https://haberdashPI.github.io/TimedPlayback.jl/latest)
<!-- [![Build status](https://ci.appveyor.com/api/projects/status/uvxq5mqlq0p2ap02/branch/master?svg=true)](https://ci.appveyor.com/project/haberdashPI/weber-jl/branch/master) -->
<!-- [![TravisCI Status](https://travis-ci.org/haberdashPI/Weber.jl.svg?branch=master)](https://travis-ci.org/haberdashPI/Weber.jl) -->
<!-- [![](https://img.shields.io/badge/docs-stable-blue.svg)](https://haberdashPI.github.io/Weber.jl/stable) -->

TimedPlayback provides a simple interface to create and play discrete sounds and continuous streams of sound. Unlike the existing solutions to [audio playback in julia](https://github.com/JuliaAudio), this library allows those sounds and streams to occur at relativley precise times:

```julia
using TimedPlayback

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

If the desired timing cannot be achieved, `play` will generate a warning. Note
that there will always be a small amount of latency in audioplayback, due to
specific audio drivers available on your machine and the physical delays present
in your speakers. On a relatively modern windows machine I've recorded a playback jitter of ~5 ms using this library during an EEG experiment.

See the [documentation](https://haberdashPI.github.io/TimedPlayback.jl/latest)
for more details.

# Plans

There are few things that need to be cleaned up since moving this to
a separate package from [Weber.jl](https://github.com/haberdashPI/Weber.jl)
to really make it an independent library.

- [ ] Separate out the documentation from Weber.jl
- [ ] CI testing and documentation-build setup
- [ ] [Fix caching bug](https://github.com/haberdashPI/Weber.jl/issues/72)
- [ ] Implement `stop` for sounds in addition to streams
- [ ] Fix latency warnings to work properly (clear warning buffer).
- [ ] Fix bugs in streaming playback introduced by changes in Julia v0.6
      (comes up when calling `stop` (maybe only when using `audible`??))

Longer term goals:

- [ ] Document hooks API
- [ ] Should I use [AxisArrays.jl](https://github.com/JuliaArrays/AxisArrays.jl)?
- [ ] Get tests working on linux
