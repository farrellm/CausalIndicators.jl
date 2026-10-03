# S1 overlap studies: the recursive moving averages, MAVP, and the structured
# WMA, VWMA, MidPoint and MidPrice, against TA-Lib's goldens and tables.

using CausalIndicators: MovingAverageState, MAVPState, UNSTABLE_MATYPES

# TA_MAType's integer order, as the goldens' optInMAType.
const MATYPE_CODES = Dict(0 => :sma, 1 => :ema, 2 => :wma, 3 => :dema, 4 => :tema,
    5 => :trima, 6 => :kama, 7 => :mama, 8 => :t3, 9 => :hma, 12 => :zlema, 13 => :rma)

# The named constructor and TA-Lib default period of each recursive MA.
const NAMED_MA = Dict("EMA" => (EMA, 30), "RMA" => (RMA, 30), "DEMA" => (DEMA, 30),
    "TEMA" => (TEMA, 30), "TRIMA" => (TRIMA, 30), "KAMA" => (KAMA, 30),
    "T3" => (T3, 5), "HMA" => (HMA, 20), "ZLEMA" => (ZLEMA, 30))
const HAS_UNSTABLE = ("EMA", "RMA", "DEMA", "TEMA", "KAMA", "T3", "ZLEMA")

function namedma(fn, p)
    ctor, default = NAMED_MA[fn]
    kw = (; period = get(p, :optInTimePeriod, default))
    fn in HAS_UNSTABLE && (kw = merge(kw, (; unstable = get(p, :unstable, 0))))
    fn == "T3" && (kw = merge(kw, (; vfactor = get(p, :optInVFactor, 0.7))))
    return ctor(:close; kw...)
end

# One of each plain S1 state, for the allocation and JET checks.
const PLAIN_S1 = [
    [
        MA(:close; matype = m, period = 7) for m in
        (:sma, :ema, :wma, :dema, :tema, :trima, :kama, :t3, :hma, :zlema, :rma)
    ]...,
    MAVP(:close, :periods; maxperiod = 12, matype = :kama),
]
const S1_INTYPES = (close = Union{Missing,Float64}, periods = Float64)

# MAVP's golden periods input: 2 + (i mod 29) for 0-based bar i.
mavpperiods(n) = [2.0 + (i % 29) for i in 0:(n-1)]

