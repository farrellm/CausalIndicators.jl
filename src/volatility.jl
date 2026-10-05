# TA-Lib's volatility indicators (S3). TRange and ADR are dependents over
# CausalFrames accumulators; ATR, NATR, CVI, MassIndex and RVI are plain
# summarizers over the recursive kernels, with their windows embedded through
# `CausalFrames.barwindow`.

# ---------------------------------------------------------------------------
# Structured dependents

"""
    TRange(; high = :high, low = :low, close = :close) -> Summarizer

TA-Lib's `TRANGE`, the true range `max(h − l, |c₋₁ − h|, |c₋₁ − l|)`, in
`:trange`, where `c₋₁` is the previous bar's close. It is a dependent over
`Last` of the high and low and `First` of the close (Group tier), so it must run
under `Bars(2)`, where `First` is the previous close. TA-Lib's lookback of 1 is
the window's partial-window rule.

TA-Lib: `ta_codegen/input/trange/trange.yaml`, `trange.md`.
"""
struct TRange{H,L,C} <: GroupSummarizer end
TRange(; high::ColumnSpec = :high, low::ColumnSpec = :low, close::ColumnSpec = :close) =
    withterms(TRange{colname(high),colname(low),colname(close)}(), high, low, close)

CausalFrames.dependencies(::TRange{H,L,C}) where {H,L,C} = (Last(H), Last(L), First(C))
CausalFrames.emptyvalue(::TRange) = (; trange = missing)
CausalFrames.fresh(::TRange{H,L,C}, ::NamedTuple) where {H,L,C} =
    derivedvalue(:trange, (lastname(H), lastname(L), Symbol(C, :_first)),
        lifted(truerange))

# The bar's range `high − low`, ADR's hidden row term.
struct BarRange{H,L} <: Function end
@inline (::BarRange{H,L})(r) where {H,L} = getproperty(r, H) - getproperty(r, L)

"""
    ADR(; high = :high, low = :low) -> Summarizer

TA-Lib's `ADR`, the average daily range, the mean of `high − low` over the
window, in `:adr`. It is a dependent over CausalFrames' `Mean` of the row term
`:adr_range` (Group tier). TA-Lib's `ADR(period = p)` is `ADR()` under
`Bars(p)`. Two `ADR`s over different columns cannot share a call, since their
terms share the name.

TA-Lib: `ta_codegen/input/adr/adr.yaml`, `adr.md`.
"""
struct ADR{H,L} <: GroupSummarizer end
ADR(; high::ColumnSpec = :high, low::ColumnSpec = :low) = adr(colname(high),
    colname(low), high, low)
adr(H, L, specs...) = withterms(ADR{H,L}(), specs..., :adr_range => BarRange{H,L}())

CausalFrames.dependencies(::ADR) = (Mean(:adr_range),)
CausalFrames.emptyvalue(::ADR) = (; adr = missing)
CausalFrames.fresh(::ADR, ::NamedTuple) = derivedvalue(:adr, (:adr_range_mean,), identity)

# ---------------------------------------------------------------------------
# ATR and NATR

struct ATRSummarizer{K,H,L,C,N} <: Summarizer
    period::Int
    unstable::Int
end

mutable struct ATRState{K,H,L,C,N,A,T} <: SummarizerState
    const kernel::A
    const unstable::Int
    out::Union{Missing,T}
end

CausalFrames.emptyvalue(::ATRSummarizer{K,H,L,C,N}) where {K,H,L,C,N} =
    NamedTuple{(N,)}((missing,))

# The element type of a price-bar indicator over input columns `cols`.
pricetype(intypes, cols) =
    floattype(promote_type(map(c -> nonmissingtype(intypes[c]), cols)...))

function CausalFrames.fresh(
    s::ATRSummarizer{K,H,L,C,N},
    intypes::NamedTuple,
) where {K,H,L,C,N}
    T = pricetype(intypes, (H, L, C))
    k = ATRKernel(T, s.period)
    return ATRState{K,H,L,C,N,typeof(k),T}(k, s.unstable, missing)
end
CausalFrames.fresh(st::ATRState{K,H,L,C,N,A,T}) where {K,H,L,C,N,A,T} =
    ATRState{K,H,L,C,N,A,T}(fresh(st.kernel), st.unstable, missing)
function CausalFrames.fresh!(st::ATRState)
    fresh!(st.kernel)
    st.out = missing
    return st
end

@inline function CausalFrames.update!(
    st::ATRState{K,H,L,C,N,A,T},
    row,
) where {K,H,L,C,N,A,T}
    h, l, c = row[H], row[L], row[C]
    st.out = missing
    anymissing(h, l, c) && return nothing
    k = st.kernel
    step!(k, h, l, c)
    nseen(k) > lookback(k) + st.unstable || return nothing
    st.out = atrvalue(Val(K), k.wilder.period, k.wilder.prev, convert(T, c))
    return nothing
