# S3 volatility indicators: the structured TRange and ADR, and the plain ATR,
# NATR, CVI, MassIndex and RVI, against TA-Lib's goldens, tables and oracles.

using CausalIndicators: ATRKernel, DMKernel, dmsums

# One of each plain S3 state, for the missing, streaming, allocation and JET
# checks.
const PLAIN_S3 = [
    PlusDM(; period = 5), MinusDM(; period = 1), PlusDI(; period = 5),
    MinusDI(; period = 1), DX(; period = 4), ADX(; period = 4, unstable = 1),
    ADXR(; period = 4), ATR(; period = 5), NATR(; period = 5, unstable = 2),
    CVI(; period = 4, rocperiod = 3), MassIndex(; fastperiod = 3, slowperiod = 5),
    RVI(:close; period = 4, stddevperiod = 5),
    BollingerBands(:close; matype = :kama, period = 6, nbdevdn = 1.5),
    KeltnerChannels(; period = 6, atrperiod = 4), SAR(), SARExt(; startvalue = -100),
    SuperTrend(; period = 5, unstable = 1),
]
const S3_INTYPES = (open = Float64, high = Float64, low = Float64,
    close = Union{Missing,Float64}, volume = Float64)

# A TA-Lib oracle value: `rtol`/`atol` as the C test states them.
oracle(got, want; rtol = 1e-12, atol = 1e-12) = isapprox(got, want; rtol, atol)

