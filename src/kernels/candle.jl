# The candlestick kernel (S7): TA-Lib's candle settings, the per-setting
# averages every pattern compares against, and the bars a pattern reads back.
#
# TA-Lib measures a candle part against `factor` times the average of the same
# measure over the `avgperiod` bars before the candle (ta_utility.h,
# TA_CANDLEAVERAGE). Each setting a pattern reads is one `CandleAverage`: a
# CausalFrames `Mean` under `barwindow` over the measure, and a lag line of the
# threshold each bar was compared against. A bar's threshold is formed before
# its own measure is folded, so it is the average of the bars before it, as in
# TA-Lib. A pattern reading a setting at bar `i − ℓ` reads that lag line `ℓ`
# back. The bars themselves are four more lag lines.
#
# `WindowValues` counts NaN rather than storing it, so the lag lines are fed a
# 0 for a NaN price or threshold, and the kernel remembers the last bar that
# had one: a pattern emits 0 while such a bar is among those it reads.

@enum CandleRange::UInt8 RANGE_REALBODY RANGE_HIGHLOW RANGE_SHADOWS

const CANDLE_RANGES = (realbody = RANGE_REALBODY, highlow = RANGE_HIGHLOW,
    shadows = RANGE_SHADOWS)

"""
    CandleSetting(range::Symbol, avgperiod::Integer, factor::Real)

One of TA-Lib's candle settings (`TA_SetCandleSettings`): a candle part is
compared with `factor` times the average `range` of the `avgperiod` bars before
it, or with the candle's own `range` when `avgperiod` is 0. `range` is
`:realbody` (`|close − open|`), `:highlow` (`high − low`) or `:shadows` (the
sum of both shadows, halved when averaged). `avgperiod` must be in
[0, 100000000] and `factor` must not be NaN, as `TA_SetCandleSettings`
requires. A negative factor is allowed, as in TA-Lib, and makes a "longer
than" test always true.
"""
struct CandleSetting
    range::CandleRange
    avgperiod::Int
    factor::Float64
    function CandleSetting(range::Symbol, avgperiod::Integer, factor::Real)
        haskey(CANDLE_RANGES, range) || throw(
            ArgumentError(
                "CandleSetting range must be :realbody, :highlow or :shadows, " *
                "got $(repr(range))"))
        checkrange("CandleSetting", "avgperiod", avgperiod, 0, 100_000_000)
        isnan(factor) && throw(ArgumentError("CandleSetting factor must not be NaN"))
        return new(CANDLE_RANGES[range], Int(avgperiod), Float64(factor))
    end
end

rangename(r::CandleRange) =
    r === RANGE_REALBODY ? :realbody : r === RANGE_HIGHLOW ? :highlow : :shadows
Base.show(io::IO, s::CandleSetting) =
    print(io, "CandleSetting(", repr(rangename(s.range)), ", ", s.avgperiod, ", ",
        s.factor, ")")

"""
    CandleSettings(; bodylong, bodyverylong, bodyshort, bodydoji, shadowlong,
                   shadowverylong, shadowshort, shadowveryshort, near, far, equal)

TA-Lib's 11 candle settings, which every candlestick pattern takes as its
`settings` keyword. Each is a [`CandleSetting`](@ref), and each defaults to
TA-Lib's (ta_global.c):

| setting | range | avgperiod | factor |
|---|---|---|---|
| `bodylong` | `:realbody` | 10 | 1.0 |
| `bodyverylong` | `:realbody` | 10 | 3.0 |
| `bodyshort` | `:realbody` | 10 | 1.0 |
| `bodydoji` | `:highlow` | 10 | 0.1 |
| `shadowlong` | `:realbody` | 0 | 1.0 |
| `shadowverylong` | `:realbody` | 0 | 2.0 |
| `shadowshort` | `:shadows` | 10 | 1.0 |
| `shadowveryshort` | `:highlow` | 10 | 0.1 |
| `near` | `:highlow` | 5 | 0.2 |
| `far` | `:highlow` | 5 | 0.6 |
| `equal` | `:highlow` | 5 | 0.05 |

TA-Lib keeps these in a global table (`TA_SetCandleSettings`); here they are an
immutable value, so two calls can use different settings. No pattern reads
`bodyverylong`, in TA-Lib either. The averaging periods count bars, and the
defaults are their authors' for daily bars.
"""
Base.@kwdef struct CandleSettings
    bodylong::CandleSetting = CandleSetting(:realbody, 10, 1.0)
    bodyverylong::CandleSetting = CandleSetting(:realbody, 10, 3.0)
    bodyshort::CandleSetting = CandleSetting(:realbody, 10, 1.0)
    bodydoji::CandleSetting = CandleSetting(:highlow, 10, 0.1)
    shadowlong::CandleSetting = CandleSetting(:realbody, 0, 1.0)
    shadowverylong::CandleSetting = CandleSetting(:realbody, 0, 2.0)
    shadowshort::CandleSetting = CandleSetting(:shadows, 10, 1.0)
    shadowveryshort::CandleSetting = CandleSetting(:highlow, 10, 0.1)
    near::CandleSetting = CandleSetting(:highlow, 5, 0.2)
    far::CandleSetting = CandleSetting(:highlow, 5, 0.6)
    equal::CandleSetting = CandleSetting(:highlow, 5, 0.05)
