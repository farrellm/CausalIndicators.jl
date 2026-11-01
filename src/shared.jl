# The pieces every indicator file shares: the dependent states, the internal
# window dependents, argument checks, output naming and the docstring
# paragraphs.

# ---------------------------------------------------------------------------
# Dependent states

# A dependent's state: fieldless, with the output names `Ns`, the names `Ds` of
# the dependency values it reads and its formula `F` (a singleton function type)
# as type parameters, so the two-argument `value` infers. The value type comes
# from the dependencies' declared field types, as in CausalFrames' own
# dependents, so a `missing` dependency keeps its `Union{Missing,…}`.
# `DerivedValue` has one output, the formula's value; `DerivedValues` has one
# per name in `Ns`, which the formula returns as a tuple.
abstract type Derived <: SummarizerState end
struct DerivedValue{Ns,Ds,F} <: Derived end
struct DerivedValues{Ns,Ds,F} <: Derived end

derivedvalue(n::Symbol, ds::Tuple, f) = DerivedValue{(n,),ds,typeof(f)}()
derivedvalues(ns::Tuple, ds::Tuple, f) = DerivedValues{ns,ds,typeof(f)}()

@inline function CausalFrames.value(::DerivedValue{Ns,Ds,F},
    vals::NamedTuple) where {Ns,Ds,F}
    V = Base.promote_op(F.instance, map(d -> fieldtype(typeof(vals), d), Ds)...)
    return NamedTuple{Ns,Tuple{V}}((F.instance(map(d -> vals[d], Ds)...),))
end

@inline function CausalFrames.value(::DerivedValues{Ns,Ds,F},
    vals::NamedTuple) where {Ns,Ds,F}
    V = Base.promote_op(F.instance, map(d -> fieldtype(typeof(vals), d), Ds)...)
    return NamedTuple{Ns,V}(F.instance(map(d -> vals[d], Ds)...))
end

CausalFrames.fresh(st::Derived) = st
CausalFrames.fresh!(st::Derived) = st
@inline CausalFrames.update!(::Derived, row) = nothing
@inline CausalFrames.downdate!(::Derived, row) = nothing
CausalFrames.combine!(::D, ::D, ::D) where {D<:Derived} = nothing

# A formula `F` lifted over `missing`: `missing` if any argument is, else
# `F(args...)`. A fieldless singleton, so it can be a dependent's formula.
struct Lifted{F} end
lifted(f) = Lifted{typeof(f)}()
@inline (::Lifted{F})(args...) where {F} =
    any(ismissing, args) ? missing : F.instance(args...)

# The all-`missing` value of outputs `Ns`, a summarizer's `emptyvalue`.
missings(Ns::Tuple) = NamedTuple{Ns}(map(_ -> missing, Ns))

# ---------------------------------------------------------------------------
# Internal window dependents, for a `barwindow` that needs several values

# The sums of columns `Cs` as one tuple: MFI's money flows, ULTOSC's pressure
# and range, CMOU's moves and Vortex's movements and range.
struct Sums{Cs} <: GroupSummarizer end

CausalFrames.dependencies(::Sums{Cs}) where {Cs} = map(Sum, Cs)
CausalFrames.emptyvalue(::Sums) = (; sums = missing)
CausalFrames.fresh(::Sums{Cs}, ::NamedTuple) where {Cs} =
    derivedvalue(:sums, map(c -> Symbol(c, :_sum), Cs), tuple)

sumswindow(Cs, n, ::Type{T}) where {T} =
    CausalFrames.barwindow(Sums{Cs}(), n, NamedTuple{Cs}(map(_ -> T, Cs)))

# The extremes of a window: the highest `H` and the lowest `L`.
struct Extremes{H,L} <: GroupSummarizer end

