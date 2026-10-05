# TA-Lib's directional movement (ta_PLUS_DM.c, ta_PLUS_DI.c, ta_DX.c): each
# bar's up move `diffP = high − previous high` and down move
# `diffM = previous low − low`. +DM1 is `diffP` when it is positive and exceeds
# `diffM`, else 0, and −DM1 is the mirror, so a tie gives 0 to both. +DM1, −DM1
# and the true range are each smoothed by a `:sum` `WilderKernel` seeded with
# the first `period − 1` values. At period 1 the kernel keeps the raw values
# instead, as TA-Lib's period-1 arms do.
mutable struct DMKernel{T,W}
    const period::Int
    n::Int
    prevhigh::T
    prevlow::T
    prevclose::T
    rawplus::T
    rawminus::T
    rawtr::T
    const plus::W
    const minus::W
    const tr::W
end

"""
    DMKernel(T, period)

Wilder's smoothed directional movement and true range over element type `T`,
stepped with `step!(k, high, low, close)` and read through
[`dmsums`](@ref). PlusDM, MinusDM, PlusDI, MinusDI, DX, ADX and ADXR read it.
"""
function DMKernel(::Type{T}, period::Integer) where {T}
    p = checkperiod("DMKernel", period)
    w = WilderKernel(T, p; form = :sum, seedn = max(p - 1, 1))
    z = zero(T)
    return DMKernel{T,typeof(w)}(p, 0, z, z, z, z, z, z, w, fresh(w), fresh(w))
end

CausalFrames.fresh(k::DMKernel{T}) where {T} = DMKernel(T, k.period)
function CausalFrames.fresh!(k::DMKernel{T}) where {T}
    k.n = 0
    k.prevhigh = k.prevlow = k.prevclose = zero(T)
    k.rawplus = k.rawminus = k.rawtr = zero(T)
    fresh!(k.plus)
    fresh!(k.minus)
    fresh!(k.tr)
    return k
end

# The bars before the smoothed sums are first available: one previous bar,
# then a seed of `period − 1` (TA-Lib's DM lookback; the DIs add one step).
lookback(k::DMKernel) = k.period == 1 ? 1 : k.period - 1
nseen(k::DMKernel) = k.n

"""
    dmsums(k) -> Tuple{T,T,T}

The smoothed `(+DM, −DM, TR)` after the last bar folded, or the raw ones at
period 1. Valid once `nseen(k) > lookback(k)`.
"""
dmsums(k::DMKernel) =
    k.period == 1 ? (k.rawplus, k.rawminus, k.rawtr) :
    (k.plus.prev, k.minus.prev, k.tr.prev)
current(k::DMKernel) = k.n > lookback(k) ? dmsums(k) : missing

function step!(k::DMKernel{T}, h::Real, l::Real, c::Real) where {T}
    hv, lv = convert(T, h), convert(T, l)
    ph, pl, pc = k.prevhigh, k.prevlow, k.prevclose
    k.prevhigh, k.prevlow, k.prevclose = hv, lv, convert(T, c)
    k.n += 1
    k.n == 1 && return missing
    diffp = hv - ph
    diffm = pl - lv
    pdm = diffp > diffm && diffp > 0 ? diffp : zero(T)
    mdm = diffm > diffp && diffm > 0 ? diffm : zero(T)
    tr = truerange(hv, lv, pc)
    if k.period == 1
        k.rawplus, k.rawminus, k.rawtr = pdm, mdm, tr
    else
        step!(k.plus, pdm)
        step!(k.minus, mdm)
        step!(k.tr, tr)
    end
    return current(k)
end
