# S5, the TA-Lib 0.8 additions: the structured QStick, IMI and FOSC, and the
# plain AC, AO, CMOU, Coppock, DPO, ER, ERI, Fractal, KDJ, SMI, TSI, VHF, Vortex,
# WAD and HeikinAshi, against TA-Lib's goldens, tables and oracles.

using CausalIndicators: ERKernel

# One of each plain S5 state, for the missing, streaming, allocation and JET
# checks.
const PLAIN_S5 = [
    AO(; fastperiod = 3, slowperiod = 7),
    AC(; fastperiod = 3, slowperiod = 7,
        signalperiod = 3), CMOU(:close; period = 5), ER(:close; period = 5),
    VHF(:close; period = 5), Vortex(; period = 5), DPO(:close; period = 6),
    Coppock(:close; wmaperiod = 4, roc1period = 3, roc2period = 5),
    ERI(; period = 5, unstable = 1), TSI(:close; firstperiod = 5, secondperiod = 3),
    SMI(; period = 4, fastperiod = 2, slowperiod = 5, signalperiod = 3, unstable = 1),
    KDJ(; fastkperiod = 5), Fractal(; leftbars = 2, rightbars = 3), WAD(),
    HeikinAshi(; unstable = 2),
]

# The `n`-bar values of a book vector, a TA-Lib table's input and output arrays.
tablearray(t, name) = Float64.(t["arrays"][name]["values"])

