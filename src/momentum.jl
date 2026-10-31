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
    missings((Symbol(C, :_, K),))
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
# RSI and CMO

struct GainLossSpec{K}
    period::Int
    unstable::Int
end

mutable struct GainLossOscillator{K,G}
    const gainloss::G
    const unstable::Int
end

barkernel(s::GainLossSpec{K}, ::Type{T}) where {K,T} =
    (g = GainLossKernel(T, s.period); GainLossOscillator{K,typeof(g)}(g, s.unstable))
CausalFrames.fresh!(o::GainLossOscillator) = (fresh!(o.gainloss); o)

@inline function barstep!(o::GainLossOscillator{K}, x) where {K}
    k = o.gainloss
    gl = step!(k, x)
    nseen(k) > lookback(k) + o.unstable || return nothing
    return (gainlossvalue(Val(K), gl),)
end

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
    return barindicator(GainLossSpec{K}(period, unstable),
        (outname(colname(column), name),), column)
end

"""
    RSI(column::ColumnSpec; period = 14, unstable = 0, name = :rsi)

TA-Lib's `RSI`, Wilder's relative strength index, in `:{column}_rsi`: with `g`
and `l` the Wilder-smoothed gains and losses, `100·g/(g + l)`, or 0 where both
are zero. The averages are seeded with the mean of the first `period` moves.
The lookback is `period`, and `unstable` is TA-Lib's unstable period.

$PLAIN_DOC$SKIP_DOC

$DAILY_DOC
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

$DAILY_DOC
TA-Lib: `ta_codegen/input/cmo/cmo.yaml`, `cmo.md`.
"""
CMO(column::ColumnSpec; period::Integer = 14, unstable::Integer = 0, name::Symbol = :cmo) =
    gainlossoscillator("CMO", :cmo, column, period, unstable, name)

# ---------------------------------------------------------------------------
# The MACD family

const MACD_SUFFIXES = (:macd, :macdsignal, :macdhist)

# `K` is `:macd`, `:macdfix` or `:macdext`, which sets how the kernels are
# built; `FM`, `SM` and `GM` are the fast, slow and signal MA types.
struct MACDSpec{K,FM,SM,GM}
    fastperiod::Int
    slowperiod::Int
    signalperiod::Int
    unstable::Int
end

mutable struct MACDKernel{F,S,G}
    const fast::F
    const slow::S
    const signal::G
    const fastoffset::Int
    const slowoffset::Int
    n::Int
end

macdkernels(::Val{:macd}, s, T) =
    (MAKernel(T, :ema, s.fastperiod; s.unstable, identity = false),
        MAKernel(T, :ema, s.slowperiod; s.unstable, identity = false),
        MAKernel(T, :ema, s.signalperiod; s.unstable, identity = false))
macdkernels(::Val{:macdfix}, s, T) =
    (fixedemakernel(T, 12, 0.15; s.unstable), fixedemakernel(T, 26, 0.075; s.unstable),
        MAKernel(T, :ema, s.signalperiod; s.unstable, identity = false))
macdkernels(::Val{:macdext}, s::MACDSpec{K,FM,SM,GM}, T) where {K,FM,SM,GM} =
    (MAKernel(T, FM, s.fastperiod; s.unstable), MAKernel(T, SM, s.slowperiod; s.unstable),
        MAKernel(T, GM, s.signalperiod; s.unstable))

function barkernel(s::MACDSpec{K}, ::Type{T}) where {K,T}
    f, sl, g = macdkernels(Val(K), s, T)
    # Both averages first emit on the same bar, as macd.c and macdext.c align
    # them: the one with the shorter lookback starts that much later.
    L = max(lookback(f), lookback(sl))
    return MACDKernel(f, sl, g, L - lookback(f), L - lookback(sl), 0)
end
function CausalFrames.fresh!(k::MACDKernel)
    fresh!(k.fast)
    fresh!(k.slow)
    fresh!(k.signal)
    k.n = 0
    return k
end

@inline function barstep!(k::MACDKernel, x)
    n = k.n += 1
    vf = n > k.fastoffset ? step!(k.fast, x) : missing
    vs = n > k.slowoffset ? step!(k.slow, x) : missing
    (ismissing(vf) || ismissing(vs)) && return nothing
    m = vf - vs
    sig = step!(k.signal, m)
    ismissing(sig) && return nothing
    return (m, sig, m - sig)
end

function macdsummarizer(K, fm, sm, gm, column, fast, slow, signal, unstable, name)
    C = colname(column)
    # TA-Lib swaps the periods (and their types) when slow < fast.
    if slow < fast
        fast, slow = slow, fast
        fm, sm = sm, fm
    end
    s = MACDSpec{K,fm,sm,gm}(fast, slow, signal, checkunstable(unstable))
    return barindicator(s, outnames(C, name, MACD_SUFFIXES), column)
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

$DAILY_DOC
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

$DAILY_DOC
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
[`MA`](@ref), and each average follows `MA`'s rules, period-1 copy included. `unstable` applies to every average whose type has an
unstable period.

$MACD_DOC
$PLAIN_DOC$SKIP_DOC

$DAILY_DOC
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

struct PriceOscillatorSpec{K,M}
    fastperiod::Int
    slowperiod::Int
    unstable::Int
end

mutable struct PriceOscillator{K,F,S}
    const fast::F
    const slow::S
end

function barkernel(s::PriceOscillatorSpec{K,M}, ::Type{T}) where {K,M,T}
    f = MAKernel(T, M, s.fastperiod; s.unstable)
    sl = MAKernel(T, M, s.slowperiod; s.unstable)
    return PriceOscillator{K,typeof(f),typeof(sl)}(f, sl)
end
CausalFrames.fresh!(k::PriceOscillator) = (fresh!(k.fast); fresh!(k.slow); k)

# Both averages start at the first bar, as ta_APO.c's two TA_MA calls do over a
# whole series; the output starts with the slow one.
@inline function barstep!(k::PriceOscillator{K}, x) where {K}
    vf = step!(k.fast, x)
    vs = step!(k.slow, x)
    return ismissing(vf) || ismissing(vs) ? nothing : (oscillatorvalue(Val(K), vf, vs),)
end

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
    N = outname(prefix ? colname(column) : nothing, name)
    return barindicator(PriceOscillatorSpec{K,matype}(fast, slow, unstable), (N,), column)
end

const PO_DOC = """
The averages are `matype` moving averages as for [`MA`](@ref), both started at
the first bar. TA-Lib swaps the periods if
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

$DAILY_DOC
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

$DAILY_DOC
TA-Lib: `ta_codegen/input/ppo/ppo.yaml`, `ppo.md`.
"""
PPO(column::ColumnSpec; fastperiod::Integer = 12, slowperiod::Integer = 26,
    matype::Symbol = :ema, unstable::Integer = 0, name::Symbol = :ppo) =
    priceoscillator("PPO", :ppo, column, fastperiod, slowperiod, matype, unstable, name)

# ---------------------------------------------------------------------------
# TRIX

struct TRIXSpec
    period::Int
    unstable::Int
end

mutable struct TRIXKernel{K,T}
    const tema::K
    started::Bool
    prev::T
end

barkernel(s::TRIXSpec, ::Type{T}) where {T} =
    TRIXKernel(TEMAKernel(T, s.period; s.unstable), false, zero(T))
function CausalFrames.fresh!(k::TRIXKernel{K,T}) where {K,T}
    fresh!(k.tema)
    k.started = false
    k.prev = zero(T)
    return k
end

# The triple EMA is TEMAKernel's three gated stages (ta_TRIX.c chains them as
# ta_TEMA.c does); TRIX is the one-bar rate of change of the third.
@inline function barstep!(k::TRIXKernel{K,T}, x::T) where {K,T}
    ismissing(step!(k.tema, x)) && return nothing
    e3 = current(k.tema.e3)::T
    started, p = k.started, k.prev
    k.started, k.prev = true, e3
    started || return nothing
    return (p != 0 ? ((e3 / p) - 1) * 100 : zero(T),)