end
@inline CausalFrames.value(st::ATRState{K,H,L,C,N,A,T}) where {K,H,L,C,N,A,T} =
    NamedTuple{(N,),Tuple{Union{Missing,T}}}((st.out,))

atrvalue(::Val{:atr}, p, atr, c) = atr
# ta_NATR.c: `atr/close·100`, 0 at a zero close, and the bare ATR at period 1.
atrvalue(::Val{:natr}, p, atr, c) = p <= 1 ? atr : c != 0 ? (atr / c) * 100 : zero(atr)

function atrsummarizer(fn, K, high, low, close, period, unstable, name)
    checkrange(fn, "period", period, 1, 100_000)
    checkunstable(unstable)
    s = ATRSummarizer{K,colname(high),colname(low),colname(close),name}(Int(period),
        Int(unstable))
    return withterms(s, high, low, close)
end

const PRICEBAR_DOC = """
$PLAIN_DOC
A bar with any input `missing` leaves the state unchanged and emits `missing`.
"""

"""
    ATR(; high = :high, low = :low, close = :close, period = 14, unstable = 0,
        name = :atr)

TA-Lib's `ATR`, Wilder's average true range, in `:atr`. Each bar's true range
against the previous close is smoothed by Wilder's method, seeded with the mean
of the first `period` true ranges. The lookback is `period`, plus `unstable`,
TA-Lib's unstable period. At period 1 it is the true range.

$PRICEBAR_DOC
TA-Lib: `ta_codegen/input/atr/atr.yaml`, `atr.md`.
"""
ATR(; high::ColumnSpec = :high, low::ColumnSpec = :low, close::ColumnSpec = :close,
    period::Integer = 14, unstable::Integer = 0, name::Symbol = :atr) =
    atrsummarizer("ATR", :atr, high, low, close, period, unstable, name)

"""
    NATR(; high = :high, low = :low, close = :close, period = 14, unstable = 0,
         name = :natr)

TA-Lib's `NATR`, the normalized ATR `ATR/close·100`, in `:natr`, with 0 at a
zero close. The lookback is `period`, plus `unstable`, TA-Lib's unstable
period. At period 1 TA-Lib does not normalize, so it is the true range.

$PRICEBAR_DOC
TA-Lib: `ta_codegen/input/natr/natr.yaml`, `natr.md`.
"""
NATR(; high::ColumnSpec = :high, low::ColumnSpec = :low, close::ColumnSpec = :close,
    period::Integer = 14, unstable::Integer = 0, name::Symbol = :natr) =
    atrsummarizer("NATR", :natr, high, low, close, period, unstable, name)

# ---------------------------------------------------------------------------
# CVI

struct CVISummarizer{H,L,N} <: Summarizer
    period::Int
    rocperiod::Int
    unstable::Int
end

mutable struct CVIState{H,L,N,E,W,T} <: SummarizerState
    const ema::E
    const lag::W
    const unstable::Int
    out::Union{Missing,T}
end

CausalFrames.emptyvalue(::CVISummarizer{H,L,N}) where {H,L,N} = NamedTuple{(N,)}((missing,))

function CausalFrames.fresh(s::CVISummarizer{H,L,N}, intypes::NamedTuple) where {H,L,N}
    T = pricetype(intypes, (H, L))
    e = EMAKernel(T, s.period)
    w = CausalFrames.barwindow(First(:x), s.rocperiod + 1, (x = T,))
    return CVIState{H,L,N,typeof(e),typeof(w),T}(e, w, s.unstable, missing)
end
CausalFrames.fresh(st::CVIState{H,L,N,E,W,T}) where {H,L,N,E,W,T} =
    CVIState{H,L,N,E,W,T}(fresh(st.ema), fresh(st.lag), st.unstable, missing)
function CausalFrames.fresh!(st::CVIState)
    fresh!(st.ema)
    fresh!(st.lag)
    st.out = missing
    return st
end

# ta_CVI.c: the rate of change, in percent, of the EMA of the range from
# `rocperiod` bars back, 0 where that EMA is exactly 0.
@inline function CausalFrames.update!(st::CVIState{H,L,N,E,W,T}, row) where {H,L,N,E,W,T}
    h, l = row[H], row[L]
    st.out = missing
    anymissing(h, l) && return nothing
    e = step!(st.ema, convert(T, h) - convert(T, l))
    emitted(st.ema, st.unstable) || return nothing
    update!(st.lag, (x = e::T,))
    old = value(st.lag).x_first
    ismissing(old) && return nothing
    st.out = old != 0 ? 100 * ((e::T - old) / old) : zero(T)
    return nothing
