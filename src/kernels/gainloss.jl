# Wilder-smoothed gains and losses (ta_RSI.c, ta_CMO.c): each bar's move from
# the previous one splits into a gain `max(Δ, 0)` and a loss `max(−Δ, 0)`, and
# each is smoothed by a `:mean` `WilderKernel`. The first bar only sets the
# previous value, so the smoothed pair is first available after `period + 1`
# bars.
mutable struct GainLossKernel{T,W}
    const period::Int
    n::Int
    prevx::T
    const gain::W
    const loss::W
end

"""
    GainLossKernel(T, period)

Wilder's smoothed gains and losses over element type `T`, the state RSI and CMO
read through [`gainloss`](@ref).
"""
function GainLossKernel(::Type{T}, period::Integer) where {T}
    w = WilderKernel(T, checkperiod("GainLossKernel", period))
    return GainLossKernel{T,typeof(w)}(w.period, 0, zero(T), w, fresh(w))
end

CausalFrames.fresh(k::GainLossKernel{T}) where {T} = GainLossKernel(T, k.period)
function CausalFrames.fresh!(k::GainLossKernel{T}) where {T}
    k.n = 0
    k.prevx = zero(T)
    fresh!(k.gain)
    fresh!(k.loss)
    return k
end

lookback(k::GainLossKernel) = k.period
nseen(k::GainLossKernel) = k.n

"""
    gainloss(k) -> Union{Missing,Tuple{T,T}}

The smoothed `(gain, loss)` after the last bar folded, `missing` until seeded.
"""
gainloss(k::GainLossKernel{T}) where {T} =
    (k.n > k.period ? (k.gain.prev, k.loss.prev) : missing)::Union{Missing,Tuple{T,T}}
current(k::GainLossKernel) = gainloss(k)

function step!(k::GainLossKernel{T}, x::Real) where {T}
    v = convert(T, x)
    n = k.n += 1
    d = v - k.prevx
    k.prevx = v
    n == 1 && return missing
    g = d > 0 ? d : zero(T)
    step!(k.gain, g)
    step!(k.loss, g - d)
    return gainloss(k)
end