end

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
    return barindicator(TRIXSpec(period, unstable), (outname(colname(column), name),),
        column)
end

# ---------------------------------------------------------------------------
# The stochastics

# `K` is `:stoch` (%K, slow %K, slow %D), `:kdj` (Stoch's, plus J), `:stochf`
# (%K, %D) or `:stochrsi` (RSI, its %K, %D); `KM` and `DM` are the MA types of
# the two smoothings (`KM` unused but by Stoch and KDJ).
struct StochSpec{K,KM,DM}
    period::Int
    fastk::Int
    slowk::Int
    d::Int
    unstable::Int
end

mutable struct StochKernel{K,G,F,S,D}
    const rsi::G
    const fastk::F
    const slowk::S
    const d::D
    const unstable::Int
end

function barkernel(s::StochSpec{K,KM,DM}, ::Type{T}) where {K,KM,DM,T}
    rsi = K === :stochrsi ? GainLossKernel(T, s.period) : nothing
    fk = FastKKernel(T, s.fastk, K === :stochrsi ? :x : :hlc)
    sk = K === :stoch || K === :kdj ? MAKernel(T, KM, s.slowk; s.unstable) : nothing
    d = MAKernel(T, DM, s.d; s.unstable)
    return StochKernel{K,typeof(rsi),typeof(fk),typeof(sk),typeof(d)}(rsi, fk, sk, d,
        s.unstable)
end
function CausalFrames.fresh!(k::StochKernel)
    maybefresh!(k.rsi)
    fresh!(k.fastk)
    maybefresh!(k.slowk)
    fresh!(k.d)
    return k
end

# %K of the RSI, or of high, low and close.
@inline function barstep!(k::StochKernel{:stochrsi}, x::T) where {T}
    gl = step!(k.rsi, x)
    nseen(k.rsi) > lookback(k.rsi) + k.unstable || return nothing
    return stochsmooth(k, step!(k.fastk, gainlossvalue(Val(:rsi), gl::Tuple{T,T})))
end
@inline barstep!(k::StochKernel, h::T, l::T, c::T) where {T} =
    stochsmooth(k, step!(k.fastk, h, l, c))

# The outputs from %K: Stoch's slow %K (or %K itself) and its %D.
@inline function stochsmooth(k::StochKernel{K}, fk) where {K}
    ismissing(fk) && return nothing
    sk = stochslowk(k, fk)
    ismissing(sk) && return nothing
    d = step!(k.d, sk)
    ismissing(d) && return nothing
    return stochouts(Val(K), sk, d)
end

@inline stochslowk(k::Union{StochKernel{:stoch},StochKernel{:kdj}}, fk) = step!(k.slowk, fk)
@inline stochslowk(::StochKernel, fk) = fk

@inline stochouts(::Val, k, d) = (k, d)
# ta_KDJ.c: J is `3·K − 2·D`, unclamped.
@inline stochouts(::Val{:kdj}, k, d) = (k, d, 3 * k - 2 * d)

const STOCH_DOC = """
%K is where the close sits in the `fastkperiod`-bar high-low range, as a
percentage (0 where TA-Lib finds the range zero), read through CausalFrames'
windowed `Max`, `Min` and `Last`. The smoothings are `matype` moving averages
as for [`MA`](@ref), and `unstable` is the unstable period of each that has one. Both outputs start together, on the first bar %D
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

$DAILY_DOC
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
    s = StochSpec{:stoch,slowkmatype,slowdmatype}(0, fastkperiod, slowkperiod,
        slowdperiod, unstable)
    return barindicator(s, outnames(nothing, name, (:slowk, :slowd)), high, low, close)
end

"""
    StochF(; high = :high, low = :low, close = :close, fastkperiod = 5,
           fastdperiod = 3, fastdmatype = :sma, unstable = 0, name = :stochf)

TA-Lib's `STOCHF`, the fast stochastic, in `:stochf_fastk` and
`:stochf_fastd`: %K, and %D a `fastdperiod` average of it.

$STOCH_DOC
$PLAIN_DOC

$DAILY_DOC
TA-Lib: `ta_codegen/input/stochf/stochf.yaml`, `stochf.md`.
"""
function StochF(; high::ColumnSpec = :high, low::ColumnSpec = :low,
    close::ColumnSpec = :close, fastkperiod::Integer = 5, fastdperiod::Integer = 3,
    fastdmatype::Symbol = :sma, unstable::Integer = 0, name::Symbol = :stochf)
    checkrange("StochF", "fastkperiod", fastkperiod, 1, 100_000)
    checkrange("StochF", "fastdperiod", fastdperiod, 1, 100_000)
    checkmatype("StochF", "fastdmatype", fastdmatype)
    checkunstable(unstable)
    s = StochSpec{:stochf,:sma,fastdmatype}(0, fastkperiod, 0, fastdperiod, unstable)
    return barindicator(s, outnames(nothing, name, (:fastk, :fastd)), high, low, close)
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

$DAILY_DOC
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
    s = StochSpec{:stochrsi,:sma,fastdmatype}(period, fastkperiod, 0, fastdperiod,
        unstable)
    return barindicator(s, outnames(colname(column), name, (:fastk, :fastd)), column)
end

# ---------------------------------------------------------------------------
# ULTOSC

struct ULTOSCSpec
    periods::NTuple{3,Int}
end

mutable struct ULTOSCKernel{W1,W2,W3,T}
    const periods::NTuple{3,Int}
    const w1::W1
    const w2::W2
    const w3::W3
    n::Int
    prevclose::T
    nullrun::Int
end

function barkernel(s::ULTOSCSpec, ::Type{T}) where {T}
    w1, w2, w3 = map(p -> sumswindow((:bp, :tr), p, T), s.periods)
    return ULTOSCKernel(s.periods, w1, w2, w3, 0, zero(T), 0)
end
function CausalFrames.fresh!(k::ULTOSCKernel{W1,W2,W3,T}) where {W1,W2,W3,T}
    fresh!(k.w1)
    fresh!(k.w2)
    fresh!(k.w3)
    k.n = 0
    k.prevclose = zero(T)
    k.nullrun = 0
    return k
end

# One period's buying pressure over its true range, 0 for a window with no
# range or one ultosc.c's run of null bars zeroes.
@inline function ultratio(sums, nullrun, p)
    a, b = sums
    (nullrun >= p || !(b > 0)) && return zero(a / b)
    return a / b
end

@inline function barstep!(k::ULTOSCKernel{W1,W2,W3,T}, h::T, l::T,
    c::T) where {W1,W2,W3,T}
    n = k.n += 1
    cy = k.prevclose
    k.prevclose = c
    n == 1 && return nothing
    bp = c - min(l, cy)
    tr = truerange(h, l, cy)
    term = (bp = bp, tr = tr)
    update!(k.w1, term)
    update!(k.w2, term)
    update!(k.w3, term)
    p1, p2, p3 = k.periods
    k.nullrun = tr == 0 && bp == 0 ? min(k.nullrun + 1, p3) : 0
    s3 = value(k.w3).sums
    ismissing(s3) && return nothing
    s1 = value(k.w1).sums::Tuple{T,T}
    s2 = value(k.w2).sums::Tuple{T,T}
    nr = k.nullrun
    v = 4 * ultratio(s1, nr, p1) + 2 * ultratio(s2, nr, p2) + ultratio(s3, nr, p3)
    return (100 * (v / 7),)
end

"""
    ULTOSC(; high = :high, low = :low, close = :close, timeperiod1 = 7,
           timeperiod2 = 14, timeperiod3 = 28, name = :ultosc)

TA-Lib's `ULTOSC`, Williams' ultimate oscillator, in `:ultosc`. Each bar's
buying pressure `close − min(low, previous close)` is summed over each period
and divided by the summed true range. The three ratios are weighted 4, 2 and 1
from the shortest period to the longest, as TA-Lib sorts them, and scaled to
100. A ratio over no range counts 0. The lookback is the longest period.

