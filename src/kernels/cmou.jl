# Chande's unsmoothed momentum oscillator over the last `period` bar-to-bar
# changes, from window sums of the up and down moves: `CMOU` emits it, and
# `VIDYAKernel` scales its smoothing factor by it, so the two stay one
# computation.
#
# `prefilled` starts the sums window full of zero moves, so from the second bar
# on the oscillator is taken over the changes seen so far, as ta_VIDYA.c's
# warm-up takes it. The zeros leave the window as real changes arrive, and from
# the `period`-th change on it is the plain `CMOU`.
mutable struct CMOUKernel{T,W}
    const period::Int
    const prefilled::Bool
    n::Int
    prev::T
    nullrun::Int
    const window::W
end

function CMOUKernel(::Type{T}, period::Integer; prefilled::Bool = false) where {T}
    w = sumswindow((:up, :dn), period, T)
    k = CMOUKernel{T,typeof(w)}(period, prefilled, 0, zero(T), 0, w)
    prefilled && prefillmoves!(k)
    return k
end

function prefillmoves!(k::CMOUKernel{T}) where {T}
    for _ in 1:k.period
        update!(k.window, (up = zero(T), dn = zero(T)))
    end
    return k
end

function CausalFrames.fresh!(k::CMOUKernel{T}) where {T}
    k.n = 0
    k.prev = zero(T)
    k.nullrun = 0
    fresh!(k.window)
    k.prefilled && prefillmoves!(k)
    return k
end

# The oscillator after the bar `x`, or `nothing` on the first bar and, unless
# prefilled, until `period` changes have arrived.
@inline function cmoustep!(k::CMOUKernel{T}, x::T) where {T}
    prev = k.prev
    k.prev = x
    (k.n += 1) == 1 && return nothing
    d = x - prev
    up, dn = d > 0 ? (d, zero(T)) : d < 0 ? (zero(T), -d) : (zero(T), zero(T))
    update!(k.window, (up = up, dn = dn))
    k.nullrun = d == 0 ? min(k.nullrun + 1, k.period) : 0
    sums = value(k.window).sums
    ismissing(sums) && return nothing
    # A window of exactly flat moves sums to exactly zero, whatever round-off
    # the sliding sums hold (ta_CMOU.c's nullRun).
    u, w = k.nullrun >= k.period ? (zero(T), zero(T)) : sums::Tuple{T,T}
    t = u + w
    return t > 0 ? (100 * (u - w)) / t : zero(T)
end
