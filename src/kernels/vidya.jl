# Chande's variable index dynamic average: an EMA whose smoothing factor is
# scaled each bar by |CMOU| / 100. The oscillator is a prefilled `CMOUKernel`,
# so through the warm-up it is taken over the changes seen so far, as
# ta_VIDYA.c takes it, and from the first full window on it is `CMOU`'s.
mutable struct VIDYAKernel{T,C}
    const period::Int
    const alpha::T
    n::Int
    last::T
    const cmou::C
end

"""
    VIDYAKernel(T, period, cmoperiod)

TA-Lib's VIDYA over element type `T`: an EMA at `period` (α = 2/(period + 1))
whose α is scaled by the absolute unsmoothed CMO over the last `cmoperiod`
changes. It is seeded with the first bar, and its lookback is `cmoperiod`. At
period 1 it copies its input, with lookback 0.
"""
function VIDYAKernel(::Type{T}, period::Integer, cmoperiod::Integer) where {T}
    p = checkperiod("VIDYAKernel", period)
    m = checkperiod("VIDYAKernel", cmoperiod)
    c = CMOUKernel(T, m; prefilled = true)
    return VIDYAKernel{T,typeof(c)}(p, T(2) / T(p + 1), 0, zero(T), c)
end

CausalFrames.fresh(k::VIDYAKernel{T}) where {T} = VIDYAKernel(T, k.period, k.cmou.period)
function CausalFrames.fresh!(k::VIDYAKernel{T}) where {T}
    k.n = 0
    k.last = zero(T)
    fresh!(k.cmou)
    return k
end

lookback(k::VIDYAKernel) = k.period == 1 ? 0 : k.cmou.period
nseen(k::VIDYAKernel) = k.n
current(k::VIDYAKernel) = k.n > lookback(k) ? k.last : missing

@inline function step!(k::VIDYAKernel{T}, x::Real) where {T}
    x = convert(T, x)
    k.n += 1
    if k.period == 1
        k.last = x
        return k.last
    end
    c = cmoustep!(k.cmou, x)
    k.last = c === nothing ? x : fma(x - k.last, k.alpha * (abs(c) / 100), k.last)
    return current(k)
end
