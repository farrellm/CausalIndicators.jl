# TA-Lib's statistic functions. VAR, AVGDEV (S3), CORREL and PERCENTILE (S4)
# are CausalFrames' `Variance(corrected = false)`, `MeanAbsDev`, `Correlation`
# and `Quantile(; interpolation = :nearestrank)` under a `Bars` window, so they
# are not defined here. StdDev, the LINEARREG family, TSF and PercentRank100 are
# dependents over CausalFrames accumulators; Beta is a plain summarizer, since
# it windows the bar-to-bar returns.

# A formula scaling its argument by `K`, a fieldless singleton so that it can be
# a dependent's formula with the factor as a type parameter.
struct Scaled{K} end
@inline (::Scaled{K})(x) where {K} = x * K

"""
    StdDev(column::ColumnSpec; nbdev = 1) -> Summarizer

TA-Lib's `STDDEV`, `nbdev` times the population standard deviation of `column`
over the window, in `:{column}_stddev`. It is a dependent over CausalFrames'
`Std(column; corrected = false)` (Group tier). TA-Lib's
`STDDEV(period = p, nbdev = k)` is `StdDev(:x; nbdev = k)` under `Bars(p)`.

CausalFrames bakes `corrected` into the state type, not the output name, so
`StdDev` cannot share a call with a corrected `Std` or `Variance` over the same
column; put them in separate calls.

TA-Lib: `ta_codegen/input/stddev/stddev.yaml`, `stddev.md`.
"""
struct StdDev{C,K} <: GroupSummarizer end
StdDev(column::ColumnSpec; nbdev::Real = 1) =
    withterms(StdDev{colname(column),Float64(nbdev)}(), column)

CausalFrames.dependencies(::StdDev{C}) where {C} = (Std(C; corrected = false),)
CausalFrames.emptyvalue(::StdDev{C}) where {C} =
    NamedTuple{(Symbol(C, :_stddev),)}((missing,))
CausalFrames.fresh(::StdDev{C,K}, ::NamedTuple) where {C,K} =
    derivedvalue(Symbol(C, :_stddev), (Symbol(C, :_std),), lifted(Scaled{K}()))

# ---------------------------------------------------------------------------
# Linear regression on the bar position

"""
    LinearRegFit{K,C}

The dependent behind [`LinearReg`](@ref), [`LinearRegSlope`](@ref),
[`LinearRegIntercept`](@ref), [`LinearRegAngle`](@ref) and [`TSF`](@ref): the
least-squares line through the window's values of column `C` against the bar
position, reported as `K`.
"""
struct LinearRegFit{K,C} <: GroupSummarizer end

linearregfit(K, column) = withterms(LinearRegFit{K,colname(column)}(), column)

CausalFrames.dependencies(::LinearRegFit{K,C}) where {K,C} =
    (Count(), Sum(C), AgeWeightedSum(C))
CausalFrames.emptyvalue(::LinearRegFit{K,C}) where {K,C} =
    NamedTuple{(Symbol(C, :_, K),)}((missing,))
CausalFrames.fresh(::LinearRegFit{K,C}, ::NamedTuple) where {K,C} =
    derivedvalue(Symbol(C, :_, K),
        (:count, Symbol(C, :_sum), Symbol(C, :_ageweightedsum)), lifted(regvalue(Val(K))))

# ta_LINEARREG.c's closed forms over the `n` bars of the window, with `x` the
# bar's age (0 for the newest), so `Σx·y` is CausalFrames' `AgeWeightedSum`.
# The divisor `(Σx)² − n·Σx²` is negated, so `m` is the slope per bar forward in
# time, and `b` is the line's value at the oldest bar.
@inline function regline(n, s, a)
    sx = n * (n - 1) / 2
    sxx = n * (n - 1) * (2n - 1) / 6
    m = (n * a - sx * s) / (sx * sx - n * sxx)
    return m, (s - m * sx) / n
end

linearregvalue(n, s, a) = ((m, b) = regline(n, s, a); b + m * (n - 1))
linearregslopevalue(n, s, a) = first(regline(n, s, a))
linearreginterceptvalue(n, s, a) = last(regline(n, s, a))
linearreganglevalue(n, s, a) = atan(first(regline(n, s, a))) * (180 / π)
tsfvalue(n, s, a) = ((m, b) = regline(n, s, a); b + m * n)
regvalue(::Val{:linearreg}) = linearregvalue
regvalue(::Val{:linearregslope}) = linearregslopevalue
regvalue(::Val{:linearregintercept}) = linearreginterceptvalue
regvalue(::Val{:linearregangle}) = linearreganglevalue
regvalue(::Val{:tsf}) = tsfvalue

