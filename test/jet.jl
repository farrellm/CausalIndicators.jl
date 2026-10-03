# Targeted JET checks: every kernel's per-bar path must be free of runtime
# dispatch, including the CausalFrames barwindows embedded in the window
# kernels, and so must every S1 plain state's update!.

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
end
