# The test-only batch driver (DESIGN.md, "Testing"). It has no fold logic of its
# own: it runs the table through exactly the transforms a pipeline would.

"""
    foldseries(s, table; window = nothing, key = nothing) -> NamedTuple

Run summarizer(s) `s` over the Tables.jl `table`, one row per bar, and return
one vector per output column. A synthetic integer `:time` column (`1:n`) is
added. With `window` (e.g. `Bars(14)`) the summarizers run under
`addrollingcolumns((w = window,), s)`, so outputs are prefixed `w_`; otherwise
under `addsummarycolumns(s)`.
"""
function foldseries(s, table; window = nothing, key = nothing)
    cols = Tables.columntable(table)
    n = length(first(cols))
    src = readtable(merge((time = collect(1:n),), cols))
    p =
        window === nothing ? addsummarycolumns(src, s; key) :
        addrollingcolumns(src, (w = window,), s; key)
    df = DataFrame(load(Context(0, n + 1), p))
    outs = [c for c in propertynames(df) if c !== :time && !haskey(cols, c)]
    return NamedTuple{Tuple(outs)}(Tuple(df[!, c] for c in outs))
end
