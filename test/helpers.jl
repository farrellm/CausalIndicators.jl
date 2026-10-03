# Shared test helpers: TA-Lib reference data, extracted tables, goldens,
# allocation checks and the streaming-property drivers later stages use.

const TESTDIR = @__DIR__

"""The 252 daily OHLCV bars of TA-Lib's regression tests (`TA_SREF_*`)."""
loadref() = Tables.columntable(CSV.File(joinpath(TESTDIR, "data", "ref252.csv");
    types = Float64))

"""The 10,000 OHLC bars of TA-Lib's `gData*` set (no volume)."""
loadgdata() = Tables.columntable(
    CSV.File(joinpath(TESTDIR, "data", "gdata10000.csv");
        types = Float64),
)

const DATASETS = Dict("ref252" => loadref, "gdata10000" => loadgdata)

"""
    loadtable(file) -> Dict

The TOML extracted from TA-Lib's `test/<file>.c` by gen/extract_talib_tests.jl,
e.g. `loadtable("test_ma")["tables"]["tableTest"]["rows"]`.
"""
loadtable(file) = TOML.parsefile(joinpath(TESTDIR, "talib", "tables", "$file.toml"))

"""
    loadgolden(fn) -> Dict{Tuple{String,String},NamedTuple}

The full-series goldens of TA-Lib function `fn`, keyed by
`(dataset, params)`; `params` is `"default"` or `"name=value;…"`. Each value
holds `index` and one `Vector{Union{Missing,Float64}}` (or `Int`) per output,
`missing` on TA-Lib's lookback rows.
"""
function loadgolden(fn)
    path = joinpath(TESTDIR, "golden", "$fn.csv.gz")
    bytes = transcode(GzipDecompressor, read(path))
    f = CSV.File(bytes; comment = "#", types = Dict(:dataset => String,
        :params => String))
    t = Tables.columntable(f)
    outs = filter(c -> !(c in (:dataset, :params, :index)), keys(t))
    groups = Dict{Tuple{String,String},Any}()
    for k in unique(zip(t.dataset, t.params))
        idx = findall(i -> (t.dataset[i], t.params[i]) == k, eachindex(t.dataset))
        groups[k] = NamedTuple{(:index, outs...)}(
            (t.index[idx], (allowmissing(t[c][idx]) for c in outs)...))
    end
    return groups
end

allowmissing(v::AbstractVector{T}) where {T} =
    convert(Vector{Union{Missing,nonmissingtype(T)}}, v)

"""
    goldenmatch(got, want; rtol = 1e-9, atol = 0) -> Bool

`got` and `want` agree bar by bar: `missing` exactly where the golden is
(TA-Lib's lookback rows), and the values `isapprox` with `rtol`/`atol` (NaN
matching NaN) elsewhere. On a mismatch the first differing bar is reported.
"""
function goldenmatch(got, want; rtol = 1e-9, atol = 0.0)
    length(got) == length(want) || (@info "length" length(got) length(want); return false)
    for i in eachindex(got, want)
        g, w = got[i], want[i]
        ok = if ismissing(w) || ismissing(g)
            ismissing(w) && ismissing(g)
        elseif isnan(w)
            isnan(g)
        else
            isapprox(g, w; rtol, atol)
        end
        ok || (@info "golden mismatch" bar = i - 1 got = g want = w; return false)
    end
    return true
end

"""
    parseparams(s) -> Dict{Symbol,Int or Float64}

A golden's `params` key as a Dict (`"default"` is empty).
"""
function parseparams(s)
    d = Dict{Symbol,Real}()
    s == "default" && return d
    for kv in split(s, ';')
        k, v = split(kv, '=')
        d[Symbol(k)] = something(tryparse(Int, v), parse(Float64, v))
    end
    return d
end

"""
    allocs(f, args...) -> Int

Bytes `f(args...)` allocates, measured after a warm-up call. The function
barrier keeps the measurement free of the caller's dynamism.
"""
# `Vararg{Any,N}` forces specialization: Julia 1.10 compiles a bare `args...`
# generically when the call is dispatched dynamically, boxing the arguments.
@noinline allocs(f::F, args::Vararg{Any,N}) where {F,N} =
    (f(args...); @allocated f(args...))

"""
    chunked(table, sizes) -> CausalPipeline

A source yielding `table` (which has a `:time` column) as consecutive chunks of
the given sizes, the re-chunking the streaming properties compare against.
"""
function chunked(table, sizes)
    df = DataFrame(table)
    sum(sizes) == nrow(df) || throw(ArgumentError("chunk sizes must sum to $(nrow(df))"))
    stops = cumsum(sizes)
    chunks = [df[(s-n+1):s, :] for (s, n) in zip(stops, sizes) if n > 0]
    return CausalPipeline(_ -> map(copy, chunks))
end

"""
    randomsizes(rng, n) -> Vector{Int}

A random partition of `n` rows into chunks of 1 to `n ÷ 3 + 1` rows.
"""
function randomsizes(rng, n)
    sizes = Int[]
    while sum(sizes; init = 0) < n
        push!(sizes, min(rand(rng, 1:(n÷3+1)), n - sum(sizes; init = 0)))
    end
    return sizes
end

"""
    interleavekeys(tables) -> NamedTuple

Interleave per-key tables (each a NamedTuple of equal-length columns) into one
table with a `:key` column (`1`, `2`, …) and a `:time` column, round-robin, so a
keyed run can be compared with the separate per-key runs.
"""
function interleavekeys(tables)
    n = length(first(first(tables)))
    rows = [
        merge((time = i, key = k), map(c -> c[i], t))
        for i in 1:n for (k, t) in enumerate(tables)
    ]
    return Tables.columntable(rows)
end
