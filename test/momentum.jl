# S2 momentum indicators: the structured MOM/ROC family, WillR, BOP, Aroon,
# AroonOsc and CCI, and the plain RSI, CMO, MACD family, APO/PPO, TRIX,
# stochastics, ULTOSC and MFI, against TA-Lib's goldens and tables.

using CausalIndicators: GainLossKernel, FastKKernel, malookback

# The MA type of a golden's `optIn…MAType` parameter, or `default`.
matypeof(p, k, default) = MATYPE_CODES[get(p, k, default)]

# One of each plain S2 state, for the allocation and JET checks.
const PLAIN_S2 = [
    RSI(:close; period = 5),
    CMO(:close; period = 5, unstable = 2),
    MACD(:close; fastperiod = 3, slowperiod = 6, signalperiod = 4, unstable = 1),
    MACDFix(:close; signalperiod = 4),
    MACDExt(:close; fastmatype = :kama, slowmatype = :ema, signalmatype = :t3,
        fastperiod = 4, slowperiod = 7, signalperiod = 3),
    APO(:close; fastperiod = 3, slowperiod = 7),
    PPO(:close; fastperiod = 3, slowperiod = 7, matype = :dema),
    TRIX(:close; period = 4),
    Stoch(; fastkperiod = 4, slowkmatype = :ema, slowdmatype = :wma),
    StochF(; fastkperiod = 4, fastdmatype = :tema),
    StochRSI(:close; period = 5, fastkperiod = 4, fastdperiod = 3),
    ULTOSC(; timeperiod1 = 3, timeperiod2 = 5, timeperiod3 = 8),
    MFI(; period = 5),
]
const S2_INTYPES = (open = Float64, high = Float64, low = Float64,
    close = Union{Missing,Float64}, volume = Float64)

# The lookback of a table row's call, for `tablerun`'s slice.
stochlookback(fk, sk, skm, sd, sdm) =
    fk - 1 + malookback(Val(skm), sk, 0) + malookback(Val(sdm), sd, 0)

# Rows asserting an error code: a bad parameter is a constructor error here,
# and the start/end index errors have no counterpart in a stream.
function tablestatus(r, ctor)
    code = r["expectedRetCode"]
    code == "TA_SUCCESS" && return true
    code == "TA_BAD_PARAM" && @test_throws ArgumentError ctor()
    return false
end

# A naive Williams' %R of the window ending at bar i, as willr.c computes it.
function naivewillr(h, l, c, i, p)
    hh = maximum(@view h[(i-p+1):i])
    ll = minimum(@view l[(i-p+1):i])
    abs(hh - ll) <= 1e-14 * (abs(hh) + abs(ll)) && return 0.0
    return clamp(((hh - c[i]) / (hh - ll)) * -100, -100.0, 0.0)
end

