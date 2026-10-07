# Generates full-series goldens for TA-Lib functions.
#
#     make -C gen/golden TALIB=~/workspace/ta-lib
#     julia --project=gen gen/golden/generate.jl ~/workspace/ta-lib EMA RMA ...
#
# Each function runs through dump_golden at TA-Lib's defaults and at every
# parameter set paramsets.toml lists for it, over both datasets in test/data.
# The 10,000-bar set runs at the defaults only (and the candlestick matrix rows
# below), which keeps the files small; the other extra parameter sets run on the 252-bar set the tables use. A dataset missing an
# input the function needs (gdata10000 has no volume) is skipped. The results go to test/golden/<FN>.csv.gz:
#
#     # TA-Lib <commit> <FN>
#     # inputs: <binding printed by dump_golden>
#     dataset,params,index,<outputs...>
#
# `params` is `default` or `name=value;...` in paramsets.toml's key order.
# Empty output cells are TA-Lib's lookback rows.
#
# Every candlestick (CDL*) also runs at each non-default row of
# test_candlestick.c's `cdlGlobalsMatrix` (rows 1-4, from the extracted table),
# as the parameter set `cdlrow=r`, over both datasets: those rows are the
# matrix's oracle, since test_candlestick.c only compares languages with each
# other there.

using TOML

include(joinpath(@__DIR__, "..", "cparse.jl"))

const DATASETS = ("ref252", "gdata10000")

paramstring(p) = isempty(p) ? "default" : join(("$k=$v" for (k, v) in p), ';')

const CDLTABLE = joinpath(@__DIR__, "..", "..", "test", "talib", "tables",
    "test_candlestick.toml")
const CDLSETTINGS = ("BodyLong", "BodyVeryLong", "BodyShort", "BodyDoji", "ShadowLong",
    "ShadowVeryLong", "ShadowShort", "ShadowVeryShort", "Near", "Far", "Equal")
const RANGETYPES = Dict("TA_RangeType_RealBody" => 0, "TA_RangeType_HighLow" => 1,
    "TA_RangeType_Shadows" => 2)

# dump_golden's cdl.<Setting>=<rangeType>:<avg>:<factor> arguments for matrix row r
# (0-based, as the C array).
function cdlargs(r)
    row = TOML.parsefile(CDLTABLE)["tables"]["cdlGlobalsMatrix"]["rows"][r+1]
    return map(collect(CDLSETTINGS)) do st
        k = lowercasefirst(st)
        "cdl.$st=$(RANGETYPES[row["$(k)_type"]]):$(row["$(k)_avg"]):$(row["$(k)_factor"])"
    end
end

expandargs(p) =
    reduce(vcat, (k == "cdlrow" ? cdlargs(v) : ["$k=$v"] for (k, v) in p); init = String[])

function runone(bin, data, fn, p)
    args = expandargs(p)
    out = IOBuffer()
    err = IOBuffer()
    proc = run(pipeline(ignorestatus(`$bin $data $fn $args`); stdout = out, stderr = err))
    proc.exitcode == 3 && return nothing
    proc.exitcode == 0 || error("dump_golden $fn $args: ", String(take!(err)))
    lines = split(String(take!(out)), '\n'; keepempty = false)
    return lines[1], lines[2], lines[3:end]
end

function generate(bin, fn, sets)
    datadir = joinpath(@__DIR__, "..", "..", "test", "data")
    outdir = joinpath(@__DIR__, "..", "..", "test", "golden")
    mkpath(outdir)
    inputs = header = nothing
    body = IOBuffer()
    for ds in DATASETS, p in sets
        ds == "gdata10000" && !isempty(p) && keys(p) != Set(["cdlrow"]) && continue
        r = runone(bin, joinpath(datadir, "$ds.csv"), fn, p)
        r === nothing && continue
        inputs = r[1]
        header = r[2]
        ps = paramstring(p)
        for l in r[3]
            println(body, ds, ',', ps, ',', l)
        end
    end
    header === nothing && error("$fn: no dataset has the inputs it needs")
    path = joinpath(outdir, "$fn.csv.gz")
    open(pipeline(`gzip -9n`; stdout = path), "w") do io
        println(io, "# TA-Lib ", TALIB_COMMIT, " ", fn)
        println(io, inputs)
        println(io, "dataset,params,", header)
        write(io, take!(body))
    end
    println(path, ": ", length(sets), " parameter sets, ", filesize(path), " bytes")
end

function main(root, fns)
    checkpin(root)
    bin = joinpath(@__DIR__, "dump_golden")
    isfile(bin) || error("build it first: make -C gen/golden TALIB=$root")
    sets = TOML.parsefile(joinpath(@__DIR__, "paramsets.toml"))
    for fn in fns
        extra = startswith(fn, "CDL") ? [Dict{String,Any}("cdlrow" => r) for r in 1:4] : []
        generate(bin, fn, [Dict{String,Any}(); get(sets, fn, Dict{String,Any}[]); extra])
    end
end

isinteractive() || main(ARGS[1], ARGS[2:end])