The window sums are CausalFrames `Sum`s under `CausalFrames.barwindow`.

$PRICEBAR_DOC
$DAILY_DOC
TA-Lib: `ta_codegen/input/ultosc/ultosc.yaml`, `ultosc.md`.
"""
function ULTOSC(; high::ColumnSpec = :high, low::ColumnSpec = :low,
    close::ColumnSpec = :close, timeperiod1::Integer = 7, timeperiod2::Integer = 14,
    timeperiod3::Integer = 28, name::Symbol = :ultosc)
    checkrange("ULTOSC", "timeperiod1", timeperiod1, 1, 100_000)
    checkrange("ULTOSC", "timeperiod2", timeperiod2, 1, 100_000)
    checkrange("ULTOSC", "timeperiod3", timeperiod3, 1, 100_000)
    ps = Tuple(sort([Int(timeperiod1), Int(timeperiod2), Int(timeperiod3)]))
    return barindicator(ULTOSCSpec(ps), (name,), high, low, close)
end

# ---------------------------------------------------------------------------
# MFI

struct MFISpec
    period::Int
end

mutable struct MFIKernel{W,T}
    const period::Int
    const window::W
    n::Int
    prevtp::T
    nullrun::Int
end

barkernel(s::MFISpec, ::Type{T}) where {T} =
    MFIKernel(s.period, sumswindow((:pos, :neg), s.period, T), 0, zero(T), 0)
function CausalFrames.fresh!(k::MFIKernel{W,T}) where {W,T}
    fresh!(k.window)
    k.n = 0
    k.prevtp = zero(T)
    k.nullrun = 0
    return k
end

@inline function barstep!(k::MFIKernel{W,T}, h::T, l::T, c::T, v::T) where {W,T}
    tp = (h + l + c) / 3
    n = k.n += 1
    prev = k.prevtp
    k.prevtp = tp
    n == 1 && return nothing
    d = tp - prev
    # mfi.c: a move TA-Lib finds zero carries no flow, and a falling bar's flow
    # is negative.
    mf = iszeroscaled(d, abs(tp) + abs(prev)) ? zero(T) : tp * v
    pos, neg = d < 0 ? (zero(T), mf) : (mf, zero(T))
    update!(k.window, (pos = pos, neg = neg))
    k.nullrun = mf == 0 ? min(k.nullrun + 1, k.period) : 0
    sums = value(k.window).sums
    ismissing(sums) && return nothing
    # A window of null bars has exactly zero flow, whatever round-off the
    # sliding sums hold (mfi.c's nullRun).
    p, q = k.nullrun >= k.period ? (zero(T), zero(T)) : sums
    total = p + q
    pc = p < 0 ? zero(T) : p > total ? total : p
    return (total <= 0 ? zero(T) : 100 * (pc / total),)
end

"""
    MFI(; high = :high, low = :low, close = :close, volume = :volume, period = 14,
        name = :mfi)

TA-Lib's `MFI`, the money flow index, in `:mfi`. Each bar's money flow is its
typical price `(high + low + close)/3` times its volume, positive when the
typical price rose from the previous bar and negative when it fell. A move
TA-Lib finds zero carries no flow. The index is `100·pos/(pos + neg)` over the
last `period` bars, or 0 when there is no flow. The lookback is `period`.

The flow sums are CausalFrames `Sum`s under `CausalFrames.barwindow`.

$PRICEBAR_DOC
$DAILY_DOC
TA-Lib: `ta_codegen/input/mfi/mfi.yaml`, `mfi.md`.
"""
function MFI(; high::ColumnSpec = :high, low::ColumnSpec = :low, close::ColumnSpec = :close,
    volume::ColumnSpec = :volume, period::Integer = 14, name::Symbol = :mfi)
    checkrange("MFI", "period", period, 2, 100_000)
    return barindicator(MFISpec(period), (name,), high, low, close, volume)
end

# ---------------------------------------------------------------------------
# Directional movement: ±DM, ±DI, DX, ADX and ADXR

# `K` is `:plusdm`, `:minusdm`, `:plusdi`, `:minusdi`, `:dx`, `:adx` or
# `:adxr`.
struct DirectionalSpec{K}
    period::Int
    unstable::Int
end

mutable struct DirectionalKernel{K,D,S,A,T}
    const dm::D
    const unstable::Int
    const invperiod::T
    const adxseed::S
    const lag::A
    ndx::Int
    lastdx::T
    adx::T
end

function barkernel(s::DirectionalSpec{K}, ::Type{T}) where {K,T}
    dm = DMKernel(T, s.period)
    lag = K === :adxr ? lagged(s.period, T) : nothing
    seed = seedsum(T)
    return DirectionalKernel{K,typeof(dm),typeof(seed),typeof(lag),T}(dm, s.unstable,
        one(T) / T(s.period), seed, lag, 0, zero(T), zero(T))
end
function CausalFrames.fresh!(k::DirectionalKernel{K,D,S,A,T}) where {K,D,S,A,T}
    fresh!(k.dm)
    fresh!(k.adxseed)
    maybefresh!(k.lag)
    k.ndx = 0
    k.lastdx = k.adx = zero(T)
    return k
end

# The DMs read no close; the low stands in for it in the unused true range.
@inline barstep!(k::DirectionalKernel{K}, h::T, l::T) where {K,T} =
    (step!(k.dm, h, l, l); directional!(Val(K), k))
@inline barstep!(k::DirectionalKernel{K}, h::T, l::T, c::T) where {K,T} =
    (step!(k.dm, h, l, c); directional!(Val(K), k))

# ta_PLUS_DM.c: the smoothed sum, or the raw DM at period 1, whose lookback
# ignores the unstable period.
function directional!(::Union{Val{:plusdm},Val{:minusdm}},
    k::DirectionalKernel{K}) where {K}
    dm = k.dm
    p = dm.period
    lb = p == 1 ? 1 : p - 1 + k.unstable
    nseen(dm) > lb || return nothing
    pdm, mdm, _ = dmsums(dm)
    return (K === :plusdm ? pdm : mdm,)
end

# ta_PLUS_DI.c: `100·DM/TR`, or at period 1 the bar's `DM/TR` without the 100,
# TA-Lib's historical quirk; 0 where there is no range.
function directional!(::Union{Val{:plusdi},Val{:minusdi}},
    k::DirectionalKernel{K,D,S,A,T}) where {K,D,S,A,T}
    dm = k.dm
    p = dm.period
    lb = p == 1 ? 1 : p + k.unstable
    nseen(dm) > lb || return nothing
    pdm, mdm, tr = dmsums(dm)
    v = K === :plusdi ? pdm : mdm
    if p == 1
        return (v > 0 ? (tr <= 0 ? zero(T) : v / tr) : zero(T),)
    end
    return (tr > 0 ? 100 * (v / tr) : zero(T),)
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
function directional!(::Val{:dx}, k::DirectionalKernel)
    dm = k.dm
    nseen(dm) > dm.period + k.unstable || return nothing
    ok, dx = dxvalue(dmsums(dm))
    ok && (k.lastdx = dx)
    return (k.lastdx,)
end

# ta_ADX.c: the mean of the first `period` DX values (a guarded one adds
# nothing), then `adx − (adx − dx)/period`, held on a guarded bar. Returns
# whether the ADX is past its lookback and unstable period.
function adxstep!(k::DirectionalKernel)
    dm = k.dm
    p = dm.period
    nseen(dm) > p || return false
    n = k.ndx += 1
    ok, dx = dxvalue(dmsums(dm))
    if n <= p
        ok && seedadd!(k.adxseed, dx)
        n == p && (k.adx = seedtotal(k.adxseed) / p)
    elseif ok
        k.adx = k.adx - (k.adx - dx) * k.invperiod
    end
    return n >= p + k.unstable
end

directional!(::Val{:adx}, k::DirectionalKernel) = adxstep!(k) ? (k.adx,) : nothing

# ta_ADXR.c: the mean of today's ADX and the one `period − 1` bars back, read
# from a CausalFrames `First` over the last `period` ADX values.
function directional!(::Val{:adxr}, k::DirectionalKernel)
    adxstep!(k) || return nothing
    update!(k.lag, (x = k.adx,))
    old = value(k.lag).x_first
    return ismissing(old) ? nothing : ((k.adx + old) / 2,)
end

function directional(fn, K, high, low, close, period, unstable, name; minperiod)
    checkrange(fn, "period", period, minperiod, 100_000)
    checkunstable(unstable)
    specs = close === nothing ? (high, low) : (high, low, close)
    return barindicator(DirectionalSpec{K}(period, unstable), (name,), specs...)
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

"""
    PlusDM(; high = :high, low = :low, period = 14, unstable = 0, name = :plusdm)

