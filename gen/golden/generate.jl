# Generates full-series goldens for TA-Lib functions.
#
#     make -C gen/golden TALIB=~/workspace/ta-lib
#     julia --project=gen gen/golden/generate.jl ~/workspace/ta-lib EMA RMA ...
#
# Each function runs through dump_golden at TA-Lib's defaults and at every
# parameter set paramsets.toml lists for it, over both datasets in test/data.
# The 10,000-bar set runs at the defaults only, which keeps the files small; the
# extra parameter sets run on the 252-bar set the tables use. A dataset missing an
# input the function needs (gdata10000 has no volume) is skipped. The results go to test/golden/<FN>.csv.gz:
#
#     # TA-Lib <commit> <FN>
#     # inputs: <binding printed by dump_golden>
#     dataset,params,index,<outputs...>
#
# `params` is `default` or `name=value;...` in paramsets.toml's key order.
# Empty output cells are TA-Lib's lookback rows.

using TOML

include(joinpath(@__DIR__, "..", "cparse.jl"))

const DATASETS = ("ref252", "gdata10000")

paramstring(p) = isempty(p) ? "default" : join(("$k=$v" for (k, v) in p), ';')

function runone(bin, data, fn, p)
    args = ["$k=$v" for (k, v) in p]
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
        ds == "gdata10000" && !isempty(p) && continue
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
        generate(bin, fn, [Dict{String,Any}(); get(sets, fn, Dict{String,Any}[])])
    end
end

isinteractive() || main(ARGS[1], ARGS[2:end])
