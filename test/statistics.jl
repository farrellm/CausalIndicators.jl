# Statistic functions: StdDev and the CausalFrames-only VAR
# (`Variance(corrected = false)`) and AVGDEV (`MeanAbsDev`) (S3); the LINEARREG
# family, TSF, PercentRank100, Beta and the CausalFrames-only CORREL
# (`Correlation`) and PERCENTILE (`Quantile`) (S4). They are checked against
# TA-Lib's goldens, tables and the hand-ported C tests.

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
        # representation error per value.
        base = 1000 .* lcgsym(0x1BADCAFE, 400)
        shiftok = map(Iterators.product((2, 5, 20, 30), (1e6, 1e8, 1e10))) do (p, c)
            v0, v1 = tavar(base, p), tavar(base .+ c, p)
            all(p:400) do i
                tol = 1e-9 + 4c * eps() / max(sqrt(abs(v0[i])), 1e-30)
                abs(v1[i] - v0[i]) / abs(v0[i]) <= tol
            end
        end
        @test all(shiftok)
        # Scale invariance: var(c·x) = c²·var(x), including Bars(2), where a
        # window of two close values has a tiny variance.
        base = 100 .+ 20 .* lcgsym(0x5EED1234, 300)
        scaleok(p) = all((1e3, 1e-3, 7.5)) do c
            v0, v1 = tavar(base, p), tavar(c .* base, p)
            all(i -> abs(v1[i] - c^2 * v0[i]) <= 1e-9 * c^2 * v0[i], p:300)
        end
        @test scaleok(2) && scaleok(10) && scaleok(25)
        # Non-negativity under a spike, a level shift and a 1e8 level, and an
        # exactly constant series gives exactly 0.
        x = [1e8 + ((i * 13) % 7 - 3) * 0.01 for i in 0:499]
        x[101] = 1e12
        x[251:end] .= [3.0 + ((i * 7) % 5 - 2) * 0.1 for i in 250:499]
        @test all(p -> all(>=(0), skipmissing(tavar(x, p))), (2, 5, 20, 50))
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

    @testset "S4 goldens" begin
        for (fn, ctor) in (("LINEARREG", LinearReg), ("LINEARREG_SLOPE", LinearRegSlope),
            ("LINEARREG_INTERCEPT", LinearRegIntercept),
            ("LINEARREG_ANGLE", LinearRegAngle), ("TSF", TSF))
            checkgoldens(fn; outputs = (:outReal,)) do p, data
                w = Bars(get(p, :optInTimePeriod, 14))
                (only(foldseries(ctor(:close), data; window = w)),)
            end
        end
        checkgoldens("PERCENTRANK"; outputs = (:outReal,)) do p, data
            w = Bars(get(p, :optInTimePeriod, 100) + 1)
            (only(foldseries(PercentRank100(:close), data; window = w)),)
        end
        checkgoldens("PERCENTILE"; outputs = (:outReal,)) do p, data
            s = Quantile(:close, get(p, :optInPercentile, 50.0) / 100;
                interpolation = :nearestrank)
            (only(foldseries(s, data; window = Bars(get(p, :optInTimePeriod, 30)))),)
        end
        # A window where either series is flat has no correlation: TA-Lib gives
        # 0 and CausalFrames NaN (DESIGN.md, "Testing"). Those bars are checked
        # in "test_correl.c" below.
        flat(x, i, p) = i >= p && allequal(@view x[(i-p+1):i])
        checkgoldens("CORREL"; outputs = (:outReal,),
            skip = (d, p, i) -> (n = get(p, :optInTimePeriod, 30);
                flat(d.close, i, n) || flat(d.high, i, n))) do p, data
            w = Bars(get(p, :optInTimePeriod, 30))
            (only(foldseries(Correlation(:close, :high), data; window = w)),)
        end
        checkgoldens("BETA"; outputs = (:outReal,)) do p, data
            (
                foldseries(Beta(:close, :high; period = get(p, :optInTimePeriod, 5)),
                    data).close_high_beta,
            )
        end
    end

    @testset "test_per_hl.c BETA and CORREL rows" begin
        ref = loadref()
        n = 0
        for r in loadtable("test_per_hl")["tables"]["tableTest"]["rows"]
            f = r["theFunction"]
            f in ("TA_BETA_TEST", "TA_CORREL_TEST") || continue
            r["expectedRetCode"] == "TA_SUCCESS" || continue
            p = r["optInTimePeriod"]
            got = if f == "TA_BETA_TEST"
                tablerun(ref, r["startIdx"], r["endIdx"], p) do d
                    foldseries(Beta(:high, :low; period = p), d).high_low_beta
                end
            else
                tablerun(ref, r["startIdx"], r["endIdx"], p - 1) do d
                    only(foldseries(Correlation(:high, :low), d; window = Bars(p)))
                end
            end
            checkrow(got, r; out = "oneOfTheExpectedOutReal0",
                index = "oneOfTheExpectedOutRealIndex0")
            n += 1
        end
        @test n == 5
    end

    @testset "test_percentile.c" begin
        close = loadref().close
        # The pinned oracle, bit for bit.
        for r in loadtable("test_percentile")["tables"]["percentileOracle"]["rows"]
            s = Quantile(:close, r["pct"] / 100; interpolation = :nearestrank)
            got = only(foldseries(s, (; close); window = Bars(r["period"])))
            @test findfirst(!ismissing, got) == r["period"]
            @test got[r["bar"]+1] === Float64(r["want"])
        end
        # The textbook example: 5 values at 8 percentiles.
        a = Dict(k => v["values"] for (k, v) in loadtable("test_percentile")["arrays"])
        for (p, want) in zip(a["pctlBookP"], a["pctlBookOut"])
            s = Quantile(:x, p / 100; interpolation = :nearestrank)
            @test last(only(foldseries(s, (x = a["pctlBookIn"],); window = Bars(5)))) ==
                  want
        end
        # The exact integer rank ceil(P·n/100) where P·n/100 is an integer, which
        # a floating-point P/100·n can round past, against a sorted window.
        x = loadgdata().close[1:600]
        for r in loadtable("test_percentile")["tables"]["pctlExactRank"]["rows"]
            n, pct = r["period"], r["pct"]
            k = cld(pct * n, 100)
            s = Quantile(:x, pct / 100; interpolation = :nearestrank)
            got = only(foldseries(s, (; x); window = Bars(n)))
            @test all(i -> got[i] == sort(x[(i-n+1):i])[k], n:length(x))
        end
        # 0 and 100 percent are the window's minimum and maximum.
        for n in (2, 5, 30)
            lo = only(
                foldseries(Quantile(:close, 0.0; interpolation = :nearestrank),
                    (; close); window = Bars(n)),
            )
            hi = only(
                foldseries(Quantile(:close, 1.0; interpolation = :nearestrank),
                    (; close); window = Bars(n)),
            )
            @test isequal(lo, only(foldseries(Min(:close), (; close); window = Bars(n))))
            @test isequal(hi, only(foldseries(Max(:close), (; close); window = Bars(n))))
        end
    end

    @testset "test_percentrank.c" begin
        close = loadref().close
        # The pinned oracle, bit for bit: TA-Lib divides, then scales.
        rows = loadtable("test_percentrank")["tables"]["percentRankOracle"]["rows"]
        for r in rows
            got = only(
                foldseries(PercentRank100(:close), (; close);
                    window = Bars(r["period"] + 1)),
            )
            @test findfirst(!ismissing, got) - 1 == r["period"]
            @test got[r["bar"]+1] === Float64(r["want"])
        end
        @test length(rows) >= 20
        # The count map against a direct count, and the strict tie rule: a
        # constant series ranks 0 everywhere.
        for p in (2, 5, 30)
            got = only(foldseries(PercentRank100(:close), (; close); window = Bars(p + 1)))
            want = [
                i <= p ? missing :
                (count(<(close[i]), close[(i-p):(i-1)]) / p) * 100 for
                i in eachindex(close)
            ]
            @test isequal(got, want)
            flat = only(
                foldseries(PercentRank100(:x), (x = fill(3.5, 40),);
                    window = Bars(p + 1)),
            )
            @test all(==(0), skipmissing(flat))
        end
    end

    @testset "LINEARREG family (test_linearreg.c)" begin
        y = 100 .+ cumsum(lcgsym(0x11EA4E61, 300))
        fit(s, x, p) = only(foldseries(s, (; x); window = Bars(p)))
        for p in (2, 3, 14, 30)
            lr, sl, ic, an, tf = (
                fit(s(:x), y, p) for s in
                (LinearReg, LinearRegSlope, LinearRegIntercept,
                    LinearRegAngle, TSF)
            )
            # A direct least-squares fit of each window against 0:p-1.
            for i in p:length(y)
                w = y[(i-p+1):i]
                t = 0:(p-1)
                tm, wm = sum(t) / p, sum(w) / p
                m = sum((t .- tm) .* (w .- wm)) / sum((t .- tm) .^ 2)
                b = wm - m * tm
                @test sl[i] ≈ m atol = 1e-9
                @test ic[i] ≈ b rtol = 1e-12
                @test lr[i] ≈ b + m * (p - 1) rtol = 1e-12
                @test tf[i] ≈ b + m * p rtol = 1e-12
            end
            # Internal consistency.
            full = p:length(y)
            @test all(i -> an[i] ≈ atan(sl[i]) * 180 / π, full)
            @test all(i -> isapprox(tf[i], lr[i] + sl[i]; rtol = 1e-12), full)
            # The affine identity: a·y + c fits a·line + c, and the slope ignores
            # c.
            a, c = 3.5, -1e4
            alr, csl =
                fit(LinearReg(:x), a .* y .+ c, p), fit(LinearRegSlope(:x), y .+ c, p)
            @test all(i -> isapprox(alr[i], a * lr[i] + c; rtol = 1e-12), full)
            @test all(i -> isapprox(csl[i], sl[i]; atol = 1e-9), full)
            # A constant window has slope 0 and every value at the level. It
            # holds to round-off only: CausalFrames' windowed AgeWeightedSum
            # drops the rounding of `(n − 1)·x` when a row leaves, so on a
            # constant series it drifts by the same error every bar (an upstream
            # fix: an error-free product in its downdate! and combine!).
            k = fill(1234.5678, 200)
            sk, lk, tk = (fit(s(:x), k, p) for s in (LinearRegSlope, LinearReg, TSF))
            @test all(v -> abs(v) <= 1e-10, skipmissing(sk))
            @test all(v -> isapprox(v, 1234.5678; rtol = 1e-13), skipmissing(lk))
            @test all(v -> isapprox(v, 1234.5678; rtol = 1e-13), skipmissing(tk))
            # Bars(2) slides without residue.
            if p == 2
                @test all(==(0), skipmissing(sk))
            else
                @test_broken all(==(0), skipmissing(sk))
            end
        end
        # A straight line is fitted exactly.
        line = 7.0 .+ 0.25 .* (0:99)
        @test all(≈(0.25), skipmissing(fit(LinearRegSlope(:x), line, 10)))
        @test all(≈(45.0), skipmissing(fit(LinearRegAngle(:x), 7.0 .+ (0:99), 10)))
        # One large print leaves no residue once it has left the window.
        z = copy(y)
        z[100] = 1e12
        base, spiked = fit(LinearReg(:x), y, 14), fit(LinearReg(:x), z, 14)
        @test all(i -> isapprox(spiked[i], base[i]; rtol = 1e-12), 114:300)
    end

    @testset "test_correl.c" begin
        # The C test's LCG, so the data is the same on every Julia version.
        x = cumsum(lcgsym(0xC0FFEE05, 200))
        y = 0.6 .* x .+ lcgsym(0xC0FFEE06, 200)
        cor(a, b, p) = only(foldseries(Correlation(:a, :b), (; a, b); window = Bars(p)))
        for p in (2, 5, 30)
            r = cor(x, y, p)
            # The two-pass oracle.
            for i in p:200
                a, b = x[(i-p+1):i], y[(i-p+1):i]
                da, db = a .- sum(a) / p, b .- sum(b) / p
                want = sum(da .* db) / sqrt(sum(da .^ 2) * sum(db .^ 2))
                @test r[i] ≈ want atol = 1e-10
            end
            # Range, self-correlation and affine invariance, sign included.
            @test all(v -> -1 <= v <= 1, skipmissing(r))
            @test all(≈(1), skipmissing(cor(x, x, p)))
            ra, rn = cor(3 .* x .+ 1e6, y, p), cor(-2 .* x, y, p)
            @test all(i -> isapprox(ra[i], r[i]; atol = 1e-9), p:200)
            @test all(i -> isapprox(rn[i], -r[i]; atol = 1e-12), p:200)
        end
        # A flat window has no correlation: TA-Lib's degenerate guard gives 0,
        # CausalFrames' Correlation NaN (DESIGN.md, "Testing").
        flat = vcat(fill(5.0, 20), x[1:20])
        r = cor(flat, y[1:40], 10)
        @test all(isnan, r[10:20]) && all(!isnan, r[30:40])
    end

    @testset "test_beta.c" begin
        ref = loadref()
        rets(v) = [(v[i] - v[i-1]) / v[i-1] for i in 2:length(v)]
        for p in (1, 2, 5, 20)
            got = foldseries(Beta(:close, :high; period = p), ref).close_high_beta
            @test findfirst(!ismissing, got) - 1 == p
            # The two-pass oracle over the window's returns.
            rx, ry = rets(ref.close), rets(ref.high)
            for i in (p+1):252
                a, b = rx[(i-p):(i-1)], ry[(i-p):(i-1)]
                da, db = a .- sum(a) / p, b .- sum(b) / p
                v = sum(da .^ 2)
                want = v > 1e-14 * sum(a .^ 2) ? sum(da .* db) / v : 0.0
                @test got[i] ≈ want rtol = 1e-9 atol = 1e-12
            end
        end
        # A series against itself is 1, and a flat index has no variance, so 0,
        # whatever the other series does.
        self = foldseries(Beta(:close, :c2; period = 8), (close = ref.close,
            c2 = ref.close)).close_c2_beta
        @test all(v -> abs(v - 1) <= 1e-12, skipmissing(self))
        for py in (fill(17.0, 60), [17.0 + i % 5 for i in 0:59])
            got =
                foldseries(Beta(:x, :y; period = 30), (x = fill(42.0, 60), y = py)).x_y_beta
            @test all(==(0), skipmissing(got))
        end
        # A zero previous price contributes a zero return, as in TA-Lib.
        z = foldseries(Beta(:x, :y; period = 3),
            (x = [0.0, 1.0, 2.0, 4.0, 4.0], y = [1.0, 2.0, 4.0, 8.0, 8.0])).x_y_beta
        @test z[4] ≈ (
            let a = [0.0, 1.0, 1.0], b = [1.0, 1.0, 1.0]
                da = a .- sum(a) / 3
                sum(da .* (b .- 1)) / sum(da .^ 2)
            end
        ) atol = 1e-15
        # Returns are scale-free, so scaling either price leaves beta unchanged.
        scaled = foldseries(Beta(:close, :high; period = 5),
            (close = 1e-3 .* ref.close, high = 1e4 .* ref.high)).close_high_beta
        base = foldseries(Beta(:close, :high; period = 5), ref).close_high_beta
        @test all(i -> isapprox(scaled[i], base[i]; rtol = 1e-9), 6:252)
    end
end
