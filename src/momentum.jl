# TA-Lib's momentum indicators (S2). The window-agnostic ones are dependents
# over CausalFrames accumulators: the previous-bar changes over `First` and
# `Last`, WillR over the window's extremes, Aroon over their positions, CCI over
# the typical price's mean and mean absolute deviation, and the bar-local BOP.
# The rest are plain summarizers over the recursive kernels.

# ---------------------------------------------------------------------------
# Structured dependents

"""
    PriceChange{K,C}

The dependent behind [`MOM`](@ref), [`ROC`](@ref), [`ROCP`](@ref),
[`ROCR`](@ref) and [`ROCR100`](@ref): the change `K` from the window's first
value of column `C` to its last.
"""
struct PriceChange{K,C} <: GroupSummarizer end

pricechange(K, column) = withterms(PriceChange{K,colname(column)}(), column)

CausalFrames.dependencies(::PriceChange{K,C}) where {K,C} = (First(C), Last(C))
CausalFrames.emptyvalue(::PriceChange{K,C}) where {K,C} =
    NamedTuple{(Symbol(C, :_, K),)}((missing,))
CausalFrames.fresh(::PriceChange{K,C}, ::NamedTuple) where {K,C} =
    derivedvalue(Symbol(C, :_, K), (Symbol(C, :_first), Symbol(C, :_last)),
        lifted(changevalue(Val(K))))

# ta_MOM.c and the ROC family; a zero first value gives 0 (TA-Lib's guard).
momvalue(f, l) = l - f
rocvalue(f, l) = f != 0 ? (l / f - 1) * 100 : zero(l / f)
rocpvalue(f, l) = f != 0 ? (l - f) / f : zero(l / f)
rocrvalue(f, l) = f != 0 ? l / f : zero(l / f)
rocr100value(f, l) = f != 0 ? (l / f) * 100 : zero(l / f)
changevalue(::Val{:mom}) = momvalue
changevalue(::Val{:roc}) = rocvalue
changevalue(::Val{:rocp}) = rocpvalue
changevalue(::Val{:rocr}) = rocrvalue
changevalue(::Val{:rocr100}) = rocr100value

const CHANGE_DOC = """
It is a dependent over `First` and `Last` (Group tier), so it is
window-agnostic. TA-Lib compares the current bar with the bar `period` back, so
the window includes both: TA-Lib's `period = p` is `Bars(p + 1)`, and its
lookback `p` is the window's partial-window rule.
"""

"""
    MOM(column::ColumnSpec) -> Summarizer

TA-Lib's `MOM`, `last − first` over the window, in `:{column}_mom`.

$CHANGE_DOC
TA-Lib: `ta_codegen/input/mom/mom.yaml`, `mom.md`.
"""
MOM(column::ColumnSpec) = pricechange(:mom, column)

"""
    ROC(column::ColumnSpec) -> Summarizer

TA-Lib's `ROC`, `(last/first − 1)·100` over the window, in `:{column}_roc`. A
zero first value gives 0, as in TA-Lib.

$CHANGE_DOC
TA-Lib: `ta_codegen/input/roc/roc.yaml`, `roc.md`.
"""
ROC(column::ColumnSpec) = pricechange(:roc, column)

"""
    ROCP(column::ColumnSpec) -> Summarizer

TA-Lib's `ROCP`, `(last − first)/first` over the window, in `:{column}_rocp`.
A zero first value gives 0, as in TA-Lib.

$CHANGE_DOC
TA-Lib: `ta_codegen/input/rocp/rocp.yaml`, `rocp.md`.
"""
ROCP(column::ColumnSpec) = pricechange(:rocp, column)

"""
    ROCR(column::ColumnSpec) -> Summarizer

TA-Lib's `ROCR`, `last/first` over the window, in `:{column}_rocr`. A zero
first value gives 0, as in TA-Lib.

$CHANGE_DOC
TA-Lib: `ta_codegen/input/rocr/rocr.yaml`, `rocr.md`.
"""
ROCR(column::ColumnSpec) = pricechange(:rocr, column)

"""
    ROCR100(column::ColumnSpec) -> Summarizer

TA-Lib's `ROCR100`, `(last/first)·100` over the window, in
`:{column}_rocr100`. A zero first value gives 0, as in TA-Lib.

$CHANGE_DOC
TA-Lib: `ta_codegen/input/rocr100/rocr100.yaml`, `rocr100.md`.
"""
ROCR100(column::ColumnSpec) = pricechange(:rocr100, column)

"""
    WillR(; high = :high, low = :low, close = :close) -> Summarizer

TA-Lib's `WILLR`, Williams' %R, `(h − c)/(h − l)·−100` in `:willr`, where `h`
and `l` are the window's highest high and lowest low and `c` the last close. It
is clamped to `[−100, 0]`, and a range TA-Lib finds zero gives 0. It is a
dependent over `Max`, `Min` and `Last` (Group tier). TA-Lib's
`WILLR(period = p)` is `WillR()` under `Bars(p)`.

TA-Lib: `ta_codegen/input/willr/willr.yaml`, `willr.md`.
"""
struct WillR{H,L,C} <: GroupSummarizer end
WillR(; high::ColumnSpec = :high, low::ColumnSpec = :low, close::ColumnSpec = :close) =
    withterms(WillR{colname(high),colname(low),colname(close)}(), high, low, close)

CausalFrames.dependencies(::WillR{H,L,C}) where {H,L,C} = (Max(H), Min(L), Last(C))
CausalFrames.emptyvalue(::WillR) = (; willr = missing)
CausalFrames.fresh(::WillR{H,L,C}, ::NamedTuple) where {H,L,C} =
    derivedvalue(:willr, (Symbol(H, :_max), Symbol(L, :_min), Symbol(C, :_last)),
        lifted(willrvalue))

function willrvalue(h, l, c)
    iszeroscaled(h - l, abs(h) + abs(l)) && return zero((h - c) / (h - l))
    v = ((h - c) / (h - l)) * -100
    return v > 0 ? zero(v) : v < -100 ? oftype(v, -100) : v
end

"""
    BOP(; open = :open, high = :high, low = :low, close = :close) -> Summarizer

TA-Lib's `BOP`, the balance of power `(close − open)/(high − low)`, in `:bop`.
A bar with no range gives 0. It is a dependent over `Last`, and it is
bar-local under any window, with lookback 0.

TA-Lib: `ta_codegen/input/bop/bop.yaml`, `bop.md`.
"""
struct BOP{O,H,L,C} <: GroupSummarizer end
BOP(; open::ColumnSpec = :open, high::ColumnSpec = :high, low::ColumnSpec = :low,
    close::ColumnSpec = :close) =
    withterms(BOP{colname(open),colname(high),colname(low),colname(close)}(), open,
        high, low, close)

CausalFrames.dependencies(::BOP{O,H,L,C}) where {O,H,L,C} =
    (Last(O), Last(H), Last(L), Last(C))
CausalFrames.emptyvalue(::BOP) = (; bop = missing)
CausalFrames.fresh(::BOP{O,H,L,C}, ::NamedTuple) where {O,H,L,C} =
    derivedvalue(:bop, map(lastname, (O, H, L, C)), lifted(bopvalue))

function bopvalue(o, h, l, c)
    r = h - l
    return r <= 0 ? zero((c - o) / r) : (c - o) / r
end

const AROON_DOC = """
It is a dependent over CausalFrames' `MaxIndex`, `MinIndex` and `Count` (Group
tier). TA-Lib's period counts the bars *before* the current one, so its window
holds `period + 1` bars: TA-Lib's `period = p` is `Bars(p + 1)`. The period is
read from the window's row count, so a time window works too. As in TA-Lib,
the newest of tied extremes counts.
"""

"""
    Aroon(; high = :high, low = :low) -> Summarizer

TA-Lib's `AROON` in `:aroon_aroondown` and `:aroon_aroonup`: with `p` one
less than the window's row count, `100·(p − d)/p`, where `d` is the bars since
the window's lowest low (down) or highest high (up).

$AROON_DOC
TA-Lib: `ta_codegen/input/aroon/aroon.yaml`, `aroon.md`.
"""
struct Aroon{H,L} <: GroupSummarizer end
Aroon(; high::ColumnSpec = :high, low::ColumnSpec = :low) =
    withterms(Aroon{colname(high),colname(low)}(), high, low)

