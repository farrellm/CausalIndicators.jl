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

"""
    loadrejected(fn) -> Vector{String}

The `params` keys of the parameter sets TA-Lib rejected with `TA_BAD_PARAM`
for function `fn` (the boundary sweep's out-of-range values, listed in the
golden's header as `# rejected: …`).
"""
function loadrejected(fn)
    path = joinpath(TESTDIR, "golden", "$fn.csv.gz")
    out = String[]
    for line in eachline(IOBuffer(transcode(GzipDecompressor, read(path))))
        startswith(line, '#') || break
        startswith(line, "# rejected: ") && push!(out, line[13:end])
    end
    return out
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

"""
    goldenatol(xs) -> Float64

The absolute tolerance the goldens allow next to `rtol = 1e-9`, scaled to the
magnitude of the input series `xs` (DESIGN.md, "Testing"): it covers outputs
near zero and the gap between compensated sums and TA-Lib's running sums.
"""
goldenatol(xs) = 1e-9 * maximum(x -> isfinite(x) ? abs(x) : 0.0, xs)

"""The TA-Lib functions whose goldens [`checkgoldens`](@ref) has checked."""
const CHECKED_GOLDENS = Set{String}()

"""TA-Lib's period parameter that a structured indicator takes as its window."""
const WINDOW = (:optInTimePeriod,)

"""
    checkgoldens(run, fn; outputs, input = :close, skip = nothing, accepts = ())

For every `(dataset, params)` golden of TA-Lib function `fn`, call
`run(params::Dict, data)`, which returns one vector per golden output column
named in `outputs` (in that order), and check each against the golden with
[`goldenmatch`](@ref). `skip(data, params, i)`, if given, excludes bar `i` (1-based)
from the comparison. The absolute tolerance is [`goldenatol`](@ref) of the
`input` column, or `atol` if given. It returns the number of series checked.

Every parameter set TA-Lib rejects ([`loadrejected`](@ref)) must make `run`
throw an `ArgumentError`, except a set over the TA-Lib parameters named in
`accepts`. Those are the periods a structured indicator takes as its `Bars`
window, where TA-Lib's range does not apply: `Bars(n)` takes any `n ≥ 1`
(DESIGN.md, "Windows").
"""
function checkgoldens(run, fn; outputs, input = :close, skip = nothing,
    convert = (want, data, params) -> want, atol = nothing, accepts = ())
    push!(CHECKED_GOLDENS, fn)
    ref = loadref()
    for ps in loadrejected(fn)
        p = parseparams(ps)
        all(in(accepts), keys(p)) && continue
        threw = try
            run(p, ref)
            false
        catch e
            e isa ArgumentError || rethrow()
            true
        end
        threw || @info "accepted a set TA-Lib rejects" fn ps
        @test threw
    end
    n = 0
    for ((ds, ps), golden) in sort(collect(loadgolden(fn)); by = first)
        data = DATASETS[ds]()
        p = parseparams(ps)
        got = run(p, data)
        tol = something(atol, goldenatol(data[input]))
        for (g, o) in zip(got, outputs)
            want = convert(golden[o], data, p)
            if skip !== nothing
                keep = [!skip(data, p, i) for i in eachindex(want)]
                g, want = g[keep], want[keep]
            end
            ok = goldenmatch(g, want; rtol = 1e-9, atol = tol)
            ok || @info "golden series failed" fn ds ps o
            @test ok
            n += 1
        end
    end
    return n
end

"""
    tiedextreme(xs, i, n) -> Bool

Whether the `n`-bar window ending at bar `i` holds its maximum or its minimum
more than once. There TA-Lib's path-dependent index tie-break and CausalFrames'
most-recent rule may differ (DESIGN.md (d)), so index tests skip such bars.
"""
function tiedextreme(xs, i, n)
    i < n && return false
    w = @view xs[(i-n+1):i]
    return count(==(maximum(w)), w) > 1 || count(==(minimum(w)), w) > 1
end

"""
    sincefromindex(want, data, params) -> Vector

A golden index column (TA-Lib's absolute bar index) as bars since the extreme,
the form CausalFrames' `MaxIndex`/`MinIndex` emit.
"""
sincefromindex(want, data, params) =
    [ismissing(w) ? missing : (i - 1) - Int(w) for (i, w) in enumerate(want)]