@testset "overlap" begin
    @testset "$fn goldens" for fn in sort(collect(keys(NAMED_MA)))
        n = checkgoldens(fn; outputs = (:outReal,)) do p, data
            (only(foldseries(namedma(fn, p), data)),)
        end
        @test n >= 2
    end

    @testset "MA goldens" begin
        checkgoldens("MA"; outputs = (:outReal,)) do p, data
            s = MA(:close; period = get(p, :optInTimePeriod, 30),
                matype = MATYPE_CODES[get(p, :optInMAType, 0)],
                unstable = get(p, :unstable, 0))
            (foldseries(s, data).close_ma,)
        end
    end

    @testset "MAVP goldens" begin
        checkgoldens("MAVP"; outputs = (:outReal,)) do p, data
            s = MAVP(:close, :periods; minperiod = get(p, :optInMinPeriod, 2),
                maxperiod = get(p, :optInMaxPeriod, 30),
                matype = MATYPE_CODES[get(p, :optInMAType, 0)])
            t = merge(data, (periods = mavpperiods(length(data.close)),))
            (foldseries(s, t).close_mavp,)
        end
    end

    @testset "structured goldens" begin
        for (fn, s, out, default) in (("WMA", WMA(:close), :w_close_wma, 30),
            ("SMA", Mean(:close), :w_close_mean, 30),
            ("VWMA", VWMA(:close), :w_close_vwma, 30),
            ("MIDPOINT", MidPoint(:close), :w_close_midpoint, 14),
            ("MIDPRICE", MidPrice(), :w_midprice, 14))
            checkgoldens(fn; outputs = (:outReal,)) do p, data
                w = Bars(get(p, :optInTimePeriod, default))
                (foldseries(s, data; window = w)[out],)
            end
        end
    end

    @testset "test_ma.c table rows" begin
        close = loadref().close
        rows = loadtable("test_ma")["tables"]["tableTest"]["rows"]
        named = Dict(:ema => EMA, :wma => nothing, :dema => DEMA, :tema => TEMA,
            :trima => TRIMA, :kama => KAMA, :t3 => T3, :sma => nothing)
        n = 0
        for r in rows
            r["id"] == "TA_ANY_MA_TEST" || continue
            m = Symbol(lowercase(replace(r["optInMAType_1"], "TA_MAType_" => "")))
            m === :mama && continue  # S6
            p = r["optInTimePeriod"]
            if r["expectedRetCode"] == "TA_BAD_PARAM"
                @test_throws ArgumentError MA(:x; period = p, matype = m)
                continue
            end
            u = r["unstablePeriod"]
            lb = CausalIndicators.MAKernel(Float64, m, p; unstable = u).lookback
            s0, e0 = r["startIdx"], r["endIdx"]
            viama = tablerun((; close), s0, e0, lb) do d
                foldseries(MA(:close; period = p, matype = m, unstable = u), d).close_ma
            end
            checkrow(viama, r)
            ctor = named[m]
            if ctor !== nothing && p > 1
                kw = m === :trima ? (; period = p) : (; period = p, unstable = u)
                vianamed = tablerun((; close), s0, e0, lb) do d
                    only(foldseries(ctor(:close; kw...), d))
                end
                @test isequal(vianamed, viama)
            end
            n += 1
        end
        @test n >= 80
    end

    @testset "test_zlema.c oracles" begin
        close = loadref().close
        # zlemaPandas10, zlemaPandas30 (output index => value) and zlemaTulip10
        # (absolute bar => value), at the C test's 1e-12 tolerance.
        pandas10 = [0 => 94.4185, 7 => 89.18387347894159, 22 => 87.68868876054243,
            37 => 89.97653283175656, 64 => 99.56766011033952, 87 => 114.58403109683026,
            112 => 130.74571000861027, 137 => 121.78172611073379,
            162 => 134.35563908057492, 187 => 106.4477445208301,
            212 => 105.65542066577297, 238 => 108.64427272744322]
        pandas30 = [0 => 83.47700000000002, 7 => 87.23894645913948,
            32 => 89.76469129270977, 57 => 119.60187628580154,
            82 => 127.58051378758816, 107 => 122.63183495348304,
            132 => 130.58827511141902, 157 => 108.98615382445496,
            182 => 96.27201161913554, 208 => 109.59533608422609]
        tulip10 = [190 => 119.85022761490855, 210 => 95.750772869804237,
            235 => 117.53789362762379]
        for (period, beg, nb, pts, absolute) in ((10, 13, 239, pandas10, false),
            (30, 43, 209, pandas30, false), (10, 13, 239, tulip10, true))
            got = foldseries(ZLEMA(:close; period), (; close)).close_zlema
            @test findfirst(!ismissing, got) - 1 == beg
            @test count(!ismissing, got) == nb
            for (i, want) in pts
                bar = absolute ? i : beg + i
                @test isapprox(got[bar+1], want; rtol = 1e-12, atol = 1e-12)
            end
        end
        # Period 1 copies the input; ZLEMA's lookback inherits EMA's unstable.
        @test isequal(foldseries(ZLEMA(:close; period = 1), (; close)).close_zlema, close)
        got = foldseries(ZLEMA(:close; period = 10, unstable = 3), (; close)).close_zlema
        @test findfirst(!ismissing, got) - 1 == 13 + 3
    end

    @testset "test_wma.c drift and contamination (W2, W3)" begin
        rng = Random.MersenneTwister(0xBEEF)
        n = 8000
        y = Vector{Float64}(undef, n)
        y[1] = 100.0
        for i in 2:n
            y[i] = y[i-1] * (1 + 0.015 * (2rand(rng) - 1))
        end
        spiked = copy(y)
        spiked[61] *= 1000
        # The definition, exactly: each window's weighted sum in BigFloat.
        exact(y, p, i) = Float64(sum(big(k) * y[i-p+k] for k in 1:p) / (p * (p + 1) / 2))
        for p in (2, 5, 14, 30)
            got = foldseries(WMA(:y), (; y); window = Bars(p)).w_y_wma
            errs = [abs(got[i] - exact(y, p, i)) for i in p:n]
            q = length(errs) ÷ 4
            first_, last_ = maximum(errs[1:q]), maximum(errs[(3q+1):end])
            @test last_ <= 5 * first_ + 1e-12
            gots = foldseries(WMA(:y), (; y = spiked); window = Bars(p)).w_y_wma
            past = (61+p):n
            @test maximum(abs(gots[i] - exact(spiked, p, i)) for i in past) <= 1e-10
        end
    end

    @testset "test_mavp.c oracle" begin
        close = loadref().close
        n = length(close)
        rng = Random.MersenneTwister(11)
        # Fractional, NaN, below-minimum and above-maximum periods.
        periods = [
            rand(rng, (NaN, -3.0, 0.5, 1.0, 2.7, 4.0, 7.9, 11.0, 15.5, 40.0, 1e9))
            for _ in 1:n
        ]
        clampp(x, lo, hi) = !(x >= lo) ? lo : x > hi ? hi : trunc(Int, x)
        for m in (:sma, :ema, :wma, :dema, :tema, :trima, :kama, :t3, :hma, :zlema, :rma),
            (lo, hi, u) in ((2, 12, 0), (1, 9, 2), (5, 5, 0))

            u = m in UNSTABLE_MATYPES ? u : 0
            got = foldseries(
                MAVP(:close, :periods; minperiod = lo, maxperiod = hi,
                    matype = m, unstable = u), (; close, periods)).close_mavp
            L = CausalIndicators.MAKernel(Float64, m, hi; unstable = u).lookback
            @test findfirst(!ismissing, got) - 1 == min(L, n)
            for p in lo:hi
                # TA_MA(p) started at MAVP's first output, as ta_MAVP.c calls it.
                lbp = CausalIndicators.MAKernel(Float64, m, p; unstable = u).lookback
                want = tablerun((; close), L, n - 1, lbp) do d
                    foldseries(MA(:close; period = p, matype = m, unstable = u), d).close_ma
                end
                for i in (L+1):n
                    clampp(periods[i], lo, hi) == p || continue
                    @test isequal(got[i], want[i])
                end
            end
        end
        @test_throws ArgumentError MAVP(:x, :p; minperiod = 5, maxperiod = 4)
        @test_throws ArgumentError MAVP(:x, :p; minperiod = 0)
        @test_throws ArgumentError MAVP(:x, :p; matype = :mama)
        # A missing period emits missing; the kernels still step.
        t = (
            x = collect(1.0:10.0),
            p = Union{Missing,Float64}[3, 3, 3, missing, 3, 3, 3, 3,
                3, 3],
        )
        got = foldseries(MAVP(:x, :p; minperiod = 2, maxperiod = 3), t).x_mavp
        @test ismissing(got[4]) && got[5] == 4.0
    end

    @testset "constructors" begin
        @test only(keys(CausalFrames.emptyvalue(EMA(:close)))) == :close_ema
        @test only(keys(CausalFrames.emptyvalue(EMA(:close; name = :ema7)))) == :close_ema7
        @test only(keys(CausalFrames.emptyvalue(MA(:close; matype = :t3)))) == :close_ma
        @test only(keys(CausalFrames.emptyvalue(MAVP(:close, :p)))) == :close_mavp
        @test only(keys(CausalFrames.emptyvalue(MidPrice()))) == :midprice
        @test only(keys(CausalFrames.emptyvalue(VWMA(:close)))) == :close_vwma
        for ctor in (EMA, RMA, DEMA, TEMA, TRIMA, KAMA, T3, HMA, ZLEMA)
            @test_throws ArgumentError ctor(:x; period = 0)
            @test_throws ArgumentError ctor(:x; period = 100_001)
        end
        @test_throws ArgumentError EMA(:x; unstable = -1)
        @test_throws ArgumentError T3(:x; vfactor = 1.5)
        @test_throws ArgumentError MA(:x; matype = :nope)
        @test_throws ArgumentError MA(:x; matype = :mama)
        # TA_MA ignores the unstable period of types that have none.
        @test isequal(foldseries(MA(:close; matype = :wma, unstable = 3), loadref()),
            foldseries(MA(:close; matype = :wma), loadref()))
        # Two periods in one call, through `name`.
        out = foldseries([EMA(:close; period = 5, name = :ema5), EMA(:close)], loadref())
        @test keys(out) == (:close_ema5, :close_ema)
        # Row terms.
        r = loadref()
        hl = row -> row.high - row.low
        out = foldseries(EMA(:hl => hl; period = 5), r)
        @test isequal(
            out.hl_ema,
            foldseries(EMA(:hl; period = 5), (; hl = r.high .- r.low)).hl_ema,
        )
    end

    @testset "period 1 copies the input" begin
        close = loadref().close
        for ctor in (EMA, RMA, DEMA, TEMA, TRIMA, KAMA, T3, HMA, ZLEMA)
            @test isequal(only(foldseries(ctor(:close; period = 1), (; close))), close)
        end
        for m in (:sma, :ema, :wma, :dema, :tema, :trima, :kama, :t3, :hma, :zlema, :rma)
            @test isequal(
                foldseries(MA(:close; period = 1, matype = m, unstable = 2),
                    (; close)).close_ma, close)
        end
        # The named functions keep their own period-1 lookback (ta_DEMA.c).
        got = foldseries(DEMA(:close; period = 1, unstable = 2), (; close)).close_dema
        @test findfirst(!ismissing, got) - 1 == 4
    end

    @testset "missing bars are skipped" begin
        x = collect(1.0:12.0)
        xm = Union{Missing,Float64}[]
        for v in x
            push!(xm, missing, v)
        end
        for s in (EMA(:x; period = 3), KAMA(:x; period = 3), T3(:x; period = 2),
            HMA(:x; period = 4), ZLEMA(:x; period = 3), TRIMA(:x; period = 4))
            want = only(foldseries(s, (; x)))
            got = only(foldseries(s, (; x = xm)))
            @test all(ismissing, got[1:2:end])
            @test isequal(got[2:2:end], want)
        end
    end

    @testset "streaming properties" begin
        r = loadref()
        t = (close = r.close[1:120], volume = r.volume[1:120], high = r.high[1:120],
            low = r.low[1:120], periods = mavpperiods(120))
        for s in
            (EMA(:close; period = 10), DEMA(:close; period = 7), TEMA(:close; period = 5),
            T3(:close), KAMA(:close; period = 10), TRIMA(:close; period = 10),
            HMA(:close; period = 9), ZLEMA(:close; period = 10), RMA(:close; period = 14),
            MA(:close; matype = :wma, period = 10), MAVP(:close, :periods; maxperiod = 12))
            checkstreaming(s, t)
        end
        for s in (WMA(:close), VWMA(:close), MidPoint(:close), MidPrice())
            checkstreaming(s, t; window = Bars(14), timewindow = 13)
        end
    end

    @testset "zero allocations" begin
        row = (time = 1, close = 101.5, periods = 7.0)
        mrow = (time = 1, close = missing, periods = 7.0)
        for s in PLAIN_S1
            st = CausalFrames.fresh(s, S1_INTYPES)
            for x in 100.0 .+ randn(Random.MersenneTwister(1), 40)
                CausalFrames.update!(st, (time = 1, close = x, periods = 7.0))
            end
            @test allocs(CausalFrames.update!, st, row) == 0
            @test allocs(CausalFrames.update!, st, mrow) == 0
            @test allocs(CausalFrames.value, st) == 0
            @test allocs(fresh!, st) == 0
        end
    end
end