CausalFrames.dependencies(::Aroon{H,L}) where {H,L} = (Count(), MaxIndex(H), MinIndex(L))
CausalFrames.emptyvalue(::Aroon) = (; aroon_aroondown = missing, aroon_aroonup = missing)
CausalFrames.fresh(::Aroon{H,L}, ::NamedTuple) where {H,L} =
    derivedvalues((:aroon_aroondown, :aroon_aroonup),
        (:count, Symbol(H, :_maxindex), Symbol(L, :_minindex)), aroonvalues)

# aroon.c: factor·(period − since), with factor = 100/period.
function aroonvalues(n, hsince, lsince)
    p = n - 1
    f = 100.0 / p
    return (f * (p - lsince), f * (p - hsince))
end

"""
    AroonOsc(; high = :high, low = :low) -> Summarizer

TA-Lib's `AROONOSC`, Aroon up minus Aroon down, in `:aroonosc`: with `p` one
less than the window's row count, `100·(dₗ − dₕ)/p`, where `dₗ` and `dₕ` are the
bars since the window's lowest low and highest high.

$AROON_DOC
TA-Lib: `ta_codegen/input/aroonosc/aroonosc.yaml`, `aroonosc.md`.
"""
struct AroonOsc{H,L} <: GroupSummarizer end
AroonOsc(; high::ColumnSpec = :high, low::ColumnSpec = :low) =
    withterms(AroonOsc{colname(high),colname(low)}(), high, low)

CausalFrames.dependencies(::AroonOsc{H,L}) where {H,L} =
    (Count(), MaxIndex(H), MinIndex(L))
CausalFrames.emptyvalue(::AroonOsc) = (; aroonosc = missing)
CausalFrames.fresh(::AroonOsc{H,L}, ::NamedTuple) where {H,L} =
    derivedvalue(:aroonosc, (:count, Symbol(H, :_maxindex), Symbol(L, :_minindex)),
        lifted(aroonoscvalue))

# aroonosc.c: factor·(highestIdx − lowestIdx), the bars since each swapped.
aroonoscvalue(n, hsince, lsince) = (100.0 / (n - 1)) * (lsince - hsince)

# The typical price `(high + low + close) / 3`, CCI's hidden row term.
struct TypicalPrice{H,L,C} <: Function end
@inline (::TypicalPrice{H,L,C})(r) where {H,L,C} =
    (getproperty(r, H) + getproperty(r, L) + getproperty(r, C)) / 3

"""
    CCI(; high = :high, low = :low, close = :close) -> Summarizer

TA-Lib's `CCI`, the commodity channel index, in `:cci`. It is
`(tp − mean)/(0.015·mad)`, where `tp` is the bar's typical price
`(high + low + close)/3`, and `mean` and `mad` are the typical price's mean and
mean absolute deviation over the window. Where TA-Lib finds the numerator or
the deviation zero relative to the mean, it gives 0. It is a dependent over
CausalFrames' `Mean`, `MeanAbsDev` and `Last` of the row term `:cci_tp` (Group
tier). TA-Lib's `CCI(period = p)` is `CCI()` under `Bars(p)`. Two `CCI`s over
different columns cannot share a call, since their terms share the name.

TA-Lib: `ta_codegen/input/cci/cci.yaml`, `cci.md`.
"""
struct CCI{H,L,C} <: GroupSummarizer end
CCI(; high::ColumnSpec = :high, low::ColumnSpec = :low, close::ColumnSpec = :close) =
    cci(colname(high), colname(low), colname(close), high, low, close)
cci(H, L, C, specs...) =
    withterms(CCI{H,L,C}(), specs..., :cci_tp => TypicalPrice{H,L,C}())

CausalFrames.dependencies(::CCI) = (Mean(:cci_tp), MeanAbsDev(:cci_tp), Last(:cci_tp))
CausalFrames.emptyvalue(::CCI) = (; cci = missing)
CausalFrames.fresh(::CCI, ::NamedTuple) =
    derivedvalue(:cci, (:cci_tp_last, :cci_tp_mean, :cci_tp_meanabsdev), lifted(ccivalue))

function ccivalue(tp, mean, mad)
    d = tp - mean
    scale = abs(mean)
    ok = !iszeroscaled(d, scale) && !iszeroscaled(mad, scale) && 0.015 * mad != 0
    return ok ? d / (0.015 * mad) : zero(d / mad)
end

# ---------------------------------------------------------------------------
# Plain summarizers: shared pieces

# An internal dependent emitting the sums of two columns as one tuple, for a
# `barwindow` that needs both: MFI's money flows and ULTOSC's pressure and range.
struct SumPair{A,B} <: GroupSummarizer end

CausalFrames.dependencies(::SumPair{A,B}) where {A,B} = (Sum(A), Sum(B))
CausalFrames.emptyvalue(::SumPair) = (; sumpair = missing)
CausalFrames.fresh(::SumPair{A,B}, ::NamedTuple) where {A,B} =
    derivedvalue(:sumpair, (Symbol(A, :_sum), Symbol(B, :_sum)), tuple)

sumpairwindow(A, B, n, ::Type{T}) where {T} =
    CausalFrames.barwindow(SumPair{A,B}(), n, NamedTuple{(A, B)}((T, T)))

function checkmatype(fn, kw, matype)
    matype in MATYPES && matype !== :mama || throw(
        ArgumentError(
            "$fn $kw must be one of $(join(map(repr, filter(!=(:mama), MATYPES)), ", ")), " *
            "got $(repr(matype))",
        ))
    return matype
end

# The output names of a plain indicator: a single-series one prefixes its
# input column, a price-bar one (`C === nothing`) does not, and a multi-output
# one appends each output's suffix.
outname(C::Symbol, name) = Symbol(C, :_, name)
outname(::Nothing, name) = name
outnames(C, name, suffixes) = map(s -> Symbol(outname(C, name), :_, s), suffixes)

# Missing-checked reads of a row's inputs.
@inline anymissing(xs...) = any(ismissing, xs)

# ---------------------------------------------------------------------------
# RSI and CMO

struct GainLossOscillator{K,C,N} <: Summarizer
    period::Int
    unstable::Int
end

mutable struct GainLossState{K,C,N,G,T} <: SummarizerState
    const kernel::G
    const unstable::Int
    out::Union{Missing,T}
end

CausalFrames.emptyvalue(::GainLossOscillator{K,C,N}) where {K,C,N} =
    NamedTuple{(N,)}((missing,))

function CausalFrames.fresh(s::GainLossOscillator{K,C,N}, intypes::NamedTuple) where {K,C,N}
    T = floattype(intypes[C])
    k = GainLossKernel(T, s.period)
    return GainLossState{K,C,N,typeof(k),T}(k, s.unstable, missing)
end
CausalFrames.fresh(st::GainLossState{K,C,N,G,T}) where {K,C,N,G,T} =
    GainLossState{K,C,N,G,T}(fresh(st.kernel), st.unstable, missing)
function CausalFrames.fresh!(st::GainLossState)
    fresh!(st.kernel)
    st.out = missing
    return st
end

@inline function CausalFrames.update!(st::GainLossState{K,C}, row) where {K,C}
    x = row[C]
    if ismissing(x)
        st.out = missing
        return nothing
    end
    gl = step!(st.kernel, x)
    k = st.kernel
    st.out = nseen(k) > lookback(k) + st.unstable ? gainlossvalue(Val(K), gl) : missing
    return nothing
end
@inline CausalFrames.value(st::GainLossState{K,C,N,G,T}) where {K,C,N,G,T} =
    NamedTuple{(N,),Tuple{Union{Missing,T}}}((st.out,))

# ta_RSI.c and ta_CMO.c: 0 where the smoothed moves sum to zero.
function gainlossvalue(::Val{:rsi}, (g, l))
    s = g + l
    return s > 0 ? 100 * (g / s) : zero(s)
end
function gainlossvalue(::Val{:cmo}, (g, l))
    s = g + l
    return s > 0 ? 100 * ((g - l) / s) : zero(s)
end

function gainlossoscillator(fn, K, column, period, unstable, name)
    checkrange(fn, "period", period, 2, 100_000)
    checkunstable(unstable)
    C = colname(column)
    s = GainLossOscillator{K,C,outname(C, name)}(Int(period), Int(unstable))
    return withterms(s, column)
end