end
@inline CausalFrames.value(st::CVIState{H,L,N,E,W,T}) where {H,L,N,E,W,T} =
    NamedTuple{(N,),Tuple{Union{Missing,T}}}((st.out,))

"""
    CVI(; high = :high, low = :low, period = 10, rocperiod = 10, unstable = 0,
        name = :cvi)

TA-Lib's `CVI`, Chaikin's volatility, in `:cvi`: the percentage change over
`rocperiod` bars of the `period`-bar EMA of the range `high − low`, or 0 where
the earlier EMA is exactly 0. The lookback is `period − 1 + rocperiod`, plus
`unstable`, the EMA unstable period TA-Lib's CVI inherits. The earlier EMA is
read from a CausalFrames `First` under `CausalFrames.barwindow`.

$PRICEBAR_DOC
TA-Lib: `ta_codegen/input/cvi/cvi.yaml`, `cvi.md`.
"""
function CVI(; high::ColumnSpec = :high, low::ColumnSpec = :low, period::Integer = 10,
    rocperiod::Integer = 10, unstable::Integer = 0, name::Symbol = :cvi)
    checkrange("CVI", "period", period, 2, 100_000)
    checkrange("CVI", "rocperiod", rocperiod, 1, 100_000)
    checkunstable(unstable)
    s = CVISummarizer{colname(high),colname(low),name}(Int(period), Int(rocperiod),
        Int(unstable))
    return withterms(s, high, low)
end

# ---------------------------------------------------------------------------
# MassIndex

struct MassIndexSummarizer{H,L,N} <: Summarizer
    fastperiod::Int
    slowperiod::Int
    unstable::Int
end

mutable struct MassIndexState{H,L,N,E,W,T} <: SummarizerState
    const e1::E
    const e2::E
    const window::W
    const unstable::Int
    out::Union{Missing,T}
end

CausalFrames.emptyvalue(::MassIndexSummarizer{H,L,N}) where {H,L,N} =
    NamedTuple{(N,)}((missing,))

function CausalFrames.fresh(
    s::MassIndexSummarizer{H,L,N},
    intypes::NamedTuple,
) where {H,L,N}
    T = pricetype(intypes, (H, L))
    e = EMAKernel(T, s.fastperiod)
    w = CausalFrames.barwindow(Sum(:x), s.slowperiod, (x = T,))
    return MassIndexState{H,L,N,typeof(e),typeof(w),T}(e, fresh(e), w, s.unstable, missing)
end
CausalFrames.fresh(st::MassIndexState{H,L,N,E,W,T}) where {H,L,N,E,W,T} =
    MassIndexState{H,L,N,E,W,T}(fresh(st.e1), fresh(st.e2), fresh(st.window), st.unstable,
        missing)
function CausalFrames.fresh!(st::MassIndexState)
    fresh!(st.e1)
    fresh!(st.e2)
    fresh!(st.window)
    st.out = missing
    return st
end

# ta_MASSI.c: the EMA of the range over the EMA of that EMA, each stage passing
# its unstable bars before feeding the next as ta_DEMA.c's do, summed over
# `slowperiod` bars. A second EMA of exactly 0 gives the ratio 1.
@inline function CausalFrames.update!(st::MassIndexState{H,L,N,E,W,T},
    row) where {H,L,N,E,W,T}
    h, l = row[H], row[L]
    st.out = missing
    anymissing(h, l) && return nothing
    v1 = step!(st.e1, convert(T, h) - convert(T, l))
    emitted(st.e1, st.unstable) || return nothing
    v2 = step!(st.e2, v1::T)
    emitted(st.e2, st.unstable) || return nothing
    ratio = v2::T == 0 ? one(T) : v1::T / v2::T
    update!(st.window, (x = ratio,))
    st.out = value(st.window).x_sum
    return nothing
end
@inline CausalFrames.value(st::MassIndexState{H,L,N,E,W,T}) where {H,L,N,E,W,T} =
    NamedTuple{(N,),Tuple{Union{Missing,T}}}((st.out,))

"""
    MassIndex(; high = :high, low = :low, fastperiod = 9, slowperiod = 25,
              unstable = 0, name = :massi)

TA-Lib's `MASSI`, Dorsey's mass index, in `:massi`: the ratio of the
`fastperiod`-bar EMA of the range `high − low` to the EMA of that EMA, summed
over the last `slowperiod` bars. A second EMA of exactly 0 counts the ratio as
1, so a flat market gives exactly `slowperiod`. The lookback is
`2(fastperiod − 1) + slowperiod − 1`, plus twice `unstable`, the EMA unstable
period TA-Lib's MASSI inherits for each EMA. The sum is a CausalFrames `Sum`
under `CausalFrames.barwindow`.

$PRICEBAR_DOC
TA-Lib: `ta_codegen/input/massi/massi.yaml`, `massi.md`.
"""
function MassIndex(; high::ColumnSpec = :high, low::ColumnSpec = :low,
    fastperiod::Integer = 9, slowperiod::Integer = 25, unstable::Integer = 0,
    name::Symbol = :massi)
    checkrange("MassIndex", "fastperiod", fastperiod, 2, 100_000)
    checkrange("MassIndex", "slowperiod", slowperiod, 2, 100_000)
    checkunstable(unstable)
    s = MassIndexSummarizer{colname(high),colname(low),name}(Int(fastperiod),
        Int(slowperiod), Int(unstable))
    return withterms(s, high, low)