@testset "volatility" begin
    @testset "goldens" begin
        checkgoldens("TRANGE"; outputs = (:outReal,)) do p, data
            (foldseries(TRange(), data; window = Bars(2)).w_trange,)
        end
        for (fn, ctor, out) in (("ATR", ATR, :atr), ("NATR", NATR, :natr))
            checkgoldens(fn; outputs = (:outReal,)) do p, data
                s = ctor(; period = get(p, :optInTimePeriod, 14),
                    unstable = get(p, :unstable, 0))
                (foldseries(s, data)[out],)
            end
        end
        checkgoldens("ADR"; accepts = WINDOW, outputs = (:outReal,)) do p, data
            (foldseries(ADR(), data; window = Bars(get(p, :optInTimePeriod, 14))).w_adr,)
        end
        checkgoldens("CVI"; outputs = (:outReal,)) do p, data
            s = CVI(; period = get(p, :optInTimePeriod, 10),
                rocperiod = get(p, :optInROCPeriod, 10), unstable = get(p, :unstable, 0))
            (foldseries(s, data).cvi,)
        end
        checkgoldens("MASSI"; outputs = (:outReal,)) do p, data
            s = MassIndex(; fastperiod = get(p, :optInFastPeriod, 9),
                slowperiod = get(p, :optInSlowPeriod, 25),
                unstable = get(p, :unstable, 0))
            (foldseries(s, data).massi,)
        end
        checkgoldens("RVI"; outputs = (:outReal,)) do p, data
            s = RVI(:close; period = get(p, :optInTimePeriod, 14),
                stddevperiod = get(p, :optInStdDevPeriod, 10),
                unstable = get(p, :unstable, 0))
            (foldseries(s, data).close_rvi,)
        end
    end

    @testset "test_trange.c table rows" begin
        ref = loadref()
        n = 0
        for r in loadtable("test_trange")["tables"]["tableTest"]["rows"]
            p, u = r["optInTimePeriod"], r["unstablePeriod"]
            run, lb = if r["doAverage"] == 0
                d -> foldseries(TRange(), d; window = Bars(2)).w_trange, 1
            else
                d -> foldseries(ATR(; period = p, unstable = u), d).atr, p + u
            end
            got = tablerun(run, ref, r["startIdx"], r["endIdx"], lb)
            checkrow(got, r)
            n += 1
        end
        @test n >= 17
    end

    @testset "test_per_hlc.c NATR rows" begin
        ref = loadref()
        n = 0
        for r in loadtable("test_per_hlc")["tables"]["tableTest"]["rows"]
            r["theFunction"] == "TA_NATR_TEST" || continue
            p = r["optInTimePeriod1"]
            got = tablerun(d -> foldseries(NATR(; period = p), d).natr, ref, r["startIdx"],
                r["endIdx"], p)
            checkrow(got, r; out = "oneOfTheExpectedOutReal0",
                index = "oneOfTheExpectedOutRealIndex0")
            n += 1
        end
        @test n >= 3
    end

    @testset "ATR is RMA of TRange (test_rma.c)" begin
        ref = loadref()
        tr = foldseries(TRange(), ref; window = Bars(2)).w_trange
        for p in (1, 2, 3, 14, 30, 100)
            @test isequal(foldseries(ATR(; period = p), ref).atr,
                foldseries(RMA(:tr; period = p), (; tr)).tr_rma)
        end
    end

    @testset "period 1 (test_period_boundary.c)" begin
        ref = loadref()
        tr = foldseries(TRange(), ref; window = Bars(2)).w_trange
        # NATR(1) is not normalized: TA-Lib's period-1 rule.
        @test isequal(foldseries(ATR(; period = 1), ref).atr, tr)
        @test isequal(foldseries(NATR(; period = 1), ref).natr, tr)
    end

    @testset "test_quote_unit.c NATR at 2^-60" begin
        scaled = map(c -> c .* ldexp(1.0, -60), loadref())
        @test foldseries(NATR(), scaled).natr[252] ≈ 3.02290672213603 rtol = 1e-12
    end

    @testset "test_adr.c oracles and edges" begin
        t = loadtable("test_adr")
        a = t["arrays"]
        kand = (high = Float64.(a["adrKandHigh"]["values"]),
            low = Float64.(a["adrKandLow"]["values"]))
        got = foldseries(ADR(), kand; window = Bars(3)).w_adr
        @test count(!ismissing, got) == length(a["adrKandExp"]["values"])
        @test all(oracle.(got[3:end], a["adrKandExp"]["values"]; atol = 1e-9))
        ref = loadref()
        for r in t["tables"]["adrSrefOracle"]["rows"]
            got = foldseries(ADR(), ref; window = Bars(r["period"])).w_adr
            @test oracle(got[r["bar"]+1], r["want"]; atol = 1e-14)
        end
        @test foldseries(ADR(), ref; window = Bars(1)).w_adr == ref.high .- ref.low
        flat = foldseries(ADR(), (high = fill(5.0, 20), low = fill(5.0, 20));
            window = Bars(4)).w_adr
        @test all(x -> x === 0.0, flat[4:end])
        @test foldseries(ADR(), (high = [1.0, 1.0], low = [1.5, 1.5]);
            window = Bars(2)).w_adr[2] === -0.5
    end

    @testset "test_cvi.c oracles and edges" begin
        ref = loadref()
        for r in loadtable("test_cvi")["tables"]["cviOracle"]["rows"]
            p = r["period"]
            got = foldseries(CVI(; period = p, rocperiod = p), ref).cvi
            @test oracle(got[r["bar"]+1], r["want"])
        end
        # The decay at n = 3: a range of 8 for 10 bars, then none.
        for m in 1:5
            h = [i < 10 ? 108.0 : 100.0 for i in 0:39]
            got = foldseries(
                CVI(; period = 3, rocperiod = m),
                (high = h, low = fill(100.0, 40)),
            ).cvi
            for t in (2+m):39
                want =
                    t <= 9 ? 0.0 :
                    t <= 9 + m ? 100 * ((2.0^(12 - t) - 8) / 8) :
                    100 * ((1 - 2.0^m) / 2.0^m)
                @test got[t+1] == want
            end
        end
        # No range at all gives exactly 0.
        flat = (high = fill(50.0, 40), low = fill(50.0, 40))
        @test all(
            n -> all(
                m -> all(==(0.0),
                    skipmissing(foldseries(CVI(; period = n, rocperiod = m), flat).cvi)),
                1:12),
            2:12)
    end

    @testset "test_massi.c oracles and edges" begin
        ref = loadref()
        for r in loadtable("test_massi")["tables"]["massiOracle"]["rows"]
            got = foldseries(MassIndex(; fastperiod = r["fast"], slowperiod = r["slow"]),
                ref).massi
            @test oracle(got[r["bar"]+1], r["want"])
        end
        n = 80
        for (f, s) in ((2, 2), (9, 25), (3, 30)), rng in (0.0, 8.0)
            d = (high = fill(100.0 + rng, n), low = fill(100.0, n))
            got = foldseries(MassIndex(; fastperiod = f, slowperiod = s), d).massi
            @test findfirst(!ismissing, got) - 1 == 2(f - 1) + s - 1
            @test all(==(s), skipmissing(got))
        end
        # Scaling by a power of two leaves it bit-identical.
        r = [1 + 0.5 * (i % 3) for i in 0:(n-1)]
        a = foldseries(MassIndex(), (high = r, low = zeros(n))).massi
        b = foldseries(MassIndex(), (high = r .* ldexp(1.0, -100), low = zeros(n))).massi
        @test isequal(a, b) && all(!=(25), skipmissing(a))
    end

    @testset "test_rvi.c oracles and edges" begin
        ref = loadref()
        t = loadtable("test_rvi")["tables"]
        for r in t["rviTradingSignals"]["rows"]
            got =
                foldseries(RVI(:close; period = r["period"], stddevperiod = r["sdPeriod"]),
                    ref).close_rvi
            @test oracle(got[r["bar"]+1], r["want"]; rtol = 1e-10)
        end
        # pandas-ta passes one length to both windows; its converged tail.
        for r in t["rviPandas"]["rows"]
            L = r["length"]
            got = foldseries(RVI(:close; period = L, stddevperiod = L), ref).close_rvi
            @test oracle(got[r["bar"]+1], r["want"]; rtol = 1e-9, atol = 1e-9)
        end
        # Period 1 takes only 0, 50 and 100; the corpus's one tie is bar 101.
        got = foldseries(RVI(:close; period = 1, stddevperiod = 10), ref).close_rvi
        @test findfirst(!ismissing, got) - 1 == 9
        v = collect(skipmissing(got))
        @test length(v) == 243
        @test count(==(0), v) == 123 && count(==(100), v) == 119
        @test findall(isequal(50.0), got) == [102]
        # A flat series gives exactly 50.
        flat = (; x = fill(42.0, 60))
        @test all(
            sd -> all(
                n -> all(==(50.0),
                    skipmissing(
                        foldseries(RVI(:x; period = n, stddevperiod = sd),
                            flat).x_rvi,
                    )), 1:20), 2:20)
    end

    @testset "constructors" begin
        @test keys(CausalFrames.emptyvalue(ATR(; name = :atr7))) == (:atr7,)
        @test keys(CausalFrames.emptyvalue(RVI(:close))) == (:close_rvi,)
        @test keys(CausalFrames.emptyvalue(TRange())) == (:trange,)
        @test_throws ArgumentError ATR(; period = 0)
        @test_throws ArgumentError NATR(; unstable = -1)
        @test_throws ArgumentError CVI(; period = 1)
        @test_throws ArgumentError CVI(; rocperiod = 0)
        @test_throws ArgumentError MassIndex(; slowperiod = 1)
        @test_throws ArgumentError RVI(:x; stddevperiod = 1)
        @test_throws ArgumentError RVI(:x; period = 0)
    end
