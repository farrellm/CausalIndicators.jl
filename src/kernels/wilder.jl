# Wilder's smoothing, in TA-Lib's two forms, seeded through a CausalFrames
# compensated `Sum`.
#
# - `:mean` (RMA, RSI, ATR): the average of the first `period` bars, then
#   `fma(β, prev, α * x)` with `β = (period - 1) / period` and `α = 1 - β`, the
#   order of ta_RMA.c.
# - `:sum` (±DM, the TR sum of ±DI and DX): the sum of the first `seedn` bars,
#   then `prev - prev / period + x` (ta_PLUS_DM.c, whose seed is `period - 1`
#   bars).
mutable struct WilderKernel{T,S,F}
    const period::Int
    const seedn::Int
    const alpha::T
    const beta::T
    n::Int
    prev::T
    const seed::S
end

"""
    WilderKernel(T, period; form = :mean, seedn = period)

A Wilder-smoothing kernel over element type `T`. `form` is `:mean` or `:sum`,
and `seedn` is the number of bars in the seed (the `:sum` form's ±DM seeds
`period - 1`).
"""
function WilderKernel(::Type{T}, period::Integer; form::Symbol = :mean,
    seedn::Integer = period) where {T}
    p = checkperiod("WilderKernel", period)
    form in (:mean, :sum) ||
        throw(ArgumentError("WilderKernel form must be :mean or :sum, got $(repr(form))"))
    seedn >= 1 || throw(ArgumentError("WilderKernel seedn must be positive, got $seedn"))
    beta = T(p - 1) / T(p)
    S = typeof(seedsum(T))
    return WilderKernel{T,S,form}(p, Int(seedn), one(T) - beta, beta, 0, zero(T),
        seedsum(T))
end

CausalFrames.fresh(w::WilderKernel{T,S,F}) where {T,S,F} =
    WilderKernel(T, w.period; form = F, seedn = w.seedn)
function CausalFrames.fresh!(w::WilderKernel{T}) where {T}
    w.n = 0
    w.prev = zero(T)
    fresh!(w.seed)
    return w
end

lookback(w::WilderKernel) = w.seedn - 1
nseen(w::WilderKernel) = w.n
current(w::WilderKernel{T}) where {T} =
    (w.n >= w.seedn ? w.prev : missing)::Union{Missing,T}

@inline smooth(w::WilderKernel{T,S,:mean}, x) where {T,S} = fma(w.beta, w.prev, w.alpha * x)
@inline smooth(w::WilderKernel{T,S,:sum}, x) where {T,S} = w.prev - w.prev / w.period + x

@inline seeded(w::WilderKernel{T,S,:mean}) where {T,S} = seedtotal(w.seed) / w.seedn
@inline seeded(w::WilderKernel{T,S,:sum}) where {T,S} = seedtotal(w.seed)

function step!(w::WilderKernel{T}, x::Real) where {T}
    v = convert(T, x)
    n = w.n += 1
    if n > w.seedn
        w.prev = smooth(w, v)
    else
        seedadd!(w.seed, v)
        n < w.seedn && return missing
        w.prev = seeded(w)
    end
    return w.prev
end
