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

An EMA kernel over element type `T` (see [`floattype`](@ref)). `k` is the
smoothing factor; MACDFix and T3 pass their own.
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
        e.prev = fma(v - e.prev, e.k, e.prev)
    else
        seedadd!(e.seed, v)
        n < e.period && return missing
        e.prev = seedtotal(e.seed) / e.period
    end
    return e.prev
end
