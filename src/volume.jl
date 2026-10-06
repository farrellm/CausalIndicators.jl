# TA-Lib's volume indicators (S4). AD, CMF and VWAP are dependents over
# CausalFrames sums of row terms, and RVOL and MarketFI over `Sum` and `Last`.
# The rest need the previous bar or a recursion, so they are plain summarizers:
# the running totals of OBV and PVT are embedded CausalFrames `Sum`s, and the
# averages of ADOSC, EFI and PVO are the recursive kernels.

# ---------------------------------------------------------------------------
# Structured dependents

# ta_AD.c's money flow volume: the close's place in the bar's range, from −1 at
# the low to 1 at the high, times the volume; 0 for a bar with no range.
@inline function moneyflowvolume(h, l, c, v)
    r = h - l
    f = (((c - l) - (h - c)) / r) * v
    return r > 0 ? f : zero(f)
end

# The money flow volume as AD's and CMF's hidden row term, `:ad_mfv`.
struct MoneyFlowVolume{H,L,C,V} <: Function end
@inline (::MoneyFlowVolume{H,L,C,V})(r) where {H,L,C,V} =
    lifted(moneyflowvolume)(getproperty(r, H), getproperty(r, L), getproperty(r, C),
        getproperty(r, V))

const MFV_DOC = """
Its hidden row term `:ad_mfv` is shared by `AD` and `CMF`, so two of them over
different columns cannot share a call.
"""

"""
    AD(; high = :high, low = :low, close = :close, volume = :volume) -> Summarizer

TA-Lib's `AD`, Chaikin's accumulation/distribution line, in `:ad`: the running
sum of each bar's money flow volume
`((close − low) − (high − close))/(high − low)·volume`, which is 0 for a bar
with no range. It is a dependent over CausalFrames' `Sum` of the row term
`:ad_mfv`, so it runs under `addsummarycolumns`, with lookback 0. Under a
window it is the window's sum.

AD is path-dependent: it is anchored at the first bar it sees, so no `warmup`
makes it split-invariant. A key restarts it.
$MFV_DOC
TA-Lib: `ta_codegen/input/ad/ad.yaml`, `ad.md`.
"""
struct AD{H,L,C,V} <: GroupSummarizer end
AD(; high::ColumnSpec = :high, low::ColumnSpec = :low, close::ColumnSpec = :close,
    volume::ColumnSpec = :volume) =
    ad(colname(high), colname(low), colname(close), colname(volume), high, low, close,
        volume)
ad(H, L, C, V, specs...) =
    withterms(AD{H,L,C,V}(), specs..., :ad_mfv => MoneyFlowVolume{H,L,C,V}())

CausalFrames.dependencies(::AD) = (Sum(:ad_mfv),)
CausalFrames.emptyvalue(::AD) = (; ad = missing)
CausalFrames.fresh(::AD, ::NamedTuple) = derivedvalue(:ad, (:ad_mfv_sum,), identity)

"""
    CMF(; high = :high, low = :low, close = :close, volume = :volume) -> Summarizer

TA-Lib's `CMF`, Chaikin's money flow, in `:cmf`: the window's sum of money flow
volume (as for [`AD`](@ref)) over its sum of volume, or 0 where the volume sum
is not positive. It is a dependent over CausalFrames' `Sum` of the row term
`:ad_mfv` and of the volume (Group tier). TA-Lib's `CMF(period = p)` is `CMF()`
under `Bars(p)`.
$MFV_DOC
TA-Lib: `ta_codegen/input/cmf/cmf.yaml`, `cmf.md`.
"""
struct CMF{H,L,C,V} <: GroupSummarizer end
CMF(; high::ColumnSpec = :high, low::ColumnSpec = :low, close::ColumnSpec = :close,
    volume::ColumnSpec = :volume) =
    cmf(colname(high), colname(low), colname(close), colname(volume), high, low, close,
        volume)
cmf(H, L, C, V, specs...) =
    withterms(CMF{H,L,C,V}(), specs..., :ad_mfv => MoneyFlowVolume{H,L,C,V}())

CausalFrames.dependencies(::CMF{H,L,C,V}) where {H,L,C,V} = (Sum(:ad_mfv), Sum(V))
CausalFrames.emptyvalue(::CMF) = (; cmf = missing)
CausalFrames.fresh(::CMF{H,L,C,V}, ::NamedTuple) where {H,L,C,V} =
    derivedvalue(:cmf, (:ad_mfv_sum, Symbol(V, :_sum)), lifted(positiveratio))