const LINEARREG_DOC = """
The line is fitted by least squares to the window's values against their bar
positions. It is a dependent over CausalFrames' `Count`, `Sum` and
`AgeWeightedSum` (Group tier), so it shares them with [`WMA`](@ref) and the rest
of the family over the same column. It is window-agnostic: TA-Lib's
`period = p` is `Bars(p)`, and its lookback `p − 1` is the window's
partial-window rule. A window of one bar has no line and gives `NaN`.
"""

"""
    LinearReg(column::ColumnSpec) -> Summarizer

TA-Lib's `LINEARREG`, the least-squares line's value at the newest bar of the
window, in `:{column}_linearreg`.

$LINEARREG_DOC
TA-Lib: `ta_codegen/input/linearreg/linearreg.yaml`, `linearreg.md`.
"""
LinearReg(column::ColumnSpec) = linearregfit(:linearreg, column)

"""
    LinearRegSlope(column::ColumnSpec) -> Summarizer

TA-Lib's `LINEARREG_SLOPE`, the least-squares line's slope per bar over the
window, in `:{column}_linearregslope`.

$LINEARREG_DOC
TA-Lib: `ta_codegen/input/linearreg_slope/linearreg_slope.yaml`,
`linearreg_slope.md`.
"""
LinearRegSlope(column::ColumnSpec) = linearregfit(:linearregslope, column)

"""
    LinearRegIntercept(column::ColumnSpec) -> Summarizer

TA-Lib's `LINEARREG_INTERCEPT`, the least-squares line's value at the oldest
bar of the window, in `:{column}_linearregintercept`.

$LINEARREG_DOC
TA-Lib: `ta_codegen/input/linearreg_intercept/linearreg_intercept.yaml`,
`linearreg_intercept.md`.
"""
LinearRegIntercept(column::ColumnSpec) = linearregfit(:linearregintercept, column)

"""
    LinearRegAngle(column::ColumnSpec) -> Summarizer

TA-Lib's `LINEARREG_ANGLE`, the least-squares line's slope as an angle in
degrees, `atan(slope)·180/π`, in `:{column}_linearregangle`.

$LINEARREG_DOC
TA-Lib: `ta_codegen/input/linearreg_angle/linearreg_angle.yaml`,
`linearreg_angle.md`.
"""
LinearRegAngle(column::ColumnSpec) = linearregfit(:linearregangle, column)

"""
    TSF(column::ColumnSpec) -> Summarizer

TA-Lib's `TSF`, the time series forecast: the least-squares line extended one
bar past the newest bar of the window, in `:{column}_tsf`.

$LINEARREG_DOC
TA-Lib: `ta_codegen/input/tsf/tsf.yaml`, `tsf.md`.
"""
TSF(column::ColumnSpec) = linearregfit(:tsf, column)

# ---------------------------------------------------------------------------
# PercentRank100

"""
    PercentRank100(column::ColumnSpec) -> Summarizer

TA-Lib's `PERCENTRANK`, the percentage of the bars before the newest one whose
value is strictly below it, in `:{column}_percentrank100`. It is
`100 · PercentRank` (Group tier): CausalFrames' `PercentRank` ranks the newest
bar against the window's other bars. TA-Lib counts the `period` bars before
the current one, so the window holds `period + 1`: TA-Lib's `period = p` is
`Bars(p + 1)`, and its lookback `p` is the window's partial-window rule.

A NaN in the window gives `NaN` until it leaves, where TA-Lib's comparisons
silently skip it.

TA-Lib: `ta_codegen/input/percentrank/percentrank.yaml`, `percentrank.md`.
"""
struct PercentRank100{C} <: GroupSummarizer end
PercentRank100(column::ColumnSpec) = withterms(PercentRank100{colname(column)}(), column)

CausalFrames.dependencies(::PercentRank100{C}) where {C} = (PercentRank(C),)
CausalFrames.emptyvalue(::PercentRank100{C}) where {C} =
    NamedTuple{(Symbol(C, :_percentrank100),)}((missing,))
# ta_PERCENTRANK.c divides, then scales: `(count/period)·100`, as PercentRank's
# `count/(n − 1)` times 100.
CausalFrames.fresh(::PercentRank100{C}, ::NamedTuple) where {C} =
    derivedvalue(Symbol(C, :_percentrank100), (Symbol(C, :_percentrank),),
        lifted(Scaled{100.0}()))

