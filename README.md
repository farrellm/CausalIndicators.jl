# CausalIndicators

[![Build Status](https://github.com/farrellm/CausalIndicators.jl/actions/workflows/CI.yml/badge.svg?branch=master)](https://github.com/farrellm/CausalIndicators.jl/actions/workflows/CI.yml?query=branch%3Amaster)

TA-Lib's technical indicators as causal, streaming building blocks for
[CausalFrames.jl](https://github.com/farrellm/CausalFrames.jl) pipelines. See
[DESIGN.md](DESIGN.md) for the design and the implementation stages. This is
under construction: only the S0′ scaffolding has landed so far, and no
indicators are exported yet.

## Development

CausalFrames is not registered. On Julia 1.11 and later, Pkg reads its URL from
`[sources]` in `Project.toml`. On Julia 1.10, develop it first:

```julia
using Pkg
Pkg.develop(url = "https://github.com/farrellm/CausalFrames.jl")
```

### TA-Lib reference data

The tests check against TA-Lib 0.8.1, commit `2aa8eb0`. The extracted tables,
datasets and goldens are committed, so running the tests needs no TA-Lib. To
regenerate them, or to add goldens for a new function:

```sh
git clone https://github.com/TA-Lib/ta-lib ~/workspace/ta-lib
git -C ~/workspace/ta-lib checkout 2aa8eb0d79bcfc4d2ff3f7b445d37958c48e0788
cmake -S ~/workspace/ta-lib -B ~/workspace/ta-lib/build
cmake --build ~/workspace/ta-lib/build --target ta-lib

julia --project=gen gen/extract_talib_data.jl ~/workspace/ta-lib    # test/data
julia --project=gen gen/extract_talib_tests.jl ~/workspace/ta-lib   # test/talib/tables
make -C gen/golden TALIB=~/workspace/ta-lib
julia --project=gen gen/golden/generate.jl ~/workspace/ta-lib EMA RMA   # test/golden
```

Before generating a function's goldens, add the parameter sets its tables use
to `gen/golden/paramsets.toml`.
