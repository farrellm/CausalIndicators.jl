# Ehlers' Hilbert-transform core behind TA-Lib's cycle family (HT_*) and MAMA
# (ta_HT_DCPERIOD.c and its siblings, ta_MAMA.c): a 4-bar WMA price smoother,
# the four Hilbert FIRs (detrender, Q1, jI, jQ), the homodyne discriminator's
# period, and the smoothed period. The DC-phase DFT and the instantaneous
# trendline are the two optional parts the HT indicators add on top.
#
# TA-Lib keeps each FIR's taps in odd/even three-slot buffers; tracing its
# `hilbertIdx` shows those are exactly the lags 2, 4 and 6 whatever the start
# parity, so here every lag line is a CausalFrames `WindowValues` under
# `barwindow`, prefilled with TA-Lib's zeros (which also gets past
# `barwindow`'s missing-until-full gate). The arithmetic follows TA-Lib's
# order term by term.
#
# A non-finite input poisons the core for good, as TA-Lib's running WMA sums
# do: every later real output is NaN. The windows are then never read again,
# so WindowValues' NaN counting never misaligns a lag.

const HT_A = 0.0962
const HT_B = 0.5769

# The lag windows: `n` zeros' worth of history, as TA-Lib initializes them.
lagwindow(::Type{T}, n) where {T} =
    prefill!(CausalFrames.barwindow(CausalFrames.WindowValues(:x), n, (x = T,)), n, T)
function prefill!(w, n, ::Type{T}) where {T}
    for _ in 1:n
        update!(w, (x = zero(T),))
    end
    return w
end
refill!(w, n, ::Type{T}) where {T} = prefill!(fresh!(w), n, T)

# The window's values, oldest first in `vals[head:end]`; `lag(v, k)` is the
# value `k` bars back (0 = newest). Prefilled, the window is always full.
@inline windowvals(w) = value(w).x_windowvalues
@inline lag(wv, k) = @inbounds wv.vals[end-k]

# One Hilbert FIR, `(a·x₀ + b·x₂ − b·x₄ − a·x₆)·adj` in TA-Lib's order, over the
# window `wv` with its newest `off` values skipped (jI reads the detrender
# delayed 3 bars).
@inline function htfir(wv, off, adj::T) where {T}
    a, b = T(HT_A), T(HT_B)
    v = -(a * lag(wv, off + 6))
    v += a * lag(wv, off)
    v -= b * lag(wv, off + 4)
    v += b * lag(wv, off + 2)
    return v * adj
end

mutable struct HilbertKernel{T,S,W,D,Q}
    const start::Int      # bars folded before the Hilbert starts (12 or 37)
    const nsmooth::Int    # the smoothed-price window: 7, or 50 for the DFT
    const smoother::S     # WMAKernel(T, 4)
    const smooth::W
    const detrender::D    # 10: the detrender and I1, 3 bars later
    const q1window::Q     # 7
    n::Int
    poisoned::Bool
    period::T
    smoothperiod::T
    previ2::T
    prevq2::T
    re::T
    im::T
    smoothed::T
    i1::T
    q1::T
end

"""
    HilbertKernel(T, start; nsmooth = 7)

The Hilbert-transform core over element type `T`, starting after `start` bars
(12 under a 32-bar lookback, 37 under a 63-bar one). `nsmooth` sizes the
smoothed-price window, 50 when the DC-phase DFT reads it.
"""
function HilbertKernel(::Type{T}, start::Integer; nsmooth::Integer = 7) where {T}
    s = WMAKernel(T, 4)
    w, d, q = lagwindow(T, nsmooth), lagwindow(T, 10), lagwindow(T, 7)
    z = zero(T)
    return HilbertKernel{T,typeof(s),typeof(w),typeof(d),typeof(q)}(Int(start),
        Int(nsmooth), s, w, d, q, 0, false, z, z, z, z, z, z, z, z, z)
end

CausalFrames.fresh(k::HilbertKernel{T}) where {T} =
    HilbertKernel(T, k.start; nsmooth = k.nsmooth)
function CausalFrames.fresh!(k::HilbertKernel{T}) where {T}
    fresh!(k.smoother)
    refill!(k.smooth, k.nsmooth, T)
    refill!(k.detrender, 10, T)
    refill!(k.q1window, 7, T)
    z = zero(T)
    k.n = 0
    k.poisoned = false
    k.period = k.smoothperiod = k.previ2 = k.prevq2 = k.re = k.im = z
    k.smoothed = k.i1 = k.q1 = z
    return k
end

nseen(k::HilbertKernel) = k.n

# TA-Lib's degree constants: rad2Deg = 45/atan(1) (equal, bit for bit, to
# ta_MAMA.c's 180/(4·atan(1))).
@inline rad2deg_ta(::Type{T}) where {T} = T(45) / atan(one(T))