TA-Lib's `PLUS_DM`, the smoothed +DM, in `:plusdm`. The lookback is
`period − 1`, plus `unstable`, TA-Lib's unstable period. At period 1 it is the
bar's raw +DM with lookback 1, whatever `unstable` is.

$DM_DOC
$PRICEBAR_DOC

$DAILY_DOC
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
$PRICEBAR_DOC

$DAILY_DOC
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
$PRICEBAR_DOC

$DAILY_DOC
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
$PRICEBAR_DOC

$DAILY_DOC
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
$PRICEBAR_DOC

$DAILY_DOC
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
$PRICEBAR_DOC

$DAILY_DOC
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
$PRICEBAR_DOC

$DAILY_DOC
TA-Lib: `ta_codegen/input/adxr/adxr.yaml`, `adxr.md`.
"""
ADXR(; high::ColumnSpec = :high, low::ColumnSpec = :low, close::ColumnSpec = :close,
    period::Integer = 14, unstable::Integer = 0, name::Symbol = :adxr) =
    directional("ADXR", :adxr, high, low, close, period, unstable, name; minperiod = 2)

# ---------------------------------------------------------------------------
# The TA-Lib 0.8 additions (S5). QStick, IMI and FOSC are dependents over
# CausalFrames accumulators; the rest are `BarIndicator`s over the kernels
# below, whose windows are CausalFrames states under `barwindow`.

# The body of a candle, QStick's hidden row term `:qstick_body`.
struct CandleBody{O,C} <: Function end
@inline (::CandleBody{O,C})(r) where {O,C} =
    lifted(-)(getproperty(r, C), getproperty(r, O))

"""
    QStick(; open = :open, close = :close) -> Summarizer

TA-Lib's `QSTICK`, Chande and Kroll's Qstick, in `:qstick`: the window's mean
candle body `close − open`. It is a dependent over CausalFrames' `Mean` of the
row term `:qstick_body` (Group tier), so two `QStick`s over different columns
cannot share a call. TA-Lib's `QSTICK(period = p)` is `QStick()` under
`Bars(p)`.

TA-Lib: `ta_codegen/input/qstick/qstick.yaml`, `qstick.md`.
"""
struct QStick{O,C} <: GroupSummarizer end
QStick(; open::ColumnSpec = :open, close::ColumnSpec = :close) =
    qstick(colname(open), colname(close), open, close)
qstick(O, C, specs...) =
    withterms(QStick{O,C}(), specs..., :qstick_body => CandleBody{O,C}())

CausalFrames.dependencies(::QStick) = (Mean(:qstick_body),)
CausalFrames.emptyvalue(::QStick) = (; qstick = missing)
CausalFrames.fresh(::QStick, ::NamedTuple) =
    derivedvalue(:qstick, (:qstick_body_mean,), identity)

# IMI's hidden row terms: the body of an up candle (`:up`), and of a down or
# flat one (`:dn`), as ta_IMI.c splits them.
struct IMITerm{K,O,C} <: Function end
@inline (::IMITerm{K,O,C})(r) where {K,O,C} =
    lifted(imiterm(Val(K)))(getproperty(r, O), getproperty(r, C))

@inline imiup(o, c) = c > o ? c - o : zero(c - o)
@inline imidn(o, c) = c > o ? zero(o - c) : o - c
imiterm(::Val{:up}) = imiup
imiterm(::Val{:dn}) = imidn

"""
    IMI(; open = :open, close = :close) -> Summarizer

TA-Lib's `IMI`, Chande's intraday momentum index, in `:imi`: the window's up
candle bodies as a percentage of all its bodies, `100·up/(up + down)`, where a
flat candle counts as down. A window of flat candles gives 50. It is a
dependent over CausalFrames' `Sum` of the row terms `:imi_up` and `:imi_dn`
(Group tier), so two `IMI`s over different columns cannot share a call.
TA-Lib's `IMI(period = p)` is `IMI()` under `Bars(p)`.

TA-Lib: `ta_codegen/input/imi/imi.yaml`, `imi.md`.
"""
struct IMI{O,C} <: GroupSummarizer end
IMI(; open::ColumnSpec = :open, close::ColumnSpec = :close) =
    imi(colname(open), colname(close), open, close)
imi(O, C, specs...) = withterms(IMI{O,C}(), specs..., :imi_up => IMITerm{:up,O,C}(),
    :imi_dn => IMITerm{:dn,O,C}())

CausalFrames.dependencies(::IMI) = (Sum(:imi_up), Sum(:imi_dn))
CausalFrames.emptyvalue(::IMI) = (; imi = missing)
CausalFrames.fresh(::IMI, ::NamedTuple) =
    derivedvalue(:imi, (:imi_up_sum, :imi_dn_sum), lifted(imivalue))

function imivalue(up, dn)
    t = up + dn
    return t == 0 ? oftype(up / t, 50) : 100 * (up / t)
end

"""
    FOSC(column::ColumnSpec) -> Summarizer

TA-Lib's `FOSC`, the forecast oscillator, in `:{column}_fosc`: the percentage
`100·(x − f)/x` by which the newest value `x` misses the forecast `f` the
previous bar's [`TSF`](@ref) made for it, or 0 at `x = 0`. The forecast is the
least-squares line through the window's other values, extended one bar, so it
is a dependent over CausalFrames' `Count`, `Sum`, `AgeWeightedSum` and `Last`
(Group tier), which it shares with the `LINEARREG` family. TA-Lib's regression
covers the `period` bars before the current one, so the window holds
`period + 1`: TA-Lib's `period = p` is `Bars(p + 1)`, and its lookback `p` is
the window's partial-window rule.

TA-Lib: `ta_codegen/input/fosc/fosc.yaml`, `fosc.md`.
"""
struct FOSC{C} <: GroupSummarizer end
FOSC(column::ColumnSpec) = withterms(FOSC{colname(column)}(), column)

CausalFrames.dependencies(::FOSC{C}) where {C} =
    (Count(), Sum(C), AgeWeightedSum(C), Last(C))
CausalFrames.emptyvalue(::FOSC{C}) where {C} = missings((Symbol(C, :_fosc),))
CausalFrames.fresh(::FOSC{C}, ::NamedTuple) where {C} =
    derivedvalue(Symbol(C, :_fosc),
        (:count, Symbol(C, :_sum), Symbol(C, :_ageweightedsum), lastname(C)),
        lifted(foscvalue))

# The window without its newest bar `x` holds `n − 1` bars, its sum is `s − x`,
# and their ages fall by one, so their age-weighted sum is `a − (s − x)`.
function foscvalue(n, s, a, x)
    so = s - x
    m, b = regline(n - 1, so, a - so)
    f = b + m * (n - 1)
    return x != 0 ? 100 * (x - f) / x : zero(f)
end

# ---------------------------------------------------------------------------
# The S5 kernels

# AO and AC: Williams' awesome and accelerator oscillators, the spread of two
# SMAs of the median price, and its distance from its own SMA.
struct AOSpec
    fast::Int
    slow::Int
    signal::Int
end

mutable struct AOKernel{F,S,G}
    const fast::F
    const slow::S
    const signal::G
end

function barkernel(s::AOSpec, ::Type{T}) where {T}
    sig = s.signal == 0 ? nothing : SMAKernel(T, s.signal)
    f, sl = SMAKernel(T, s.fast), SMAKernel(T, s.slow)
    return AOKernel(f, sl, sig)
end
function CausalFrames.fresh!(k::AOKernel)
    fresh!(k.fast)
    fresh!(k.slow)
    maybefresh!(k.signal)
    return k
end

@inline function barstep!(k::AOKernel{F,S,G}, h::T, l::T) where {F,S,G,T}
    m = (h + l) / 2
    f = step!(k.fast, m)
    s = step!(k.slow, m)
    (ismissing(f) || ismissing(s)) && return nothing
    ao = f - s
    G === Nothing && return (ao,)
    sig = step!(k.signal, ao)
    return ismissing(sig) ? nothing : (ao - sig,)
end

"""
    AO(; high = :high, low = :low, fastperiod = 5, slowperiod = 34, name = :ao)