"""
    RSI(column::ColumnSpec; period = 14, unstable = 0, name = :rsi)

TA-Lib's `RSI`, Wilder's relative strength index, in `:{column}_rsi`: with `g`
and `l` the Wilder-smoothed gains and losses, `100·g/(g + l)`, or 0 where both
are zero. The averages are seeded with the mean of the first `period` moves.
The lookback is `period`, and `unstable` is TA-Lib's unstable period.

$PLAIN_DOC$SKIP_DOC
TA-Lib: `ta_codegen/input/rsi/rsi.yaml`, `rsi.md`.
"""
RSI(column::ColumnSpec; period::Integer = 14, unstable::Integer = 0, name::Symbol = :rsi) =
    gainlossoscillator("RSI", :rsi, column, period, unstable, name)

"""
    CMO(column::ColumnSpec; period = 14, unstable = 0, name = :cmo)

TA-Lib's `CMO`, Chande's momentum oscillator, in `:{column}_cmo`:
`100·(g − l)/(g + l)` over Wilder-smoothed gains and losses, as for
[`RSI`](@ref). The lookback is `period`, and `unstable` is TA-Lib's unstable
period.

$PLAIN_DOC$SKIP_DOC
TA-Lib: `ta_codegen/input/cmo/cmo.yaml`, `cmo.md`.
"""
CMO(column::ColumnSpec; period::Integer = 14, unstable::Integer = 0, name::Symbol = :cmo) =
    gainlossoscillator("CMO", :cmo, column, period, unstable, name)

# ---------------------------------------------------------------------------
# The MACD family

const MACD_SUFFIXES = (:macd, :macdsignal, :macdhist)

# `K` is `:macd`, `:macdfix` or `:macdext`, which sets how the kernels are
# built; `FM`, `SM` and `GM` are the fast, slow and signal MA types.
struct MACDSummarizer{K,FM,SM,GM,C,Ns} <: Summarizer
    fastperiod::Int
    slowperiod::Int
    signalperiod::Int
    unstable::Int
end

mutable struct MACDState{C,Ns,F,S,G,T} <: SummarizerState
    const fast::F
    const slow::S
    const signal::G
    const fastoffset::Int
    const slowoffset::Int
    n::Int
    macd::Union{Missing,T}
    signalout::Union{Missing,T}
end

CausalFrames.emptyvalue(::MACDSummarizer{K,FM,SM,GM,C,Ns}) where {K,FM,SM,GM,C,Ns} =
    NamedTuple{Ns}((missing, missing, missing))

macdkernels(::Val{:macd}, s, T) =
    (MAKernel(T, :ema, s.fastperiod; s.unstable, identity = false),
        MAKernel(T, :ema, s.slowperiod; s.unstable, identity = false),
        MAKernel(T, :ema, s.signalperiod; s.unstable, identity = false))
macdkernels(::Val{:macdfix}, s, T) =
    (fixedemakernel(T, 12, 0.15; s.unstable), fixedemakernel(T, 26, 0.075; s.unstable),
        MAKernel(T, :ema, s.signalperiod; s.unstable, identity = false))
macdkernels(::Val{:macdext}, s::MACDSummarizer{K,FM,SM,GM}, T) where {K,FM,SM,GM} =
    (MAKernel(T, FM, s.fastperiod; s.unstable), MAKernel(T, SM, s.slowperiod; s.unstable),
        MAKernel(T, GM, s.signalperiod; s.unstable))

function CausalFrames.fresh(s::MACDSummarizer{K,FM,SM,GM,C,Ns},
    intypes::NamedTuple) where {K,FM,SM,GM,C,Ns}
    T = floattype(intypes[C])
    f, sl, g = macdkernels(Val(K), s, T)
    # Both averages first emit on the same bar, as macd.c and macdext.c align
    # them: the one with the shorter lookback starts that much later.
    L = max(lookback(f), lookback(sl))
    return MACDState{C,Ns,typeof(f),typeof(sl),typeof(g),T}(f, sl, g, L - lookback(f),
        L - lookback(sl), 0, missing, missing)
end
CausalFrames.fresh(st::MACDState{C,Ns,F,S,G,T}) where {C,Ns,F,S,G,T} =
    MACDState{C,Ns,F,S,G,T}(fresh(st.fast), fresh(st.slow), fresh(st.signal),
        st.fastoffset, st.slowoffset, 0, missing, missing)
function CausalFrames.fresh!(st::MACDState)
    fresh!(st.fast)
    fresh!(st.slow)
    fresh!(st.signal)
    st.n = 0
    st.macd = missing
    st.signalout = missing
    return st
end

@inline function CausalFrames.update!(st::MACDState{C,Ns,F,S,G,T}, row) where {C,Ns,F,S,G,T}
    x = row[C]
    st.macd = st.signalout = missing
    ismissing(x) && return nothing
    n = st.n += 1
    vf = n > st.fastoffset ? step!(st.fast, x) : missing
    vs = n > st.slowoffset ? step!(st.slow, x) : missing
    (ismissing(vf) || ismissing(vs)) && return nothing
    m = vf - vs
    sig = step!(st.signal, m)
    ismissing(sig) && return nothing
    st.macd = m
    st.signalout = sig
    return nothing
end

@inline function CausalFrames.value(st::MACDState{C,Ns,F,S,G,T}) where {C,Ns,F,S,G,T}
    m, s = st.macd, st.signalout
    h = ismissing(m) || ismissing(s) ? missing : m - s
    return NamedTuple{Ns,NTuple{3,Union{Missing,T}}}((m, s, h))
end

function macdsummarizer(K, fm, sm, gm, column, fast, slow, signal, unstable, name)
    C = colname(column)
    # TA-Lib swaps the periods (and their types) when slow < fast.
    if slow < fast
        fast, slow = slow, fast
        fm, sm = sm, fm
    end
    s = MACDSummarizer{K,fm,sm,gm,C,outnames(C, name, MACD_SUFFIXES)}(Int(fast),
        Int(slow), Int(signal), Int(checkunstable(unstable)))
    return withterms(s, column)
end

const MACD_DOC = """
The three outputs start together, on the first bar the signal line has a
value. The fast and slow averages are aligned to emit first on the same bar, as
TA-Lib aligns them, and the signal averages the MACD line from its first value.
`name` replaces the middle of the output names: `name = :m5` gives
`:{column}_m5_macd`, and so on.
"""

"""
    MACD(column::ColumnSpec; fastperiod = 12, slowperiod = 26, signalperiod = 9,
         unstable = 0, name = :macd)

TA-Lib's `MACD` in `:{column}_macd_macd`, `:{column}_macd_macdsignal` and
`:{column}_macd_macdhist`. The MACD line is the fast EMA minus the slow one,
the signal is an EMA of it, and the histogram is their difference. TA-Lib
swaps the periods if `slowperiod < fastperiod`. `unstable` is EMA's unstable
period, which TA-Lib's MACD inherits. Each EMA stage passes it before feeding
the next, so it changes the values as well as delaying them.

$MACD_DOC
$PLAIN_DOC$SKIP_DOC
TA-Lib: `ta_codegen/input/macd/macd.yaml`, `macd.md`.
"""
function MACD(column::ColumnSpec; fastperiod::Integer = 12, slowperiod::Integer = 26,
    signalperiod::Integer = 9, unstable::Integer = 0, name::Symbol = :macd)
    checkrange("MACD", "fastperiod", fastperiod, 2, 100_000)
    checkrange("MACD", "slowperiod", slowperiod, 2, 100_000)
    checkrange("MACD", "signalperiod", signalperiod, 1, 100_000)
    return macdsummarizer(:macd, :ema, :ema, :ema, column, fastperiod, slowperiod,
        signalperiod, unstable, name)
end

"""
    MACDFix(column::ColumnSpec; signalperiod = 9, unstable = 0, name = :macdfix)

TA-Lib's `MACDFIX` in `:{column}_macdfix_macd`, `:{column}_macdfix_macdsignal`
and `:{column}_macdfix_macdhist`: [`MACD`](@ref) at 12 and 26 bars, with
TA-Lib's fixed smoothing factors 0.15 and 0.075 in place of `2/(p + 1)`.

$MACD_DOC
$PLAIN_DOC$SKIP_DOC
TA-Lib: `ta_codegen/input/macdfix/macdfix.yaml`, `macdfix.md`.
"""
function MACDFix(column::ColumnSpec; signalperiod::Integer = 9, unstable::Integer = 0,
    name::Symbol = :macdfix)
    checkrange("MACDFix", "signalperiod", signalperiod, 1, 100_000)
    return macdsummarizer(:macdfix, :ema, :ema, :ema, column, 12, 26, signalperiod,
        unstable, name)
