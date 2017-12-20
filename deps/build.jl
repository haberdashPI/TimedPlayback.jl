downloaddir = joinpath(dirname(@__FILE__),"downloads")
bindir = joinpath(dirname(@__FILE__),"usr","lib")

const weber_sound_version = 4

# remove any old build files
for d in [downloaddir,bindir]
  rm(d,recursive=true,force=true)
  mkpath(d)
end

################################################################################
# install SDL2 and plugins

weber_sound = "UNKNOWN"
portaudio = "UNKNOWN"

@static if is_windows()
  # WinRPM lacks SDL2_ttf and SDL2_mixer binaries, so I'm just directly
  # downloading them from the SDL website.
  function setupbin(library,uri)
    libdir = joinpath(downloaddir,library)
    zipfile = joinpath(downloaddir,library*".zip")
    try
      download(uri,zipfile)
      run(`$(joinpath(JULIA_HOME, "7z.exe")) x $zipfile -y -o$libdir`)
      for lib in filter(s -> endswith(s,".dll"),readdir(libdir))
        cp(joinpath(libdir,lib),joinpath(bindir,lib))
      end
      replace(joinpath(bindir,library*".dll"),"\\","\\\\")
    finally
      rm(libdir,recursive=true,force=true)
      rm(zipfile,force=true)
    end
  end

  weber_build = joinpath(dirname(@__FILE__),"build",
                         "libweber-sound.$(weber_sound_version).dll")
  weber_sound = joinpath(bindir,"libweber-sound.$(weber_sound_version).dll")
  portaudio_build = joinpath(dirname(@__FILE__),"lib","portaudio_x64.dll")
  portaudio = joinpath(bindir,"portaudio_x64.dll")
  if isfile(weber_build)
    info("Using Makefile generated libraries $weber_build and $portaudio_build.")
    mv(weber_build,weber_sound)
    mv(portaudio_build,portaudio)
  else
    download("http://haberdashpi.github.io/libweber-sound."*
             "$(weber_sound_version).dll",weber_sound)
    download("http://haberdashpi.github.io/portaudio_x64.dll",portaudio)
  end

  weber_sound = replace(weber_sound,"\\","\\\\")
  portaudio = replace(portaudio,"\\","\\\\")
elseif is_apple()
  using Homebrew

  Homebrew.add("portaudio")

  prefix = joinpath(Homebrew.prefix(),"lib")
  portaudio = joinpath(prefix,"libportaudio.2.dylib")

  weber_build = joinpath(dirname(@__FILE__),"build",
                         "libweber-sound.$(weber_sound_version).dylib")
  weber_sound = joinpath(bindir,"libweber-sound.$(weber_sound_version).dylib")
  if isfile(weber_build)
    info("Using Makefile generated library $weber_build.")
    cp(weber_build,weber_sound)
  else
    original_path = "/usr/local/opt/portaudio/lib/libportaudio.2.dylib"
    download("http://haberdashpi.github.io/libweber-sound."*
             "$(weber_sound_version).dylib",weber_sound)
    run(`install_name_tool -change $original_path $portaudio $weber_sound`)
  end
elseif is_linux()
    error("Linux is not supported at this time.")
else
  error("Unsupported operating system.")
end

@assert portaudio != "UNKNOWN"
@assert weber_sound != "UNKNOWN"

deps = joinpath(dirname(@__FILE__),"deps.jl")
open(deps,"w") do s
  for (var,val) in [:weber_portaudio => portaudio,
                    :weber_sound => weber_sound]
    println(s,"const $var = \"$val\"")
  end
end