@testset "momentum" begin
    @testset "RSI and CMO goldens" begin
        for (fn, ctor) in (("RSI", RSI), ("CMO", CMO))
            checkgoldens(fn; outputs = (:outReal,)) do p, data
                s = ctor(:close; period = get(p, :optInTimePeriod, 14),
                    unstable = get(p, :unstable, 0))
                (only(foldseries(s, data)),)
            end
        end
    end

    @testset "MACD family goldens" begin
        outs = (:outMACD, :outMACDSignal, :outMACDHist)
        checkgoldens("MACD"; outputs = outs) do p, data
            s = MACD(:close; fastperiod = get(p, :optInFastPeriod, 12),
                slowperiod = get(p, :optInSlowPeriod, 26),
                signalperiod = get(p, :optInSignalPeriod, 9),
                unstable = get(p, :unstable, 0))
            Tuple(foldseries(s, data))
        end
        checkgoldens("MACDFIX"; outputs = outs) do p, data
            s = MACDFix(:close; signalperiod = get(p, :optInSignalPeriod, 9),
                unstable = get(p, :unstable, 0))
            Tuple(foldseries(s, data))
        end
        checkgoldens("MACDEXT"; outputs = outs) do p, data
            s = MACDExt(:close; fastperiod = get(p, :optInFastPeriod, 12),
                fastmatype = matypeof(p, :optInFastMAType, 0),
                slowperiod = get(p, :optInSlowPeriod, 26),
                slowmatype = matypeof(p, :optInSlowMAType, 0),
                signalperiod = get(p, :optInSignalPeriod, 9),
                signalmatype = matypeof(p, :optInSignalMAType, 0),
                unstable = get(p, :unstable, 0))
            Tuple(foldseries(s, data))
        end
    end

    @testset "APO, PPO and TRIX goldens" begin
        for (fn, ctor) in (("APO", APO), ("PPO", PPO))
            checkgoldens(fn; outputs = (:outReal,)) do p, data
                s = ctor(:close; fastperiod = get(p, :optInFastPeriod, 12),
                    slowperiod = get(p, :optInSlowPeriod, 26),
                    matype = matypeof(p, :optInMAType, 1),
                    unstable = get(p, :unstable, 0))
                (only(foldseries(s, data)),)
            end
        end
        checkgoldens("TRIX"; outputs = (:outReal,)) do p, data
            s = TRIX(:close; period = get(p, :optInTimePeriod, 30),
                unstable = get(p, :unstable, 0))
            (foldseries(s, data).close_trix,)
        end
    end

    @testset "stochastic goldens" begin
        checkgoldens("STOCH"; outputs = (:outSlowK, :outSlowD)) do p, data
            s = Stoch(; fastkperiod = get(p, :optInFastK_Period, 5),
                slowkperiod = get(p, :optInSlowK_Period, 3),
                slowkmatype = matypeof(p, :optInSlowK_MAType, 0),
                slowdperiod = get(p, :optInSlowD_Period, 3),
                slowdmatype = matypeof(p, :optInSlowD_MAType, 0),
                unstable = get(p, :unstable, 0))
            o = foldseries(s, data)
            (o.stoch_slowk, o.stoch_slowd)
        end
        checkgoldens("STOCHF"; outputs = (:outFastK, :outFastD)) do p, data
            s = StochF(; fastkperiod = get(p, :optInFastK_Period, 5),
                fastdperiod = get(p, :optInFastD_Period, 3),
                fastdmatype = matypeof(p, :optInFastD_MAType, 0),
                unstable = get(p, :unstable, 0))
            o = foldseries(s, data)
            (o.stochf_fastk, o.stochf_fastd)
        end
        checkgoldens("STOCHRSI"; outputs = (:outFastK, :outFastD)) do p, data
            s = StochRSI(:close; period = get(p, :optInTimePeriod, 14),
                fastkperiod = get(p, :optInFastK_Period, 5),
                fastdperiod = get(p, :optInFastD_Period, 3),
                fastdmatype = matypeof(p, :optInFastD_MAType, 0),
                unstable = get(p, :unstable, 0))
            o = foldseries(s, data)
            (o.close_stochrsi_fastk, o.close_stochrsi_fastd)
        end
    end

    @testset "ULTOSC and MFI goldens" begin
        checkgoldens("ULTOSC"; outputs = (:outReal,)) do p, data
            s = ULTOSC(; timeperiod1 = get(p, :optInTimePeriod1, 7),
                timeperiod2 = get(p, :optInTimePeriod2, 14),
                timeperiod3 = get(p, :optInTimePeriod3, 28))
            (foldseries(s, data).ultosc,)
        end
        checkgoldens("MFI"; outputs = (:outReal,)) do p, data
            (foldseries(MFI(; period = get(p, :optInTimePeriod, 14)), data).mfi,)
        end
    end

    @testset "structured goldens" begin
        # TA-Lib's period p is Bars(p) for the window functions and Bars(p + 1)
        # for the ones that compare with the bar p back.
        for (fn, s, out, default, extra) in (
            ("MOM", MOM(:close), :w_close_mom, 10, 1),
            ("ROC", ROC(:close), :w_close_roc, 10, 1),
            ("ROCP", ROCP(:close), :w_close_rocp, 10, 1),
            ("ROCR", ROCR(:close), :w_close_rocr, 10, 1),
            ("ROCR100", ROCR100(:close), :w_close_rocr100, 10, 1),
            ("WILLR", WillR(), :w_willr, 14, 0),
            ("CCI", CCI(), :w_cci, 14, 0),
            ("AROONOSC", AroonOsc(), :w_aroonosc, 14, 1))
            checkgoldens(fn; outputs = (:outReal,)) do p, data
                w = Bars(get(p, :optInTimePeriod, default) + extra)
                (foldseries(s, data; window = w)[out],)
            end
        end
        # Aroon's newest-wins tie-break is CausalFrames', so no row is skipped.
        checkgoldens("AROON"; outputs = (:outAroonDown, :outAroonUp)) do p, data
            o = foldseries(Aroon(), data; window = Bars(get(p, :optInTimePeriod, 14) + 1))
            (o.w_aroon_aroondown, o.w_aroon_aroonup)
        end
        checkgoldens("BOP"; outputs = (:outReal,)) do p, data
            (foldseries(BOP(), data).bop,)
        end
    end

    @testset "test_rsi.c table rows" begin
        close = loadref().close
        n = 0
        for r in loadtable("test_rsi")["tables"]["tableTest"]["rows"]
            ctor = r["theFunction"] == "TA_RSI_TEST" ? RSI : CMO
            p, u = r["optInTimePeriod"], r["unstablePeriod"]
            tablestatus(r, () -> ctor(:x; period = p)) || continue
            got = tablerun((; close), r["startIdx"], r["endIdx"], p + u) do d
                only(foldseries(ctor(:close; period = p, unstable = u), d))
            end
            checkrow(got, r; out = "oneOfTheExpectedOutReal0",
                index = "oneOfTheExpectedOutRealIndex0")
            n += 1
        end
        @test n >= 15
    end

    @testset "test_macd.c table rows" begin
        close = loadref().close
        n = 0
        for r in loadtable("test_macd")["tables"]["tableTest"]["rows"]
            fast, slow = minmax(r["optInFastPeriod"], r["optInSlowPeriod"])
            sig = r["optInSignalPeriod_2"]
            id = r["testId"]
            s =
                id == "TA_MACDFIX_TEST" ? MACDFix(:close; signalperiod = sig) :
                id == "TA_MACDEXT_TEST" ?
                MACDExt(:close; fastperiod = fast, slowperiod = slow, signalperiod = sig,
                    fastmatype = :ema, slowmatype = :ema, signalmatype = :ema) :
                MACD(:close; fastperiod = fast, slowperiod = slow, signalperiod = sig)
            id == "TA_MACDFIX_TEST" && ((fast, slow) = (12, 26))
            tablestatus(
                r,
                () -> MACD(:x; fastperiod = fast, slowperiod = slow,
                    signalperiod = sig),
            ) || continue
            lb = slow - 1 + sig - 1
            for k in 0:2
                got = tablerun((; close), r["startIdx"], r["endIdx"], lb) do d
                    foldseries(s, d)[k+1]
                end
                checkrow(got, r; out = "oneOfTheExpectedOutReal$k",
                    index = "oneOfTheExpectedOutRealIndex$k")
            end
            n += 1
        end
        @test n >= 5
    end

    @testset "test_mom.c table rows" begin
        close = loadref().close
        ctors = Dict("TA_MOM_TEST" => MOM, "TA_ROC_TEST" => ROC, "TA_ROCR_TEST" => ROCR,
            "TA_ROCR100_TEST" => ROCR100, "TA_ROCP_TEST" => ROCP)
        n = 0
        for r in loadtable("test_mom")["tables"]["tableTest"]["rows"]
            r["expectedRetCode"] == "TA_SUCCESS" || continue
            ctor = ctors[r["theFunction"]]
            p = r["optInTimePeriod"]
            got = tablerun((; close), r["startIdx"], r["endIdx"], p) do d
                only(foldseries(ctor(:close), d; window = Bars(p + 1)))
            end
            checkrow(got, r; out = "oneOfTheExpectedOutReal0",
                index = "oneOfTheExpectedOutRealIndex0")
            n += 1
        end
        @test n >= 40
    end

    @testset "test_stoch.c table rows" begin
        ref = loadref()
        n = 0
        for r in loadtable("test_stoch")["tables"]["tableTest"]["rows"]
            p0, p1, p2 = r["optInPeriod_0"], r["optInPeriod_1"], r["optInPeriod_2"]
            dm = tablematype(r["optInMAType_2"])
            if r["testId"] == "TEST_STOCH"
                km = tablematype(r["optInMAType_1"])
                s =
                    () -> Stoch(; fastkperiod = p0, slowkperiod = p1, slowkmatype = km,
                        slowdperiod = p2, slowdmatype = dm)
                lb = stochlookback(p0, p1, km, p2, dm)
            else
                s =
                    () -> StochRSI(:close; period = p0, fastkperiod = p1, fastdperiod = p2,
                        fastdmatype = dm)
                lb = p0 + p1 - 1 + malookback(Val(dm), p2, 0)
            end
            tablestatus(r, s) || continue
            for k in 0:1
                got = tablerun(ref, r["startIdx"], r["endIdx"], lb) do d
                    foldseries(s(), d)[k+1]
                end
                checkrow(got, r; out = "oneOfTheExpectedOutReal$k",
                    index = "oneOfTheExpectedOutRealIndex$k")
            end
            n += 1
        end
        @test n >= 10
    end

    @testset "test_po.c table rows" begin
        close = loadref().close
        n = 0
        for r in loadtable("test_po")["tables"]["tableTest"]["rows"]
            ctor = r["doPercentage"] == 1 ? PPO : APO
            fast, slow = r["optInFastPeriod"], r["optInSlowPeriod"]
            m = tablematype(r["optInMethod_2"])
            s = () -> ctor(:close; fastperiod = fast, slowperiod = slow, matype = m)
            tablestatus(r, s) || continue
            lb = malookback(Val(m), max(fast, slow), 0)
            got = tablerun((; close), r["startIdx"], r["endIdx"], lb) do d
                only(foldseries(s(), d))
            end
            # ta_APO.c calls TA_MA for each average from startIdx, so a
            # recursive fast average starts lookback(fast) bars before it, not
            # where the slow one does. That depends on where a batch call
            # starts, which a stream cannot reproduce; the full-series goldens
            # check those values, and these rows only their shape.
            checkrow(got, r; value = m === :sma || r["startIdx"] == 0)
            n += 1
        end
        @test n >= 30
    end

    @testset "test_per_ema.c TRIX rows" begin
        close = loadref().close
        n = 0
        for r in loadtable("test_per_ema")["tables"]["tableTest"]["rows"]
            r["theFunction"] == "TA_TRIX_TEST" || continue
            p, u = r["optInTimePeriod"], r["unstablePeriod"]
            tablestatus(r, () -> TRIX(:x; period = p)) || continue
            got = tablerun((; close), r["startIdx"], r["endIdx"], 3 * (p - 1 + u) + 1) do d
                foldseries(TRIX(:close; period = p, unstable = u), d).close_trix
            end
            checkrow(got, r)
            n += 1
        end
        @test n >= 3
    end

    @testset "test_per_hlc.c rows" begin
        ref = loadref()
        n = 0
        for r in loadtable("test_per_hlc")["tables"]["tableTest"]["rows"]
            f = r["theFunction"]
            f in ("TA_CCI_TEST", "TA_WILLR_TEST", "TA_ULTOSC_TEST") || continue
            r["expectedRetCode"] == "TA_SUCCESS" || continue
            p1, p2, p3 = r["optInTimePeriod1"], r["optInTimePeriod2"], r["optInTimePeriod3"]
            run, lb = if f == "TA_ULTOSC_TEST"
                d -> foldseries(
                    ULTOSC(; timeperiod1 = p1, timeperiod2 = p2,
                        timeperiod3 = p3), d).ultosc,
                max(p1, p2, p3)
            elseif f == "TA_CCI_TEST"
                d -> foldseries(CCI(), d; window = Bars(p1)).w_cci, p1 - 1
            else
                d -> foldseries(WillR(), d; window = Bars(p1)).w_willr, p1 - 1
            end
            got = tablerun(run, ref, r["startIdx"], r["endIdx"], lb)
            checkrow(got, r; out = "oneOfTheExpectedOutReal0",
                index = "oneOfTheExpectedOutRealIndex0")
            n += 1
        end
        @test n >= 10
    end

    @testset "test_per_hlcv.c MFI rows" begin
        ref = loadref()
        n = 0
        for r in loadtable("test_per_hlcv")["tables"]["tableTest"]["rows"]
            r["theFunction"] == "TA_MFI_TEST" || continue
            r["expectedRetCode"] == "TA_SUCCESS" || continue
            p = r["optInTimePeriod"]
            got = tablerun(ref, r["startIdx"], r["endIdx"], p) do d
                foldseries(MFI(; period = p), d).mfi
            end
            checkrow(got, r; out = "oneOfTheExpectedOutReal0",
                index = "oneOfTheExpectedOutRealIndex0")
            n += 1
        end
        @test n >= 5
    end

    @testset "test_per_hl.c Aroon rows" begin
        ref = loadref()
        outs = Dict("TA_AROON_UP_TEST" => :w_aroon_aroonup,
            "TA_AROON_DOWN_TEST" => :w_aroon_aroondown,
            "TA_AROONOSC_TEST" => :w_aroonosc)
        n = 0
        for r in loadtable("test_per_hl")["tables"]["tableTest"]["rows"]
            out = get(outs, r["theFunction"], nothing)
            out === nothing && continue
            r["expectedRetCode"] == "TA_SUCCESS" || continue
            p = r["optInTimePeriod"]
            s = out === :w_aroonosc ? AroonOsc() : Aroon()
            got = tablerun(ref, r["startIdx"], r["endIdx"], p) do d
                foldseries(s, d; window = Bars(p + 1))[out]
            end
            checkrow(got, r; out = "oneOfTheExpectedOutReal0",
                index = "oneOfTheExpectedOutRealIndex0")
            n += 1
        end
        @test n >= 5
    end

    @testset "test_per_ohlc.c BOP rows" begin
        ref = loadref()
        n = 0
        for r in loadtable("test_per_ohlc")["tables"]["tableTest"]["rows"]
            r["theFunction"] == "TA_BOP_TEST" || continue
            r["expectedRetCode"] == "TA_SUCCESS" || continue
            got = tablerun(d -> foldseries(BOP(), d).bop, ref, r["startIdx"],
                r["endIdx"], 0)
            checkrow(got, r; out = "oneOfTheExpectedOutReal0",
                index = "oneOfTheExpectedOutRealIndex0")
            n += 1
        end
        @test n >= 2
    end

    @testset "test_mfi.c oracles" begin
        ref = loadref()
        # The Tulip and pandas-ta oracles at the C test's 2e-12, with natural
        # volume and with volume × 2^-60.
        for scale in (1.0, ldexp(1.0, -60))
            data = merge(ref, (volume = ref.volume .* scale,))
            for r in loadtable("test_mfi")["tables"]["mfiOracle"]["rows"]
                p = r["period"]
                got = foldseries(MFI(; period = p), data).mfi
                @test findfirst(!ismissing, got) - 1 == p
                v = got[p+r["idx"]+1]
                @test abs(v - r["tulip"]) <= 2e-12 && abs(v - r["pandas"]) <= 2e-12
            end
        end
        # Scaling every volume by a power of two leaves MFI bit-identical.
        for p in loadtable("test_mfi")["arrays"]["mfiPeriod"]["values"]
            want = foldseries(MFI(; period = p), ref).mfi
            for k in loadtable("test_mfi")["arrays"]["mfiScaleExp"]["values"]
                data = merge(ref, (volume = ref.volume .* ldexp(1.0, -k),))
                @test isequal(foldseries(MFI(; period = p), data).mfi, want)
            end
        end
        # In [0, 100] at every period.
        @test all(2:60) do p
            all(v -> 0 <= v <= 100, skipmissing(foldseries(MFI(; period = p), ref).mfi))
        end
        # A window with no money flow is exactly 0: after a busy stretch, 40
        # bars whose typical price is flat (shape 0) or whose volume is zero
        # (shape 1), over 24 phases.
        nb = 252
        for shape in 0:1, ph in 0:23
            phase = ph * 0.0313
            t = [
                1000.0 * (
                    1.0 +
                    0.3 * sin(
                        (shape == 0 && i >= nb - 40 ? nb - 41 : i) * 0.7 + phase)
                ) for i in 0:(nb-1)
            ]
            v = [
                i < nb - 40 ? 1.0e6 + (i % 97) : shape == 0 ? 1234.0 : 0.0
                for i in 0:(nb-1)
            ]
            got = foldseries(
                MFI(),
                (high = t .* 1.01, low = t .* 0.99, close = t,
                    volume = v),
            ).mfi
            @test got[end] === 0.0
        end
    end

    @testset "test_po.c default is EMA" begin
        close = loadref().close
        for ctor in (APO, PPO)
            @test isequal(only(foldseries(ctor(:close), (; close))),
                only(foldseries(ctor(:close; matype = :ema), (; close))))
        end
    end

    @testset "constructors" begin
        @test keys(CausalFrames.emptyvalue(RSI(:close))) == (:close_rsi,)
        @test keys(CausalFrames.emptyvalue(RSI(:close; name = :rsi7))) == (:close_rsi7,)
        @test keys(CausalFrames.emptyvalue(MACD(:close))) ==
              (:close_macd_macd, :close_macd_macdsignal, :close_macd_macdhist)
        @test keys(CausalFrames.emptyvalue(MACDFix(:close; name = :m))) ==
              (:close_m_macd, :close_m_macdsignal, :close_m_macdhist)
        @test keys(CausalFrames.emptyvalue(Stoch())) == (:stoch_slowk, :stoch_slowd)
        @test keys(CausalFrames.emptyvalue(StochF(; name = :sf))) == (:sf_fastk, :sf_fastd)
        @test keys(CausalFrames.emptyvalue(StochRSI(:close))) ==
              (:close_stochrsi_fastk, :close_stochrsi_fastd)
        @test keys(CausalFrames.emptyvalue(Aroon())) == (:aroon_aroondown, :aroon_aroonup)
        @test keys(CausalFrames.emptyvalue(MFI(; name = :mfi7))) == (:mfi7,)
        @test keys(CausalFrames.emptyvalue(ROCR100(:close))) == (:close_rocr100,)
        for ctor in (RSI, CMO)
            @test_throws ArgumentError ctor(:x; period = 1)
            @test_throws ArgumentError ctor(:x; period = 100_001)
            @test_throws ArgumentError ctor(:x; unstable = -1)
        end
        @test_throws ArgumentError MACD(:x; fastperiod = 1)
        @test_throws ArgumentError MACD(:x; signalperiod = 0)
        @test_throws ArgumentError MACDExt(:x; slowmatype = :mama)
        @test_throws ArgumentError APO(:x; matype = :nope)
        @test_throws ArgumentError TRIX(:x; period = 0)
        @test_throws ArgumentError Stoch(; fastkperiod = 0)
        @test_throws ArgumentError StochRSI(:x; period = 1)
        @test_throws ArgumentError ULTOSC(; timeperiod2 = 0)
        @test_throws ArgumentError MFI(; period = 1)
        # TA-Lib swaps reversed periods.
        r = loadref()
        @test isequal(foldseries(MACD(:close; fastperiod = 26, slowperiod = 12), r),
            foldseries(MACD(:close), r))
        @test isequal(foldseries(PPO(:close; fastperiod = 26, slowperiod = 12), r),
            foldseries(PPO(:close), r))
        # MACDExt over EMAs is MACD.
        ext = foldseries(
            MACDExt(:close; fastmatype = :ema, slowmatype = :ema,
                signalmatype = :ema), r)
        @test all(
            isequal(a, b) || a ≈ b
            for (x, y) in zip(ext, foldseries(MACD(:close), r)) for (a, b) in zip(x, y)
        )
        # Two periods in one call, through `name`.
        out = foldseries([RSI(:close; period = 7, name = :rsi7), RSI(:close)], r)
        @test keys(out) == (:close_rsi7, :close_rsi)
    end

    @testset "missing bars are skipped" begin
        r = loadref()
        n = 80
        base = map(c -> c[1:n], r)
        withgaps = map(
            c -> (v = Union{Missing,Float64}[]; foreach(x -> push!(v, missing, x), c); v),
            base,
        )
        for s in (RSI(:close; period = 5), CMO(:close; period = 5), MACD(:close),
            MACDFix(:close), APO(:close; matype = :kama), TRIX(:close; period = 5),
            Stoch(), StochF(), StochRSI(:close; period = 5), ULTOSC(), MFI())
            want = foldseries(s, base)
            got = foldseries(s, withgaps)
            for o in keys(want)
                @test all(ismissing, got[o][1:2:end])
                @test isequal(got[o][2:2:end], want[o])
            end
        end
    end

    @testset "test_rolling_extremum.c WILLR block-scan oracle" begin
        rng = Random.MersenneTwister(148)
        for p in (2, 3, 29, 30, 31, 32, 60), extra in (0, 1, p - 1, p, 2p + 1)
            n = p + extra
            x = round.(100 .+ 10 .* randn(rng, n); digits = 0)
            h = x .+ rand(rng, 0:3, n)
            l = x .- rand(rng, 0:3, n)
            got =
                foldseries(WillR(), (high = h, low = l, close = x); window = Bars(p)).w_willr
            @test all(ismissing, got[1:(p-1)])
            @test all(i -> got[i] == naivewillr(h, l, x, i, p), p:n)
        end
    end

    @testset "streaming properties" begin
        r = loadref()
        t = map(c -> c[1:120], r)
        for s in (RSI(:close; period = 10), CMO(:close; period = 10),
            MACD(:close; fastperiod = 5, slowperiod = 12, signalperiod = 4),
            MACDFix(:close; signalperiod = 4),
            MACDExt(:close; fastmatype = :wma, slowmatype = :kama, slowperiod = 14),
            APO(:close; fastperiod = 5, slowperiod = 12), PPO(:close; matype = :sma),
            TRIX(:close; period = 6), Stoch(), StochF(; fastdmatype = :ema),
            StochRSI(:close; period = 8), ULTOSC(), MFI())
            checkstreaming(s, t)
        end
        for (s, w) in ((MOM(:close), 11), (ROC(:close), 11), (ROCP(:close), 11),
            (ROCR(:close), 11), (ROCR100(:close), 11), (WillR(), 14), (CCI(), 14),
            (Aroon(), 15), (AroonOsc(), 15), (BOP(), 3))
            checkstreaming(s, t; window = Bars(w), timewindow = w - 1)
        end
    end

    @testset "zero allocations" begin
        rng = Random.MersenneTwister(2)
        mkrow(x) = (time = 1, open = x, high = x + 1, low = x - 1, close = x, volume = 1e5)
        for s in PLAIN_S2
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