end

"""
    MACDExt(column::ColumnSpec; fastperiod = 12, fastmatype = :sma, slowperiod = 26,
            slowmatype = :sma, signalperiod = 9, signalmatype = :sma, unstable = 0,
            name = :macdext)

TA-Lib's `MACDEXT`, [`MACD`](@ref) with any moving-average types, in
`:{column}_macdext_macd`, `:{column}_macdext_macdsignal` and
`:{column}_macdext_macdhist`. The types are `matype` symbols as for
[`MA`](@ref) (`:mama` lands with S6), and each average follows `MA`'s rules,
period-1 copy included. `unstable` applies to every average whose type has an
unstable period.

$MACD_DOC
$PLAIN_DOC$SKIP_DOC
TA-Lib: `ta_codegen/input/macdext/macdext.yaml`, `macdext.md`.
"""
function MACDExt(column::ColumnSpec; fastperiod::Integer = 12, fastmatype::Symbol = :sma,
    slowperiod::Integer = 26, slowmatype::Symbol = :sma, signalperiod::Integer = 9,
    signalmatype::Symbol = :sma, unstable::Integer = 0, name::Symbol = :macdext)
    checkrange("MACDExt", "fastperiod", fastperiod, 2, 100_000)
    checkrange("MACDExt", "slowperiod", slowperiod, 2, 100_000)
    checkrange("MACDExt", "signalperiod", signalperiod, 1, 100_000)
    checkmatype("MACDExt", "fastmatype", fastmatype)
    checkmatype("MACDExt", "slowmatype", slowmatype)
    checkmatype("MACDExt", "signalmatype", signalmatype)
    return macdsummarizer(:macdext, fastmatype, slowmatype, signalmatype, column,
        fastperiod, slowperiod, signalperiod, unstable, name)
end

# ---------------------------------------------------------------------------
# APO and PPO

struct PriceOscillator{K,M,C,N} <: Summarizer
    fastperiod::Int
    slowperiod::Int
    unstable::Int
end

mutable struct PriceOscillatorState{K,C,N,F,S,T} <: SummarizerState
    const fast::F
    const slow::S
    out::Union{Missing,T}
end

CausalFrames.emptyvalue(::PriceOscillator{K,M,C,N}) where {K,M,C,N} =
    NamedTuple{(N,)}((missing,))

function CausalFrames.fresh(
    s::PriceOscillator{K,M,C,N},
    intypes::NamedTuple,
) where {K,M,C,N}
    T = floattype(intypes[C])
    f = MAKernel(T, M, s.fastperiod; s.unstable)
    sl = MAKernel(T, M, s.slowperiod; s.unstable)
    return PriceOscillatorState{K,C,N,typeof(f),typeof(sl),T}(f, sl, missing)
end
CausalFrames.fresh(st::PriceOscillatorState{K,C,N,F,S,T}) where {K,C,N,F,S,T} =
    PriceOscillatorState{K,C,N,F,S,T}(fresh(st.fast), fresh(st.slow), missing)
function CausalFrames.fresh!(st::PriceOscillatorState)
    fresh!(st.fast)
    fresh!(st.slow)
    st.out = missing
    return st
end

# Both averages start at the first bar, as ta_APO.c's two TA_MA calls do over a
# whole series; the output starts with the slow one.
@inline function CausalFrames.update!(st::PriceOscillatorState{K,C}, row) where {K,C}
    x = row[C]
    if ismissing(x)
        st.out = missing
        return nothing
    end
    vf = step!(st.fast, x)
    vs = step!(st.slow, x)
    st.out = ismissing(vf) || ismissing(vs) ? missing : oscillatorvalue(Val(K), vf, vs)
    return nothing
end
@inline CausalFrames.value(st::PriceOscillatorState{K,C,N,F,S,T}) where {K,C,N,F,S,T} =
    NamedTuple{(N,),Tuple{Union{Missing,T}}}((st.out,))

oscillatorvalue(::Val{:apo}, f, s) = f - s
oscillatorvalue(::Val{:ppo}, f, s) = iszerota(s) ? zero(s) : ((f - s) / s) * 100

# `prefix = false` gives the bare output name of a price-bar indicator (PVO).
function priceoscillator(fn, K, column, fast, slow, matype, unstable, name;
    prefix::Bool = true)
    checkrange(fn, "fastperiod", fast, 2, 100_000)
    checkrange(fn, "slowperiod", slow, 2, 100_000)
    checkmatype(fn, "matype", matype)
    checkunstable(unstable)
    fast, slow = minmax(fast, slow)
    C = colname(column)
    N = outname(prefix ? C : nothing, name)
    s = PriceOscillator{K,matype,C,N}(Int(fast), Int(slow), Int(unstable))
    return withterms(s, column)
end

const PO_DOC = """
The averages are `matype` moving averages as for [`MA`](@ref) (`:mama` lands
with S6), both started at the first bar. TA-Lib swaps the periods if
`slowperiod < fastperiod`. `unstable` is the unstable period of `matype`, if it
has one.
"""

"""
    APO(column::ColumnSpec; fastperiod = 12, slowperiod = 26, matype = :ema,
        unstable = 0, name = :apo)

TA-Lib's `APO`, the absolute price oscillator `fast − slow`, in
`:{column}_apo`.

$PO_DOC
$PLAIN_DOC$SKIP_DOC
TA-Lib: `ta_codegen/input/apo/apo.yaml`, `apo.md`.
"""
APO(column::ColumnSpec; fastperiod::Integer = 12, slowperiod::Integer = 26,
    matype::Symbol = :ema, unstable::Integer = 0, name::Symbol = :apo) =
    priceoscillator("APO", :apo, column, fastperiod, slowperiod, matype, unstable, name)

"""
    PPO(column::ColumnSpec; fastperiod = 12, slowperiod = 26, matype = :ema,
        unstable = 0, name = :ppo)

TA-Lib's `PPO`, the percentage price oscillator `(fast − slow)/slow·100`, in
`:{column}_ppo`. A slow average TA-Lib finds zero gives 0.

$PO_DOC
$PLAIN_DOC$SKIP_DOC
TA-Lib: `ta_codegen/input/ppo/ppo.yaml`, `ppo.md`.
"""
PPO(column::ColumnSpec; fastperiod::Integer = 12, slowperiod::Integer = 26,
    matype::Symbol = :ema, unstable::Integer = 0, name::Symbol = :ppo) =
    priceoscillator("PPO", :ppo, column, fastperiod, slowperiod, matype, unstable, name)

# ---------------------------------------------------------------------------
# TRIX

struct TRIXSummarizer{C,N} <: Summarizer
    period::Int
    unstable::Int
end

mutable struct TRIXState{C,N,K,T} <: SummarizerState
    const tema::K
    started::Bool
    prev::T
    out::Union{Missing,T}
end

CausalFrames.emptyvalue(::TRIXSummarizer{C,N}) where {C,N} = NamedTuple{(N,)}((missing,))

function CausalFrames.fresh(s::TRIXSummarizer{C,N}, intypes::NamedTuple) where {C,N}
    T = floattype(intypes[C])
    k = TEMAKernel(T, s.period; s.unstable)
    return TRIXState{C,N,typeof(k),T}(k, false, zero(T), missing)
end
CausalFrames.fresh(st::TRIXState{C,N,K,T}) where {C,N,K,T} =
    TRIXState{C,N,K,T}(fresh(st.tema), false, zero(T), missing)
function CausalFrames.fresh!(st::TRIXState{C,N,K,T}) where {C,N,K,T}
    fresh!(st.tema)
    st.started = false
    st.prev = zero(T)
    st.out = missing
    return st
end

# The triple EMA is TEMAKernel's three gated stages (ta_TRIX.c chains them as
# ta_TEMA.c does); TRIX is the one-bar rate of change of the third.
@inline function CausalFrames.update!(st::TRIXState{C,N,K,T}, row) where {C,N,K,T}
    x = row[C]
    st.out = missing
    ismissing(x) && return nothing
    ismissing(step!(st.tema, x)) && return nothing
    e3 = current(st.tema.e3)::T
    if st.started
        p = st.prev
        st.out = p != 0 ? ((e3 / p) - 1) * 100 : zero(T)
    end
    st.started = true
    st.prev = e3
    return nothing