# `a/b`, or 0 where `b` is not positive (ta_CMF.c, ta_VWAP.c).
positiveratio(a, b) = b > 0 ? a / b : zero(a / b)

# VWAP's hidden row terms: the typical price times the volume (`:pv`) and the
# volume (`:v`), both 0 on a bar whose typical price or volume is not finite, as
# ta_VWAP.c skips that bar.
struct VWAPTerm{K,H,L,C,V} <: Function end
@inline (::VWAPTerm{K,H,L,C,V})(r) where {K,H,L,C,V} =
    lifted(vwapterm(Val(K)))(getproperty(r, H), getproperty(r, L), getproperty(r, C),
        getproperty(r, V))

@inline function vwappv(h, l, c, v)
    tp = (h + l + c) / 3
    pv = tp * v
    return isfinite(tp) && isfinite(v) ? pv : zero(pv)
end
@inline function vwapv(h, l, c, v)
    tp = (h + l + c) / 3
    w = v * one(tp)
    return isfinite(tp) && isfinite(v) ? w : zero(w)
end
vwapterm(::Val{:pv}) = vwappv
vwapterm(::Val{:v}) = vwapv

"""
    VWAP(; high = :high, low = :low, close = :close, volume = :volume) -> Summarizer

TA-Lib's `VWAP`, the volume-weighted average price, in `:vwap`: the sum of the
typical price `(high + low + close)/3` times the volume, over the sum of the
volume. A bar whose typical price or volume is not finite is left out, and
while no volume has traded the value is 0. It is a dependent over CausalFrames'
`Sum` of the row terms `:vwap_pv` and `:vwap_v`, so it runs under
`addsummarycolumns`, with lookback 0. Under a window it is the window's VWAP.

VWAP is path-dependent: it is anchored at the first bar it sees. The usual
session reset is a key, as in `key = [:symbol, :date]`. TA-Lib carries its last
value forward over bars that leave the volume sum at or below 0; a dependent
has no previous value, so it gives 0 there, which differs only for negative
volume. Two `VWAP`s over different columns cannot share a call, since their
terms share the names.

TA-Lib: `ta_codegen/input/vwap/vwap.yaml`, `vwap.md`.
"""
struct VWAP{H,L,C,V} <: GroupSummarizer end
VWAP(; high::ColumnSpec = :high, low::ColumnSpec = :low, close::ColumnSpec = :close,
    volume::ColumnSpec = :volume) =
    vwap(colname(high), colname(low), colname(close), colname(volume), high, low, close,
        volume)
vwap(H, L, C, V, specs...) =
    withterms(VWAP{H,L,C,V}(), specs..., :vwap_pv => VWAPTerm{:pv,H,L,C,V}(),
        :vwap_v => VWAPTerm{:v,H,L,C,V}())

CausalFrames.dependencies(::VWAP) = (Sum(:vwap_pv), Sum(:vwap_v))
CausalFrames.emptyvalue(::VWAP) = (; vwap = missing)
CausalFrames.fresh(::VWAP, ::NamedTuple) =
    derivedvalue(:vwap, (:vwap_pv_sum, :vwap_v_sum), lifted(positiveratio))

"""
    MarketFI(; high = :high, low = :low, volume = :volume) -> Summarizer

TA-Lib's `MARKETFI`, Bill Williams' market facilitation index
`(high − low)/volume`, in `:marketfi`; a bar with zero volume gives 0. It is a
dependent over `Last`, and it is bar-local under any window, with lookback 0.

TA-Lib: `ta_codegen/input/marketfi/marketfi.yaml`, `marketfi.md`.
"""
struct MarketFI{H,L,V} <: GroupSummarizer end
MarketFI(; high::ColumnSpec = :high, low::ColumnSpec = :low, volume::ColumnSpec = :volume) =
    withterms(MarketFI{colname(high),colname(low),colname(volume)}(), high, low, volume)

CausalFrames.dependencies(::MarketFI{H,L,V}) where {H,L,V} = (Last(H), Last(L), Last(V))
CausalFrames.emptyvalue(::MarketFI) = (; marketfi = missing)
CausalFrames.fresh(::MarketFI{H,L,V}, ::NamedTuple) where {H,L,V} =
    derivedvalue(:marketfi, map(lastname, (H, L, V)), lifted(marketfivalue))

