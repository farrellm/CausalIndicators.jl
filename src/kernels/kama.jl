# Kaufman's efficiency ratio (ta_ER.c), the ratio ta_KAMA.c computes inside its
# recursion: the net move over `period` bars divided by the path travelled. The
# path is a CausalFrames `Sum` of `|Δx|` over the last `period` bars and the net
# move reads `x[t - period]` from a `First` over `period + 1` bars, both through
# `CausalFrames.barwindow`.
mutable struct ERKernel{T,S,F}
    const period::Int
    n::Int
    prevx::T
    nullrun::Int
    const absdiffs::S
    const lagged::F
end

"""
    ERKernel(T, period)

Kaufman's efficiency ratio over the last `period` bar-to-bar changes, element
type `T`, in [0, 1]. A flat window gives 1, as ta_ER.c and ta_KAMA.c do.
"""
function ERKernel(::Type{T}, period::Integer) where {T}
    p = checkperiod("ERKernel", period)
    s = CausalFrames.barwindow(Sum(:x), p, (x = T,))
    f = CausalFrames.barwindow(First(:x), p + 1, (x = T,))
    return ERKernel{T,typeof(s),typeof(f)}(p, 0, zero(T), 0, s, f)
end

CausalFrames.fresh(e::ERKernel{T}) where {T} = ERKernel(T, e.period)
function CausalFrames.fresh!(e::ERKernel{T}) where {T}
    e.n = 0
    e.prevx = zero(T)
    e.nullrun = 0
    fresh!(e.absdiffs)
    fresh!(e.lagged)
    return e
end

lookback(e::ERKernel) = e.period
nseen(e::ERKernel) = e.n

function step!(e::ERKernel{T}, x::Real) where {T}
    v = convert(T, x)
    n = e.n += 1
    update!(e.lagged, (x = v,))
    if n > 1
        d = v - e.prevx
        update!(e.absdiffs, (x = abs(d),))
        # A whole window of exactly flat bars has an exactly zero path, whatever
        # round-off the sliding sum holds (ta_ER.c's and ta_KAMA.c's nullRun).
        e.nullrun = d == 0 ? min(e.nullrun + 1, e.period) : 0
    end
    e.prevx = v
    n <= e.period && return missing
    vol = e.nullrun >= e.period ? zero(T) : value(e.absdiffs).x_sum::T
    roc = v - value(e.lagged).x_first::T
    # Pinned to 1 on a straight-line advance and a flat window, clamped to 1.
    return vol <= 0 || vol <= roc ? one(T) : min(abs(roc / vol), one(T))
end

# Kaufman's adaptive moving average (ta_KAMA.c): an EMA whose smoothing constant
# moves with the efficiency ratio of an `ERKernel`. The first value moves from
# the previous bar.
mutable struct KAMAKernel{T,E}
    n::Int
    prev::T
    const er::E
end

const KAMA_FASTEST = 2 / (2 + 1)
const KAMA_SLOWEST = 2 / (30 + 1)

"""
    KAMAKernel(T, period)

Kaufman's adaptive moving average over element type `T`, with TA-Lib's fast
and slow constants (2 and 30 bars).
"""
function KAMAKernel(::Type{T}, period::Integer) where {T}
    e = ERKernel(T, checkperiod("KAMAKernel", period))
    return KAMAKernel{T,typeof(e)}(0, zero(T), e)
end

CausalFrames.fresh(k::KAMAKernel{T}) where {T} = KAMAKernel(T, k.er.period)
function CausalFrames.fresh!(k::KAMAKernel{T}) where {T}
    k.n = 0
    k.prev = zero(T)
    fresh!(k.er)
    return k
end

lookback(k::KAMAKernel) = k.er.period == 1 ? 0 : k.er.period
nseen(k::KAMAKernel) = k.n
current(k::KAMAKernel{T}) where {T} =
    (k.n > lookback(k) ? k.prev : missing)::Union{Missing,T}

function step!(k::KAMAKernel{T}, x::Real) where {T}
    v = convert(T, x)
    n = k.n += 1
    p = k.er.period
    # Period 1 copies the bar, as ta_KAMA.c does explicitly.
    p == 1 && return k.prev = v
    n == p + 1 && (k.prev = k.er.prevx)
    er = step!(k.er, v)
    ismissing(er) && return missing
    sc = er * T(KAMA_FASTEST - KAMA_SLOWEST) + T(KAMA_SLOWEST)
    sc *= sc
    return k.prev = (v - k.prev) * sc + k.prev
end
