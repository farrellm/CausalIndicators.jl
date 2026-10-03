# S1 price transforms: AvgPrice, MedPrice, TypPrice and WclPrice, bar-local
# dependents over `Last`.

@testset "price" begin
    @testset "goldens" begin
        for (fn, s, out) in (("AVGPRICE", AvgPrice(), :avgprice),
            ("MEDPRICE", MedPrice(), :medprice), ("TYPPRICE", TypPrice(), :typprice),
            ("WCLPRICE", WclPrice(), :wclprice))
            checkgoldens(fn; outputs = (:outReal,)) do p, data
                (foldseries(s, data)[out],)
            end
            # Bar-local under any window once the window is full.
            r = loadref()
            whole = foldseries(s, r)[out]
            windowed = foldseries(s, r; window = Bars(5))
            got = windowed[Symbol(:w_, out)]
            @test all(ismissing, got[1:4]) && got[5:end] == whole[5:end]
        end
    end

    @testset "test_per_ohlc.c table rows" begin
        r = loadref()
        rows = loadtable("test_per_ohlc")["tables"]["tableTest"]["rows"]
        n = 0
        for row in rows
            row["theFunction"] == "TA_AVGPRICE_TEST" || continue
            row["expectedRetCode"] == "TA_SUCCESS" || continue
            got = tablerun(r, row["startIdx"], row["endIdx"], 0) do d
                foldseries(AvgPrice(), d).avgprice
            end
            checkrow(got, row; out = "oneOfTheExpectedOutReal0",
                index = "oneOfTheExpectedOutRealIndex0")
            n += 1
        end
        @test n >= 1
    end

    @testset "custom columns and integer input" begin
        t = (o = [1, 2], h = [4, 6], l = [0, 1], c = [3, 5])
        out = foldseries(
            [AvgPrice(; open = :o, high = :h, low = :l, close = :c),
                MedPrice(; high = :h, low = :l),
                TypPrice(; high = :h, low = :l, close = :c),
                WclPrice(; high = :h, low = :l, close = :c)], t)
        @test out.avgprice == [2.0, 3.5]
        @test out.medprice == [2.0, 3.5]
        @test out.typprice ≈ [7 / 3, 4.0]
        @test out.wclprice == [2.5, 4.25]
    end

    @testset "streaming properties" begin
        r = loadref()
        t = map(c -> c[1:80], r)
        for s in (AvgPrice(), MedPrice(), TypPrice(), WclPrice())
            checkstreaming(s, t)
            checkstreaming(s, t; window = Bars(3), timewindow = 2)
        end
    end
end
