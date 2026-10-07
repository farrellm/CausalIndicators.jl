# test_reference.c: TA-Lib's shared numerical-reference battery
# (ta_test_reference.c and its exact-rational goldens), and the legs of
# test_correl.c, test_beta.c, test_linearreg.c, test_wma.c, test_stddev.c and
# test_bbands.c that are refereed by it.
#
# TA-Lib referees with a double-double oracle and checks that oracle against the
# goldens. Here the oracle is exact: every input is a double, so every sum and
# product is a `Rational{BigInt}`, rounded once at the end.

const REF = loadtable("ta_test_reference")
refarr(name) = Float64.(REF["arrays"]["ta_test_ref_$name"]["values"])
refdef(name) = REF["defines"]["TA_TEST_REF_$name"]

const WILKINSON = ["x", "round", "big", "little", "huge", "tiny", "zero"]
const LADDER_PERIODS = Int.(refarr("golden_ladder_periods"))

exact(v) = Rational{BigInt}.(v)
roundexact(q) = setprecision(() -> Float64(BigFloat(numerator(q)) / denominator(q)), 320)
sqrtexact(q) =
    setprecision(() -> Float64(sqrt(BigFloat(numerator(q)) / denominator(q))), 320)

# The window's deviations scaled by n, n·x − Σx, exact.
devs(w) = (q = exact(w); length(q) .* q .- sum(q))

isconstant(w) = all(==(first(w)), w)

"""Population variance of the window `w`, exact, rounded once."""
refvar(w) = isconstant(w) ? 0.0 : roundexact(sum(devs(w) .^ 2) / length(w)^3)
refstd(w) = isconstant(w) ? 0.0 : sqrtexact(sum(devs(w) .^ 2) / length(w)^3)
refmean(w) = roundexact(sum(exact(w)) / length(w))

"""Pearson r of two windows, exactly rounded; 0 where either is constant, as
TA-Lib's oracle gives."""
function refcorr(x, y)
    (isconstant(x) || isconstant(y)) && return 0.0
    dx, dy = devs(x), devs(y)
    sxy = sum(dx .* dy)
    return sign(sxy) * sqrtexact(sxy^2 / (sum(dx .^ 2) * sum(dy .^ 2)))
end

"""OLS slope of `y` on `x` and the conditioning max|x| / rms deviation of x."""
function refslope(x, y)
    isconstant(x) && return 0.0, 0.0
    dx, dy = devs(x), devs(y)
    sxx = sum(dx .^ 2)
    n = length(x)
    kappa = maximum(abs, x) / sqrtexact(sxx / n^3)
    return roundexact(sum(dx .* dy) / sxx), kappa
end

