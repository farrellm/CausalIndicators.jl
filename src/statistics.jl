# TA-Lib's statistic functions (S3: STDDEV, VAR, AVGDEV). VAR and AVGDEV are
# CausalFrames' `Variance(corrected = false)` and `MeanAbsDev` under a `Bars`
# window, so only StdDev is defined here.

# A formula scaling its argument by `K`, a fieldless singleton so that it can be
# a dependent's formula with the factor as a type parameter.
struct Scaled{K} end
@inline (::Scaled{K})(x) where {K} = x * K

"""
    StdDev(column::ColumnSpec; nbdev = 1) -> Summarizer

TA-Lib's `STDDEV`, `nbdev` times the population standard deviation of `column`
over the window, in `:{column}_stddev`. It is a dependent over CausalFrames'
`Std(column; corrected = false)` (Group tier). TA-Lib's
`STDDEV(period = p, nbdev = k)` is `StdDev(:x; nbdev = k)` under `Bars(p)`.

CausalFrames bakes `corrected` into the state type, not the output name, so
`StdDev` cannot share a call with a corrected `Std` or `Variance` over the same
column; put them in separate calls.

TA-Lib: `ta_codegen/input/stddev/stddev.yaml`, `stddev.md`.
"""
struct StdDev{C,K} <: GroupSummarizer end
StdDev(column::ColumnSpec; nbdev::Real = 1) =
    withterms(StdDev{colname(column),Float64(nbdev)}(), column)

CausalFrames.dependencies(::StdDev{C}) where {C} = (Std(C; corrected = false),)
CausalFrames.emptyvalue(::StdDev{C}) where {C} =
    NamedTuple{(Symbol(C, :_stddev),)}((missing,))
CausalFrames.fresh(::StdDev{C,K}, ::NamedTuple) where {C,K} =
    derivedvalue(Symbol(C, :_stddev), (Symbol(C, :_std),), lifted(Scaled{K}()))