function marketfivalue(h, l, v)
    q = (h - l) / v
    return v != 0 ? q : zero(q)
end

"""
    RVOL(; volume = :volume) -> Summarizer

TA-Lib's `RVOL`, the relative volume, in `:rvol`: the newest bar's volume over
the mean volume of the window's other bars, `last/((sum − last)/(n − 1))` for a
window of `n` bars. A baseline of zero gives ±Inf, or NaN for a zero bar, as
rvol.md specifies. It is a dependent over CausalFrames' `Count`, `Sum` and
`Last` (Group tier). TA-Lib's baseline is the `period` bars before the current
one, so the window holds `period + 1`: TA-Lib's `period = p` is `Bars(p + 1)`,
and its lookback `p` is the window's partial-window rule.

TA-Lib: `ta_codegen/input/rvol/rvol.yaml`, `rvol.md`.
"""
struct RVOL{V} <: GroupSummarizer end
RVOL(; volume::ColumnSpec = :volume) = withterms(RVOL{colname(volume)}(), volume)

CausalFrames.dependencies(::RVOL{V}) where {V} = (Count(), Sum(V), Last(V))
CausalFrames.emptyvalue(::RVOL) = (; rvol = missing)
CausalFrames.fresh(::RVOL{V}, ::NamedTuple) where {V} =
    derivedvalue(:rvol, (:count, Symbol(V, :_sum), lastname(V)), lifted(rvolvalue))

rvolvalue(n, s, v) = v / ((s - v) / (n - 1))

# ---------------------------------------------------------------------------
# Cumulative states: OBV, PVT, NVI and PVI

# `K` is `:obv`, `:pvt`, `:nvi` or `:pvi`. Each reads a price column `C` and the
# volume `V`, and keeps the previous bar's price and volume.
struct VolumeTotal{K,C,V,N} <: Summarizer end

mutable struct VolumeTotalState{K,C,V,N,S,T} <: SummarizerState
    const total::S
    n::Int
    prevc::T
    prevv::T
    index::T
    out::Union{Missing,T}
end

CausalFrames.emptyvalue(::VolumeTotal{K,C,V,N}) where {K,C,V,N} =
    NamedTuple{(N,)}((missing,))

# NVI and PVI start at 1000 (ta_NVI.c, ta_PVI.c).
startindex(::Val{K}, ::Type{T}) where {K,T} = K === :nvi || K === :pvi ? T(1000) : zero(T)

function CausalFrames.fresh(::VolumeTotal{K,C,V,N}, intypes::NamedTuple) where {K,C,V,N}
    T = pricetype(intypes, (C, V))
    s = seedsum(T)
    return VolumeTotalState{K,C,V,N,typeof(s),T}(s, 0, zero(T), zero(T),
        startindex(Val(K), T), missing)
end
CausalFrames.fresh(st::VolumeTotalState{K,C,V,N,S,T}) where {K,C,V,N,S,T} =
    VolumeTotalState{K,C,V,N,S,T}(fresh(st.total), 0, zero(T), zero(T),
        startindex(Val(K), T), missing)
function CausalFrames.fresh!(st::VolumeTotalState{K,C,V,N,S,T}) where {K,C,V,N,S,T}
    fresh!(st.total)
    st.n = 0
    st.prevc = st.prevv = zero(T)
    st.index = startindex(Val(K), T)
    st.out = missing
    return st
end

@inline function CausalFrames.update!(
    st::VolumeTotalState{K,C,V,N,S,T},
    row,
) where {K,C,V,N,S,T}
    c0, v0 = row[C], row[V]
    st.out = missing
    anymissing(c0, v0) && return nothing
    c, v = convert(T, c0), convert(T, v0)
    if (st.n += 1) == 1
        # Each function compares its first bar with itself.
        st.prevc, st.prevv = c, v
        K === :obv && seedadd!(st.total, v)
    end
    st.out = volumetotal!(Val(K), st, c, v)
    st.prevc, st.prevv = c, v
    return nothing
end
@inline CausalFrames.value(st::VolumeTotalState{K,C,V,N,S,T}) where {K,C,V,N,S,T} =
    NamedTuple{(N,),Tuple{Union{Missing,T}}}((st.out,))

