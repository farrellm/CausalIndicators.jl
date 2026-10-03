# The linearly weighted moving average inside a recursive state: the package's
# `WMA` dependent under `CausalFrames.barwindow`, so it folds through the
# upstream `AgeWeightedSum`, `Sum` and `Count` rather than its own sums.
mutable struct WMAKernel{T,W}
    const period::Int
    n::Int
    const window::W
end

"""
    WMAKernel(T, period)

A `period`-bar linearly weighted moving average kernel over element type `T`.
"""
function WMAKernel(::Type{T}, period::Integer) where {T}
    p = checkperiod("WMAKernel", period)
    w = CausalFrames.barwindow(WMA(:x), p, (x = T,))
    return WMAKernel{T,typeof(w)}(p, 0, w)
end

CausalFrames.fresh(w::WMAKernel{T}) where {T} = WMAKernel(T, w.period)
function CausalFrames.fresh!(w::WMAKernel)
    w.n = 0
    fresh!(w.window)
    return w
end

lookback(w::WMAKernel) = w.period - 1
nseen(w::WMAKernel) = w.n
current(w::WMAKernel{T}) where {T} = convert(Union{Missing,T}, value(w.window).x_wma)

function step!(w::WMAKernel{T}, x::Real) where {T}
    w.n += 1
    update!(w.window, (x = convert(T, x),))
    return current(w)
end

# TA-Lib's TRIMA (ta_TRIMA.c, trima.md): an SMA of an SMA, of
# `(period + 1) ÷ 2` bars twice for an odd period, and `period ÷ 2` then
# `period ÷ 2 + 1` bars for an even one.
mutable struct TRIMAKernel{T,K}
    const period::Int
    n::Int
    const s1::K
    const s2::K
end

"""
    TRIMAKernel(T, period)

TA-Lib's triangular moving average over element type `T`.
"""
function TRIMAKernel(::Type{T}, period::Integer) where {T}
    p = checkperiod("TRIMAKernel", period)
    n1, n2 = isodd(p) ? ((p + 1) ÷ 2, (p + 1) ÷ 2) : (p ÷ 2, p ÷ 2 + 1)
    s1 = SMAKernel(T, n1)
    return TRIMAKernel{T,typeof(s1)}(p, 0, s1, SMAKernel(T, n2))
end

CausalFrames.fresh(t::TRIMAKernel{T}) where {T} = TRIMAKernel(T, t.period)
function CausalFrames.fresh!(t::TRIMAKernel)
    t.n = 0
    fresh!(t.s1)
    fresh!(t.s2)
    return t
end

lookback(t::TRIMAKernel) = t.period - 1
nseen(t::TRIMAKernel) = t.n
current(t::TRIMAKernel) = current(t.s2)

function step!(t::TRIMAKernel, x::Real)
    t.n += 1
    return step!(t.s2, step!(t.s1, x))
end

# Hull's moving average (ta_HMA.c): `WMA(2·WMA(x, period ÷ 2) − WMA(x, period),
# isqrt(period))`, both derived periods truncated as hma.md specifies.
mutable struct HMAKernel{T,K}
    const period::Int
    n::Int
    out::Union{Missing,T}
    const half::K
    const full::K
    const root::K
    # An explicit inner constructor: the default one would bind `T` only
    # through `out::Union{Missing,T}`, an unbound parameter when `out` is
    # `missing` (Aqua flags it on Julia 1.10).
    HMAKernel{T,K}(period, n, out, half, full, root) where {T,K} =
        new{T,K}(period, n, out, half, full, root)
end

"""
    HMAKernel(T, period)

Hull's moving average over element type `T`.
"""
function HMAKernel(::Type{T}, period::Integer) where {T}
    p = checkperiod("HMAKernel", period)
    # At period 1 the half period is 0; the kernel copies its input there.
    half = WMAKernel(T, max(p ÷ 2, 1))
    return HMAKernel{T,typeof(half)}(p, 0, missing, half, WMAKernel(T, p),
        WMAKernel(T, isqrt(p)))
end

CausalFrames.fresh(h::HMAKernel{T}) where {T} = HMAKernel(T, h.period)
function CausalFrames.fresh!(h::HMAKernel)
    h.n = 0
    h.out = missing
    fresh!(h.half)
    fresh!(h.full)
    fresh!(h.root)
    return h
end

lookback(h::HMAKernel) = (h.period - 1) + (isqrt(h.period) - 1)
nseen(h::HMAKernel) = h.n
current(h::HMAKernel) = h.out

function step!(h::HMAKernel{T}, x::Real) where {T}
    h.n += 1
    h.period == 1 && return h.out = convert(T, x)
    a = step!(h.half, x)
    b = step!(h.full, x)
    ismissing(b) && return missing
    v = step!(h.root, 2 * (a::T) - b)
    ismissing(v) && return missing
    return h.out = v
end

# The zero-lag EMA (ta_ZLEMA.c): an EMA of `2x − x[lag]` with
# `lag = (period - 1) ÷ 2`. The lagged bar comes from a CausalFrames `First`
# over the last `lag + 1` bars.
mutable struct ZLEMAKernel{T,S,W}
    n::Int
    const lagged::W
    const ema::EMAKernel{T,S}
end

"""
    ZLEMAKernel(T, period)

The zero-lag EMA over element type `T`.
"""
function ZLEMAKernel(::Type{T}, period::Integer) where {T}
    e = EMAKernel(T, period)
    w = CausalFrames.barwindow(First(:x), (e.period - 1) ÷ 2 + 1, (x = T,))
    return ZLEMAKernel{T,typeof(e.seed),typeof(w)}(0, w, e)
end

CausalFrames.fresh(z::ZLEMAKernel{T}) where {T} = ZLEMAKernel(T, z.ema.period)
function CausalFrames.fresh!(z::ZLEMAKernel)
    z.n = 0
    fresh!(z.lagged)
    fresh!(z.ema)
    return z
end

lookback(z::ZLEMAKernel) = (z.ema.period - 1) ÷ 2 + lookback(z.ema)
nseen(z::ZLEMAKernel) = z.n
current(z::ZLEMAKernel) = current(z.ema)

function step!(z::ZLEMAKernel{T}, x::Real) where {T}
    z.n += 1
    v = convert(T, x)
    update!(z.lagged, (x = v,))
    old = value(z.lagged).x_first
    ismissing(old) && return missing
    return step!(z.ema, 2 * v - old)
end
