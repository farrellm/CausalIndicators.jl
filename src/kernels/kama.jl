# Kaufman's adaptive moving average (ta_KAMA.c). The efficiency ratio's
# volatility is a CausalFrames `Sum` of `|Δx|` over the last `period` bars and
# its direction reads `x[t - period]` from a `First` over `period + 1` bars, both
# through `CausalFrames.barwindow`. The first value moves from the previous bar.
mutable struct KAMAKernel{T,S,F}
    const period::Int
    n::Int
    prevx::T
    prev::T
    nullrun::Int
    const absdiffs::S
    const lagged::F
end

const KAMA_FASTEST = 2 / (2 + 1)
const KAMA_SLOWEST = 2 / (30 + 1)

"""
    KAMAKernel(T, period)

Kaufman's adaptive moving average over element type `T`, with TA-Lib's fast
and slow constants (2 and 30 bars).
"""
function KAMAKernel(::Type{T}, period::Integer) where {T}
    p = checkperiod("KAMAKernel", period)
    s = CausalFrames.barwindow(Sum(:x), p, (x = T,))
    f = CausalFrames.barwindow(First(:x), p + 1, (x = T,))
    return KAMAKernel{T,typeof(s),typeof(f)}(p, 0, zero(T), zero(T), 0, s, f)
end

CausalFrames.fresh(k::KAMAKernel{T}) where {T} = KAMAKernel(T, k.period)
function CausalFrames.fresh!(k::KAMAKernel{T}) where {T}
    k.n = 0
    k.prevx = zero(T)
    k.prev = zero(T)
    k.nullrun = 0
    fresh!(k.absdiffs)
    fresh!(k.lagged)
    return k
end

lookback(k::KAMAKernel) = k.period == 1 ? 0 : k.period
nseen(k::KAMAKernel) = k.n
current(k::KAMAKernel{T}) where {T} =
    (k.n > lookback(k) ? k.prev : missing)::Union{Missing,T}

function step!(k::KAMAKernel{T}, x::Real) where {T}
    v = convert(T, x)
    n = k.n += 1
    # Period 1 copies the bar, as ta_KAMA.c does explicitly.
    k.period == 1 && return k.prev = v
    update!(k.lagged, (x = v,))
    if n > 1
        d = v - k.prevx
        update!(k.absdiffs, (x = abs(d),))
        # A whole window of exactly flat bars has an exactly zero volatility,
        # whatever round-off the sliding sum holds (ta_KAMA.c's nullRun).
        k.nullrun = d == 0 ? min(k.nullrun + 1, k.period) : 0
    end
    n == k.period + 1 && (k.prev = k.prevx)
    k.prevx = v
    n <= k.period && return missing
    vol = k.nullrun >= k.period ? zero(T) : value(k.absdiffs).x_sum::T
    roc = v - value(k.lagged).x_first::T
    er = vol <= 0 || vol <= roc ? one(T) : min(abs(roc / vol), one(T))
    sc = er * T(KAMA_FASTEST - KAMA_SLOWEST) + T(KAMA_SLOWEST)
    sc *= sc
    return k.prev = (v - k.prev) * sc + k.prev
end