CausalFrames.dependencies(::Extremes{H,L}) where {H,L} = (Max(H), Min(L))
CausalFrames.emptyvalue(::Extremes) = (; extremes = missing)
CausalFrames.fresh(::Extremes{H,L}, ::NamedTuple) where {H,L} =
    derivedvalue(:extremes, (Symbol(H, :_max), Symbol(L, :_min)), tuple)

extremeswindow(n, ::Type{T}) where {T} =
    CausalFrames.barwindow(Extremes{:high,:low}(), n, (high = T, low = T))

# The first values of columns `Cs`.
struct Firsts{Cs} <: GroupSummarizer end

CausalFrames.dependencies(::Firsts{Cs}) where {Cs} = map(First, Cs)
CausalFrames.emptyvalue(::Firsts) = (; firsts = missing)
CausalFrames.fresh(::Firsts{Cs}, ::NamedTuple) where {Cs} =
    derivedvalue(:firsts, map(c -> Symbol(c, :_first), Cs), tuple)

# ---------------------------------------------------------------------------
# Kernel parts that may be absent

maybefresh!(::Nothing) = nothing
maybefresh!(k) = fresh!(k)

# ---------------------------------------------------------------------------
# Argument checks and output names

function checkrange(fn, kw, x, lo, hi)
    lo <= x <= hi ||
        throw(ArgumentError("$fn $kw must be in [$lo, $hi] (TA-Lib's range), got $x"))
    return x
end

function checkmatype(fn, kw, matype)
    matype in MATYPES || throw(
        ArgumentError(
            "$fn $kw must be one of $(join(map(repr, MATYPES), ", ")), " *
            "got $(repr(matype))",
        ))
    return matype
end

# The output names of a plain indicator: a single-series one prefixes its
# input column, a price-bar one (`C === nothing`) does not, and a multi-output
# one appends each output's suffix.
outname(C::Symbol, name) = Symbol(C, :_, name)
outname(::Nothing, name) = name
outnames(C, name, suffixes) = map(s -> Symbol(outname(C, name), :_, s), suffixes)

@inline anymissing(xs...) = any(ismissing, xs)

# The element type of an indicator over input columns `cols`.
pricetype(intypes, cols) =
    floattype(promote_type(map(c -> nonmissingtype(intypes[c]), cols)...))

# ---------------------------------------------------------------------------
# Docstring paragraphs

const PLAIN_DOC = """
It is a plain summarizer (no `combine!`), so it belongs under
`addsummarycolumns`. Under `addrollingcolumns` each window re-folds from a
fresh state, a cold start per window. The output is `missing` for TA-Lib's
lookback (plus `unstable`) bars.
"""

const SKIP_DOC = """
A `missing` input bar leaves the state unchanged and emits `missing`.
"""

# A plain `BarIndicator`, which skips a bar with any input `missing` (also used
# by the S5 single-series indicators).
const PRICEBAR_DOC = """
$PLAIN_DOC
A bar with any input `missing` leaves the state unchanged and emits `missing`.
"""

# For every indicator with an `unstable` keyword.
const AUTO_DOC = """
`unstable = :auto4` or `:auto8` is TA-Lib's Auto-Stabilization: each unstable
period the indicator reads drops the bars TA-Lib's rule gives at these
parameters, so that 4 (or 8) significant digits no longer depend on where the
data starts. The count depends on the parameters, not on the data. It is
TA-Lib's target, not a guarantee: TA-Lib's spec lists where it falls short
(`website/src/spec/auto-stabilization/`, "Known exceptions").
"""

# The ratio outputs' exception (TA-Lib's "no level" list).
const AUTO_FLAT_DOC = """
No level covers a flat market: it divides one smoothed series by another, and
when prices stop moving both shrink together and the ratio keeps its dependence
on the start.
"""

# For the indicators whose defaults are their author's daily-chart parameters.
const DAILY_DOC = """
The defaults are TA-Lib's, which are the author's parameters for daily bars.
Periods count bars, not days, so on other bar sizes the defaults span other
lengths of time: choose the parameters for your bars.
"""
