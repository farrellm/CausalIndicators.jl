# S6: TA-Lib's Hilbert-transform cycle family and MAMA, plain `BarIndicator`s
# over the shared `HilbertKernel` (kernels/hilbert.jl).

const HT_DOC = """
$PLAIN_DOC
A `missing` input bar leaves the state unchanged and emits `missing`. A
non-finite input poisons the state for good, as TA-Lib's running sums do: every
later real output is NaN. The state is recursive, so it is anchored at the
first bar seen. `unstable` is TA-Lib's unstable period for the function: it
delays the first output without changing the values.
"""

# F names the function: :dcperiod, :phasor (Hilbert from bar 13, lookback 32),
# :dcphase, :sine, :trendline, :trendmode (from bar 38, lookback 63).
struct HTSpec{F}
    unstable::Int
end

mutable struct HTIndicatorKernel{F,T,H,P,L}
    const core::H
    const phase::P   # DCPhasePart, or nothing
    const trend::L   # TrendlinePart, or nothing
    const unstable::Int
    days::Int        # HT_TRENDMODE's days in trend
end

htlookback(F::Symbol) = F in (:dcperiod, :phasor) ? 32 : 63
htphase(F::Symbol) = F in (:dcphase, :sine, :trendmode)
httrend(F::Symbol) = F in (:trendline, :trendmode)

function barkernel(s::HTSpec{F}, ::Type{T}) where {F,T}
    h = HilbertKernel(T, htlookback(F) == 32 ? 12 : 37; nsmooth = htphase(F) ? 50 : 7)
    p = htphase(F) ? DCPhasePart(T) : nothing
    l = httrend(F) ? TrendlinePart(T) : nothing
    return HTIndicatorKernel{F,T,typeof(h),typeof(p),typeof(l)}(h, p, l, s.unstable, 0)
end
barouttype(::HTSpec{:trendmode}, ::Type{T}) where {T} = Int

partfresh(p) = fresh(p)
partfresh(::Nothing) = nothing
partfresh!(p) = fresh!(p)
partfresh!(::Nothing) = nothing

CausalFrames.fresh(k::HTIndicatorKernel{F,T,H,P,L}) where {F,T,H,P,L} =
    HTIndicatorKernel{F,T,H,P,L}(fresh(k.core), partfresh(k.phase), partfresh(k.trend),
        k.unstable, 0)
function CausalFrames.fresh!(k::HTIndicatorKernel)
    fresh!(k.core)
    partfresh!(k.phase)
    partfresh!(k.trend)
    k.days = 0
    return k
end

@inline function barstep!(k::HTIndicatorKernel{F,T}, x::T) where {F,T}
    k.trend === nothing || pushraw!(k.trend, k.core, x)
    step!(k.core, x) || return nothing
    k.phase === nothing || dcphase!(k.phase, k.core)
    k.trend === nothing || trendline!(k.trend, k.core)
    out = htout(Val(F), k)
    nseen(k.core) > htlookback(F) + k.unstable || return nothing
    return out
end

@inline htout(::Val{:dcperiod}, k) = (k.core.smoothperiod,)
@inline htout(::Val{:phasor}, k) = (k.core.i1, k.core.q1)
@inline htout(::Val{:dcphase}, k) = (k.phase.dcphase,)
@inline htout(::Val{:sine}, k) = (k.phase.sine, k.phase.leadsine)
@inline htout(::Val{:trendline}, k) = (k.trend.trendline,)

