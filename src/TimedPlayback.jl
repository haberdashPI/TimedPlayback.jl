__precompile__()

module TimedPlayback

using Lazy: @>, @_
using Unitful

export @>, @_

depsjl = joinpath(dirname(@__FILE__), "..", "deps", "deps.jl")
if isfile(depsjl)
  include(depsjl)
else
  error("TimedPlayback not properly installed. "*
        "Please run\nPkg.build(\"TimedPlayback\")")
end

const sound_is_setup = Array{Bool}()
sound_is_setup[] = false

include(joinpath(dirname(@__FILE__),"units.jl"))
include(joinpath(dirname(@__FILE__),"timing.jl"))
include(joinpath(dirname(@__FILE__),"sound.jl"))
include(joinpath(dirname(@__FILE__),"stream.jl"))
include(joinpath(dirname(@__FILE__),"playback.jl"))

include(joinpath(dirname(@__FILE__),"audio.jl"))

const localunits = Unitful.basefactors
const localpromotion = Unitful.promotion
function __init__()
  merge!(Unitful.basefactors,localunits)
  merge!(Unitful.promotion, localpromotion)
end

end
