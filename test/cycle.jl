# S6, the Hilbert-transform cycle family (HT_DCPERIOD, HT_DCPHASE, HT_PHASOR,
# HT_SINE, HT_TRENDLINE, HT_TRENDMODE) and MAMA, against TA-Lib's goldens and
# tables, and `:mama` through MA and BBANDS.

using CausalIndicators: HilbertKernel, MAMAKernel

# Each HT function's constructor, golden outputs and TA-Lib lookback.
const HT_FNS = [
    ("HT_DCPERIOD", HTDCPeriod, (:outReal,), 32),
    ("HT_DCPHASE", HTDCPhase, (:outReal,), 63),
    ("HT_PHASOR", HTPhasor, (:outInPhase, :outQuadrature), 32),
    ("HT_SINE", HTSine, (:outSine, :outLeadSine), 63),
    ("HT_TRENDLINE", HTTrendline, (:outReal,), 63),
    ("HT_TRENDMODE", HTTrendMode, (:outInteger,), 63),
]

# One of each S6 state, for the missing, streaming, allocation and JET checks.
const PLAIN_S6 = [
    HTDCPeriod(:close), HTDCPhase(:close), HTPhasor(:close; unstable = 1),
    HTSine(:close), HTTrendline(:close), HTTrendMode(:close; unstable = 2),
    MAMA(:close; fastlimit = 0.6, slowlimit = 0.1),
    MA(:close; matype = :mama), BollingerBands(:close; matype = :mama, period = 40),
]

# TA-Lib's tables run the cycle family and MAMA on the median price.
medprice(r) = (close = (r.high .+ r.low) ./ 2,)

