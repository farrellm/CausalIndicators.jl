# S4 volume indicators: the structured AD, CMF, VWAP, MarketFI and RVOL, and the
# plain OBV, PVT, NVI, PVI, ADOSC, EFI and PVO, and the plain Beta (S4
# statistics), against TA-Lib's goldens, tables and oracles.

# One of each plain S4 state, for the missing, streaming, allocation and JET
# checks.
const PLAIN_S4 = [
    OBV(:close), PVT(), NVI(), PVI(), ADOSC(),
    ADOSC(; fastperiod = 5, slowperiod = 2,
        unstable = 1), EFI(; period = 4), EFI(; period = 1, unstable = 2),
    PVO(; fastperiod = 3, slowperiod = 6),
    PVO(; matype = :sma, fastperiod = 3,
        slowperiod = 5), Beta(:close, :high; period = 4),
]

@testset "volume" begin
    @testset "goldens" begin
        checkgoldens("AD"; outputs = (:outReal,), input = :volume) do p, data
            (foldseries(AD(), data).ad,)
        end
        checkgoldens("ADOSC"; outputs = (:outReal,), input = :volume) do p, data
            s = ADOSC(; fastperiod = get(p, :optInFastPeriod, 3),
                slowperiod = get(p, :optInSlowPeriod, 10),
                unstable = get(p, :unstable, 0))
            (foldseries(s, data).adosc,)
        end
        checkgoldens("CMF"; outputs = (:outReal,)) do p, data
            (foldseries(CMF(), data; window = Bars(get(p, :optInTimePeriod, 20))).w_cmf,)
        end
        checkgoldens("EFI"; outputs = (:outReal,), input = :volume) do p, data
            s = EFI(;
                period = get(p, :optInTimePeriod, 13),
                unstable = get(p, :unstable, 0),
            )
            (foldseries(s, data).efi,)
        end
        # MARKETFI is bar-local arithmetic on values near 1e-7.
        checkgoldens("MARKETFI"; outputs = (:outReal,), atol = 0.0) do p, data
            (foldseries(MarketFI(), data).marketfi,)
        end
        for (fn, s, out, input) in (("NVI", NVI(), :nvi, :close),
            ("PVI", PVI(), :pvi, :close), ("OBV", OBV(:close), :close_obv, :volume),
            ("PVT", PVT(), :pvt, :volume), ("VWAP", VWAP(), :vwap, :close))
            checkgoldens(fn; outputs = (:outReal,), input) do p, data
                (foldseries(s, data)[out],)
            end
        end
        checkgoldens("PVO"; outputs = (:outReal,)) do p, data
            s = PVO(; fastperiod = get(p, :optInFastPeriod, 12),
                slowperiod = get(p, :optInSlowPeriod, 26),
                matype = CausalIndicators.MATYPES[get(p, :optInMAType, 1)+1],
                unstable = get(p, :unstable, 0))
            (foldseries(s, data).pvo,)
        end
        checkgoldens("RVOL"; outputs = (:outReal,)) do p, data
            (
                foldseries(RVOL(), data; window = Bars(get(p, :optInTimePeriod, 20) + 1)).w_rvol,
            )
        end
    end

    @testset "test_per_hlcv.c AD and ADOSC rows" begin
        ref = loadref()
        runs = Dict(
            "TA_AD_TEST" => (d -> foldseries(AD(), d).ad, 0),
            "TA_ADOSC_3_10_TEST" => (d -> foldseries(ADOSC(), d).adosc, 9),
            "TA_ADOSC_5_2_TEST" =>
                (d -> foldseries(ADOSC(; fastperiod = 5, slowperiod = 2), d).adosc, 4),
        )
        n = 0
        for r in loadtable("test_per_hlcv")["tables"]["tableTest"]["rows"]
            haskey(runs, r["theFunction"]) || continue
            run, lb = runs[r["theFunction"]]
            got = tablerun(run, ref, r["startIdx"], r["endIdx"], lb)
            checkrow(got, r; out = "oneOfTheExpectedOutReal0",
                index = "oneOfTheExpectedOutRealIndex0")
            n += 1
        end
        @test n == 9
    end

    @testset "test_per_cv.c" begin
        ref = loadref()
        outs = Dict("TA_NVI_TEST" => (NVI(), :nvi), "TA_PVI_TEST" => (PVI(), :pvi),
            "TA_PVT_TEST" => (PVT(), :pvt))
        n = 0
        for r in loadtable("test_per_cv")["tables"]["tableTest"]["rows"]
            s, o = outs[r["theFunction"]]
            got = tablerun(d -> foldseries(s, d)[o], ref, r["startIdx"], r["endIdx"], 0)
            checkrow(got, r; out = "oneOfTheExpectedOutReal0",
                index = "oneOfTheExpectedOutRealIndex0")
            n += 1
        end
        @test n == 18
        # The PVT oracle at the C test's 1e-12 relative.
        pvt = foldseries(PVT(), ref).pvt
        for r in loadtable("test_per_cv")["tables"]["pvtOracle"]["rows"]
            @test pvt[r["bar"]+1] ≈ r["want"] rtol = 1e-12
        end
        # Edges: a zero previous close adds nothing to PVT and leaves NVI and PVI
        # unchanged; an overflowing NVI keeps its last finite value.
        c = [10.0, 0.0, 5.0, 6.0]
        v = [100.0, 50.0, 200.0, 100.0]
        @test foldseries(PVT(), (close = c, volume = v)).pvt ≈ [0.0, -50.0, -50.0, -30.0]
        @test foldseries(PVI(), (close = c, volume = v)).pvi == [1000.0, 1000.0, 1000.0,
            1000.0]
        @test foldseries(NVI(), (close = c, volume = v)).nvi ≈ [1000.0, 0.0, 0.0, 0.0]
        big = [1e-300, 1e300, 1e300, 2e300]
        @test foldseries(NVI(), (close = big, volume = [4.0, 3.0, 2.0, 1.0])).nvi ==
              [1000.0, 1000.0, 1000.0, 2000.0]
    end

    @testset "OBV" begin
        c = [10.0, 11.0, 11.0, 9.0, 12.0]
        v = [100.0, 20.0, 30.0, 40.0, 50.0]
        @test foldseries(OBV(:close), (close = c, volume = v)).close_obv ==
              [100.0, 120.0, 120.0, 80.0, 130.0]
        @test keys(foldseries(OBV(:close; name = :o2), (close = c, volume = v))) ==
              (:close_o2,)
    end

    @testset "test_cmf.c" begin
        ref = loadref()
        t = loadtable("test_cmf")["tables"]
        for r in t["cmfShape"]["rows"]
            got = foldseries(CMF(), ref; window = Bars(r["period"])).w_cmf
            @test findfirst(!ismissing, got) - 1 == r["begIdx"]
            @test count(!ismissing, got) == r["nbElement"]
            @test all(x -> abs(x) <= 1 + 1e-12, skipmissing(got))
        end
        # The oracle at the C test's 1e-13, and TA-Lib's own output, which it
        # pins bit for bit and the compensated sums reproduce to 1e-15.
        for (name, tol) in (("cmfOracle", 1e-13), ("cmfSelf", 1e-15))
            for r in t[name]["rows"]
                p = r["period"]
                got = foldseries(CMF(), ref; window = Bars(p)).w_cmf
                @test got[r["idx"]+p] ≈ r["value"] atol = tol
            end
        end
        cmf(h, l, c, v, p) = foldseries(CMF(), (high = h, low = l, close = c,
            volume = v); window = Bars(p)).w_cmf
        # All-zero volume gives exactly 0; a flat bar adds its volume but no flow;
        # a malformed bar (low above high) adds no flow.
        i = 0:19
        @test all(==(0), skipmissing(cmf(100.0 .+ i, 99.0 .+ i, 99.5 .+ i, zeros(20), 5)))
        v3 = [300.0, 300.0, 100.0]
        @test isequal(cmf([50.0, 50, 60], [50.0, 50, 40], [50.0, 50, 60], v3, 2),
            [missing, 0.0, 0.25])
        @test cmf([40.0, 40, 60], [50.0, 50, 40], [45.0, 45, 60], v3, 2)[3] == 0.25
        # The close at the high, the low and the middle give exactly 1, −1 and 0.
        h, l = 100.0 .+ (0:11), 90.0 .+ (0:11)
        v = 1000.0 .+ 10.0 .* (0:11)
        @test all(==(1), skipmissing(cmf(h, l, h, v, 4)))
        @test all(==(-1), skipmissing(cmf(h, l, l, v, 4)))
        @test all(==(0), skipmissing(cmf(h, l, (h .+ l) ./ 2, v, 4)))
        @test isequal(cmf(h, l, h, v, 12)[12], 1.0)
        @test all(ismissing, cmf(h, l, h, v, 13))
    end

    @testset "test_marketfi.c" begin
        ref = loadref()
        got = foldseries(MarketFI(), ref).marketfi
        for r in loadtable("test_marketfi")["tables"]["marketfiPin"]["rows"]
            @test got[r["idx"]+1] ≈ r["value"] rtol = 1e-12
        end
        # Zero volume reports 0, also with no range, and a negative range passes
        # through.
        @test foldseries(
            MarketFI(),
            (high = [2.0, 2.0, 1.0], low = [1.0, 2.0, 3.0],
                volume = [0.0, 0.0, 4.0]),
        ).marketfi == [0.0, 0.0, -0.5]
    end

    @testset "test_rvol.c" begin
        ref = loadref()
        for r in loadtable("test_rvol")["tables"]["rvolOracle"]["rows"]
            p = r["period"]
            got = foldseries(RVOL(), ref; window = Bars(p + 1)).w_rvol
            @test findfirst(!ismissing, got) - 1 == p
            @test got[r["bar"]+1] ≈ r["want"] rtol = 1e-13
        end
        # The baseline is the mean of the bars before the current one; a dead
        # window gives Inf, or NaN for a zero bar.
        rv(v, p) = foldseries(RVOL(), (; volume = v); window = Bars(p + 1)).w_rvol
        @test isequal(rv([2.0, 4.0, 6.0, 3.0], 2), [missing, missing, 2.0, 0.6])
        @test isequal(rv([0.0, 0.0, 5.0, 0.0], 2), [missing, missing, Inf, 0.0])
        @test isnan(rv([0.0, 0.0, 0.0], 2)[3])
    end

    @testset "test_vwap.c" begin
        ref = loadref()
        t = loadtable("test_vwap")["tables"]
        shapes = t["vwapShape"]["rows"]
        for (k, sh) in enumerate(shapes)
            # A TA-Lib call from startIdx anchors a new VWAP there.
            data = map(c -> c[(sh["startIdx"]+1):end], ref)
            got = foldseries(VWAP(), data).vwap
            @test length(got) == sh["nbElement"] && !any(ismissing, got)
            for name in ("vwapOracle", "vwapBitwise"), r in t[name]["rows"]
                r["shape"] == k - 1 || continue
                @test got[r["idx"]+1] ≈ r["value"] rtol = 1e-14
            end
        end
        vw(h, v) = foldseries(VWAP(), (high = h, low = h, close = h, volume = v)).vwap
        # No volume yet gives 0; a zero-volume bar repeats the value; a bar with
        # a non-finite price or volume is left out.
        @test vw([5.0, 6.0, 8.0, 9.0], [0.0, 0.0, 2.0, 0.0]) == [0.0, 0.0, 8.0, 8.0]
        @test vw([4.0, NaN, 8.0], [1.0, 5.0, 1.0]) == [4.0, 4.0, 6.0]
        @test vw([4.0, 6.0, 8.0], [1.0, Inf, 1.0]) == [4.0, 4.0, 6.0]
        # A key restarts it, the session reset.
        k = foldseries(VWAP(),
            (high = [4.0, 8.0, 2.0, 4.0], low = [4.0, 8.0, 2.0, 4.0],
                close = [4.0, 8.0, 2.0, 4.0], volume = ones(4), day = [1, 1, 2, 2]);
            key = :day)
        @test k.vwap == [4.0, 6.0, 2.0, 3.0]
    end

    @testset "EFI" begin
        # Period 1 is the raw force, from the second bar.
        c, v = [10.0, 12.0, 11.0, 11.0], [5.0, 3.0, 2.0, 7.0]
        @test isequal(foldseries(EFI(; period = 1), (close = c, volume = v)).efi,
            [missing, 6.0, -2.0, 0.0])
        # The EMA is EMA's: EFI equals EMA over the force series.
        ref = loadref()
        force = [missing; diff(ref.close) .* ref.volume[2:end]]
        want = vcat(
            missing,
            foldseries(EMA(:f; period = 13, unstable = 2),
                (f = force[2:end],)).f_ema,
        )
        @test isequal(foldseries(EFI(; unstable = 2), ref).efi, want)
    end

    @testset "PVO is PPO of the volume" begin
        ref = loadref()
        for m in (:ema, :sma, :kama)
            want = foldseries(PPO(:volume; matype = m), ref).volume_ppo
            @test isequal(foldseries(PVO(; matype = m), ref).pvo, want)
        end
    end

    @testset "AD, CMF and ADOSC agree" begin
        ref = loadref()
        out = foldseries([AD(), ADOSC(; fastperiod = 4, slowperiod = 7)], ref)
        ad = out.ad
        # ADOSC is the difference of two EMAs of the AD line seeded at its first
        # value, and CMF is a window ratio of AD's own row term.
        e(k) = accumulate((p, x) -> k * x + (1 - k) * p, ad)
        @test all(
            i -> isapprox(out.adosc[i], e(2 / 5)[i] - e(2 / 8)[i]; rtol = 1e-9,
                atol = 1e-3), 7:252)
        mfv = [i == 1 ? ad[1] : ad[i] - ad[i-1] for i in 1:252]
        cmf = foldseries(CMF(), ref; window = Bars(10)).w_cmf
        @test all(
            i -> isapprox(cmf[i],
                sum(mfv[(i-9):i]) / sum(ref.volume[(i-9):i]); atol = 1e-12), 10:252)
    end

    @testset "constructors" begin
        @test_throws ArgumentError ADOSC(; fastperiod = 1)
        @test_throws ArgumentError ADOSC(; unstable = -1)
        @test_throws ArgumentError EFI(; period = 0)
        @test_throws ArgumentError PVO(; matype = :mama)
        @test_throws ArgumentError PVO(; slowperiod = 1)
        @test_throws ArgumentError Beta(:a, :b; period = 0)
        @test keys(CausalFrames.emptyvalue(Beta(:a, :b; name = :b5))) == (:a_b_b5,)
        @test keys(CausalFrames.emptyvalue(PVO(; name = :pvo5))) == (:pvo5,)
        @test keys(CausalFrames.emptyvalue(EFI(; name = :efi2))) == (:efi2,)
        @test keys(CausalFrames.emptyvalue(ADOSC(; name = :ao))) == (:ao,)
        # AD and CMF share their money flow row term.
        ref = loadref()
        out = foldseries([AD(), CMF()], ref; window = Bars(20))
        @test keys(out) == (:w_ad, :w_cmf)
    end

    @testset "missing bars are skipped" begin
        r = loadref()
        n = 80
        base = map(c -> c[1:n], r)
        withgaps = map(
            c -> (v = Union{Missing,Float64}[]; foreach(x -> push!(v, missing, x), c); v),
            base,
        )
        for s in PLAIN_S4
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
        for s in PLAIN_S4
            checkstreaming(s, t)
        end
        for s in (AD(), VWAP())
            checkstreaming(s, t)
        end
        for (s, w) in ((CMF(), 20), (MarketFI(), 3), (RVOL(), 21), (AD(), 5),
            (VWAP(), 10), (LinearReg(:close), 14), (LinearRegAngle(:close), 5),
            (TSF(:close), 14), (PercentRank100(:close), 11),
            ([LinearRegSlope(:close), LinearRegIntercept(:close), WMA(:close)], 9))
            checkstreaming(s, t; window = Bars(w), timewindow = w - 1)
        end
    end

    @testset "zero allocations" begin
        rng = Random.MersenneTwister(3)
        mkrow(x) = (time = 1, open = x, high = x + 1, low = x - 1, close = x,
            volume = 1e5 + 1e3 * x)
        for s in PLAIN_S4
            st = CausalFrames.fresh(s, S2_INTYPES)
            for x in 100.0 .+ randn(rng, 60)
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
end
