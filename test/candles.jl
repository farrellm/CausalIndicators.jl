# S7, the 61 candlestick patterns of `CausalIndicators.Candles`, against TA-Lib's
# goldens (at the default settings, test_candlestick.c's settings matrix and the
# penetration sets), the MC/DC fixtures captured from test_candlestick.c, and its
# table.

using CausalIndicators.Candles

const CANDLE_FNS = [(J, ta, pen) for (J, ta, pen, _) in Candles.CANDLES]

const CDL_RANGES = Dict("TA_RangeType_RealBody" => :realbody,
    "TA_RangeType_HighLow" => :highlow, "TA_RangeType_Shadows" => :shadows)
# CandleSettings' fields, as the matrix's columns spell them.
const CDL_FIELDS = (bodylong = "bodyLong", bodyverylong = "bodyVeryLong",
    bodyshort = "bodyShort", bodydoji = "bodyDoji", shadowlong = "shadowLong",
    shadowverylong = "shadowVeryLong", shadowshort = "shadowShort",
    shadowveryshort = "shadowVeryShort", near = "near", far = "far", equal = "equal")

# test_candlestick.c's cdlGlobalsMatrix row `r` (0-based) as a CandleSettings.
function cdlmatrix(r)
    row = loadtable("test_candlestick")["tables"]["cdlGlobalsMatrix"]["rows"][r+1]
    kw = map(
        k -> CandleSetting(CDL_RANGES[row["$(k)_type"]], row["$(k)_avg"],
            row["$(k)_factor"]), CDL_FIELDS)
    return CandleSettings(; kw...)
end

# A pattern's summarizer at a golden's parameters.
function candlecall(J, pen, p::AbstractDict)
    settings = haskey(p, :cdlrow) ? cdlmatrix(p[:cdlrow]) : CandleSettings()
    f = getfield(Candles, J)
    pen === nothing && return f(; settings)
    return f(; settings, penetration = get(p, :optInPenetration, pen))
end

candleout(s, data) = only(values(foldseries(s, data)))

# One state of each shape, for the missing, streaming, allocation and JET
# checks: one, two, three, four and five bars, a penetration, and the Hikkake
# family's state.
const PLAIN_S7 = [
    Candles.Doji(), Candles.Hammer(), Candles.Engulfing(), Candles.MorningStar(),
    Candles.ThreeLineStrike(), Candles.MatHold(; penetration = 0.4), Candles.Hikkake(),
    Candles.HikkakeMod(;
        settings = CandleSettings(; near = CandleSetting(:highlow, 3, 0.5)),
    ),
]

const CDL_RANGEORDER = (:realbody, :highlow, :shadows)   # TA_RangeType

# The pattern-builder calls gen/candles/capture.c recorded from
# test_candlestick.c: one NamedTuple per call.
function loadmcdc()
    path = joinpath(TESTDIR, "talib", "candles", "mcdc.txt.gz")
    lines = filter(l -> !startswith(l, '#'),
        split(String(transcode(GzipDecompressor, read(path))), '\n'; keepempty = false))
    nums(l) = parse.(Float64, split(l)[2:end])
    return map(1:7:length(lines)) do i
        r = split(lines[i])
        sv = nums(lines[i+1])
        kw = map(enumerate(keys(CDL_FIELDS))) do (k, f)
            t, a, x = sv[3k-2], sv[3k-1], sv[3k]
            f => CandleSetting(CDL_RANGEORDER[Int(t)+1], Int(a), x)
        end
        (name = String(r[2]), pen = r[3] == "-" ? nothing : parse(Float64, r[3]),
            startidx = parse(Int, r[4]), endidx = parse(Int, r[5]),
            beg = parse(Int, r[6]), nb = parse(Int, r[7]),
            settings = CandleSettings(; kw...),
            data = (open = nums(lines[i+2]), high = nums(lines[i+3]),
                low = nums(lines[i+4]), close = nums(lines[i+5])),
            out = parse.(Int, split(lines[i+6])[2:end]))
    end
end

