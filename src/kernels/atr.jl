# TA-Lib's average true range (ta_ATR.c): each bar's true range against the
# previous close, smoothed by a `:mean` `WilderKernel`. The first bar only sets
# the previous close, so the average is first available after `period + 1`
# bars. Sharing `WilderKernel` with RMA keeps TA-Lib's identity
# `RMA(TRANGE) == ATR`.
mutable struct ATRKernel{T,W}
    n::Int
    prevclose::T
    const wilder::W
end

"""
    ATRKernel(T, period)

Wilder's average true range over element type `T`, stepped with
`step!(k, high, low, close)`. ATR, NATR, KeltnerChannels and SuperTrend read it.
"""
function ATRKernel(::Type{T}, period::Integer) where {T}
    w = WilderKernel(T, checkperiod("ATRKernel", period))
    return ATRKernel{T,typeof(w)}(0, zero(T), w)
end

CausalFrames.fresh(k::ATRKernel{T}) where {T} = ATRKernel(T, k.wilder.period)
function CausalFrames.fresh!(k::ATRKernel{T}) where {T}
    k.n = 0
    k.prevclose = zero(T)
    fresh!(k.wilder)
    return k
end

lookback(k::ATRKernel) = k.wilder.period
nseen(k::ATRKernel) = k.n
current(k::ATRKernel) = k.n > 1 ? current(k.wilder) : missing

function step!(k::ATRKernel{T}, h::Real, l::Real, c::Real) where {T}
    cy = k.prevclose
    k.prevclose = convert(T, c)
    k.n += 1
    k.n == 1 && return missing
    return step!(k.wilder, truerange(convert(T, h), convert(T, l), cy))
end