# ---------------------------------------------------------------------------
# Beta

# The window moments Beta reads, as one tuple from an internal dependent: the
# population covariance of the returns `:x` and `:y`, the variance of `:x` and
# its mean.
struct BetaMoments <: GroupSummarizer end

CausalFrames.dependencies(::BetaMoments) =
    (Covariance(:x, :y; corrected = false), Variance(:x; corrected = false), Mean(:x))
CausalFrames.emptyvalue(::BetaMoments) = (; betamoments = missing)
CausalFrames.fresh(::BetaMoments, ::NamedTuple) =
    derivedvalue(:betamoments, (:x_y_covariance, :x_variance, :x_mean), tuple)

struct BetaSummarizer{A,B,N} <: Summarizer
    period::Int
end

mutable struct BetaState{A,B,N,W,T} <: SummarizerState
    const window::W
    n::Int
    preva::T
    prevb::T
    out::Union{Missing,T}
end

CausalFrames.emptyvalue(::BetaSummarizer{A,B,N}) where {A,B,N} =
    NamedTuple{(N,)}((missing,))

function CausalFrames.fresh(s::BetaSummarizer{A,B,N}, intypes::NamedTuple) where {A,B,N}
    T = pricetype(intypes, (A, B))
    w = CausalFrames.barwindow(BetaMoments(), s.period, (x = T, y = T))
    return BetaState{A,B,N,typeof(w),T}(w, 0, zero(T), zero(T), missing)
end
CausalFrames.fresh(st::BetaState{A,B,N,W,T}) where {A,B,N,W,T} =
    BetaState{A,B,N,W,T}(fresh(st.window), 0, zero(T), zero(T), missing)
function CausalFrames.fresh!(st::BetaState{A,B,N,W,T}) where {A,B,N,W,T}
    fresh!(st.window)
    st.n = 0
    st.preva = st.prevb = zero(T)
    st.out = missing
    return st
end

# ta_BETA.c's return: 0 over a zero previous price.
@inline barreturn(p, prev) = prev != 0 ? (p - prev) / prev : zero(p / one(prev))

@inline function CausalFrames.update!(st::BetaState{A,B,N,W,T}, row) where {A,B,N,W,T}
    a, b = row[A], row[B]
    st.out = missing
    anymissing(a, b) && return nothing
    pa, pb = convert(T, a), convert(T, b)
    n = st.n += 1
    x, y = barreturn(pa, st.preva), barreturn(pb, st.prevb)
    st.preva, st.prevb = pa, pb
    n == 1 && return nothing
    update!(st.window, (x = x, y = y))
    moments = value(st.window).betamoments
    ismissing(moments) && return nothing
    st.out = betavalue(moments...)
    return nothing
end
@inline CausalFrames.value(st::BetaState{A,B,N,W,T}) where {A,B,N,W,T} =
    NamedTuple{(N,),Tuple{Union{Missing,T}}}((st.out,))

# ta_BETA.c: `cov/var`, or 0 where the variance is not above 1e-14 of the
# returns' second moment.
betavalue(cov, var, mean) = var > 1e-14 * (var + mean * mean) ? cov / var : zero(cov)

"""
    Beta(x::ColumnSpec, y::ColumnSpec; period = 5, name = :beta) -> Summarizer

TA-Lib's `BETA` in `:{x}_{y}_beta`: the least-squares slope of `y`'s bar-to-bar
returns on `x`'s over the last `period` returns, `cov(x, y)/var(x)`. TA-Lib's
`inReal0` is `x` (the market, say) and `inReal1` is `y`. A return over a zero
previous price is 0, and a window whose `x` returns TA-Lib finds to have no
variance gives 0. The lookback is `period`, one bar for the first return.

The window moments are CausalFrames' `Covariance`, `Variance` and `Mean` under
`CausalFrames.barwindow`, so a NaN return leaves the output NaN only until it
leaves the window.

$PLAIN_DOC$SKIP_DOC
TA-Lib: `ta_codegen/input/beta/beta.yaml`, `beta.md`.
"""
function Beta(x::ColumnSpec, y::ColumnSpec; period::Integer = 5, name::Symbol = :beta)
    checkrange("Beta", "period", period, 1, 100_000)
    A, B = colname(x), colname(y)
    return withterms(BetaSummarizer{A,B,Symbol(A, :_, B, :_, name)}(Int(period)), x, y)
end
