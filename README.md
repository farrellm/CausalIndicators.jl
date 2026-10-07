# CausalIndicators

[![Build Status](https://github.com/farrellm/CausalIndicators.jl/actions/workflows/CI.yml/badge.svg?branch=master)](https://github.com/farrellm/CausalIndicators.jl/actions/workflows/CI.yml?query=branch%3Amaster)

TA-Lib's technical indicators as causal, streaming building blocks for
[CausalFrames.jl](https://github.com/farrellm/CausalFrames.jl) pipelines. See
[DESIGN.md](DESIGN.md) for the design and the implementation stages. All seven
stages have landed: S1 (moving averages, rolling operators and price
transforms), S2 (momentum I), S3 (directional movement and volatility), S4
(statistics and volume), S5 (the TA-Lib 0.8 additions), S6 (the Hilbert cycle
family and MAMA) and S7 (the candlestick patterns).

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
`missing` for TA-Lib's lookback. Functions that compare with the bar `period`
back (the MOM/ROC family, Aroon, PercentRank100, RVOL, FOSC) take `Bars(period + 1)`. Indicators with a
TA-Lib unstable period, their own or inherited, take an `unstable` keyword.

Bars can be any size, daily or minute or tick, because every period and window
counts bars, not days. The defaults, here and in the table below, are TA-Lib's,
and most are their authors' parameters for daily charts: Wilder's 14,
MACD's 12/26/9, Bollinger's 20. On other bar sizes they span other lengths of
time, so choose the parameters for your bars. The docstrings note where a
default or constant assumes daily bars. One example is the Hilbert family's
6–50-bar cycle range; another is Coppock, whose defaults are month counts.

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
| `RSI`, `CMO` | `RSI(:x; period = 14)`, `CMO(:x; period = 14)` | `addsummarycolumns` |
| `MACD`, `MACDFIX`, `MACDEXT` | `MACD(:x; fastperiod = 12, slowperiod = 26, signalperiod = 9)`, `MACDFix(:x)`, `MACDExt(:x; fastmatype, …)` | `addsummarycolumns` |
| `APO`, `PPO` | `APO(:x; fastperiod = 12, slowperiod = 26, matype = :ema)`, `PPO(:x; …)` | `addsummarycolumns` |
| `TRIX` | `TRIX(:x; period = 30)` | `addsummarycolumns` |
| `STOCH`, `STOCHF`, `STOCHRSI` | `Stoch(; fastkperiod = 5, …)`, `StochF(; …)`, `StochRSI(:x; period = 14, …)` | `addsummarycolumns` |
| `ULTOSC` | `ULTOSC(; timeperiod1 = 7, timeperiod2 = 14, timeperiod3 = 28)` | `addsummarycolumns` |
| `MFI` | `MFI(; period = 14)` | `addsummarycolumns` |
| `MOM`, `ROC`, `ROCP`, `ROCR`, `ROCR100` | `MOM(:x)`, `ROC(:x)`, … | `Bars(11)` (period + 1) |
| `WILLR` | `WillR(; high, low, close)` | `Bars(14)` |
| `CCI` | `CCI(; high, low, close)` | `Bars(14)` |
| `AROON`, `AROONOSC` | `Aroon(; high, low)`, `AroonOsc(; high, low)` | `Bars(15)` (period + 1) |
| `BOP` | `BOP()` | either (bar-local) |
| `PLUS_DM`, `MINUS_DM` | `PlusDM(; period = 14)`, `MinusDM(; …)` | `addsummarycolumns` |
| `PLUS_DI`, `MINUS_DI`, `DX`, `ADX`, `ADXR` | `PlusDI(; period = 14)`, `MinusDI`, `DX`, `ADX`, `ADXR` (same keywords) | `addsummarycolumns` |
| `TRANGE` | `TRange(; high, low, close)` | `Bars(2)` |
| `ATR`, `NATR` | `ATR(; period = 14)`, `NATR(; period = 14)` | `addsummarycolumns` |
| `ADR` | `ADR(; high, low)` | `Bars(14)` |
| `CVI` | `CVI(; period = 10, rocperiod = 10)` | `addsummarycolumns` |
| `MASSI` | `MassIndex(; fastperiod = 9, slowperiod = 25)` | `addsummarycolumns` |
| `RVI` | `RVI(:x; period = 14, stddevperiod = 10)` | `addsummarycolumns` |
| `STDDEV` | `StdDev(:x; nbdev = 1)` | `Bars(5)` |
| `BBANDS` | `BollingerBands(:x; nbdevup = 2, nbdevdn = 2)` (SMA), or with `matype` and `period = 20` | `Bars(20)`, or `addsummarycolumns` with `matype` |
| `ACCBANDS` | `AccBands(; high, low, close)` | `Bars(20)` |
| `DONCHIAN` | `Donchian(; high, low)` | `Bars(20)` |
| `KC` | `KeltnerChannels(; period = 20, atrperiod = 10, nbdev = 2)` | `addsummarycolumns` |
| `SAR`, `SAREXT` | `SAR(; acceleration = 0.02, maximum = 0.2)`, `SARExt(; startvalue = 0, …)` | `addsummarycolumns` |
| `SUPERTREND` | `SuperTrend(; period = 10, multiplier = 3.0)` | `addsummarycolumns` |
| `LINEARREG`, `LINEARREG_SLOPE`, `LINEARREG_INTERCEPT`, `LINEARREG_ANGLE`, `TSF` | `LinearReg(:x)`, `LinearRegSlope(:x)`, `LinearRegIntercept(:x)`, `LinearRegAngle(:x)`, `TSF(:x)` | `Bars(14)` |
| `PERCENTRANK` | `PercentRank100(:x)` | `Bars(101)` (period + 1) |
| `BETA` | `Beta(:x, :y; period = 5)` | `addsummarycolumns` |
| `AD` | `AD(; high, low, close, volume)` | `addsummarycolumns` |
| `ADOSC` | `ADOSC(; fastperiod = 3, slowperiod = 10)` | `addsummarycolumns` |
| `CMF` | `CMF(; high, low, close, volume)` | `Bars(20)` |
| `EFI` | `EFI(; period = 13)` | `addsummarycolumns` |
| `MARKETFI` | `MarketFI(; high, low, volume)` | either (bar-local) |
| `OBV` | `OBV(:x; volume = :volume)` | `addsummarycolumns` |
| `NVI`, `PVI`, `PVT` | `NVI(; close, volume)`, `PVI(; …)`, `PVT(; …)` | `addsummarycolumns` |
| `PVO` | `PVO(; fastperiod = 12, slowperiod = 26, matype = :ema)` | `addsummarycolumns` |
| `RVOL` | `RVOL(; volume)` | `Bars(21)` (period + 1) |
| `VWAP` | `VWAP(; high, low, close, volume)` | `addsummarycolumns` (a key per session) |
| `AO`, `AC` | `AO(; fastperiod = 5, slowperiod = 34)`, `AC(; …, signalperiod = 5)` | `addsummarycolumns` |
| `CMOU` | `CMOU(:x; period = 14)` | `addsummarycolumns` |
| `COPPOCK` | `Coppock(:x; wmaperiod = 10, roc1period = 11, roc2period = 14)` | `addsummarycolumns` |
| `DPO` | `DPO(:x; period = 20)` | `addsummarycolumns` |
| `ER` | `ER(:x; period = 10)` | `addsummarycolumns` |
| `ERI` | `ERI(; period = 13)` | `addsummarycolumns` |
| `FOSC` | `FOSC(:x)` | `Bars(6)` (period + 1) |
| `FRACTAL` | `Fractal(; leftbars = 2, rightbars = 2)` (`Int`, on the confirmation bar) | `addsummarycolumns` |
| `IMI` | `IMI(; open, close)` | `Bars(14)` |
| `KDJ` | `KDJ(; fastkperiod = 9, slowkperiod = 3, slowkmatype = :rma, …)` | `addsummarycolumns` |
| `QSTICK` | `QStick(; open, close)` | `Bars(10)` |
| `SMI` | `SMI(; period = 13, fastperiod = 2, slowperiod = 25, signalperiod = 9)` | `addsummarycolumns` |
| `TSI` | `TSI(:x; firstperiod = 25, secondperiod = 13)` | `addsummarycolumns` |
| `VHF` | `VHF(:x; period = 28)` | `addsummarycolumns` |
| `VORTEX` | `Vortex(; period = 14)` | `addsummarycolumns` |
| `WAD` | `WAD(; high, low, close)` | `addsummarycolumns` |
| `HA` | `HeikinAshi(; open, high, low, close)` | `addsummarycolumns` |
| `HT_DCPERIOD`, `HT_DCPHASE`, `HT_TRENDLINE` | `HTDCPeriod(:x)`, `HTDCPhase(:x)`, `HTTrendline(:x)` | `addsummarycolumns` |
| `HT_PHASOR`, `HT_SINE` | `HTPhasor(:x)` (inphase, quadrature), `HTSine(:x)` (sine, leadsine) | `addsummarycolumns` |
| `HT_TRENDMODE` | `HTTrendMode(:x)` (`Int`: 1 trend, 0 cycle) | `addsummarycolumns` |
| `MAMA` | `MAMA(:x; fastlimit = 0.5, slowlimit = 0.05)` (mama, fama); also `matype = :mama` | `addsummarycolumns` |

These TA-Lib functions are CausalFrames summarizers already, so this package
only tests them and adds no constructor:

| TA-Lib | CausalFrames | Runs under |
|---|---|---|
| `SMA` | `Mean(:x)` | `Bars(30)` |
| `SUM` | `Sum(:x)` | `Bars(30)` |
| `CUMSUM` | `Sum(:x)` | `addsummarycolumns` |
| `MAX`, `MIN`, `MINMAX` | `Max(:x)`, `Min(:x)` | `Bars(30)` |
| `MAXINDEX`, `MININDEX`, `MINMAXINDEX` | `MaxIndex(:x)`, `MinIndex(:x)` (bars since the extreme, newest tie wins) | `Bars(30)` |
| `VAR` | `Variance(:x; corrected = false)` | `Bars(5)` |
| `AVGDEV` | `MeanAbsDev(:x)` | `Bars(14)` |
| `CORREL` | `Correlation(:x, :y)` (`NaN` on a flat window, where TA-Lib gives 0) | `Bars(30)` |
| `PERCENTILE` | `Quantile(:x, percentile / 100; interpolation = :nearestrank)` | `Bars(30)` |

## Candlestick patterns

TA-Lib's 61 `CDL*` patterns live in the `CausalIndicators.Candles` submodule,
so their names stay out of your namespace unless you ask for them. Each takes
`open`, `high`, `low` and `close` keywords (defaulting to those columns), runs
under `addsummarycolumns`, and emits `Int` in `:cdl<name>`. The values are 100
(bullish), −100 (bearish) or 0. Engulfing, Harami and HaramiCross give ±80 for
their weaker forms, and the Hikkake pair gives ±200 on a confirmation bar.

```julia
using CausalIndicators.Candles

loose = CandleSettings(; bodydoji = CandleSetting(:highlow, 10, 0.2))
p |> addsummarycolumns([Hammer(), Engulfing(), Doji(; settings = loose, name = :doji20),
    MorningStar(; penetration = 0.5)]; key = :symbol)
```

The thresholds a pattern compares against are TA-Lib's 11 candle settings
(`TA_SetCandleSettings`). Here they are an immutable `CandleSettings`, passed
as `settings`. Each setting is a `CandleSetting(range, avgperiod, factor)`.

| TA-Lib | `Candles.` |
|---|---|
| `CDL2CROWS` | `TwoCrows()` |
| `CDL3BLACKCROWS` | `ThreeBlackCrows()` |
| `CDL3INSIDE` | `ThreeInside()` |
| `CDL3LINESTRIKE` | `ThreeLineStrike()` |
| `CDL3OUTSIDE` | `ThreeOutside()` |
| `CDL3STARSINSOUTH` | `ThreeStarsInTheSouth()` |
| `CDL3WHITESOLDIERS` | `ThreeWhiteSoldiers()` |
| `CDLABANDONEDBABY` | `AbandonedBaby(; penetration = 0.3)` |
| `CDLADVANCEBLOCK` | `AdvanceBlock()` |
| `CDLBELTHOLD` | `BeltHold()` |
| `CDLBREAKAWAY` | `Breakaway()` |
| `CDLCLOSINGMARUBOZU` | `ClosingMarubozu()` |
| `CDLCONCEALBABYSWALL` | `ConcealingBabySwallow()` |
| `CDLCOUNTERATTACK` | `Counterattack()` |
| `CDLDARKCLOUDCOVER` | `DarkCloudCover(; penetration = 0.5)` |
| `CDLDOJI` | `Doji()` |
| `CDLDOJISTAR` | `DojiStar()` |
| `CDLDRAGONFLYDOJI` | `DragonflyDoji()` |
| `CDLENGULFING` | `Engulfing()` |
| `CDLEVENINGDOJISTAR` | `EveningDojiStar(; penetration = 0.3)` |
| `CDLEVENINGSTAR` | `EveningStar(; penetration = 0.3)` |
| `CDLGAPSIDESIDEWHITE` | `GapSideSideWhite()` |
| `CDLGRAVESTONEDOJI` | `GravestoneDoji()` |
| `CDLHAMMER` | `Hammer()` |
| `CDLHANGINGMAN` | `HangingMan()` |
| `CDLHARAMI` | `Harami()` |
| `CDLHARAMICROSS` | `HaramiCross()` |
| `CDLHIGHWAVE` | `HighWave()` |
| `CDLHIKKAKE` | `Hikkake()` |
| `CDLHIKKAKEMOD` | `HikkakeMod()` |
| `CDLHOMINGPIGEON` | `HomingPigeon()` |
| `CDLIDENTICAL3CROWS` | `IdenticalThreeCrows()` |
| `CDLINNECK` | `InNeck()` |
| `CDLINVERTEDHAMMER` | `InvertedHammer()` |
| `CDLKICKING` | `Kicking()` |
| `CDLKICKINGBYLENGTH` | `KickingByLength()` |
| `CDLLADDERBOTTOM` | `LadderBottom()` |
| `CDLLONGLEGGEDDOJI` | `LongLeggedDoji()` |
| `CDLLONGLINE` | `LongLine()` |
| `CDLMARUBOZU` | `Marubozu()` |
| `CDLMATCHINGLOW` | `MatchingLow()` |
| `CDLMATHOLD` | `MatHold(; penetration = 0.5)` |
| `CDLMORNINGDOJISTAR` | `MorningDojiStar(; penetration = 0.3)` |
| `CDLMORNINGSTAR` | `MorningStar(; penetration = 0.3)` |
| `CDLONNECK` | `OnNeck()` |
| `CDLPIERCING` | `Piercing()` |
| `CDLRICKSHAWMAN` | `RickshawMan()` |
| `CDLRISEFALL3METHODS` | `RiseFallThreeMethods()` |
| `CDLSEPARATINGLINES` | `SeparatingLines()` |
| `CDLSHOOTINGSTAR` | `ShootingStar()` |
| `CDLSHORTLINE` | `ShortLine()` |
| `CDLSPINNINGTOP` | `SpinningTop()` |
| `CDLSTALLEDPATTERN` | `StalledPattern()` |
| `CDLSTICKSANDWICH` | `StickSandwich()` |
| `CDLTAKURI` | `Takuri()` |
| `CDLTASUKIGAP` | `TasukiGap()` |
| `CDLTHRUSTING` | `Thrusting()` |
| `CDLTRISTAR` | `Tristar()` |
| `CDLUNIQUE3RIVER` | `UniqueThreeRiver()` |
| `CDLUPSIDEGAP2CROWS` | `UpsideGapTwoCrows()` |
| `CDLXSIDEGAP3METHODS` | `XSideGapThreeMethods()` |

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
cmake --build ~/workspace/ta-lib/build --target ta-lib ta-lib-static

julia --project=gen gen/extract_talib_data.jl ~/workspace/ta-lib    # test/data
julia --project=gen gen/extract_talib_tests.jl ~/workspace/ta-lib   # test/talib/tables
make -C gen/golden TALIB=~/workspace/ta-lib
julia --project=gen gen/golden/generate.jl ~/workspace/ta-lib EMA RMA ...   # test/golden
make -C gen/candles TALIB=~/workspace/ta-lib
julia --project=gen gen/candles/capture.jl ~/workspace/ta-lib       # test/talib/candles
```

The candlestick goldens also run at the settings rows of `test_candlestick.c`.
`gen/candles` captures that file's pattern-builder calls, which sit on each
pattern's decision boundaries, by linking it against the static library with
every `TA_CDL*` entry point wrapped.

Before generating a function's goldens, add the parameter sets its tables use
to `gen/golden/paramsets.toml`.
