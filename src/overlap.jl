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
`:kama`, `:t3`, `:hma`, `:zlema` and `:rma` (`:mama` lands with S6). It always
returns a plain summarizer. The window-agnostic SMA is CausalFrames' `Mean`
under a `Bars` window.

`unstable` is TA-Lib's unstable period for the dispatched function, and it
applies only to the types that have one (`:ema`, `:dema`, `:tema`, `:kama`,
`:t3`, `:zlema`, `:rma`). Period 1 copies the input with lookback 0, as
`TA_MA` does. `:t3` uses `vfactor = 0.7`, as `TA_MA` does.

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
    matype === :mama && throw(ArgumentError("MA matype :mama is not implemented yet"))
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
    matype in MATYPES && matype !== :mama || throw(
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
