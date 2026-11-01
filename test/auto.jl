# S9′: TA-Lib 0.8.3's Auto-Stabilization levels as `unstable = :auto4`/`:auto8`.
# The goldens hold both levels for every function a level changes; these pin
# the lookbacks to TA-Lib's closed forms by hand, and the keyword's checks.

using CausalIndicators: AutoLevel, autoadosc

# The 0-based bar of the first value of `s`'s first output over the 10,000-bar
# set, with a volume column for ADOSC: its lookback.
function autolookback(s)
    data = loadgdata()
    data = merge(data, (volume = fill(1000.0, length(data.close)),))
    return findfirst(!ismissing, first(foldseries(s, data))) - 1
end

@testset "auto-stabilization" begin
    @testset "lookbacks are TA-Lib's closed forms" begin
        # (constructor, :auto4 lookback, :auto8 lookback), each worked from the
        # function's TA_<FN>_Lookback in TA-Lib 0.8.3.
        cases = [
            # 29 + (10·30 + 1) ÷ 2, 29 + (19·30 + 1) ÷ 2
            (u -> EMA(:close; unstable = u), 179, 314),
            # A period of 1 does no smoothing: no bars.
            (u -> EMA(:close; period = 1, unstable = u), 0, 0),
            # 13 + (10·27 + 1) ÷ 2
            (u -> RMA(:close; period = 14, unstable = u), 148, 13 + 257),
            # 14 + 10·14 (an output that divides by Wilder sums)
            (u -> RSI(:close; unstable = u), 154, 14 + 266),
            (u -> ATR(; unstable = u), 14 + 135, 14 + 257),
            (u -> NATR(; unstable = u), 154, 280),
            # 2·14 + (10 + 6)·14 − 1, and ADXR's 14 − 1 on top
            (u -> ADX(; unstable = u), 251, 28 + 25 * 14 - 1),
            (u -> ADXR(; unstable = u), 264, 14 + 28 + 25 * 14 - 2),
            # 30 + 25·4·isqrt(30)
            (u -> KAMA(:close; unstable = u), 530, 30 + 25 * 8 * 5),
            # 6·4 + (11·(4 + 4)·5 + 7) ÷ 8
            (u -> T3(:close; unstable = u), 79, 24 + (11 * 12 * 5 + 7) ÷ 8),
            # (13·10 + 8) ÷ 9, (13·19 + 8) ÷ 9
            (u -> HeikinAshi(; unstable = u), 15, 28),
            (u -> HTDCPeriod(:close; unstable = u), 32 + 280, 32 + 480),
            (u -> HTTrendline(:close; unstable = u), 63 + 200, 63 + 280),
            # 32 + 80 + 50·4 + ceil(20 / 0.5)
            (u -> MAMA(:close; unstable = u), 352, 32 + 480 + 76),
            # EMA's at the slow period, then at the signal period
            (u -> MACD(:close; unstable = u), 155 + 53, 25 + 247 + 8 + 86),
            # 9 + (10·10 + 1) ÷ 2 + ADOSC's offset (15·3 + 3·6 + 7) ÷ 8
            (u -> ADOSC(; unstable = u), 67, 9 + 95 + 8),
            # TA_MA reads the dispatched type's id at its own period.
            (u -> MA(:close; matype = :ema, unstable = u), 179, 314),
            # ... and SMA has none.
            (u -> MA(:close; matype = :sma, unstable = u), 29, 29),
        ]
        for (ctor, lb4, lb8) in cases
            @test autolookback(ctor(:auto4)) == lb4
            @test autolookback(ctor(:auto8)) == lb8
        end
    end

    @testset "ADOSC's offset" begin
        # It does not depend on the level, and the order of the periods does
        # not matter; a count adds none.
        @test autoadosc(AutoLevel(10, 4), 3, 10) == 8
        @test autoadosc(AutoLevel(19, 8), 10, 3) == 8
        @test autolookback(ADOSC(; unstable = 2)) == 9 + 2
    end

    @testset "a level is not a count" begin
        # A level gives each id its own count; a count is the same for all.
        @test autolookback(MACD(:close; unstable = 5)) == 25 + 8 + 2 * 5
        @test autolookback(KeltnerChannels(; unstable = :auto4)) ==
              max(19 + (10 * 20 + 1) ÷ 2, 10 + (10 * 19 + 1) ÷ 2)
    end

    @testset "argument checks" begin
        @test_throws ArgumentError EMA(:close; unstable = :auto5)
        @test_throws ArgumentError RSI(:close; unstable = :auto)
        @test_throws ArgumentError EMA(:close; unstable = -1)
        # Without a matype, BollingerBands takes no unstable period.
        @test_throws ArgumentError BollingerBands(:close; unstable = :auto4)
    end

    @testset "zero allocations under a level" begin
        intypes = (time = Int, open = Float64, high = Float64, low = Float64,
            close = Float64)
        rng = Random.MersenneTwister(7)
        for s in (EMA(:close; period = 5, unstable = :auto8),
            MACD(:close; fastperiod = 3, slowperiod = 6, signalperiod = 4,
                unstable = :auto4),
            ADX(; period = 3, unstable = :auto4), HeikinAshi(; unstable = :auto8))
            st = CausalFrames.fresh(s, intypes)
            for x in 100.0 .+ cumsum(randn(rng, 200))
                CausalFrames.update!(
                    st,
                    (time = 1, open = x, high = x + 1, low = x - 1,
                        close = x),
                )
            end
            row = (time = 1, open = 100.0, high = 101.0, low = 99.0, close = 100.5)
            @test allocs(CausalFrames.update!, st, row) == 0
            @test allocs(CausalFrames.value, st) == 0
        end
    end
end
