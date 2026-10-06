# The plain summarizer shared by the S5 indicators: it reads the input columns
# `Is`, skips a bar with any of them `missing`, and steps a per-indicator kernel
# over the rest. The kernel is built from an immutable spec `P` by
# `barkernel(spec, T)` and stepped by `barstep!(k, inputs...)`, which returns a
# tuple with one value per output name in `Ns`, or `nothing` during the
# lookback. `barouttype(spec, T)` is the outputs' element type (`T` unless the
# indicator emits `Int`), and `O` the tuple type the state keeps.
struct BarIndicator{Is,Ns,P} <: Summarizer
    spec::P
end

mutable struct BarIndicatorState{Is,Ns,K,E,T,O} <: SummarizerState
    const kernel::K
    out::Union{Nothing,O}
end

barouttype(spec, ::Type{T}) where {T} = T

CausalFrames.emptyvalue(::BarIndicator{Is,Ns}) where {Is,Ns} =
    NamedTuple{Ns}(map(_ -> missing, Ns))

function CausalFrames.fresh(s::BarIndicator{Is,Ns}, intypes::NamedTuple) where {Is,Ns}
    T = pricetype(intypes, Is)
    k = barkernel(s.spec, T)
    E = barouttype(s.spec, T)
    return BarIndicatorState{Is,Ns,typeof(k),E,T,NTuple{length(Ns),E}}(k, nothing)
end
CausalFrames.fresh(st::BarIndicatorState{Is,Ns,K,E,T,O}) where {Is,Ns,K,E,T,O} =
    BarIndicatorState{Is,Ns,K,E,T,O}(fresh(st.kernel), nothing)
function CausalFrames.fresh!(st::BarIndicatorState)
    fresh!(st.kernel)
    st.out = nothing
    return st
end

@inline function CausalFrames.update!(st::BarIndicatorState{Is,Ns,K,E,T,O},
    row) where {Is,Ns,K,E,T,O}
    xs = map(c -> row[c], Is)
    st.out = nothing
    anymissing(xs...) && return nothing
    st.out = barstep!(st.kernel, map(x -> convert(T, x), xs)...)
    return nothing
end

@inline function CausalFrames.value(
    st::BarIndicatorState{Is,Ns,K,E,T,O},
) where {Is,Ns,K,E,T,O}
    V = NTuple{length(Ns),Union{Missing,E}}
    out = st.out
    return NamedTuple{Ns,V}(out === nothing ? map(_ -> missing, Ns) : out::O)
end

# A `BarIndicator` over the input specs `specs` (columns or row terms), with
# output names `Ns`.
barindicator(spec, Ns, specs...) =
    withterms(BarIndicator{map(colname, specs),Ns,typeof(spec)}(spec), specs...)
