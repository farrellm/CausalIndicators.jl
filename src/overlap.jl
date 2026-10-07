# TA-Lib's overlap studies: the structured moving averages and midpoints, which
# are dependents over CausalFrames accumulators, and the recursive moving
# averages, which are plain summarizers over `MAKernel`.

# A dependent's state: fieldless, with the output name `N`, the names `Ds` of
# the dependency values it reads and its formula `F` (a singleton function type)
# as type parameters, so the two-argument `value` infers. The value type comes
# from the dependencies' declared field types, as in CausalFrames' own
# dependents, so a `missing` dependency keeps its `Union{Missing,…}`.
struct DerivedValue{N,Ds,F} <: SummarizerState end

derivedvalue(n::Symbol, ds::Tuple, f) = DerivedValue{n,ds,typeof(f)}()

@inline function CausalFrames.value(::DerivedValue{N,Ds,F},
    vals::NamedTuple) where {N,Ds,F}
    V = Base.promote_op(F.instance, map(d -> fieldtype(typeof(vals), d), Ds)...)
    return NamedTuple{(N,),Tuple{V}}((F.instance(map(d -> vals[d], Ds)...),))
end

CausalFrames.fresh(st::DerivedValue) = st
CausalFrames.fresh!(st::DerivedValue) = st
@inline CausalFrames.update!(::DerivedValue, row) = nothing
@inline CausalFrames.downdate!(::DerivedValue, row) = nothing
CausalFrames.combine!(::DerivedValue, ::DerivedValue, ::DerivedValue) = nothing

# The same for a formula `F` returning one value per output name in `Ns`, as a
# tuple.
struct DerivedValues{Ns,Ds,F} <: SummarizerState end

derivedvalues(ns::Tuple, ds::Tuple, f) = DerivedValues{ns,ds,typeof(f)}()

@inline function CausalFrames.value(::DerivedValues{Ns,Ds,F},
    vals::NamedTuple) where {Ns,Ds,F}
    V = Base.promote_op(F.instance, map(d -> fieldtype(typeof(vals), d), Ds)...)
    return NamedTuple{Ns,V}(F.instance(map(d -> vals[d], Ds)...))
end

CausalFrames.fresh(st::DerivedValues) = st
CausalFrames.fresh!(st::DerivedValues) = st
@inline CausalFrames.update!(::DerivedValues, row) = nothing
@inline CausalFrames.downdate!(::DerivedValues, row) = nothing
CausalFrames.combine!(::DerivedValues, ::DerivedValues, ::DerivedValues) = nothing

# A formula `F` lifted over `missing`: `missing` if any argument is, else
# `F(args...)`. A fieldless singleton, so it can be a dependent's formula.
struct Lifted{F} end
lifted(f) = Lifted{typeof(f)}()
@inline (::Lifted{F})(args...) where {F} =
    any(ismissing, args) ? missing : F.instance(args...)

midvalue(a, b) = (a + b) / 2

# ---------------------------------------------------------------------------
# Structured dependents

"""
    WMA(column::ColumnSpec) -> Summarizer

TA-Lib's `WMA`, the linearly weighted moving average, in `:{column}_wma`. The
newest bar has weight `n` and the oldest weight 1, over the `n` bars of the
window:

    WMA = (n·Σy − Σk·y) / (n(n + 1)/2)

Here `k` is a bar's age (0 for the newest). It is a dependent over
`AgeWeightedSum`, `Sum` and `Count`, so it runs in the Group tier and shares
those sums with every other summarizer in the call. It is window-agnostic.
TA-Lib's `WMA(period = p)` is `WMA(:x)` under
`addrollingcolumns((w = Bars(p),), …)`, and its lookback `p − 1` is the
window's partial-window rule.

TA-Lib: `ta_codegen/input/wma/wma.yaml`, `wma.md`.
"""
struct WMA{C} <: GroupSummarizer end
WMA(column::ColumnSpec) = withterms(WMA{colname(column)}(), column)

CausalFrames.dependencies(::WMA{C}) where {C} = (Count(), Sum(C), AgeWeightedSum(C))
CausalFrames.emptyvalue(::WMA{C}) where {C} = NamedTuple{(Symbol(C, :_wma),)}((missing,))
CausalFrames.fresh(::WMA{C}, ::NamedTuple) where {C} =
    derivedvalue(Symbol(C, :_wma), (:count, Symbol(C, :_sum), Symbol(C, :_ageweightedsum)),
        wmavalue)

wmavalue(n, s, a) = (n * s - a) / (n * (n + 1) / 2)

"""
    VWMA(column::ColumnSpec; volume = :volume) -> Summarizer

TA-Lib's `VWMA`, the volume-weighted moving average, in `:{column}_vwma`. It is
`Σ(column·volume) / Σvolume` over the window, a dependent over `DotProduct`
and `Sum` (Group tier). A window whose volume is all zero gives `NaN`, as
vwma.md specifies. Under `Bars(1)` a zero-volume bar also gives `NaN`, where
TA-Lib's period 1 copies the input. TA-Lib's `VWMA(period = p)` is `VWMA(:x)`
under `Bars(p)`.

TA-Lib: `ta_codegen/input/vwma/vwma.yaml`, `vwma.md`.
"""
struct VWMA{C,V} <: GroupSummarizer end
VWMA(column::ColumnSpec; volume::ColumnSpec = :volume) =
    withterms(VWMA{colname(column),colname(volume)}(), column, volume)

# The dot product under CausalFrames' canonical argument order, so it is shared
# with any `DotProduct` or `Covariance` over the same pair.
canonicaldot(a, b) = isless(b, a) ? (b, a) : (a, b)
dotname(a, b) = Symbol(canonicaldot(a, b)[1], :_, canonicaldot(a, b)[2], :_dotproduct)

CausalFrames.dependencies(::VWMA{C,V}) where {C,V} =
    (DotProduct(canonicaldot(C, V)...), Sum(V))
CausalFrames.emptyvalue(::VWMA{C}) where {C} = NamedTuple{(Symbol(C, :_vwma),)}((missing,))
CausalFrames.fresh(::VWMA{C,V}, ::NamedTuple) where {C,V} =
    derivedvalue(Symbol(C, :_vwma), (dotname(C, V), Symbol(V, :_sum)), /)

"""
    MidPoint(column::ColumnSpec) -> Summarizer

TA-Lib's `MIDPOINT`, `(max + min) / 2` of `column` over the window, in
`:{column}_midpoint`. It is a dependent over `Max` and `Min` (Group tier).
TA-Lib's `MIDPOINT(period = p)` is `MidPoint(:x)` under `Bars(p)`.

TA-Lib: `ta_codegen/input/midpoint/midpoint.yaml`, `midpoint.md`.
"""
struct MidPoint{C} <: GroupSummarizer end
MidPoint(column::ColumnSpec) = withterms(MidPoint{colname(column)}(), column)

