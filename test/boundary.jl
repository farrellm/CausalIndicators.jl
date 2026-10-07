# test_period_boundary.c: the period-1 and minimum-period boundaries. Its
# abstract parameter sweep (testMinBoundarySweep) is not here: every function's
# goldens carry the sweep's grid, and `checkgoldens` requires an ArgumentError
# for each set TA-Lib rejects (gen/golden/generate.jl).

using CausalIndicators: MATYPES

firstvalid(v) = findfirst(!ismissing, v) - 1

# pbFillRoundTripHostileHistory: two-decimal prices and six-digit volumes, on
# which (P·V)/V does not give back P.
function roundtriphostile()
    i = 0:251
    close = (10000 .+ (i .* 7919) .% 20000) ./ 100.0
    open = (10000 .+ (i .* 5417) .% 20000) ./ 100.0
    volume = Float64.(100003 .+ (i .* 104729) .% 899993)
    return (; open, high = max.(open, close) .+ 0.25, low = min.(open, close) .- 0.25,
        close, volume)
end

# pbFillSterbenzHostileHistory: alternating ~3× moves, where the period-1 EMA
# step (x − prev)·1 + prev does not give back x.
function sterbenzhostile()
    i = 0:251
    close = ifelse.(isodd.(i), 41.37, 124.11)
    open = ifelse.(isodd.(i), 41.53, 123.67)
    volume = Float64.(100003 .+ (i .* 104729) .% 899993)
    return (; open, high = max.(open, close) .+ 0.11, low = min.(open, close) .- 0.11,
        close, volume)
end

# The bars on which the naive period-1 EMA step loses its input.
function naiveemaloss(x)
    n, prev = 0, x[1]
    for v in @view x[2:end]
        prev = ((v - prev) * 1.0) + prev
        n += prev != v
    end
    return n
end

