export audible
import Base: eltype, isinf

abstract type AbstractStream{R,T} end
const Audible{R,T} = Union{Sound{R,T},AbstractStream{R,T}}
stream(x::AbstractStream) = x

samplerate{R}(s::AbstractStream{R}) = R*Hz
eltype{R,T}(x::AbstractStream{R,T}) = T
isinf(x::AbstractStream) = isinf(duration(x))
done(x::AbstractStream) = duration(x) <= 0s

struct Stream{R,T} <: AbstractStream{R,T}
  fn::Function
  index::Array{Int,0}
end
stream(x::Sound) = Stream(x)
Stream{T}(R::Int,::Type{T},fn::Function) = Stream{R,T}(fn,Array{Int}() .= 1)

duration(x::Stream) = Inf*s
nsamples(x::Stream) = typemax(Int)
index(x::Stream) = x.index[]
index_ids(x::Stream) = [object_id(x.index)]

Stream{R,T}(x::Sound{R,T,1}) = limit(Stream(R,T,i -> x[i]),nsamples(x))
function Stream{R,T}(x::Sound{R,T,2})
  if nchannels(x) == 2
    leftright(Stream(x[:,left]),Stream(x[:,right]))
  else
    Stream(x[:])
  end
end

Stream(x::Array) = Stream(sound(x))

"""
    sound(stream,[len])

Consume some amount of the stream, converting it to a finite `sound`.

If left unspecified, the entire stream is consumed.  Infinite streams throw an
error.
"""
sound{R}(fs::AbstractStream{R},len::Quantity) = sound(fs,insamples(len,R*Hz))
function sound(fs::AbstractStream)
  if isinf(fs)
    error("Cannot turn an infinite stream into a sound. Specify a length as a ",
          "second argument.")
  else
    sound(fs,nsamples(fs))
  end
end

function sound{R,T}(fs::Stream{R,T},len::Int)
  i = fs.index[]
  fs.index[] .+= len
  Sound{R,T,1}(fs.fn(i:(i+len-1)))
end

"""
    audible(fn,len=Inf,asseconds=true;[sample_rate=samplerate(),eltype=Float64])

Creates monaural sound where `fn(t)` returns the amplitudes for a given `Range`
of time points, value ranging between -1 and 1.

If `asseconds` is false, `audible` creates a monaural sound where `fn(i)`
returns the amplitudes for a given `Range` of sample indices.

The function `fn` should always return elements of type `eltype`.

If an infinite length is specified, a stream is created rather than a sound.

The function `fn` need not be pure and it can be safely assumed that `fn` will
only be called for a given range of indices once. While indices and times passed
to `fn` normally begin from 1 and 0, respectively, this is not always the case.
"""
function audible(fn::Function,len=Inf,asseconds=true;
                 sample_rate=samplerate(),eltype=Float64)
  sample_rate_Hz = inHz(sample_rate)
  if ustrip(len) < Inf
    n = ustrip(insamples(len,sample_rate_Hz))
    R = ustrip(sample_rate_Hz)
    Sound{R,eltype,1}(!asseconds ? fn(1:n) : fn(((1:n)-1)/R))
  else
    R = ustrip(sample_rate_Hz)
    Stream(R,eltype,!asseconds ? fn : i -> fn((i-1)/R))
  end
end

mutable struct LimitStream{R,T} <: AbstractStream{R,T}
  data::AbstractStream{R,T}
  limit::Int
  limit_start::Int
end
duration{R}(x::LimitStream{R}) = inseconds(nsamples(x)*samples,R)
nsamples(x::LimitStream) =
  clamp(min(x.limit,(x.limit_start + x.limit) - index(x.data)),
        0,nsamples(x.data))
index(x::LimitStream) = index(x.data)
index_ids(x::LimitStream) = index_ids(x.data)
function sound(ls::LimitStream,len::Int = typemax(Int))
  ls.limit_start = index(ls)
  sound(ls.data,min(len,nsamples(ls)))
end
right(x::LimitStream) = limit(right(x.data),n)
left(x::LimitStream) = limit(left(x.data),n)

limit{R}(stream::AbstractStream{R},len::Time) = limit(stream,insamples(len,R*Hz))
limit{R,T}(s::AbstractStream{R,T},n::Int) = LimitStream{R,T}(s,n,1)

mutable struct CatStream{R,T} <: AbstractStream{R,T}
  a::AbstractStream{R,T}
  b::AbstractStream{R,T}
end

vcat(xs::Audible...) = error("Sample rates differ, fix with `resample`")
vcat{R}(xs::Audible{R}...) = reduce(vcat_helper,map(stream,xs))
function vcat_helper{R,T}(a::AbstractStream{R,T},b::AbstractStream{R,T})
  if isinf(a)
    error("Connot concatenate to the end of an infinite stream")
  else
    CatStream{R,T}(a,b)
  end
end
function vcat_helper{R,T,S}(a::AbstractStream{R,T},b::AbstractStream{R,S})
  error("Cannot concatenate different element types, convert to common ",
        "element type.")
  # doesn't quite work...
  # P = promote_type(T,S)
  # helper(s) = map(e -> convert(P,e),s)
  # vcat(helper(a),helper(b))
end

duration(x::CatStream) = duration(x.a) + duration(x.b)
nsamples(x::CatStream) =
  isinf(x.a) || isinf(x.b) ? typemax(Int) : nsamples(x.a) + nsamples(x.b)