"""Slope, intercept, fit and forecast of `y` against 0:n-1, exact."""
function reflinreg(y)
    n = length(y)
    q = exact(y)
    ybar = sum(q) / n
    n == 1 && return 0.0, y[1], y[1], y[1]
    t = big.(0:(n-1)) .- (n - 1) // 2
    m = sum(t .* (q .- ybar)) / sum(t .^ 2)
    return roundexact(m), roundexact(ybar - m * (n - 1) // 2),
    roundexact(ybar + m * (n - 1) // 2), roundexact(ybar + m * (n + 1) // 2)
end

refwma(y) = roundexact(sum(exact(y) .* (1:length(y))) / (length(y) * (length(y) + 1) // 2))

"""NIST StRD NumAcc1–4 as ta_test_ref_numacc builds them."""
function numacc(which)
    base = (1.0e7, 0.0, 999999.0, 9999999.0)[which]
    which == 1 && return [base + 1.0, base + 2.0, base + 3.0]
    x = [base + 1.2]
    while length(x) < 1001
        push!(x, base + 1.1, base + 1.3)
    end
    return x
end

function lcghalf(seed, n)
    state = UInt32(seed)
    return map(1:n) do _
        state = state * 0x41c64e6d + 0x00003039
        Float64((state >> 8) & 0x00ffffff) / 16777216.0 - 0.5
    end
end

function xorshiftunit(seed, n)
    s = UInt32(seed)
    return map(1:n) do _
        s ⊻= s << 13
        s ⊻= s >> 17
        s ⊻= s << 5
        Float64((s >> 8) & 0x0000ffff) / 65535.0
    end
end

relerr(got, want) = abs(want) > 1e-12 ? abs(got - want) / abs(want) : abs(got - want)

windowed(s, cols, p) = only(foldseries(s, cols; window = Bars(p)))
corr(x, y, p) = windowed(Correlation(:x, :y), (; x, y), p)

@testset "reference battery (test_reference.c)" begin
    golden(name) = refarr("golden_$name")
    wilk(name) = refarr("wilkinson_$name")
    ladder = refarr("ladder")

    @testset "the oracle against the goldens" begin
        # Every baked value, to the C test's 1e-15, counted as the C test counts
        # them: the count is derived from the tables, so a dropped one is noticed.
        ncmp = Ref(0)
        cmp(got, want) = (ncmp[] += 1; relerr(got, want) <= 1e-15)
        ox, oy = refarr("pd_outlier_x"), refarr("pd_outlier_y")
        for (off, g) in ((0.0, "corr_outlier_off0"), (1e13, "corr_outlier_off1e13"))
            y = oy .+ off
            @test all(k -> cmp(refcorr(ox[k:(k+8)], y[k:(k+8)]), golden(g)[k]),
                eachindex(golden(g)))
        end
        sx, sy = refarr("pd_shared_x"), refarr("pd_shared_y")
        for (off, g) in ((1e10, "corr_shared_1e10"), (1e14, "corr_shared_1e14"))
            x, y = sx .+ off, sy .+ off
            @test all(k -> cmp(refcorr(x[k:(k+4)], y[k:(k+4)]), golden(g)[k]),
                eachindex(golden(g)))
        end
        for (ds, p, g) in (("nonan", 3, "corr_nonan"), ("extreme", 5, "corr_extreme"))
            x, y = refarr("pd_$(ds)_x"), refarr("pd_$(ds)_y")
            @test all(k -> cmp(refcorr(x[k:(k+p-1)], y[k:(k+p-1)]), golden(g)[k]),
                eachindex(golden(g)))
        end
        for (ds, p) in (("var47721", 6), ("var52407", 3))
            x = refarr("pd_$ds")
            @test all(k -> cmp(refvar(x[k:(k+p-1)]), golden(ds)[k]), eachindex(golden(ds)))
        end
        for (i, w) in enumerate(WILKINSON)
            got = reflinreg(wilk(w))
            for (v, o) in zip(got, ("slope", "intercept", "fit", "tsf"))
                @test cmp(v, golden("wilkinson_$o")[i])
            end
            @test cmp(refwma(wilk(w)), only(golden("wilkinson_wma_$w")))
        end
        counts = Int.(refarr("golden_ladder_counts"))
        for (p, c) in zip(LADDER_PERIODS, counts)
            @test c == length(ladder) - p + 1
            for k in 1:c
                w = ladder[k:(k+p-1)]
                got = (reflinreg(w)..., refstd(w), refwma(w))
                for (v, o) in zip(got, ("slope", "intercept", "fit", "tsf", "sigma", "wma"))
                    @test cmp(v, golden("ladder_p$(p)_$o")[k])
                end
            end
        end
        @test ncmp[] == 10 + 10 + 2 * 6 + 6 + 7 + 11 + 8 + 5 * 7 + 6 * sum(counts)
    end

    @testset "the datasets" begin
        # NIST certifies Norris' fit of the exact decimals; the goldens are the
        # fit of those decimals rounded to double.
        @test abs(refdef("GOLDEN_NORRIS_R") - refdef("NORRIS_R")) <= 1e-14
        @test abs(refdef("GOLDEN_NORRIS_B1") - refdef("NORRIS_B1")) <= 1e-13
        @test abs(refdef("GOLDEN_NORRIS_B0") - refdef("NORRIS_B0")) <= 1e-13
        nx, ny = refarr("norris_x"), refarr("norris_y")
        @test length(nx) == length(ny) == 36
        @test abs(refcorr(nx, ny) - refdef("GOLDEN_NORRIS_R")) <= 1e-15
        @test abs(refslope(nx, ny)[1] - refdef("GOLDEN_NORRIS_B1")) <= 1e-15
        # NumAcc1–4's certified population variance, from the built series.
        for (i, (v, tol)) in enumerate(((2 / 3, 1e-15), (10 / 1001, 1e-15),
            (10 / 1001, 1e-9), (10 / 1001, 1e-7)))
            x = numacc(i)
            @test length(x) == (i == 1 ? 3 : 1001)
            @test abs(refvar(x) - v) / v <= tol
        end
        # A window of bit-identical values gives exactly zero from every oracle.
        c = fill(1e11, 8)
        @test refvar(c) === refstd(c) === refcorr(c, c) === refslope(c, c)[1] === 0.0
    end

    @testset "the random number generators" begin
        # The first three draws and the 1000th, which the C tests' tolerances
        # were measured on.
        pins(v) = (v[1], v[2], v[3], v[1000])
        @test pins(lcgsym(0x1BADCAFE, 1000)) == (-0.5367124080657959, 0.33585023880004883,
            0.93741476535797119, 0.71201968193054199)
        @test pins(lcghalf(7, 1000)) == (0.29852801561355591, -0.35036760568618774,
            -0.33416271209716797, 0.21563214063644409)
        @test pins(xorshiftunit(2463534242, 1000)) == (0.12227054245822842,
            0.85467307545586324, 0.032608529793240255, 0.63552300297550923)
        @test all(v -> -1 <= v < 1, lcgsym(0x1BADCAFE, 1000))
        @test all(v -> -0.5 <= v < 0.5, lcghalf(7, 1000))
        @test all(v -> 0 <= v <= 1, xorshiftunit(2463534242, 1000))
    end

    @testset "test_correl.c" begin
        # (C1) pandas' adversarial arrays against the goldens, both argument
        # orders against the same table.
        ox, oy = refarr("pd_outlier_x"), refarr("pd_outlier_y")
        for (off, g) in ((0.0, "corr_outlier_off0"), (1e13, "corr_outlier_off1e13"))
            y = oy .+ off
            for r in (corr(ox, y, 9), corr(y, ox, 9))
                @test all(k -> relerr(r[k+8], golden(g)[k]) <= 1e-12, eachindex(golden(g)))
            end
        end
        sx, sy = refarr("pd_shared_x"), refarr("pd_shared_y")
        for (off, g) in ((1e10, "corr_shared_1e10"), (1e14, "corr_shared_1e14"))
            r = corr(sx .+ off, sy .+ off, 5)
            @test all(k -> relerr(r[k+4], golden(g)[k]) <= 1e-12, eachindex(golden(g)))
        end
        # The last two extreme-range windows are NaN once the 3e37 value has
        # left them: CausalFrames' windowed co-moments do not recover from it.
        for (ds, p, g) in (("nonan", 3, "corr_nonan"), ("extreme", 5, "corr_extreme"))
            r = corr(refarr("pd_$(ds)_x"), refarr("pd_$(ds)_y"), p)
            for k in eachindex(golden(g))
                ok = -1 <= r[k+p-1] <= 1 && relerr(r[k+p-1], golden(g)[k]) <= 1e-5
                @test ok broken = ds == "extreme" && k >= 6
            end
        end
        # (C2) NIST StRD Norris: the certificate, and the exact answer for these
        # doubles.
        r = corr(refarr("norris_x"), refarr("norris_y"), 36)[36]
        @test abs(r - refdef("NORRIS_R")) <= 1e-13
        @test abs(r - refdef("GOLDEN_NORRIS_R")) <= 1e-15
        # (C3) r(x, a·x + b) = sign(a) wherever x varies, on NumAcc4 and on
        # issue #242's tick ladder. A constant window is NaN here (DESIGN.md).
        function identity(x, p, a, b)
            r = corr(x, a .* x .+ b, p)
            return all(p:length(x)) do i
                isconstant(x[(i-p+1):i]) ? isnan(r[i]) : abs(r[i] - sign(a)) <= 1e-12
            end
        end
        n4 = vcat(fill(9999999.0 + 1.1, 500), fill(9999999.0 + 1.3, 500), 9999999.0 + 1.2)
        @test identity(n4, 30, 2.0, 1e-6) && identity(n4, 30, -3.0, 5.0)
        ticks60 = refarr("ticks60")
        for level in (0.0, 100.0, 20000.0), tick in (1e-5, 1e-6, 1e-8, 1e-9)
            @test identity(level .+ ticks60 .* tick, 30, 2.0, tick)
        end
        # (C5) r never leaves [-1, 1].
        for level in (100.0, 20000.0, 1e6), tick in (1e-2, 1e-4, 1e-6, 1e-8)
            x = level .+ ticks60 .* tick
            @test all(v -> -1 <= v <= 1, skipmissing(corr(x, 2 .* x .+ tick, 30)))
        end
        # (#395) Sums of squares near 2e-170, whose product underflows: TA-Lib
        # gives 0 there. Correlation is scale-free, so the answer is the
        # unscaled one.
        xs, ys = [0.0, 1, 2, 3, 4, 5], [0.0, 1, 1, 0, 1, 1]
        s = ldexp(1.0, -283)
        small, unit = corr(xs .* s, ys .* s, 4), corr(xs, ys, 4)
        @test all(i -> isapprox(small[i], unit[i]; atol = 1e-15), 4:6)
    end

    @testset "test_beta.c" begin
        beta(x, y, p) = foldseries(Beta(:x, :y; period = p), (; x, y)).x_y_beta
        ret(v, i) = v[i-1] != 0 ? (v[i] - v[i-1]) / v[i-1] : 0.0
        # (B1) Wilkinson W.IV.B: a series regressed on itself is exactly 1. BIG
        # and LITTLE have returns of ~1e-8 that barely vary, which `betavalue`'s
        # guard (variance against variance + mean²) reads as no variance and
        # zeroes. The pinned beta.c measures its guard from a shifted origin
        # instead (#242), so TA-Lib gives 1.
        for w in ("x", "round", "huge", "tiny", "big", "little")
            @test all(v -> abs(v - 1) <= 1e-12, skipmissing(beta(wilk(w), wilk(w), 8))) broken =
                w in ("big", "little")
        end
        # (B2) W.IV.D: an index with no variance gives exactly 0.
        @test all(==(0), skipmissing(beta(wilk("zero"), wilk("x"), 8)))
        # (B3) NIST Norris' certified slope, fed as returns.
        nx, ny = refarr("norris_x"), refarr("norris_y")
        px, py = ones(37), ones(37)
        for i in 1:36
            px[i+1] = px[i] * (1 + 1e-3 * nx[i])
            py[i+1] = py[i] * (1 + 1e-3 * ny[i])
        end
        b = beta(px, py, 36)[37]
        @test abs(b - refdef("NORRIS_B1")) / refdef("NORRIS_B1") <= 1e-12
        # (B7) A spike of 1e2 to 1e12 (and 1e-3, 1e-9) on either axis transits
        # the window; once it has left, the slope is the window's own again.
        # Judged on the scale sd(y)/sd(x) a slope lives on, at the C test's 1e-9
        # plus the window's conditioning.
        #
        # CausalFrames' windowed Covariance and Variance keep a residue of the
        # spike's return once it has left the window, so these rungs are broken
        # until an upstream re-anchor (TA-Lib's beta.c re-seeds its sums).
        broken = Set(
            [(1, 1e3, 5);
                [(1, s, p) for s in (1e5, 1e8, 1e12, 1e-3, 1e-9)
                 for p in (5, 14, 30)]; (2, 1e3, 5); (2, 1e5, 5); (2, 1e8, 5);
                (2, 1e8, 30);
                [(2, 1e12, p) for p in (5, 14, 30)]; (2, 1e-3, 5); (2, 1e-3, 30);
                [(2, 1e-9, p) for p in (5, 14, 30)]],
        )
        @test length(broken) == 28
        for axis in 1:2,
            spike in (1.1e2, 2.0e2, 1.0e3, 1.0e5, 1.0e8, 1.0e12, 1.0e-3, 1.0e-9),
            p in (5, 14, 30)

            x = [100.0 + ((i * 37) % 11) * 0.01 for i in 0:399]
            y = [200.0 + ((i * 53) % 13) * 0.02 for i in 0:399]
            (axis == 1 ? x : y)[101] = spike
            got = beta(x, y, p)
            ok = all((101+p+2):400) do bar
                rx = [ret(x, i) for i in (bar-p+1):bar]
                ry = [ret(y, i) for i in (bar-p+1):bar]
                want, kappa = refslope(rx, ry)
                sdx = refstd(rx)
                scale = sdx > 0 ? refstd(ry) / sdx : 0.0
                norm = max(abs(want), scale)
                norm == 0 && return true
                tol = p == 5 && spike >= 1e5 ? 1.2e-7 : 1e-9
                abs(got[bar] - want) / norm <= tol + 100 * kappa * eps()
            end
            @test ok broken = (axis, spike, p) in broken
        end
    end

    @testset "test_linearreg.c" begin
        ctors = (LinearRegSlope, LinearRegIntercept, LinearReg, TSF, LinearRegAngle)
        fits(y, p) = map(c -> windowed(c(:x), (x = y,), p), ctors)
        # lr_compare: the cancellation bound on the window's scale |mean| + σ,
        # plus the k^1.5 residue of k outputs on the largest value seen.
        function lrok(y, p, out, bar, k, want)
            w = y[(bar-p+1):bar]
            sc = abs(refmean(w)) + refstd(w)
            drift = 11 * eps() * maximum(abs, y[1:bar]) * k * sqrt(k) / p
            tslope = 50 * eps() * sc + drift
            tvalue = (40 * eps() * sc + drift) * p
            angle = atand(want[1])
            tangle = tslope * (180 / π) / (1 + want[1]^2) + 4 * eps() * abs(angle)
            tols = (tslope, tvalue, tvalue, tvalue, tangle)
            return all(zip(out, (want..., angle), tols)) do (o, w, t)
                abs(o[bar] - w) <= t
            end
        end
        # (L1) Wilkinson's nasty.dat at period 9, against the goldens.
        for (i, w) in enumerate(WILKINSON)
            y = wilk(w)
            want = map(o -> golden("wilkinson_$o")[i], ("slope", "intercept", "fit", "tsf"))
            @test lrok(y, 9, fits(y, 9), 9, 0, want)
        end
        # (L3) The sliding-sum ladder at four periods, against the goldens.
        for p in LADDER_PERIODS
            out = fits(ladder, p)
            @test all(eachindex(golden("ladder_p$(p)_slope"))) do k
                want = map(
                    o -> golden("ladder_p$(p)_$o")[k],
                    ("slope", "intercept", "fit", "tsf"),
                )
                lrok(ladder, p, out, k + p - 1, k - 1, want)
            end
        end
        # (L4) NIST NumAcc3 and NumAcc4, against the exact oracle.
        for which in (3, 4), p in (2, 5, 14, 30, 60)
            y = numacc(which)
            out = fits(y, p)
            @test all(bar -> lrok(y, p, out, bar, bar - p, reflinreg(y[(bar-p+1):bar])),
                p:length(y))
        end
    end

    @testset "test_wma.c W1" begin
        wmascale(w) = sum(abs.(w) .* (1:length(w))) / (length(w) * (length(w) + 1) / 2)
        for w in WILKINSON
            y = wilk(w)
            got = windowed(WMA(:x), (x = y,), 9)[9]
            @test abs(got - only(golden("wilkinson_wma_$w"))) <= 60 * eps() * wmascale(y)
        end
        for p in LADDER_PERIODS
            got = windowed(WMA(:x), (x = ladder,), p)
            g = golden("ladder_p$(p)_wma")
            @test all(
                k -> abs(got[k+p-1] - g[k]) <= 60 * eps() * wmascale(ladder[k:(k+p-1)]),
                eachindex(g))
        end
    end

    var(x, p) = windowed(Variance(:x; corrected = false), (; x), p)
    sd(x, p) = windowed(StdDev(:x), (; x), p)
    # The variance's conditioning |mean|/σ widens the bound: both the function
    # and any oracle lose ~κ·eps digits on a window of nearly equal values.
    function varok(got, want, w; base = 1e-9)
        got < 0 && return false
        want == 0 && return got <= 1e-12 * sum(abs2, w) / length(w)
        kappa = abs(refmean(w)) / sqrt(want)
        return abs(got - want) / want <= base + 100 * kappa * eps()
    end

    @testset "test_stddev.c" begin
        # NIST NumAcc1–4: the certified population variance (and σ).
        for (i, tol) in enumerate((1e-12, 1e-12, 1e-8, 1e-6))
            x = numacc(i)
            v = i == 1 ? 2 / 3 : 10 / 1001
            n = length(x)
            @test abs(var(x, n)[n] - v) / v <= tol
            @test abs(sd(x, n)[n] - sqrt(v)) / sqrt(v) <= tol
        end
        # pandas GH#47721 and GH#52407 against the goldens; GH#42064 and random
        # data at three magnitudes against the exact oracle.
        # GH#52407's windows after its 3e-16 value has left carry a ~3e-48
        # residue of it where the exact variance is ~1e-96 to 1e-102:
        # CausalFrames' windowed Variance does not re-anchor.
        for (ds, p) in (("var47721", 6), ("var52407", 3))
            x, g = refarr("pd_$ds"), golden(ds)
            v = var(x, p)
            @test all(k -> varok(v[k+p-1], g[k], x[k:(k+p-1)]), eachindex(g)) broken =
                ds == "var52407"
        end
        a = zeros(1000)
        a[1] = 1000.0
        v = var(a, 10)
        @test all(i -> varok(v[i], refvar(a[(i-9):i]), a[(i-9):i]), 10:1000)
        for (m, mag) in enumerate((1.0, 1e4, 1e8)), p in (2, 5, 14, 50)
            x = mag .* (1 .+ 1e-3 .* lcgsym(0xC0FFEE + m - 1, 2000))
            v = var(x, p)
            @test all(i -> varok(v[i], refvar(x[(i-p+1):i]), x[(i-p+1):i]), p:2000)
        end
        # Issue #243: σ on a 1e-8 tick must not collapse to 0. The ticks walk
        # twelve decades down from 1e-2, at levels 0 and 100.
        ticks60 = refarr("ticks60")
        for base in (0.0, 100.0), p in (2, 5, 20, 30), d in 0:11
            x = base .+ ticks60 .* (1e-2 / 10.0^d)
            s = sd(x, p)
            ok = all(p:60) do i
                w = x[(i-p+1):i]
                want = refstd(w)
                want == 0 && return s[i] <= 1e-6 * maximum(abs, w)
                s[i] == 0 && return false
                ke = abs(refmean(w)) / want * eps()
                abs(s[i] - want) / want <= 1e-11 + 1e-6 * ke^2
            end
            ok || @info "STDDEV #243" base p d
            @test ok
        end
    end

    @testset "test_bbands.c" begin
        # The deviation as a caller sees it, (upper − lower) / (devup + devdn),
        # which cancels the middle band: that costs |mid|·eps/width.
        halfwidth(b, i, k) = (b[1][i] - b[3][i]) / k
        readback(mid, k, sigma) = 8 * abs(mid) * eps() / (k * sigma)
        bands(x, p; up = 1.0, dn = 1.0) =
            Tuple(
                foldseries(BollingerBands(:x; nbdevup = up, nbdevdn = dn), (; x);
                    window = Bars(p)),
            )
        # (#243) The tick ladder under SMA, EMA and WMA middle bands.
        ticks60 = refarr("ticks60")
        for base in (0.0, 100.0), m in (:sma, :ema, :wma), d in 0:11
            x = base .+ ticks60 .* (1e-2 / 10.0^d)
            b = Tuple(
                foldseries(
                    BollingerBands(:x; matype = m, period = 5, nbdevup = 2,
                        nbdevdn = 3), (; x)),
            )
            first_ = findfirst(!ismissing, b[1])
            ok = all(first_:60) do i
                w = x[(i-4):i]
                want, dev = refstd(w), halfwidth(b, i, 5)
                want == 0 && return dev <= 1e-6 * maximum(abs, w)
                dev == 0 && return false
                ke = abs(refmean(w)) / want * eps()
                abs(dev - want) / want <= 1e-11 + 1e-6 * ke^2 + readback(b[2][i], 5, want)
            end
            ok || @info "BBANDS #243" base m d
            @test ok
        end
        # (R1) NumAcc1–4: the half-width is the certified σ.
        for (i, tol) in enumerate((1e-12, 1e-12, 1e-8, 1e-6))
            x = numacc(i)
            n = length(x)
            sigma = sqrt(i == 1 ? 2 / 3 : 10 / 1001)
            b = bands(x, n)
            @test abs(halfwidth(b, n, 2) - sigma) / sigma <=
                  tol + readback(b[2][n], 2, sigma)
        end
        # (R2, R3) pandas' arrays and the ladder, against the goldens. The bands
        # never cross.
        sets = [(refarr("pd_var47721"), 6, sqrt.(golden("var47721"))),
            (refarr("pd_var52407"), 3, sqrt.(golden("var52407")))]
        append!(sets, [(ladder, p, golden("ladder_p$(p)_sigma")) for p in LADDER_PERIODS])
        for (x, p, g) in sets
            b = bands(x, p)
            ok = all(eachindex(g)) do k
                i = k + p - 1
                b[1][i] >= b[2][i] >= b[3][i] || return false
                dev, w = halfwidth(b, i, 2), x[k:i]
                g[k] == 0 && return dev <= 1e-12 * maximum(abs, w)
                dev == 0 && return false
                ke = abs(refmean(w)) / g[k] * eps()
                abs(dev - g[k]) / g[k] <= 1e-11 + 1e-6 * ke^2 + readback(b[2][i], 2, g[k])
            end
            # GH#52407, as for VAR above.
            @test ok broken = x === sets[2][1]
        end
    end
end