end
@inline CausalFrames.value(st::TRIXState{C,N,K,T}) where {C,N,K,T} =
    NamedTuple{(N,),Tuple{Union{Missing,T}}}((st.out,))

"""
    TRIX(column::ColumnSpec; period = 30, unstable = 0, name = :trix)

TA-Lib's `TRIX` in `:{column}_trix`: the one-bar rate of change, in percent,
of a triple EMA (an EMA of an EMA of an EMA, each seeded as TA-Lib seeds it).
The lookback is `3(period − 1) + 1`. `unstable` is EMA's unstable period, which
each stage passes before feeding the next, as for [`TEMA`](@ref).

$PLAIN_DOC$SKIP_DOC
TA-Lib: `ta_codegen/input/trix/trix.yaml`, `trix.md`.
"""
function TRIX(column::ColumnSpec; period::Integer = 30, unstable::Integer = 0,
    name::Symbol = :trix)
    checkrange("TRIX", "period", period, 1, 100_000)
    checkunstable(unstable)
    C = colname(column)
    return withterms(TRIXSummarizer{C,outname(C, name)}(Int(period), Int(unstable)),
        column)
end

# ---------------------------------------------------------------------------
# The stochastics

# `K` is `:stoch` (%K, slow %K, slow %D), `:stochf` (%K, %D) or `:stochrsi`
# (RSI, its %K, %D); `KM` and `DM` are the MA types of the two smoothings (`KM`
# unused but by Stoch). `Is` are the input columns: high, low, close, or the one
# series.
struct StochSummarizer{K,KM,DM,Is,Ns} <: Summarizer
    period::Int
    fastk::Int
    slowk::Int
    d::Int
    unstable::Int
end

mutable struct StochState{K,Is,Ns,G,F,S,D,T} <: SummarizerState
    const rsi::G
    const fastk::F
    const slowk::S
    const d::D
    const unstable::Int
    k::Union{Missing,T}
    dout::Union{Missing,T}
end

CausalFrames.emptyvalue(::StochSummarizer{K,KM,DM,Is,Ns}) where {K,KM,DM,Is,Ns} =
    NamedTuple{Ns}((missing, missing))

function CausalFrames.fresh(s::StochSummarizer{K,KM,DM,Is,Ns},
    intypes::NamedTuple) where {K,KM,DM,Is,Ns}
    T = floattype(promote_type(map(c -> nonmissingtype(intypes[c]), Is)...))
    rsi = K === :stochrsi ? GainLossKernel(T, s.period) : nothing
    fk = FastKKernel(T, s.fastk, K === :stochrsi ? :x : :hlc)
    sk = K === :stoch ? MAKernel(T, KM, s.slowk; s.unstable) : nothing
    d = MAKernel(T, DM, s.d; s.unstable)
    return StochState{K,Is,Ns,typeof(rsi),typeof(fk),typeof(sk),typeof(d),T}(rsi, fk, sk,
        d, s.unstable, missing, missing)
end
CausalFrames.fresh(st::StochState{K,Is,Ns,G,F,S,D,T}) where {K,Is,Ns,G,F,S,D,T} =
    StochState{K,Is,Ns,G,F,S,D,T}(freshornothing(st.rsi), fresh(st.fastk),
        freshornothing(st.slowk), fresh(st.d), st.unstable, missing, missing)
function CausalFrames.fresh!(st::StochState)
    st.rsi === nothing || fresh!(st.rsi)
    fresh!(st.fastk)
    st.slowk === nothing || fresh!(st.slowk)
    fresh!(st.d)
    st.k = st.dout = missing
    return st
end

freshornothing(::Nothing) = nothing
freshornothing(k) = fresh(k)

# %K from the row: the window's %K of high, low and close, or of the RSI.
@inline function stochfastk(
    st::StochState{:stochrsi,Is,Ns,G,F,S,D,T},
    row,
) where {Is,Ns,G,F,S,D,T}
    x = row[Is[1]]
    ismissing(x) && return missing
    gl = step!(st.rsi, x)
    nseen(st.rsi) > lookback(st.rsi) + st.unstable || return missing
    return step!(st.fastk, gainlossvalue(Val(:rsi), gl::Tuple{T,T}))
end
@inline function stochfastk(st::StochState, row)
    H, L, C = stochcolumns(st)
    h, l, c = row[H], row[L], row[C]
    anymissing(h, l, c) && return missing
    return step!(st.fastk, h, l, c)
end
stochcolumns(::StochState{K,Is}) where {K,Is} = Is

# The smoothed %K: Stoch's slow %K, or %K itself.
@inline stochslowk(st::StochState{:stoch}, k) = step!(st.slowk, k)
@inline stochslowk(::StochState, k) = k

@inline function CausalFrames.update!(st::StochState, row)
    st.k = st.dout = missing
    fk = stochfastk(st, row)
    ismissing(fk) && return nothing
    k = stochslowk(st, fk)
    ismissing(k) && return nothing
    d = step!(st.d, k)
    ismissing(d) && return nothing
    st.k = k
    st.dout = d
    return nothing
end
@inline CausalFrames.value(st::StochState{K,Is,Ns,G,F,S,D,T}) where {K,Is,Ns,G,F,S,D,T} =
    NamedTuple{Ns,NTuple{2,Union{Missing,T}}}((st.k, st.dout))

const STOCH_DOC = """
%K is where the close sits in the `fastkperiod`-bar high-low range, as a
percentage (0 where TA-Lib finds the range zero), read through CausalFrames'
windowed `Max`, `Min` and `Last`. The smoothings are `matype` moving averages
as for [`MA`](@ref) (`:mama` lands with S6), and `unstable` is the unstable
period of each that has one. Both outputs start together, on the first bar %D
has a value. A bar with any input `missing` leaves the state unchanged and
emits `missing`.
"""

"""
    Stoch(; high = :high, low = :low, close = :close, fastkperiod = 5, slowkperiod = 3,
          slowkmatype = :sma, slowdperiod = 3, slowdmatype = :sma, unstable = 0,
          name = :stoch)

TA-Lib's `STOCH`, the slow stochastic, in `:stoch_slowk` and `:stoch_slowd`:
slow %K is a `slowkperiod` average of %K, and slow %D a `slowdperiod` average
of slow %K.

$STOCH_DOC
$PLAIN_DOC
TA-Lib: `ta_codegen/input/stoch/stoch.yaml`, `stoch.md`.
"""
function Stoch(; high::ColumnSpec = :high, low::ColumnSpec = :low,
    close::ColumnSpec = :close, fastkperiod::Integer = 5, slowkperiod::Integer = 3,
    slowkmatype::Symbol = :sma, slowdperiod::Integer = 3, slowdmatype::Symbol = :sma,
    unstable::Integer = 0, name::Symbol = :stoch)
    checkrange("Stoch", "fastkperiod", fastkperiod, 1, 100_000)
    checkrange("Stoch", "slowkperiod", slowkperiod, 1, 100_000)
    checkrange("Stoch", "slowdperiod", slowdperiod, 1, 100_000)
    checkmatype("Stoch", "slowkmatype", slowkmatype)
    checkmatype("Stoch", "slowdmatype", slowdmatype)
    checkunstable(unstable)
    Is = (colname(high), colname(low), colname(close))
    s = StochSummarizer{:stoch,slowkmatype,slowdmatype,Is,
        outnames(nothing, name, (:slowk, :slowd))}(0, Int(fastkperiod), Int(slowkperiod),
        Int(slowdperiod), Int(unstable))
    return withterms(s, high, low, close)
end

"""
    StochF(; high = :high, low = :low, close = :close, fastkperiod = 5,
           fastdperiod = 3, fastdmatype = :sma, unstable = 0, name = :stochf)

TA-Lib's `STOCHF`, the fast stochastic, in `:stochf_fastk` and
`:stochf_fastd`: %K, and %D a `fastdperiod` average of it.

$STOCH_DOC
$PLAIN_DOC
TA-Lib: `ta_codegen/input/stochf/stochf.yaml`, `stochf.md`.
"""
function StochF(; high::ColumnSpec = :high, low::ColumnSpec = :low,
    close::ColumnSpec = :close, fastkperiod::Integer = 5, fastdperiod::Integer = 3,
    fastdmatype::Symbol = :sma, unstable::Integer = 0, name::Symbol = :stochf)
    checkrange("StochF", "fastkperiod", fastkperiod, 1, 100_000)
    checkrange("StochF", "fastdperiod", fastdperiod, 1, 100_000)
    checkmatype("StochF", "fastdmatype", fastdmatype)
    checkunstable(unstable)
    Is = (colname(high), colname(low), colname(close))
    s = StochSummarizer{:stochf,:sma,fastdmatype,Is,
        outnames(nothing, name, (:fastk, :fastd))}(0, Int(fastkperiod), 0,
        Int(fastdperiod), Int(unstable))
    return withterms(s, high, low, close)