CausalFrames.dependencies(::MidPoint{C}) where {C} = (Max(C), Min(C))
CausalFrames.emptyvalue(::MidPoint{C}) where {C} =
    NamedTuple{(Symbol(C, :_midpoint),)}((missing,))
CausalFrames.fresh(::MidPoint{C}, ::NamedTuple) where {C} =
    derivedvalue(Symbol(C, :_midpoint), (Symbol(C, :_max), Symbol(C, :_min)), midvalue)

"""
    MidPrice(; high = :high, low = :low) -> Summarizer

TA-Lib's `MIDPRICE`, `(max(high) + min(low)) / 2` over the window, in
`:midprice`. It is a dependent over `Max` and `Min` (Group tier). TA-Lib's
`MIDPRICE(period = p)` is `MidPrice()` under `Bars(p)`.

TA-Lib: `ta_codegen/input/midprice/midprice.yaml`, `midprice.md`.
"""
struct MidPrice{H,L} <: GroupSummarizer end
MidPrice(; high::ColumnSpec = :high, low::ColumnSpec = :low) =
    withterms(MidPrice{colname(high),colname(low)}(), high, low)

CausalFrames.dependencies(::MidPrice{H,L}) where {H,L} = (Max(H), Min(L))
CausalFrames.emptyvalue(::MidPrice) = (; midprice = missing)
CausalFrames.fresh(::MidPrice{H,L}, ::NamedTuple) where {H,L} =
    derivedvalue(:midprice, (Symbol(H, :_max), Symbol(L, :_min)), midvalue)

# ---------------------------------------------------------------------------
# Recursive moving averages

"""
    MovingAverage{M,C,N}

The plain summarizer behind every recursive moving average: an
[`MAKernel`](@ref) of type `M` over column `C`, emitted as `N`. It is built by
[`MA`](@ref), [`EMA`](@ref), [`DEMA`](@ref), [`TEMA`](@ref), [`TRIMA`](@ref),
[`KAMA`](@ref), [`T3`](@ref), [`HMA`](@ref), [`ZLEMA`](@ref) and
[`RMA`](@ref), not directly.
"""
struct MovingAverage{M,C,N} <: Summarizer
    period::Int
    unstable::Int
    vfactor::Float64
    identity::Bool
end

mutable struct MovingAverageState{C,N,K,T} <: SummarizerState
    const kernel::K
    out::Union{Missing,T}
end

CausalFrames.emptyvalue(::MovingAverage{M,C,N}) where {M,C,N} =
    NamedTuple{(N,)}((missing,))

function CausalFrames.fresh(s::MovingAverage{M,C,N}, intypes::NamedTuple) where {M,C,N}
    T = floattype(intypes[C])
    k = MAKernel(T, M, s.period; s.unstable, s.vfactor, s.identity)
    return MovingAverageState{C,N,typeof(k),T}(k, missing)
end

CausalFrames.fresh(st::MovingAverageState{C,N,K,T}) where {C,N,K,T} =
    MovingAverageState{C,N,K,T}(fresh(st.kernel), missing)
function CausalFrames.fresh!(st::MovingAverageState)
    fresh!(st.kernel)
    st.out = missing
    return st
end

@inline CausalFrames.update!(st::MovingAverageState{C}, row) where {C} =
    (st.out = step!(st.kernel, row[C]); nothing)

@inline CausalFrames.value(st::MovingAverageState{C,N,K,T}) where {C,N,K,T} =
    NamedTuple{(N,),Tuple{Union{Missing,T}}}((st.out,))

function checkrange(fn, kw, x, lo, hi)
    lo <= x <= hi ||
        throw(ArgumentError("$fn $kw must be in [$lo, $hi] (TA-Lib's range), got $x"))
    return x
end

function movingaverage(fn, matype, column, period, unstable, name;
    vfactor = 0.7, identity = false)
    checkrange(fn, "period", period, 1, 100_000)
    checkunstable(unstable)
    matype in UNSTABLE_MATYPES || unstable == 0 ||
        throw(ArgumentError("$fn has no unstable period (matype $(repr(matype)))"))
    C = colname(column)
    s = MovingAverage{matype,C,Symbol(C, :_, name)}(Int(period), Int(unstable),
        Float64(vfactor), identity)
    return withterms(s, column)
end

# The docstring paragraphs shared by the plain indicators of every file.
const PLAIN_DOC = """
It is a plain summarizer (no `combine!`), so it belongs under
`addsummarycolumns`. Under `addrollingcolumns` each window re-folds from a
fresh state, a cold start per window. The output is `missing` for TA-Lib's
lookback (plus `unstable`) bars.
"""

const SKIP_DOC = """
A `missing` input bar leaves the state unchanged and emits `missing`.
"""

const MA_DOC_COMMON = """
It is a plain summarizer (no `combine!`), so it belongs under
`addsummarycolumns`. Under `addrollingcolumns` each window re-folds from a
fresh state, a cold start per window. A `missing` bar leaves the state
unchanged and emits `missing`. The output is `missing` for TA-Lib's lookback
(plus `unstable`) bars. `name` replaces the output suffix:
`name = :x7` gives `:{column}_x7`.
"""

"""
    MA(column::ColumnSpec; period = 30, matype = :sma, unstable = 0, name = :ma)

TA-Lib's `MA`: the `matype` moving average of `column` in `:{column}_ma`.
`matype` is one of `:sma`, `:ema`, `:wma`, `:dema`, `:tema`, `:trima`,
`:kama`, `:mama`, `:t3`, `:hma`, `:zlema` and `:rma`. It always
returns a plain summarizer. The window-agnostic SMA is CausalFrames' `Mean`
under a `Bars` window.

`unstable` is TA-Lib's unstable period for the dispatched function, and it
applies only to the types that have one (`:ema`, `:dema`, `:tema`, `:kama`,
`:mama`, `:t3`, `:zlema`, `:rma`). Period 1 copies the input with lookback 0, as
`TA_MA` does. `:t3` uses `vfactor = 0.7`, as `TA_MA` does. `:mama` ignores the
period and is [`MAMA`](@ref)'s MAMA line at its default limits, lookback 32.

$MA_DOC_COMMON
TA-Lib: `ta_codegen/input/ma/ma.yaml`, `ma.md`.
"""
function MA(column::ColumnSpec; period::Integer = 30, matype::Symbol = :sma,
    unstable::Integer = 0, name::Symbol = :ma)
    matype in MATYPES || throw(
        ArgumentError(
            "MA matype must be one of $(join(map(repr, MATYPES), ", ")), " *
            "got $(repr(matype))",
        ))
    # TA_MA ignores the unstable period of types that have none.
    u = matype in UNSTABLE_MATYPES ? unstable : 0
    checkunstable(unstable)
    return movingaverage("MA", matype, column, period, u, name; identity = true)