end

# ---------------------------------------------------------------------------
# RVI

struct RVISummarizer{C,N} <: Summarizer
    period::Int
    sdperiod::Int
    unstable::Int
end

mutable struct RVIState{C,N,S,W,T} <: SummarizerState
    const std::S
    const up::W
    const dn::W
    const unstable::Int
    started::Bool
    prevx::T
    out::Union{Missing,T}
end

CausalFrames.emptyvalue(::RVISummarizer{C,N}) where {C,N} = NamedTuple{(N,)}((missing,))

function CausalFrames.fresh(s::RVISummarizer{C,N}, intypes::NamedTuple) where {C,N}
    T = floattype(intypes[C])
    sd = CausalFrames.barwindow(Std(:x; corrected = false), s.sdperiod, (x = T,))
    w = WilderKernel(T, s.period)
    return RVIState{C,N,typeof(sd),typeof(w),T}(sd, w, fresh(w), s.unstable, false,
        zero(T), missing)
end
CausalFrames.fresh(st::RVIState{C,N,S,W,T}) where {C,N,S,W,T} =
    RVIState{C,N,S,W,T}(fresh(st.std), fresh(st.up), fresh(st.dn), st.unstable, false,
        zero(T), missing)
function CausalFrames.fresh!(st::RVIState{C,N,S,W,T}) where {C,N,S,W,T}
    fresh!(st.std)
    fresh!(st.up)
    fresh!(st.dn)
    st.started = false
    st.prevx = zero(T)
    st.out = missing
    return st
end

# ta_RVI.c: the window's population standard deviation goes to the up leg on a
# rising bar and to the down leg on a falling one (a flat bar feeds 0 to both),
# each leg Wilder-smoothed; the index is the up leg's share, 50 when both are 0.
@inline function CausalFrames.update!(st::RVIState{C,N,S,W,T}, row) where {C,N,S,W,T}
    x = row[C]
    st.out = missing
    ismissing(x) && return nothing
    v = convert(T, x)
    d = v - st.prevx
    started = st.started
    st.started = true
    st.prevx = v
    update!(st.std, (x = v,))
    sigma = value(st.std).x_std
    (ismissing(sigma) || !started) && return nothing
    step!(st.up, d > 0 ? sigma : zero(T))
    step!(st.dn, d < 0 ? sigma : zero(T))
    nseen(st.up) > lookback(st.up) + st.unstable || return nothing
    up, dn = st.up.prev, st.dn.prev
    total = up + dn
    st.out = total == 0 ? T(50) : 100 * (up / total)
    return nothing
end
@inline CausalFrames.value(st::RVIState{C,N,S,W,T}) where {C,N,S,W,T} =
    NamedTuple{(N,),Tuple{Union{Missing,T}}}((st.out,))

"""
    RVI(column::ColumnSpec; period = 14, stddevperiod = 10, unstable = 0, name = :rvi)

TA-Lib's `RVI`, Dorsey's relative volatility index, in `:{column}_rvi`. Each
bar's `stddevperiod`-bar population standard deviation counts as up volatility
on a rising bar and down volatility on a falling one (a flat bar counts 0 for
both). Each is smoothed by Wilder's method over `period` bars, and the index is
`100·up/(up + down)`, or 50 where both are 0. The lookback is
`stddevperiod − 1 + period − 1`, plus `unstable`, TA-Lib's unstable period. The
standard deviation is a CausalFrames `Std(corrected = false)` under
`CausalFrames.barwindow`.

$PLAIN_DOC$SKIP_DOC
TA-Lib: `ta_codegen/input/rvi/rvi.yaml`, `rvi.md`.
"""
function RVI(column::ColumnSpec; period::Integer = 14, stddevperiod::Integer = 10,
    unstable::Integer = 0, name::Symbol = :rvi)
    checkrange("RVI", "period", period, 1, 100_000)
    checkrange("RVI", "stddevperiod", stddevperiod, 2, 100_000)
    checkunstable(unstable)
    C = colname(column)
    s = RVISummarizer{C,outname(C, name)}(Int(period), Int(stddevperiod), Int(unstable))
    return withterms(s, column)
end
