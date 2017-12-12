__precompile__()

module TimedSound

using Lazy: @>>, @>, @_
using Unitful

export @>>, @>, @_

depsjl = joinpath(@__DIR__, "..", "deps", "deps.jl")
if isfile(depsjl)
  include(depsjl)
else
  error("TimedSound not properly installed. "*
        "Please run\nPkg.build(\"TimedSound\")")
end

include(joinpath(@__DIR__,"units.jl"))
include(joinpath(@__DIR__,"timing.jl"))
include(joinpath(@__DIR__,"sound.jl"))
include(joinpath(@__DIR__,"stream.jl"))
include(joinpath(@__DIR__,"playback.jl"))

include(joinpath(@__DIR__,"audio.jl"))

const localunits = Unitful.basefactors
const localpromotion = Unitful.promotion
function __init__()
  merge!(Unitful.basefactors,localunits)
  merge!(Unitful.promotion, localpromotion)
end

end
