# Arnaud Legoux's moving average: the window's values weighted by a Gaussian,
# fixed at construction. The values are a CausalFrames `WindowValues` under
# `barwindow`, and each bar's dot product is a scan recomputed from them, a
# plain loop oldest first in ta_ALMA.c's order, as `MeanAbsDev`'s scan is
# (DESIGN.md, "Warm-up").
mutable struct ALMAKernel{T,W}
    const period::Int
    const weights::Vector{T}
    n::Int
    last::T
    const window::W
end

"""
    ALMAKernel(T, period, sigma = 6, offset = 0.85)

TA-Lib's ALMA over `period` bars, element type `T`: the Gaussian's peak sits at
bar `floor(offset·(period − 1))` from the oldest, and its standard deviation is
`period / sigma` bars. At period 1 it copies its input.
"""
function ALMAKernel(::Type{T}, period::Integer, sigma::Real = 6.0,
    offset::Real = 0.85) where {T}
    p = checkperiod("ALMAKernel", period)
    w = CausalFrames.barwindow(CausalFrames.WindowValues(:x), p, (x = T,))
    return ALMAKernel{T,typeof(w)}(p, almaweights(T, p, sigma, offset), 0, zero(T), w)
end

# ta_ALMA.c's weights, in its expression order: unnormalized Gaussians, then
# each divided by their sum.
function almaweights(::Type{T}, p, sigma, offset) where {T}
    m = floor(Int, T(offset) * (p - 1))
    s = T(p) / T(sigma)
    twossq = 2 * s * s
    g = [exp(-(T(j - m) * T(j - m)) / twossq) for j in 0:(p-1)]
    norm = zero(T)
    for v in g
        norm += v
    end
    return g ./ norm
end

CausalFrames.fresh(k::ALMAKernel{T,W}) where {T,W} =
    ALMAKernel{T,W}(k.period, k.weights, 0, zero(T), fresh(k.window))
function CausalFrames.fresh!(k::ALMAKernel{T}) where {T}
    k.n = 0
    k.last = zero(T)
    fresh!(k.window)
    return k
end

lookback(k::ALMAKernel) = k.period - 1
nseen(k::ALMAKernel) = k.n
current(k::ALMAKernel) = k.n > lookback(k) ? k.last : missing

@inline function step!(k::ALMAKernel{T}, x::Real) where {T}
    k.n += 1
    if k.period == 1
        # A dot product seeded with 0.0 would turn a -0.0 into +0.0.
        k.last = x
        return k.last
    end
    update!(k.window, (x = convert(T, x),))
    k.n > lookback(k) || return missing
    wv = value(k.window).x_windowvalues
    # `WindowValues` counts NaN rather than storing it: a NaN in the window
    # makes the dot product NaN, as in TA-Lib.
    if wv.nans > 0
        k.last = T(NaN)
    else
        s = zero(T)
        @inbounds for j in 1:k.period
            s += k.weights[j] * wv.vals[wv.head+j-1]
        end
        k.last = s
    end
    return k.last
end
