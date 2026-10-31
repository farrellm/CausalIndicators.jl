# The plain summarizer every plain indicator is: it reads the input columns
# `Is`, skips a bar with any of them `missing`, and steps a per-indicator kernel
# over the rest. The kernel is built from an immutable spec `P` by
# `barkernel(spec, T)` and stepped by `barstep!(k, inputs...)` with the inputs
# converted to `T`. It returns a tuple with one value per output name in `Ns`,
# or `nothing` during the lookback.
#
# A fresh state rebuilds its kernel from the spec, so a kernel needs only
# `fresh!`, not `fresh`.
#
# `barouttype(spec, T)` is the outputs' element type: `T` unless the indicator
# emits `Int`. An indicator whose outputs differ in type instead defines
# `barouttypes(spec, T, n)`, the tuple type `barstep!` returns.
struct BarIndicator{Is,Ns,P} <: Summarizer
    spec::P
end

mutable struct BarIndicatorState{Is,Ns,P,K,T,O,V} <: SummarizerState
    const spec::P
    const kernel::K
    out::Union{Nothing,O}
end

barouttype(spec, ::Type{T}) where {T} = T
barouttypes(spec, ::Type{T}, n) where {T} = NTuple{n,barouttype(spec, T)}

CausalFrames.emptyvalue(::BarIndicator{Is,Ns}) where {Is,Ns} = missings(Ns)

function CausalFrames.fresh(s::BarIndicator{Is,Ns,P}, intypes::NamedTuple) where {Is,Ns,P}
    T = pricetype(intypes, Is)
    k = barkernel(s.spec, T)
    O = barouttypes(s.spec, T, length(Ns))
    V = Tuple{map(E -> Union{Missing,E}, fieldtypes(O))...}
    return BarIndicatorState{Is,Ns,P,typeof(k),T,O,V}(s.spec, k, nothing)
end
CausalFrames.fresh(st::BarIndicatorState{Is,Ns,P,K,T,O,V}) where {Is,Ns,P,K,T,O,V} =
    BarIndicatorState{Is,Ns,P,K,T,O,V}(st.spec, barkernel(st.spec, T), nothing)
function CausalFrames.fresh!(st::BarIndicatorState)
    fresh!(st.kernel)
    st.out = nothing
    return st
end

@inline function CausalFrames.update!(st::BarIndicatorState{Is,Ns,P,K,T},
    row) where {Is,Ns,P,K,T}
    xs = map(c -> row[c], Is)
    st.out = nothing
    anymissing(xs...) && return nothing
    st.out = barstep!(st.kernel, map(x -> convert(T, x), xs)...)
    return nothing
end

@inline function CausalFrames.value(
    st::BarIndicatorState{Is,Ns,P,K,T,O,V},
) where {Is,Ns,P,K,T,O,V}
    out = st.out
    return NamedTuple{Ns,V}(out === nothing ? map(_ -> missing, Ns) : out::O)
end

# A `BarIndicator` over the input specs `specs` (columns or row terms), with
# output names `Ns`.
barindicator(spec, Ns, specs...) =
    withterms(BarIndicator{map(colname, specs),Ns,typeof(spec)}(spec), specs...)