end

"""
    EMA(column::ColumnSpec; period = 30, unstable = 0, name = :ema)

TA-Lib's `EMA` in `:{column}_ema`, seeded with the simple average of its first
`period` bars.

$MA_DOC_COMMON
TA-Lib: `ta_codegen/input/ema/ema.yaml`, `ema.md`.
"""
EMA(column::ColumnSpec; period::Integer = 30, unstable::Integer = 0,
    name::Symbol = :ema) = movingaverage("EMA", :ema, column, period, unstable, name)

"""
    RMA(column::ColumnSpec; period = 30, unstable = 0, name = :rma)

TA-Lib's `RMA`, Wilder's smoothing, in `:{column}_rma`. It is seeded with the
average of its first `period` bars and then steps `α = 1/period`.

$MA_DOC_COMMON
TA-Lib: `ta_codegen/input/rma/rma.yaml`, `rma.md`.
"""
RMA(column::ColumnSpec; period::Integer = 30, unstable::Integer = 0,
    name::Symbol = :rma) = movingaverage("RMA", :rma, column, period, unstable, name)

"""
    DEMA(column::ColumnSpec; period = 30, unstable = 0, name = :dema)

TA-Lib's `DEMA`, `2·EMA − EMA(EMA)`, in `:{column}_dema`. `unstable` is EMA's
unstable period, which TA-Lib's DEMA inherits. Each EMA stage passes it before
feeding the next, so it changes the values as well as delaying them.

$MA_DOC_COMMON
TA-Lib: `ta_codegen/input/dema/dema.yaml`, `dema.md`.
"""
DEMA(column::ColumnSpec; period::Integer = 30, unstable::Integer = 0,
    name::Symbol = :dema) = movingaverage("DEMA", :dema, column, period, unstable, name)

"""
    TEMA(column::ColumnSpec; period = 30, unstable = 0, name = :tema)

TA-Lib's `TEMA`, `3·EMA − 3·EMA(EMA) + EMA(EMA(EMA))`, in `:{column}_tema`.
`unstable` is EMA's unstable period, inherited as for [`DEMA`](@ref).

$MA_DOC_COMMON
TA-Lib: `ta_codegen/input/tema/tema.yaml`, `tema.md`.
"""
TEMA(column::ColumnSpec; period::Integer = 30, unstable::Integer = 0,
    name::Symbol = :tema) = movingaverage("TEMA", :tema, column, period, unstable, name)

"""
    TRIMA(column::ColumnSpec; period = 30, name = :trima)

TA-Lib's `TRIMA`, the triangular moving average, in `:{column}_trima`. It is an
SMA of an SMA, built from two CausalFrames `Mean`s under
`CausalFrames.barwindow`.

$MA_DOC_COMMON
TA-Lib: `ta_codegen/input/trima/trima.yaml`, `trima.md`.
"""
TRIMA(column::ColumnSpec; period::Integer = 30, name::Symbol = :trima) =
    movingaverage("TRIMA", :trima, column, period, 0, name)

"""
    KAMA(column::ColumnSpec; period = 30, unstable = 0, name = :kama)

TA-Lib's `KAMA`, Kaufman's adaptive moving average, in `:{column}_kama`. Its
efficiency ratio reads a CausalFrames `Sum` of `|Δx|` and a `First` over
count windows. The lookback is `period` bars.

$MA_DOC_COMMON
TA-Lib: `ta_codegen/input/kama/kama.yaml`, `kama.md`.
"""
KAMA(column::ColumnSpec; period::Integer = 30, unstable::Integer = 0,
    name::Symbol = :kama) = movingaverage("KAMA", :kama, column, period, unstable, name)

"""
    T3(column::ColumnSpec; period = 5, vfactor = 0.7, unstable = 0, name = :t3)

Tillson's T3 in `:{column}_t3`: six chained EMAs combined with coefficients
from the volume factor `vfactor`, which must be in `[0, 1]`. The lookback is
`6(period − 1)`.

$MA_DOC_COMMON
TA-Lib: `ta_codegen/input/t3/t3.yaml`, `t3.md`.
"""
function T3(column::ColumnSpec; period::Integer = 5, vfactor::Real = 0.7,
    unstable::Integer = 0, name::Symbol = :t3)
    checkrange("T3", "vfactor", vfactor, 0, 1)
    return movingaverage("T3", :t3, column, period, unstable, name; vfactor)
end

"""
    HMA(column::ColumnSpec; period = 20, name = :hma)

Hull's moving average,
`WMA(2·WMA(x, period ÷ 2) − WMA(x, period), isqrt(period))`, in
`:{column}_hma`. The WMAs are [`WMA`](@ref)s under `CausalFrames.barwindow`.

$MA_DOC_COMMON
TA-Lib: `ta_codegen/input/hma/hma.yaml`, `hma.md`.
"""
HMA(column::ColumnSpec; period::Integer = 20, name::Symbol = :hma) =
    movingaverage("HMA", :hma, column, period, 0, name)

"""
    ZLEMA(column::ColumnSpec; period = 30, unstable = 0, name = :zlema)

The zero-lag EMA, an EMA of `2x − x[lag]` with `lag = (period − 1) ÷ 2`, in
`:{column}_zlema`. `unstable` is EMA's unstable period, which only delays
ZLEMA's first output.

$MA_DOC_COMMON
TA-Lib: `ta_codegen/input/zlema/zlema.yaml`, `zlema.md`.
"""
ZLEMA(column::ColumnSpec; period::Integer = 30, unstable::Integer = 0,
    name::Symbol = :zlema) = movingaverage("ZLEMA", :zlema, column, period, unstable, name)

# ---------------------------------------------------------------------------
# MAVP

struct MAVPSummarizer{M,C,P,N} <: Summarizer
    minperiod::Int
    maxperiod::Int
    unstable::Int
end

