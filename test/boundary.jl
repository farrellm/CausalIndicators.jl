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
# step (x − prev)·1 + prev does not give back x, and every 16th close a -0.0
# behind a positive one, which that step turns into +0.0.
function sterbenzhostile()
    i = 0:251
    close = ifelse.(i .% 16 .== 15, -0.0, ifelse.(isodd.(i), 41.37, 124.11))
    open = ifelse.(isodd.(i), 41.53, 123.67)
    volume = Float64.(100003 .+ (i .* 104729) .% 899993)
    return (; open, high = max.(open, close) .+ 0.11, low = min.(open, close) .- 0.11,
        close, volume)
end

# pbCountNegZeroAfterPositive: the -0.0 values of `x` right after a value whose
# sign bit is clear (`missing` counts as neither).
negzeroafterpositive(x) =
    count(i -> isequal(x[i], -0.0) && !ismissing(x[i-1]) && !signbit(x[i-1]), 2:length(x))

# Equal by value at no tolerance, so -0.0 passes for +0.0 (pbCheckSameValues).
valueequal(a, b) =
    length(a) == length(b) &&
    all(((x, y),) -> ismissing(x) ? ismissing(y) : x == y, zip(a, b))

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
        for (s, lb) in
            ((MACD(:close; fastperiod = 2, slowperiod = 7, signalperiod = 1), 6),
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
        @test negzeroafterpositive(sb.close) >= 8
        # Every matype with a period (MAMA's are its fast and slow limits), so a
        # new one cannot slip past; then the named constructors and the
        # structured averages. Each equals its input by value; the sign of a
        # zero is held, bit for bit, only where an EMA-step copy decides it
        # (EMA, DEMA, TEMA and ZLEMA), as test_period_boundary.c holds it.
        matypes = filter(!=(:mama), MATYPES)
        @test length(matypes) == length(MATYPES) - 1
        bits = (:ema, :dema, :tema, :zlema)
        same(m, got, x) = m in bits ? isequal(got, x) : valueequal(got, x)
        for (what, data) in (("reference", ref), ("round-trip-hostile", rt),
            ("Sterbenz-hostile", sb))
            for m in matypes
                got = foldseries(MA(:close; period = 1, matype = m), data).close_ma
                ok = same(m, got, data.close)
                ok || @info "MA(1) is not the input" what m
                @test ok
            end
            for (m, ctor) in ((:ema, EMA), (:rma, RMA), (:dema, DEMA), (:tema, TEMA),
                (:trima, TRIMA), (:kama, KAMA), (:t3, T3), (:hma, HMA), (:zlema, ZLEMA))
                @test same(m, only(foldseries(ctor(:close; period = 1), data)), data.close)
            end
            for s in (Mean(:close), WMA(:close))
                @test valueequal(only(foldseries(s, data; window = Bars(1))), data.close)
            end
            # VWMA under Bars(1) copies its input (TA-Lib #184), where (P·V)/V
            # would lose P on the round-trip series.
            @test valueequal(only(foldseries(VWMA(:close), data; window = Bars(1))),
                data.close)
        end
    end

    @testset "ERI and EFI at period 1 keep the sign of a zero" begin
        # testEriEfiStreamAtPeriodOne: EFI(1) is the raw force, -0.0 where a
        # falling close meets zero volume; ERI(1) is high and low less the close,
        # through an EMA(1) that copies a -0.0 close.
        n, warm = 64, 6
        cl = accumulate((a, i) -> a + (i % 4 == 3 ? -0.37 : 1.21), 1:(n-1); init = 50.13)
        cl = [50.13; cl]
        vol = [i % 4 == 3 ? 0.0 : 1000.0 + 17.0 * i for i in 0:(n-1)]
        efi = foldseries(EFI(; period = 1), (close = cl, volume = vol)).efi
        @test firstvalid(efi) == 1
        @test negzeroafterpositive(efi[(warm+1):end]) > 0
        @test isequal(efi[2:end], diff(cl) .* vol[2:end])
        dead = [i >= warm && i % 4 == 3 for i in 0:(n-1)]
        c2 = ifelse.(dead, -0.0, cl)
        hi, lo = ifelse.(dead, -0.0, cl .+ 1.5), ifelse.(dead, -0.0, cl .- 1.5)
        @test count(i -> dead[i] && c2[i-1] > 0, 2:n) > 0
        o = foldseries(ERI(; period = 1), (high = hi, low = lo, close = c2))
        @test isequal(o.eri_bullpower, hi .- c2) && isequal(o.eri_bearpower, lo .- c2)
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

        # pbMacdNegZeroSeries: after a run of +0.0, five times the smallest
        # subnormal and then its negation round TA-Lib's fast EMA to -0.0, which
        # puts a -0.0 on its MACD line for the signal=1 copy to keep. The
        # compensated EMAs here do not round to -0.0 there, so the line holds
        # none and only the bitwise copy of the line is checked.
        x = zeros(252)
        x[61], x[62] = 5 * nextfloat(0.0), -5 * nextfloat(0.0)
        for s in (MACD(:close; signalperiod = 1), MACDFix(:close; signalperiod = 1),
            MACDExt(:close; fastmatype = :ema, slowmatype = :ema, signalperiod = 1,
                signalmatype = :ema))
            o = foldseries(s, (close = x,))
            @test isequal(o[2], o[1]) && all(iszero, skipmissing(o[3]))
        end
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
            s = foldseries(
                Stoch(; fastkperiod = 5, slowkperiod = 1, slowkmatype = m,
                    slowdperiod = 1, slowdmatype = m), ref)
            @test isequal(s.stoch_slowk, f.stochf_fastk)
            @test isequal(s.stoch_slowd, f.stochf_fastk)
        end
        # STOCHRSI(14, 1, 1): a one-bar %K window has no range, so 0 throughout.
        sr =
            foldseries(StochRSI(:close; period = 14, fastkperiod = 1, fastdperiod = 1), ref)
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