# ta_OBV.c: the volume added on a rise and subtracted on a fall.
@inline function volumetotal!(::Val{:obv}, st, c, v)
    c > st.prevc ? seedadd!(st.total, v) : c < st.prevc && seedadd!(st.total, -v)
    return seedtotal(st.total)
end
# ta_PVT.c: the volume times the fractional change, none over a zero close.
@inline function volumetotal!(::Val{:pvt}, st, c, v)
    p = st.prevc
    p != 0 && seedadd!(st.total, ((c - p) / p) * v)
    return seedtotal(st.total)
end
# ta_NVI.c and ta_PVI.c: the index compounds the fractional change on a bar
# whose volume fell (NVI) or rose (PVI), keeping its last finite value.
@inline volumetotal!(::Val{:nvi}, st, c, v) = compound!(st, c, v < st.prevv)
@inline volumetotal!(::Val{:pvi}, st, c, v) = compound!(st, c, v > st.prevv)
@inline function compound!(st, c, moved)
    p = st.prevc
    if moved && p != 0
        x = st.index
        x += ((c - p) / p) * x
        isfinite(x) && (st.index = x)
    end
    return st.index
end

const CUMULATIVE_DOC = """
It is path-dependent: it is anchored at the first bar it sees, so no `warmup`
makes it split-invariant, and a key restarts it. It is a plain summarizer (no
`combine!`), so it belongs under `addsummarycolumns`, with lookback 0. A bar
with any input `missing` leaves the state unchanged and emits `missing`.
"""

volumetotal(K, C, V, N, specs...) = withterms(VolumeTotal{K,C,V,N}(), specs...)

"""
    OBV(column::ColumnSpec; volume = :volume, name = :obv) -> Summarizer

TA-Lib's `OBV`, Granville's on-balance volume, in `:{column}_obv`: starting
from the first bar's volume, the running total adds each bar's volume when
`column` rose from the previous bar and subtracts it when it fell. The total
is a CausalFrames compensated `Sum`.

$CUMULATIVE_DOC
TA-Lib: `ta_codegen/input/obv/obv.yaml`, `obv.md`.
"""
OBV(column::ColumnSpec; volume::ColumnSpec = :volume, name::Symbol = :obv) =
    volumetotal(:obv, colname(column), colname(volume), outname(colname(column), name),
        column, volume)

"""
    PVT(; close = :close, volume = :volume, name = :pvt) -> Summarizer

TA-Lib's `PVT`, the price volume trend, in `:pvt`: starting from 0, the running
total of each bar's volume times its close's fractional change from the
previous bar. A zero previous close adds nothing. The total is a CausalFrames
compensated `Sum`.

$CUMULATIVE_DOC
TA-Lib: `ta_codegen/input/pvt/pvt.yaml`, `pvt.md`.
"""
PVT(; close::ColumnSpec = :close, volume::ColumnSpec = :volume, name::Symbol = :pvt) =
    volumetotal(:pvt, colname(close), colname(volume), name, close, volume)

const VOLUMEINDEX_DOC = """
A zero previous close leaves the index unchanged, and so does a change that
would overflow it.
"""

"""
    NVI(; close = :close, volume = :volume, name = :nvi) -> Summarizer

TA-Lib's `NVI`, the negative volume index, in `:nvi`: starting from 1000, the
index compounds the close's fractional change on each bar whose volume fell
from the previous bar, and is unchanged on the others.
$VOLUMEINDEX_DOC
$CUMULATIVE_DOC
TA-Lib: `ta_codegen/input/nvi/nvi.yaml`, `nvi.md`.
"""
NVI(; close::ColumnSpec = :close, volume::ColumnSpec = :volume, name::Symbol = :nvi) =
    volumetotal(:nvi, colname(close), colname(volume), name, close, volume)

"""
    PVI(; close = :close, volume = :volume, name = :pvi) -> Summarizer

TA-Lib's `PVI`, the positive volume index, in `:pvi`: starting from 1000, the
index compounds the close's fractional change on each bar whose volume rose
from the previous bar, and is unchanged on the others.
$VOLUMEINDEX_DOC
$CUMULATIVE_DOC
TA-Lib: `ta_codegen/input/pvi/pvi.yaml`, `pvi.md`.
"""
PVI(; close::ColumnSpec = :close, volume::ColumnSpec = :volume, name::Symbol = :pvi) =
    volumetotal(:pvi, colname(close), colname(volume), name, close, volume)

