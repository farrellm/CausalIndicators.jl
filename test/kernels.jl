using CausalIndicators: EMAKernel, WilderKernel, SMAKernel, MAKernel, MATYPES, step!,
    current, nseen, lookback, floattype, WMAKernel, DEMAKernel, TEMAKernel, T3Kernel,
    TRIMAKernel, KAMAKernel, HMAKernel, ZLEMAKernel

# One of every S1 kernel, for the generic kernel properties.
const S1_KERNELS =
    (() -> WMAKernel(Float64, 5), () -> DEMAKernel(Float64, 5; unstable = 1),
        () -> TEMAKernel(Float64, 4), () -> T3Kernel(Float64, 3, 0.5),
        () -> TRIMAKernel(Float64, 6), () -> KAMAKernel(Float64, 5),
        () -> HMAKernel(Float64, 9),
        () -> ZLEMAKernel(Float64, 6), () -> MAKernel(Float64, :dema, 5; unstable = 2))

# Run a kernel over a series as an indicator would, with `unstable` extra
# warm-up bars: `missing` until it has seen lookback + unstable + 1 bars.
function runkernel(k, xs; unstable = 0)
    out = Vector{Union{Missing,Float64}}(undef, length(xs))
    for (i, x) in enumerate(xs)
        v = step!(k, x)
        out[i] = nseen(k) > lookback(k) + unstable ? v : missing
    end
    return out
end

# The extracted TA-Lib table rows for one MA type that check a value.
function marows(matype)
    rows = loadtable("test_ma")["tables"]["tableTest"]["rows"]
    return [
        r for r in rows if r["optInMAType_1"] == matype &&
            r["id"] == "TA_ANY_MA_TEST" && r["expectedRetCode"] == "TA_SUCCESS" &&
            r["startIdx"] == 0 && r["expectedNbElement"] > 0
    ]
end

const KERNELS =
    Dict("EMA" => (p, T) -> EMAKernel(T, p), "RMA" => (p, T) -> WilderKernel(T, p))

