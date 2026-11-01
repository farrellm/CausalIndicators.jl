# TA-Lib's overlap studies: the structured moving averages and midpoints, which
# are dependents over CausalFrames accumulators, and the recursive moving
# averages, which are plain summarizers over `MAKernel`.

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
CausalFrames.emptyvalue(::WMA{C}) where {C} = missings((Symbol(C, :_wma),))
CausalFrames.fresh(::WMA{C}, ::NamedTuple) where {C} =
    derivedvalue(Symbol(C, :_wma), (:count, Symbol(C, :_sum), Symbol(C, :_ageweightedsum)),
        wmavalue)

wmavalue(n, s, a) = (n * s - a) / (n * (n + 1) / 2)

"""
    VWMA(column::ColumnSpec; volume = :volume) -> Summarizer

TA-Lib's `VWMA`, the volume-weighted moving average, in `:{column}_vwma`. It is
`Σ(column·volume) / Σvolume` over the window, a dependent over `Count`,
`DotProduct`, `Sum` and `Last` (Group tier). A window whose volume is all zero
gives `NaN`, as vwma.md specifies. A window holding one row gives that row's
`column`, as TA-Lib's period 1 does (TA-Lib #184): (P·V)/V need not round-trip
to P, and a zero-volume bar would give `NaN`. TA-Lib's `VWMA(period = p)` is
`VWMA(:x)` under `Bars(p)`.

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
    (Count(), DotProduct(canonicaldot(C, V)...), Sum(V), Last(C))
CausalFrames.emptyvalue(::VWMA{C}) where {C} = missings((Symbol(C, :_vwma),))
CausalFrames.fresh(::VWMA{C,V}, ::NamedTuple) where {C,V} =
    derivedvalue(Symbol(C, :_vwma),
        (:count, dotname(C, V), Symbol(V, :_sum), lastname(C)), vwmavalue)

vwmavalue(n, pv, v, p) = n == 1 ? float(p) : pv / v

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
    missings((Symbol(C, :_midpoint),))
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

# Every recursive moving average is a `BarIndicator` over an `MAKernel` of type
# `M`, built by `MA`, `EMA`, `DEMA`, `TEMA`, `TRIMA`, `KAMA`, `T3`, `HMA`,
# `ZLEMA` and `RMA`.
struct MASpec{M}
    period::Int
    unstable::Unstable
    vfactor::Float64
    identity::Bool
end

barkernel(s::MASpec{M}, ::Type{T}) where {M,T} =
    MAKernel(T, M, s.period; s.unstable, s.vfactor, s.identity)

@inline function barstep!(k::MAKernel, x)
    v = step!(k, x)
    return ismissing(v) ? nothing : (v,)
end

function movingaverage(fn, matype, column, period, unstable, name;
    vfactor = 0.7, identity = false)
    checkrange(fn, "period", period, 1, 100_000)
    unstable = checkunstable(unstable)
    matype in UNSTABLE_MATYPES || unstable == 0 ||
        throw(ArgumentError("$fn has no unstable period (matype $(repr(matype)))"))
    s = MASpec{matype}(period, unstable, vfactor, identity)
    return barindicator(s, (outname(colname(column), name),), column)
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
`:kama`, `:mama`, `:t3`, `:hma`, `:zlema` and `:rma`. It always
returns a plain summarizer. The window-agnostic SMA is CausalFrames' `Mean`
under a `Bars` window.

`unstable` is TA-Lib's unstable period for the dispatched function, and it
applies only to the types that have one (`:ema`, `:dema`, `:tema`, `:kama`,
`:mama`, `:t3`, `:zlema`, `:rma`). Period 1 copies the input with lookback 0, as
`TA_MA` does. `:t3` uses `vfactor = 0.7`, as `TA_MA` does. `:mama` ignores the
period and is [`MAMA`](@ref)'s MAMA line at its default limits, lookback 32.

$MA_DOC_COMMON
$AUTO_DOC
TA-Lib: `ta_codegen/input/ma/ma.yaml`, `ma.md`.
"""
function MA(column::ColumnSpec; period::Integer = 30, matype::Symbol = :sma,
    unstable::UnstableArg = 0, name::Symbol = :ma)
    checkmatype("MA", "matype", matype)
    unstable = checkunstable(unstable)
    # TA_MA ignores the unstable period of types that have none.
    u = matype in UNSTABLE_MATYPES ? unstable : 0
    return movingaverage("MA", matype, column, period, u, name; identity = true)
