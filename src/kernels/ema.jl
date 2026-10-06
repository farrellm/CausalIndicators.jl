# TA-Lib's exponential moving average (ta_EMA.c, default compatibility mode). The
# first `period` bars seed it with their simple average, taken through a
# CausalFrames compensated `Sum`; each later bar moves it by `k` toward the bar,
# as `fma(x - prev, k, prev)`.
mutable struct EMAKernel{T,S}
    const period::Int
    const k::T
    n::Int
    prev::T
    const seed::S
end

"""
    EMAKernel(T, period[, k = 2 / (period + 1)])

An EMA kernel over element type `T` (see [`floattype`](@ref)), seeded with
the simple average of its first `period` bars. `k` is the smoothing factor;
MACDFix passes its own, and ADOSC passes its periods' factors at `period = 1`,
an EMA seeded with its first bar.
"""
function EMAKernel(::Type{T}, period::Integer, k::Real = 2 / (period + 1)) where {T}
    p = checkperiod("EMAKernel", period)
    return EMAKernel{T,typeof(seedsum(T))}(p, T(k), 0, zero(T), seedsum(T))
end

CausalFrames.fresh(e::EMAKernel{T}) where {T} = EMAKernel(T, e.period, e.k)
function CausalFrames.fresh!(e::EMAKernel{T}) where {T}
    e.n = 0
    e.prev = zero(T)
    fresh!(e.seed)
    return e
end

lookback(e::EMAKernel) = e.period - 1
nseen(e::EMAKernel) = e.n
current(e::EMAKernel{T}) where {T} =
    (e.n >= e.period ? e.prev : missing)::Union{Missing,T}

function step!(e::EMAKernel{T}, x::Real) where {T}
    v = convert(T, x)
    n = e.n += 1
    if n > e.period
        # `k = 1` (period 1) copies the bar (TA-Lib's period1_identity); the
        # recursion would lose it to the rounding of `v - prev`.
        e.prev = isone(e.k) ? v : fma(v - e.prev, e.k, e.prev)
    else
        seedadd!(e.seed, v)
        n < e.period && return missing
        e.prev = seedtotal(e.seed) / e.period
    end
    return e.prev
end

# Whether EMA kernel `e` has emitted past `unstable` extra bars: the bar from
# which TA-Lib's DEMA and TEMA feed it to the next stage (ta_DEMA.c advances
# EMA1 through its unstable period before EMA2 seeds).
@inline emitted(e::EMAKernel, unstable) = e.n > lookback(e) + unstable

# TA-Lib's DEMA (ta_DEMA.c): `2·EMA1 − EMA2`, where EMA2 smooths EMA1 and seeds
# from EMA1's first `period` emitted values. EMA's unstable period delays each
# stage, so unlike EMA's own it changes the values, not only the first bar.
mutable struct DEMAKernel{T,S}
    const unstable::Int
    n::Int
    out::Union{Missing,T}
    const e1::EMAKernel{T,S}
    const e2::EMAKernel{T,S}
end

"""
    DEMAKernel(T, period; unstable = 0)

TA-Lib's double EMA over element type `T`, with EMA's unstable period
`unstable` applied to both stages.
"""
function DEMAKernel(::Type{T}, period::Integer; unstable::Integer = 0) where {T}
    e = EMAKernel(T, period)
    return DEMAKernel{T,typeof(e.seed)}(checkunstable(unstable), 0, missing, e, fresh(e))
end

CausalFrames.fresh(d::DEMAKernel{T}) where {T} =
    DEMAKernel(T, d.e1.period; unstable = d.unstable)
function CausalFrames.fresh!(d::DEMAKernel)
    d.n = 0
    d.out = missing
    fresh!(d.e1)
    fresh!(d.e2)
    return d
end

lookback(d::DEMAKernel) = 2 * (lookback(d.e1) + d.unstable)
nseen(d::DEMAKernel) = d.n
current(d::DEMAKernel) = d.out

function step!(d::DEMAKernel{T}, x::Real) where {T}
    d.n += 1
    v1 = step!(d.e1, x)
    emitted(d.e1, d.unstable) || return missing
    v2 = step!(d.e2, v1::T)
    emitted(d.e2, d.unstable) || return missing
    return d.out = 2 * (v1::T) - v2::T
end

