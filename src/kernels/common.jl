# Kernels are the recursive building blocks of the plain indicators: mutable
# structs embedded as concrete fields of an indicator's state, never summarizers
# themselves. Window sums, extrema and ring buffers are not kernels; those are
# CausalFrames states, embedded through `CausalFrames.barwindow`.
#
# A kernel `k` over element type `T` implements
#
# - `step!(k, x)::Union{Missing,T}` folds one bar and returns the kernel's value
#   after it, `missing` until the kernel has seen `lookback(k) + 1` bars. A
#   `missing` bar is skipped: it leaves the kernel unchanged and returns
#   `missing` (DESIGN.md, "Missing and non-finite inputs").
# - `current(k)::Union{Missing,T}` is the value after the last bar folded.
# - `nseen(k)` counts the non-`missing` bars folded, so an indicator emits from
#   `nseen(k) > lookback(k) + unstable`. (`MAKernel` folds `unstable` into its
#   own `lookback` and gates `step!` itself; see kernels/ma.jl.)
# - `lookback(k)` is TA-Lib's lookback for the kernel's parameters.
# - `fresh(k)` returns a new zero kernel with the same parameters, and `fresh!(k)`
#   zeroes `k` in place and returns it; `step!` and `fresh!` do not allocate.

"""
    floattype(T) -> Type

The element type a kernel computes in for an input column of type `T`.
Integers widen to `Float64`, and a float wider than `Float64` is kept.
"""
floattype(::Type{T}) where {T} = promote_type(Float64, float(nonmissingtype(T)))

"""
    step!(k, x) -> Union{Missing,T}

Fold the bar `x` into kernel `k` and return the kernel's value after it.
A `missing` bar leaves `k` unchanged and returns `missing`.
"""
function step! end

step!(::Any, ::Missing) = missing

# The CausalFrames `Sum` state a kernel seeds from: one compensated sum shared by
# every seed in the package.
seedsum(::Type{T}) where {T} = fresh(Sum(:x), (x = T,))
@inline seedadd!(s, x) = update!(s, (x = x,))
@inline seedtotal(s) = value(s).x_sum

function checkperiod(kernel, period)
    period >= 1 || throw(ArgumentError("$kernel period must be positive, got $period"))
    return Int(period)
end

"""
    AutoLevel(K, X)

TA-Lib's Auto-Stabilization level as an `unstable` value: `:auto4` is
`TA_UNSTABLE_AUTO_PREC_4` (`K = 10` e-folds, `X = 4` digits) and `:auto8` is
`TA_UNSTABLE_AUTO_PREC_8` (`K = 19`, `X = 8`). Under a level each unstable id
drops the bars its function's rule gives at the call's parameters, the `c4` and
`c8` of its `TA_GLOBALS_UNSTABLE` read. A rule written in `K` is a bound, one
written in `X` a measurement (TA-Lib's `docs/auto-stabilization-rule.md`).
"""
struct AutoLevel
    K::Int
    X::Int
end

const AUTO4 = AutoLevel(10, 4)
const AUTO8 = AutoLevel(19, 8)

# An `unstable` keyword's value: a count, `:auto4` or `:auto8` as given, and a
# stored count or a level once checked.
const UnstableArg = Union{Integer,Symbol,AutoLevel}
const Unstable = Union{Int,AutoLevel}

function checkunstable(unstable::Integer)
    unstable >= 0 ||
        throw(ArgumentError("unstable period must be non-negative, got $unstable"))
    return Int(unstable)
end
function checkunstable(unstable::Symbol)
    unstable === :auto4 && return AUTO4
    unstable === :auto8 && return AUTO8
    throw(
        ArgumentError(
            "unstable must be a non-negative count, :auto4 or :auto8, got $(repr(unstable))",
        ),
    )
end
# TA-Lib defines only these two levels; its rules are not checked at others.
function checkunstable(a::AutoLevel)
    a === AUTO4 || a === AUTO8 ||
        throw(
            ArgumentError(
                "unstable must be a non-negative count, :auto4 or :auto8, got $a",
            ),
        )
    return a
end

# The count of an unstable id under `u`: a stored count as is, or under a level
# its rule at the call's parameters, as `TA_GLOBALS_UNSTABLE` reads it.
unstablecount(u::Int, rule, args...) = u
unstablecount(a::AutoLevel, rule, args...) = rule(a, args...)::Int