end

"""
    EMA(column::ColumnSpec; period = 30, unstable = 0, name = :ema)

TA-Lib's `EMA` in `:{column}_ema`, seeded with the simple average of its first
`period` bars.

$MA_DOC_COMMON
$AUTO_DOC
TA-Lib: `ta_codegen/input/ema/ema.yaml`, `ema.md`.
"""
EMA(column::ColumnSpec; period::Integer = 30, unstable::UnstableArg = 0,
    name::Symbol = :ema) = movingaverage("EMA", :ema, column, period, unstable, name)

"""
    RMA(column::ColumnSpec; period = 30, unstable = 0, name = :rma)

TA-Lib's `RMA`, Wilder's smoothing, in `:{column}_rma`. It is seeded with the
average of its first `period` bars and then steps `α = 1/period`.

$MA_DOC_COMMON
$AUTO_DOC
TA-Lib: `ta_codegen/input/rma/rma.yaml`, `rma.md`.
"""
RMA(column::ColumnSpec; period::Integer = 30, unstable::UnstableArg = 0,
    name::Symbol = :rma) = movingaverage("RMA", :rma, column, period, unstable, name)

"""
    DEMA(column::ColumnSpec; period = 30, unstable = 0, name = :dema)

TA-Lib's `DEMA`, `2·EMA − EMA(EMA)`, in `:{column}_dema`. `unstable` is EMA's
unstable period, which TA-Lib's DEMA inherits. Each EMA stage passes it before
feeding the next, so it changes the values as well as delaying them.

$MA_DOC_COMMON
$AUTO_DOC
TA-Lib: `ta_codegen/input/dema/dema.yaml`, `dema.md`.
"""
DEMA(column::ColumnSpec; period::Integer = 30, unstable::UnstableArg = 0,
    name::Symbol = :dema) = movingaverage("DEMA", :dema, column, period, unstable, name)