# S3 directional movement: ±DM, ±DI, DX, ADX and ADXR.

const DIRECTIONAL = Dict("PLUS_DM" => (PlusDM, :plusdm), "MINUS_DM" => (MinusDM, :minusdm),
    "PLUS_DI" => (PlusDI, :plusdi), "MINUS_DI" => (MinusDI, :minusdi),
    "DX" => (DX, :dx),
    "ADX" => (ADX, :adx), "ADXR" => (ADXR, :adxr))

# TA-Lib's lookback of each, at period p and unstable period u.
function dirlookback(fn, p, u)
    fn in ("PLUS_DM", "MINUS_DM") && return p == 1 ? 1 : p - 1 + u
    fn in ("PLUS_DI", "MINUS_DI") && return p == 1 ? 1 : p + u
    fn == "DX" && return p + u
    fn == "ADX" && return 2p - 1 + u
    return 3p - 2 + u
end

@testset "directional movement" begin
    @testset "$fn goldens" for fn in sort(collect(keys(DIRECTIONAL)))
        ctor, out = DIRECTIONAL[fn]
        checkgoldens(fn; outputs = (:outReal,)) do p, data
            s = ctor(;
                period = get(p, :optInTimePeriod, 14),
                unstable = get(p, :unstable, 0),
            )
            (foldseries(s, data)[out],)
        end
    end

    @testset "test_adx.c table rows" begin
        ref = loadref()
        n = 0
        for r in loadtable("test_adx")["tables"]["tableTest"]["rows"]
            fn = replace(r["id"], "TST_" => "")
            ctor, out = DIRECTIONAL[fn]
            p, u = r["optInTimePeriod"], r["unstablePeriod"]
            got = tablerun(ref, r["startIdx"], r["endIdx"], dirlookback(fn, p, u)) do d
                foldseries(ctor(; period = p, unstable = u), d)[out]
            end
            checkrow(got, r; out = "oneOfTheExpectedOutReal0",
                index = "oneOfTheExpectedOutRealIndex0")
            n += 1
        end
        @test n >= 30
    end

    @testset "period 1 (test_period_boundary.c)" begin
        ref = loadref()
        tr = foldseries(TRange(), ref; window = Bars(2)).w_trange
        for (ctor, dm) in ((PlusDI, PlusDM), (MinusDI, MinusDM))
            di = only(foldseries(ctor(; period = 1, unstable = 3), ref))
            raw = only(foldseries(dm(; period = 1, unstable = 3), ref))
            @test findfirst(!ismissing, di) == 2 && findfirst(!ismissing, raw) == 2
            # No factor 100 at period 1: TA-Lib's historical quirk.
            @test all(i -> di[i] ≈ (tr[i] == 0 ? 0.0 : raw[i] / tr[i]), 2:length(di))
        end
    end

    @testset "test_quote_unit.c 2^-60 oracles and range" begin
        ref = loadref()
        scaled = map(c -> c .* ldexp(1.0, -60), ref)
        for (ctor, out, want) in ((ADX, :adx, 15.526057510526849),
            (ADXR, :adxr, 20.492086296160466), (DX, :dx, 0.47222726427924594),
            (PlusDI, :plusdi, 20.99955113874627), (MinusDI, :minusdi, 21.198823368250974))
            # pandas-ta's oracles, to the C test's relative 1e-6 (its Wilder
            # seeding differs).
            @test foldseries(ctor(), scaled)[out][252] ≈ want rtol = 1e-6
            for p in (2, 5, 14, 30)
                v = skipmissing(foldseries(ctor(; period = p), ref)[out])
                @test all(x -> 0 <= x <= 100, v)
            end
        end
    end

    @testset "DX repeats the previous value where it is undefined" begin
        # A flat stretch has no directional movement, so the DIs sum to zero.
        h = vcat(collect(10.0:2.0:40.0), fill(40.0, 10))
        d = (high = h, low = h .- 1, close = h .- 0.5)
        dx = foldseries(DX(; period = 3), d).dx
        adx = foldseries(ADX(; period = 3), d).adx
        last_ = findlast(i -> h[i] != h[i-1], 2:length(h)) + 1
        @test all(==(dx[last_]), dx[(last_+1):end])
        @test !ismissing(adx[end])
    end

    @testset "constructors" begin
        @test keys(CausalFrames.emptyvalue(PlusDM())) == (:plusdm,)
        @test keys(CausalFrames.emptyvalue(ADX(; name = :adx7))) == (:adx7,)
        for ctor in (PlusDM, MinusDM, PlusDI, MinusDI)
            @test_throws ArgumentError ctor(; period = 0)
            @test_throws ArgumentError ctor(; unstable = -1)
        end
        for ctor in (DX, ADX, ADXR)
            @test_throws ArgumentError ctor(; period = 1)
            @test_throws ArgumentError ctor(; period = 100_001)
        end
        # DM reads no close.
        @test keys(
            foldseries(
                PlusDM(; period = 3),
                (high = [1.0, 2.0, 3.0, 5.0],
                    low = [0.0, 1.0, 2.0, 3.0]),
            ),
        ) == (:plusdm,)
    end
end