TA-Lib's `AO`, Williams' awesome oscillator, in `:ao`: the `fastperiod` SMA of
the median price `(high + low)/2` minus its `slowperiod` SMA. The periods are
not swapped, so `fastperiod > slowperiod` gives `−AO`. The lookback is the
longer period minus 1. The averages are CausalFrames `Mean`s under
`CausalFrames.barwindow`.

$PRICEBAR_DOC

$DAILY_DOC
TA-Lib: `ta_codegen/input/ao/ao.yaml`, `ao.md`.
"""
function AO(; high::ColumnSpec = :high, low::ColumnSpec = :low, fastperiod::Integer = 5,
    slowperiod::Integer = 34, name::Symbol = :ao)
    checkrange("AO", "fastperiod", fastperiod, 2, 100_000)
    checkrange("AO", "slowperiod", slowperiod, 2, 100_000)
    return barindicator(AOSpec(fastperiod, slowperiod, 0), (name,), high, low)
end

"""
    AC(; high = :high, low = :low, fastperiod = 5, slowperiod = 34, signalperiod = 5,
       name = :ac)

TA-Lib's `AC`, Williams' accelerator/decelerator oscillator, in `:ac`: the
awesome oscillator (as [`AO`](@ref)) minus its own `signalperiod` SMA. The
lookback is the longer of `fastperiod` and `slowperiod`, plus `signalperiod`,
minus 2.

$PRICEBAR_DOC

$DAILY_DOC
TA-Lib: `ta_codegen/input/ac/ac.yaml`, `ac.md`.
"""
function AC(; high::ColumnSpec = :high, low::ColumnSpec = :low, fastperiod::Integer = 5,
    slowperiod::Integer = 34, signalperiod::Integer = 5, name::Symbol = :ac)
    checkrange("AC", "fastperiod", fastperiod, 2, 100_000)
    checkrange("AC", "slowperiod", slowperiod, 2, 100_000)
    checkrange("AC", "signalperiod", signalperiod, 2, 100_000)
    return barindicator(AOSpec(fastperiod, slowperiod, signalperiod), (name,), high, low)
end

# CMOU: Chande's unsmoothed momentum oscillator, over window sums of the up and
# down moves.
struct CMOUSpec
    period::Int
end

mutable struct CMOUKernel{T,W}
    const period::Int
    n::Int
    prev::T
    nullrun::Int
    const window::W
end

function barkernel(s::CMOUSpec, ::Type{T}) where {T}
    w = sumswindow((:up, :dn), s.period, T)
    return CMOUKernel{T,typeof(w)}(s.period, 0, zero(T), 0, w)
end
function CausalFrames.fresh!(k::CMOUKernel{T}) where {T}
    k.n = 0
    k.prev = zero(T)
    k.nullrun = 0
    fresh!(k.window)
    return k
end

@inline function barstep!(k::CMOUKernel{T}, x::T) where {T}
    prev = k.prev
    k.prev = x
    (k.n += 1) == 1 && return nothing
    d = x - prev
    up, dn = d > 0 ? (d, zero(T)) : d < 0 ? (zero(T), -d) : (zero(T), zero(T))
    update!(k.window, (up = up, dn = dn))
    k.nullrun = d == 0 ? min(k.nullrun + 1, k.period) : 0
    sums = value(k.window).sums
    ismissing(sums) && return nothing
    # A window of exactly flat moves sums to exactly zero, whatever round-off
    # the sliding sums hold (ta_CMOU.c's nullRun).
    u, w = k.nullrun >= k.period ? (zero(T), zero(T)) : sums::Tuple{T,T}
    t = u + w
    return (t > 0 ? (100 * (u - w)) / t : zero(T),)
end

"""
    CMOU(column::ColumnSpec; period = 14, name = :cmou)

TA-Lib's `CMOU`, Chande's original (unsmoothed) momentum oscillator, in
`:{column}_cmou`: over the last `period` bar-to-bar changes, the sum of the
rises `u` and of the falls `d` give `100·(u − d)/(u + d)`, or 0 for a flat
window. Unlike [`CMO`](@ref) the sums are plain window sums, CausalFrames
`Sum`s under `CausalFrames.barwindow`, so there is no unstable period. The
lookback is `period`.

$PRICEBAR_DOC

$DAILY_DOC
TA-Lib: `ta_codegen/input/cmou/cmou.yaml`, `cmou.md`.
"""
function CMOU(column::ColumnSpec; period::Integer = 14, name::Symbol = :cmou)
    checkrange("CMOU", "period", period, 2, 100_000)
    return barindicator(CMOUSpec(period), (outname(colname(column), name),), column)
end

# ER: Kaufman's efficiency ratio, the `ERKernel` KAMA embeds.
struct ERSpec
    period::Int
end

mutable struct ERIndicatorKernel{E}
    const er::E
end

barkernel(s::ERSpec, ::Type{T}) where {T} = (e = ERKernel(T, s.period);
    ERIndicatorKernel{typeof(e)}(e))
CausalFrames.fresh!(k::ERIndicatorKernel) = (fresh!(k.er); k)

@inline function barstep!(k::ERIndicatorKernel, x::T) where {T}
    e = step!(k.er, x)
    return ismissing(e) ? nothing : (e::T,)
end

"""
    ER(column::ColumnSpec; period = 10, name = :er)

TA-Lib's `ER`, Kaufman's efficiency ratio, in `:{column}_er`: the net move over
the last `period` bars, `|x − x[t − period]|`, over the path travelled, the sum
of the `period` bar-to-bar moves `|Δx|`, in [0, 1]. A straight-line advance
and a flat window give exactly 1. It is the ratio [`KAMA`](@ref) adapts to,
from the same kernel. The lookback is `period`.

$PRICEBAR_DOC

$DAILY_DOC
TA-Lib: `ta_codegen/input/er/er.yaml`, `er.md`.
"""
function ER(column::ColumnSpec; period::Integer = 10, name::Symbol = :er)
    checkrange("ER", "period", period, 2, 100_000)
    return barindicator(ERSpec(period), (outname(colname(column), name),), column)
end

# VHF: White's vertical horizontal filter, the range of the newest `period`
# values over the sum of the `period` moves before them.
struct VHFSpec
    period::Int
end

mutable struct VHFKernel{T,X,S}
    const period::Int
    n::Int
    prev::T
    nullrun::Int
    const extremes::X
    const path::S
end

function barkernel(s::VHFSpec, ::Type{T}) where {T}
    x = extremeswindow(s.period, T)
    p = CausalFrames.barwindow(Sum(:x), s.period, (x = T,))
    return VHFKernel{T,typeof(x),typeof(p)}(s.period, 0, zero(T), 0, x, p)
end
function CausalFrames.fresh!(k::VHFKernel{T}) where {T}
    k.n = 0
    k.prev = zero(T)
    k.nullrun = 0
    fresh!(k.extremes)
    fresh!(k.path)
    return k
end

@inline function barstep!(k::VHFKernel{T}, x::T) where {T}
    prev = k.prev
    k.prev = x
    update!(k.extremes, (high = x, low = x))
    (k.n += 1) == 1 && return nothing
    d = x - prev
    update!(k.path, (x = abs(d),))
    k.nullrun = d == 0 ? min(k.nullrun + 1, k.period) : 0
    k.n > k.period || return nothing
    hi, lo = value(k.extremes).extremes::Tuple{T,T}
    s = k.nullrun >= k.period ? zero(T) : value(k.path).x_sum::T
    return (s > 0 ? (hi - lo) / s : zero(T),)
end

"""
    VHF(column::ColumnSpec; period = 28, name = :vhf)