# ---------------------------------------------------------------------------
# ADOSC

struct ADOSCSummarizer{H,L,C,V,N} <: Summarizer
    fastperiod::Int
    slowperiod::Int
    unstable::Int
end

mutable struct ADOSCState{H,L,C,V,N,S,E,T} <: SummarizerState
    const ad::S
    const fast::E
    const slow::E
    const lookback::Int
    out::Union{Missing,T}
end

CausalFrames.emptyvalue(::ADOSCSummarizer{H,L,C,V,N}) where {H,L,C,V,N} =
    NamedTuple{(N,)}((missing,))

# ta_ADOSC.c seeds both EMAs with the first A/D value: `EMAKernel` at period 1
# with each period's factor.
adoscema(::Type{T}, period) where {T} = EMAKernel(T, 1, 2 / (period + 1))

function CausalFrames.fresh(
    s::ADOSCSummarizer{H,L,C,V,N},
    intypes::NamedTuple,
) where {H,L,C,V,N}
    T = pricetype(intypes, (H, L, C, V))
    ad = seedsum(T)
    f, sl = adoscema(T, s.fastperiod), adoscema(T, s.slowperiod)
    lb = max(s.fastperiod, s.slowperiod) - 1 + s.unstable
    return ADOSCState{H,L,C,V,N,typeof(ad),typeof(f),T}(ad, f, sl, lb, missing)
end
CausalFrames.fresh(st::ADOSCState{H,L,C,V,N,S,E,T}) where {H,L,C,V,N,S,E,T} =
    ADOSCState{H,L,C,V,N,S,E,T}(fresh(st.ad), fresh(st.fast), fresh(st.slow),
        st.lookback, missing)
function CausalFrames.fresh!(st::ADOSCState)
    fresh!(st.ad)
    fresh!(st.fast)
    fresh!(st.slow)
    st.out = missing
    return st
end

@inline function CausalFrames.update!(
    st::ADOSCState{H,L,C,V,N,S,E,T},
    row,
) where {H,L,C,V,N,S,E,T}
    h, l, c, v = row[H], row[L], row[C], row[V]
    st.out = missing
    anymissing(h, l, c, v) && return nothing
    seedadd!(st.ad,
        moneyflowvolume(convert(T, h), convert(T, l), convert(T, c), convert(T, v)))
    ad = seedtotal(st.ad)
    f = step!(st.fast, ad)::T
    sl = step!(st.slow, ad)::T
    nseen(st.fast) > st.lookback && (st.out = f - sl)
    return nothing
end
@inline CausalFrames.value(st::ADOSCState{H,L,C,V,N,S,E,T}) where {H,L,C,V,N,S,E,T} =
    NamedTuple{(N,),Tuple{Union{Missing,T}}}((st.out,))

"""
    ADOSC(; high = :high, low = :low, close = :close, volume = :volume,
          fastperiod = 3, slowperiod = 10, unstable = 0, name = :adosc)

TA-Lib's `ADOSC`, Chaikin's A/D oscillator, in `:adosc`: the `fastperiod` EMA
of the A/D line (as [`AD`](@ref)) minus its `slowperiod` EMA. Both EMAs are
seeded with the first A/D value, and they are not swapped: with
`fastperiod > slowperiod` the "fast" EMA is the slower one. The lookback is the
longer period minus 1, plus `unstable`, EMA's unstable period, which TA-Lib's
ADOSC inherits; it delays the first output without changing the values. The A/D
line is a CausalFrames compensated `Sum`.

ADOSC is path-dependent, as AD is: no `warmup` makes it split-invariant.

$PLAIN_DOC
A bar with any input `missing` leaves the state unchanged and emits `missing`.

TA-Lib: `ta_codegen/input/adosc/adosc.yaml`, `adosc.md`.
"""
function ADOSC(; high::ColumnSpec = :high, low::ColumnSpec = :low,
    close::ColumnSpec = :close, volume::ColumnSpec = :volume, fastperiod::Integer = 3,
    slowperiod::Integer = 10, unstable::Integer = 0, name::Symbol = :adosc)
    checkrange("ADOSC", "fastperiod", fastperiod, 2, 100_000)
    checkrange("ADOSC", "slowperiod", slowperiod, 2, 100_000)
    s = ADOSCSummarizer{colname(high),colname(low),colname(close),colname(volume),name}(
        Int(fastperiod), Int(slowperiod), checkunstable(unstable))
    return withterms(s, high, low, close, volume)
