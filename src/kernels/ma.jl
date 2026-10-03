# TA-Lib's moving-average family behind one type: the `matype` symbol is
# dispatched once at construction into the parameter `M`, so the fold never
# branches on it. Each stage adds the MA types its indicators need.

"""
TA-Lib's MA types, in `TA_MAType` order, as CausalIndicators' `matype` symbols.
"""
const MATYPES = (:sma, :ema, :wma, :dema, :tema, :trima, :kama, :mama, :t3, :hma,
    :zlema, :rma)

struct MAKernel{M,K}
    inner::K
end

"""
    MAKernel(T, matype, period)

The `matype` moving average over `period` bars, element type `T`. `matype` is one
of [`MATYPES`](@ref).
"""
function MAKernel(::Type{T}, matype::Symbol, period::Integer) where {T}
    matype in MATYPES || throw(
        ArgumentError(
            "MAKernel matype must be one of $(join(map(repr, MATYPES), ", ")), " *
            "got $(repr(matype))",
        ))
    inner = makernel(Val(matype), T, period)
    return MAKernel{matype,typeof(inner)}(inner)
end

makernel(::Val{:sma}, ::Type{T}, period) where {T} = SMAKernel(T, period)
makernel(::Val{:ema}, ::Type{T}, period) where {T} = EMAKernel(T, period)
makernel(::Val{:rma}, ::Type{T}, period) where {T} = WilderKernel(T, period)
makernel(::Val{M}, ::Type, period) where {M} =
    throw(ArgumentError("MAKernel matype $(repr(M)) is not implemented yet"))

CausalFrames.fresh(m::MAKernel{M}) where {M} = MAKernel{M}(fresh(m.inner))
MAKernel{M}(inner::K) where {M,K} = MAKernel{M,K}(inner)
CausalFrames.fresh!(m::MAKernel) = (fresh!(m.inner); m)

lookback(m::MAKernel) = lookback(m.inner)
nseen(m::MAKernel) = nseen(m.inner)
current(m::MAKernel) = current(m.inner)
@inline step!(m::MAKernel, x::Real) = step!(m.inner, x)