TA-Lib's `VHF`, White's vertical horizontal filter, in `:{column}_vhf`: the
range (highest minus lowest) of the newest `period` values over the sum of the
`period` bar-to-bar moves `|Δx|` ending at the newest, in [0, 1], or 0 for a
flat window. The extremes are CausalFrames `Max` and `Min` and the path a
`Sum`, under `CausalFrames.barwindow`. The lookback is `period`.

$PRICEBAR_DOC

$DAILY_DOC
TA-Lib: `ta_codegen/input/vhf/vhf.yaml`, `vhf.md`.
"""
function VHF(column::ColumnSpec; period::Integer = 28, name::Symbol = :vhf)
    checkrange("VHF", "period", period, 2, 100_000)
    return barindicator(VHFSpec(period), (outname(colname(column), name),), column)
end

# Vortex: Botes and Siepman's vortex lines, window sums of the vortex
# movements over the window sum of the true range.
struct VortexSpec
    period::Int
end

mutable struct VortexKernel{T,W}
    const period::Int
    n::Int
    prevh::T
    prevl::T
    prevc::T
    nullrun::Int
    const window::W
end

function barkernel(s::VortexSpec, ::Type{T}) where {T}
    w = sumswindow((:tr, :vmp, :vmm), s.period, T)
    return VortexKernel{T,typeof(w)}(s.period, 0, zero(T), zero(T), zero(T), 0, w)
end
function CausalFrames.fresh!(k::VortexKernel{T}) where {T}
    k.n = 0
    k.prevh = k.prevl = k.prevc = zero(T)
    k.nullrun = 0
    fresh!(k.window)
    return k
end

@inline function barstep!(k::VortexKernel{T}, h::T, l::T, c::T) where {T}
    ph, pl, pc = k.prevh, k.prevl, k.prevc
    k.prevh, k.prevl, k.prevc = h, l, c
    (k.n += 1) == 1 && return nothing
    tr = truerange(h, l, pc)
    update!(k.window, (tr = tr, vmp = abs(h - pl), vmm = abs(l - ph)))
    k.nullrun = tr == 0 ? min(k.nullrun + 1, k.period) : 0
    sums = value(k.window).sums
    ismissing(sums) && return nothing
    s, p, m = sums::NTuple{3,T}
    # A window of null true ranges has an exactly zero range sum (ta_VORTEX.c's
    # nullRun); the movements, which read the previous bar, stay as they are.
    k.nullrun >= k.period && (s = zero(T))
    return s > 0 ? (p / s, m / s) : (zero(T), zero(T))
end

"""
    Vortex(; high = :high, low = :low, close = :close, period = 14, name = :vortex)

TA-Lib's `VORTEX`, Botes and Siepman's vortex indicator, in `:vortex_plusvi`
and `:vortex_minusvi`: the sums over the last `period` bars of
`|high − previous low|` and of `|low − previous high|`, each over the sum of
the true range, or both 0 when that is zero. The sums are CausalFrames `Sum`s
under `CausalFrames.barwindow`. The lookback is `period`.

$PRICEBAR_DOC

$DAILY_DOC
TA-Lib: `ta_codegen/input/vortex/vortex.yaml`, `vortex.md`.
"""
function Vortex(; high::ColumnSpec = :high, low::ColumnSpec = :low,
    close::ColumnSpec = :close, period::Integer = 14, name::Symbol = :vortex)
    checkrange("Vortex", "period", period, 1, 100_000)
    return barindicator(VortexSpec(period), outnames(nothing, name, (:plusvi, :minusvi)),
        high, low, close)
end

# DPO: the detrended price oscillator, the value `period ÷ 2 + 1` bars back
# minus the `period`-bar SMA.
struct DPOSpec
    period::Int
end

mutable struct DPOKernel{S,F}
    const sma::S
    const lagged::F
end

function barkernel(s::DPOSpec, ::Type{T}) where {T}
    m = SMAKernel(T, s.period)
    f = lagged(s.period ÷ 2 + 2, T)
    return DPOKernel{typeof(m),typeof(f)}(m, f)
end
CausalFrames.fresh!(k::DPOKernel) = (fresh!(k.sma); fresh!(k.lagged); k)

@inline function barstep!(k::DPOKernel, x::T) where {T}
    m = step!(k.sma, x)
    update!(k.lagged, (x = x,))
    old = value(k.lagged).x_first
    (ismissing(m) || ismissing(old)) && return nothing
    return (old::T - m::T,)
end

"""
    DPO(column::ColumnSpec; period = 20, name = :dpo)

TA-Lib's `DPO`, the detrended price oscillator, in `:{column}_dpo`: the value
`period ÷ 2 + 1` bars back minus the `period`-bar SMA, written at the bar whose
average produced it (charting packages usually draw it shifted back). The
lookback is the larger of `period − 1` and `period ÷ 2 + 1`. The SMA is a
CausalFrames `Mean` and the lagged value a `First`, under
`CausalFrames.barwindow`.

$PRICEBAR_DOC

$DAILY_DOC
TA-Lib: `ta_codegen/input/dpo/dpo.yaml`, `dpo.md`.
"""
function DPO(column::ColumnSpec; period::Integer = 20, name::Symbol = :dpo)
    checkrange("DPO", "period", period, 2, 100_000)
    return barindicator(DPOSpec(period), (outname(colname(column), name),), column)
end

# Coppock: the WMA of the sum of two ROCs.
struct CoppockSpec
    wma::Int
    roc1::Int
    roc2::Int
end

mutable struct CoppockKernel{F1,F2,W}
    const lag1::F1
    const lag2::F2
    const wma::W
end

function barkernel(s::CoppockSpec, ::Type{T}) where {T}
    f1 = lagged(s.roc1 + 1, T)
    f2 = lagged(s.roc2 + 1, T)
    w = WMAKernel(T, s.wma)
    return CoppockKernel{typeof(f1),typeof(f2),typeof(w)}(f1, f2, w)
end
CausalFrames.fresh!(k::CoppockKernel) = (fresh!(k.lag1); fresh!(k.lag2); fresh!(k.wma); k)

@inline function barstep!(k::CoppockKernel, x::T) where {T}
    update!(k.lag1, (x = x,))
    update!(k.lag2, (x = x,))
    a, b = value(k.lag1).x_first, value(k.lag2).x_first
    (ismissing(a) || ismissing(b)) && return nothing
    v = step!(k.wma, rocvalue(a::T, x) + rocvalue(b::T, x))
    return ismissing(v) ? nothing : (v::T,)
end

"""
    Coppock(column::ColumnSpec; wmaperiod = 10, roc1period = 11, roc2period = 14,
            name = :coppock)

TA-Lib's `COPPOCK`, the Coppock curve, in `:{column}_coppock`: the
`wmaperiod`-bar [`WMA`](@ref) of the sum (not the mean) of the `roc1period`-
and `roc2period`-bar [`ROC`](@ref)s, each 0 over a zero base. The lookback is
the longer ROC period plus `wmaperiod − 1`. The lagged values are CausalFrames
`First`s, and the WMA the package's `WMA` dependent, under
`CausalFrames.barwindow`. Coppock designed the curve for monthly bars, and
TA-Lib's defaults are his month counts: on daily bars they span weeks, not
the year and more he intended.

