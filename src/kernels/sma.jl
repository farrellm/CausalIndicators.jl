# The simple moving average inside a recursive state: a CausalFrames `Mean`
# under `CausalFrames.barwindow`, so it shares the package-wide compensated sum.
# The window's type depends on the runtime tiering, hence the parameter `W`.
mutable struct SMAKernel{T,W}
    const period::Int
    n::Int
    const window::W
end

"""
    SMAKernel(T, period)

A `period`-bar simple moving average kernel over element type `T`.
"""
function SMAKernel(::Type{T}, period::Integer) where {T}
    p = checkperiod("SMAKernel", period)
    w = CausalFrames.barwindow(Mean(:x), p, (x = T,))
    return SMAKernel{T,typeof(w)}(p, 0, w)
end

CausalFrames.fresh(s::SMAKernel{T}) where {T} = SMAKernel(T, s.period)
function CausalFrames.fresh!(s::SMAKernel)
    s.n = 0
    fresh!(s.window)
    return s
end

lookback(s::SMAKernel) = s.period - 1
nseen(s::SMAKernel) = s.n
current(s::SMAKernel{T}) where {T} = convert(Union{Missing,T}, value(s.window).x_mean)

function step!(s::SMAKernel{T}, x::Real) where {T}
    s.n += 1
    update!(s.window, (x = convert(T, x),))
    return current(s)
end