@testset "candles" begin
    @testset "settings" begin
        d = CandleSettings()
        @test d.bodydoji == CandleSetting(:highlow, 10, 0.1)
        @test d.shadowlong == CandleSetting(:realbody, 0, 1.0)
        @test cdlmatrix(0) == d
        @test cdlmatrix(1) != d
        @test_throws ArgumentError CandleSetting(:body, 10, 1.0)
        @test_throws ArgumentError CandleSetting(:realbody, -1, 1.0)
        @test_throws ArgumentError CandleSetting(:realbody, 100_000_001, 1.0)
        @test_throws ArgumentError CandleSetting(:realbody, 10, NaN)
        @test CandleSetting(:shadows, 0, -1.0).factor == -1.0
        @test repr(CandleSetting(:shadows, 5, 0.5)) == "CandleSetting(:shadows, 5, 0.5)"
    end

    @testset "goldens" begin
        n = 0
        for (J, ta, pen) in CANDLE_FNS
            n += checkgoldens(ta; outputs = (:outInteger,)) do p, data
                (candleout(candlecall(J, pen, p), data),)
            end
        end
        # Five settings rows on two datasets, plus two penetrations for seven.
        @test n == 61 * 10 + 7 * 2
    end

    @testset "test_candlestick.c pattern builders" begin
        byname = Dict(ta => (J, pen) for (J, ta, pen) in CANDLE_FNS)
        recs = loadmcdc()
        for r in recs
            J, pen = byname[r.name]
            f = getfield(Candles, J)
            s = pen === nothing ? f(; r.settings) :
                f(; r.settings, penetration = r.pen)
            lb = Candles.candlelookback(Val(J), r.settings)
            got = tablerun(d -> candleout(s, d), r.data, r.startidx, r.endidx, lb)
            want = Vector{Union{Missing,Int}}(missing, r.endidx + 1)
            want[(r.beg+1):(r.beg+r.nb)] = r.out
            ok = isequal(got, want)
            ok || @info "MC/DC record failed" r.name
            @test ok
        end
        # Every pattern's builder ran (Hikkake's twice: its predicate gate too).
        @test length(recs) == 63
        @test Set(r.name for r in recs) == Set(ta for (_, ta, _) in CANDLE_FNS)
    end

    @testset "test_candlestick.c table" begin
        # Every row asks for bar 0 alone, inside every lookback: no output.
        data = loadref()
        rows = loadtable("test_candlestick")["tables"]["tableTest"]["rows"]
        byname = Dict(ta => (J, pen) for (J, ta, pen) in CANDLE_FNS)
        for r in rows
            J, pen = byname[r["name"]]
            p = Dict{Symbol,Real}(:optInPenetration => r["params"][1])
            s = candlecall(J, pen, p)
            lb = Candles.candlelookback(Val(J), CandleSettings())
            got = tablerun(d -> candleout(s, d), data, r["startIdx"], r["endIdx"], lb)
            @test r["expectedRetCode"] == "TA_SUCCESS"
            @test all(ismissing, got)
        end
        @test length(rows) == 61
    end

    @testset "lookbacks" begin
        # A pattern reads no bar before the first: its bars fit its lookback even
        # with every average turned off.
        zero_ = CandleSettings(;
            map(f -> f => CandleSetting(:realbody, 0, 1.0),
                keys(CDL_FIELDS))...,
        )
        for (J, _, _) in CANDLE_FNS
            _, nbars = Candles.candleshape(Val(J))
            @test nbars <= Candles.candlelookback(Val(J), zero_) + 1
            s = getfield(Candles, J)(; settings = zero_)
            out = candleout(s, map(c -> c[1:40], loadref()))
            @test findfirst(!ismissing, out) - 1 == Candles.candlelookback(Val(J), zero_)
        end
    end

    @testset "missing bars are skipped" begin
        base = map(c -> c[1:120], loadref())
        withgaps = map(
            c -> (v = Union{Missing,Float64}[]; foreach(x -> push!(v, missing, x), c); v),
            base,
        )
        for s in PLAIN_S7
            want = candleout(s, base)
            got = candleout(s, withgaps)
            @test all(ismissing, got[1:2:end])
            @test isequal(got[2:2:end], want)
        end
    end

    @testset "non-finite bars" begin
        # A NaN high at bar k (0-based) poisons bar k's prices and, through the
        # 10-bar averages, the thresholds of bars k+1 to k+10. A pattern reading
        # `nbars` bars emits 0 until the last of those is out of its reach, then
        # agrees with the clean series again.
        data = map(c -> c[1:300], loadgdata())
        k = 150
        bad =
            merge(data, (high = [i == k + 1 ? NaN : x for (i, x) in enumerate(data.high)],))
        for (J, nbars) in ((:Doji, 1), (:LongLine, 1), (:MatHold, 5), (:Engulfing, 2))
            s = getfield(Candles, J)()
            want = candleout(s, data)
            got = candleout(s, bad)
            clean = J === :Engulfing ? k + nbars : k + 10 + nbars    # no averages
            @test all(==(0), got[(k+1):clean])
            @test isequal(got[(clean+1):end], want[(clean+1):end])
            @test isequal(got[1:k], want[1:k])
        end
    end

    @testset "streaming properties" begin
        t = map(c -> c[1:150], loadref())
        for s in PLAIN_S7
            checkstreaming(s, t)
        end
    end

    @testset "zero allocations" begin
        rng = Random.MersenneTwister(7)
        mkrow(x) = (time = 1, open = x, high = x + 1.5, low = x - 1, close = x + 0.25,
            volume = 1e5)
        for s in PLAIN_S7
            st = CausalFrames.fresh(s, S2_INTYPES)
            for x in 100.0 .+ randn(rng, 120)
                CausalFrames.update!(st, mkrow(x))
            end
            @test allocs(CausalFrames.update!, st, mkrow(101.5)) == 0
            @test allocs(
                CausalFrames.update!,
                st,
                merge(mkrow(101.5), (close = missing,)),
            ) == 0
            @test allocs(CausalFrames.value, st) == 0
            @test allocs(fresh!, st) == 0
        end
    end

    @testset "constructors" begin
        @test keys(CausalFrames.emptyvalue(Candles.Hammer())) == (:cdlhammer,)
        @test keys(CausalFrames.emptyvalue(Candles.TwoCrows(; name = :tc))) == (:tc,)
        out = foldseries(Candles.Doji(; open = :o, high = :h, low = :l, close = :c),
            (o = [1.0, 2.0], h = [2.0, 3.0], l = [0.5, 1.5], c = [1.0, 2.5]))
        @test keys(out) == (:cdldoji,)
        for (J, ta, pen) in CANDLE_FNS
            s = getfield(Candles, J)()
            @test keys(CausalFrames.emptyvalue(s)) == (Symbol(lowercase(ta)),)
            if pen !== nothing
                @test_throws ArgumentError getfield(Candles, J)(; penetration = -0.1)
                @test_throws ArgumentError getfield(Candles, J)(; penetration = NaN)
            end
        end
        # The names stay out of the top level.
        @test !(:Hammer in names(CausalIndicators))
        @test :Hammer in names(Candles)
    end
end
