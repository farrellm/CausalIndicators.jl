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

struct ATRSpec{K}
    period::Int
    unstable::Unstable
end

mutable struct ATRIndicatorKernel{K,A}
    const atr::A
    const unstable::Int
end

function barkernel(s::ATRSpec{K}, ::Type{T}) where {K,T}
    a = ATRKernel(T, s.period)
    return ATRIndicatorKernel{K,typeof(a)}(
        a,
        unstablecount(s.unstable, atrrule(K), s.period),
    )
end

# ATR's own id has Wilder's rule; NATR's divides by the ATR, so it has the
# ratio rule.
atrrule(K) = K === :natr ? autoratio : autowilder
CausalFrames.fresh!(k::ATRIndicatorKernel) = (fresh!(k.atr); k)

@inline function barstep!(k::ATRIndicatorKernel{K}, h::T, l::T, c::T) where {K,T}
    a = k.atr
    step!(a, h, l, c)
    nseen(a) > lookback(a) + k.unstable || return nothing
    return (atrvalue(Val(K), a.wilder.period, a.wilder.prev, c),)
end

atrvalue(::Val{:atr}, p, atr, c) = atr
# ta_NATR.c: `atr/close·100`, 0 at a zero close, and the bare ATR at period 1.
atrvalue(::Val{:natr}, p, atr, c) = p <= 1 ? atr : c != 0 ? (atr / c) * 100 : zero(atr)

function atrsummarizer(fn, K, high, low, close, period, unstable, name)
    checkrange(fn, "period", period, 1, 100_000)
    unstable = checkunstable(unstable)
    return barindicator(ATRSpec{K}(period, unstable), (name,), high, low, close)
end

"""
    ATR(; high = :high, low = :low, close = :close, period = 14, unstable = 0,
        name = :atr)

TA-Lib's `ATR`, Wilder's average true range, in `:atr`. Each bar's true range
against the previous close is smoothed by Wilder's method, seeded with the mean
of the first `period` true ranges. The lookback is `period`, plus `unstable`,
TA-Lib's unstable period. At period 1 it is the true range.

$PRICEBAR_DOC

$DAILY_DOC
$AUTO_DOC
TA-Lib: `ta_codegen/input/atr/atr.yaml`, `atr.md`.
"""
ATR(; high::ColumnSpec = :high, low::ColumnSpec = :low, close::ColumnSpec = :close,
    period::Integer = 14, unstable::UnstableArg = 0, name::Symbol = :atr) =
    atrsummarizer("ATR", :atr, high, low, close, period, unstable, name)

"""
    NATR(; high = :high, low = :low, close = :close, period = 14, unstable = 0,
         name = :natr)

TA-Lib's `NATR`, the normalized ATR `ATR/close·100`, in `:natr`, with 0 at a
zero close. The lookback is `period`, plus `unstable`, TA-Lib's unstable
period. At period 1 TA-Lib does not normalize, so it is the true range.

$PRICEBAR_DOC

$DAILY_DOC
$AUTO_DOC
TA-Lib: `ta_codegen/input/natr/natr.yaml`, `natr.md`.
"""
NATR(; high::ColumnSpec = :high, low::ColumnSpec = :low, close::ColumnSpec = :close,
    period::Integer = 14, unstable::UnstableArg = 0, name::Symbol = :natr) =
    atrsummarizer("NATR", :natr, high, low, close, period, unstable, name)

# ---------------------------------------------------------------------------
# CVI

struct CVISpec
    period::Int
    rocperiod::Int
    unstable::Unstable
end

mutable struct CVIKernel{E,W}
    const ema::E
    const lag::W
    const unstable::Int
end

barkernel(s::CVISpec, ::Type{T}) where {T} =
    CVIKernel(EMAKernel(T, s.period), lagged(s.rocperiod + 1, T),
        unstablecount(s.unstable, autoema, s.period))
CausalFrames.fresh!(k::CVIKernel) = (fresh!(k.ema); fresh!(k.lag); k)

# ta_CVI.c: the rate of change, in percent, of the EMA of the range from
# `rocperiod` bars back, 0 where that EMA is exactly 0.
@inline function barstep!(k::CVIKernel, h::T, l::T) where {T}
    e = step!(k.ema, h - l)
    emitted(k.ema, k.unstable) || return nothing
    update!(k.lag, (x = e::T,))
    old = value(k.lag).x_first
    ismissing(old) && return nothing
    return (old != 0 ? 100 * ((e::T - old) / old) : zero(T),)
end

"""
    CVI(; high = :high, low = :low, period = 10, rocperiod = 10, unstable = 0,
        name = :cvi)

TA-Lib's `CVI`, Chaikin's volatility, in `:cvi`: the percentage change over
`rocperiod` bars of the `period`-bar EMA of the range `high − low`, or 0 where
the earlier EMA is exactly 0. The lookback is `period − 1 + rocperiod`, plus
`unstable`, the EMA unstable period TA-Lib's CVI inherits. The earlier EMA is
read from a CausalFrames `First` under `CausalFrames.barwindow`.

$PRICEBAR_DOC

$DAILY_DOC
$AUTO_DOC
TA-Lib: `ta_codegen/input/cvi/cvi.yaml`, `cvi.md`.
"""
function CVI(; high::ColumnSpec = :high, low::ColumnSpec = :low, period::Integer = 10,
    rocperiod::Integer = 10, unstable::UnstableArg = 0, name::Symbol = :cvi)
    checkrange("CVI", "period", period, 2, 100_000)
    checkrange("CVI", "rocperiod", rocperiod, 1, 100_000)
    unstable = checkunstable(unstable)
    return barindicator(CVISpec(period, rocperiod, unstable), (name,), high, low)