"""
    step!(k::HilbertKernel, x) -> Bool

Fold the bar `x`; `true` once the Hilbert transform has stepped on it, after
which `k.smoothed`, `k.i1`, `k.q1`, `k.period` and `k.smoothperiod` are the
bar's.
"""
@inline function step!(k::HilbertKernel{T}, x::T) where {T}
    k.n += 1
    s = step!(k.smoother, x)
    isfinite(x) || (k.poisoned = true)
    k.n > k.start || return false
    if k.poisoned
        nan = T(NaN)
        k.smoothed = k.i1 = k.q1 = k.period = k.smoothperiod = nan
        return true
    end
    s = s::T
    k.smoothed = s
    adj = T(0.075) * k.period + T(0.54)
    update!(k.smooth, (x = s,))
    detrender = htfir(windowvals(k.smooth), 0, adj)
    update!(k.detrender, (x = detrender,))
    dv = windowvals(k.detrender)
    q1 = htfir(dv, 0, adj)
    update!(k.q1window, (x = q1,))
    ji = htfir(dv, 3, adj)
    jq = htfir(windowvals(k.q1window), 0, adj)
    i1 = lag(dv, 3)
    k.i1, k.q1 = i1, q1
    q2 = T(0.2) * (q1 + ji) + T(0.8) * k.prevq2
    i2 = T(0.2) * (i1 - jq) + T(0.8) * k.previ2
    # The homodyne discriminator: the period for the next bar.
    k.re = T(0.2) * ((i2 * k.previ2) + (q2 * k.prevq2)) + T(0.8) * k.re
    k.im = T(0.2) * ((i2 * k.prevq2) - (q2 * k.previ2)) + T(0.8) * k.im
    k.prevq2, k.previ2 = q2, i2
    prev = k.period
    period = prev
    if k.im != 0 && k.re != 0
        period = T(360) / (atan(k.im / k.re) * rad2deg_ta(T))
    end
    t = T(1.5) * prev
    period > t && (period = t)
    t = T(0.67) * prev
    period < t && (period = t)
    if period < 6
        period = T(6)
    elseif period > 50
        period = T(50)
    end
    k.period = T(0.2) * period + T(0.8) * prev
    k.smoothperiod = T(0.33) * k.period + T(0.67) * k.smoothperiod
    return true
end

# `trunc(smoothPeriod + 0.5)`, the bars the DFT and the trendline average. The
# period is clamped to [6, 50], so this is at most 50; a poisoned (NaN) period
# reads nothing.
@inline dcperiodint(sp) =
    isfinite(sp) ? clamp(unsafe_trunc(Int, sp + oftype(sp, 0.5)), 0, 50) : 0

# The DFT's sine and cosine weights: `sincos(i·2π / k)` for `0 ≤ i < k ≤ 50`,
# with TA-Lib's `(i·constDeg2RadBy360)/k`, computed once.
const HT_DFT_WEIGHTS = let c = atan(1.0) * 8.0, w = zeros(2, 50, 50)
    for k in 1:50, i in 0:(k-1)
        θ = (i * c) / k
        w[1, i+1, k], w[2, i+1, k] = sin(θ), cos(θ)
    end
    w
end
@inline dftweights(::Type{Float64}, i, k) =
    @inbounds (HT_DFT_WEIGHTS[1, i+1, k], HT_DFT_WEIGHTS[2, i+1, k])
@inline function dftweights(::Type{T}, i, k) where {T}
    θ = (i * (atan(one(T)) * 8)) / k
    return (sin(θ), cos(θ))
end

# The dominant-cycle phase (ta_HT_DCPHASE.c), from the core's 50-bar smoothed
# prices, and the sine wave of it (ta_HT_SINE.c). The DFT is a plain sum in
# TA-Lib's order, as CausalFrames' own per-emission scans are.
mutable struct DCPhasePart{T}
    dcphase::T
    prevdcphase::T
    sine::T
    leadsine::T
    prevsine::T
    prevleadsine::T
end

DCPhasePart(::Type{T}) where {T} = (z = zero(T); DCPhasePart{T}(z, z, z, z, z, z))
CausalFrames.fresh(p::DCPhasePart{T}) where {T} = DCPhasePart(T)
function CausalFrames.fresh!(p::DCPhasePart{T}) where {T}
    z = zero(T)
    p.dcphase = p.prevdcphase = p.sine = p.leadsine = p.prevsine = p.prevleadsine = z
    return p
end