end

@testset "S3 plain and structured properties" begin
    @testset "kernels" begin
        ref = loadref()
        k = ATRKernel(Float64, 5)
        for i in 1:30
            step!(k, ref.high[i], ref.low[i], ref.close[i])
        end
        @test nseen(k) == 30 && lookback(k) == 5
        @test current(k) == foldseries(ATR(; period = 5), map(c->c[1:30], ref)).atr[30]
        d = DMKernel(Float64, 4)
        @test ismissing(step!(d, 2.0, 1.0, 1.5))
        @test lookback(d) == 3
        # An up move wins, a tie gives neither, a down move wins.
        foreach(b -> step!(d, b...), ((3.0, 1.5, 2.0), (3.5, 1.0, 2.0), (3.5, 0.5, 1.0)))
        @test dmsums(d) == (1.0, 0.5, 1.5 + 2.5 + 3.0)
    end

    @testset "missing bars are skipped" begin
        r = loadref()
        n = 80
        base = map(c -> c[1:n], r)
        withgaps = map(
            c -> (v = Union{Missing,Float64}[]; foreach(x -> push!(v, missing, x), c); v),
            base,
        )
        for s in PLAIN_S3
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
        for s in PLAIN_S3
            checkstreaming(s, t)
        end
        for (s, w) in ((TRange(), 2), (Donchian(), 20), (AccBands(), 20), (ADR(), 14),
            (StdDev(:close; nbdev = 2), 5), (BollingerBands(:close; nbdevup = 1), 20))
            checkstreaming(s, t; window = Bars(w), timewindow = w - 1)
        end
    end

    @testset "zero allocations" begin
        rng = Random.MersenneTwister(3)
        mkrow(x) = (time = 1, open = x, high = x + 1, low = x - 1, close = x, volume = 1e5)
        for s in PLAIN_S3
            st = CausalFrames.fresh(s, S3_INTYPES)
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