@testset "period boundaries (test_period_boundary.c)" begin
    ref = loadref()

    @testset "every golden's sweep was checked" begin
        # The rejected sets are only tested through checkgoldens, so a golden
        # read any other way would drop its sweep silently. This file runs last.
        goldens = Set(replace.(readdir(joinpath(TESTDIR, "golden")), ".csv.gz" => ""))
        @test length(goldens) == 182
        @test setdiff(goldens, CHECKED_GOLDENS) == Set{String}()
    end

    @testset "lookbacks at period 1" begin
        # SourceForge bug 84: TA_MACD_Lookback(2, 7, 1) == 6.
        for (s, lb) in ((MACD(:close; fastperiod = 2, slowperiod = 7, signalperiod = 1), 6),
            (MACD(:close; fastperiod = 2, slowperiod = 7, signalperiod = 2), 7),
            (MACD(:close; fastperiod = 12, slowperiod = 26, signalperiod = 1), 25),
            (MACDFix(:close; signalperiod = 1), 25),
            (TRIX(:close; period = 1), 1),
            (ULTOSC(; timeperiod1 = 1, timeperiod2 = 1, timeperiod3 = 1), 1))
            @test all(o -> firstvalid(o) == lb, foldseries(s, ref))
        end
        mavp = MAVP(:close, :periods; minperiod = 1, maxperiod = 2, matype = :sma)
        got = foldseries(mavp, merge(ref, (periods = ones(252),))).close_mavp
        @test firstvalid(got) == 1
        # Every output of MAVP with all periods 1 is the input.
        @test isequal(got[2:end], ref.close[2:end])
        # The identity holds under an unstable period, which only delays it.
        got = foldseries(EMA(:close; period = 1, unstable = 3), ref).close_ema
        @test firstvalid(got) == 3
        @test isequal(got[4:end], ref.close[4:end])
    end

    @testset "every moving average copies its input at period 1" begin
        rt, sb = roundtriphostile(), sterbenzhostile()
        # The series must be hostile, or the sweep is a benign rerun.
        @test count(i -> (rt.close[i] * rt.volume[i]) / rt.volume[i] != rt.close[i],
            1:252) >= 8
        @test naiveemaloss(sb.close) >= 32
        # Every matype with a period (MAMA's are its fast and slow limits), so a
        # new one cannot slip past; then the named constructors and the
        # structured averages.
        matypes = filter(!=(:mama), MATYPES)
        @test length(matypes) == length(MATYPES) - 1
        for (what, data) in (("reference", ref), ("round-trip-hostile", rt),
            ("Sterbenz-hostile", sb))
            for m in matypes
                got = foldseries(MA(:close; period = 1, matype = m), data).close_ma
                ok = isequal(got, data.close)
                ok || @info "MA(1) is not the input" what m
                @test ok
            end
            for ctor in (EMA, RMA, DEMA, TEMA, TRIMA, KAMA, T3, HMA, ZLEMA)
                @test isequal(only(foldseries(ctor(:close; period = 1), data)), data.close)
            end
            for s in (Mean(:close), WMA(:close))
                @test isequal(only(foldseries(s, data; window = Bars(1))), data.close)
            end
            # VWMA under Bars(1) is (P·V)/V, which loses P on the round-trip
            # series: the defect TA-Lib #184 fixed with a period-1 copy. The
            # dependent cannot see its window's size, so the copy needs a
            # change of design, not a test edit.
            vwma = only(foldseries(VWMA(:close), data; window = Bars(1)))
            if what == "reference"
                @test isequal(vwma, data.close)
            else
                @test_broken isequal(vwma, data.close)
            end
        end
    end

    @testset "MACD family at signal period 1" begin
        # The signal line is the MACD line and the histogram exactly 0.
        signalisline(o) = (o = map(collect ∘ skipmissing, Tuple(o));
        o[2] == o[1] && all(iszero, o[3]))
        outs(s) = foldseries(s, ref)
        sig1 = outs(MACD(:close; signalperiod = 1))
        @test firstvalid(sig1[1]) == 25
        @test signalisline(sig1)
        # Neither shifted nor rescaled against signal period 2.
        sig2 = outs(MACD(:close; signalperiod = 2))
        @test isequal(sig2[1][27:end], sig1[1][27:end])
        @test signalisline(outs(MACDFix(:close; signalperiod = 1)))
        for m in MATYPES
            s = MACDExt(:close; fastmatype = :sma, slowmatype = :sma, signalperiod = 1,
                signalmatype = m)
            @test signalisline(outs(s))
        end
        @test signalisline(outs(MACD(:close; signalperiod = 1, unstable = 3)))

        # testMacdSignalOneHostile: a grid of flat runs, where the MACD line
        # leaves the factor-of-two band the naive signal step needs. Each
        # function's line must defeat that step somewhere on the grid.
        runs = loadtable("test_period_boundary")["arrays"]
        losses = zeros(Int, 3)
        for r in runs["pbMacdRuns"]["values"],
            (lo, hi) in zip(runs["pbMacdLo"]["values"], runs["pbMacdHi"]["values"])

            x = [isodd(i ÷ r) ? lo : hi for i in 0:251]
            for (k, s) in enumerate((MACD(:close; signalperiod = 1),
                MACDFix(:close; signalperiod = 1),
                MACDExt(:close; fastmatype = :ema, slowmatype = :ema,
                    signalperiod = 1, signalmatype = :ema)))
                o = foldseries(s, (close = x,))
                @test signalisline(o)
                losses[k] += naiveemaloss(collect(skipmissing(o[1])))
            end
        end
        @test all(>=(1), losses)
    end

    @testset "period-1 pins" begin
        h, l, c = ref.high, ref.low, ref.close
        tr = foldseries(TRange(), ref; window = Bars(2)).w_trange
        # ULTOSC(1, 1, 1): one bar's buying pressure over its true range.
        u = foldseries(ULTOSC(; timeperiod1 = 1, timeperiod2 = 1, timeperiod3 = 1),
            ref).ultosc
        want = map(2:252) do i
            lo, hi = min(l[i], c[i-1]), max(h[i], c[i-1])
            hi == lo ? 0.0 : 100 * (c[i] - lo) / (hi - lo)
        end
        @test all(isapprox.(u[2:end], want; atol = 1e-9))

        # A smoothing period of 1 is transparent: STOCHF(5, 1) is the raw %K,
        # and STOCH(5, 1, 1) gives it as both lines, SMA or EMA.
        f = foldseries(StochF(; fastkperiod = 5, fastdperiod = 1), ref)
        rawk = map(5:252) do i
            hh, ll = maximum(h[(i-4):i]), minimum(l[(i-4):i])
            hh == ll ? 0.0 : 100 * (c[i] - ll) / (hh - ll)
        end
        @test firstvalid(f.stochf_fastk) == 4
        @test all(isapprox.(f.stochf_fastk[5:end], rawk; atol = 1e-9))
        @test isequal(f.stochf_fastd, f.stochf_fastk)
        for m in (:sma, :ema)
            s = foldseries(Stoch(; fastkperiod = 5, slowkperiod = 1, slowkmatype = m,
                    slowdperiod = 1, slowdmatype = m), ref)
            @test isequal(s.stoch_slowk, f.stochf_fastk)
            @test isequal(s.stoch_slowd, f.stochf_fastk)
        end
        # STOCHRSI(14, 1, 1): a one-bar %K window has no range, so 0 throughout.
        sr = foldseries(StochRSI(:close; period = 14, fastkperiod = 1, fastdperiod = 1), ref)
        @test all(o -> firstvalid(o) == 14 && all(iszero, skipmissing(o)), sr)

        mom = foldseries(MOM(:close), ref; window = Bars(2)).w_close_mom
        @test all(isapprox.(mom[2:end], diff(c); atol = 1e-9))
        roc = foldseries(ROC(:close), ref; window = Bars(2)).w_close_roc
        @test firstvalid(roc) == 1
        # TRIX(1) is three identity EMAs and a one-bar rate of change.
        trix = foldseries(TRIX(:close; period = 1), ref).close_trix
        @test firstvalid(trix) == 1
        @test all(isapprox.(trix[2:end], roc[2:end]; atol = 1e-9))

        # The degenerate one-bar windows. TA-Lib gives CORREL(1) 0; CausalFrames'
        # Correlation gives NaN for a flat window (DESIGN.md, "Testing").
        var = foldseries(Variance(:close; corrected = false), ref; window = Bars(1))
        @test all(x -> abs(x) <= 1e-9, only(var))
        cor = foldseries(Correlation(:high, :low), ref; window = Bars(1))
        @test all(isnan, only(cor))
        beta = foldseries(Beta(:high, :low; period = 1), ref).high_low_beta
        @test firstvalid(beta) == 1
        @test all(x -> abs(x) <= 1e-9, skipmissing(beta))
    end

    @testset "LINEARREG family past period 1024" begin
        # testLinearRegRampOverflowProbe (#142): an exact ramp's fit at a period
        # whose Σx² overflowed TA-Lib's int32.
        p, base, step = 1025, 100.0, 0.25
        ramp = (x = base .+ step .* (0:1029),)
        want = Dict(LinearReg => t -> base + step * t, LinearRegSlope => t -> step,
            LinearRegIntercept => t -> base + step * (t - p + 1),
            TSF => t -> base + step * (t + 1), LinearRegAngle => t -> atand(step))
        for (ctor, f) in want
            got = only(foldseries(ctor(:x), ramp; window = Bars(p)))
            @test count(!ismissing, got) == 1030 - (p - 1)
            @test all(t -> isapprox(got[t+1], f(t); atol = 1e-6 * (abs(f(t)) + 1)),
                (p-1):1029)
        end
    end
end
