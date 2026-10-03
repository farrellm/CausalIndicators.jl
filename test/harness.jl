# The test harness itself: foldseries, the data and table loaders, and the
# streaming-property helpers, checked on CausalFrames summarizers.

@testset "harness" begin
    @testset "reference data" begin
        ref = loadref()
        @test keys(ref) == (:open, :high, :low, :close, :volume)
        @test length(ref.close) == 252
        @test ref.open[1] == 92.5 && ref.volume[1] == 4077500
        g = loadgdata()
        @test keys(g) == (:open, :high, :low, :close)
        @test length(g.close) == 10_000
        @test g.close[1] == 111.45
    end

    @testset "extracted tables" begin
        t = loadtable("test_ma")
        @test t["commit"] == "2aa8eb0d79bcfc4d2ff3f7b445d37958c48e0788"
        rows = t["tables"]["tableTest"]["rows"]
        @test length(rows) == 93
        @test first(t["structs"]["TA_Test"]["fields"]) == "doRangeTestFlag"
        # { 1, TA_ANY_MA_TEST, 0, 0, 251, 30, TA_MAType_SMA, TA_SUCCESS, 0, 90.42, 29, 252-29 }
        r = only(
            x for x in rows if x["optInMAType_1"] == "TA_MAType_SMA" &&
                x["optInTimePeriod"] == 30 && x["oneOfTheExpectedOutRealIndex"] == 0
        )
        @test r["oneOfTheExpectedOutReal"] == 90.42 && r["expectedNbElement"] == 223
        @test any(
            x -> get(x, "rangecheck", false) &&
                 x["expectedRetCode"] == "TA_BAD_PARAM", rows)
    end

    @testset "foldseries" begin
        x = [1.0, 2.0, 4.0, 8.0, 16.0]
        out = foldseries([Sum(:x), Mean(:x)], (; x))
        @test out.x_sum == cumsum(x)
        out = foldseries(Max(:x), (; x); window = Bars(2))
        @test isequal(out.w_x_max, [missing, 2.0, 4.0, 8.0, 16.0])
        @test foldseries(Mean(:close), loadref(); window = Bars(30)).w_close_mean[30] ≈
              90.42 atol = 0.01
    end

    @testset "streaming helpers" begin
        rng = Random.MersenneTwister(3)
        n = 40
        t = (time = collect(1:n), x = randn(rng, n))
        whole =
            DataFrame(load(Context(0, n + 1), readtable(t) |> addsummarycolumns(Sum(:x))))
        for _ in 1:5
            sizes = randomsizes(rng, n)
            @test sum(sizes) == n
            p = chunked(t, sizes) |> addsummarycolumns(Sum(:x))
            @test DataFrame(load(Context(0, n + 1), p)).x_sum ≈ whole.x_sum
        end
        a = (x = [1.0, 2.0, 3.0],)
        b = (x = [10.0, 20.0, 30.0],)
        k = interleavekeys([a, b])
        @test k.key == [1, 2, 1, 2, 1, 2] && k.x == [1.0, 10.0, 2.0, 20.0, 3.0, 30.0]
        keyed = DataFrame(
            load(Context(0, 10),
                readtable(k) |> addsummarycolumns(Sum(:x); key = :key)),
        )
        @test keyed.x_sum[keyed.key .== 2] == cumsum(b.x)
    end
end