end

# ---------------------------------------------------------------------------
# MassIndex

struct MassIndexSpec
    fastperiod::Int
    slowperiod::Int
    unstable::Unstable
end

mutable struct MassIndexKernel{E,W}
    const e1::E
    const e2::E
    const window::W
    const unstable::Int
end

function barkernel(s::MassIndexSpec, ::Type{T}) where {T}
    e = EMAKernel(T, s.fastperiod)
    w = CausalFrames.barwindow(Sum(:x), s.slowperiod, (x = T,))
    return MassIndexKernel(e, fresh(e), w, unstablecount(s.unstable, autoema, s.fastperiod))
end
CausalFrames.fresh!(k::MassIndexKernel) = (fresh!(k.e1); fresh!(k.e2); fresh!(k.window); k)

# ta_MASSI.c: the EMA of the range over the EMA of that EMA, each stage passing
# its unstable bars before feeding the next as ta_DEMA.c's do, summed over
# `slowperiod` bars. A second EMA of exactly 0 gives the ratio 1.
@inline function barstep!(k::MassIndexKernel, h::T, l::T) where {T}
    v1 = step!(k.e1, h - l)
    emitted(k.e1, k.unstable) || return nothing
    v2 = step!(k.e2, v1::T)
    emitted(k.e2, k.unstable) || return nothing
    ratio = v2::T == 0 ? one(T) : v1::T / v2::T
    update!(k.window, (x = ratio,))
    s = value(k.window).x_sum
    return ismissing(s) ? nothing : (s,)
end

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

$DAILY_DOC
$AUTO_DOC
TA-Lib: `ta_codegen/input/massi/massi.yaml`, `massi.md`.
"""
function MassIndex(; high::ColumnSpec = :high, low::ColumnSpec = :low,
    fastperiod::Integer = 9, slowperiod::Integer = 25, unstable::UnstableArg = 0,
    name::Symbol = :massi)
    checkrange("MassIndex", "fastperiod", fastperiod, 2, 100_000)
    checkrange("MassIndex", "slowperiod", slowperiod, 2, 100_000)
    unstable = checkunstable(unstable)
    return barindicator(MassIndexSpec(fastperiod, slowperiod, unstable), (name,), high,
        low)
end

# ---------------------------------------------------------------------------
# RVI

struct RVISpec
    period::Int
    sdperiod::Int
    unstable::Unstable
end

mutable struct RVIKernel{S,W,T}
    const std::S
    const up::W
    const dn::W
    const unstable::Int
    started::Bool
    prevx::T
end

function barkernel(s::RVISpec, ::Type{T}) where {T}
    sd = CausalFrames.barwindow(Std(:x; corrected = false), s.sdperiod, (x = T,))
    w = WilderKernel(T, s.period)
    u = unstablecount(s.unstable, autoratio, s.period)
    return RVIKernel(sd, w, fresh(w), u, false, zero(T))
end
function CausalFrames.fresh!(k::RVIKernel{S,W,T}) where {S,W,T}
    fresh!(k.std)
    fresh!(k.up)
    fresh!(k.dn)
    k.started = false
    k.prevx = zero(T)
    return k
end

# ta_RVI.c: the window's population standard deviation goes to the up leg on a
# rising bar and to the down leg on a falling one (a flat bar feeds 0 to both),
# each leg Wilder-smoothed; the index is the up leg's share, 50 when both are 0.
@inline function barstep!(k::RVIKernel{S,W,T}, x::T) where {S,W,T}
    d = x - k.prevx
    started = k.started
    k.started = true
    k.prevx = x
    update!(k.std, (x = x,))
    sigma = value(k.std).x_std
    (ismissing(sigma) || !started) && return nothing
    step!(k.up, d > 0 ? sigma : zero(T))
    step!(k.dn, d < 0 ? sigma : zero(T))
    nseen(k.up) > lookback(k.up) + k.unstable || return nothing
    up, dn = k.up.prev, k.dn.prev
    total = up + dn
    return (total == 0 ? T(50) : 100 * (up / total),)
end

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

$DAILY_DOC
$AUTO_DOC
$AUTO_FLAT_DOC
TA-Lib: `ta_codegen/input/rvi/rvi.yaml`, `rvi.md`.
"""
function RVI(column::ColumnSpec; period::Integer = 14, stddevperiod::Integer = 10,
    unstable::UnstableArg = 0, name::Symbol = :rvi)
    checkrange("RVI", "period", period, 1, 100_000)
    checkrange("RVI", "stddevperiod", stddevperiod, 2, 100_000)
    unstable = checkunstable(unstable)
    return barindicator(RVISpec(period, stddevperiod, unstable),
        (outname(colname(column), name),), column)
end