end

# ---------------------------------------------------------------------------
# EFI

struct EFISummarizer{C,V,N} <: Summarizer
    period::Int
    unstable::Int
end

mutable struct EFIState{C,V,N,E,T} <: SummarizerState
    const ema::E
    const unstable::Int
    n::Int
    prevc::T
    out::Union{Missing,T}
end

CausalFrames.emptyvalue(::EFISummarizer{C,V,N}) where {C,V,N} = NamedTuple{(N,)}((missing,))

function CausalFrames.fresh(s::EFISummarizer{C,V,N}, intypes::NamedTuple) where {C,V,N}
    T = pricetype(intypes, (C, V))
    e = EMAKernel(T, s.period)
    return EFIState{C,V,N,typeof(e),T}(e, s.unstable, 0, zero(T), missing)
end
CausalFrames.fresh(st::EFIState{C,V,N,E,T}) where {C,V,N,E,T} =
    EFIState{C,V,N,E,T}(fresh(st.ema), st.unstable, 0, zero(T), missing)
function CausalFrames.fresh!(st::EFIState{C,V,N,E,T}) where {C,V,N,E,T}
    fresh!(st.ema)
    st.n = 0
    st.prevc = zero(T)
    st.out = missing
    return st
end

@inline function CausalFrames.update!(st::EFIState{C,V,N,E,T}, row) where {C,V,N,E,T}
    c0, v0 = row[C], row[V]
    st.out = missing
    anymissing(c0, v0) && return nothing
    c = convert(T, c0)
    prev = st.prevc
    st.prevc = c
    (st.n += 1) == 1 && return nothing
    e = st.ema
    f = step!(e, (c - prev) * convert(T, v0))
    nseen(e) > lookback(e) + st.unstable && (st.out = f)
    return nothing
end
@inline CausalFrames.value(st::EFIState{C,V,N,E,T}) where {C,V,N,E,T} =
    NamedTuple{(N,),Tuple{Union{Missing,T}}}((st.out,))

"""
    EFI(; close = :close, volume = :volume, period = 13, unstable = 0, name = :efi)

TA-Lib's `EFI`, Elder's force index, in `:efi`: the `period` EMA of each bar's
force `(close − previous close)·volume`, seeded with the mean of the first
`period` forces. Period 1 is the raw force. The lookback is `period`, one bar
for the first force, plus `unstable`, EMA's unstable period, which TA-Lib's EFI
inherits.

$PLAIN_DOC
A bar with any input `missing` leaves the state unchanged and emits `missing`.

TA-Lib: `ta_codegen/input/efi/efi.yaml`, `efi.md`.
"""
function EFI(; close::ColumnSpec = :close, volume::ColumnSpec = :volume,
    period::Integer = 13, unstable::Integer = 0, name::Symbol = :efi)
    checkrange("EFI", "period", period, 1, 100_000)
    s = EFISummarizer{colname(close),colname(volume),name}(Int(period),
        checkunstable(unstable))
    return withterms(s, close, volume)
end

# ---------------------------------------------------------------------------
# PVO

"""
    PVO(; volume = :volume, fastperiod = 12, slowperiod = 26, matype = :ema,
        unstable = 0, name = :pvo)

TA-Lib's `PVO`, the percentage volume oscillator `(fast − slow)/slow·100` of
the volume, in `:pvo`. A slow average TA-Lib finds zero gives 0. It is
[`PPO`](@ref) over the volume, the same state under a bare output name.

$PO_DOC
$PLAIN_DOC$SKIP_DOC
TA-Lib: `ta_codegen/input/pvo/pvo.yaml`, `pvo.md`.
"""
PVO(; volume::ColumnSpec = :volume, fastperiod::Integer = 12, slowperiod::Integer = 26,
    matype::Symbol = :ema, unstable::Integer = 0, name::Symbol = :pvo) =
    priceoscillator("PVO", :ppo, volume, fastperiod, slowperiod, matype, unstable, name;
        prefix = false)
