# Extracts the initialized test tables of TA-Lib's C regression tests into TOML.
#
#     julia --project=gen gen/extract_talib_tests.jl ~/workspace/ta-lib
#
# For each src/tools/ta_regtest/ta_test_func/test_*.c this writes
# test/talib/tables/<file>.toml holding every file-scope initialized array:
# arrays of a struct typedef'd in the file become `[tables.<name>]` with the
# struct's field list and one `[[tables.<name>.rows]]` entry per initializer row;
# arrays of scalars become `[arrays.<name>]`. Constant expressions (`252-24`,
# `#define`d sizes, casts) are evaluated; identifiers (`TA_SUCCESS`,
# `TA_MAType_SMA`, test ids) are kept as strings, as is any expression the
# evaluator does not handle. A row inside a preprocessor conditional lists it in
# `cond` (`"!TA_FUNC_NO_RANGE_CHECK"`), and rows of the range-check block also
# carry `rangecheck = true`: TA-Lib's parameter-range error tests.

using TOML

include(joinpath(@__DIR__, "cparse.jl"))

const SCALARTYPES = Set(["double", "float", "int", "long", "TA_Real", "TA_Integer",
    "char*", "unsigned int", "short"])

function rowdict(fields::Vector{Field}, row, conds::Vector{String}, defines)
    d = Dict{String,Any}()
    if row isa Vector && length(row) == length(fields)
        for (f, v) in zip(fields, row)
            d[f.name] = v
        end
    else
        # A flattened or partial initializer: keep the values positionally.
        d["values"] = row isa Vector ? row : Any[row]
    end
    if !isempty(conds)
        d["cond"] = conds
        "!TA_FUNC_NO_RANGE_CHECK" in conds && (d["rangecheck"] = true)
    end
    return d
end

function extractfile(path::AbstractString, relpath::AbstractString)
    defines = Dict{String,Vector{Tok}}()
    toks = tokenize(stripcomments(read(path, String)), defines)
    structs, decls = scandecls(toks)
    empty!(ARRAYLENS)
    for d in decls
        ARRAYLENS[d.name] = length(d.init.items)
    end
    tables = Dict{String,Any}()
    arrays = Dict{String,Any}()
    used = Set{String}()
    for d in decls
        if haskey(structs, d.ctype)
            fields = structs[d.ctype]
            rows = [
                rowdict(fields, plain(item, defines), d.init.conds[k], defines)
                for (k, item) in enumerate(d.init.items)
            ]
            tables[d.name] = Dict{String,Any}("type" => d.ctype, "rows" => rows)
            push!(used, d.ctype)
        elseif d.ctype in SCALARTYPES
            arrays[d.name] = Dict{String,Any}("type" => d.ctype,
                "values" => plain(d.init, defines))
        end
    end
    isempty(tables) && isempty(arrays) && return nothing
    out = Dict{String,Any}("source" => relpath, "commit" => TALIB_COMMIT)
    if !isempty(used)
        out["structs"] = Dict{String,Any}(
            s => Dict{String,Any}(
                "fields" => [f.name for f in structs[s]],
                "types" => [
                    f.ctype * join("[" * x * "]" for x in f.dims)
                    for f in structs[s]
                ]) for s in used
        )
    end
    isempty(tables) || (out["tables"] = tables)
    isempty(arrays) || (out["arrays"] = arrays)
    return out
end

function main(root::AbstractString)
    checkpin(root)
    reldir = "src/tools/ta_regtest/ta_test_func"
    dir = joinpath(root, reldir)
    outdir = joinpath(@__DIR__, "..", "test", "talib", "tables")
    mkpath(outdir)
    foreach(f -> endswith(f, ".toml") && rm(joinpath(outdir, f)), readdir(outdir))
    empty_ = String[]
    for f in sort(filter(x -> startswith(x, "test_") && endswith(x, ".c"), readdir(dir)))
        res = extractfile(joinpath(dir, f), "$reldir/$f")
        if res === nothing
            push!(empty_, f)
            continue
        end
        open(joinpath(outdir, replace(f, ".c" => ".toml")), "w") do io
            println(io, "# Extracted by gen/extract_talib_tests.jl from TA-Lib ",
                TALIB_COMMIT[1:7], ":", res["source"], ". Do not edit.")
            TOML.print(io, res; sorted = true)
        end
        ntab = length(get(res, "tables", ()))
        nrow =
            sum((length(t["rows"]) for t in values(get(res, "tables", Dict()))); init = 0)
        narr = length(get(res, "arrays", ()))
        println(rpad(f, 26), "tables=", ntab, " rows=", nrow, " arrays=", narr)
    end
    println("\nNo file-scope tables (hand-port): ", join(empty_, ", "))
    return empty_
end

isinteractive() || main(ARGS[1])