end

"""
    StochRSI(column::ColumnSpec; period = 14, fastkperiod = 5, fastdperiod = 3,
             fastdmatype = :sma, unstable = 0, name = :stochrsi)

TA-Lib's `STOCHRSI`, the fast stochastic of the `period`-bar [`RSI`](@ref), in
`:{column}_stochrsi_fastk` and `:{column}_stochrsi_fastd`. `unstable` is both
RSI's unstable period and that of `fastdmatype`, if it has one, as
`TA_SetUnstablePeriod(TA_FUNC_UNST_ALL, …)` sets them.

$STOCH_DOC
$PLAIN_DOC
TA-Lib: `ta_codegen/input/stochrsi/stochrsi.yaml`, `stochrsi.md`.
"""
function StochRSI(column::ColumnSpec; period::Integer = 14, fastkperiod::Integer = 5,
    fastdperiod::Integer = 3, fastdmatype::Symbol = :sma, unstable::Integer = 0,
    name::Symbol = :stochrsi)
    checkrange("StochRSI", "period", period, 2, 100_000)
    checkrange("StochRSI", "fastkperiod", fastkperiod, 1, 100_000)
    checkrange("StochRSI", "fastdperiod", fastdperiod, 1, 100_000)
    checkmatype("StochRSI", "fastdmatype", fastdmatype)
    checkunstable(unstable)
    C = colname(column)
    s = StochSummarizer{:stochrsi,:sma,fastdmatype,(C,),
        outnames(C, name, (:fastk, :fastd))}(Int(period), Int(fastkperiod), 0,
        Int(fastdperiod), Int(unstable))
    return withterms(s, column)
end

# ---------------------------------------------------------------------------
# ULTOSC

struct ULTOSCSummarizer{H,L,C,N} <: Summarizer
    periods::NTuple{3,Int}
end

mutable struct ULTOSCState{H,L,C,N,W1,W2,W3,T} <: SummarizerState
    const periods::NTuple{3,Int}
    const w1::W1
    const w2::W2
    const w3::W3
    n::Int
    prevclose::T
    nullrun::Int
    out::Union{Missing,T}
end

CausalFrames.emptyvalue(::ULTOSCSummarizer{H,L,C,N}) where {H,L,C,N} =
    NamedTuple{(N,)}((missing,))

function CausalFrames.fresh(
    s::ULTOSCSummarizer{H,L,C,N},
    intypes::NamedTuple,
) where {H,L,C,N}
    T = floattype(promote_type(map(c -> nonmissingtype(intypes[c]), (H, L, C))...))
    w1, w2, w3 = map(p -> sumpairwindow(:bp, :tr, p, T), s.periods)
    return ULTOSCState{H,L,C,N,typeof(w1),typeof(w2),typeof(w3),T}(s.periods, w1, w2, w3,
        0, zero(T), 0, missing)
end
CausalFrames.fresh(st::ULTOSCState{H,L,C,N,W1,W2,W3,T}) where {H,L,C,N,W1,W2,W3,T} =
    ULTOSCState{H,L,C,N,W1,W2,W3,T}(st.periods, fresh(st.w1), fresh(st.w2), fresh(st.w3),
        0, zero(T), 0, missing)
function CausalFrames.fresh!(st::ULTOSCState{H,L,C,N,W1,W2,W3,T}) where {H,L,C,N,W1,W2,W3,T}
    fresh!(st.w1)
    fresh!(st.w2)
    fresh!(st.w3)
    st.n = 0
    st.prevclose = zero(T)
    st.nullrun = 0
    st.out = missing
    return st
end

# One period's buying pressure over its true range, 0 for a window with no
# range or one ultosc.c's run of null bars zeroes.
@inline function ultratio(sums, nullrun, p)
    a, b = sums
    (nullrun >= p || !(b > 0)) && return zero(a / b)
    return a / b
end

@inline function CausalFrames.update!(st::ULTOSCState{H,L,C,N,W1,W2,W3,T},
    row) where {H,L,C,N,W1,W2,W3,T}
    h, l, c = row[H], row[L], row[C]
    st.out = missing
    anymissing(h, l, c) && return nothing
    h, l, c = convert(T, h), convert(T, l), convert(T, c)
    n = st.n += 1
    cy = st.prevclose
    st.prevclose = c
    n == 1 && return nothing
    bp = c - min(l, cy)
    tr = truerange(h, l, cy)
    term = (bp = bp, tr = tr)
    update!(st.w1, term)
    update!(st.w2, term)
    update!(st.w3, term)
    p1, p2, p3 = st.periods
    st.nullrun = tr == 0 && bp == 0 ? min(st.nullrun + 1, p3) : 0
    s3 = value(st.w3).sumpair
    ismissing(s3) && return nothing
    s1 = value(st.w1).sumpair::Tuple{T,T}
    s2 = value(st.w2).sumpair::Tuple{T,T}
    nr = st.nullrun
    v = 4 * ultratio(s1, nr, p1) + 2 * ultratio(s2, nr, p2) + ultratio(s3, nr, p3)
    st.out = 100 * (v / 7)
    return nothing
end
@inline CausalFrames.value(st::ULTOSCState{H,L,C,N,W1,W2,W3,T}) where {H,L,C,N,W1,W2,W3,T} =
    NamedTuple{(N,),Tuple{Union{Missing,T}}}((st.out,))

"""
    ULTOSC(; high = :high, low = :low, close = :close, timeperiod1 = 7,
           timeperiod2 = 14, timeperiod3 = 28, name = :ultosc)

TA-Lib's `ULTOSC`, Williams' ultimate oscillator, in `:ultosc`. Each bar's
buying pressure `close − min(low, previous close)` is summed over each period
and divided by the summed true range. The three ratios are weighted 4, 2 and 1
from the shortest period to the longest, as TA-Lib sorts them, and scaled to
100. A ratio over no range counts 0. The lookback is the longest period.

The window sums are CausalFrames `Sum`s under `CausalFrames.barwindow`.

$PLAIN_DOC
A bar with any input `missing` leaves the state unchanged and emits `missing`.

TA-Lib: `ta_codegen/input/ultosc/ultosc.yaml`, `ultosc.md`.
"""
function ULTOSC(; high::ColumnSpec = :high, low::ColumnSpec = :low,
    close::ColumnSpec = :close, timeperiod1::Integer = 7, timeperiod2::Integer = 14,
    timeperiod3::Integer = 28, name::Symbol = :ultosc)
    checkrange("ULTOSC", "timeperiod1", timeperiod1, 1, 100_000)
    checkrange("ULTOSC", "timeperiod2", timeperiod2, 1, 100_000)
    checkrange("ULTOSC", "timeperiod3", timeperiod3, 1, 100_000)
    ps = Tuple(sort([Int(timeperiod1), Int(timeperiod2), Int(timeperiod3)]))
    s = ULTOSCSummarizer{colname(high),colname(low),colname(close),name}(ps)
    return withterms(s, high, low, close)
end

# ---------------------------------------------------------------------------
# MFI

struct MFISummarizer{H,L,C,V,N} <: Summarizer
    period::Int
end

mutable struct MFIState{H,L,C,V,N,W,T} <: SummarizerState
    const period::Int
    const window::W
    n::Int
    prevtp::T
    nullrun::Int
    out::Union{Missing,T}
end

CausalFrames.emptyvalue(::MFISummarizer{H,L,C,V,N}) where {H,L,C,V,N} =
    NamedTuple{(N,)}((missing,))

function CausalFrames.fresh(
    s::MFISummarizer{H,L,C,V,N},
    intypes::NamedTuple,
) where {H,L,C,V,N}
    T = floattype(promote_type(map(c -> nonmissingtype(intypes[c]), (H, L, C, V))...))
    w = sumpairwindow(:pos, :neg, s.period, T)
    return MFIState{H,L,C,V,N,typeof(w),T}(s.period, w, 0, zero(T), 0, missing)
end
CausalFrames.fresh(st::MFIState{H,L,C,V,N,W,T}) where {H,L,C,V,N,W,T} =
    MFIState{H,L,C,V,N,W,T}(st.period, fresh(st.window), 0, zero(T), 0, missing)
