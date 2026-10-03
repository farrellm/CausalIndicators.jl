# CausalIndicators

[![Build Status](https://github.com/farrellm/CausalIndicators.jl/actions/workflows/CI.yml/badge.svg?branch=master)](https://github.com/farrellm/CausalIndicators.jl/actions/workflows/CI.yml?query=branch%3Amaster)

TA-Lib's technical indicators as causal, streaming building blocks for
[CausalFrames.jl](https://github.com/farrellm/CausalFrames.jl) pipelines. See
[DESIGN.md](DESIGN.md) for the design and the implementation stages. This is
under construction: stage S1 (moving averages, rolling operators and price
transforms) has landed.

```julia
using CausalFrames, CausalIndicators, Dates

p = readcsv("bars.csv"; types = Dict(:time => DateTime, :symbol => String,
        :open => Float64, :high => Float64, :low => Float64, :close => Float64,
        :volume => Float64)) |>
    addrollingcolumns((b20 = Bars(20),), [Mean(:close), WMA(:close), MidPrice()];
        key = :symbol) |>
    addsummarycolumns([EMA(:close), KAMA(:close; period = 10)]; key = :symbol)
```

Structured indicators (sums, extrema and their dependents) take their window
from `addrollingcolumns`, so TA-Lib's `period = p` is `Bars(p)`. Recursive ones
take a `period` keyword and run under `addsummarycolumns`. Output columns are
`missing` for TA-Lib's lookback.

## Indicators

| TA-Lib | CausalIndicators | Runs under |
|---|---|---|
| `MA` | `MA(:x; period = 30, matype = :sma)` | `addsummarycolumns` |
| `EMA`, `DEMA`, `TEMA`, `TRIMA`, `KAMA`, `T3`, `HMA`, `ZLEMA`, `RMA` | `EMA(:x; period)`, … (same names) | `addsummarycolumns` |
| `MAVP` | `MAVP(:x, :periods; minperiod = 2, maxperiod = 30, matype = :sma)` | `addsummarycolumns` |
| `WMA` | `WMA(:x)` | `Bars(30)` |
| `VWMA` | `VWMA(:x; volume = :volume)` | `Bars(30)` |
| `MIDPOINT` | `MidPoint(:x)` | `Bars(14)` |
| `MIDPRICE` | `MidPrice(; high, low)` | `Bars(14)` |
| `AVGPRICE`, `MEDPRICE`, `TYPPRICE`, `WCLPRICE` | `AvgPrice()`, `MedPrice()`, `TypPrice()`, `WclPrice()` | either (bar-local) |

These TA-Lib functions are CausalFrames summarizers already, so this package
only tests them and adds no constructor:

| TA-Lib | CausalFrames | Runs under |
|---|---|---|
| `SMA` | `Mean(:x)` | `Bars(30)` |
| `SUM` | `Sum(:x)` | `Bars(30)` |
| `CUMSUM` | `Sum(:x)` | `addsummarycolumns` |
| `MAX`, `MIN`, `MINMAX` | `Max(:x)`, `Min(:x)` | `Bars(30)` |
| `MAXINDEX`, `MININDEX`, `MINMAXINDEX` | `MaxIndex(:x)`, `MinIndex(:x)` (bars since the extreme, newest tie wins) | `Bars(30)` |

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
julia --project=gen gen/golden/generate.jl ~/workspace/ta-lib EMA RMA ...   # test/golden
```

Before generating a function's goldens, add the parameter sets its tables use
to `gen/golden/paramsets.toml`.
