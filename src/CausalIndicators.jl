"""
    CausalIndicators

TA-Lib's technical indicators as causal, streaming CausalFrames summarizers.
See DESIGN.md for the design and the staging of the implementation.
"""
module CausalIndicators

using CausalFrames
using CausalFrames: fresh, fresh!, update!, value

include("kernels/common.jl")
include("kernels/ema.jl")
include("kernels/wilder.jl")
include("kernels/sma.jl")
include("kernels/ma.jl")

end