end

# TA-Lib's candle measures (ta_utility.h), in its operation order.
@inline cmin(a, b) = a < b ? a : b    # the C min/max macros
@inline cmax(a, b) = a > b ? a : b
@inline realbody(o, c) = abs(c - o)
@inline uppershadow(o, h, c) = h - (c >= o ? c : o)
@inline lowershadow(o, l, c) = (c >= o ? o : c) - l

# TA_CANDLERANGE
@inline function candlerange(s::CandleSetting, o::T, h::T, l::T, c::T) where {T}
    r = s.range
    r === RANGE_REALBODY && return realbody(o, c)
    r === RANGE_HIGHLOW && return h - l
    return uppershadow(o, h, c) + lowershadow(o, l, c)
end

# TA_CANDLEAVERAGE, with the mean of the bars before already divided out.
@inline function candleaverage(s::CandleSetting, mean::T, range::T) where {T}
    v = T(s.factor) * (s.avgperiod != 0 ? mean : range)
    return s.range === RANGE_SHADOWS ? v / T(2) : v    # TA-Lib's `/ 1.0` is exact
end

struct CandleAverage{T,W,L}
    setting::CandleSetting
    window::W   # barwindow(Mean(:x), max(avgperiod, 1)) over the measure
    thr::L      # lagwindow: each bar's threshold
end

function CandleAverage(::Type{T}, s::CandleSetting, nbars::Integer) where {T}
    w = CausalFrames.barwindow(Mean(:x), max(s.avgperiod, 1), (x = T,))
    l = lagwindow(T, nbars)
    return CandleAverage{T,typeof(w),typeof(l)}(s, w, l)
end

CausalFrames.fresh(a::CandleAverage{T,W,L}) where {T,W,L} =
    CandleAverage{T,W,L}(a.setting, fresh(a.window), fresh(a.thr))
function fresh_avg!(a::CandleAverage{T}, nbars) where {T}
    fresh!(a.window)
    refill!(a.thr, nbars, T)
    return a
end

# Fold one bar: push its threshold, then fold its measure. Returns whether the
# threshold is non-finite. Before the window fills the threshold is never read,
# and 0 stands in.
@inline function step!(a::CandleAverage{T}, o::T, h::T, l::T, c::T) where {T}
    s = a.setting
    r = candlerange(s, o, h, l, c)
    m = value(a.window).x_mean
    thr =
        s.avgperiod == 0 ? candleaverage(s, zero(T), r) :
        m === missing ? zero(T) : candleaverage(s, m, r)
    bad = !isfinite(thr)
    update!(a.thr, (x = bad ? zero(T) : thr,))
    update!(a.window, (x = r,))
    return bad
end

# The Hikkake family's pattern state (ta_CDLHIKKAKE.c, ta_CDLHIKKAKEMOD.c): a
# countdown of the bars a confirmation may still come in, the last pattern's
# sign, and the high and low a confirmation must close beyond.
mutable struct HikkakeState{T}
    count::Int
    result::Int
    high::T
    low::T
end
HikkakeState{T}() where {T} = HikkakeState{T}(0, 0, zero(T), zero(T))
CausalFrames.fresh(::HikkakeState{T}) where {T} = HikkakeState{T}()
function CausalFrames.fresh!(st::HikkakeState{T}) where {T}
    st.count = st.result = 0
    st.high = st.low = zero(T)
    return st
end
hikkakefresh(::Nothing) = nothing
hikkakefresh(st) = fresh(st)
hikkakefresh!(::Nothing) = nothing
hikkakefresh!(st) = fresh!(st)

"""
    CandleKernel{P,T}

The state of candlestick pattern `P` over element type `T`: the averages of the
settings `P` reads (a `NamedTuple` of `CandleAverage`s keyed by setting), lag
lines of the last `nbars` bars' prices, and the Hikkake state where `P` has
one. `n` counts the bars folded and `lastbad` is the last with a non-finite
price or threshold.
"""
mutable struct CandleKernel{P,T,A<:NamedTuple,L,H}
    const lookback::Int
    const nbars::Int
    const penetration::T
    const avgs::A
    const open::L
    const high::L
    const low::L
    const close::L
    const hikkake::H
    n::Int
    lastbad::Int
end

const NEVER = typemin(Int) ÷ 2

function CandleKernel{P}(::Type{T}, settings::CandleSettings, penetration,
    lookback::Integer, nbars::Integer, names::Tuple{Vararg{Symbol}}, hikkake) where {P,T}
    avgs =
        NamedTuple{names}(map(s -> CandleAverage(T, getfield(settings, s), nbars), names))
    o, h, l, c = (lagwindow(T, nbars) for _ in 1:4)
    return CandleKernel{P,T,typeof(avgs),typeof(o),typeof(hikkake)}(Int(lookback),
        Int(nbars), T(penetration), avgs, o, h, l, c, hikkake, 0, NEVER)