function CausalFrames.fresh!(st::MFIState{H,L,C,V,N,W,T}) where {H,L,C,V,N,W,T}
    fresh!(st.window)
    st.n = 0
    st.prevtp = zero(T)
    st.nullrun = 0
    st.out = missing
    return st
end

@inline function CausalFrames.update!(
    st::MFIState{H,L,C,V,N,W,T},
    row,
) where {H,L,C,V,N,W,T}
    h, l, c, v = row[H], row[L], row[C], row[V]
    st.out = missing
    anymissing(h, l, c, v) && return nothing
    tp = (convert(T, h) + convert(T, l) + convert(T, c)) / 3
    n = st.n += 1
    prev = st.prevtp
    st.prevtp = tp
    n == 1 && return nothing
    d = tp - prev
    # mfi.c: a move TA-Lib finds zero carries no flow, and a falling bar's flow
    # is negative.
    mf = iszeroscaled(d, abs(tp) + abs(prev)) ? zero(T) : tp * convert(T, v)
    pos, neg = d < 0 ? (zero(T), mf) : (mf, zero(T))
    update!(st.window, (pos = pos, neg = neg))
    st.nullrun = mf == 0 ? min(st.nullrun + 1, st.period) : 0
    sums = value(st.window).sumpair
    ismissing(sums) && return nothing
    # A window of null bars has exactly zero flow, whatever round-off the
    # sliding sums hold (mfi.c's nullRun).
    p, q = st.nullrun >= st.period ? (zero(T), zero(T)) : sums
    total = p + q
    pc = p < 0 ? zero(T) : p > total ? total : p
    st.out = total <= 0 ? zero(T) : 100 * (pc / total)
    return nothing
end
@inline CausalFrames.value(st::MFIState{H,L,C,V,N,W,T}) where {H,L,C,V,N,W,T} =
    NamedTuple{(N,),Tuple{Union{Missing,T}}}((st.out,))

"""
    MFI(; high = :high, low = :low, close = :close, volume = :volume, period = 14,
        name = :mfi)

TA-Lib's `MFI`, the money flow index, in `:mfi`. Each bar's money flow is its
typical price `(high + low + close)/3` times its volume, positive when the
typical price rose from the previous bar and negative when it fell. A move
TA-Lib finds zero carries no flow. The index is `100·pos/(pos + neg)` over the
last `period` bars, or 0 when there is no flow. The lookback is `period`.

The flow sums are CausalFrames `Sum`s under `CausalFrames.barwindow`.

$PLAIN_DOC
A bar with any input `missing` leaves the state unchanged and emits `missing`.

TA-Lib: `ta_codegen/input/mfi/mfi.yaml`, `mfi.md`.
"""
function MFI(; high::ColumnSpec = :high, low::ColumnSpec = :low, close::ColumnSpec = :close,
    volume::ColumnSpec = :volume, period::Integer = 14, name::Symbol = :mfi)
    checkrange("MFI", "period", period, 2, 100_000)
    s = MFISummarizer{colname(high),colname(low),colname(close),colname(volume),name}(
        Int(period))
    return withterms(s, high, low, close, volume)
end

# ---------------------------------------------------------------------------
# Directional movement: ±DM, ±DI, DX, ADX and ADXR

# `K` is `:plusdm`, `:minusdm`, `:plusdi`, `:minusdi`, `:dx`, `:adx` or
# `:adxr`; `C` is `nothing` for the DMs, which read no close.
struct DirectionalSummarizer{K,H,L,C,N} <: Summarizer
    period::Int
    unstable::Int
end

mutable struct DirectionalState{K,H,L,C,N,D,S,A,T} <: SummarizerState
    const kernel::D
    const unstable::Int
    const invperiod::T
    const adxseed::S
    const lag::A
    ndx::Int
    lastdx::T
    adx::T
    out::Union{Missing,T}
end

CausalFrames.emptyvalue(::DirectionalSummarizer{K,H,L,C,N}) where {K,H,L,C,N} =
    NamedTuple{(N,)}((missing,))

dicolumns(H, L, ::Nothing) = (H, L)
dicolumns(H, L, C) = (H, L, C)

function CausalFrames.fresh(s::DirectionalSummarizer{K,H,L,C,N},
    intypes::NamedTuple) where {K,H,L,C,N}
    T = floattype(promote_type(map(c -> nonmissingtype(intypes[c]), dicolumns(H, L, C))...))
    k = DMKernel(T, s.period)
    lag = K === :adxr ? CausalFrames.barwindow(First(:x), s.period, (x = T,)) : nothing
    seed = seedsum(T)
    return DirectionalState{K,H,L,C,N,typeof(k),typeof(seed),typeof(lag),T}(k, s.unstable,
        one(T) / T(s.period), seed, lag, 0, zero(T), zero(T), missing)
end
CausalFrames.fresh(st::DirectionalState{K,H,L,C,N,D,S,A,T}) where {K,H,L,C,N,D,S,A,T} =
    DirectionalState{K,H,L,C,N,D,S,A,T}(fresh(st.kernel), st.unstable, st.invperiod,
        fresh(st.adxseed), freshornothing(st.lag), 0, zero(T), zero(T), missing)
function CausalFrames.fresh!(
    st::DirectionalState{K,H,L,C,N,D,S,A,T},
) where {K,H,L,C,N,D,S,A,T}
    fresh!(st.kernel)
    fresh!(st.adxseed)
    st.lag === nothing || fresh!(st.lag)
    st.ndx = 0
    st.lastdx = st.adx = zero(T)
    st.out = missing
    return st
end

dirclose(row, L, ::Nothing) = row[L]
dirclose(row, L, C) = row[C]

@inline function CausalFrames.update!(st::DirectionalState{K,H,L,C}, row) where {K,H,L,C}
    h, l, c = row[H], row[L], dirclose(row, L, C)
    st.out = missing
    anymissing(h, l, c) && return nothing
    step!(st.kernel, h, l, c)
    directional!(Val(K), st)
    return nothing
end
@inline CausalFrames.value(
    st::DirectionalState{K,H,L,C,N,D,S,A,T},
) where {K,H,L,C,N,D,S,A,T} =
    NamedTuple{(N,),Tuple{Union{Missing,T}}}((st.out,))

# ta_PLUS_DM.c: the smoothed sum, or the raw DM at period 1, whose lookback
# ignores the unstable period.
function directional!(::Union{Val{:plusdm},Val{:minusdm}},
    st::DirectionalState{K}) where {K}
    k = st.kernel
    p = k.period
    lb = p == 1 ? 1 : p - 1 + st.unstable
    nseen(k) > lb || return nothing
    pdm, mdm, _ = dmsums(k)
    st.out = K === :plusdm ? pdm : mdm
    return nothing
end

# ta_PLUS_DI.c: `100·DM/TR`, or at period 1 the bar's `DM/TR` without the 100,
# TA-Lib's historical quirk; 0 where there is no range.
function directional!(::Union{Val{:plusdi},Val{:minusdi}},
    st::DirectionalState{K,H,L,C,N,D,S,A,T}) where {K,H,L,C,N,D,S,A,T}
    k = st.kernel
    p = k.period
    lb = p == 1 ? 1 : p + st.unstable
    nseen(k) > lb || return nothing
    pdm, mdm, tr = dmsums(k)
    dm = K === :plusdi ? pdm : mdm
    st.out = if p == 1
        dm > 0 ? (tr <= 0 ? zero(T) : dm / tr) : zero(T)
    else
        tr > 0 ? 100 * (dm / tr) : zero(T)
    end
    return nothing
end

# ta_DX.c: the bar's DX and whether TA-Lib's guards (some range, and DIs that
# do not sum to zero) let it count.
@inline function dxvalue((pdm, mdm, tr)::NTuple{3,T}) where {T}
    tr > 0 || return (false, zero(T))
    m = 100 * (mdm / tr)
    pl = 100 * (pdm / tr)
    s = m + pl
    iszerota(s) && return (false, zero(T))
    return (true, 100 * (abs(m - pl) / s))
end

# A guarded DX repeats the previous one (0 before the first), as ta_DX.c does.
function directional!(::Val{:dx}, st::DirectionalState)
    k = st.kernel
    nseen(k) > k.period + st.unstable || return nothing
    ok, dx = dxvalue(dmsums(k))
    ok && (st.lastdx = dx)
    st.out = st.lastdx
    return nothing