@inline function dcphase!(p::DCPhasePart{T}, k::HilbertKernel{T}) where {T}
    r2d = rad2deg_ta(T)
    sp = k.smoothperiod
    p.prevdcphase = p.dcphase
    n = dcperiodint(sp)
    re, im = zero(T), zero(T)
    if n > 0
        wv = windowvals(k.smooth)
        for i in 0:(n-1)
            sw, cw = dftweights(T, i, n)
            v = lag(wv, i)
            re += sw * v
            im += cw * v
        end
    end
    ph = p.dcphase
    a = abs(im)
    if a > 0
        ph = atan(re / im) * r2d
    elseif a <= T(0.01)
        if re < 0
            ph -= 90
        elseif re > 0
            ph += 90
        end
    end
    ph += 90
    # Compensate for the one-bar lag of the WMA smoother.
    ph += T(360) / sp
    im < 0 && (ph += 180)
    ph > 315 && (ph -= 360)
    p.dcphase = ph
    d2r = one(T) / r2d
    p.prevsine, p.prevleadsine = p.sine, p.leadsine
    p.sine = sin(ph * d2r)
    p.leadsine = sin((ph + 45) * d2r)
    return p
end

# The instantaneous trendline (ta_HT_TRENDLINE.c): the mean of the last
# `DCPeriodInt` raw prices, then a 4-3-2-1 WMA of those means. The raw window is
# fed every bar from the first.
mutable struct TrendlinePart{T,W}
    const raw::W
    itrend1::T
    itrend2::T
    itrend3::T
    trendline::T
end

function TrendlinePart(::Type{T}) where {T}
    w = lagwindow(T, 50)
    z = zero(T)
    return TrendlinePart{T,typeof(w)}(w, z, z, z, z)
end
CausalFrames.fresh(p::TrendlinePart{T}) where {T} = TrendlinePart(T)
function CausalFrames.fresh!(p::TrendlinePart{T}) where {T}
    refill!(p.raw, 50, T)
    p.itrend1 = p.itrend2 = p.itrend3 = p.trendline = zero(T)
    return p
end

# Every bar, before the core steps (a poisoned core no longer needs it).
@inline function pushraw!(p::TrendlinePart, k::HilbertKernel, x)
    k.poisoned || !isfinite(x) || update!(p.raw, (x = x,))
    return p
end

@inline function trendline!(p::TrendlinePart{T}, k::HilbertKernel{T}) where {T}
    if k.poisoned
        p.trendline = T(NaN)
        return p
    end
    n = dcperiodint(k.smoothperiod)
    t = zero(T)
    wv = windowvals(p.raw)
    for j in 0:(n-1)
        t += lag(wv, j)
    end
    n > 0 && (t = t / n)
    p.trendline = (4 * t + 3 * p.itrend1 + 2 * p.itrend2 + p.itrend3) / 10
    p.itrend3, p.itrend2, p.itrend1 = p.itrend2, p.itrend1, t
    return p
end

# MESA's adaptive moving average (ta_MAMA.c) over the Hilbert core: the phase
# rate sets alpha in [slowlimit, fastlimit], MAMA is the alpha-EMA of the raw
# price and FAMA the alpha/2-EMA of MAMA. Its lookback is 32 bars; at `copy`
# (TA_MA's period 1) it copies the input instead.
mutable struct MAMAKernel{T,H}
    const core::H
    const fastlimit::T
    const slowlimit::T
    const copy::Bool
    prevphase::T
    mama::T
    fama::T
    out::Union{Missing,T}
end

"""
    MAMAKernel(T, fastlimit, slowlimit; copy = false)

TA-Lib's MAMA and FAMA over element type `T`. `step!` returns MAMA, and
`k.fama` is FAMA. With `copy`, it is `TA_MA`'s period-1 identity.
"""
function MAMAKernel(
    ::Type{T},
    fastlimit::Real,
    slowlimit::Real;
    copy::Bool = false,
) where {T}
    h = HilbertKernel(T, 12)
    z = zero(T)
    return MAMAKernel{T,typeof(h)}(h, T(fastlimit), T(slowlimit), copy, z, z, z, missing)
end

CausalFrames.fresh(k::MAMAKernel{T}) where {T} =
    MAMAKernel(T, k.fastlimit, k.slowlimit; copy = k.copy)
function CausalFrames.fresh!(k::MAMAKernel{T}) where {T}
    fresh!(k.core)
    k.prevphase = k.mama = k.fama = zero(T)
    k.out = missing
    return k
end

lookback(k::MAMAKernel) = k.copy ? 0 : 32
nseen(k::MAMAKernel) = nseen(k.core)
current(k::MAMAKernel) = k.out

@inline function step!(k::MAMAKernel{T}, x::Real) where {T}
    v = convert(T, x)
    if k.copy
        k.core.n += 1
        return k.out = v
    end
    h = k.core
    step!(h, v) || return k.out = missing
    phase = h.i1 != 0 ? atan(h.q1 / h.i1) * rad2deg_ta(T) : zero(T)
    dp = k.prevphase - phase
    k.prevphase = phase
    dp < 1 && (dp = one(T))
    if dp > 1
        alpha = k.fastlimit / dp
        alpha < k.slowlimit && (alpha = k.slowlimit)
    else
        alpha = k.fastlimit
    end
    k.mama = alpha * v + (1 - alpha) * k.mama
    alpha *= T(0.5)
    k.fama = alpha * k.mama + (1 - alpha) * k.fama
    return k.out = k.mama
end