"""
    MAVP(column::ColumnSpec, periods::ColumnSpec; minperiod = 2, maxperiod = 30,
         matype = :sma, unstable = 0, name = :mavp)

TA-Lib's `MAVP`, a moving average whose period varies per bar, in
`:{column}_mavp`. Each bar's period is `periods` truncated to an integer and
clamped to `[minperiod, maxperiod]`. A `NaN` period counts as below the minimum,
as in ta_MAVP.c. A `missing` period emits `missing`.

As in TA-Lib, every period in `minperiod:maxperiod` keeps its own `matype`
average over the whole series. Each one is anchored where ta_MAVP.c anchors
it, `lookback(maxperiod) − lookback(p)` bars in, so the recursive types agree
with TA-Lib too. The cost per bar is O(maxperiod − minperiod). The lookback is
`MA`'s at `maxperiod`.

$MA_DOC_COMMON
TA-Lib: `ta_codegen/input/mavp/mavp.yaml`, `mavp.md`.
"""
function MAVP(column::ColumnSpec, periods::ColumnSpec; minperiod::Integer = 2,
    maxperiod::Integer = 30, matype::Symbol = :sma, unstable::Integer = 0,
    name::Symbol = :mavp)
    checkrange("MAVP", "minperiod", minperiod, 1, 100_000)
    checkrange("MAVP", "maxperiod", maxperiod, 1, 100_000)
    minperiod <= maxperiod || throw(
        ArgumentError("MAVP minperiod ($minperiod) must not exceed maxperiod ($maxperiod)"))
    matype in MATYPES || throw(
        ArgumentError("MAVP matype $(repr(matype)) is not supported"))
    checkunstable(unstable)
    u = matype in UNSTABLE_MATYPES ? Int(unstable) : 0
    C = colname(column)
    s = MAVPSummarizer{matype,C,colname(periods),Symbol(C, :_, name)}(Int(minperiod),
        Int(maxperiod), u)
    return withterms(s, column, periods)
end

mutable struct MAVPState{C,P,N,K,T} <: SummarizerState
    const minperiod::Int
    const kernels::Vector{K}
    const offsets::Vector{Int}
    const lookback::Int
    n::Int
    out::Union{Missing,T}
end

CausalFrames.emptyvalue(::MAVPSummarizer{M,C,P,N}) where {M,C,P,N} =
    NamedTuple{(N,)}((missing,))

function CausalFrames.fresh(s::MAVPSummarizer{M,C,P,N}, intypes::NamedTuple) where {M,C,P,N}
    T = floattype(intypes[C])
    kernels = [MAKernel(T, M, p; s.unstable) for p in s.minperiod:s.maxperiod]
    lb = lookback(last(kernels))
    offsets = [lb - lookback(k) for k in kernels]
    return MAVPState{C,P,N,eltype(kernels),T}(s.minperiod, kernels, offsets, lb, 0,
        missing)
end

CausalFrames.fresh(st::MAVPState{C,P,N,K,T}) where {C,P,N,K,T} =
    MAVPState{C,P,N,K,T}(st.minperiod, map(fresh, st.kernels), copy(st.offsets),
        st.lookback, 0, missing)
function CausalFrames.fresh!(st::MAVPState)
    foreach(fresh!, st.kernels)
    st.n = 0
    st.out = missing
    return st
end

function CausalFrames.update!(st::MAVPState{C,P}, row) where {C,P}
    x = row[C]
    if ismissing(x)
        st.out = missing
        return nothing
    end
    n = st.n += 1
    @inbounds for i in eachindex(st.kernels, st.offsets)
        n > st.offsets[i] && step!(st.kernels[i], x)
    end
    st.out = n > st.lookback ? mavppick(st, row[P]) : missing
    return nothing
end

mavppick(::MAVPState, ::Missing) = missing
function mavppick(st::MAVPState{C,P,N,K,T}, p::Real) where {C,P,N,K,T}
    lo = st.minperiod
    hi = lo + length(st.kernels) - 1
    # ta_MAVP.c: below the minimum (or NaN) takes the minimum, above the
    # maximum the maximum, and the rest truncate.
    q = !(p >= lo) ? lo : p > hi ? hi : trunc(Int, p)
    return current(st.kernels[q-lo+1])::Union{Missing,T}
end

@inline CausalFrames.value(st::MAVPState{C,P,N,K,T}) where {C,P,N,K,T} =
    NamedTuple{(N,),Tuple{Union{Missing,T}}}((st.out,))

# ---------------------------------------------------------------------------
# Bands (S3)

const BAND_SUFFIXES = (:upperband, :middleband, :lowerband)

"""
    Donchian(; high = :high, low = :low) -> Summarizer

TA-Lib's `DONCHIAN`, the Donchian channel, in `:donchian_upperband` (the
window's highest high), `:donchian_middleband` (their midpoint) and
`:donchian_lowerband` (the lowest low). It is a dependent over `Max` and `Min`
(Group tier), so it shares them with [`MidPrice`](@ref). TA-Lib's
`DONCHIAN(period = p)` is `Donchian()` under `Bars(p)`.

TA-Lib: `ta_codegen/input/donchian/donchian.yaml`, `donchian.md`.
"""
struct Donchian{H,L} <: GroupSummarizer end
Donchian(; high::ColumnSpec = :high, low::ColumnSpec = :low) =
    withterms(Donchian{colname(high),colname(low)}(), high, low)

CausalFrames.dependencies(::Donchian{H,L}) where {H,L} = (Max(H), Min(L))
CausalFrames.emptyvalue(::Donchian) =
    NamedTuple{outnames(nothing, :donchian, BAND_SUFFIXES)}((missing, missing, missing))
CausalFrames.fresh(::Donchian{H,L}, ::NamedTuple) where {H,L} =
    derivedvalues(outnames(nothing, :donchian, BAND_SUFFIXES),
        (Symbol(H, :_max), Symbol(L, :_min)), donchianvalues)

donchianvalues(u, l) = (u, (u + l) / 2, l)

# AccBands' hidden row terms: the bar's high and low widened by
# `f = 4(high − low)/(high + low)`, or the bare high and low where TA-Lib finds
# `high + low` zero relative to the prices (ta_ACCBANDS.c).
struct AccBandTerm{K,H,L} <: Function end
@inline function (::AccBandTerm{K,H,L})(r) where {K,H,L}
    h, l = getproperty(r, H), getproperty(r, L)
    s = h + l
    iszeroscaled(s, abs(h) + abs(l)) && return K === :up ? float(h) : float(l)
    f = 4 * (h - l) / s
    return K === :up ? h * (1 + f) : l * (1 - f)
end

"""
    AccBands(; high = :high, low = :low, close = :close) -> Summarizer

TA-Lib's `ACCBANDS`, Headley's acceleration bands, in `:accbands_upperband`,
`:accbands_middleband` and `:accbands_lowerband`. With
`f = 4(high − low)/(high + low)` per bar, they are the means over the window of
`high·(1 + f)`, of the close and of `low·(1 − f)`. A bar whose `high + low`
TA-Lib finds zero contributes its bare high and low. It is a dependent over
CausalFrames' `Mean` of the row terms `:accbands_up` and `:accbands_dn` and of
the close (Group tier). TA-Lib's `ACCBANDS(period = p)` is `AccBands()` under
`Bars(p)`. Two `AccBands` over different columns cannot share a call, since
their terms share the names.

TA-Lib: `ta_codegen/input/accbands/accbands.yaml`, `accbands.md`.
"""
struct AccBands{H,L,C} <: GroupSummarizer end
AccBands(; high::ColumnSpec = :high, low::ColumnSpec = :low, close::ColumnSpec = :close) =
    accbands(colname(high), colname(low), colname(close), high, low, close)