@testset "cycle" begin
    @testset "goldens" begin
        for (fn, ctor, outs, _) in HT_FNS
            checkgoldens(fn; outputs = outs) do p, data
                Tuple(foldseries(ctor(:close; unstable = get(p, :unstable, 0)), data))
            end
        end
        checkgoldens("MAMA"; outputs = (:outMAMA, :outFAMA)) do p, data
            s = MAMA(:close; fastlimit = get(p, :optInFastLimit, 0.5),
                slowlimit = get(p, :optInSlowLimit, 0.05),
                unstable = get(p, :unstable, 0))
            Tuple(foldseries(s, data))
        end
    end

    @testset "test_1in_1out.c and test_1in_2out.c rows" begin
        data = medprice(loadref())
        byid = Dict("TA_$(fn)_TEST" => (ctor, lb) for (fn, ctor, _, lb) in HT_FNS)
        n = 0
        for file in ("test_1in_1out", "test_1in_2out")
            for r in loadtable(file)["tables"]["tableTest"]["rows"]
                haskey(byid, r["theFunction"]) || continue
                ctor, lb = byid[r["theFunction"]]
                u = r["unstablePeriod"]
                s0, e0 = r["startIdx"], r["endIdx"]
                outs = 0:(file=="test_1in_1out" ? 0 : 1)
                # test_1in_2out.c's first HT_PHASOR quadrature, 5.2143, is
                # 2.4e-4 off TA-Lib's own output (5.21454, which the goldens
                # match). TA-Lib checks its literals at TA_REAL_EQ(…, 0.01),
                # so this one is held to that.
                stale =
                    r["theFunction"] == "TA_HT_PHASOR_TEST" &&
                    r["oneOfTheExpectedOutReal1"] == 5.2143
                for k in outs
                    got = tablerun(data, s0, e0, lb + u) do d
                        collect(foldseries(ctor(:close; unstable = u), d)[k+1])
                    end
                    checkrow(got, r; out = "oneOfTheExpectedOutReal$k",
                        index = "oneOfTheExpectedOutRealIndex$k",
                        atol = stale && k == 1 ? 0.01 : nothing)
                end
                n += 1
            end
        end
        @test n == 12 + 11
    end

    @testset "test_ma.c MAMA rows" begin
        data = medprice(loadref())
        n = 0
        for r in loadtable("test_ma")["tables"]["tableTest"]["rows"]
            get(r, "optInMAType_1", "") == "TA_MAType_MAMA" || continue
            u = r["unstablePeriod"]
            s0, e0 = r["startIdx"], r["endIdx"]
            got = tablerun(data, s0, e0, 32 + u) do d
                if r["id"] == "TA_ANY_MA_TEST"
                    s = MA(:close; matype = :mama, period = r["optInTimePeriod"], unstable = u)
                    foldseries(s, d).close_ma
                else
                    o = foldseries(MAMA(:close; unstable = u), d)
                    r["id"] == "TA_MAMA_TEST" ? o.close_mama_mama : o.close_mama_fama
                end
            end
            checkrow(got, r)
            n += 1
        end
        @test n == 6
    end

    @testset "test_bbands.c MAMA alignment" begin
        close = loadref().close
        mama = foldseries(MA(:close; matype = :mama), (; close)).close_ma
        for p in (20, 33, 34, 40, 50, 100)
            bb = foldseries(BollingerBands(:close; matype = :mama, period = p), (; close))
            sd = foldseries(StdDev(:close), (; close); window = Bars(p)).w_close_stddev
            lb = max(32, p - 1)
            @test findfirst(!ismissing, bb.close_bbands_middleband) - 1 == lb
            @test all(ismissing, bb.close_bbands_upperband[1:lb])
            i = (lb+1):length(close)
            @test isequal(bb.close_bbands_middleband[i], mama[i])
            @test bb.close_bbands_upperband[i] ≈ mama[i] .+ 2 .* sd[i]
            @test bb.close_bbands_lowerband[i] ≈ mama[i] .- 2 .* sd[i]
        end
    end

    @testset "MAMA's recurrences" begin
        x = loadgdata().close
        for (fast, slow) in ((0.5, 0.05), (0.9, 0.1))
            o = foldseries(MAMA(:close; fastlimit = fast, slowlimit = slow), (close = x,))
            m, f = o.close_mama_mama, o.close_mama_fama
            for t in 34:length(x)
                # MAMA is an EMA of the price whose factor stays within the
                # limits, and FAMA an EMA of MAMA at half that factor.
                d = x[t] - m[t-1]
                abs(d) > 1e-6 * abs(x[t]) || continue
                α = (m[t] - m[t-1]) / d
                @test slow - 1e-9 <= α <= fast + 1e-9
                @test f[t] ≈ (α / 2) * m[t] + (1 - α / 2) * f[t-1] rtol = 1e-9
            end
        end
        # Equal limits fix the factor: a plain EMA, seeded at 0 on bar 13.
        o = foldseries(MAMA(:close; fastlimit = 0.2, slowlimit = 0.2), (close = x,))
        m = 0.0
        want = map(enumerate(x)) do (t, v)
            t > 12 && (m = 0.2 * v + 0.8 * m)
            t > 32 ? m : missing
        end
        @test isapprox(collect(skipmissing(o.close_mama_mama)),
            collect(skipmissing(want)); rtol = 1e-12)
        # TA_MA's MAMA is the indicator's MAMA line; period 1 copies.
        @test isequal(foldseries(MA(:close; matype = :mama), (close = x,)).close_ma,
            foldseries(MAMA(:close), (close = x,)).close_mama_mama)
        @test foldseries(MA(:close; matype = :mama, period = 1), (close = x,)).close_ma == x
    end

    @testset "the family's identities" begin
        x = loadgdata().close
        ph = foldseries(HTDCPhase(:close), (close = x,)).close_htdcphase
        sn = foldseries(HTSine(:close), (close = x,))
        i = findall(!ismissing, ph)
        @test sn.close_htsine_sine[i] ≈ sind.(ph[i])
        @test sn.close_htsine_leadsine[i] ≈ sind.(ph[i] .+ 45)
        @test all(<=(315), skipmissing(ph))
        tm = foldseries(HTTrendMode(:close), (close = x,)).close_httrendmode
        @test eltype(tm) == Union{Missing,Int}
        @test Set(skipmissing(tm)) == Set([0, 1])
        dc = collect(
            skipmissing(foldseries(HTDCPeriod(:close), (close = x,)).close_htdcperiod),
        )
        @test all(v -> 6 <= v <= 50, dc[100:end])
    end

    @testset "unstable only delays" begin
        x = loadref().close
        for (_, ctor, _, lb) in HT_FNS
            base = foldseries(ctor(:close), (close = x,))
            late = foldseries(ctor(:close; unstable = 7), (close = x,))
            for o in keys(base)
                @test all(ismissing, late[o][1:(lb+7)])
                @test isequal(late[o][(lb+8):end], base[o][(lb+8):end])
            end
        end
    end

    @testset "a non-finite input poisons the state" begin
        x = loadgdata().close[1:300]
        x[150] = NaN
        for (_, ctor, _, _) in HT_FNS
            o = foldseries(ctor(:close), (close = x,))
            for v in o
                if eltype(v) == Union{Missing,Int}
                    @test all(==(1), v[150:end])
                else
                    @test all(isnan, v[150:end])
                    @test all(isfinite, skipmissing(v[1:149]))
                end
            end
        end
        o = foldseries(MAMA(:close), (close = x,))
        @test all(isnan, o.close_mama_mama[150:end])
        @test all(isnan, o.close_mama_fama[150:end])
    end

    @testset "missing bars are skipped" begin
        base = map(c -> c[1:120], loadref())
        withgaps = map(
            c -> (v = Union{Missing,Float64}[]; foreach(x -> push!(v, missing, x), c); v),
            base,
        )
        for s in PLAIN_S6
            want = foldseries(s, base)
            got = foldseries(s, withgaps)
            for o in keys(want)
                @test all(ismissing, got[o][1:2:end])
                @test isequal(got[o][2:2:end], want[o])
            end
        end
    end

    @testset "streaming properties" begin
        t = map(c -> c[1:150], loadref())
        for s in PLAIN_S6
            checkstreaming(s, t)
        end
    end

    @testset "zero allocations" begin
        rng = Random.MersenneTwister(6)
        mkrow(x) = (time = 1, open = x, high = x + 1, low = x - 1, close = x, volume = 1e5)
        for s in PLAIN_S6
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
        @test keys(CausalFrames.emptyvalue(HTPhasor(:close))) ==
              (:close_htphasor_inphase, :close_htphasor_quadrature)
        @test keys(CausalFrames.emptyvalue(HTSine(:close; name = :s))) ==
              (:close_s_sine, :close_s_leadsine)
        @test keys(CausalFrames.emptyvalue(MAMA(:close))) ==
              (:close_mama_mama, :close_mama_fama)
        @test keys(CausalFrames.emptyvalue(HTTrendMode(:close))) == (:close_httrendmode,)
        @test_throws ArgumentError MAMA(:x; fastlimit = 1.0)
        @test_throws ArgumentError MAMA(:x; slowlimit = 0.0)
        for ctor in
            (HTDCPeriod, HTDCPhase, HTPhasor, HTSine, HTTrendline, HTTrendMode, MAMA)
            @test_throws ArgumentError ctor(:x; unstable = -1)
        end
    end
end