$PRICEBAR_DOC
TA-Lib: `ta_codegen/input/coppock/coppock.yaml`, `coppock.md`.
"""
function Coppock(column::ColumnSpec; wmaperiod::Integer = 10, roc1period::Integer = 11,
    roc2period::Integer = 14, name::Symbol = :coppock)
    checkrange("Coppock", "wmaperiod", wmaperiod, 1, 100_000)
    checkrange("Coppock", "roc1period", roc1period, 1, 100_000)
    checkrange("Coppock", "roc2period", roc2period, 1, 100_000)
    return barindicator(CoppockSpec(wmaperiod, roc1period, roc2period),
        (outname(colname(column), name),), column)
end

# ERI: Elder's bull and bear power, the high and the low less one EMA of the
# close.
struct ERISpec
    period::Int
    unstable::Int
end

mutable struct ERIKernel{E}
    const unstable::Int
    const ema::E
end

barkernel(s::ERISpec, ::Type{T}) where {T} =
    (e = EMAKernel(T, s.period); ERIKernel{typeof(e)}(s.unstable, e))
CausalFrames.fresh!(k::ERIKernel) = (fresh!(k.ema); k)

@inline function barstep!(k::ERIKernel, h::T, l::T, c::T) where {T}
    e = step!(k.ema, c)
    emitted(k.ema, k.unstable) || return nothing
    return (h - e::T, l - e::T)
end

"""
    ERI(; high = :high, low = :low, close = :close, period = 13, unstable = 0,
        name = :eri)

TA-Lib's `ERI`, Elder's ray index, in `:eri_bullpower` and `:eri_bearpower`:
the high and the low less the `period`-bar EMA of the close. The lookback is
`period − 1` plus `unstable`, EMA's unstable period, which TA-Lib's ERI
inherits; it delays the first output without changing the values.

$PRICEBAR_DOC

$DAILY_DOC
TA-Lib: `ta_codegen/input/eri/eri.yaml`, `eri.md`.
"""
function ERI(; high::ColumnSpec = :high, low::ColumnSpec = :low, close::ColumnSpec = :close,
    period::Integer = 13, unstable::Integer = 0, name::Symbol = :eri)
    checkrange("ERI", "period", period, 1, 100_000)
    return barindicator(ERISpec(period, checkunstable(unstable)),
        outnames(nothing, name, (:bullpower, :bearpower)), high, low, close)
end

# Blau's double smoothing (SMI and TSI): a numerator and a denominator, each
# through two chained EMAs. Each stage feeds the next from the bar it has
# passed its unstable period, as ta_SMI.c and ta_TSI.c chain the callee
# lookbacks; the denominators are EMAs of non-negative terms.
mutable struct BlauKernel{E}
    const unstable::Int
    const num1::E
    const den1::E
    const num2::E
    const den2::E
end

function BlauKernel(::Type{T}, first::Integer, second::Integer, unstable::Int) where {T}
    e1, e2 = EMAKernel(T, first), EMAKernel(T, second)
    return BlauKernel{typeof(e1)}(unstable, e1, fresh(e1), e2, fresh(e2))
end
function CausalFrames.fresh!(k::BlauKernel)
    fresh!(k.num1)
    fresh!(k.den1)
    fresh!(k.num2)
    fresh!(k.den2)
    return k
end

# The doubly smoothed pair after folding `num` and `den`, or `nothing` until the
# second stage has passed its unstable period.
@inline function blaustep!(k::BlauKernel, num::T, den::T) where {T}
    n1 = step!(k.num1, num)
    d1 = step!(k.den1, den)
    emitted(k.num1, k.unstable) || return nothing
    n2 = step!(k.num2, n1::T)
    d2 = step!(k.den2, d1::T)
    emitted(k.num2, k.unstable) || return nothing
    return (n2::T, d2::T)
end

struct TSISpec
    first::Int
    second::Int
    unstable::Int
end

mutable struct TSIKernel{T,B}
    n::Int
    prev::T
    const blau::B
end

barkernel(s::TSISpec, ::Type{T}) where {T} =
    (
        b = BlauKernel(T, s.first, s.second, s.unstable);
        TSIKernel{T,typeof(b)}(0, zero(T), b)
    )
CausalFrames.fresh!(k::TSIKernel{T}) where {T} =
    (k.n = 0; k.prev = zero(T); fresh!(k.blau); k)

@inline function barstep!(k::TSIKernel{T}, x::T) where {T}
    prev = k.prev
    k.prev = x
    (k.n += 1) == 1 && return nothing
    m = x - prev
    nd = blaustep!(k.blau, m, abs(m))
    nd === nothing && return nothing
    n, d = nd
    return (d > 0 ? (100 * n) / d : zero(T),)
end

"""
    TSI(column::ColumnSpec; firstperiod = 25, secondperiod = 13, unstable = 0,
        name = :tsi)

TA-Lib's `TSI`, Blau's true strength index, in `:{column}_tsi`: the bar-to-bar
change and its magnitude are each smoothed by a `firstperiod` EMA and then a
`secondperiod` EMA, and the index is `100·change/magnitude`, or 0 where every
change was zero. The periods apply in that order; they do not commute.
`unstable` is EMA's unstable period, which TA-Lib's TSI inherits: each stage
passes it before it feeds the next, so it changes the values, not only the
first bar. The lookback is `1 + (firstperiod − 1) + (secondperiod − 1)` plus
twice `unstable`.

$PRICEBAR_DOC

$DAILY_DOC
TA-Lib: `ta_codegen/input/tsi/tsi.yaml`, `tsi.md`.
"""
function TSI(column::ColumnSpec; firstperiod::Integer = 25, secondperiod::Integer = 13,
    unstable::Integer = 0, name::Symbol = :tsi)
    checkrange("TSI", "firstperiod", firstperiod, 2, 100_000)
    checkrange("TSI", "secondperiod", secondperiod, 2, 100_000)
    return barindicator(TSISpec(firstperiod, secondperiod, checkunstable(unstable)),
        (outname(colname(column), name),), column)
end

struct SMISpec
    period::Int
    fast::Int
    slow::Int
    signal::Int
    unstable::Int
end

mutable struct SMIKernel{X,B,E}
    const unstable::Int
    const extremes::X
    const blau::B
    const signal::E
end

function barkernel(s::SMISpec, ::Type{T}) where {T}
    x = extremeswindow(s.period, T)
    b = BlauKernel(T, s.slow, s.fast, s.unstable)
    e = EMAKernel(T, s.signal)
    return SMIKernel{typeof(x),typeof(b),typeof(e)}(s.unstable, x, b, e)
end
CausalFrames.fresh!(k::SMIKernel) =
    (fresh!(k.extremes); fresh!(k.blau); fresh!(k.signal); k)

@inline function barstep!(k::SMIKernel, h::T, l::T, c::T) where {T}
    update!(k.extremes, (high = h, low = l))
    ext = value(k.extremes).extremes
    ismissing(ext) && return nothing
    hh, ll = ext::Tuple{T,T}
    nd = blaustep!(k.blau, c - (hh + ll) * T(0.5), hh - ll)
    nd === nothing && return nothing
    n, d = nd
    half = T(0.5) * d
    smi = half > 0 ? (100 * n) / half : zero(T)
    sig = step!(k.signal, smi)
    emitted(k.signal, k.unstable) || return nothing
    return (smi, sig::T)
end

"""
    SMI(; high = :high, low = :low, close = :close, period = 13, fastperiod = 2,
        slowperiod = 25, signalperiod = 9, unstable = 0, name = :smi)

TA-Lib's `SMI`, Blau's stochastic momentum index, in `:smi_smi` and
`:smi_smisignal`. Over the `period`-bar high-low range, the close's distance
from the range's midpoint and the range itself are each smoothed by a
`slowperiod` EMA and then a `fastperiod` EMA, and the index is
`100·distance/(range/2)`, in [−100, 100], or 0 where every range was zero. The
signal is its `signalperiod` EMA, and both outputs start with it. The extremes
are CausalFrames `Max` and `Min` under `CausalFrames.barwindow`. `unstable` is
EMA's unstable period, which TA-Lib's SMI inherits: each of the three EMA
stages passes it before it feeds the next.

$PRICEBAR_DOC