index(x::CatStream) = index(x.a)
index_ids(x::CatStream) = [index_ids(x.a); index_ids(x.b)]
left(x::CatStream) = CatStream(left(x.a),left(x.b))
right(x::CatStream) = CatStream(right(x.a),right(x.b))

struct EmptyStream{R,T} <: AbstractStream{R,T}
end

duration(x::EmptyStream) = 0s
nsamples(x::EmptyStream) = 0
sound{R,T}(x::EmptyStream{R,T},len::Int) = Sound{R,T,1}(T[])
index(x::EmptyStream) = 0
index_ids(x::EmptyStream) = UInt64[]
left(x::EmptyStream) = x
right(x::EmptyStream) = y

function step_next{R,T}(x::CatStream{R,T},b::CatStream{R,T})
  x.a = b
  x.b = b.b
end

function step_next{R,T}(x::CatStream{R,T},b::AbstractStream{R,T})
  x.a = b
  x.b = EmptyStream{R,T}()
end

function sound(cs::CatStream,len::Int)
  first_part = sound(cs.a,len)
  if nsamples(first_part) < len
    step_next(cs,cs.b)
    result = [first_part; sound(cs,len - nsamples(first_part))]

    result
  else
    first_part
  end
end

function playable{R}(s::AbstractStream{R},cache=true,sample_rate=samplerate())
  if ustrip(sample_rate) != R
    error("Cannot convert a stream at sample rate $(R*Hz) to $sample_rate. ",
          "Create a stream at $sample_rate instead.")
  end
  s
end

"""
For a stream, `fn` will be applied to each unit of sound as it is requested
from the stream.
"""
@inline function audiofn{R,T}(fn::Function,stream::Stream{R,T})
  Stream{R,T}(i -> fn(stream.fn(i)),stream.index)
end

# TODO: we need to lookup the guidelines for implementing broadcast
# before implementing this
# # TODO: this is mostly useful Julia 0.6 where ./ etc... invokes broadcast
# function broadcast{R,T}(f::Function,xs::Stream{R,T}...)
#   let offsets = Int[]
#     Stream{R,T}(xs[1].index) do i
#       if empty(offsets)
#         indices = map(x -> x.index,xs)
#         append!(offsets,[0; indices[1] - indices[2:end]])

#         # TODO: find max, as per soundop
#       end
#       f.(map((x,offset) -> x.fn(i-offset),xs,offsets)...)
#     end
#   end
# end

const emptyfn = () -> nothing
mutable struct OpStream{R,T} <: AbstractStream{R,T}
  op::Function
  a::AbstractStream{R,T}
  b::AbstractStream{R,T}
end

asstream(x::AbstractArray) = Stream(x)
asstream(x::AbstractStream) = x

function *(x::Number,stream::Stream)
  audiofn(stream) do stream
    x * stream
  end
end

function *(stream::Stream,x::Number)
  audiofn(stream) do stream
    x * stream
  end
end

soundop(op,xs::AbstractStream...) =
  error("Incompatible sample rates. Use `resample`.")
soundop{R}(op,xs::Union{Audible{R},Array}...) = soundop(op,map(asstream,xs)...)
soundop{R}(op,xs::AbstractStream{R}...) = reduce((x,y) -> soundop(op,x,y),xs)
soundop(op,x::AbstractStream) = x
function soundop{R,T,S}(op,x::AbstractStream{R,T},y::AbstractStream{R,S})
  error("The streams have different element types, convert to a common, ",
        "element type first.")
  #P = promote_type(T,S)
  #helper(x,_) = map(e -> convert(P,e),x)
  #soundop(op,...
end
function soundop{R,T}(op,x::AbstractStream{R,T},y::AbstractStream{R,T})
  if x !== y && any(i ∈ index_ids(x) for i ∈ index_ids(y))
    error("Cannot combine two streams derrived from the same underlying ",
          " stream. Please use `deepcopy` on one of the streams you are trying",
          " to combine.")
  end
  OpStream{R,T}(op,x,y)
end

duration(x::OpStream) = max(duration(x.a),duration(x.b))
nsamples(x::OpStream) = max(nsamples(x.a),nsamples(x.b))
index(x::OpStream) = index(x.a)
index_ids(x::OpStream) = [index_ids(x.a); index_ids(x.b)]

function sound{R,T}(os::OpStream{R,T},len::Int)
  if os.op === emptyfn
    sound(os.a,len)
  elseif os.a === os.b
    a = sound(os.a,len)
    os.op(a,a)
  else
    na = nsamples(os.a)
    nb = nsamples(os.b)
    N_all = min(na,nb,len)
    x = sound(os.op(sound(os.a,N_all),sound(os.b,N_all)))

    if nb < len && na > nb
      x = [x; sound(os.a,min(len - nb,na - nb))]
      os.op = emptyfn
      os.b = os.a
    elseif na < len && nb > na
      x = [x; sound(os.b,min(len - na,nb - na))]
      os.op = emptyfn
      os.a = os.b
    end

    x
  end
end

function audiofn(fn::Function,stream::AbstractStream)
  soundop(stream,stream) do x,_
    fn(x)
  end
end

leftright{R,T}(x::AbstractStream{R,T},y::AbstractStream{R,T}) =
  soundop(leftright,x,y)

left(x::AbstractStream) = audiofn(left,x)
right(x::AbstractStream) = audiofn(right,x)