end

CausalFrames.fresh(k::CandleKernel{P,T,A,L,H}) where {P,T,A,L,H} =
    CandleKernel{P,T,A,L,H}(k.lookback, k.nbars, k.penetration, map(fresh, k.avgs),
        fresh(k.open), fresh(k.high), fresh(k.low), fresh(k.close),
        hikkakefresh(k.hikkake), 0, NEVER)
function CausalFrames.fresh!(k::CandleKernel{P,T}) where {P,T}
    n = k.nbars
    foreach(a -> fresh_avg!(a, n), values(k.avgs))
    refill!(k.open, n, T)
    refill!(k.high, n, T)
    refill!(k.low, n, T)
    refill!(k.close, n, T)
    hikkakefresh!(k.hikkake)
    k.n = 0
    k.lastbad = NEVER
    return k
end

nseen(k::CandleKernel) = k.n
lookback(k::CandleKernel) = k.lookback

@inline nanzero(x::T) where {T} = isnan(x) ? zero(T) : x

# Fold one bar into the averages and the lag lines.
@inline function stepbars!(k::CandleKernel{P,T}, o::T, h::T, l::T, c::T) where {P,T}
    k.n += 1
    bad = !(isfinite(o) & isfinite(h) & isfinite(l) & isfinite(c))
    bad |= any(map(a -> step!(a, o, h, l, c), values(k.avgs)))
    update!(k.open, (x = nanzero(o),))
    update!(k.high, (x = nanzero(h),))
    update!(k.low, (x = nanzero(l),))
    update!(k.close, (x = nanzero(c),))
    bad && (k.lastbad = k.n)
    return nothing
end

# Whether every bar the pattern reads, and every threshold, is finite.
@inline candleclean(k::CandleKernel) = k.n - k.lastbad >= k.nbars

"""
    CandleBars

The bars and thresholds a pattern reads, borrowed from its kernel for one bar:
`op(b, ℓ)`, `hi`, `lo` and `cl` are the prices `ℓ` bars back (0 = this bar),
and `avg(b, :setting, ℓ)` is the setting's threshold for that bar.
"""
struct CandleBars{T,V,A}
    o::V
    h::V
    l::V
    c::V
    avgs::A
    penetration::T
end

# A prefilled lag line is never empty, so its value is never `missing`: the
# assertion narrows the type, keeping `CandleBars` concrete.
@inline linevals(w) = windowvals(w)::CausalFrames.WindowValuesState

@inline candlebars(k::CandleKernel) =
    CandleBars(linevals(k.open), linevals(k.high), linevals(k.low), linevals(k.close),
        map(a -> linevals(a.thr), k.avgs), k.penetration)

@inline op(b::CandleBars, ℓ) = lag(b.o, ℓ)
@inline hi(b::CandleBars, ℓ) = lag(b.h, ℓ)
@inline lo(b::CandleBars, ℓ) = lag(b.l, ℓ)
@inline cl(b::CandleBars, ℓ) = lag(b.c, ℓ)
@inline avg(b::CandleBars, s::Symbol, ℓ) = lag(getfield(b.avgs, s), ℓ)

# The pattern measures of bar `ℓ` back, as ta_utility.h and the pattern files
# spell them.
@inline body(b, ℓ) = realbody(op(b, ℓ), cl(b, ℓ))                   # fabs(c − o)
@inline upper(b, ℓ) = uppershadow(op(b, ℓ), hi(b, ℓ), cl(b, ℓ))
@inline lower(b, ℓ) = lowershadow(op(b, ℓ), lo(b, ℓ), cl(b, ℓ))
@inline color(b, ℓ) = cl(b, ℓ) >= op(b, ℓ) ? 1 : -1                 # TA_CANDLECOLOR
@inline white(b, ℓ) = color(b, ℓ) == 1
@inline black(b, ℓ) = color(b, ℓ) == -1
@inline bodytop(b, ℓ) = cmax(op(b, ℓ), cl(b, ℓ))                     # max(o, c)
@inline bodybot(b, ℓ) = cmin(op(b, ℓ), cl(b, ℓ))                     # min(o, c)
# TA_REALBODYGAPUP/DOWN(ℓ2, ℓ1) and TA_CANDLEGAPUP/DOWN(ℓ2, ℓ1): bar ℓ2's body
# or range clears bar ℓ1's.
@inline bodygapup(b, ℓ2, ℓ1) = cmin(op(b, ℓ2), cl(b, ℓ2)) > cmax(op(b, ℓ1), cl(b, ℓ1))
@inline bodygapdown(b, ℓ2, ℓ1) = cmax(op(b, ℓ2), cl(b, ℓ2)) < cmin(op(b, ℓ1), cl(b, ℓ1))
@inline gapup(b, ℓ2, ℓ1) = lo(b, ℓ2) > hi(b, ℓ1)
@inline gapdown(b, ℓ2, ℓ1) = hi(b, ℓ2) < lo(b, ℓ1)
