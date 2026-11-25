# S11, TA-Lib 0.8.3's overlap and statistics additions: the CausalFrames-only
# MEDIAN and KURTOSIS, the structured CG and CTI, BBW and PERCENTB in both
# forms, and the plain ALMA, VIDYA, MCGD, FRAMA and ICHIMOKU, against TA-Lib's
# goldens, tables and oracles.

using CausalIndicators: ALMAKernel, VIDYAKernel, CMOUKernel

# One of each plain S11 state, for the missing, streaming, allocation and JET
# checks.
const PLAIN_S11 = [
    ALMA(:close; period = 7), ALMA(:close; period = 1),
    VIDYA(:close; period = 5,
        cmoperiod = 4, unstable = 2), VIDYA(:close; period = 1, unstable = 2),
    McGinley(:close; period = 5, unstable = 1), FRAMA(; period = 6, unstable = 1),
    Ichimoku(; tenkanperiod = 3, kijunperiod = 5, senkoubperiod = 8),
    BBW(:close; matype = :vidya, period = 6, unstable = 1),
    PercentB(:close; matype = :alma, period = 6),
    MA(:close; matype = :vidya, period = 5), MA(:close; matype = :alma, period = 5),
]

const ICHIMOKU_OUTS = (:outTenkanSen, :outKijunSen, :outSenkouSpanA, :outSenkouSpanB)

# BBW and PERCENTB at a golden's parameters: the structured form for the SMA
# without an unstable period, the plain one otherwise.
function bollingerstatrun(ctor, out, p, data)
    m = matypecode(get(p, :optInMAType, 0))
    per = get(p, :optInTimePeriod, 20)
    up, dn = get(p, :optInNbDevUp, 2.0), get(p, :optInNbDevDn, 2.0)
    if m === :sma && get(p, :unstable, 0) == 0
        r = foldseries(ctor(:close; nbdevup = up, nbdevdn = dn), data; window = Bars(per))
        return (r[Symbol(:w_close_, out)],)
    end
    s = ctor(:close; matype = m, period = per, nbdevup = up, nbdevdn = dn,
        unstable = get(p, :unstable, 0))
    return (foldseries(s, data)[Symbol(:close_, out)],)
end

# The C tests' synthetic series (almaSynth, vidyaSynth, mcgdSynth, framaSynth).
synth083(n) = [100.0 + 10.0 * sin(i / 7.0) + 0.15 * i + 2.0 * sin(i / 2.3) for i in 0:(n-1)]
function framasynth(n)
    c = synth083(n)
    i = 0:(n-1)
    return (high = c .+ 1.0 .+ 0.5 .* abs.(sin.(i ./ 3.0)),
        low = c .- 1.0 .- 0.5 .* abs.(cos.(i ./ 5.0)), close = c)
end

tarr(t, name) = Float64.(t["arrays"][name]["values"])
# A table's real parameter, TA-Lib's range limits included.
tareal(v) = v == "TA_REAL_MAX" ? 3e37 : v == "TA_REAL_MIN" ? -3e37 : Float64(v)
trows(t, name) = t["tables"][name]["rows"]

# One output of `s` over the series `x` (as the column `:close`).
series1(s, x; window = nothing) = only(foldseries(s, (close = x,); window))

# C's `memcmp` on two doubles: equal bits, so -0.0 is not 0.0 and NaN is NaN.
samebits(a, b) =
    !ismissing(a) && !ismissing(b) &&
    reinterpret(UInt64, Float64(a)) ==
    reinterpret(UInt64, Float64(b))

# The sample excess kurtosis G2 of `w` in BigFloat, an oracle for one window.
function g2big(w)
    setprecision(BigFloat, 256) do
        x = big.(w)
        n = length(x)
        m = sum(x) / n
        m2 = sum((x .- m) .^ 2)
        m4 = sum((x .- m) .^ 4)
        s2 = m2 / (n - 1)
        Float64(
            n * (n + 1) / ((n - 1) * (n - 2) * (n - 3)) * m4 / s2^2 -
            3 * (n - 1)^2 / ((n - 2) * (n - 3)),
        )
    end
end

# The corpora of test_bbw.c and test_percentb.c (bbw_build_series,
# pctb_build_series), by the name a golden row gives; `nothing` for the PEG
# series, which reads ta_test_reference.c's EMA peg and is not ported.
function bandcorpus(name, close)
    lcgrows(seed, n, f) = map(f, lcgsym(seed, n))
    name in ("CORPUS",) && return close
    name == "NEGCORPUS" && return -close
    name == "INTCORPUS" && return floor.(close)
    name == "TICK100" &&
        return lcgrows(0x447A, 300, u -> (10000.0 + (u >= 0 ? 1.0 : 0.0)) / 100)
    name == "BIG1E8" &&
        return lcgrows(0x447B, 300, u -> (1.0e10 + trunc((u + 1) * 1.5)) / 100)
    name == "FINE100" &&
        return lcgrows(0x447C, 300, u -> (1.0e10 + trunc((u + 1) * 1.5)) / 1.0e8)
    name == "EPS" && return lcgrows(0x447D, 200, u -> (u >= 0 ? 1.0 : -1.0) * eps())
    name == "LONG" && return lcgrows(0x447E, 100_500, u -> 100.0 + 20.0 * u)
    name == "FLATPOS" && return fill(5.0, 60)
    name == "FLATNEG" && return fill(-5.0, 60)
    name == "ZERO" && return zeros(60)
    name == "ALT" && return [iseven(i) ? 1.0 : -1.0 for i in 0:59]
    name == "STEPFLAT" && return [close[min(i, 39)+1] for i in 0:79]
    name == "SUBULP" && return (x = fill(1.0e8, 100); x[[31, 61]] .= nextfloat(1.0e8); x)
    name == "HD" && return nothing   # passed in by the caller
    return nothing