@testset "kernels" begin
    @testset "floattype" begin
        @test floattype(Int) === Float64
        @test floattype(Union{Missing,Int32}) === Float64
        @test floattype(Float32) === Float64
        @test floattype(BigFloat) === BigFloat
    end

    @testset "$fn goldens" for fn in ("EMA", "RMA")
        mk = KERNELS[fn]
        for ((ds, ps), want) in loadgolden(fn)
            p = parseparams(ps)
            period = get(p, :optInTimePeriod, 30)
            unstable = get(p, :unstable, 0)
            got = runkernel(mk(period, Float64), DATASETS[ds]().close; unstable)
            @test goldenmatch(got, want.outReal; rtol = 1e-9)
        end
    end

    @testset "EMA table rows (test_ma.c)" begin
        close = loadref().close
        rows = marows("TA_MAType_EMA")
        @test length(rows) >= 10
        for r in rows
            got = runkernel(EMAKernel(Float64, r["optInTimePeriod"]), close;
                unstable = r["unstablePeriod"])
            @test findfirst(!ismissing, got) - 1 == r["expectedBegIdx"]
            @test count(!ismissing, got) == r["expectedNbElement"]
            want = r["oneOfTheExpectedOutReal"]
            bar = r["expectedBegIdx"] + r["oneOfTheExpectedOutRealIndex"]
            @test got[bar+1] ≈ want atol = 10.0^-decimals(want)
        end
    end

    @testset "SMA table rows (test_ma.c)" begin
        close = loadref().close
        rows = marows("TA_MAType_SMA")
        @test length(rows) >= 5
        for r in rows
            got = runkernel(MAKernel(Float64, :sma, r["optInTimePeriod"]), close)
            @test findfirst(!ismissing, got) - 1 == r["expectedBegIdx"]
            want = r["oneOfTheExpectedOutReal"]
            bar = r["expectedBegIdx"] + r["oneOfTheExpectedOutRealIndex"]
            @test got[bar+1] ≈ want atol = 10.0^-decimals(want)
        end
    end

    @testset "RMA oracles (test_rma.c)" begin
        t = loadtable("test_rma")["tables"]
        crossing = [((i * 37) % 401 - 200) / 8.0 for i in 0:251]
        for (name, xs, rtol, atol) in (("rmaPandasClose", loadref().close, 1e-12, 1e-12),
            ("rmaPandasCross", crossing, 1e-12, 1e-12),
            ("rmaTulipClose", loadref().close, 1e-14, 1e-13),
            ("rmaTulipCross", crossing, 1e-14, 1e-13))
            rows = t[name]["rows"]
            @test !isempty(rows)
            for r in rows
                got = runkernel(WilderKernel(Float64, r["period"]), xs)
                @test isapprox(got[r["bar"]+1], r["want"]; rtol, atol)
            end
        end
    end

    @testset "Wilder :sum form" begin
        xs = [3.0, 1.0, 4.0, 1.0, 5.0, 9.0, 2.0, 6.0]
        p = 4
        k = WilderKernel(Float64, p; form = :sum, seedn = p - 1)
        @test lookback(k) == p - 2
        got = [step!(k, x) for x in xs]
        ref = Union{Missing,Float64}[missing, missing]
        s = sum(xs[1:(p-1)])
        push!(ref, s)
        for x in xs[p:end]
            s = s - s * (1 / p) + x
            push!(ref, s)
        end
        @test isequal(got, ref)
    end

    @testset "missing is skipped" begin
        for mk in (p -> EMAKernel(Float64, p), p -> WilderKernel(Float64, p),
            p -> SMAKernel(Float64, p), p -> MAKernel(Float64, :ema, p),
            p -> WMAKernel(Float64, p), p -> DEMAKernel(Float64, p),
            p -> TEMAKernel(Float64, p), p -> T3Kernel(Float64, p),
            p -> TRIMAKernel(Float64, p), p -> KAMAKernel(Float64, p),
            p -> HMAKernel(Float64, p), p -> ZLEMAKernel(Float64, p),
            p -> MAKernel(Float64, :kama, p; unstable = 1))
            xs = [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 8.0, 7.0, 9.0, 11.0, 10.0, 12.0, 15.0, 13.0]
            a = mk(3)
            b = mk(3)
            wantb = [step!(b, x) for x in xs]
            got = Union{Missing,Float64}[]
            for x in xs
                @test ismissing(step!(a, missing))
                push!(got, step!(a, x))
            end
            @test isequal(got, wantb)
            @test nseen(a) == length(xs)
        end
    end

    @testset "fresh and fresh!" begin
        xs = randn(Random.MersenneTwister(1), 50)
        for mk in (() -> EMAKernel(Float64, 5), () -> WilderKernel(Float64, 5),
            () -> WilderKernel(Float64, 5; form = :sum, seedn = 4),
            () -> SMAKernel(Float64, 5), () -> MAKernel(Float64, :rma, 5), S1_KERNELS...)
            k = mk()
            first_ = [step!(k, x) for x in xs]
            @test isequal(current(k), first_[end])
            fresh!(k)
            @test nseen(k) == 0 && ismissing(current(k))
            @test isequal([step!(k, x) for x in xs], first_)
            k2 = fresh(k)
            @test typeof(k2) === typeof(k) && nseen(k2) == 0
            @test isequal([step!(k2, x) for x in xs], first_)
        end
    end

    @testset "integer and Float32 inputs" begin
        k = EMAKernel(floattype(Int), 3)
        @test isequal([step!(k, x) for x in 1:5], [missing, missing, 2.0, 3.0, 4.0])
        k = EMAKernel(floattype(Float32), 3)
        @test step!(k, 1.0f0) isa Missing
    end

    @testset "MAKernel" begin
        @test length(MATYPES) == 12
        for (m, K) in ((:sma, SMAKernel), (:ema, EMAKernel), (:rma, WilderKernel),
            (:wma, WMAKernel), (:dema, DEMAKernel), (:tema, TEMAKernel), (:t3, T3Kernel),
            (:trima, TRIMAKernel), (:kama, KAMAKernel), (:hma, HMAKernel),
            (:zlema, ZLEMAKernel))
            @test MAKernel(Float64, m, 5).inner isa K
        end
        # TA-Lib's lookbacks (ta_MA.c dispatch) at period 7, unstable 2.
        for (m, lb) in ((:sma, 6), (:ema, 8), (:wma, 6), (:dema, 16), (:tema, 24),
            (:trima, 6), (:kama, 9), (:t3, 38), (:hma, 7), (:zlema, 11), (:rma, 8))
            @test lookback(MAKernel(Float64, m, 7; unstable = 2)) == lb
            # TA_MA copies at period 1 with lookback 0, whatever the unstable period.
            @test lookback(MAKernel(Float64, m, 1; unstable = 2)) == 0
        end
        @test lookback(MAKernel(Float64, :dema, 1; unstable = 2, identity = false)) == 4
        @test lookback(MAKernel(Float64, :kama, 1; unstable = 2, identity = false)) == 2
        @test_throws ArgumentError MAKernel(Float64, :mama, 5)
        @test_throws ArgumentError MAKernel(Float64, :ema, 5; unstable = -1)
        @test_throws ArgumentError T3Kernel(Float64, 5, 1.5)
        @test_throws ArgumentError MAKernel(Float64, :nope, 5)
        @test_throws ArgumentError EMAKernel(Float64, 0)
        @test_throws ArgumentError WilderKernel(Float64, 5; form = :median)
    end

    @testset "zero allocations" begin
        xs = randn(Random.MersenneTwister(2), 100)
        for k in (EMAKernel(Float64, 5), WilderKernel(Float64, 5),
            WilderKernel(Float64, 5; form = :sum), SMAKernel(Float64, 5),
            MAKernel(Float64, :sma, 5), map(mk -> mk(), S1_KERNELS)...)
            foreach(x -> step!(k, x), xs)
            @test allocs(step!, k, 1.5) == 0
            @test allocs(step!, k, missing) == 0
            @test allocs(fresh!, k) == 0
        end
    end
end
