# The S1 functions that are CausalFrames only (SMA, SUM, CUMSUM, MAX, MIN,
# MINMAX, MAXINDEX, MININDEX, MINMAXINDEX): this package adds only their TA-Lib
# tests. The structured MidPoint and MidPrice share the extremum tables.

# Bars since the newest extreme of the `n`-bar window ending at each bar, by a
# scan: test_minmax.c's checkIndexOutput, whose tie rule (the most recent bar)
# TA-Lib shares with CausalFrames since 0.8.3 (#503).
function scanindex(x, n, better)
    return map(eachindex(x)) do i
        i < n && return missing
        best = i - n + 1
        for k in (i-n+2):i
            (x[k] == x[best] || better(x[k], x[best])) && (best = k)
        end
        i - best
    end
end

@testset "rolling" begin
    @testset "CausalFrames-only goldens" begin
        w(p, d) = Bars(get(p, :optInTimePeriod, d))
        checkgoldens("SUM"; accepts = WINDOW, outputs = (:outReal,)) do p, data
            (foldseries(Sum(:close), data; window = w(p, 30)).w_close_sum,)
        end
        checkgoldens("CUMSUM"; outputs = (:outReal,)) do p, data
            (foldseries(Sum(:close), data).close_sum,)
        end
        checkgoldens("MAX"; accepts = WINDOW, outputs = (:outReal,)) do p, data
            (foldseries(Max(:close), data; window = w(p, 30)).w_close_max,)
        end
        checkgoldens("MIN"; accepts = WINDOW, outputs = (:outReal,)) do p, data
            (foldseries(Min(:close), data; window = w(p, 30)).w_close_min,)
        end
        checkgoldens("MINMAX"; accepts = WINDOW, outputs = (:outMin, :outMax)) do p, data
            o = foldseries([Min(:close), Max(:close)], data; window = w(p, 30))
            (o.w_close_min, o.w_close_max)
        end
        checkgoldens("MAXINDEX"; accepts = WINDOW, outputs = (:outInteger,),
            convert = sincefromindex) do p, data
            (foldseries(MaxIndex(:close), data; window = w(p, 30)).w_close_maxindex,)
        end
        checkgoldens("MININDEX"; accepts = WINDOW, outputs = (:outInteger,),
            convert = sincefromindex) do p, data
            (foldseries(MinIndex(:close), data; window = w(p, 30)).w_close_minindex,)
        end
        checkgoldens("MINMAXINDEX"; accepts = WINDOW, outputs = (:outMinIdx, :outMaxIdx),
            convert = sincefromindex) do p, data
            o = foldseries([MinIndex(:close), MaxIndex(:close)], data; window = w(p, 30))
            (o.w_close_minindex, o.w_close_maxindex)
        end
    end

    @testset "test_minmax.c table rows" begin
        open_ = loadref().open  # test_minmax.c runs on the open series
        rows = loadtable("test_minmax")["tables"]["tableTest"]["rows"]
        runs = Dict(
            "TA_MAX_TEST" => (Max(:x), :w_x_max), "TA_MIN_TEST" => (Min(:x), :w_x_min),
            "TA_MINMAX_TEST" => (Min(:x), :w_x_min),  # out0 is the minimum
            "TA_MIDPOINT_TEST" => (MidPoint(:x), :w_x_midpoint),
            "TA_MAXINDEX_TEST" => (MaxIndex(:x), :w_x_maxindex),
            "TA_MININDEX_TEST" => (MinIndex(:x), :w_x_minindex),
            "TA_MINMAXINDEX_TEST" => (MinIndex(:x), :w_x_minindex))
        n = 0
        for r in rows
            s, out = runs[r["theFunction"]]
            p = r["optInTimePeriod"]
            if r["expectedRetCode"] != "TA_SUCCESS"
                continue  # periods below 2 are a Bars(n) choice here, not an error
            end
            got = tablerun((x = open_,), r["startIdx"], r["endIdx"], p - 1) do d
                foldseries(s, d; window = Bars(p))[out]
            end
            # test_minmax.c holds the index forms to a window scan, not to the
            # row's value (a placeholder 0).
            isindex = endswith(r["theFunction"], "INDEX_TEST")
            checkrow(got, r; out = "oneOfTheExpectedOutReal0",
                index = "oneOfTheExpectedOutRealIndex0", value = !isindex)
            if isindex
                better = r["theFunction"] == "TA_MAXINDEX_TEST" ? (>) : (<)
                want = scanindex(open_[1:(r["endIdx"]+1)], p, better)
                want[1:r["startIdx"]] .= missing
                @test isequal(got, want)
            end
            n += 1
        end
        @test n >= 15
    end

    @testset "test_per_hl.c MIDPRICE rows" begin
        r = loadref()
        rows = loadtable("test_per_hl")["tables"]["tableTest"]["rows"]
        n = 0
        for row in rows
            row["theFunction"] == "TA_MIDPRICE_TEST" || continue
            row["expectedRetCode"] == "TA_SUCCESS" || continue
            p = row["optInTimePeriod"]
            got = tablerun(r, row["startIdx"], row["endIdx"], p - 1) do d
                foldseries(MidPrice(), d; window = Bars(p)).w_midprice
            end
            checkrow(got, row; out = "oneOfTheExpectedOutReal0",
                index = "oneOfTheExpectedOutRealIndex0")
            n += 1
        end
        @test n >= 10
    end

    @testset "test_cumsum.c C40" begin
        t = loadtable("test_cumsum")["arrays"]
        net = Float64.(t["c40_A"]["values"]) .- Float64.(t["c40_D"]["values"])
        got = foldseries(Sum(:x), (; x = net)).x_sum
        @test got == cumsum(net)
        @test got[1:8] == t["c40_first8"]["values"]
        @test got[end] == 4400
        # The (3, 7) slice restarts the sum at bar 3.
        @test foldseries(Sum(:x), (; x = net[4:8])).x_sum == t["c40_slice37"]["values"]
    end

    @testset "test_rolling_extremum.c and test_minmax.c block-scan oracle" begin
        # The definition, a naive window scan, over periods straddling the
        # block-structure edges and lengths chosen relative to each period.
        rng = Random.MersenneTwister(147)
        for p in (2, 3, 29, 30, 31, 32, 60, 199), extra in (0, 1, p - 1, p, 2p + 1)
            n = p + extra
            # Coarse values, so windows hold ties.
            x = round.(100 .+ 10 .* randn(rng, n); digits = 0)
            h = x .+ rand(rng, 0:3, n)
            l = x .- rand(rng, 0:3, n)
            o = foldseries(
                [Max(:x), Min(:x), MidPoint(:x), MidPrice(), MaxIndex(:x), MinIndex(:x)],
                (; x, high = h, low = l);
                window = Bars(p))
            # test_minmax.c's index sweep over a tied series: the newest tie.
            @test isequal(o.w_x_maxindex, scanindex(x, p, >))
            @test isequal(o.w_x_minindex, scanindex(x, p, <))
            for i in 1:n
                if i < p
                    @test ismissing(o.w_x_max[i]) && ismissing(o.w_midprice[i])
                    continue
                end
                wx = @view x[(i-p+1):i]
                @test o.w_x_max[i] === maximum(wx)
                @test o.w_x_min[i] === minimum(wx)
                @test o.w_x_midpoint[i] === (maximum(wx) + minimum(wx)) / 2
                @test o.w_midprice[i] ===
                      (maximum(@view h[(i-p+1):i]) + minimum(@view l[(i-p+1):i])) / 2
            end
        end
    end
end