# What a function adds on top of an id it inherits: nothing under a stored
# count, its own offset under a level (`TA_GLOBALS_UNSTABLE_AUTO`, `_OFFSET`).
unstableoffset(u::Int, rule, args...) = 0
unstableoffset(a::AutoLevel, rule, args...) = rule(a, args...)::Int

# TA-Lib's rules (ta_codegen/input/helpers/auto_stabilization.c and each
# function's lookback), at the level `a`.
#
# A one-pole EMA, pole (p − 1)/(p + 1): p/2 bars an e-fold (EMA).
autoema(a, p) = p > 1 ? (a.K * p + 1) ÷ 2 : 0
# Wilder's smoothing, pole 1 − 1/p: p − 1/2 bars an e-fold (RMA, ATR, ±DM).
autowilder(a, p) = p > 1 ? (a.K * (2p - 1) + 1) ÷ 2 : 0
# An output that divides by Wilder-smoothed values (RSI, CMO, ±DI, DX, NATR,
# RVI on its `period`).
autoratio(a, p) = p > 1 ? a.K * p : 0
# ADX: the DX's ratio, then a second Wilder stage.
autoadx(a, p) = (a.K + 6) * p
# KAMA, measured: its smoothing constant moves with the data.
autokama(a, p) = p == 1 ? 0 : 25 * a.X * isqrt(p)
# T3's six chained EMAs, measured.
autot3(a, p) = p > 1 ? (11 * (a.X + 4) * p + 7) ÷ 8 : 0
# Heikin-Ashi's open, a pole at 1/2.
autoha(a) = (13 * a.K + 8) ÷ 9
# The Hilbert core, measured; the trendline and trend mode read a period cut to
# whole bars.
autohilbert(a) = 80 + 50 * a.X
autohttrend(a) = 120 + 20 * a.X
# MAMA: the Hilbert core, then the larger (faster) of its limits as a pole,
# as ta_MAMA.c's `limit` takes it.
automama(a, fastlimit, slowlimit) =
    autohilbert(a) + ceil(Int, 2 * a.K / max(fastlimit, slowlimit))
# ADOSC's offset on EMA's count: what its two EMAs, seeded on one value, can
# cancel. The sum stands for the fast period times the log of the ratio.
function autoadosc(a, fastperiod, slowperiod)
    f, s = minmax(fastperiod, slowperiod)
    return (15 * f + 3 * sum(j -> min(s >> j, f), 1:16) + 7) ÷ 8
end

# TA-Lib's zero tests (ta_utility.h): `TA_IS_ZERO`, a fixed band, and
# `TA_IS_ZERO_SCALED`, a band relative to the operands' magnitude `scale`
# (|a| + |b| for a difference a − b). The indicators that guard a division with
# one use the same test, so a flat window gives TA-Lib's 0 rather than a
# quotient of round-off.
const TA_EPSILON = 1e-14
@inline iszerota(v) = -TA_EPSILON < v < TA_EPSILON
@inline iszeroscaled(v, scale) = abs(v) <= TA_EPSILON * scale

# TA-Lib's true range: the bar's range widened to the previous close.
@inline truerange(h, l, cprev) = max(h - l, abs(cprev - h), abs(cprev - l))

# A `First` over the last `n` bars: the value `n − 1` bars back.
lagged(n, ::Type{T}) where {T} = CausalFrames.barwindow(First(:x), n, (x = T,))

# Lag lines: a CausalFrames `WindowValues` under `barwindow`, prefilled with
# zeros so it is full from the first bar (which also gets past `barwindow`'s
# missing-until-full gate). `WindowValues` counts NaN rather than storing it, so
# a lag line must only ever be fed non-NaN values, or its lags misalign. The
# Hilbert core (kernels/hilbert.jl) and the candlesticks (kernels/candle.jl)
# use them. `lagwindow(T, n)` holds `n` zeros' worth of history.
lagwindow(::Type{T}, n) where {T} =
    prefill!(CausalFrames.barwindow(CausalFrames.WindowValues(:x), n, (x = T,)), n, T)
function prefill!(w, n, ::Type{T}) where {T}
    for _ in 1:n
        update!(w, (x = zero(T),))
    end
    return w
end
refill!(w, n, ::Type{T}) where {T} = prefill!(fresh!(w), n, T)

# The window's values, oldest first in `vals[head:end]`; `lag(v, k)` is the
# value `k` bars back (0 = newest). Prefilled, the window is always full.
@inline windowvals(w) = value(w).x_windowvalues
@inline lag(wv, k) = @inbounds wv.vals[end-k]
