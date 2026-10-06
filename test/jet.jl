# Targeted JET checks: every kernel's per-bar path must be free of runtime
# dispatch, including the CausalFrames barwindows embedded in the window
# kernels, and so must every plain state's update! (S1 to S5).

using JET

@testset "JET" begin
    for k in (EMAKernel(Float64, 5), WilderKernel(Float64, 5),
        WilderKernel(Float64, 5; form = :sum), SMAKernel(Float64, 5),
        (MAKernel(Float64, m, 5; unstable = 1) for m in MATYPES if m !== :mama)...)
        JET.@test_opt step!(k, 1.5)
        JET.@test_opt step!(k, missing)
        JET.@test_opt current(k)
        JET.@test_opt fresh!(k)
    end

    # The S1 plain states' per-row path, including the skipped missing row.
    for s in PLAIN_S1
        st = fresh(s, S1_INTYPES)
        JET.@test_opt CausalFrames.update!(st, (time = 1, close = 1.5, periods = 7.0))
        JET.@test_opt CausalFrames.update!(st, (time = 1, close = missing, periods = 7.0))
        JET.@test_opt CausalFrames.value(st)
    end

    # The S2 kernels and plain states.
    gl = GainLossKernel(Float64, 5)
    JET.@test_opt step!(gl, 1.5)
    fk = FastKKernel(Float64, 5)
    JET.@test_opt step!(fk, 2.0, 1.0, 1.5)
    fx = FastKKernel(Float64, 5, :x)
    JET.@test_opt step!(fx, 1.5)

    # The S3 kernels.
    for k in (ATRKernel(Float64, 5), DMKernel(Float64, 5), DMKernel(Float64, 1))
        JET.@test_opt step!(k, 2.0, 1.0, 1.5)
        JET.@test_opt current(k)
        JET.@test_opt fresh!(k)
    end
    row = (time = 1, open = 1.0, high = 2.0, low = 0.5, close = 1.5, volume = 10.0)
    # The S5 efficiency-ratio kernel KAMA now embeds.
    er = ERKernel(Float64, 5)
    JET.@test_opt step!(er, 1.5)
    JET.@test_opt fresh!(er)
    for s in vcat(PLAIN_S2, PLAIN_S3, PLAIN_S4, PLAIN_S5)
        st = fresh(s, S2_INTYPES)
        JET.@test_opt CausalFrames.update!(st, row)
        JET.@test_opt CausalFrames.update!(st, merge(row, (close = missing,)))
        JET.@test_opt CausalFrames.value(st)
    end
end