# ta_HT_TRENDMODE.c: a trend by default; a cycle from a crossing of the sine
# and lead sine for half a smoothed period, or while the phase advances at the
# cycle's rate; a trend again once the smoothed price strays 1.5% from the
# trendline. It runs every bar, the lookback included, for its days count.
@inline function htout(::Val{:trendmode}, k::HTIndicatorKernel{F,T}) where {F,T}
    p, sp = k.phase, k.core.smoothperiod
    trend = 1
    if (p.sine > p.leadsine && p.prevsine <= p.prevleadsine) ||
       (p.sine < p.leadsine && p.prevsine >= p.prevleadsine)
        k.days = 0
        trend = 0
    end
    k.days += 1
    k.days < T(0.5) * sp && (trend = 0)
    d = p.dcphase - p.prevdcphase
    if sp != 0 && d > T(0.67) * 360 / sp && d < T(1.5) * 360 / sp
        trend = 0
    end
    tl, s = k.trend.trendline, k.core.smoothed
    tl != 0 && abs((s - tl) / tl) >= T(0.015) && (trend = 1)
    return (trend,)
end

"""
    HTDCPeriod(column::ColumnSpec; unstable = 0, name = :htdcperiod)

TA-Lib's `HT_DCPERIOD`, the Hilbert transform's dominant cycle period in bars,
in `:{column}_htdcperiod`: the homodyne discriminator's period, clamped to
[6, 50] bars and smoothed twice. The price is first smoothed by a 4-bar WMA.
The lookback is 32 bars.

$HT_DOC
TA-Lib: `ta_codegen/input/ht_dcperiod/ht_dcperiod.yaml`, `ht_dcperiod.md`.
"""
HTDCPeriod(column::ColumnSpec; unstable::Integer = 0, name::Symbol = :htdcperiod) =
    barindicator(HTSpec{:dcperiod}(checkunstable(unstable)),
        (outname(colname(column), name),), column)

"""
    HTDCPhase(column::ColumnSpec; unstable = 0, name = :htdcphase)

TA-Lib's `HT_DCPHASE`, the dominant cycle phase in degrees, in
`:{column}_htdcphase`, wrapped to at most 315: the phase of a one-cycle DFT of the
smoothed price over the dominant cycle period (see [`HTDCPeriod`](@ref)),
advanced to compensate for the smoother's lag. The lookback is 63 bars.

$HT_DOC
TA-Lib: `ta_codegen/input/ht_dcphase/ht_dcphase.yaml`, `ht_dcphase.md`.
"""
HTDCPhase(column::ColumnSpec; unstable::Integer = 0, name::Symbol = :htdcphase) =
    barindicator(HTSpec{:dcphase}(checkunstable(unstable)),
        (outname(colname(column), name),), column)

"""
    HTPhasor(column::ColumnSpec; unstable = 0, name = :htphasor)

TA-Lib's `HT_PHASOR`, the Hilbert transform's phasor components, in
`:{column}_htphasor_inphase` (the detrended price, 3 bars late) and
`:{column}_htphasor_quadrature`. The lookback is 32 bars.

$HT_DOC
TA-Lib: `ta_codegen/input/ht_phasor/ht_phasor.yaml`, `ht_phasor.md`.
"""
HTPhasor(column::ColumnSpec; unstable::Integer = 0, name::Symbol = :htphasor) =
    barindicator(HTSpec{:phasor}(checkunstable(unstable)),
        outnames(colname(column), name, (:inphase, :quadrature)), column)

"""
    HTSine(column::ColumnSpec; unstable = 0, name = :htsine)

TA-Lib's `HT_SINE`, Ehlers' sine wave indicator, in `:{column}_htsine_sine`
and `:{column}_htsine_leadsine`: the sines of the dominant cycle phase (see
[`HTDCPhase`](@ref)) and of the phase 45° ahead. The lookback is 63 bars.

$HT_DOC
TA-Lib: `ta_codegen/input/ht_sine/ht_sine.yaml`, `ht_sine.md`.
"""
HTSine(column::ColumnSpec; unstable::Integer = 0, name::Symbol = :htsine) =
    barindicator(HTSpec{:sine}(checkunstable(unstable)),
        outnames(colname(column), name, (:sine, :leadsine)), column)