@testset "additions" begin
    @testset "goldens" begin
        checkgoldens("AC"; outputs = (:outReal,)) do p, data
            s = AC(; fastperiod = get(p, :optInFastPeriod, 5),
                slowperiod = get(p, :optInSlowPeriod, 34),
                signalperiod = get(p, :optInSignalPeriod, 5))
            (foldseries(s, data).ac,)
        end
        checkgoldens("AO"; outputs = (:outReal,)) do p, data
            s = AO(; fastperiod = get(p, :optInFastPeriod, 5),
                slowperiod = get(p, :optInSlowPeriod, 34))
            (foldseries(s, data).ao,)
        end
        checkgoldens("CMOU"; outputs = (:outReal,), atol = 1e-9) do p, data
            (
                foldseries(CMOU(:close; period = get(p, :optInTimePeriod, 14)), data).close_cmou,
            )
        end
        checkgoldens("COPPOCK"; outputs = (:outReal,), atol = 1e-9) do p, data
            s = Coppock(:close; wmaperiod = get(p, :optInWMAPeriod, 10),
                roc1period = get(p, :optInROC1Period, 11),
                roc2period = get(p, :optInROC2Period, 14))
            (foldseries(s, data).close_coppock,)
        end
        checkgoldens("DPO"; outputs = (:outReal,)) do p, data
            (
                foldseries(DPO(:close; period = get(p, :optInTimePeriod, 20)), data).close_dpo,
            )
        end
        checkgoldens("ER"; outputs = (:outReal,), atol = 1e-12) do p, data
            (foldseries(ER(:close; period = get(p, :optInTimePeriod, 10)), data).close_er,)
        end
        checkgoldens("ERI"; outputs = (:outBullPower, :outBearPower)) do p, data
            s = ERI(;
                period = get(p, :optInTimePeriod, 13),
                unstable = get(p, :unstable, 0),
            )
            out = foldseries(s, data)
            (out.eri_bullpower, out.eri_bearpower)
        end
        # FOSC is a percentage of a cancellation, the close less its forecast.
        checkgoldens("FOSC"; outputs = (:outReal,), atol = 1e-9) do p, data
            n = get(p, :optInTimePeriod, 5)
            (foldseries(FOSC(:close), data; window = Bars(n + 1)).w_close_fosc,)
        end
        checkgoldens("FRACTAL"; outputs = (:outSwingHigh, :outSwingLow)) do p, data
            s = Fractal(; leftbars = get(p, :optInLeftBars, 2),
                rightbars = get(p, :optInRightBars, 2))
            out = foldseries(s, data)
            (out.fractal_swinghigh, out.fractal_swinglow)
        end
        checkgoldens(
            "HA";
            outputs = (:outHAOpen, :outHAHigh, :outHALow, :outHAClose),
        ) do p,
        data
            out = foldseries(HeikinAshi(; unstable = get(p, :unstable, 0)), data)
            (out.ha_haopen, out.ha_hahigh, out.ha_halow, out.ha_haclose)
        end
        checkgoldens("IMI"; outputs = (:outReal,), atol = 1e-9) do p, data
            (foldseries(IMI(), data; window = Bars(get(p, :optInTimePeriod, 14))).w_imi,)
        end
        checkgoldens("KDJ"; outputs = (:outK, :outD, :outJ), atol = 1e-9) do p, data
            s = KDJ(; fastkperiod = get(p, :optInFastK_Period, 9),
                slowkperiod = get(p, :optInSlowK_Period, 3),
                slowkmatype = MATYPE_CODES[get(p, :optInSlowK_MAType, 13)],
                slowdperiod = get(p, :optInSlowD_Period, 3),
                slowdmatype = MATYPE_CODES[get(p, :optInSlowD_MAType, 13)],
                unstable = get(p, :unstable, 0))
            out = foldseries(s, data)
            (out.kdj_k, out.kdj_d, out.kdj_j)
        end
        checkgoldens("QSTICK"; outputs = (:outReal,)) do p, data
            (
                foldseries(QStick(), data; window = Bars(get(p, :optInTimePeriod, 10))).w_qstick,
            )
        end
        checkgoldens("SMI"; outputs = (:outSMI, :outSMISignal), atol = 1e-9) do p, data
            s = SMI(; period = get(p, :optInTimePeriod, 13),
                fastperiod = get(p, :optInFastPeriod, 2),
                slowperiod = get(p, :optInSlowPeriod, 25),
                signalperiod = get(p, :optInSignalPeriod, 9),
                unstable = get(p, :unstable, 0))
            out = foldseries(s, data)
            (out.smi_smi, out.smi_smisignal)
        end
        checkgoldens("TSI"; outputs = (:outReal,), atol = 1e-9) do p, data
            s = TSI(:close; firstperiod = get(p, :optInFirstPeriod, 25),
                secondperiod = get(p, :optInSecondPeriod, 13),
                unstable = get(p, :unstable, 0))
            (foldseries(s, data).close_tsi,)
        end
        checkgoldens("VHF"; outputs = (:outReal,), atol = 1e-12) do p, data
            (
                foldseries(VHF(:close; period = get(p, :optInTimePeriod, 28)), data).close_vhf,
            )
        end
        checkgoldens("VORTEX"; outputs = (:outPlusVI, :outMinusVI), atol = 1e-12) do p, data
            out = foldseries(Vortex(; period = get(p, :optInTimePeriod, 14)), data)
            (out.vortex_plusvi, out.vortex_minusvi)
        end
        checkgoldens("WAD"; outputs = (:outReal,)) do p, data
            (foldseries(WAD(), data).wad,)
        end
    end

    @testset "test_cmou.c" begin
        ref = loadref()
        got = foldseries(CMOU(:close), ref).close_cmou
        @test findfirst(!ismissing, got) == 15 && count(!ismissing, got) == 238
        # The Tulip/pandas oracle at the C test's 1e-12 relative.
        for (i, want) in ((0, -1.7053206002728516), (1, -7.189072609633359),
            (56, 21.50968603874415), (113, 57.38636363636365),
            (170, -25.802752293577985), (237, -8.07719799857037))
            @test got[15+i] ≈ want rtol = 1e-12
        end
        cmou(x, p) = foldseries(CMOU(:close; period = p), (close = x,)).close_cmou
        @test all(==(100.0), cmou(100.0 .+ 1.5 .* (0:19), 5)[6:end])
        @test all(==(-100.0), cmou(100.0 .- 1.5 .* (0:19), 5)[6:end])
        @test all(x -> x === 0.0, cmou(fill(42.0, 20), 5)[6:end])
        @test cmou([10.0, 11.0, 9.0, 12.0, 12.0, 8.0], 3)[4:6] ≈
              [100 * 2 / 6, 100 * 1 / 5, 100 * -1 / 7] atol = 1e-12
        # The empty window: a random walk with a spike, then a flat tail, gives
        # exactly 0 wherever the whole window is flat, whatever residue the
        # sliding sums held.
        n, flat = 260, 140
        walk = cumprod(1.0 .+ 0.02 .* lcgsym(0x2530C303, flat))
        checks = 0
        for spike in (1e1, 1e3, 1e5), bar in (40, 60)
            x = 100.0 .* [walk; fill(walk[end], n - flat)]
            x[bar+1] *= spike
            for p in 2:30
                out = cmou(x, p)
                for i in (flat+p+1):n
                    @test out[i] === 0.0
                    checks += 1
                end
            end
        end
        @test checks == 18096
        # The [−100, 100] range at a 2^-60 quote, and the quote-unit oracle.
        scaled = map(c -> c .* ldexp(1.0, -60), ref)
        q = foldseries(CMOU(:close), scaled).close_cmou
        @test all(x -> -100 <= x <= 100, skipmissing(q))
        @test q[252] ≈ -8.07719799857037 rtol = 1e-12
    end

    @testset "test_dpo.c" begin
        t = loadtable("test_dpo")
        ref = loadref()
        for r in t["tables"]["dpoOracle"]["rows"]
            got = foldseries(DPO(:close; period = r["period"]), ref).close_dpo[r["bar"]+1]
            for want in (r["tulip"], r["pandas"])
                @test isapprox(got, want; rtol = 1e-12, atol = 1e-12)
            end
        end
        for r in t["tables"]["dpoBookVectors"]["rows"]
            x, want = tablearray(t, r["in"]), tablearray(t, r["out"])
            got = foldseries(DPO(:close; period = r["period"]), (close = x,)).close_dpo
            @test count(!ismissing, got) == r["nbOut"]
            @test all(
                abs.(got[(end-r["nbOut"]+1):end] .- want) .<=
                0.5 * 10.0^-r["decimals"] + 1e-12,
            )
        end
        # Both arms of the lookback `max(period − 1, period ÷ 2 + 1)`, and the
        # exact constants of a line, `in[i] = 64 + i/2`.
        x = 64.0 .+ (0:99) ./ 2
        for p in t["arrays"]["dpoPeriods"]["values"]
            got = foldseries(DPO(:close; period = p), (close = x,)).close_dpo
            lb = max(p - 1, p ÷ 2 + 1)
            @test findfirst(!ismissing, got) == min(lb + 1, length(x) + 1) ||
                  all(ismissing, got)
            lb < length(x) || continue
            @test all(skipmissing(got) .≈ (p - 1) / 4 - (p ÷ 2 + 1) / 2)
        end
    end

    @testset "test_fosc.c" begin
        t = loadtable("test_fosc")
        fosc(x, p) =
            foldseries(FOSC(:close), (close = x,); window = Bars(p + 1)).w_close_fosc
        for (inn, exp, tol) in (("foscAtozIn", "foscAtozExp", 5e-5),
            ("foscUntestIn", "foscUntestExp", 5e-4))
            want = tablearray(t, exp)
            got = fosc(tablearray(t, inn), 5)
            @test count(!ismissing, got) == length(want)
            @test all(abs.(got[(end-length(want)+1):end] .- want) .<= tol)
        end
        # The Tulip and trading-signals oracles at the C test's 1e-10 absolute;
        # `i` indexes the output, which starts at bar `period`.
        ref = loadref()
        oracle = (
            (5, 0, -0.7820343461030329, -0.7820343461030179),
            (5, 1, -1.8539932994703714, -1.853993299470433),
            (5, 2, -0.08948787061992905, -0.08948787061999033),
            (5, 41, -1.6147200349956117, -1.6147200349956117),
            (5, 82, 1.7742304349816402, 1.7742304349814584),
            (5, 123, 0.4492537313445379, 0.44925373134328644),
            (5, 164, 1.1997516684801903, 1.1997516684774112),
            (5, 205, -3.378335618597047, -3.3783356186056355),
            (5, 245, -1.1429885057352827, -1.1429885057470697),
            (5, 246, -1.083711875393563, -1.0837118754054988),
            (14, 0, -3.742120516845753, -3.7421205168458),
            (14, 1, -0.38721715713582444, -0.38721715713582444),
            (14, 2, -4.3815530552113335, -4.381553055211222),
            (14, 39, -7.978680002632227, -7.97868000263209),
            (14, 79, -0.9065818877139841, -0.9065818877139483),
            (14, 119, -3.4280296770211796, -3.428029677020908),
            (14, 158, 3.2936043548283656, 3.293604354828829),
            (14, 198, 0.7227591107003658, 0.7227591107014678),
            (14, 236, 0.055475558922640715, 0.05547555892377758),
            (14, 237, -1.2222689704856493, -1.2222689704843979),
            (23, 0, -6.611933901614386, -6.611933901614402),
            (23, 1, -4.002934841778904, -4.002934841778972),
            (23, 2, -5.330030418389548, -5.3300304183893905),
            (23, 38, 1.054733034099452, 1.0547330340992593),
            (23, 76, -1.0553568814438217, -1.0553568814438579),
            (23, 114, -7.773110273616304, -7.773110273615753),
            (23, 152, 1.211091387632196, 1.2110913876331555),
            (23, 190, 2.7474844798682048, 2.747484479870267),
            (23, 227, -1.782054427334196, -1.7820544273318308),
            (23, 228, -2.1098079191380332, -2.1098079191356485),
        )
        for (p, i, tulip, ts) in oracle
            got = fosc(ref.close, p)
            @test findfirst(!ismissing, got) == p + 1
            @test abs(got[p+i+1] - tulip) <= 1e-10 && abs(got[p+i+1] - ts) <= 1e-10
        end
        # FOSC is TSF anchored one bar earlier, and 0 at a zero close.
        tsf = foldseries(TSF(:close), ref; window = Bars(5)).w_close_tsf
        got = fosc(ref.close, 5)
        @test all(i -> got[i] ≈ 100 * (ref.close[i] - tsf[i-1]) / ref.close[i], 6:252)
        @test fosc([1.0, 2.0, 3.0, 0.0], 2)[4] === 0.0
    end

    @testset "test_vhf.c" begin
        t = loadtable("test_vhf")
        ref = loadref()
        vhf(x, p) = foldseries(VHF(:close; period = p), (close = x,)).close_vhf
        for r in t["tables"]["vhfOracle"]["rows"]
            @test vhf(ref.close, r["period"])[r["bar"]+1] ≈ r["want"] rtol = 1e-12
        end
        for r in t["tables"]["vhfBookVectors"]["rows"]
            x, want = tablearray(t, r["in"]), tablearray(t, r["out"])
            got = vhf(x, length(x) - r["nbOut"])
            @test all(
                abs.(got[(end-r["nbOut"]+1):end] .- want) .<=
                0.5 * 10.0^-r["decimals"] + 1e-12,
            )
        end
        # A direct scan of every window, the [0, 1] bound, and a flat window's 0.
        for p in (2, 5, 14, 28)
            got = vhf(ref.close, p)
            for i in (p+1):252
                w = ref.close[(i-p+1):i]
                path = sum(abs, diff(ref.close[(i-p):i]))
                @test isapprox(got[i], (maximum(w) - minimum(w)) / path; rtol = 1e-12,
                    atol = 1e-13)
                @test 0 <= got[i] <= 1 + 8e-16
            end
        end
        x = [ref.close[1:40]; fill(ref.close[40], 40)]
        @test all(v -> v === 0.0, vhf(x, 10)[51:end])
    end

    @testset "test_er via KAMA" begin
        # ER is the ratio KAMA adapts to: KAMA steps by `(er·(2/3 − 2/31) + 2/31)²`.
        ref = loadref()
        for p in (2, 10, 30)
            er = foldseries(ER(:close; period = p), ref).close_er
            k = foldseries(KAMA(:close; period = p), ref).close_kama
            for i in (p+2):252
                sc = (er[i] * (2 / 3 - 2 / 31) + 2 / 31)^2
                @test k[i] ≈ (ref.close[i] - k[i-1]) * sc + k[i-1] rtol = 1e-12
            end
            @test all(x -> 0 <= x <= 1, skipmissing(er))
        end
        er(x, p) = foldseries(ER(:close; period = p), (close = x,)).close_er
        @test all(==(1.0), er(collect(1.0:20.0), 4)[5:end])
        @test all(==(1.0), er(fill(3.0, 20), 4)[5:end])
        @test all(==(1.0), er([collect(1.0:20.0); fill(20.0, 20)], 4)[25:end])
    end

    @testset "test_composite1.c AO, AC and QStick" begin
        ref = loadref()
        mp = (ref.high .+ ref.low) ./ 2
        sma(x, n) = [i < n ? missing : sum(x[(i-n+1):i]) / n for i in eachindex(x)]
        for (f, s) in ((5, 34), (34, 5), (2, 3))
            ao = foldseries(AO(; fastperiod = f, slowperiod = s), ref).ao
            want = sma(mp, f) .- sma(mp, s)
            @test isequal(ismissing.(ao), ismissing.(want))
            @test all(skipmissing(ao) .≈ skipmissing(want))
            for g in (2, 5)
                ac = foldseries(AC(; fastperiod = f, slowperiod = s, signalperiod = g),
                    ref).ac
                lb = max(f, s) - 1
                aw = Vector{Union{Missing,Float64}}(missing, 252)
                aw[(lb+1):end] = want[(lb+1):end] .- sma(collect(skipmissing(want)), g)
                @test isequal(ismissing.(ac), ismissing.(aw))
                @test all(skipmissing(ac) .≈ skipmissing(aw))
            end
        end
        t = loadtable("test_composite1")
        qs(o, c, p) = foldseries(QStick(), (open = o, close = c); window = Bars(p)).w_qstick
        for (o, c, e, p) in (("qstickBookOpen", "qstickBookClose", "qstickBookExp", 4),
            ("qstickTulipOpen", "qstickTulipClose", "qstickTulipExp", 5))
            want = tablearray(t, e)
            got = qs(tablearray(t, o), tablearray(t, c), p)
            @test count(!ismissing, got) == length(want)
            @test all(abs.(got[p:end] .- want) .<= 1e-12)
        end
        for p in t["arrays"]["qstickGrid"]["values"]
            got = qs(ref.open, ref.close, p)
            want = sma(ref.close .- ref.open, p)
            @test isequal(ismissing.(got), ismissing.(want))
            @test all(isapprox.(skipmissing(got), skipmissing(want); atol = 1e-12))
        end
    end

    @testset "test_composite2.c Coppock and SMI" begin
        ref = loadref()
        x = ref.close
        for (w, r1, r2) in ((10, 11, 14), (1, 11, 14), (5, 14, 3))
            got = foldseries(Coppock(:close; wmaperiod = w, roc1period = r1,
                roc2period = r2), ref).close_coppock
            m = max(r1, r2)
            s = [(x[i] / x[i-r1] - 1) * 100 + (x[i] / x[i-r2] - 1) * 100 for i in (m+1):252]
            wma = [sum((1:w) .* s[(j-w+1):j]) / (w * (w + 1) / 2) for j in w:length(s)]
            @test findfirst(!ismissing, got) == m + w
            @test got[(m+w):end] ≈ wma rtol = 1e-12
        end
        # SMI composed from the window's extremes and TA_EMA's chained stages.
        ema(v, n) = foldseries(EMA(:x; period = n), (x = v,)).x_ema
        p, f, sl, g = 13, 2, 25, 9
        hh = foldseries(Max(:high), ref; window = Bars(p)).w_high_max
        ll = foldseries(Min(:low), ref; window = Bars(p)).w_low_min
        num = collect(skipmissing(ref.close .- (hh .+ ll) .* 0.5))
        den = collect(skipmissing(hh .- ll))
        sm(v) = collect(skipmissing(ema(collect(skipmissing(ema(v, sl))), f)))
        smi = 100 .* sm(num) ./ (0.5 .* sm(den))
        sig = collect(skipmissing(ema(smi, g)))
        out = foldseries(SMI(), ref)
        @test count(!ismissing, out.smi_smi) == length(sig)
        @test collect(skipmissing(out.smi_smi)) ≈ smi[g:end] rtol = 1e-12
        @test collect(skipmissing(out.smi_smisignal)) ≈ sig rtol = 1e-12
        scaled = map(c -> c .* ldexp(1.0, -60), ref)
        q = foldseries(SMI(; period = 10, fastperiod = 3, slowperiod = 3,
            signalperiod = 3), scaled)
        @test q.smi_smi[252] ≈ 4.34844428191114 rtol = 1e-12
        @test all(v -> -100 <= v <= 100, skipmissing(q.smi_smi))
        @test all(v -> -100 <= v <= 100, skipmissing(q.smi_smisignal))
        flat = (high = fill(5.0, 80), low = fill(5.0, 80), close = fill(5.0, 80))
        @test all(v -> v === 0.0, skipmissing(foldseries(SMI(), flat).smi_smi))
    end

    @testset "test_tsi.c" begin
        t = loadtable("test_tsi")
        ref = loadref()
        tsi(a, b; kw...) =
            foldseries(TSI(:close; firstperiod = a, secondperiod = b, kw...), ref).close_tsi
        for r in t["tables"]["tsiOracle"]["rows"]
            got = tsi(r["first"], r["second"])
            @test findfirst(!ismissing, got) == r["first"] + r["second"]
            @test abs(got[r["bar"]+1] - r["want"]) <= 1e-12
        end
        got = tsi(5, 3)
        for r in t["tables"]["tsiTradingSignals"]["rows"]
            @test abs(got[r["bar"]+1] - r["want"]) <= 1e-12
        end
        # The unstable period delays both stages: the lookback grows by twice it.
        for u in t["arrays"]["tsiUnstGrid"]["values"]
            @test findfirst(!ismissing, tsi(25, 13; unstable = u)) == 38 + 2u
        end
        flat = foldseries(TSI(:close), (close = fill(7.0, 80),)).close_tsi
        @test all(v -> v === 0.0, skipmissing(flat))
    end

    @testset "test_eri.c" begin
        ref = loadref()
        out = foldseries(ERI(), ref)
        @test findfirst(!ismissing, out.eri_bullpower) == 13
        for (bar, bull, bear) in ((12, 4.9611538461538487, 1.8661538461538498),
            (63, 4.7412968545015843, 2.4612968545015832),
            (110, 1.1794771477264163, -2.7605228522735814),
            (155, 4.1215715236162112, 0.7515715236162066),
            (203, -11.790083766069827, -13.910083766069832),
            (251, 0.53947989919237216, -2.3405201008076233))
            @test abs(out.eri_bullpower[bar+1] - bull) <= 1e-12
            @test abs(out.eri_bearpower[bar+1] - bear) <= 1e-12
        end
        # The shared EMA: bull − bear is high − low, and period 1 is the copy.
        @test all(
            i -> out.eri_bullpower[i] - out.eri_bearpower[i] ≈
                 ref.high[i] - ref.low[i], 13:252)
        hi, lo = 651.28353856681395, 73.36385038087522
        c = [isodd(i) ? hi : lo for i in 1:64]
        one_ = foldseries(ERI(; period = 1), (high = c .+ 1, low = c .- 1, close = c))
        @test all(==(1.0), one_.eri_bullpower) && all(==(-1.0), one_.eri_bearpower)
        for u in loadtable("test_eri")["arrays"]["eriUnstGrid"]["values"]
            got = foldseries(ERI(; unstable = u), ref).eri_bullpower
            @test findfirst(!ismissing, got) == 13 + u
            @test got[(13+u):end] == out.eri_bullpower[(13+u):end]
        end
    end

    @testset "test_vortex.c" begin
        ref = loadref()
        out = foldseries(Vortex(), ref)
        @test findfirst(!ismissing, out.vortex_plusvi) == 15
        for (bar, plus, minus) in ((14, 0.91516119373190941, 0.90527996806068456),
            (20, 0.90702681542376196, 0.96036406341749847),
            (50, 0.99915659263424228, 0.81993252741073930),
            (125, 1.19342208300704770, 0.63997650743931100),
            (200, 0.72637931034482750, 1.22413793103448270),
            (251, 0.93942403177755707, 1.02333664349553130))
            @test isapprox(out.vortex_plusvi[bar+1], plus; rtol = 1e-12, atol = 1e-12)
            @test isapprox(out.vortex_minusvi[bar+1], minus; rtol = 1e-12, atol = 1e-12)
        end
        # TRange and the movements through window sums, at every period.
        h, l, c = ref.high, ref.low, ref.close
        tr = [max(h[i] - l[i], abs(c[i-1] - h[i]), abs(c[i-1] - l[i])) for i in 2:252]
        vp = [abs(h[i] - l[i-1]) for i in 2:252]
        vm = [abs(l[i] - h[i-1]) for i in 2:252]
        for p in loadtable("test_vortex")["arrays"]["vortexPeriodGrid"]["values"]
            got = foldseries(Vortex(; period = p), ref)
            for i in p:251
                s = sum(tr[(i-p+1):i])
                @test got.vortex_plusvi[i+1] ≈ sum(vp[(i-p+1):i]) / s rtol = 1e-12
                @test got.vortex_minusvi[i+1] ≈ sum(vm[(i-p+1):i]) / s rtol = 1e-12
            end
        end
        # A halt after a spread bar: the true range sum is exactly 0, so both
        # lines are 0, while the movements stay non-negative.
        hh = [fill(10.0, 5); 12.0; fill(11.0, 10)]
        lw = [fill(10.0, 5); 9.0; fill(11.0, 10)]
        cl = [fill(10.0, 5); 11.0; fill(11.0, 10)]
        got = foldseries(Vortex(; period = 3), (high = hh, low = lw, close = cl))
        @test all(==(0.0), got.vortex_plusvi[10:end])
        @test all(==(0.0), got.vortex_minusvi[10:end])
    end

    @testset "test_imi.c" begin
        ref = loadref()
        for r in loadtable("test_imi")["tables"]["tableTest"]["rows"]
            p = r["optInTimePeriod"]
            got = tablerun(d -> foldseries(IMI(), d; window = Bars(p)).w_imi, ref,
                r["startIdx"], r["endIdx"], p - 1)
            checkrow(got, r; out = "oneOfTheExpectedOutReal0",
                index = "oneOfTheExpectedOutRealIndex0")
        end
        # A flat window gives 50, including after the sliding sums have held
        # moves; an all-up window 100 and an all-down one 0.
        imi(o, c, p) = foldseries(IMI(), (open = o, close = c); window = Bars(p)).w_imi
        o = [ref.open[1:30]; fill(5.0, 30)]
        c = [ref.close[1:30]; fill(5.0, 30)]
        @test all(==(50.0), imi(o, c, 7)[37:end])
        @test all(==(100.0), imi(fill(1.0, 10), fill(2.0, 10), 3)[3:end])
        @test all(==(0.0), imi(fill(2.0, 10), fill(1.0, 10), 3)[3:end])
    end

    @testset "test_kdj.c" begin
        ref = loadref()
        for r in loadtable("test_kdj")["tables"]["kdjOracle"]["rows"]
            m = r["arm"] == "KDJ_ARM_TULIP" ? :rma : :sma
            out = foldseries(
                KDJ(; fastkperiod = r["n"], slowkperiod = r["m1"],
                    slowdperiod = r["m2"], slowkmatype = m, slowdmatype = m), ref)
            i = r["bar"] + 1
            for (got, want) in ((out.kdj_k[i], r["k"]), (out.kdj_d[i], r["d"]),
                (out.kdj_j[i], r["j"]))
                @test isapprox(got, want; rtol = 1e-13, atol = 2e-12)
            end
        end
        # KDJ is Stoch's two lines plus J.
        for (n, m1, m2) in ((9, 3, 3), (5, 3, 3), (14, 3, 3), (9, 5, 5), (2, 1, 1),
                (9, 1, 3)),
            m in (:rma, :sma, :ema)

            k = foldseries(
                KDJ(; fastkperiod = n, slowkperiod = m1, slowdperiod = m2,
                    slowkmatype = m, slowdmatype = m), ref)
            s = foldseries(
                Stoch(; fastkperiod = n, slowkperiod = m1, slowdperiod = m2,
                    slowkmatype = m, slowdmatype = m), ref)
            @test isequal(k.kdj_k, s.stoch_slowk) && isequal(k.kdj_d, s.stoch_slowd)
            @test isequal(k.kdj_j, 3 .* k.kdj_k .- 2 .* k.kdj_d)
        end
    end

    @testset "test_fractal.c" begin
        t = loadtable("test_fractal")
        a = t["arrays"]
        fires(f) = findall(==(100), coalesce.(f, 0)) .- 1
        function check(data, rows)
            for r in rows
                out = foldseries(
                    Fractal(; leftbars = r["optInLeftBars"],
                        rightbars = r["optInRightBars"]), data)
                lb = r["optInLeftBars"] + r["optInRightBars"]
                @test findfirst(!ismissing, out.fractal_swinghigh) == lb + 1
                @test fires(out.fractal_swinghigh) == a[r["swingHigh"]]["values"]
                @test fires(out.fractal_swinglow) == a[r["swingLow"]]["values"]
            end
        end
        ref = loadref()
        check(ref, t["tables"]["fractalCorpus"]["rows"])
        syn = (high = tablearray(t, "fractalSynHigh"), low = tablearray(t, "fractalSynLow"))
        check(syn, t["tables"]["fractalSynthetic"]["rows"])
        for r in t["tables"]["fractalBothFire"]["rows"]
            out = foldseries(
                Fractal(; leftbars = r["optInLeftBars"],
                    rightbars = r["optInRightBars"]), syn)
            @test out.fractal_swinghigh[r["bar"]+1] == out.fractal_swinglow[r["bar"]+1] ==
                  100
        end
        # Flat and monotone series have no pivot.
        for hi in (fill(50.0, 64), 48.0 .+ 0.25 .* (0:63)),
            (l, r) in a["fractalDegPairs"]["values"]

            out = foldseries(
                Fractal(; leftbars = l, rightbars = r),
                (high = hi, low = hi .- 2),
            )
            @test all(==(0), out.fractal_swinghigh[(l+r+1):end])
            @test all(==(0), out.fractal_swinglow[(l+r+1):end])
        end
    end

    @testset "test_ha.c" begin
        t = loadtable("test_ha")["tables"]
        function check(data, rows)
            out = foldseries(HeikinAshi(), data)
            for r in rows
                i = r["bar"] + 1
                @test out.ha_haopen[i] == r["open"] && out.ha_hahigh[i] == r["high"]
                @test out.ha_halow[i] == r["low"] && out.ha_haclose[i] == r["close"]
            end
        end
        check(loadref(), t["haSrefOracle"]["rows"])
        i = 0:63
        b = 100.0 .+ 0.125 .* ((i .* 13) .% 64)
        seed = (open = b, high = b .+ 2.0 .+ 0.125 .* (i .% 7),
            low = b .- 2.0 .- 0.125 .* (i .% 5),
            close = b .+ 0.25 .* (((i .* 7) .% 9) .- 4))
        check(seed, t["haSeedOracle"]["rows"])
        # The signed zeros: the extremes start at the raw high and low and move
        # only on a strictly greater or lesser candidate.
        neg = [1 0 1 1; 1 1 0 1; 0 1 1 0; 1 1 1 1; 0 0 0 0; 1 0 0 1; 0 1 0 1; 1 0 1 0]
        z = map(j -> [neg[k, j] == 1 ? -0.0 : 0.0 for k in 1:8], 1:4)
        out = foldseries(HeikinAshi(), (open = z[1], high = z[2], low = z[3], close = z[4]))
        bits = loadtable("test_ha")["arrays"]["haZeroSignBits"]["values"]
        for k in 1:8, (j, o) in enumerate((:ha_haopen, :ha_hahigh, :ha_halow, :ha_haclose))
            @test signbit(out[o][k]) == (bits[k][j] == 1)
        end
        # The unstable period only delays the output.
        whole = foldseries(HeikinAshi(), loadref())
        for u in (1, 5, 30)
            got = foldseries(HeikinAshi(; unstable = u), loadref())
            @test all(ismissing, got.ha_haopen[1:u])
            @test got.ha_haclose[(u+1):end] == whole.ha_haclose[(u+1):end]
        end
    end

    @testset "test_per_hlc.c WAD" begin
        t = loadtable("test_per_hlc")
        ref = loadref()
        wad = foldseries(WAD(), ref).wad
        for r in t["tables"]["tableTest"]["rows"]
            r["theFunction"] == "TA_WAD_TEST" || continue
            got =
                tablerun(d -> foldseries(WAD(), d).wad, ref, r["startIdx"], r["endIdx"], 0)
            checkrow(got, r; out = "oneOfTheExpectedOutReal0",
                index = "oneOfTheExpectedOutRealIndex0")
        end
        # The published vectors omit the leading 0 of the first bar.
        for k in ("Book", "Tulip")
            got = foldseries(
                WAD(),
                (high = tablearray(t, "wad$(k)High"),
                    low = tablearray(t, "wad$(k)Low"),
                    close = tablearray(t, "wad$(k)Close")),
            ).wad
            @test got[1] === 0.0
            @test all(abs.(got[2:end] .- tablearray(t, "wad$(k)Exp")) .<= 5e-3)
        end
        @test wad[1] === 0.0
    end

    @testset "missing bars are skipped" begin
        r = loadref()
        n = 80
        base = map(c -> c[1:n], r)
        withgaps = map(
            c -> (v = Union{Missing,Float64}[]; foreach(x -> push!(v, missing, x), c); v),
            base,
        )
        for s in PLAIN_S5
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
        for s in PLAIN_S5
            checkstreaming(s, t)
        end
        for (s, w) in ((QStick(), 10), (IMI(), 14), (FOSC(:close), 6))
            checkstreaming(s, t; window = Bars(w), timewindow = w - 1)
        end
    end

    @testset "zero allocations" begin
        rng = Random.MersenneTwister(5)
        mkrow(x) = (time = 1, open = x, high = x + 1, low = x - 1, close = x, volume = 1e5)
        for s in PLAIN_S5
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

    @testset "parameter ranges" begin
        @test_throws ArgumentError AO(; fastperiod = 1)
        @test_throws ArgumentError AC(; signalperiod = 1)
        @test_throws ArgumentError CMOU(:close; period = 1)
        @test_throws ArgumentError Coppock(:close; wmaperiod = 0)
        @test_throws ArgumentError DPO(:close; period = 1)
        @test_throws ArgumentError ER(:close; period = 1)
        @test_throws ArgumentError ERI(; period = 0)
        @test_throws ArgumentError ERI(; unstable = -1)
        @test_throws ArgumentError Fractal(; leftbars = 0)
        @test_throws ArgumentError KDJ(; slowkmatype = :nope)
        @test_throws ArgumentError SMI(; fastperiod = 1)
        @test_throws ArgumentError TSI(:close; secondperiod = 1)
        @test_throws ArgumentError VHF(:close; period = 1)
        @test_throws ArgumentError Vortex(; period = 0)
        @test_throws ArgumentError HeikinAshi(; unstable = -1)
    end
end
