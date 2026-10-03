# Targeted JET checks: every kernel's per-bar path must be free of runtime
# dispatch, including the CausalFrames barwindow embedded in SMAKernel.

using JET

@testset "JET" begin
    for k in (EMAKernel(Float64, 5), WilderKernel(Float64, 5),
        WilderKernel(Float64, 5; form = :sum), SMAKernel(Float64, 5),
        MAKernel(Float64, :sma, 5), MAKernel(Float64, :ema, 5))
        JET.@test_opt step!(k, 1.5)
        JET.@test_opt step!(k, missing)
        JET.@test_opt current(k)
        JET.@test_opt fresh!(k)
    end
end