"""
    HTTrendline(column::ColumnSpec; unstable = 0, name = :httrendline)

TA-Lib's `HT_TRENDLINE`, Ehlers' instantaneous trendline, in
`:{column}_httrendline`: the mean of the raw price over the dominant cycle
period (see [`HTDCPeriod`](@ref)), smoothed by a 4-bar WMA of those means. The
lookback is 63 bars.

$HT_DOC
TA-Lib: `ta_codegen/input/ht_trendline/ht_trendline.yaml`, `ht_trendline.md`.
"""
HTTrendline(column::ColumnSpec; unstable::Integer = 0, name::Symbol = :httrendline) =
    barindicator(HTSpec{:trendline}(checkunstable(unstable)),
        (outname(colname(column), name),), column)

"""
    HTTrendMode(column::ColumnSpec; unstable = 0, name = :httrendmode)

TA-Lib's `HT_TRENDMODE`, Ehlers' trend-versus-cycle mode, in
`:{column}_httrendmode` as an `Int`: 1 in a trend, 0 in a cycle. A crossing of
[`HTSine`](@ref)'s two lines starts a cycle for half a dominant cycle period,
a phase advancing at the cycle's rate keeps it, and a smoothed price 1.5% or
more away from [`HTTrendline`](@ref)'s line is a trend. The lookback is 63
bars. After a non-finite input it emits 1, as TA-Lib's comparisons with NaN do.

$HT_DOC
TA-Lib: `ta_codegen/input/ht_trendmode/ht_trendmode.yaml`, `ht_trendmode.md`.
"""
HTTrendMode(column::ColumnSpec; unstable::Integer = 0, name::Symbol = :httrendmode) =
    barindicator(HTSpec{:trendmode}(checkunstable(unstable)),
        (outname(colname(column), name),), column)

struct MAMASpec
    fastlimit::Float64
    slowlimit::Float64
    unstable::Int
end

mutable struct MAMAIndicatorKernel{K}
    const mama::K
    const unstable::Int
end

barkernel(s::MAMASpec, ::Type{T}) where {T} =
    (
        k = MAMAKernel(T, s.fastlimit, s.slowlimit);
        MAMAIndicatorKernel{typeof(k)}(k, s.unstable)
    )
CausalFrames.fresh(k::MAMAIndicatorKernel{K}) where {K} =
    MAMAIndicatorKernel{K}(fresh(k.mama), k.unstable)
CausalFrames.fresh!(k::MAMAIndicatorKernel) = (fresh!(k.mama); k)

@inline function barstep!(k::MAMAIndicatorKernel, x::T) where {T}
    step!(k.mama, x)
    nseen(k.mama) > lookback(k.mama) + k.unstable || return nothing
    return (k.mama.mama, k.mama.fama)
end

"""
    MAMA(column::ColumnSpec; fastlimit = 0.5, slowlimit = 0.05, unstable = 0,
         name = :mama)

TA-Lib's `MAMA`, Ehlers' MESA adaptive moving average, in
`:{column}_mama_mama` and `:{column}_mama_fama`. The Hilbert transform's phase
rate sets the smoothing factor, `fastlimit / Δphase` clamped to
`[slowlimit, fastlimit]`. MAMA is that EMA of `column`, and FAMA, the following
average, is the EMA of MAMA at half the factor. Both limits must be in
[0.01, 0.99]. The lookback is 32 bars. `MA(…; matype = :mama)` is the MAMA
line at the default limits.

$HT_DOC
TA-Lib: `ta_codegen/input/mama/mama.yaml`, `mama.md`.
"""
function MAMA(column::ColumnSpec; fastlimit::Real = 0.5, slowlimit::Real = 0.05,
    unstable::Integer = 0, name::Symbol = :mama)
    checkrange("MAMA", "fastlimit", fastlimit, 0.01, 0.99)
    checkrange("MAMA", "slowlimit", slowlimit, 0.01, 0.99)
    return barindicator(
        MAMASpec(Float64(fastlimit), Float64(slowlimit), checkunstable(unstable)),
        outnames(colname(column), name, (:mama, :fama)), column)
end