"""
    checkstreaming(s, table; window = nothing, timewindow = nothing)

The streaming properties of DESIGN.md "Testing" for summarizer(s) `s` over the
Tables.jl `table`:

- the pipeline output equals [`foldseries`](@ref)
- random re-chunkings give identical output
- a keyed run over two interleaved series equals the separate runs
- with a sufficient `warmup`, two split contexts concatenate to the whole
- for a structured indicator (`window` given), the re-fold path equals the
  running path, and on unit-spaced bars `timewindow` equals `window`. A time
  look-back `w` covers `[t − w, t]`, so `Bars(n)` matches `timewindow = n − 1`.
"""
function checkstreaming(s, table; window = nothing, timewindow = nothing,
    rng = Random.MersenneTwister(7))
    cols = Tables.columntable(table)
    n = length(first(cols))
    t = merge((time = collect(1:n),), cols)
    apply(p) =
        window === nothing ? addsummarycolumns(p, s) :
        addrollingcolumns(p, (w = window,), s)
    whole = foldseries(s, cols; window)
    outs = keys(whole)
    frame(p, ctx = Context(0, n + 1)) = DataFrame(load(ctx, p))
    @test all(isequal(frame(apply(readtable(t)))[!, o], whole[o]) for o in outs)

    for _ in 1:3
        got = frame(apply(chunked(t, randomsizes(rng, n))))
        @test all(isequal(got[!, o], whole[o]) for o in outs)
    end

    # Keyed: the second series is the first reversed, interleaved bar by bar.
    rev = map(reverse, cols)
    k = interleavekeys([cols, rev])
    kp =
        window === nothing ? addsummarycolumns(readtable(k), s; key = :key) :
        addrollingcolumns(readtable(k), (w = window,), s; key = :key)
    keyed = DataFrame(load(Context(0, 2n + 1), kp))
    other = foldseries(s, rev; window)
    for o in outs
        @test isequal(keyed[keyed.key .== 1, o], whole[o])
        @test isequal(keyed[keyed.key .== 2, o], other[o])
    end

    # warmup: [1, b) and [b, n] loaded separately, each warmed up over every
    # earlier bar, concatenate to the whole.
    b = n ÷ 2
    w1 = frame(readtable(t) |> warmup(n, apply), Context(0, b))
    w2 = frame(readtable(t) |> warmup(n, apply), Context(b, n + 1))
    @test all(isequal(vcat(w1[!, o], w2[!, o]), whole[o]) for o in outs)

    if window !== nothing
        # The re-fold path: the same summarizers, wrapped so no tier applies.
        refold = foldseries(map(refolded, tosummarizers(s)), cols; window)
        for o in outs
            @test isapprox(collect(skipmissing(refold[o])), collect(skipmissing(whole[o]));
                rtol = 1e-9, atol = goldenatol(skipmissing(first(cols))))
            @test isequal(ismissing.(refold[o]), ismissing.(whole[o]))
        end
        if timewindow !== nothing
            timed = foldseries(s, cols; window = timewindow)
            # A time window has no partial-window rule, so compare where the
            # bar window is full.
            for o in outs
                full = .!ismissing.(whole[o])
                @test isequal(timed[o][full], whole[o][full])
            end
        end
    end
    return nothing
end

tosummarizers(s::CausalFrames.Summarizer) = [s]
tosummarizers(ss) = collect(ss)

# A structure-hiding wrapper, as CausalFrames' own tests use: it delegates to the
# wrapped summarizer and its dependencies but subtypes plain `Summarizer`, so
# the window transforms re-fold it, the oracle for the running path.
struct Refold{S<:CausalFrames.Summarizer} <: CausalFrames.Summarizer
    inner::S
end
CausalFrames.emptyvalue(o::Refold) = CausalFrames.emptyvalue(o.inner)
CausalFrames.fresh(o::Refold, intypes::NamedTuple) = CausalFrames.fresh(o.inner, intypes)
CausalFrames.dependencies(o::Refold) = map(Refold, CausalFrames.dependencies(o.inner))

# Wrap a summarizer that carries row terms inside its terms, which must stay
# outermost.
refolded(s) = Refold(s)
refolded(t::CausalFrames.Termed) = CausalFrames.Termed(Refold(t.summarizer), t.terms)

# The decimals a table value was written with, which set its tolerance. The
# extractor evaluates the C literals, so a value can carry a representation
# error (0.7333000000000001); 15 significant digits recover the literal.
function decimals(v)
    s = string(round(v; sigdigits = 15))
    m, e = occursin('e', s) ? split(s, 'e') : (s, "0")
    d = occursin('.', m) ? length(m) - findlast('.', m) : 0
    return max(d - parse(Int, e), 0)
end

"""
    tablerun(run, data, startidx, endidx, lookback) -> Vector

A TA-Lib table row's call over `startIdx:endIdx` (0-based), as a vector indexed
by absolute bar (1-based), `missing` outside the output. TA-Lib seeds a call
at `startIdx − lookback`, so `run(slice)` runs over the bars from there through
`endIdx` and must return one vector of outputs for them.
"""
function tablerun(run, data, startidx, endidx, lookback)
    first_ = max(startidx - lookback, 0)
    slice = map(c -> c[(first_+1):(endidx+1)], data)
    got = run(slice)
    out = Vector{Union{Missing,eltype(got)}}(missing, endidx + 1)
    out[(first_+1):end] = got
    # TA-Lib emits nothing before startIdx.
    out[1:min(startidx, endidx+1)] .= missing
    return out
end

"""
    checkrow(got, row; out = "oneOfTheExpectedOutReal", index = "oneOfTheExpectedOutRealIndex",
             atol = nothing)

The assertions of DESIGN.md "Testing" for one TA-Lib table row: the first
emitted bar is `expectedBegIdx`, `expectedNbElement` bars are emitted, and the
value at `expectedBegIdx + index` matches to the row's precision, or to `atol`
if given.
"""
function checkrow(got, row; out = "oneOfTheExpectedOutReal",
    index = "oneOfTheExpectedOutRealIndex", value = true, atol = nothing)
    nb = row["expectedNbElement"]
    @test count(!ismissing, got) == nb
    nb == 0 && return nothing
    beg = row["expectedBegIdx"]
    @test findfirst(!ismissing, got) - 1 == beg
    if value
        want = row[out]
        # A literal at 17 digits is held to 1e-14 relative: the compensated sums
        # differ from TA-Lib's running ones in the last digits.
        tol = something(atol, max(10.0^-decimals(want), 1e-14 * abs(want)))
        @test got[beg+row[index]+1] ≈ want atol = tol
    end
    return nothing
end

"""
    lcgsym(seed, n) -> Vector{Float64}

`n` draws in `[-1, 1)` from ta_test_reference.c's LCG (`ta_test_ref_lcg_sym`)
seeded with `seed`, so a hand port runs on the C test's own data, identical on
every Julia version (`rand` streams are not).
"""
function lcgsym(seed, n)
    state = UInt32(seed)
    return map(1:n) do _
        state = state * 0x41c64e6d + 0x00003039
        Float64((state >> 8) & 0x00ffffff) / 8388608.0 - 1.0
    end
end
