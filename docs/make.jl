using Documenter, TimedSound
makedocs(
  modules = [TimedSound],
  format = :html,
  sitename = "TimedSound.jl",
  html_prettyurls = true,
  pages = Any[
    "User guide" => Any[
      "Creating Sounds" => "stimulus.md",
    ],
    "Reference" => Any[
      "Sound" => "sound.md",
    ]
  ]
)
deploydocs(
  repo = "github.com/haberdashPI/TimedSound.jl.git",
  julia = "0.6",
  osname = "osx",
  deps = nothing,
  make = nothing,
  target = "build"
)