# TA-Lib's TEMA (ta_TEMA.c): `EMA3 + (3·EMA1 − 3·EMA2)`, three chained stages
# seeded and delayed as DEMA's.
mutable struct TEMAKernel{T,S}
    const unstable::Int
    n::Int
    out::Union{Missing,T}
    const e1::EMAKernel{T,S}
    const e2::EMAKernel{T,S}
    const e3::EMAKernel{T,S}
end

"""
    TEMAKernel(T, period; unstable = 0)

TA-Lib's triple EMA over element type `T`, with EMA's unstable period
`unstable` applied to each stage.
"""
function TEMAKernel(::Type{T}, period::Integer; unstable::Integer = 0) where {T}
    e = EMAKernel(T, period)
    return TEMAKernel{T,typeof(e.seed)}(checkunstable(unstable), 0, missing, e,
        fresh(e), fresh(e))
end

CausalFrames.fresh(t::TEMAKernel{T}) where {T} =
    TEMAKernel(T, t.e1.period; unstable = t.unstable)
function CausalFrames.fresh!(t::TEMAKernel)
    t.n = 0
    t.out = missing
    fresh!(t.e1)
    fresh!(t.e2)
    fresh!(t.e3)
    return t
end

lookback(t::TEMAKernel) = 3 * (lookback(t.e1) + t.unstable)
nseen(t::TEMAKernel) = t.n
current(t::TEMAKernel) = t.out

function step!(t::TEMAKernel{T}, x::Real) where {T}
    t.n += 1
    v1 = step!(t.e1, x)
    emitted(t.e1, t.unstable) || return missing
    v2 = step!(t.e2, v1::T)
    emitted(t.e2, t.unstable) || return missing
    v3 = step!(t.e3, v2::T)
    emitted(t.e3, t.unstable) || return missing
    return t.out = v3::T + (3 * (v1::T) - 3 * (v2::T))
end

# Tillson's T3 (ta_T3.c): six chained EMAs with `k = 2 / (period + 1)`, each
# seeded from the previous one's first `period` values, combined with
# coefficients from the volume factor. T3's own unstable period only delays the
# first output (ta_T3.c skips it after seeding), so the kernel has none.
mutable struct T3Kernel{T,S}
    const c1::T
    const c2::T
    const c3::T
    const c4::T
    const vfactor::T
    n::Int
    out::Union{Missing,T}
    const e::NTuple{6,EMAKernel{T,S}}
end

"""
    T3Kernel(T, period, vfactor = 0.7)

Tillson's T3 over element type `T`.
"""
function T3Kernel(::Type{T}, period::Integer, vfactor::Real = 0.7) where {T}
    0 <= vfactor <= 1 ||
        throw(ArgumentError("T3Kernel vfactor must be in [0, 1], got $vfactor"))
    e = EMAKernel(T, period)
    v = T(vfactor)
    v2 = v * v
    c1 = -(v2 * v)
    c2 = 3 * (v2 - c1)
    c3 = -6 * v2 - 3 * (v - c1)
    c4 = 1 + 3 * v - c1 + 3 * v2
    return T3Kernel{T,typeof(e.seed)}(c1, c2, c3, c4, v, 0, missing,
        (e, ntuple(_ -> fresh(e), Val(5))...))
end

CausalFrames.fresh(t::T3Kernel{T}) where {T} = T3Kernel(T, t.e[1].period, t.vfactor)
function CausalFrames.fresh!(t::T3Kernel)
    t.n = 0
    t.out = missing
    foreach(fresh!, t.e)
    return t
end

lookback(t::T3Kernel) = 6 * lookback(t.e[1])
nseen(t::T3Kernel) = t.n
current(t::T3Kernel) = t.out

function step!(t::T3Kernel{T}, x::Real) where {T}
    t.n += 1
    e1, e2, e3, e4, e5, e6 = t.e
    # Period 1 copies the bar; the coefficients sum to 1 only up to rounding.
    e1.period == 1 && return t.out = convert(T, x)
    v = step!(e6, step!(e5, step!(e4, step!(e3, step!(e2, step!(e1, x))))))
    ismissing(v) && return missing
    return t.out =
        t.c1 * v + t.c2 * current(e5)::T + t.c3 * current(e4)::T +
        t.c4 * current(e3)::T
end
