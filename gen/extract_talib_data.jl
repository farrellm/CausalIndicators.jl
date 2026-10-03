# Extracts TA-Lib's regression price data into test/data/*.csv.
#
#     julia --project=gen gen/extract_talib_data.jl ~/workspace/ta-lib
#
# - ref252.csv: the 252 daily bars `TA_SREF_*_daily_ref_0_PRIV` (OHLCV) of
#   src/tools/ta_regtest/test_data.c, the input of nearly every table test.
# - gdata10000.csv: the 10,000 bars `gData{Open,High,Low,Close}` of
#   src/tools/ta_regtest/ta_gData*.c. TA-Lib has no volume for this set.
#
# The C literals are copied verbatim, so the parsed Float64s are exactly the
# doubles TA-Lib compiles.

include(joinpath(@__DIR__, "cparse.jl"))

function literals(path::AbstractString)
    defines = Dict{String,Vector{Tok}}()
    toks = tokenize(stripcomments(read(path, String)), defines)
    _, decls = scandecls(toks)
    out = Dict{String,Vector{String}}()
    for d in decls
        vals = String[]
        for item in d.init.items
            item isa Leaf || error("$(d.name): nested initializer")
            push!(vals, join(t.text for t in item.toks))
        end
        out[d.name] = vals
    end
    return out
end

function writecsv(path, names, cols)
    n = length(first(cols))
    all(c -> length(c) == n, cols) || error("$path: ragged columns")
    open(path, "w") do io
        println(io, join(names, ','))
        for i in 1:n
            println(io, join((c[i] for c in cols), ','))
        end
    end
    println(path, ": ", n, " rows")
end

function main(root::AbstractString)
    checkpin(root)
    dir = joinpath(root, "src", "tools", "ta_regtest")
    outdir = joinpath(@__DIR__, "..", "test", "data")
    mkpath(outdir)

    ref = literals(joinpath(dir, "test_data.c"))
    names = ["open", "high", "low", "close", "volume"]
    writecsv(joinpath(outdir, "ref252.csv"), names,
        [ref["TA_SREF_$(c)_daily_ref_0_PRIV"] for c in names])

    gcols = [
        only(values(literals(joinpath(dir, "ta_gData$(uppercasefirst(c)).c"))))
        for c in names[1:4]
    ]
    writecsv(joinpath(outdir, "gdata10000.csv"), names[1:4], gcols)
end

isinteractive() || main(ARGS[1])