accbands(H, L, C, specs...) =
    withterms(AccBands{H,L,C}(), specs..., :accbands_up => AccBandTerm{:up,H,L}(),
        :accbands_dn => AccBandTerm{:dn,H,L}())

CausalFrames.dependencies(::AccBands{H,L,C}) where {H,L,C} =
    (Mean(:accbands_up), Mean(C), Mean(:accbands_dn))
CausalFrames.emptyvalue(::AccBands) =
    NamedTuple{outnames(nothing, :accbands, BAND_SUFFIXES)}((missing, missing, missing))
CausalFrames.fresh(::AccBands{H,L,C}, ::NamedTuple) where {H,L,C} =
    derivedvalues(outnames(nothing, :accbands, BAND_SUFFIXES),
        (:accbands_up_mean, Symbol(C, :_mean), :accbands_dn_mean), tuple)

# Bollinger's bands around `mid` at `up` and `dn` deviations `sd`, in
# ta_BBANDS.c's arithmetic: one offset when the multipliers are equal, else a
# fused upper band. `missing` propagates element-wise.
struct BandsFormula{U,D} end
@inline (::BandsFormula{U,D})(mid, sd) where {U,D} = bbandsvalues(mid, sd, U, D)
@inline function bbandsvalues(mid, sd, up, dn)
    if up == dn
        off = sd * up
        return (mid + off, mid, mid - off)
    end
    return (bandfma(sd, up, mid), mid, mid - sd * dn)
end
bandfma(sd, k, m) = ismissing(sd) || ismissing(m) ? missing : fma(sd, k, m)

"""
    BollingerBands(column::ColumnSpec; nbdevup = 2, nbdevdn = 2) -> Summarizer
    BollingerBands(column::ColumnSpec; matype, period = 20, nbdevup = 2, nbdevdn = 2,
                   unstable = 0, name = :bbands) -> Summarizer

TA-Lib's `BBANDS`, Bollinger's bands, in `:{column}_bbands_upperband`,
`:{column}_bbands_middleband` and `:{column}_bbands_lowerband`: the middle band
is a moving average of `column`, and the outer ones lie `nbdevup` and `nbdevdn`
population standard deviations of `column` above and below it.

- **Without `matype`** the middle band is the simple average, and the indicator
  is a dependent over CausalFrames' `Mean` and `Std(corrected = false)` (Group
  tier). It is window-agnostic: TA-Lib's `BBANDS(period = p)` with the SMA is
  `BollingerBands(:x)` under `Bars(p)`. It takes no `period`.
- **With `matype`** (any `matype` symbol of [`MA`](@ref))
  it is a plain summarizer over a `period`-bar moving average and a CausalFrames
  `Std(corrected = false)` under `CausalFrames.barwindow`. The lookback is the
  larger of the average's and `period − 1`, and `unstable` is the unstable
  period of `matype`, if it has one. `name` replaces the `bbands` in the output
  names.

CausalFrames bakes `corrected` into the state type, not the output name, so the
structured form cannot share a call with a corrected `Std` or `Variance` over
the same column; put them in separate calls.

TA-Lib: `ta_codegen/input/bbands/bbands.yaml`, `bbands.md`.
"""
function BollingerBands(column::ColumnSpec; nbdevup::Real = 2, nbdevdn::Real = 2,
    matype::Union{Nothing,Symbol} = nothing, period::Union{Nothing,Integer} = nothing,
    unstable::Integer = 0, name::Symbol = :bbands)
    C = colname(column)
    up, dn = Float64(nbdevup), Float64(nbdevdn)
    if matype === nothing
        period === nothing && unstable == 0 && name === :bbands || throw(
            ArgumentError(
                "BollingerBands without matype takes its window from the transform; " *
                "period, unstable and name need a matype"))
        return withterms(BollingerSMA{C,up,dn}(), column)
    end
    p = something(period, 20)
    checkrange("BollingerBands", "period", p, 2, 100_000)
    checkmatype("BollingerBands", "matype", matype)
    checkunstable(unstable)
    s = BollingerSummarizer{matype,C,outnames(C, name, BAND_SUFFIXES)}(Int(p), up, dn,
        Int(unstable))
    return withterms(s, column)
end

struct BollingerSMA{C,U,D} <: GroupSummarizer end

CausalFrames.dependencies(::BollingerSMA{C}) where {C} =
    (Mean(C), Std(C; corrected = false))
CausalFrames.emptyvalue(::BollingerSMA{C}) where {C} =
    NamedTuple{outnames(C, :bbands, BAND_SUFFIXES)}((missing, missing, missing))
CausalFrames.fresh(::BollingerSMA{C,U,D}, ::NamedTuple) where {C,U,D} =
    derivedvalues(outnames(C, :bbands, BAND_SUFFIXES),
        (Symbol(C, :_mean), Symbol(C, :_std)),
        BandsFormula{U,D}())

struct BollingerSummarizer{M,C,Ns} <: Summarizer
    period::Int
    nbdevup::Float64
    nbdevdn::Float64
    unstable::Int
end

mutable struct BollingerState{C,Ns,K,W,T} <: SummarizerState
    const ma::K
    const std::W
    const nbdevup::T
    const nbdevdn::T
    bands::Union{Missing,NTuple{3,T}}
end

CausalFrames.emptyvalue(::BollingerSummarizer{M,C,Ns}) where {M,C,Ns} =
    NamedTuple{Ns}((missing, missing, missing))

function CausalFrames.fresh(
    s::BollingerSummarizer{M,C,Ns},
    intypes::NamedTuple,
) where {M,C,Ns}
    T = floattype(intypes[C])
    k = MAKernel(T, M, s.period; s.unstable)
    w = CausalFrames.barwindow(Std(:x; corrected = false), s.period, (x = T,))
    return BollingerState{C,Ns,typeof(k),typeof(w),T}(k, w, T(s.nbdevup), T(s.nbdevdn),
        missing)
end
CausalFrames.fresh(st::BollingerState{C,Ns,K,W,T}) where {C,Ns,K,W,T} =
    BollingerState{C,Ns,K,W,T}(fresh(st.ma), fresh(st.std), st.nbdevup, st.nbdevdn, missing)