end

# ta_ADX.c: the mean of the first `period` DX values (a guarded one adds
# nothing), then `adx − (adx − dx)/period`, held on a guarded bar. Returns
# whether the ADX is past its lookback and unstable period.
function adxstep!(st::DirectionalState{K,H,L,C,N,D,S,A,T}) where {K,H,L,C,N,D,S,A,T}
    k = st.kernel
    p = k.period
    nseen(k) > p || return false
    n = st.ndx += 1
    ok, dx = dxvalue(dmsums(k))
    if n <= p
        ok && seedadd!(st.adxseed, dx)
        n == p && (st.adx = seedtotal(st.adxseed) / p)
    elseif ok
        st.adx = st.adx - (st.adx - dx) * st.invperiod
    end
    return n >= p + st.unstable
end

function directional!(::Val{:adx}, st::DirectionalState)
    adxstep!(st) && (st.out = st.adx)
    return nothing
end

# ta_ADXR.c: the mean of today's ADX and the one `period − 1` bars back, read
# from a CausalFrames `First` over the last `period` ADX values.
function directional!(
    ::Val{:adxr},
    st::DirectionalState{K,H,L,C,N,D,S,A,T},
) where {K,H,L,C,N,D,S,A,T}
    adxstep!(st) || return nothing
    update!(st.lag, (x = st.adx,))
    old = value(st.lag).x_first
    st.out = ismissing(old) ? missing : (st.adx + old) / 2
    return nothing
end

function directional(fn, K, high, low, close, period, unstable, name; minperiod)
    checkrange(fn, "period", period, minperiod, 100_000)
    checkunstable(unstable)
    H, L = colname(high), colname(low)
    C = close === nothing ? nothing : colname(close)
    s = DirectionalSummarizer{K,H,L,C,name}(Int(period), Int(unstable))
    specs = close === nothing ? (high, low) : (high, low, close)
    return withterms(s, specs...)
end

const DM_DOC = """
The directional movement of a bar is its up move `high − previous high` (+DM)
or its down move `previous low − low` (−DM), whichever is larger and positive;
the other is 0, and a tie gives 0 to both. Over more than one bar they are
smoothed as Wilder's running sums, seeded with the sum of the first
`period − 1` moves and stepped `prev − prev/period + dm`.
"""

const DI_DOC = """
The directional indicators are `100·DM/TR` over the Wilder-smoothed sums of the
directional movement and the true range, each seeded with its first
`period − 1` values (0 where the summed range is not positive).
"""

const DIR_DOC = """
$PLAIN_DOC
A bar with any input `missing` leaves the state unchanged and emits `missing`.
"""

"""
    PlusDM(; high = :high, low = :low, period = 14, unstable = 0, name = :plusdm)

TA-Lib's `PLUS_DM`, the smoothed +DM, in `:plusdm`. The lookback is
`period − 1`, plus `unstable`, TA-Lib's unstable period. At period 1 it is the
bar's raw +DM with lookback 1, whatever `unstable` is.

$DM_DOC
$DIR_DOC
TA-Lib: `ta_codegen/input/plus_dm/plus_dm.yaml`, `plus_dm.md`.
"""
PlusDM(; high::ColumnSpec = :high, low::ColumnSpec = :low, period::Integer = 14,
    unstable::Integer = 0, name::Symbol = :plusdm) =
    directional("PlusDM", :plusdm, high, low, nothing, period, unstable, name;
        minperiod = 1)

"""
    MinusDM(; high = :high, low = :low, period = 14, unstable = 0, name = :minusdm)

TA-Lib's `MINUS_DM`, the smoothed −DM, in `:minusdm`, as [`PlusDM`](@ref).

$DM_DOC
$DIR_DOC
TA-Lib: `ta_codegen/input/minus_dm/minus_dm.yaml`, `minus_dm.md`.
"""
MinusDM(; high::ColumnSpec = :high, low::ColumnSpec = :low, period::Integer = 14,
    unstable::Integer = 0, name::Symbol = :minusdm) =
    directional("MinusDM", :minusdm, high, low, nothing, period, unstable, name;
        minperiod = 1)

"""
    PlusDI(; high = :high, low = :low, close = :close, period = 14, unstable = 0,
           name = :plusdi)

TA-Lib's `PLUS_DI`, the positive directional indicator, in `:plusdi`. The
lookback is `period`, plus `unstable`, TA-Lib's unstable period. At period 1 it
is the bar's `+DM/TR` *without* the factor 100, TA-Lib's historical quirk, with
lookback 1 whatever `unstable` is.

$DI_DOC
$DM_DOC
$DIR_DOC
TA-Lib: `ta_codegen/input/plus_di/plus_di.yaml`, `plus_di.md`.
"""
PlusDI(; high::ColumnSpec = :high, low::ColumnSpec = :low, close::ColumnSpec = :close,
    period::Integer = 14, unstable::Integer = 0, name::Symbol = :plusdi) =
    directional("PlusDI", :plusdi, high, low, close, period, unstable, name;
        minperiod = 1)

"""
    MinusDI(; high = :high, low = :low, close = :close, period = 14, unstable = 0,
            name = :minusdi)

TA-Lib's `MINUS_DI`, the negative directional indicator, in `:minusdi`, as
[`PlusDI`](@ref).

$DI_DOC
$DM_DOC
$DIR_DOC
TA-Lib: `ta_codegen/input/minus_di/minus_di.yaml`, `minus_di.md`.
"""
MinusDI(; high::ColumnSpec = :high, low::ColumnSpec = :low, close::ColumnSpec = :close,
    period::Integer = 14, unstable::Integer = 0, name::Symbol = :minusdi) =
    directional("MinusDI", :minusdi, high, low, close, period, unstable, name;
        minperiod = 1)

"""
    DX(; high = :high, low = :low, close = :close, period = 14, unstable = 0, name = :dx)

TA-Lib's `DX`, the directional movement index `100·|−DI − +DI|/(−DI + +DI)`,
in `:dx`. Where there is no range, or the DIs sum to what TA-Lib finds zero,
it repeats the previous DX (0 before the first), as TA-Lib does. The lookback
is `period`, plus `unstable`, TA-Lib's unstable period.

$DI_DOC
$DIR_DOC
TA-Lib: `ta_codegen/input/dx/dx.yaml`, `dx.md`.
"""
DX(; high::ColumnSpec = :high, low::ColumnSpec = :low, close::ColumnSpec = :close,
    period::Integer = 14, unstable::Integer = 0, name::Symbol = :dx) =
    directional("DX", :dx, high, low, close, period, unstable, name; minperiod = 2)

const ADX_DOC = """
The ADX is seeded with the mean of the first `period` DX values (a bar where
DX is undefined adds nothing), then steps `adx − (adx − dx)/period`, holding
its value on a bar where DX is undefined.
"""

"""
    ADX(; high = :high, low = :low, close = :close, period = 14, unstable = 0,
        name = :adx)

TA-Lib's `ADX`, Wilder's average directional movement index, in `:adx`. The
lookback is `2·period − 1`, plus `unstable`, TA-Lib's unstable period.

$ADX_DOC
$DIR_DOC
TA-Lib: `ta_codegen/input/adx/adx.yaml`, `adx.md`.
"""
ADX(; high::ColumnSpec = :high, low::ColumnSpec = :low, close::ColumnSpec = :close,
    period::Integer = 14, unstable::Integer = 0, name::Symbol = :adx) =
    directional("ADX", :adx, high, low, close, period, unstable, name; minperiod = 2)

"""
    ADXR(; high = :high, low = :low, close = :close, period = 14, unstable = 0,
         name = :adxr)

TA-Lib's `ADXR`, the average of today's [`ADX`](@ref) and the one
`period − 1` bars back, in `:adxr`. The lookback is `3·period − 2`, plus
`unstable`, the ADX unstable period TA-Lib's ADXR inherits. The earlier ADX is
read from a CausalFrames `First` under `CausalFrames.barwindow`.

$ADX_DOC
$DIR_DOC
TA-Lib: `ta_codegen/input/adxr/adxr.yaml`, `adxr.md`.
"""
ADXR(; high::ColumnSpec = :high, low::ColumnSpec = :low, close::ColumnSpec = :close,
    period::Integer = 14, unstable::Integer = 0, name::Symbol = :adxr) =
    directional("ADXR", :adxr, high, low, close, period, unstable, name; minperiod = 2)
