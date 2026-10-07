using Aqua
using CausalFrames
using CausalFrames: fresh, fresh!
using CausalIndicators
using CodecZlib
using CSV
using DataFrames
using Random
using Tables
using TOML
using Test

include("foldseries.jl")
include("helpers.jl")

@testset "CausalIndicators.jl" begin
    @testset "Aqua" begin
        Aqua.test_all(CausalIndicators)
    end

    include("harness.jl")
    include("kernels.jl")
    include("overlap.jl")
    include("price.jl")
    include("momentum.jl")
    include("rolling.jl")
    include("statistics.jl")
    include("volatility.jl")
    include("volume.jl")
    include("additions.jl")
    include("cycle.jl")
    include("candles.jl")
    include("boundary.jl")

    # JET can lag pre-release Julia; the checks are the same on every released
    # version, so skipping them there loses nothing.
    if isempty(VERSION.prerelease)
        include("jet.jl")
    end
end