function CausalFrames.fresh!(st::BollingerState)
    fresh!(st.ma)
    fresh!(st.std)
    st.bands = missing
    return st
end

@inline function CausalFrames.update!(
    st::BollingerState{C,Ns,K,W,T},
    row,
) where {C,Ns,K,W,T}
    x = row[C]
    st.bands = missing
    ismissing(x) && return nothing
    v = convert(T, x)
    m = step!(st.ma, v)
    update!(st.std, (x = v,))
    sd = value(st.std).x_std
    (ismissing(m) || ismissing(sd)) && return nothing
    st.bands = bbandsvalues(m::T, sd::T, st.nbdevup, st.nbdevdn)
    return nothing
end
@inline function CausalFrames.value(st::BollingerState{C,Ns,K,W,T}) where {C,Ns,K,W,T}
    b = st.bands
    vals = ismissing(b) ? (missing, missing, missing) : b
    return NamedTuple{Ns,NTuple{3,Union{Missing,T}}}(vals)
end

# ---------------------------------------------------------------------------
# Keltner channels

struct KeltnerSummarizer{H,L,C,Ns} <: Summarizer
    period::Int
    atrperiod::Int
    nbdev::Float64
    unstable::Int
end

mutable struct KeltnerState{H,L,C,Ns,E,A,T} <: SummarizerState
    const ema::E
    const atr::A
    const nbdev::T
    const unstable::Int
    const emaoffset::Int
    const atroffset::Int
    n::Int
    bands::Union{Missing,NTuple{3,T}}
end

CausalFrames.emptyvalue(::KeltnerSummarizer{H,L,C,Ns}) where {H,L,C,Ns} =
    NamedTuple{Ns}((missing, missing, missing))

function CausalFrames.fresh(
    s::KeltnerSummarizer{H,L,C,Ns},
    intypes::NamedTuple,
) where {H,L,C,Ns}
    T = pricetype(intypes, (H, L, C))
    e = EMAKernel(T, s.period)
    a = ATRKernel(T, s.atrperiod)
    # Both legs first emit on the same bar, as ta_KC.c anchors them: the one
    # with the shorter lookback starts that much later.
    le, la = lookback(e) + s.unstable, lookback(a) + s.unstable
    L0 = max(le, la)
    return KeltnerState{H,L,C,Ns,typeof(e),typeof(a),T}(e, a, T(s.nbdev), s.unstable,
        L0 - le, L0 - la, 0, missing)
end
CausalFrames.fresh(st::KeltnerState{H,L,C,Ns,E,A,T}) where {H,L,C,Ns,E,A,T} =
    KeltnerState{H,L,C,Ns,E,A,T}(fresh(st.ema), fresh(st.atr), st.nbdev, st.unstable,
        st.emaoffset, st.atroffset, 0, missing)
function CausalFrames.fresh!(st::KeltnerState)
    fresh!(st.ema)
    fresh!(st.atr)
    st.n = 0
    st.bands = missing
    return st
end

@inline function CausalFrames.update!(st::KeltnerState{H,L,C,Ns,E,A,T},
    row) where {H,L,C,Ns,E,A,T}
    h, l, c = row[H], row[L], row[C]
    st.bands = missing
    anymissing(h, l, c) && return nothing
    h, l, c = convert(T, h), convert(T, l), convert(T, c)
    n = st.n += 1
    n > st.emaoffset && step!(st.ema, (h + l + c) / 3)
    n > st.atroffset && step!(st.atr, h, l, c)
    a = st.atr
    (emitted(st.ema, st.unstable) && nseen(a) > lookback(a) + st.unstable) ||
        return nothing
    mid = st.ema.prev
    w = a.wilder.prev * st.nbdev
    st.bands = (mid + w, mid, mid - w)
    return nothing
end
@inline function CausalFrames.value(st::KeltnerState{H,L,C,Ns,E,A,T}) where {H,L,C,Ns,E,A,T}
    b = st.bands
    vals = ismissing(b) ? (missing, missing, missing) : b
    return NamedTuple{Ns,NTuple{3,Union{Missing,T}}}(vals)
end

"""
    KeltnerChannels(; high = :high, low = :low, close = :close, period = 20,
                    atrperiod = 10, nbdev = 2, unstable = 0, name = :kc)

TA-Lib's `KC`, Keltner's channels, in `:kc_upperband`, `:kc_middleband` and
`:kc_lowerband`: the middle band is the `period`-bar EMA of the typical price
`(high + low + close)/3`, and the outer ones lie `nbdev` times the
`atrperiod`-bar [`ATR`](@ref) above and below it. The two averages are aligned
to emit first on the same bar, as TA-Lib aligns them, so the lookback is the
larger of `period − 1` and `atrperiod`, plus `unstable`, the EMA and ATR
unstable period TA-Lib's KC inherits.

$PLAIN_DOC
A bar with any input `missing` leaves the state unchanged and emits `missing`.

TA-Lib: `ta_codegen/input/kc/kc.yaml`, `kc.md`.
"""
function KeltnerChannels(; high::ColumnSpec = :high, low::ColumnSpec = :low,
    close::ColumnSpec = :close, period::Integer = 20, atrperiod::Integer = 10,
    nbdev::Real = 2, unstable::Integer = 0, name::Symbol = :kc)
    checkrange("KeltnerChannels", "period", period, 2, 100_000)
    checkrange("KeltnerChannels", "atrperiod", atrperiod, 1, 100_000)
    checkunstable(unstable)
    s = KeltnerSummarizer{colname(high),colname(low),colname(close),
        outnames(nothing, name, BAND_SUFFIXES)}(Int(period), Int(atrperiod),
        Float64(nbdev), Int(unstable))
    return withterms(s, high, low, close)
end

# ---------------------------------------------------------------------------
# Parabolic SAR

# `K` is `:sar` (the SAR itself) or `:sarext` (signed: negative while short).
struct SARSummarizer{K,H,L,N} <: Summarizer
    startvalue::Float64
    offset::Float64
    initlong::Float64
    accellong::Float64
    maxlong::Float64
    initshort::Float64
    accelshort::Float64
    maxshort::Float64
end

mutable struct SARState{K,H,L,N,T} <: SummarizerState
    const startvalue::T
    const offset::T
    const initlong::T
    const accellong::T
    const maxlong::T
    const initshort::T
    const accelshort::T
    const maxshort::T
    n::Int
    islong::Bool
    sar::T
    ep::T
    aflong::T
    afshort::T
    newhigh::T
    newlow::T
    out::Union{Missing,T}
end

CausalFrames.emptyvalue(::SARSummarizer{K,H,L,N}) where {K,H,L,N} =
    NamedTuple{(N,)}((missing,))