end

# One BBW or PERCENTB golden case: `out` over bars `startIdx:endIdx` (TA-Lib's
# call, seeded `lookback` bars before startIdx), in the structured form for
# the SMA at no unstable period and the `matype` form otherwise.
function bandcase(ctor, x, startidx, endidx, n, up, dn, m, u)
    if m === :sma && u == 0
        run =
            sl -> series1(ctor(:close; nbdevup = up, nbdevdn = dn), sl.close;
                window = Bars(n))
        lb = n - 1
    else
        run =
            sl -> series1(
                ctor(:close; matype = m, period = n, nbdevup = up,
                    nbdevdn = dn, unstable = u), sl.close)
        lb = max(CausalIndicators.malookback(Val(m), n, u), n - 1)
    end
    return tablerun(run, (close = x,), startidx, endidx, lb)
end

@testset "TA-Lib 0.8.3 overlap and statistics" begin
    @testset "goldens" begin
        # CausalFrames only: Median, and Kurtosis's G2, under Bars(n).
        checkgoldens("MEDIAN"; accepts = WINDOW, outputs = (:outReal,)) do p, data
            n = get(p, :optInTimePeriod, 30)
            (foldseries(Median(:close), data; window = Bars(n)).w_close_median,)
        end
        # The fourth moment's quotient: TA-Lib's binomial expansion and
        # CausalFrames' exact deviations agree to far below 1e-9 of a kurtosis
        # of order 1.
        checkgoldens("KURTOSIS"; accepts = WINDOW, outputs = (:outReal,),
            atol = 1e-9) do p, data
            n = get(p, :optInTimePeriod, 30)
            (foldseries(Kurtosis(:close), data; window = Bars(n)).w_close_kurtosis,)
        end
        checkgoldens("CG"; accepts = WINDOW, outputs = (:outReal,), atol = 1e-9) do p, data
            n = get(p, :optInTimePeriod, 10)
            (foldseries(CG(:close), data; window = Bars(n)).w_close_cg,)
        end
        checkgoldens("CTI"; accepts = WINDOW, outputs = (:outReal,), atol = 1e-9) do p, data
            n = get(p, :optInTimePeriod, 20)
            (foldseries(CTI(:close), data; window = Bars(n)).w_close_cti,)
        end
        checkgoldens("BBW"; accepts = WINDOW, outputs = (:outReal,), atol = 1e-9) do p, data
            bollingerstatrun(BBW, :bbw, p, data)
        end
        checkgoldens("PERCENTB"; accepts = WINDOW, outputs = (:outReal,),
            atol = 1e-9) do p, data
            bollingerstatrun(PercentB, :percentb, p, data)
        end
        checkgoldens("ALMA"; outputs = (:outReal,)) do p, data
            s = ALMA(:close; period = get(p, :optInTimePeriod, 9),
                sigma = get(p, :optInSigma, 6.0), offset = get(p, :optInOffset, 0.85))
            (foldseries(s, data).close_alma,)
        end
        checkgoldens("VIDYA"; outputs = (:outReal,)) do p, data
            s = VIDYA(:close; period = get(p, :optInTimePeriod, 12),
                cmoperiod = get(p, :optInCMOPeriod, 9), unstable = get(p, :unstable, 0))
            (foldseries(s, data).close_vidya,)
        end
        checkgoldens("MCGD"; outputs = (:outReal,)) do p, data
            s = McGinley(:close; period = get(p, :optInTimePeriod, 14),
                unstable = get(p, :unstable, 0))
            (foldseries(s, data).close_mcgd,)
        end
        checkgoldens("FRAMA"; outputs = (:outReal,)) do p, data
            s = FRAMA(; period = get(p, :optInTimePeriod, 16),
                unstable = get(p, :unstable, 0))
            (foldseries(s, data).frama,)
        end
        checkgoldens("ICHIMOKU"; outputs = ICHIMOKU_OUTS) do p, data
            s = Ichimoku(; tenkanperiod = get(p, :optInTenkanPeriod, 9),
                kijunperiod = get(p, :optInKijunPeriod, 26),
                senkoubperiod = get(p, :optInSenkouBPeriod, 52))
            Tuple(foldseries(s, data))
        end
    end

    @testset "test_median.c" begin
        t = loadtable("test_median")
        corpus = tarr(t, "medianCorpus")
        # numpy.median on the 40-bar corpus, bit for bit.
        for (n, g) in
            ((7, "medianGolden_7"), (8, "medianGolden_8"), (20, "medianGolden_20"))
            got = series1(Median(:close), corpus; window = Bars(n))
            want = tarr(t, g)
            @test count(!ismissing, got) == length(want)
            @test all(samebits.(got[n:end], want))
        end
        # A ramp's median is its mid-window value, the mean of the two central
        # bars at even n; a constant is itself.
        ramp = [2.0 * i + 5.0 for i in 0:399]
        for n in 2:40
            got = series1(Median(:close), ramp; window = Bars(n))
            @test all(t -> samebits(got[t], (ramp[t-n+1] + ramp[t]) / 2), n:400)
            @test all(
                ==(7.25),
                skipmissing(series1(Median(:close), fill(7.25, 400);
                    window = Bars(n))),
            )
        end
        # At odd n MEDIAN is PERCENTILE at 50, bit for bit; at even n it is not:
        # on 1, 2, 3, 4 it gives 2.5 where PERCENTILE gives 2.
        close = loadref().close
        for n in (3, 7, 21)
            @test isequal(series1(Median(:close), close; window = Bars(n)),
                series1(Quantile(:close, 0.5; interpolation = :nearestrank), close;
                    window = Bars(n)))
        end
        @test series1(Median(:close), [1.0, 2, 3, 4]; window = Bars(4))[4] == 2.5
        @test series1(Quantile(:close, 0.5; interpolation = :nearestrank), [1.0, 2, 3, 4];
            window = Bars(4))[4] == 2.0
    end

    @testset "test_kurtosis.c" begin
        t = loadtable("test_kurtosis")
        close = loadref().close
        # The 60-digit goldens over TA_SREF's close, at 2e-12.
        for g in trows(t, "kurtGoldens")
            got = series1(Kurtosis(:close), close; window = Bars(g["period"]))
            @test findfirst(!ismissing, got) == g["period"]
            @test got[g["bar"]+1] ≈ g["exact"] atol = 2e-12 rtol = 2e-12
        end
        # The benign corpus at periods 10 and 20, and the near-degenerate one
        # (base + k ulp at 2^20) at period 8, where scipy misses by 375%.
        for (x, n, g) in (("kurtBenign", 10, "kurtBenign_g2_10"),
            ("kurtBenign", 20, "kurtBenign_g2_20"),
            ("kurtNearDegenerate", 8, "kurtNearDegenerate_g2_8"))
            got = collect(
                skipmissing(series1(Kurtosis(:close), tarr(t, x); window = Bars(n))),
            )
            want = tarr(t, g)
            @test length(got) == length(want)
            @test all(isapprox.(got, want; rtol = 1e-12, atol = 1e-12))
        end
        # Excel's documented example, KURT(3, 4, 5, 2, 3, 4, 5, 6, 4, 7).
        @test series1(Kurtosis(:close), tarr(t, "kurtExcel"); window = Bars(10))[10] ≈
              -0.151799637208425 atol = 1e-12
        # An arithmetic progression is uniform: G2 = −6/5 at every n.
        for n in (4, 5, 9, 30)
            got = series1(Kurtosis(:close), [3.0 + 0.25i for i in 0:99]; window = Bars(n))
            @test all(v -> isapprox(v, -1.2; atol = 1e-12), skipmissing(got))
        end
        # No spread, no kurtosis: NaN on exactly the flat windows, after a
        # varied lead-in, at every level and period; and the varied windows
        # against the exact oracle.
        for level in (0.1, 100.0, 100.37, 3.3, 31498938283.17, 3.7e-67), n in (4, 49, 103)
            lead = level .* (1 .+ 1e-3 .* ((1:n) .% 7 .- 3) .* 1e-3)
            x = vcat(lead, fill(level, 10n))
            got = series1(Kurtosis(:close), x; window = Bars(n))
            @test all(isnan, got[(2n):end])
            @test all(
                i ->
                    isnan(got[i]) || isapprox(got[i], g2big(x[(i-n+1):i]);
                        rtol = 1e-10, atol = 1e-10), n:(2n-1))
        end
        # One-ulp moves on a flat level stay exact against the oracle.
        u = nextfloat(100.37) - 100.37
        x = [i % 20 == 0 ? 100.37 + ((i % 7) - 3) * u : 100.37 for i in 0:399]
        x[1] = 100.37 * 1.001
        got = series1(Kurtosis(:close), x; window = Bars(40))
        @test all(
            i ->
                isequal(got[i], g2big(x[(i-39):i])) ||
                isapprox(got[i], g2big(x[(i-39):i]); rtol = 1e-9), 40:400)
    end

    @testset "test_cg.c" begin
        # The C test's edge windows, exactly (CG_FLAT_REL for a flat 0.1).
        edges = (([1.0, 1, 2], -1.75), ([0.0, 1], -1.0), ([1.0, 0], -2.0),
            ([zeros(9); 1.0], -1.0), ([1.0; zeros(9)], -10.0), (fill(7.0, 2), -1.5),
            (fill(7.0, 10), -5.5), (fill(2.0^-60, 2), -1.5), (fill(2.0^-60, 10), -5.5),
            (zeros(2), -1.5), (zeros(10), -5.5), (fill(-0.0, 2), -1.5),
            (fill(-0.0, 10), -5.5), ([2.0, -1, -1], -2.0), ([-1.0, -1, -2], -1.75),
            ([100.0, 100, 100, 101], -1001 / 401), ([2.0^-60, 2.0^-59], -4 / 3),
            ([1.0, -2], 0.0), ([2.0^50, 1 - 2.0^50], -1125899906842625.0))
        for (w, want) in edges
            @test series1(CG(:close), w; window = Bars(length(w)))[end] == want
        end
        for n in (10, 1000)
            @test series1(CG(:close), fill(0.1, n); window = Bars(n))[end] ≈ -(n + 1) / 2 rtol =
                1e-12
        end
        # Negating the series leaves CG unchanged, bit for bit.
        close = loadref().close
        for n in 2:30
            a = series1(CG(:close), close; window = Bars(n))
            b = series1(CG(:close), -close; window = Bars(n))
            @test all(i -> ismissing(a[i]) ? ismissing(b[i]) : a[i] == b[i], eachindex(a))
        end
        # A positive series stays in [−n, −1].
        @test all(
            v -> -10 <= v <= -1,
            skipmissing(series1(CG(:close), close;
                window = Bars(10))),
        )
    end

    @testset "test_cti.c" begin
        t = loadtable("test_cti")
        close = loadref().close
        # The exact-arithmetic goldens over TA_SREF's close, at 1e-12.
        for g in trows(t, "ctiGoldens")
            got = series1(CTI(:close), close; window = Bars(g["period"]))
            @test got[g["bar"]+1] ≈ g["exact"] atol = 1e-12
        end
        # The cancellation corpus: spread 1e-5 on a level of 100, which
        # n·Σx² − (Σx)² loses. The variance is measured from a shift and holds,
        # but the cross term Σk·x − Σx·(n − 1)/2 is two price-scale sums each
        # rounded once, about 1e-8 of it here, where ta_CTI.c's shifted sums
        # meet the C test's 1e-9. A shifted age-weighted sum would be an
        # upstream accumulator (PLAN.md, S10).
        got = collect(
            skipmissing(
                series1(CTI(:close), tarr(t, "ctiCancelCorpus");
                    window = Bars(20)),
            ),
        )
        want = tarr(t, "ctiCancelGolden")
        @test length(got) == length(want)
        @test maximum(abs.(got .- want)) <= 1e-8
        @test_broken maximum(abs.(got .- want)) <= 1e-9
        # Exact lines give exactly ±1.
        for (x, s) in
            (([10.0 + 0.5i for i in 0:399], 1.0), ([10.0 - 0.5i for i in 0:399], -1.0))
            for n in 2:7:60
                @test all(==(s), skipmissing(series1(CTI(:close), x; window = Bars(n))))
            end
        end
        # A window gone flat gives exactly 0, at three levels.
        for level in (close[27], close[252], 0.1), n in 2:60
            x = vcat(close[1:100], fill(level, 300))
            got = series1(CTI(:close), x; window = Bars(n))
            @test all(==(0.0), got[(100+n):end])
        end
        # Two bars: the sign of the move, or 0 for none.
        got = series1(CTI(:close), close; window = Bars(2))
        for i in 2:252
            d = close[i] - close[i-1]
            @test d == 0 ? got[i] == 0 : isapprox(got[i], sign(d); atol = 1e-9)
        end
        # The coefficient stays in [−1, 1].
        for n in (3, 14, 50)
            @test all(
                v -> -1 <= v <= 1,
                skipmissing(series1(CTI(:close), close;
                    window = Bars(n))),
            )
        end
    end

    @testset "test_bbw.c and test_percentb.c goldens" begin
        close = loadref().close
        nskipped = 0
        for (fn, ctor, file, table) in (("BBW", BBW, "test_bbw", "bbwGoldens"),
            ("PERCENTB", PercentB, "test_percentb", "pctbGoldens"))
            t = loadtable(file)
            for r in trows(t, table)
                v = r["values"]
                tag, series = v[1], replace(v[2], r"^(BBW|PCTB)_" => "")
                startidx, endidx, n, up, dn = v[3], v[4], v[5], tareal(v[6]), tareal(v[7])
                m, u, beg, nb = tablematype(v[8]), v[9], v[10], v[11]
                rowsname = match(r"\(\s*(\w+)\s*\)", v[end])[1]
                x = series == "HD" ? tarr(t, "pctbHd") : bandcorpus(series, close)
                x === nothing && (nskipped += 1; continue)
                got = bandcase(ctor, x, startidx, endidx, n, up, dn, m, u)
                @test findfirst(!ismissing, got) - 1 == beg
                @test count(!ismissing, got) == nb
                if fn == "BBW"
                    for row in trows(t, rowsname)
                        g, e = got[row["bar"]+1], row["exact"]
                        ok =
                            row["mid0"] != 0 || row["tol"] == 0 ? samebits(g, e) :
                            abs(g - e) <= row["tol"]
                        ok || @info "BBW golden" tag row["bar"] g e row["tol"]
                        @test ok
                    end
                else
                    # The tolerance of test_percentb.c: what the deviation's and
                    # the middle band's errors do to %B, measured here against
                    # the frozen sigma and M, plus the quotient's own.
                    rows = trows(t, rowsname)
                    sd = bandcase((c; kw...) -> StdDev(c), x, startidx, endidx, n, 0.0,
                        0.0, :sma, 0)
                    mid = tablerun(
                        sl -> foldseries(
                            m === :sma && u == 0 ?
                            BollingerBands(:close) :
                            BollingerBands(:close; matype = m, period = n,
                                unstable = u), sl;
                            window = m === :sma && u == 0 ? Bars(n) : nothing)[2],
                        (close = x,), startidx, endidx,
                        m === :sma && u == 0 ? n - 1 :
                        max(CausalIndicators.malookback(Val(m), n, u), n - 1))
                    K = up + dn
                    eV, eM, absM = 1e-15, 1e-15, 0.0
                    for row in rows
                        b = row["bar"] + 1
                        row["kind"] == 0 &&
                            (eV = max(eV, abs(sd[b] - row["sigma"]) / row["sigma"]))
                        d = abs(mid[b] - row["M"])
                        absM = max(absM, d)
                        row["M"] != 0 && (eM = max(eM, d / abs(row["M"])))
                    end
                    @test eV <= 1e-6 && eM <= 1e-6
                    for row in rows
                        g, q = got[row["bar"]+1], row["q"]
                        if row["kind"] == 0
                            tol =
                                eV * abs(q - dn / K) +
                                (row["M"] != 0 ? eM * abs(row["M"]) : absM) /
                                (abs(K) * row["sigma"]) + row["own"]
                            ok = abs(g - q) <= tol
                        else
                            ok = samebits(g, q)
                        end
                        ok || @info "PERCENTB golden" tag row["bar"] g q
                        @test ok
                    end
                end
            end
        end
        @test nskipped == 2   # the PEG series, once each
        # Bollinger's worked example as he printed it, at every default.
        hd = tarr(loadtable("test_percentb"), "pctbHd")
        @test series1(PercentB(:close), hd; window = Bars(20))[20] ≈ 0.6830 atol = 5e-5
    end

    @testset "BBW and PERCENTB compose BBANDS" begin
        # Each is read off BBANDS' own bands, bit for bit, in both forms.
        close = loadref().close
        for (kw, window) in (((;), Bars(20)), ((; nbdevup = 1.0, nbdevdn = 3.0), Bars(5)),
            ((; matype = :ema, period = 10), nothing),
            ((; matype = :vidya, period = 10, nbdevup = 2.5, nbdevdn = 1.5), nothing))
            b = foldseries(BollingerBands(:close; kw...), (close = close,); window)
            w = series1(BBW(:close; kw...), close; window)
            pb = series1(PercentB(:close; kw...), close; window)
            up, mid, lo = Tuple(b)
            for i in eachindex(close)
                ismissing(mid[i]) && (@test ismissing(w[i]) && ismissing(pb[i]); continue)
                @test samebits(w[i], mid[i] == 0 ? 0.0 : (up[i] - lo[i]) / mid[i] * 100)
                @test samebits(pb[i],
                    up[i] == lo[i] ? 0.5 : (close[i] - lo[i]) / (up[i] - lo[i]))
            end
        end
        # A zero middle band gives 0, and coincident bands 0.5.
        @test all(==(0.0), skipmissing(series1(BBW(:close), zeros(30); window = Bars(5))))
        @test all(
            ==(0.5),
            skipmissing(series1(PercentB(:close), fill(3.0, 30);
                window = Bars(5))),
        )
        @test all(
            ==(0.5),
            skipmissing(
                series1(PercentB(:close; nbdevup = 0, nbdevdn = 0),
                    close; window = Bars(5)),
            ),
        )
    end

    @testset "test_alma.c" begin
        t = loadtable("test_alma")
        close = loadref().close
        for g in trows(t, "almaGolden")
            got = series1(
                ALMA(:close; period = g["n"], sigma = g["sigma"],
                    offset = g["offset"]), close)
            @test findfirst(!ismissing, got) == g["n"]
            @test got[g["bar"]+1] ≈ g["want"] rtol = 1e-14
        end
        got = series1(ALMA(:close), tarr(t, "almaSpyClose"))
        @test maximum(abs.(collect(skipmissing(got)) .- tarr(t, "almaSpyAlma"))) <= 5.1e-8
        # Tulip's beta/alma.c, expression for expression, over the grid: the
        # same bits.
        c = synth083(1200)
        function tulip(x, n, sigma, offset)
            m = floor(offset * (n - 1))
            s = n / sigma
            w = [exp(-1 * ((i - m) * (i - m)) / (2 * (s * s))) for i in 0:(n-1)]
            w ./= sum(w; init = 0.0) == 0 ? 1 : foldl(+, w)
            return [
                foldl((a, j) -> a + x[i-n+j] * w[j], 1:n; init = 0.0) for i in n:length(x)
            ]
        end
        for n in Int.(tarr(t, "almaGridN")), sigma in tarr(t, "almaGridSigma"),
            offset in tarr(t, "almaGridOffset")

            n > 1 || continue
            got = series1(ALMA(:close; period = n, sigma, offset), c)
            ok = all(samebits.(got[n:end], tulip(c, n, sigma, offset)))
            ok || @info "ALMA Tulip" n sigma offset
            @test ok
        end
        # Period 1 copies, the sign of a zero included.
        x = [-0.0, 0.0, 1.25, -0.0, -3.5, 0.0, 1e300, -1e-310]
        @test all(samebits.(series1(ALMA(:close; period = 1), x), x))
        # The corners: every output inside its window's range, and a one-bar
        # kernel (sigma TA_REAL_MAX) the peak bar exactly.
        for (n, sigma, offset) in ((2, 0.01, 0.0), (2, 3e37, 1.0), (9, 0.01, 1.0),
            (9, 3e37, 0.0), (60, 0.01, 0.5), (60, 3e37, 1.0))
            got = series1(ALMA(:close; period = n, sigma, offset), c)
            for i in n:1200
                lo, hi = extrema(c[(i-n+1):i])
                @test lo * (1 - 4e-16) <= got[i] <= hi * (1 + 4e-16)
                sigma == 3e37 && @test samebits(got[i], offset == 1 ? c[i] : c[i-n+1])
            end
        end
        for (n, sigma, offset) in ((0, 6.0, 0.85), (100_001, 6.0, 0.85), (9, 0.0099, 0.85),
            (9, -6.0, 0.85), (9, 6.0, -0.01), (9, 6.0, 1.01))
            @test_throws ArgumentError ALMA(:close; period = n, sigma, offset)
        end
        # MA's ALMA is ALMA at the default sigma and offset, bit for bit.
        for n in (2, 3, 5, 9, 10, 21, 50, 200)
            @test isequal(series1(MA(:close; period = n, matype = :alma), c),
                series1(ALMA(:close; period = n), c))
        end
    end

    @testset "test_vidya.c" begin
        t = loadtable("test_vidya")
        c = synth083(1200)
        vid(x, n, m; u = 0) =
            series1(VIDYA(:close; period = n, cmoperiod = m, unstable = u), x)
        for g in vcat(trows(t, "vidyaGolden"), trows(t, "vidyaTail"))
            got = vid(c, g["n"], g["m"])
            @test findfirst(!ismissing, got) == g["m"] + 1
            @test got[g["bar"]+1] ≈ g["want"] rtol = 1e-13
        end
        # ta4j's CMO, the oscillator VIDYA scales by.
        for g in trows(t, "vidyaTa4jCmo")
            @test series1(CMOU(:close; period = g["n"]), c)[g["bar"]+1] ≈ g["want"] atol =
                1e-12
        end
        # LEAN's lookback: VIDYA(p, p) starts at bar p.
        for p in Int.(tarr(t, "vidyaLeanP"))
            @test findfirst(!ismissing, vid(c, p, p)) == p + 1
        end
        # The composite: from its first full window on, VIDYA is the EMA step
        # scaled by CMOU's magnitude, and through the warm-up by the CMO of the
        # changes seen so far.
        for n in Int.(tarr(t, "vidyaGridN")), m in Int.(tarr(t, "vidyaGridM")),
            u in Int.(tarr(t, "vidyaGridUnst"))

            got = vid(c, n, m; u)
            cm = series1(CMOU(:close; period = m), c)
            alpha = 2.0 / (n + 1)
            v, su, sd = c[1], 0.0, 0.0
            for j in 2:m
                d = c[j] - c[j-1]
                d > 0 ? (su += d) : d < 0 && (sd -= d)
                tt = su + sd
                v = fma(
                    c[j] - v,
                    tt > 0 ? alpha * (abs((100 * (su - sd)) / tt) / 100) : 0.0,
                    v,
                )
            end
            ref = Vector{Union{Missing,Float64}}(missing, 1200)
            for j in (m+1):1200
                v = fma(c[j] - v, alpha * (abs(cm[j]) / 100), v)
                ref[j] = v
            end
            ref[1:(m+u)] .= missing
            ok = all(
                i ->
                    ismissing(got[i]) ? ismissing(ref[i]) :
                    isapprox(got[i], ref[i]; rtol = 1e-13), 1:1200)
            ok || @info "VIDYA composite" n m u
            @test ok
        end
        # The line stops on a flat run: from the first all-flat CMO window on,
        # it holds; and a constant series is itself.
        for pre in 0:1
            x = [
                i >= 30 ? 130.7 :
                pre == 0 ? 100.0 + sin(i / 3.0) :
                (i % 3 == 0 ? 5000.0 : i % 3 == 1 ? 0.37 : 100.0) + i / 7.0 for
                i in 0:69
            ]
            got = vid(x, 9, 9)
            @test all(==(got[39]), got[40:end])
        end
        @test all(==(42.17), skipmissing(vid(fill(42.17, 70), 12, 9)))
        # On a strictly rising ramp |CMO| is 100, so VIDYA is the EMA step,
        # bit for bit, seeded on the first bar.
        x = [1000.0 + 3i + (i * i) % 3 for i in 0:299]
        for n in (2, 12, 30), m in (2, 9, 40)
            got = vid(x, n, m)
            alpha = 2.0 / (n + 1)
            v = x[1]
            ok = true
            for i in 2:300
                v = fma(x[i] - v, alpha, v)
                i > m && (ok &= got[i] == v)
            end
            @test ok
        end
        # Period 1 copies, delayed by the unstable period; MA's period-1 copy
        # is not delayed.
        for u in (0, 7)
            got = vid(x, 1, 9; u)
            @test all(ismissing, got[1:u]) && isequal(got[(u+1):end], x[(u+1):end])
        end
        @test isequal(series1(MA(:close; period = 1, matype = :vidya, unstable = 5), c), c)
        # MA's VIDYA is VIDYA at Chande's 12:9 ratio, bit for bit.
        for u in (0, 5),
            (n, m) in ((2, 2), (5, 4), (9, 7), (10, 8), (12, 9), (14, 11),
                (20, 15), (26, 20), (30, 23), (50, 38), (200, 150))

            @test isequal(series1(MA(:close; period = n, matype = :vidya, unstable = u), c),
                vid(c, n, m; u))
        end
        # BBANDS' middle band is MA(close, 20, VIDYA).
        # BBANDS' lookback is the deviation's 19 bars, past VIDYA's 15.
        b = foldseries(BollingerBands(:close; matype = :vidya, period = 20), (close = c,))
        @test findfirst(!ismissing, b[2]) == 20
        @test isequal(b[2][20:end], vid(c, 20, 15)[20:end])
    end

    @testset "test_mcgd.c" begin
        t = loadtable("test_mcgd")
        c = synth083(1200)
        mc(x, n; u = 0) = series1(McGinley(:close; period = n, unstable = u), x)
        for g in vcat(trows(t, "mcgdGolden"), trows(t, "mcgdLean"))
            got = mc(c, g["period"])
            @test findfirst(!ismissing, got) == g["period"]
            @test got[g["bar"]+1] ≈ g["want"] rtol = 1e-14
        end
        # McGinley's worked example: seven bars at 10, then 14 or 6.
        for (close, want) in ((14.0, 170570 / 16807), (6.0, 3170 / 567))
            got = mc([fill(10.0, 7); close], 7)
            @test got[7] == 10.0
            @test got[8] ≈ want rtol = 1e-15
        end
        # A zero price holds the line, inside and after the warm-up.
        x = copy(c[1:300])
        x[151] = 0.0
        got = mc(x, 14)
        @test all(isfinite, skipmissing(got)) && got[151] == got[150] &&
              got[152] != got[151]
        x = copy(c[1:300])
        x[6] = 0.0
        @test all(isfinite, skipmissing(mc(x, 14)))
        # A price that takes the line toward zero.
        for g in trows(t, "mcgdCancel")
            x = copy(c[1:300])
            x[122] = g["bar121"]
            @test mc(x, 14)[g["bar"]+1] ≈ g["want"] rtol = 1e-13
        end
    end

    @testset "test_frama.c" begin
        t = loadtable("test_frama")
        s = framasynth(1500)
        fr(d, n; u = 0) = only(foldseries(FRAMA(; period = n, unstable = u), d))
        for g in trows(t, "framaGolden")
            got = fr(s, g["period"])
            @test findfirst(!ismissing, got) == g["period"] + 1
            @test got[g["bar"]+1] ≈ g["want"] rtol = 1e-12
        end
        # High and low collapsed onto the close: every half has a range.
        got = fr((high = s.close, low = s.close), 16)
        for g in trows(t, "framaCollapsed")
            @test got[g["bar"]+1] ≈ g["want"] rtol = 1e-13
        end
        # Ehlers' own N = 16 output, printed to the cent: the filter, and his
        # trendline 2F[t] − F[t−8], away from half-cent ties.
        rows = trows(t, "framaEhlers")
        h, l = [r["high"] for r in rows], [r["low"] for r in rows]
        f = fr((high = h, low = l), 16)
        halfcent(v, hh, ll) =
            v == (hh + ll) / 2 && isodd(round(Int, hh * 100) + round(Int, ll * 100))
        nf = ntl = 0
        for i in 17:length(rows)
            halfcent(f[i], h[i], l[i]) && continue
            nf += 1
            @test abs(f[i] - rows[i]["filt"]) <= 0.005
        end
        for i in 25:length(rows)
            f[i] == (h[i] + l[i]) / 2 && halfcent(f[i-8], h[i-8], l[i-8]) && continue
            ntl += 1
            @test abs(2f[i] - f[i-8] - rows[i]["tl"]) <= 0.005
        end
        @test nf == 622 && ntl == 616
        # A brute-force FRAMA, each window scanned, on series with flat
        # stretches: equal bits.
        hh, ll = copy(s.high), copy(s.low)
        for i in 0:1499
            lv =
                300 <= i <= 339 ? 130.7 :
                500 <= i <= 507 ? s.close[500] :
                700 <= i <= 707 ? 120.0 : 708 <= i <= 715 ? 125.0 : nothing
            lv === nothing || (hh[i+1] = ll[i+1] = lv)
        end
        scale = -4.6 / 0.6931471805599453
        for n in (2, 4, 16, 40)
            half = n ÷ 2
            got = fr((high = hh, low = ll), n)
            prev = (hh[n] + ll[n]) / 2
            ok = true
            for i in (n+1):1500
                hi1, lo1 = maximum(hh[(i-half+1):i]), minimum(ll[(i-half+1):i])
                hi2, lo2 = maximum(hh[(i-n+1):(i-half)]), minimum(ll[(i-n+1):(i-half)])
                r1, r2, r = hi1 - lo1, hi2 - lo2, max(hi1, hi2) - min(lo1, lo2)
                p = (hh[i] + ll[i]) / 2
                if r1 > 0 && r2 > 0 && r1 + r2 > r
                    a = exp(scale * log((r1 + r2) / r))
                    prev = fma(1 - a, prev, a * p)
                else
                    prev = p
                end
                ok &= samebits(got[i], prev)
            end
            @test ok
        end
        # Odd periods are refused; the lookback is the period plus the
        # unstable bars.
        for n in (3, 15, 99999)
            @test_throws ArgumentError FRAMA(; period = n)
        end
        for n in (2, 16, 40), u in (0, 3, 17)
            @test findfirst(!ismissing, fr(s, n; u)) == n + u + 1
        end
    end

    @testset "test_ichimoku.c" begin
        t = loadtable("test_ichimoku")
        ref = loadref()
        ich(d, a, b, c) = Tuple(
            foldseries(Ichimoku(; tenkanperiod = a, kijunperiod = b,
                senkoubperiod = c), d),
        )
        got = ich(ref, 9, 26, 52)
        @test findfirst(!ismissing, got[1]) == 52
        for g in trows(t, "ichGolden")
            @test got[g["output"]+1][g["bar"]+1] == g["value"]
        end
        # Each line is MIDPRICE over its own window and span A their mean.
        for r in vcat(trows(t, "ichCompose"), trows(t, "ichLookback"))
            a, b, c = r["tenkan"], r["kijun"], r["senkouB"]
            o = ich(ref, a, b, c)
            L = max(a, b, c)
            @test findfirst(!ismissing, o[1]) == L
            for (k, n) in ((1, a), (2, b), (4, c))
                want = foldseries(MidPrice(), ref; window = Bars(n)).w_midprice
                @test isequal(o[k][L:end], want[L:end])
            end
            @test isequal(o[3][L:end], (o[1][L:end] .+ o[2][L:end]) ./ 2)
        end
        # Span A halves the two rounded midpoints, which the four-extreme
        # average misses on at least 20 bars here.
        h, l = tarr(t, "ichSpanAHigh"), tarr(t, "ichSpanALow")
        o = ich((high = h, low = l), 3, 5, 7)
        nd = 0
        for i in 7:length(h)
            hT, lT = maximum(h[(i-2):i]), minimum(l[(i-2):i])
            hK, lK = maximum(h[(i-4):i]), minimum(l[(i-4):i])
            want = ((hT + lT) / 2 + (hK + lK) / 2) / 2
            @test o[3][i] == want
            nd += (hT + lT + hK + lK) / 4 != want
        end
        @test nd >= 20
        # Swapping the tenkan and span B periods swaps those lines and leaves
        # the base line; span A must change.
        a, b = ich(ref, 9, 26, 52), ich(ref, 52, 26, 9)
        @test isequal(a[1], b[4]) && isequal(a[4], b[1]) && isequal(a[2], b[2])
        @test !isequal(a[3], b[3])
        # A flat series is its level on every line.
        flat = (high = fill(50.0, 252), low = fill(50.0, 252))
        @test all(o -> all(==(50.0), skipmissing(o)), ich(flat, 9, 26, 52))
    end

    @testset "missing bars are skipped" begin
        r = loadref()
        n = 80
        base = map(c -> c[1:n], r)
        withgaps = map(
            c -> (v = Union{Missing,Float64}[]; foreach(x -> push!(v, missing, x), c); v),
            base,
        )
        for s in PLAIN_S11
            want = foldseries(s, base)
            got = foldseries(s, withgaps)
            for o in keys(want)
                @test all(ismissing, got[o][1:2:end])
                @test isequal(got[o][2:2:end], want[o])
            end
        end
    end

    @testset "streaming properties" begin
        t = map(c -> c[1:120], loadref())
        for s in PLAIN_S11
            checkstreaming(s, t)
        end
        for (s, w) in ((CG(:close), 10), (CTI(:close), 12), (BBW(:close), 8),
            (PercentB(:close; nbdevup = 1.5, nbdevdn = 2.5), 8), (Median(:close), 6),
            (Kurtosis(:close), 9))
            checkstreaming(s, t; window = Bars(w), timewindow = w - 1)
        end
    end

    @testset "zero allocations" begin
        rng = Random.MersenneTwister(5)
        mkrow(x) = (time = 1, open = x, high = x + 1, low = x - 1, close = x, volume = 1e5)
        for s in PLAIN_S11
            st = CausalFrames.fresh(s, S2_INTYPES)
            for x in 100.0 .+ randn(rng, 60)
                CausalFrames.update!(st, mkrow(x))
            end
            @test allocs(CausalFrames.update!, st, mkrow(101.5)) == 0
            @test allocs(
                CausalFrames.update!,
                st,
                merge(mkrow(101.5), (close = missing,)),
            ) ==
                  0
            @test allocs(CausalFrames.value, st) == 0
            @test allocs(fresh!, st) == 0
        end
    end

    @testset "parameter ranges" begin
        @test_throws ArgumentError ALMA(:close; period = 0)
        @test_throws ArgumentError ALMA(:close; sigma = 0.0)
        @test_throws ArgumentError ALMA(:close; offset = 1.5)
        @test_throws ArgumentError VIDYA(:close; period = 0)
        @test_throws ArgumentError VIDYA(:close; cmoperiod = 1)
        @test_throws ArgumentError VIDYA(:close; unstable = -1)
        @test_throws ArgumentError McGinley(:close; period = 1)
        @test_throws ArgumentError FRAMA(; period = 7)
        @test_throws ArgumentError FRAMA(; period = 0)
        @test_throws ArgumentError Ichimoku(; tenkanperiod = 1)
        @test_throws ArgumentError Ichimoku(; senkoubperiod = 100_001)
        @test_throws ArgumentError BBW(:close; period = 20)
        @test_throws ArgumentError BBW(:close; matype = :nope)
        @test_throws ArgumentError BBW(:close; matype = :ema, period = 1)
        @test_throws ArgumentError PercentB(:close; name = :pb)
        @test_throws ArgumentError PercentB(:close; matype = :sma, unstable = -1)
    end
end
