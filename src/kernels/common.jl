# Kernels are the recursive building blocks of the plain indicators: mutable
# structs embedded as concrete fields of an indicator's state, never summarizers
# themselves. Window sums, extrema and ring buffers are not kernels; those are
# CausalFrames states, embedded through `CausalFrames.barwindow`.
#
# A kernel `k` over element type `T` implements
#
# - `step!(k, x)::Union{Missing,T}` folds one bar and returns the kernel's value
#   after it, `missing` until the kernel has seen `lookback(k) + 1` bars. A
#   `missing` bar is skipped: it leaves the kernel unchanged and returns
#   `missing` (DESIGN.md, "Missing and non-finite inputs").
# - `current(k)::Union{Missing,T}` is the value after the last bar folded.
# - `nseen(k)` counts the non-`missing` bars folded, so an indicator emits from
#   `nseen(k) > lookback(k) + unstable`. (`MAKernel` folds `unstable` into its
#   own `lookback` and gates `step!` itself; see kernels/ma.jl.)
# - `lookback(k)` is TA-Lib's lookback for the kernel's parameters.
# - `fresh(k)` returns a new zero kernel with the same parameters, and `fresh!(k)`
#   zeroes `k` in place and returns it; `step!` and `fresh!` do not allocate.

"""
    floattype(T) -> Type

The element type a kernel computes in for an input column of type `T`.
Integers widen to `Float64`, and a float wider than `Float64` is kept.
"""
floattype(::Type{T}) where {T} = promote_type(Float64, float(nonmissingtype(T)))

"""
    step!(k, x) -> Union{Missing,T}

Fold the bar `x` into kernel `k` and return the kernel's value after it.
A `missing` bar leaves `k` unchanged and returns `missing`.
"""
function step! end

step!(::Any, ::Missing) = missing

# The CausalFrames `Sum` state a kernel seeds from: one compensated sum shared by
# every seed in the package.
seedsum(::Type{T}) where {T} = fresh(Sum(:x), (x = T,))
@inline seedadd!(s, x) = update!(s, (x = x,))
@inline seedtotal(s) = value(s).x_sum

function checkperiod(kernel, period)
    period >= 1 || throw(ArgumentError("$kernel period must be positive, got $period"))
    return Int(period)
end

function checkunstable(unstable)
    unstable >= 0 ||
        throw(ArgumentError("unstable period must be non-negative, got $unstable"))
    return Int(unstable)
end