function CausalFrames.fresh(s::SARSummarizer{K,H,L,N}, intypes::NamedTuple) where {K,H,L,N}
    T = pricetype(intypes, (H, L))
    z = zero(T)
    return SARState{K,H,L,N,T}(s.startvalue, s.offset, s.initlong, s.accellong,
        s.maxlong, s.initshort, s.accelshort, s.maxshort, 0, true, z, z, z, z, z, z,
        missing)
end
CausalFrames.fresh(st::SARState{K,H,L,N,T}) where {K,H,L,N,T} = fresh!(
    SARState{K,H,L,N,T}(st.startvalue, st.offset, st.initlong, st.accellong, st.maxlong,
        st.initshort, st.accelshort, st.maxshort, 0, true, zero(T), zero(T), zero(T),
        zero(T), zero(T), zero(T), missing))
function CausalFrames.fresh!(st::SARState{K,H,L,N,T}) where {K,H,L,N,T}
    st.n = 0
    st.islong = true
    st.sar = st.ep = st.newhigh = st.newlow = zero(T)
    st.aflong = st.initlong
    st.afshort = st.initshort
    st.out = missing
    return st
end

@inline function CausalFrames.update!(st::SARState{K,H,L,N,T}, row) where {K,H,L,N,T}
    h, l = row[H], row[L]
    st.out = missing
    anymissing(h, l) && return nothing
    h, l = convert(T, h), convert(T, l)
    n = st.n += 1
    if n == 1
        st.newhigh, st.newlow = h, l
        return nothing
    end
    n == 2 && sarstart!(st, h, l)
    st.out = sarstep!(st, h, l)
    return nothing
end
@inline CausalFrames.value(st::SARState{K,H,L,N,T}) where {K,H,L,N,T} =
    NamedTuple{(N,),Tuple{Union{Missing,T}}}((st.out,))

# ta_SAREXT.c's start on the second bar: the direction from the first two bars'
# −DM (long unless the down move wins), or from the sign of `startvalue`; the
# SAR at the previous bar's extreme or `|startvalue|`; the extreme point at
# this bar's. Then the "cheat": this bar also stands in for the previous one.
function sarstart!(st::SARState, h, l)
    sv = st.startvalue
    if sv == 0
        diffp = h - st.newhigh
        diffm = st.newlow - l
        mdm = diffm > 0 && diffp < diffm ? diffm : zero(diffm)
        st.islong = !(mdm > 0)
        st.sar = st.islong ? st.newlow : st.newhigh
    else
        st.islong = sv > 0
        st.sar = abs(sv)
    end
    st.ep = st.islong ? h : l
    st.newhigh, st.newlow = h, l
    return nothing
end

# One bar of ta_SAREXT.c's loop: the value emitted is the SAR going into the
# bar, or on a reversal the old extreme point clamped to the two bars' range and
# offset; then the SAR moves `af` of the way to the extreme point, clamped.
function sarstep!(st::SARState{K,H,L,N,T}, h, l) where {K,H,L,N,T}
    prevlow, prevhigh = st.newlow, st.newhigh
    st.newlow, st.newhigh = l, h
    sar = st.sar
    if st.islong
        if l <= sar
            st.islong = false
            sar = max(st.ep, prevhigh, h)
            st.offset != 0 && (sar += sar * st.offset)
            out = -sar
            st.afshort = st.initshort
            st.ep = l
            sar = max(fma(st.afshort, st.ep - sar, sar), prevhigh, h)
        else
            out = sar
            if h > st.ep
                st.ep = h
                st.aflong = min(st.aflong + st.accellong, st.maxlong)
            end
            sar = min(fma(st.aflong, st.ep - sar, sar), prevlow, l)
        end
    else
        if h >= sar
            st.islong = true
            sar = min(st.ep, prevlow, l)
            st.offset != 0 && (sar -= sar * st.offset)
            out = sar
            st.aflong = st.initlong
            st.ep = h
            sar = min(fma(st.aflong, st.ep - sar, sar), prevlow, l)
        else
            out = -sar
            if l < st.ep
                st.ep = l
                st.afshort = min(st.afshort + st.accelshort, st.maxshort)
            end
            sar = max(fma(st.afshort, st.ep - sar, sar), prevhigh, h)
        end
    end
    st.sar = sar
    return K === :sarext ? out : abs(out)
end

function sarsummarizer(K, high, low, name, sv, off, il, al, ml, is, as, ms)
    # ta_SAREXT.c caps the initial and step factors at the maximum.
    il, al = min(il, ml), min(al, ml)
    is, as = min(is, ms), min(as, ms)
    s = SARSummarizer{K,colname(high),colname(low),name}(sv, off, il, al, ml, is, as, ms)
    return withterms(s, high, low)
end

const SAR_DOC = """
It is path-dependent: its value depends on the bar the state starts at, so no
finite `warmup` makes it split-invariant. The lookback is 1.

$PLAIN_DOC
A bar with any input `missing` leaves the state unchanged and emits `missing`.
"""

"""
    SAR(; high = :high, low = :low, acceleration = 0.02, maximum = 0.2, name = :sar)

TA-Lib's `SAR`, Wilder's parabolic stop and reverse, in `:sar`. The trend
starts long unless the first two bars' down move wins. Each bar the SAR moves
`af` of the way to the trend's extreme point, clamped to the last two bars'
range. `af` starts at `acceleration` and grows by it with each new extreme, up
to `maximum`. When a bar's range reaches the SAR it reverses, emitting the old
extreme point as the SAR.

$SAR_DOC
TA-Lib: `ta_codegen/input/sar/sar.yaml`, `sar.md`.
"""
function SAR(; high::ColumnSpec = :high, low::ColumnSpec = :low,
    acceleration::Real = 0.02, maximum::Real = 0.2, name::Symbol = :sar)
    checkrange("SAR", "acceleration", acceleration, 0, Inf)
    checkrange("SAR", "maximum", maximum, 0, Inf)
    a, m = Float64(acceleration), Float64(maximum)
    return sarsummarizer(:sar, high, low, name, 0.0, 0.0, a, a, m, a, a, m)
end

