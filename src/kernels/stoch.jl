# The stochastic %K inside a recursive state (ta_STOCHF.c): where the close sits
# in the window's high-low range, as a percentage. It is the internal dependent
# `StochK` over CausalFrames' `Max`, `Min` and `Last`, under
# `CausalFrames.barwindow`, so the extremes slide the upstream monotone deques.
# Stoch and StochF run it over high, low and close; StochRSI runs it over one
# series (`StochK{:x,:x,:x}`), as ta_STOCHRSI.c passes the RSI as all three.

# An internal dependent: `(c − l)/(h − l)·100` from the window's highest high,
# lowest low and last close, or 0 where TA-Lib finds the range zero.
struct StochK{H,L,C} <: GroupSummarizer end

CausalFrames.dependencies(::StochK{H,L,C}) where {H,L,C} = (Max(H), Min(L), Last(C))
CausalFrames.emptyvalue(::StochK) = (; stochk = missing)
CausalFrames.fresh(::StochK{H,L,C}, ::NamedTuple) where {H,L,C} =
    derivedvalue(:stochk, (Symbol(H, :_max), Symbol(L, :_min), Symbol(C, :_last)),
        stochk)

stochk(h, l, c) =
    h === missing || l === missing || c === missing ? missing : stochkvalue(h, l, c)
stochkvalue(h, l, c) =
    iszeroscaled(h - l, abs(h) + abs(l)) ? zero((c - l) / (h - l)) : (c - l) / (h - l) * 100

mutable struct FastKKernel{T,F,W}
    const period::Int
    n::Int
    const window::W
end

"""
    FastKKernel(T, period, form = :hlc)

The stochastic %K over the last `period` bars, element type `T`. Form `:hlc`
steps `step!(k, high, low, close)`, and form `:x` steps `step!(k, x)` with the
one series as all three.
"""
function FastKKernel(::Type{T}, period::Integer, form::Symbol = :hlc) where {T}
    p = checkperiod("FastKKernel", period)
    w = if form === :hlc
        CausalFrames.barwindow(StochK{:high,:low,:close}(), p,
            (high = T, low = T, close = T))
    elseif form === :x
        CausalFrames.barwindow(StochK{:x,:x,:x}(), p, (x = T,))
    else
        throw(ArgumentError("FastKKernel form must be :hlc or :x, got $(repr(form))"))
    end
    return FastKKernel{T,form,typeof(w)}(p, 0, w)
end

CausalFrames.fresh(k::FastKKernel{T,F}) where {T,F} = FastKKernel(T, k.period, F)
function CausalFrames.fresh!(k::FastKKernel)
    k.n = 0
    fresh!(k.window)
    return k
end

lookback(k::FastKKernel) = k.period - 1
nseen(k::FastKKernel) = k.n
current(k::FastKKernel{T}) where {T} =
    convert(Union{Missing,T}, value(k.window).stochk)

function step!(k::FastKKernel{T,:hlc}, h::Real, l::Real, c::Real) where {T}
    k.n += 1
    update!(k.window, (high = convert(T, h), low = convert(T, l), close = convert(T, c)))
    return current(k)
end

function step!(k::FastKKernel{T,:x}, x::Real) where {T}
    k.n += 1
    update!(k.window, (x = convert(T, x),))
    return current(k)
end