"""
    TEMA(column::ColumnSpec; period = 30, unstable = 0, name = :tema)

TA-Lib's `TEMA`, `3·EMA − 3·EMA(EMA) + EMA(EMA(EMA))`, in `:{column}_tema`.
`unstable` is EMA's unstable period, inherited as for [`DEMA`](@ref).

$MA_DOC_COMMON
$AUTO_DOC
TA-Lib: `ta_codegen/input/tema/tema.yaml`, `tema.md`.
"""
TEMA(column::ColumnSpec; period::Integer = 30, unstable::UnstableArg = 0,
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
$AUTO_DOC
Under a level KAMA is sized for a market that trends or wanders; a
range-bound one slows it by design and can need several times the count.

TA-Lib: `ta_codegen/input/kama/kama.yaml`, `kama.md`.
"""
KAMA(column::ColumnSpec; period::Integer = 30, unstable::UnstableArg = 0,
    name::Symbol = :kama) = movingaverage("KAMA", :kama, column, period, unstable, name)

"""
    T3(column::ColumnSpec; period = 5, vfactor = 0.7, unstable = 0, name = :t3)

Tillson's T3 in `:{column}_t3`: six chained EMAs combined with coefficients
from the volume factor `vfactor`, which must be in `[0, 1]`. The lookback is
`6(period − 1)`.

$MA_DOC_COMMON
$AUTO_DOC
Under a level T3 can need a fifth more than its count; a count of
`20·period` covers it.

TA-Lib: `ta_codegen/input/t3/t3.yaml`, `t3.md`.
"""
function T3(column::ColumnSpec; period::Integer = 5, vfactor::Real = 0.7,
    unstable::UnstableArg = 0, name::Symbol = :t3)
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
$AUTO_DOC
TA-Lib: `ta_codegen/input/zlema/zlema.yaml`, `zlema.md`.
"""
ZLEMA(column::ColumnSpec; period::Integer = 30, unstable::UnstableArg = 0,
    name::Symbol = :zlema) = movingaverage("ZLEMA", :zlema, column, period, unstable, name)

# ---------------------------------------------------------------------------
# MAVP

struct MAVPSummarizer{M,C,P,N} <: Summarizer
    minperiod::Int
    maxperiod::Int
    unstable::Unstable
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
$AUTO_DOC
TA-Lib: `ta_codegen/input/mavp/mavp.yaml`, `mavp.md`.
"""
function MAVP(column::ColumnSpec, periods::ColumnSpec; minperiod::Integer = 2,
    maxperiod::Integer = 30, matype::Symbol = :sma, unstable::UnstableArg = 0,
    name::Symbol = :mavp)
    checkrange("MAVP", "minperiod", minperiod, 1, 10_000)
    checkrange("MAVP", "maxperiod", maxperiod, 1, 10_000)
    minperiod <= maxperiod || throw(
        ArgumentError("MAVP minperiod ($minperiod) must not exceed maxperiod ($maxperiod)"))
    checkmatype("MAVP", "matype", matype)
    unstable = checkunstable(unstable)
    u = matype in UNSTABLE_MATYPES ? unstable : 0
    C = colname(column)
    s = MAVPSummarizer{matype,C,colname(periods),outname(C, name)}(minperiod, maxperiod, u)
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

CausalFrames.emptyvalue(::MAVPSummarizer{M,C,P,N}) where {M,C,P,N} = missings((N,))

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
    missings(outnames(nothing, :donchian, BAND_SUFFIXES))
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
    missings(outnames(nothing, :accbands, BAND_SUFFIXES))
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

$DAILY_DOC
$AUTO_DOC
TA-Lib: `ta_codegen/input/bbands/bbands.yaml`, `bbands.md`.
"""
function BollingerBands(column::ColumnSpec; nbdevup::Real = 2, nbdevdn::Real = 2,
    matype::Union{Nothing,Symbol} = nothing, period::Union{Nothing,Integer} = nothing,
    unstable::UnstableArg = 0, name::Symbol = :bbands)
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
    unstable = checkunstable(unstable)
    return barindicator(BollingerSpec{matype}(p, up, dn, unstable),
        outnames(C, name, BAND_SUFFIXES), column)
end

struct BollingerSMA{C,U,D} <: GroupSummarizer end

CausalFrames.dependencies(::BollingerSMA{C}) where {C} =
    (Mean(C), Std(C; corrected = false))
CausalFrames.emptyvalue(::BollingerSMA{C}) where {C} =
    missings(outnames(C, :bbands, BAND_SUFFIXES))
CausalFrames.fresh(::BollingerSMA{C,U,D}, ::NamedTuple) where {C,U,D} =
    derivedvalues(outnames(C, :bbands, BAND_SUFFIXES),
        (Symbol(C, :_mean), Symbol(C, :_std)),
        BandsFormula{U,D}())

struct BollingerSpec{M}
    period::Int
    nbdevup::Float64
    nbdevdn::Float64
    unstable::Unstable
end

mutable struct BollingerKernel{K,W,T}
    const ma::K
    const std::W
    const nbdevup::T
    const nbdevdn::T
end

function barkernel(s::BollingerSpec{M}, ::Type{T}) where {M,T}
    k = MAKernel(T, M, s.period; s.unstable)
    w = CausalFrames.barwindow(Std(:x; corrected = false), s.period, (x = T,))
    return BollingerKernel(k, w, T(s.nbdevup), T(s.nbdevdn))
end
CausalFrames.fresh!(k::BollingerKernel) = (fresh!(k.ma); fresh!(k.std); k)

@inline function barstep!(k::BollingerKernel{K,W,T}, x::T) where {K,W,T}
    m = step!(k.ma, x)
    update!(k.std, (x = x,))
    sd = value(k.std).x_std
    (ismissing(m) || ismissing(sd)) && return nothing
    return bbandsvalues(m::T, sd::T, k.nbdevup, k.nbdevdn)
end

# ---------------------------------------------------------------------------
# Keltner channels

struct KeltnerSpec
    period::Int
    atrperiod::Int
    nbdev::Float64
    unstable::Unstable
end

mutable struct KeltnerKernel{E,A,T}
    const ema::E
    const atr::A
    const nbdev::T
    const emaunstable::Int
    const atrunstable::Int
    const emaoffset::Int
    const atroffset::Int
    n::Int
end

function barkernel(s::KeltnerSpec, ::Type{T}) where {T}
    e = EMAKernel(T, s.period)
    a = ATRKernel(T, s.atrperiod)
    # Under a level each leg drops its own id's count at its own period.
    ue = unstablecount(s.unstable, autoema, s.period)
    ua = unstablecount(s.unstable, autowilder, s.atrperiod)
    # Both legs first emit on the same bar, as ta_KC.c anchors them: the one
    # with the shorter lookback starts that much later.
    le, la = lookback(e) + ue, lookback(a) + ua
    L0 = max(le, la)
    return KeltnerKernel(e, a, T(s.nbdev), ue, ua, L0 - le, L0 - la, 0)
end
function CausalFrames.fresh!(k::KeltnerKernel)
    fresh!(k.ema)
    fresh!(k.atr)
    k.n = 0
    return k
end

@inline function barstep!(k::KeltnerKernel{E,A,T}, h::T, l::T, c::T) where {E,A,T}
    n = k.n += 1
    n > k.emaoffset && step!(k.ema, (h + l + c) / 3)
    n > k.atroffset && step!(k.atr, h, l, c)
    a = k.atr
    (emitted(k.ema, k.emaunstable) && nseen(a) > lookback(a) + k.atrunstable) ||
        return nothing
    mid = k.ema.prev
    w = a.wilder.prev * k.nbdev
    return (mid + w, mid, mid - w)
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
unstable period TA-Lib's KC inherits. Under a level each leg adds its own
count, EMA's at `period` and ATR's at `atrperiod`, and the larger lookback
wins.

$PRICEBAR_DOC
$DAILY_DOC
$AUTO_DOC
TA-Lib: `ta_codegen/input/kc/kc.yaml`, `kc.md`.
"""
function KeltnerChannels(; high::ColumnSpec = :high, low::ColumnSpec = :low,
    close::ColumnSpec = :close, period::Integer = 20, atrperiod::Integer = 10,
    nbdev::Real = 2, unstable::UnstableArg = 0, name::Symbol = :kc)
    checkrange("KeltnerChannels", "period", period, 2, 100_000)
    checkrange("KeltnerChannels", "atrperiod", atrperiod, 1, 100_000)
    unstable = checkunstable(unstable)
    return barindicator(KeltnerSpec(period, atrperiod, nbdev, unstable),
        outnames(nothing, name, BAND_SUFFIXES), high, low, close)
end

# ---------------------------------------------------------------------------
# Parabolic SAR

# `K` is `:sar` (the SAR itself) or `:sarext` (signed: negative while short).
struct SARSpec{K}
    startvalue::Float64
    offset::Float64
    initlong::Float64
    accellong::Float64
    maxlong::Float64
    initshort::Float64
    accelshort::Float64
    maxshort::Float64
end

mutable struct SARKernel{K,T}
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
end

function barkernel(s::SARSpec{K}, ::Type{T}) where {K,T}
    z = zero(T)
    return fresh!(
        SARKernel{K,T}(s.startvalue, s.offset, s.initlong, s.accellong,
            s.maxlong, s.initshort, s.accelshort, s.maxshort, 0, true, z, z, z, z, z, z),
    )
end
function CausalFrames.fresh!(k::SARKernel{K,T}) where {K,T}
    k.n = 0
    k.islong = true
    k.sar = k.ep = k.newhigh = k.newlow = zero(T)
    k.aflong = k.initlong
    k.afshort = k.initshort
    return k
end

@inline function barstep!(k::SARKernel{K,T}, h::T, l::T) where {K,T}
    n = k.n += 1
    if n == 1
        k.newhigh, k.newlow = h, l
        return nothing
    end
    n == 2 && sarstart!(k, h, l)
    return (sarstep!(k, h, l),)
end

# ta_SAREXT.c's start on the second bar: the direction from the first two bars'
# −DM (long unless the down move wins), or from the sign of `startvalue`; the
# SAR at the previous bar's extreme or `|startvalue|`; the extreme point at
# this bar's. Then the "cheat": this bar also stands in for the previous one.
function sarstart!(st::SARKernel, h, l)
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
function sarstep!(st::SARKernel{K}, h, l) where {K}
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
    return barindicator(SARSpec{K}(sv, off, il, al, ml, is, as, ms), (name,), high, low)
end

const SAR_DOC = """
It is path-dependent: its value depends on the bar the state starts at, so no
finite `warmup` makes it split-invariant. The lookback is 1.

$PRICEBAR_DOC"""

"""
    SAR(; high = :high, low = :low, acceleration = 0.02, maximum = 0.2, name = :sar)

TA-Lib's `SAR`, Wilder's parabolic stop and reverse, in `:sar`. The trend
starts long unless the first two bars' down move wins. Each bar the SAR moves
`af` of the way to the trend's extreme point, clamped to the last two bars'
range. `af` starts at `acceleration` and grows by it with each new extreme, up
to `maximum`. When a bar's range reaches the SAR it reverses, emitting the old
extreme point as the SAR.

$SAR_DOC

$DAILY_DOC
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

$DAILY_DOC
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

struct SuperTrendSpec
    period::Int
    multiplier::Float64
    unstable::Unstable
end

barouttypes(::SuperTrendSpec, ::Type{T}, n) where {T} = Tuple{T,Int}

mutable struct SuperTrendKernel{A,T}
    const atr::A
    const multiplier::T
    const unstable::Int
    started::Bool
    isup::Bool
    upper::T
    lower::T
    prevclose::T
end

function barkernel(s::SuperTrendSpec, ::Type{T}) where {T}
    z = zero(T)
    u = unstablecount(s.unstable, autowilder, s.period)
    return SuperTrendKernel(ATRKernel(T, s.period), T(s.multiplier), u, false,
        true, z, z, z)
end
function CausalFrames.fresh!(k::SuperTrendKernel{A,T}) where {A,T}
    fresh!(k.atr)
    k.started = false
    k.isup = true
    k.upper = k.lower = k.prevclose = zero(T)
    return k
end

# ta_SUPERTREND.c: bands `(h + l)/2 ± multiplier·ATR`. The first bar takes
# both and starts up. After it, each band only tightens unless the previous
# close crossed it; the trend turns down when the close falls below the lower
# band and up when it rises above the upper one; the line is the lower band in
# an uptrend and the upper one in a downtrend.
@inline function barstep!(k::SuperTrendKernel{A,T}, h::T, l::T, c::T) where {A,T}
    a = k.atr
    step!(a, h, l, c)
    nseen(a) > lookback(a) + k.unstable || return nothing
    med = (h + l) / 2
    band = k.multiplier * a.wilder.prev
    bu, bl = med + band, med - band
    if k.started
        (bu < k.upper || k.prevclose > k.upper) && (k.upper = bu)
        (bl > k.lower || k.prevclose < k.lower) && (k.lower = bl)
        if k.isup
            c < k.lower && (k.isup = false)
        else
            c > k.upper && (k.isup = true)
        end
    else
        k.started = true
        k.isup = true
        k.upper, k.lower = bu, bl
    end
    k.prevclose = c
    return k.isup ? (k.lower, 1) : (k.upper, -1)
end

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

$PRICEBAR_DOC
$DAILY_DOC
$AUTO_DOC
It is path-dependent, so a level only lengthens the lookback of its ATR
and promises nothing about the line.

TA-Lib: `ta_codegen/input/supertrend/supertrend.yaml`, `supertrend.md`.
"""
function SuperTrend(; high::ColumnSpec = :high, low::ColumnSpec = :low,
    close::ColumnSpec = :close, period::Integer = 10, multiplier::Real = 3.0,
    unstable::UnstableArg = 0, name::Symbol = :supertrend)
    checkrange("SuperTrend", "period", period, 2, 100_000)
    checkrange("SuperTrend", "multiplier", multiplier, 0, Inf)
    unstable = checkunstable(unstable)
    return barindicator(SuperTrendSpec(period, multiplier, unstable),
        outnames(nothing, name, (:supertrend, :trend)), high, low, close)
end