"""
    SARExt(; high = :high, low = :low, startvalue = 0, offsetonreverse = 0,
           accelerationinitlong = 0.02, accelerationlong = 0.02,
           accelerationmaxlong = 0.2, accelerationinitshort = 0.02,
           accelerationshort = 0.02, accelerationmaxshort = 0.2, name = :sarext)

TA-Lib's `SAREXT`, the parabolic SAR with separate long and short acceleration
factors, in `:sarext`, as [`SAR`](@ref) but signed: positive while long and
negative while short. A positive `startvalue` starts long at that SAR and a
negative one starts short at its magnitude; 0 decides as `SAR` does. On a
reversal the emitted SAR moves `offsetonreverse` times itself away from the
price.

$SAR_DOC
TA-Lib: `ta_codegen/input/sarext/sarext.yaml`, `sarext.md`.
"""
function SARExt(; high::ColumnSpec = :high, low::ColumnSpec = :low,
    startvalue::Real = 0, offsetonreverse::Real = 0, accelerationinitlong::Real = 0.02,
    accelerationlong::Real = 0.02, accelerationmaxlong::Real = 0.2,
    accelerationinitshort::Real = 0.02, accelerationshort::Real = 0.02,
    accelerationmaxshort::Real = 0.2, name::Symbol = :sarext)
    for (kw, v) in (("offsetonreverse", offsetonreverse),
        ("accelerationinitlong", accelerationinitlong),
        ("accelerationlong", accelerationlong),
        ("accelerationmaxlong", accelerationmaxlong),
        ("accelerationinitshort", accelerationinitshort),
        ("accelerationshort", accelerationshort),
        ("accelerationmaxshort", accelerationmaxshort))
        checkrange("SARExt", kw, v, 0, Inf)
    end
    return sarsummarizer(:sarext, high, low, name, Float64(startvalue),
        Float64(offsetonreverse), Float64(accelerationinitlong), Float64(accelerationlong),
        Float64(accelerationmaxlong), Float64(accelerationinitshort),
        Float64(accelerationshort), Float64(accelerationmaxshort))
end

# ---------------------------------------------------------------------------
# SuperTrend

struct SuperTrendSummarizer{H,L,C,Ns} <: Summarizer
    period::Int
    multiplier::Float64
    unstable::Int
end

mutable struct SuperTrendState{H,L,C,Ns,A,T} <: SummarizerState
    const atr::A
    const multiplier::T
    const unstable::Int
    started::Bool
    isup::Bool
    upper::T
    lower::T
    prevclose::T
    out::Union{Missing,T}
    trend::Union{Missing,Int}
end

CausalFrames.emptyvalue(::SuperTrendSummarizer{H,L,C,Ns}) where {H,L,C,Ns} =
    NamedTuple{Ns}((missing, missing))

function CausalFrames.fresh(s::SuperTrendSummarizer{H,L,C,Ns},
    intypes::NamedTuple) where {H,L,C,Ns}
    T = pricetype(intypes, (H, L, C))
    a = ATRKernel(T, s.period)
    z = zero(T)
    return SuperTrendState{H,L,C,Ns,typeof(a),T}(a, T(s.multiplier), s.unstable, false,
        true, z, z, z, missing, missing)
end
CausalFrames.fresh(st::SuperTrendState{H,L,C,Ns,A,T}) where {H,L,C,Ns,A,T} =
    SuperTrendState{H,L,C,Ns,A,T}(fresh(st.atr), st.multiplier, st.unstable, false, true,
        zero(T), zero(T), zero(T), missing, missing)
function CausalFrames.fresh!(st::SuperTrendState{H,L,C,Ns,A,T}) where {H,L,C,Ns,A,T}
    fresh!(st.atr)
    st.started = false
    st.isup = true
    st.upper = st.lower = st.prevclose = zero(T)
    st.out = st.trend = missing
    return st
end

# ta_SUPERTREND.c: bands `(h + l)/2 ± multiplier·ATR`. The first bar takes
# both and starts up. After it, each band only tightens unless the previous
# close crossed it; the trend turns down when the close falls below the lower
# band and up when it rises above the upper one; the line is the lower band in
# an uptrend and the upper one in a downtrend.
@inline function CausalFrames.update!(st::SuperTrendState{H,L,C,Ns,A,T},
    row) where {H,L,C,Ns,A,T}
    h, l, c = row[H], row[L], row[C]
    st.out = st.trend = missing
    anymissing(h, l, c) && return nothing
    h, l, c = convert(T, h), convert(T, l), convert(T, c)
    a = st.atr
    step!(a, h, l, c)
    nseen(a) > lookback(a) + st.unstable || return nothing
    med = (h + l) / 2
    band = st.multiplier * a.wilder.prev
    bu, bl = med + band, med - band
    if st.started
        (bu < st.upper || st.prevclose > st.upper) && (st.upper = bu)
        (bl > st.lower || st.prevclose < st.lower) && (st.lower = bl)
        if st.isup
            c < st.lower && (st.isup = false)
        else
            c > st.upper && (st.isup = true)
        end
    else
        st.started = true
        st.isup = true
        st.upper, st.lower = bu, bl
    end
    st.prevclose = c
    st.out = st.isup ? st.lower : st.upper
    st.trend = st.isup ? 1 : -1
    return nothing
end
@inline CausalFrames.value(st::SuperTrendState{H,L,C,Ns,A,T}) where {H,L,C,Ns,A,T} =
    NamedTuple{Ns,Tuple{Union{Missing,T},Union{Missing,Int}}}((st.out, st.trend))

"""
    SuperTrend(; high = :high, low = :low, close = :close, period = 10,
               multiplier = 3.0, unstable = 0, name = :supertrend)

TA-Lib's `SUPERTREND` in `:supertrend_supertrend` and `:supertrend_trend`. The
bands lie `multiplier` times the `period`-bar [`ATR`](@ref) above and below the
bar's median price `(high + low)/2`. Each band only tightens unless the
previous close crossed it. The trend (an `Int`, 1 up or −1 down) starts up and
turns when the close crosses the band on its side, and the line is the lower
band in an uptrend and the upper one in a downtrend. The lookback is `period`,
plus `unstable`, the ATR unstable period TA-Lib's SUPERTREND inherits.

It is path-dependent: its value depends on the bar the state starts at, so no
finite `warmup` makes it split-invariant.

$PLAIN_DOC
A bar with any input `missing` leaves the state unchanged and emits `missing`.

TA-Lib: `ta_codegen/input/supertrend/supertrend.yaml`, `supertrend.md`.
"""
function SuperTrend(; high::ColumnSpec = :high, low::ColumnSpec = :low,
    close::ColumnSpec = :close, period::Integer = 10, multiplier::Real = 3.0,
    unstable::Integer = 0, name::Symbol = :supertrend)
    checkrange("SuperTrend", "period", period, 2, 100_000)
    checkrange("SuperTrend", "multiplier", multiplier, 0, Inf)
    checkunstable(unstable)
    s = SuperTrendSummarizer{colname(high),colname(low),colname(close),
        outnames(nothing, name, (:supertrend, :trend))}(Int(period), Float64(multiplier),
        Int(unstable))
    return withterms(s, high, low, close)
end
