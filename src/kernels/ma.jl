# TA-Lib's moving-average family behind one type: the `matype` symbol is
# dispatched once at construction into the parameter `M`, so the fold never
# branches on it. Each stage adds the MA types its indicators need.
#
# Unlike the other kernels, an `MAKernel`'s `lookback` is TA-Lib's whole
# lookback for the type, unstable period included, and `step!` returns
# `missing` until it has passed: it is the kernel the indicators emit from
# directly.

"""
TA-Lib's MA types as CausalIndicators' `matype` symbols, in `TA_MAType` order.
TA-Lib's `TA_MAType_DISABLED` and `TA_MAType_DEFAULT` (10 and 11, between
`:hma` and `:zlema`) have no symbol.
"""
const MATYPES = (:sma, :ema, :wma, :dema, :tema, :trima, :kama, :mama, :t3, :hma,
    :zlema, :rma)

"""
The MA types whose TA-Lib lookback includes an unstable period: their own
(`:ema`, `:kama`, `:mama`, `:t3`, `:rma`) or EMA's, which `:dema`, `:tema` and
`:zlema` inherit.
"""
const UNSTABLE_MATYPES = (:ema, :dema, :tema, :kama, :mama, :t3, :zlema, :rma)

mutable struct MAKernel{M,K}
    const inner::K
    const lookback::Int
    n::Int
end

"""
    MAKernel(T, matype, period; unstable = 0, vfactor = 0.7, identity = true)

The `matype` moving average over `period` bars, element type `T`. `matype` is one
of [`MATYPES`](@ref).

- `unstable` is TA-Lib's unstable period, for the types in
  [`UNSTABLE_MATYPES`](@ref); the others ignore it.
- `vfactor` is T3's volume factor; `TA_MA` always uses 0.7.
- `identity = true` is `TA_MA`'s convention at period 1: a copy with lookback 0,
  whatever `unstable` is. With `false` the period-1 lookback is the type's own
  function's, which the unstable period still delays (`TA_DEMA` by twice it).
"""
function MAKernel(::Type{T}, matype::Symbol, period::Integer; unstable::Integer = 0,
    vfactor::Real = 0.7, identity::Bool = true) where {T}
    matype in MATYPES || throw(
        ArgumentError(
            "MAKernel matype must be one of $(join(map(repr, MATYPES), ", ")), " *
            "got $(repr(matype))",
        ))
    p = checkperiod("MAKernel", period)
    u = identity && p == 1 ? 0 : checkunstable(unstable)
    inner = makernel(Val(matype), T, p, u, vfactor)
    lb = identity && p == 1 ? 0 : malookback(Val(matype), p, u)
    return MAKernel{matype,typeof(inner)}(inner, lb, 0)
end

makernel(::Val{:sma}, ::Type{T}, p, u, vf) where {T} = SMAKernel(T, p)
makernel(::Val{:ema}, ::Type{T}, p, u, vf) where {T} = EMAKernel(T, p)
makernel(::Val{:wma}, ::Type{T}, p, u, vf) where {T} = WMAKernel(T, p)
makernel(::Val{:dema}, ::Type{T}, p, u, vf) where {T} = DEMAKernel(T, p; unstable = u)
makernel(::Val{:tema}, ::Type{T}, p, u, vf) where {T} = TEMAKernel(T, p; unstable = u)
makernel(::Val{:trima}, ::Type{T}, p, u, vf) where {T} = TRIMAKernel(T, p)
makernel(::Val{:kama}, ::Type{T}, p, u, vf) where {T} = KAMAKernel(T, p)
# TA_MA's MAMA ignores the period and uses the default limits (ta_MA.c).
makernel(::Val{:mama}, ::Type{T}, p, u, vf) where {T} =
    MAMAKernel(T, 0.5, 0.05; copy = p == 1)
makernel(::Val{:t3}, ::Type{T}, p, u, vf) where {T} = T3Kernel(T, p, vf)
makernel(::Val{:hma}, ::Type{T}, p, u, vf) where {T} = HMAKernel(T, p)
makernel(::Val{:zlema}, ::Type{T}, p, u, vf) where {T} = ZLEMAKernel(T, p)
makernel(::Val{:rma}, ::Type{T}, p, u, vf) where {T} = WilderKernel(T, p)

# TA-Lib's `TA_<FN>_Lookback` for each type at period `p` and unstable period
# `u` (ta_MA.c's dispatch, then each function's own).
malookback(::Val{:sma}, p, u) = p - 1
malookback(::Val{:ema}, p, u) = p - 1 + u
malookback(::Val{:wma}, p, u) = p - 1
malookback(::Val{:dema}, p, u) = 2 * (p - 1 + u)
malookback(::Val{:tema}, p, u) = 3 * (p - 1 + u)
malookback(::Val{:trima}, p, u) = p - 1
malookback(::Val{:kama}, p, u) = (p == 1 ? 0 : p) + u
malookback(::Val{:mama}, p, u) = 32 + u
malookback(::Val{:t3}, p, u) = 6 * (p - 1) + u
malookback(::Val{:hma}, p, u) = (p - 1) + (isqrt(p) - 1)
malookback(::Val{:zlema}, p, u) = (p - 1) ÷ 2 + p - 1 + u
malookback(::Val{:rma}, p, u) = p - 1 + u

CausalFrames.fresh(m::MAKernel{M,K}) where {M,K} =
    MAKernel{M,K}(fresh(m.inner), m.lookback, 0)
function CausalFrames.fresh!(m::MAKernel)
    m.n = 0
    fresh!(m.inner)
    return m
end

lookback(m::MAKernel) = m.lookback
nseen(m::MAKernel) = m.n
current(m::MAKernel) = m.n > m.lookback ? current(m.inner) : missing

@inline function step!(m::MAKernel, x::Real)
    m.n += 1
    v = step!(m.inner, x)
    return m.n > m.lookback ? v : missing
end

"""
    fixedemakernel(T, period, k; unstable = 0) -> MAKernel{:ema}

An `:ema` `MAKernel` with smoothing factor `k` in place of `2 / (period + 1)`:
MACDFix's fixed 12- and 26-bar EMAs (`k = 0.15` and `0.075`, ta_MACDFIX.c).
"""
function fixedemakernel(
    ::Type{T},
    period::Integer,
    k::Real;
    unstable::Integer = 0,
) where {T}
    e = EMAKernel(T, period, k)
    return MAKernel{:ema,typeof(e)}(e,
        malookback(Val(:ema), e.period,
            checkunstable(unstable)), 0)
end
