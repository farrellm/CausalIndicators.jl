# Runs the MC/DC capture (capture.c) and writes its records, deduplicated, to
# test/talib/candles/mcdc.txt.gz:
#
#     make -C gen/candles TALIB=~/workspace/ta-lib
#     julia --project=gen gen/candles/capture.jl ~/workspace/ta-lib
#
# The file starts with a `# TA-Lib <commit> ...` line; the records follow in
# capture.c's format, each one R, S, O, H, L, C and V line.

include(joinpath(@__DIR__, "..", "cparse.jl"))

function main(root)
    checkpin(root)
    bin = joinpath(@__DIR__, "capture")
    isfile(bin) || error("build it first: make -C gen/candles TALIB=$root")
    ref = joinpath(@__DIR__, "..", "..", "test", "data", "ref252.csv")
    raw = tempname()
    run(pipeline(`$bin $ref $raw`; stdout = devnull))
    lines = readlines(raw)
    rm(raw)
    length(lines) % 7 == 0 || error("capture: ragged output")
    records = unique(join(lines[i:(i+6)], '\n') for i in 1:7:length(lines))
    outdir = joinpath(@__DIR__, "..", "..", "test", "talib", "candles")
    mkpath(outdir)
    path = joinpath(outdir, "mcdc.txt.gz")
    open(pipeline(`gzip -9n`; stdout = path), "w") do io
        println(io, "# TA-Lib ", TALIB_COMMIT, " test_candlestick.c pattern-builder calls,",
            " captured by gen/candles/capture.c. Do not edit.")
        foreach(r -> println(io, r), records)
    end
    println(path, ": ", length(records), " records, ", filesize(path), " bytes")
end

isinteractive() || main(ARGS[1])
