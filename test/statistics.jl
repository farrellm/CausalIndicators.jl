# S3 statistic functions: StdDev, and the CausalFrames-only VAR
# (`Variance(corrected = false)`) and AVGDEV (`MeanAbsDev`) under a `Bars`
# window, against TA-Lib's goldens, tables and the hand-ported test_stddev.c
# checks.

# The windowed population variance of `x` at period p, as TA-Lib's VAR.
tavar(x, p) = only(foldseries(Variance(:x; corrected = false), (; x); window = Bars(p)))

@testset "statistics" begin
    @testset "goldens" begin
        checkgoldens("STDDEV"; outputs = (:outReal,)) do p, data
            s = StdDev(:close; nbdev = get(p, :optInNbDev, 1.0))
            (
                foldseries(s, data; window = Bars(get(p, :optInTimePeriod, 5))).w_close_stddev,
            )
        end
        checkgoldens("VAR"; outputs = (:outReal,)) do p, data
            (tavar(data.close, get(p, :optInTimePeriod, 5)),)
        end
        checkgoldens("AVGDEV"; outputs = (:outReal,)) do p, data
            s = MeanAbsDev(:close)
            (
                foldseries(s, data; window = Bars(get(p, :optInTimePeriod, 14))).w_close_meanabsdev,
            )
        end
    end

    @testset "test_stddev.c and test_avgdev.c table rows" begin
        close = loadref().close
        n = 0
        for r in loadtable("test_stddev")["tables"]["tableTest"]["rows"]
            p, k = r["optInTimePeriod"], r["optInNbDeviation_1"]
            got = tablerun((; close), r["startIdx"], r["endIdx"], p - 1) do d
                only(foldseries(StdDev(:close; nbdev = k), d; window = Bars(p)))
            end
            checkrow(got, r; out = "oneOfTheExpectedOutReal0",
                index = "oneOfTheExpectedOutRealIndex0")
            n += 1
        end
        for r in loadtable("test_avgdev")["tables"]["tableTest"]["rows"]
            p = r["optInTimePeriod"]
            got = tablerun((; close), r["startIdx"], r["endIdx"], p - 1) do d
                only(foldseries(MeanAbsDev(:close), d; window = Bars(p)))
            end
            checkrow(got, r; out = "oneOfTheExpectedOutReal0",
                index = "oneOfTheExpectedOutRealIndex0")
            n += 1
        end
        @test n >= 9
    end

    @testset "test_stddev.c invariants" begin
        # Shift invariance, to the C test's tolerance: x + c carries ~c·eps of
        # representation error per value. CausalFrames' windowed Variance forms
        # `(Σx² − (Σx)²/n)/n`, which cancels under a large offset, so this leg
        # is broken until it is fixed upstream (CausalFrames.jl#89).
        base = 1000 .* lcgsym(0x1BADCAFE, 400)
        shiftok = map(Iterators.product((2, 5, 20, 30), (1e6, 1e8, 1e10))) do (p, c)
            v0, v1 = tavar(base, p), tavar(base .+ c, p)
            all(p:400) do i
                tol = 1e-9 + 4c * eps() / max(sqrt(abs(v0[i])), 1e-30)
                abs(v1[i] - v0[i]) / abs(v0[i]) <= tol
            end
        end
        @test_broken all(shiftok)
        # Scale invariance: var(c·x) = c²·var(x). Under Bars(2) a window of two
        # close values has a tiny variance, which the same cancellation
        # spoils (to ~1e-7), so that period is broken until #89 is fixed.
        base = 100 .+ 20 .* lcgsym(0x5EED1234, 300)
        scaleok(p) = all((1e3, 1e-3, 7.5)) do c
            v0, v1 = tavar(base, p), tavar(c .* base, p)
            all(i -> abs(v1[i] - c^2 * v0[i]) <= 1e-9 * c^2 * v0[i], p:300)
        end
        @test scaleok(10) && scaleok(25)
        @test_broken scaleok(2)
        # Non-negativity under a spike and a level shift, and an exactly
        # constant series gives exactly 0.
        x = [1e8 + ((i * 13) % 7 - 3) * 0.01 for i in 0:499]
        x[101] = 1e12
        x[251:end] .= [3.0 + ((i * 7) % 5 - 2) * 0.1 for i in 250:499]
        # The same cancellation drives VAR negative at the 1e8 level (Std
        # clamps it to 0), so that leg is broken until #89 is fixed.
        @test_broken all(p -> all(>=(0), skipmissing(tavar(x, p))), (2, 5, 20, 50))
        for p in (2, 5, 20, 50)
            @test all(
                >=(0),
                skipmissing(only(foldseries(StdDev(:x), (; x); window = Bars(p)))),
            )
            @test all(==(0), skipmissing(tavar(fill(1234567.0, 500), p)))
        end
    end

    @testset "test_stddev.c flat tail" begin
        # TA-Lib floors a variance below 1e-12 of the window's mean square to
        # exactly 0. CausalFrames' compensated sums do not floor, so a window
        # wholly inside a flat tail is held to that bound instead (DESIGN.md,
        # "Testing").
        for (k, level) in enumerate((100.0, 1234.56789, 1e8, 1e-6, 1e11)),
            p in (2, 5, 20, 49)

            x = vcat(
                level .* (1 .+ 0.05 .* lcgsym(0xF1A77A11 + k - 1, 100)),
                fill(level, 500),
            )
            sd = only(foldseries(StdDev(:x), (; x); window = Bars(p)))
            @test all(i -> 0 <= sd[i] <= 1e-6 * level, (100+p):600)
        end
    end

    @testset "constructors" begin
        @test keys(CausalFrames.emptyvalue(StdDev(:close))) == (:close_stddev,)
        # Two windows, two periods.
        out = foldseries(StdDev(:close; nbdev = 2), loadref(); window = Bars(5))
        @test keys(out) == (:w_close_stddev,)
    end
end