$DAILY_DOC
TA-Lib: `ta_codegen/input/smi/smi.yaml`, `smi.md`.
"""
function SMI(; high::ColumnSpec = :high, low::ColumnSpec = :low, close::ColumnSpec = :close,
    period::Integer = 13, fastperiod::Integer = 2, slowperiod::Integer = 25,
    signalperiod::Integer = 9, unstable::Integer = 0, name::Symbol = :smi)
    checkrange("SMI", "period", period, 2, 100_000)
    checkrange("SMI", "fastperiod", fastperiod, 2, 100_000)
    checkrange("SMI", "slowperiod", slowperiod, 2, 100_000)
    checkrange("SMI", "signalperiod", signalperiod, 2, 100_000)
    s = SMISpec(period, fastperiod, slowperiod, signalperiod, checkunstable(unstable))
    return barindicator(s, outnames(nothing, name, (:smi, :smisignal)), high, low, close)
end

"""
    KDJ(; high = :high, low = :low, close = :close, fastkperiod = 9, slowkperiod = 3,
        slowkmatype = :rma, slowdperiod = 3, slowdmatype = :rma, unstable = 0,
        name = :kdj)

TA-Lib's `KDJ`, the stochastic as Chinese-market platforms draw it, in
`:kdj_k`, `:kdj_d` and `:kdj_j`: K and D are [`Stoch`](@ref)'s slow %K and slow
%D, smoothed by Wilder's average by default, and `J = 3K − 2D`, unclamped.

$STOCH_DOC
$PLAIN_DOC

$DAILY_DOC
TA-Lib: `ta_codegen/input/kdj/kdj.yaml`, `kdj.md`.
"""
function KDJ(; high::ColumnSpec = :high, low::ColumnSpec = :low,
    close::ColumnSpec = :close, fastkperiod::Integer = 9, slowkperiod::Integer = 3,
    slowkmatype::Symbol = :rma, slowdperiod::Integer = 3, slowdmatype::Symbol = :rma,
    unstable::Integer = 0, name::Symbol = :kdj)
    checkrange("KDJ", "fastkperiod", fastkperiod, 1, 100_000)
    checkrange("KDJ", "slowkperiod", slowkperiod, 1, 100_000)
    checkrange("KDJ", "slowdperiod", slowdperiod, 1, 100_000)
    checkmatype("KDJ", "slowkmatype", slowkmatype)
    checkmatype("KDJ", "slowdmatype", slowdmatype)
    checkunstable(unstable)
    s = StochSpec{:kdj,slowkmatype,slowdmatype}(0, fastkperiod, slowkperiod, slowdperiod,
        unstable)
    return barindicator(s, outnames(nothing, name, (:k, :d, :j)), high, low, close)
end

# Fractal: Williams' swing pivots. The pivot `right` bars back must strictly
# exceed the `left` bars before it, read from the extremes of those bars when
# the pivot arrived, and the `right` bars after it, the extremes of the newest
# `right` bars. The pivot and its left extremes are delayed through `First`s.
struct FractalSpec
    left::Int
    right::Int
end

barouttype(::FractalSpec, ::Type) = Int

mutable struct FractalKernel{L,R,D}
    const spec::FractalSpec
    n::Int
    const leftside::L
    const rightside::R
    const delayed::D
end

function barkernel(s::FractalSpec, ::Type{T}) where {T}
    l = extremeswindow(s.left, T)
    r = extremeswindow(s.right, T)
    d = CausalFrames.barwindow(Firsts{(:h, :l, :lh, :ll)}(), s.right + 1,
        (h = T, l = T, lh = T, ll = T))
    return FractalKernel{typeof(l),typeof(r),typeof(d)}(s, 0, l, r, d)
end
function CausalFrames.fresh!(k::FractalKernel)
    k.n = 0
    fresh!(k.leftside)
    fresh!(k.rightside)
    fresh!(k.delayed)
    return k
end

@inline function barstep!(k::FractalKernel, h::T, l::T) where {T}
    # The extremes of the `left` bars before this one; until there are that
    # many, this bar can never be reported, so any placeholder will do.
    left = value(k.leftside).extremes
    lh, ll = ismissing(left) ? (h, l) : left::Tuple{T,T}
    update!(k.leftside, (high = h, low = l))
    update!(k.rightside, (high = h, low = l))
    update!(k.delayed, (h = h, l = l, lh = lh, ll = ll))
    (k.n += 1) > k.spec.left + k.spec.right || return nothing
    ph, pl, plh, pll = value(k.delayed).firsts::NTuple{4,T}
    rh, rl = value(k.rightside).extremes::Tuple{T,T}
    return (ph > plh && ph > rh ? 100 : 0, pl < pll && pl < rl ? 100 : 0)
end

"""
    Fractal(; high = :high, low = :low, leftbars = 2, rightbars = 2, name = :fractal)

TA-Lib's `FRACTAL`, Williams' fractal swing pivots, in `:fractal_swinghigh`
and `:fractal_swinglow` (`Int`): 100 where the bar `rightbars` back has a high
strictly above (a low strictly below) those of the `leftbars` bars before it
and the `rightbars` bars after it, and 0 elsewhere. A pivot tied with any bar
of its window is not one. The verdict is written on the confirmation bar,
`rightbars` after the pivot, so the output is causal; shift it back with
`Acausal.lead` to plot it on the pivot. The lookback is
`leftbars + rightbars`. The extremes are CausalFrames `Max` and `Min`, and the
delayed pivot a `First`, under `CausalFrames.barwindow`; a NaN in a window
gives 0.

$PRICEBAR_DOC
TA-Lib: `ta_codegen/input/fractal/fractal.yaml`, `fractal.md`.
"""
function Fractal(; high::ColumnSpec = :high, low::ColumnSpec = :low,
    leftbars::Integer = 2, rightbars::Integer = 2, name::Symbol = :fractal)
    checkrange("Fractal", "leftbars", leftbars, 1, 100_000)
    checkrange("Fractal", "rightbars", rightbars, 1, 100_000)
    return barindicator(FractalSpec(leftbars, rightbars),
        outnames(nothing, name, (:swinghigh, :swinglow)), high, low)
end

# WAD: Williams' accumulation/distribution in Achelis' no-volume form, a
# compensated running sum of each close's move to the true-range extreme.
struct WADSpec end

mutable struct WADKernel{T,S}
    n::Int
    prev::T
    const total::S
end

barkernel(::WADSpec, ::Type{T}) where {T} =
    (s = seedsum(T); WADKernel{T,typeof(s)}(0, zero(T), s))
CausalFrames.fresh!(k::WADKernel{T}) where {T} =
    (k.n = 0; k.prev = zero(T); fresh!(k.total); k)

@inline function barstep!(k::WADKernel{T}, h::T, l::T, c::T) where {T}
    # The first bar is measured against itself and adds nothing.
    p = (k.n += 1) == 1 ? c : k.prev
    k.prev = c
    if c > p
        seedadd!(k.total, c - (p < l ? p : l))
    elseif c < p
        seedadd!(k.total, c - (p > h ? p : h))
    end
    return (seedtotal(k.total)::T,)
end

"""
    WAD(; high = :high, low = :low, close = :close, name = :wad)

TA-Lib's `WAD`, Williams' accumulation/distribution in Achelis' form, which
reads no volume, in `:wad`: starting from 0, the running total adds
`close − min(low, previous close)` on a bar whose close rose and
`close − max(high, previous close)` on one whose close fell. The total is a
CausalFrames compensated `Sum`, and the lookback is 0.

WAD is path-dependent: it is anchored at the first bar it sees, so no `warmup`
makes it split-invariant, and a key restarts it.

$PRICEBAR_DOC
TA-Lib: `ta_codegen/input/wad/wad.yaml`, `wad.md`.
"""
WAD(; high::ColumnSpec = :high, low::ColumnSpec = :low, close::ColumnSpec = :close,
    name::Symbol = :wad) = barindicator(WADSpec(), (name,), high, low, close)
