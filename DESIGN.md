# CausalIndicators.jl — Design

CausalIndicators provides the technical indicators of
[TA-Lib](https://github.com/TA-Lib/ta-lib) as causal, streaming building blocks
for [CausalFrames.jl](https://github.com/farrellm/CausalFrames.jl) pipelines.
An indicator here is a CausalFrames `Summarizer`. It is folded one bar at a time,
per key, across chunk boundaries, by the transforms CausalFrames already has.
The package adds no new pipeline machinery beyond one context-widening
combinator (`warmup`).

This document is the source of truth for the design. It is written ahead of the
code and governs the staged implementation PRs listed under "Staging". Any API
or semantics change must update it in the same commit.

```julia
using CausalFrames, CausalIndicators, Dates

bars = readcsv("ticks.csv";
            types = Dict(:time => DateTime, :symbol => String,
                         :price => Float64, :size => Float64)) |>
    intervalize(clock(Minute(1)),
        [First(:price), Max(:price), Min(:price), Last(:price), Sum(:size)];
        key = :symbol) |>
    addcolumns(r -> (; open = r.price_first, high = r.price_max,
                       low = r.price_min, close = r.price_last,
                       volume = r.size_sum))

p = bars |> warmup(Day(3),
    addsummarycolumns([RSI(:close), MACD(:close), ATR(), SMA(:close; period = 20)];
                      key = :symbol))

frame = load(Context(DateTime(2026, 1, 5), DateTime(2026, 2, 1)), p)
```

## Scope

**In scope:** every TA-Lib 0.8.1 function except the element-wise math ones,
which is 182 functions: 121 indicators plus 61 candlestick patterns. All of
them are listed under "Name table".

**Non-goals.**

- **Element-wise math**, meaning TA-Lib's *Math Transform* group (`ACOS`,
  `ASIN`, `ATAN`, `CEIL`, `COS`, `COSH`, `EXP`, `FLOOR`, `LN`, `LOG10`, `SIN`,
  `SINH`, `SQRT`, `TAN`, `TANH`) and the arithmetic operators `ADD`, `SUB`,
  `MULT`, `DIV`. Each of these is a one-line row function:
  `addcolumns(r -> (; logclose = log(r.close)))`,
  `addcolumns(r -> (; spread = r.ask - r.bid))`.
- **TA-Lib's MetaStock compatibility mode**, which changes EMA seeding. Only the
  default mode is reproduced.
- **TA-Lib's global unstable-period setting.** It becomes a per-indicator
  `unstable` keyword (see "Warm-up").
- **Acausal variants.** TA-Lib 0.8.1 is causal throughout. For example, `FRACTAL`
  reports a pivot on its confirmation bar, and `DPO` is written at the bar whose
  average produced it. So nothing here belongs in CausalFrames' `Acausal`
  submodule, and a centred or shifted plotting convention is the caller's own
  `Acausal.lead`.

**Pinned reference.** TA-Lib 0.8.1, commit
[`2aa8eb0`](https://github.com/TA-Lib/ta-lib/tree/2aa8eb0d79bcfc4d2ff3f7b445d37958c48e0788).
Each function's contract comes from
`ta_codegen/input/<fn>/<fn>.yaml` (inputs, parameter ranges and defaults,
outputs, `unstable_period`/`path_dependent` flags) and `<fn>.md` (formula and
edge cases). Both are cited from each docstring. Moving to a later TA-Lib is a
deliberate PR that regenerates the extracted tests and goldens (see "Testing").

## No duplication with CausalFrames

**No summarizer, state or kernel in this package may compute something
CausalFrames already computes.** Every TA-Lib function that overlaps CausalFrames
is resolved in exactly one of three ways, and the "Relation" column of the name
table records which:

1. **CausalFrames only.** If the value is *identical* to a CausalFrames
   summarizer, that summarizer is the implementation, and this package contributes
   only the TA-Lib tests for it. A TA-Lib-style constructor may exist for
   discoverability, but it is a plain *function* returning the CausalFrames
   summarizer, possibly wrapped in `Bars`. It never defines a type, and the
   output column keeps the CausalFrames name.
   - `SMA(:close; period)` returns `Bars(period, Mean(:close))` and emits
     `:close_mean`.
   - The same pattern covers `SUM` → `Sum`, `MAX`/`MIN`/`MINMAX` → `Max`/`Min`,
     `VAR` → `Variance(corrected = false)`, `CORREL` → `Correlation`, and
     `CUMSUM` → `Sum` with no window.
2. **TA-Lib-named dependent summarizer.** If the value is *derived* from
   CausalFrames values, the indicator is a fieldless dependent summarizer
   (CausalFrames DESIGN.md, "Dependent summarizers"). It declares those
   summarizers in `dependencies` and computes its value in the two-argument
   `value(st, vals)`. It folds no rows itself, so its accumulators are shared with
   every other summarizer in the call through CausalFrames' name-keyed
   deduplication.
   - `StdDev` is `nbdev · Std(corrected = false)`.
   - `MidPoint` is `(Max + Min) / 2`.
   - `WillR` reads `Max(:high)`, `Min(:low)`, `Last(:close)`.
   - `ROC` reads `First`/`Last` over `period + 1` bars.
   - `AvgPrice` reads `Last` of four columns.
3. **Move it into CausalFrames.** If an indicator needs a *generic* accumulator
   that CausalFrames lacks, the accumulator is added upstream to CausalFrames as a
   prerequisite PR, with its own tests, docs and DESIGN.md entry. The indicator
   here then becomes case 2. The upstream additions are listed under
   "Upstream prerequisites". The rule also runs the other way: if a CausalFrames
   summarizer ever turns out to be indicator-specific, it moves here instead of
   being mirrored.

The rule also binds internal code. A recursive indicator that needs a window
sum or extremum (KAMA's volatility sum, CCI's mean, AO's two means) embeds the
CausalFrames state (`CausalFrames.fresh`/`update!`/`downdate!`, windowed by
`Bars`). It never hand-rolls a compensated sum or a monotone deque.

### Upstream prerequisites

These are added to CausalFrames before the stages that need them (stage S0):

- **`Bars(n, s)`**: a count window over any structured summarizer (see "Bar
  windows"). Count windows are generic, not an indicator concept.
- **A recency-weighted sum** `Σₖ k·yₖ`, where `k` is the number of bars since
  that row (0 for the newest). It carries its own count, so it is lawful as a
  group over first-in-first-out windows:
  - `update!` adds `Σy` to the weighted sum, then adds `y` to `Σy`
  - `downdate!` of the oldest row subtracts `(n−1)·y`
  - `combine!(a, b)` gives `a.S₂ + a.S₁·b.n + b.S₂`

  With `Count` and `Sum` it gives `WMA` and the whole `LINEARREG` family,
  including `TSF`, as dependents. The bar position is the regression's `x`,
  and `Σx` and `Σx²` are closed forms in `n`.
- **`MaxIndex`/`MinIndex` monoids**: the arg-extreme, carried as a value plus a
  bars-since position that `combine!` shifts by the right operand's count. The
  tie-break is pinned to TA-Lib's by the goldens. They give `RollingMaxIndex`,
  `RollingMinIndex`, `RollingMinMaxIndex`, `Aroon` and `AroonOsc`.
- **Row-expression terms for the sum family**: `Sum` and `DotProduct` over a
  named row function (`Sum(:mfv => r -> clv(r) * r.volume)`) as well as over a
  column. The output name is the given name, and the term is formed at
  accumulator width like the existing term functors. This keeps `CMF`, `AD`,
  `VWAP`, `ADR`, `QStick`, `IMI` and `AccBands` as pure dependents instead of
  needing their own sum states or an `addcolumns` step before them.

## Model

- **One row is one bar.** Indicators never look at `:time` except through the
  transform folding them. Bars come from anywhere, whether a bar file, or
  `intervalize`/`summarizecycles` over ticks, as in the example above. Rows
  sharing a timestamp are distinct bars. With `key`, each key has its own
  series.
- **An indicator is a `Summarizer`.** The configuration is immutable. Its input
  column names are type parameters, so output names are known to the compiler, and
  its numeric parameters are fields. Parameters are validated at construction
  against the YAML `range`s, with an `ArgumentError` naming the TA-Lib limit.
  States are typed from the input schema (`fresh(s, intypes)`) and reset in place
  (`fresh!`), exactly per CausalFrames' summarizer interface.
- **Inputs.** A single-series indicator takes the column positionally:
  `RSI(:close)`, `Correl(:a, :b)`. A price-bar indicator takes its columns as
  keywords defaulting to the conventional names:
  `ATR(; high = :high, low = :low, close = :close)`,
  `CMF(; high, low, close, volume = :volume)`.
- **Parameters** are lowercase keywords with the TA-Lib defaults. `TimePeriod`
  becomes `period`, and the rest lose their `optIn` prefix and underscores
  (`fastperiod`, `nbdevup`, `slowkmatype`). MA types are symbols (`:sma`, `:ema`,
  `:wma`, `:dema`, `:tema`, `:trima`, `:kama`, `:mama`, `:t3`, `:hma`, `:zlema`,
  `:rma`), dispatched at construction into a type parameter so that the fold never
  branches on them.
- **Output names** follow CausalFrames' suffixing rule.
  - A single-series indicator suffixes its input: `RSI(:close)` gives
    `:close_rsi`.
  - A price-bar indicator uses its bare lowercase name: `:atr`.
  - A multi-output indicator appends each output's suffix from the name table:
    `:close_macd_macd`, `:close_macd_macdsignal`, `:close_macd_macdhist`.
  - A `name` keyword replaces the stem, which is how two periods of the same
    indicator coexist in one call: `RSI(:close; period = 7, name = :rsi7)`.
  - Constructors that return CausalFrames summarizers (case 1) keep the
    CausalFrames names, and CausalFrames' own uniqueness check applies to both.
- **Integer inputs** are widened to `Float64` (or to the column's float type if
  it is wider). Candlestick patterns emit `Int` (−100, 0 or 100). The index forms
  emit `Int` *bars since* the extreme (0 = this bar), not TA-Lib's absolute array
  index, which is meaningless in a stream. The tests convert between the two.

## Semantics

### Warm-up

An indicator emits `missing` until it has folded its **lookback** (TA-Lib's
`TA_<FN>_Lookback` at the given parameters) plus `unstable` further bars. The
`unstable` keyword defaults to 0 and exists on every function whose YAML carries
`unstable_period`. Output columns are therefore `Union{Missing, T}`. This matches
CausalFrames' empty-summary convention, and `forwardfill`/`fillmissing` apply
directly. Setting `unstable = k` reproduces exactly the rows TA-Lib emits under
`TA_SetUnstablePeriod(…, k)`, which is how the unstable-period test rows are
checked.

Seeding follows TA-Lib exactly:

- EMA is seeded with the SMA of its first `period` values.
- Wilder smoothing (RSI, ATR, ±DM, ±DI, DX, ADX) is seeded with the sum or mean
  of its first `period` values.
- T3, TEMA and similar chain their seeds in the same way.

That is what makes the values *bit-comparable* with TA-Lib, not just
asymptotically close.

### The `warmup` combinator

A bar count cannot be turned into a time span in general, so an indicator
cannot widen its own context the way `addrollingcolumns` does. Instead:

```julia
warmup(lookback, transform) -> (CausalPipeline -> CausalPipeline)
```

This runs `transform(p)` over `[start − lookback, stop)` and drops the output
rows with `time < start`. It is built only on the public `CausalPipeline(run)`
constructor and a small chunk-filtering iterator. It needs none of CausalFrames'
internal `chunkmap`, and it keeps the chunk protocol's no-empty-chunk rule. It is
causal: an output row at `t` still depends only on input rows at or before `t`.
Once `lookback` spans at least the indicator's lookback plus its effective memory
in bars, loading `[a, c)` equals concatenating `[a, b)` and `[b, c)`. That is
exact for finite-window indicators, and holds to the tolerance of the decayed
seed for recursive ones. So `warmup` restores the chunk-concatenation property
over split contexts that plain `addsummarycolumns` does not give.

**Path-dependent indicators** are those TA-Lib flags `path_dependent`: `AD`,
`ADOSC`, `OBV`, `NVI`, `PVI`, `PVT`, `WAD`, `VWAP`, `CumSum`, `SAR`, `SARExt`
and `SuperTrend`. They are anchored at the first bar they see, so their values
depend on where the context starts and no finite `warmup` makes them
split-invariant. Their docstrings say so. The idiomatic session reset is a key:
`VWAP()` under `key = [:symbol, :date]` restarts each day.

### Missing and non-finite inputs

- A `missing` input bar leaves a recursive state **unchanged** and emits
  `missing` for that row. It is skipped, not treated as poison. The CausalFrames
  accumulators poison on `missing` because a sum with an unknown term is unknown.
  A recursive state has no inverse, though, so poison would be permanent, and
  skipping is the only recoverable choice. The structured indicators inherit
  CausalFrames' own `missing` rules unchanged, since their state *is* the
  CausalFrames state.
- `NaN` and `±Inf` propagate as IEEE arithmetic and TA-Lib do, and the `RVOL`
  and `VWMA` zero-volume cases follow their YAML notes. The structured
  indicators recover once a nonfinite bar leaves the window, courtesy of
  CausalFrames' compensated, nonfinite-counting sums. Recursive ones do not
  recover, as in TA-Lib.

## Structure and fast paths

Every indicator is placed in the most structured tier it can lawfully claim.
The name table's "Tier" column records it.

- **Group** (`GroupSummarizer`, running O(1) with `downdate!`). The value is a
  function of invertible sums: `SMA`, `SUM`, `VAR`, `StdDev`, `Correl`, `VWMA`,
  `WMA`, the `LINEARREG` family, `CMF`, `ADR`, `QStick`, `IMI`, `AccBands`,
  `AD`, `VWAP`, and `BollingerBands` with `matype = :sma`. By the
  no-duplication rule each of these is a CausalFrames summarizer or a dependent
  over CausalFrames accumulators. A dependent is automatically a group, because
  its effective structure is its dependencies'.
- **Monoid** (`MonoidSummarizer`, segment tree O(log n) with `combine!`). The
  value is combinable over ordered sub-ranges:
  - `MAX`/`MIN`/`MINMAX`
  - the index forms
  - `MidPoint`, `MidPrice`, `Donchian`, `WillR`, `Aroon`/`AroonOsc`
  - `MOM`/`ROC*` (`First`/`Last`)
  - `RVOL` (`Sum` and `Last`)
  - the bar-local price transforms (`AvgPrice`, `MedPrice`, `TypPrice`,
    `WclPrice`, `BOP`, `MarketFI`), which are `Last`-dependents
- **Plain** (`Summarizer`). These have no lawful `combine!`, so they are folded
  row by row:
  - recursive filters: the EMA family, Wilder smoothing, `MACD`, `KAMA`, `T3`,
    `MAMA`, the Hilbert family
  - path-dependent states: `SAR`, `SuperTrend`, `OBV`
  - order statistics: `Percentile`, `PercentRank`
  - mean-deviation indicators: `CCI`, `AvgDev`
  - indicators whose per-row term needs the previous bar: `TRange`, `MFI`,
    `Beta` returns, `Vortex`
  - candlesticks

  A previous-bar indicator is promoted to monoid only if its state can carry
  its boundary bars so that `combine!` stays associative. That is decided per
  indicator in its stage PR, and the table is updated then.

The tiers matter because the structured indicators are **window-agnostic**. They
are defined once, with no period, and the window is supplied by the transform:

- a *time* window, through `addrollingcolumns((h1 = Hour(1),), MidPrice())` or
  `summarizewindows`, on CausalFrames' running and tree fast paths
- an *interval*, through `intervalize`
- a *bar count*, through `Bars`

A plain indicator can still be passed to `addrollingcolumns`, which re-folds each
window from a fresh state. That is correct but means a cold start per window,
which is rarely what a recursive indicator wants. Its docstring says so.

### Bar windows

`Bars(n, s)` is upstreamed to CausalFrames (see "Upstream prerequisites"). It
wraps a structured summarizer in a count window of the last `n` bars, for use
under `addsummarycolumns`:

- **Group `s`:** a typed ring buffer of the `n` live rows. Each new row is
  `update!`d and the evicted row is `downdate!`d, so each row costs O(1).
- **Monoid `s`:** a two-stack queue of `combine!`d states, O(1) amortized per
  row, which needs only `combine!` and `fresh!`.
- It emits `missing` until `n` bars have arrived, which is TA-Lib's lookback for
  these functions.

Every structured indicator takes a `period` keyword with TA-Lib's default and
returns it wrapped in `Bars`. With `period = nothing` it returns the bare,
window-agnostic summarizer instead, for use under time windows:

- `SMA(:x; period = 30)` returns `Bars(30, Mean(:x))`. `SMA` is a function,
  per case 1.
- `RollingMax(:x; period = 30)` returns `Bars(30, Max(:x))`.
- `MidPoint(:x)` returns `Bars(14, ·)` around the `MidPoint` dependent, and
  `MidPoint(:x; period = nothing)` is that dependent itself.
- `ROC(:x; period = 10)` windows `period + 1` bars. Its lookback is the bar
  `period` back.

The one oddity is that `MidPoint(:x) isa Bars`. This is an outer constructor
returning a wrapper, accepted so that the TA-Lib spelling and defaults work
unchanged. The same indicator therefore serves bar-count and time windows from
one implementation, and the tests hold the two against each other.

## Implementation architecture

- **Kernels** (`src/kernels/`) cover only what CausalFrames does not:
  - `RingBuffer{T}`: fixed capacity, allocated in `fresh` and reset by `fresh!`.
    It holds the look-back bars that recursive indicators and candlesticks read.
  - `EMAKernel` and `WilderKernel`: isbits, with SMA seeding built in.
  - `MAKernel{M}`: the moving-average family behind a type parameter, used by
    `MA`, `MACDExt`, `APO`/`PPO`/`PVO`, `Stoch*`, `KDJ` and non-SMA
    `BollingerBands`.
  - `CandleAverages`: TA-Lib's per-setting body and shadow averages, built on
    embedded CausalFrames `Mean` states.

  Window sums and extrema are never kernels. They are embedded CausalFrames
  states.
- **States compose kernels as concrete fields**, with no `Any` and no abstract
  field types. `update!` allocates nothing. `fresh!` zeroes everything in place,
  and allocation tests pin both. The per-row work sits behind CausalFrames'
  existing function barriers, so no new barrier is needed.
- **`foldseries(s, table) -> NamedTuple`** folds an indicator over a Tables.jl
  table of plain vectors, returning one vector per output column. It is the
  batch entry point for users outside a pipeline and the test path against
  TA-Lib. Because it drives the *same* `fresh`/`update!`/`value` calls,
  batch and streaming cannot diverge.
- **`MA(:x; period, matype)`** is a constructor function. It returns the
  CausalFrames `SMA` form for `:sma` and the plain summarizer for every other
  type, mirroring TA-Lib's `MA` dispatch.
- **Candlesticks** live in the `CausalIndicators.Candles` submodule, which
  re-exports nothing into the top level. That keeps 61 pattern names out of
  user namespaces: `using CausalIndicators.Candles` or `Candles.Hammer()`. The 11
  TA-Lib candle settings (`BodyLong`, `BodyVeryLong`, `BodyShort`, `BodyDoji`,
  `ShadowLong`, `ShadowVeryLong`, `ShadowShort`, `ShadowVeryShort`, `Near`,
  `Far`, `Equal`) form an immutable `CandleSettings` passed as a keyword,
  defaulting to TA-Lib's defaults. TA-Lib has a global settings table instead,
  which is not reproduced.

### Module layout

| File | Content |
|---|---|
| `src/CausalIndicators.jl` | module, includes, exports |
| `src/kernels/*.jl` | `RingBuffer`, `EMAKernel`, `WilderKernel`, `MAKernel`, `CandleAverages` |
| `src/foldseries.jl` | the batch entry point |
| `src/warmup.jl` | the context-widening combinator |
| `src/overlap.jl` | moving averages and bands |
| `src/momentum.jl` | momentum indicators |
| `src/volatility.jl` | volatility indicators |
| `src/statistics.jl` | statistic functions |
| `src/volume.jl` | volume indicators |
| `src/price.jl` | price transforms |
| `src/rolling.jl` | the rolling operators (the TA-Lib *Math Operators* group) |
| `src/cycle.jl` | the Hilbert-transform family and `MAMA` |
| `src/candles/*.jl` | the `Candles` submodule |
| `gen/` | the TA-Lib test extractor and golden generator (not part of the package) |

The file groups follow TA-Lib's own `group` field, so the YAML says where a
function lives.

## Testing

TA-Lib's own regression suite is the oracle, taken over in two complementary
forms and pinned to the reference commit.

**Extracted test tables.**

- `gen/extract_talib_tests.jl` parses each
  `src/tools/ta_regtest/ta_test_func/test_*.c`:
  - the file's own `typedef struct … TA_Test` field list, which differs from
    file to file
  - the `tableTest[]` initializer rows
  - the `TA_*_TEST` and `TA_MAType_*` identifiers

  It evaluates the rows' constant expressions (`252-14`) and writes
  `test/talib/tables/<file>.toml`, which is committed with the source path and
  commit.
- A small hand-written adapter per file maps each test identifier to a Julia
  constructor. Each row asserts:
  - the value at `expectedBegIdx + index` matches to the precision the C test
    uses (the expected values are rounded to 2–4 decimals)
  - the first non-`missing` row is `expectedBegIdx` (lookback + `unstable`)
  - the number of non-`missing` rows is `expectedNbElement`

  Rows exercising `startIdx`/`endIdx` sub-ranges run over the corresponding
  slice. Rows asserting TA-Lib error codes become constructor `ArgumentError`
  tests.
- C tests that are not tables, such as the candlestick settings matrix, the
  division-by-zero cases and the stream/finite-value checks, are ported by hand
  and listed in `test/talib/README.md`.
- The reference data (`TA_SREF_*_daily_ref_0_PRIV`, 252 OHLCV bars, and the
  10,000-bar `gData*` set) is extracted once to `test/data/*.csv`.

**Full-series goldens.** The tables check a handful of points per function.
`gen/golden/dump_golden.c` links a pinned TA-Lib build and uses its abstract
interface (`TA_GetFuncHandle`, `TA_CallFunc`) to run every in-scope function,
at its defaults and at every parameter set the tables use, over both
datasets. It writes `test/golden/<FN>.csv`. Every output is then compared bar by
bar at 1e-9 relative tolerance (exact for integer outputs), with the
lookback rows required to be `missing`. The generator runs by hand when the pin
moves. It is not built in CI, so CI needs no C toolchain.

**Streaming properties**, tested for every indicator:

- `load` through `addsummarycolumns` equals `foldseries`
- random re-chunkings of the input (via `readtable` over small partitions) give
  identical output
- a keyed run equals separate per-key runs, with keys interleaved
- `warmup` with a sufficient look-back makes split contexts concatenate to the
  whole context
- for structured indicators: `Bars` equals the goldens, and under
  `addrollingcolumns` the running or tree path equals the re-fold path
- zero allocations per row in the fold, and JET cleanliness on the per-row path

Aqua runs as in CausalFrames.

## Staging

One PR per stage. Each lands its code, extracted tables, goldens, docs and
README rows together, and updates this document where reality differs.

- **S0, upstream prerequisites (CausalFrames PRs):** `Bars`, the
  recency-weighted sum, `MaxIndex`/`MinIndex`, and row-expression sum terms.
- **S0′, scaffolding:**
  - the CausalFrames dependency. It is unregistered, so this uses `[sources]`
    on Julia ≥ 1.11 plus a CI `Pkg.develop(url = …)` step on 1.10.
  - kernels, `foldseries` and `warmup`
  - the extractor, the golden generator and the extracted data
  - CI with Aqua and JET
- **S1:** moving averages, the rolling operators and price transforms (28
  functions).
- **S2:** momentum I: MOM/ROC family, RSI, CMO, MACD family, APO/PPO, TRIX, the
  stochastics, WillR, CCI, BOP, Aroon, ULTOSC, MFI (23).
- **S3:** directional movement and volatility: TRange, ATR, NATR, ±DM, ±DI, DX,
  ADX, ADXR, SAR, SARExt, BollingerBands, StdDev, Var, AvgDev, AccBands,
  Keltner, Donchian, SuperTrend, ADR, CVI, MassIndex, RVI (24).
- **S4:** statistics and volume (21).
- **S5:** the TA-Lib 0.8 additions: AC, AO, CMOU, Coppock, DPO, ERI, ER, FOSC,
  Fractal, IMI, KDJ, QStick, SMI, TSI, VHF, Vortex, WAD, HeikinAshi (18).
- **S6:** the Hilbert-transform cycle family and `MAMA` (7).
- **S7:** the 61 candlestick patterns and `CandleSettings`.

A stage PR that finds an indicator can claim a stronger tier, or needs another
upstream accumulator, amends the name table and "Upstream prerequisites" in
the same PR.

## Open questions

- **Registering CausalFrames**, which would replace the `[sources]` and CI
  workaround with a plain `[compat]` entry.
- **The exact public shape of the upstream additions** (type names and output
  suffixes). This is settled in their CausalFrames PRs, and the name table
  follows.

## Name table

All 182 in-scope TA-Lib functions. The table is generated from the pinned YAML.

- **Relation** is the no-duplication resolution:
  - *CausalFrames only* (case 1)
  - *dependent* (case 2)
  - *dependent (upstream)* (case 2, over an S0 addition)
  - *new state* (no CausalFrames equivalent)
  - *constructor* (dispatch only)
- **Keywords** are the Julia keywords with TA-Lib's defaults.
- **Output suffixes** name the columns of a multi-output indicator.

| TA-Lib | Julia | Stage | Relation to CausalFrames | Tier | Inputs | Keywords (defaults) | Output suffixes |
|---|---|---|---|---|---|---|---|
| `AVGPRICE` | `AvgPrice` | S1 | dependent: `Last` | Monoid | open, high, low, close | — | (one column) |
| `CUMSUM` | `CumSum` | S1 | CausalFrames only: `Sum` (no window) | Group | real | — | (one column) |
| `DEMA` | `DEMA` | S1 | new state | plain | real | period=30 | (one column) |
| `EMA` | `EMA` | S1 | new state | plain | real | period=30 | (one column) |
| `HMA` | `HMA` | S1 | new state | plain | real | period=20 | (one column) |
| `KAMA` | `KAMA` | S1 | new state | plain | real | period=30 | (one column) |
| `MA` | `MA` | S1 | constructor (dispatches on `matype`) | per MA type | real | period=30, matype=:sma | (one column) |
| `MAVP` | `MAVP` | S1 | new state | plain | real, periods | minperiod=2, maxperiod=30, matype=:sma | (one column) |
| `MAX` | `RollingMax` | S1 | CausalFrames only: `Max` | Monoid | real | period=30 | (one column) |
| `MAXINDEX` | `RollingMaxIndex` | S1 | dependent (upstream): `MaxIndex` | Monoid | real | period=30 | (one column) |
| `MEDPRICE` | `MedPrice` | S1 | dependent: `Last` | Monoid | high, low | — | (one column) |
| `MIDPOINT` | `MidPoint` | S1 | dependent: `Max`, `Min` | Monoid | real | period=14 | (one column) |
| `MIDPRICE` | `MidPrice` | S1 | dependent: `Max`, `Min` | Monoid | high, low | period=14 | (one column) |
| `MIN` | `RollingMin` | S1 | CausalFrames only: `Min` | Monoid | real | period=30 | (one column) |
| `MININDEX` | `RollingMinIndex` | S1 | dependent (upstream): `MinIndex` | Monoid | real | period=30 | (one column) |
| `MINMAX` | `RollingMinMax` | S1 | CausalFrames only: `Min`, `Max` | Monoid | real | period=30 | min, max |
| `MINMAXINDEX` | `RollingMinMaxIndex` | S1 | dependent (upstream): `MinIndex`, `MaxIndex` | Monoid | real | period=30 | minidx, maxidx |
| `RMA` | `RMA` | S1 | new state | plain | real | period=30 | (one column) |
| `SMA` | `SMA` | S1 | CausalFrames only: `Mean` | Group | real | period=30 | (one column) |
| `SUM` | `RollingSum` | S1 | CausalFrames only: `Sum` | Group | real | period=30 | (one column) |
| `T3` | `T3` | S1 | new state | plain | real | period=5, vfactor=0.7 | (one column) |
| `TEMA` | `TEMA` | S1 | new state | plain | real | period=30 | (one column) |
| `TRIMA` | `TRIMA` | S1 | new state (nested `Mean` windows) | plain | real | period=30 | (one column) |
| `TYPPRICE` | `TypPrice` | S1 | dependent: `Last` | Monoid | high, low, close | — | (one column) |
| `VWMA` | `VWMA` | S1 | dependent: `DotProduct`, `Sum` | Group | real, volume | period=30 | (one column) |
| `WCLPRICE` | `WclPrice` | S1 | dependent: `Last` | Monoid | high, low, close | — | (one column) |
| `WMA` | `WMA` | S1 | dependent (upstream): recency sum, `Sum`, `Count` | Group | real | period=30 | (one column) |
| `ZLEMA` | `ZLEMA` | S1 | new state | plain | real | period=30 | (one column) |
| `APO` | `APO` | S2 | new state | plain | real | fastperiod=12, slowperiod=26, matype=:ema | (one column) |
| `AROON` | `Aroon` | S2 | dependent (upstream): `MaxIndex`, `MinIndex` | Monoid | high, low | period=14 | aroondown, aroonup |
| `AROONOSC` | `AroonOsc` | S2 | dependent (upstream): `MaxIndex`, `MinIndex` | Monoid | high, low | period=14 | (one column) |
| `BOP` | `BOP` | S2 | dependent: `Last` | Monoid | open, high, low, close | — | (one column) |
| `CCI` | `CCI` | S2 | new state (mean deviation needs the window) | plain | high, low, close | period=14 | (one column) |
| `CMO` | `CMO` | S2 | new state | plain | real | period=14 | (one column) |
| `MACD` | `MACD` | S2 | new state | plain | real | fastperiod=12, slowperiod=26, signalperiod=9 | macd, macdsignal, macdhist |
| `MACDEXT` | `MACDExt` | S2 | new state | plain | real | fastperiod=12, fastmatype=:sma, slowperiod=26, slowmatype=:sma, signalperiod=9, signalmatype=:sma | macd, macdsignal, macdhist |
| `MACDFIX` | `MACDFix` | S2 | new state | plain | real | signalperiod=9 | macd, macdsignal, macdhist |
| `MFI` | `MFI` | S2 | new state | plain | high, low, close, volume | period=14 | (one column) |
| `MOM` | `MOM` | S2 | dependent: `First`, `Last` | Monoid | real | period=10 | (one column) |
| `PPO` | `PPO` | S2 | new state | plain | real | fastperiod=12, slowperiod=26, matype=:ema | (one column) |
| `ROC` | `ROC` | S2 | dependent: `First`, `Last` | Monoid | real | period=10 | (one column) |
| `ROCP` | `ROCP` | S2 | dependent: `First`, `Last` | Monoid | real | period=10 | (one column) |
| `ROCR` | `ROCR` | S2 | dependent: `First`, `Last` | Monoid | real | period=10 | (one column) |
| `ROCR100` | `ROCR100` | S2 | dependent: `First`, `Last` | Monoid | real | period=10 | (one column) |
| `RSI` | `RSI` | S2 | new state | plain | real | period=14 | (one column) |
| `STOCH` | `Stoch` | S2 | new state | plain | high, low, close | fastkperiod=5, slowkperiod=3, slowkmatype=:sma, slowdperiod=3, slowdmatype=:sma | slowk, slowd |
| `STOCHF` | `StochF` | S2 | new state (%K is `WillR`'s dependent) | plain | high, low, close | fastkperiod=5, fastdperiod=3, fastdmatype=:sma | fastk, fastd |
| `STOCHRSI` | `StochRSI` | S2 | new state | plain | real | period=14, fastkperiod=5, fastdperiod=3, fastdmatype=:sma | fastk, fastd |
| `TRIX` | `TRIX` | S2 | new state | plain | real | period=30 | (one column) |
| `ULTOSC` | `ULTOSC` | S2 | new state | plain | high, low, close | timeperiod1=7, timeperiod2=14, timeperiod3=28 | (one column) |
| `WILLR` | `WillR` | S2 | dependent: `Max`, `Min`, `Last` | Monoid | high, low, close | period=14 | (one column) |
| `ACCBANDS` | `AccBands` | S3 | dependent (upstream): row-term `Sum`, `Count` | Group | high, low, close | period=20 | upperband, middleband, lowerband |
| `ADR` | `ADR` | S3 | dependent (upstream): row-term `Sum`, `Count` | Group | high, low | period=14 | (one column) |
| `ADX` | `ADX` | S3 | new state | plain | high, low, close | period=14 | (one column) |
| `ADXR` | `ADXR` | S3 | new state | plain | high, low, close | period=14 | (one column) |
| `ATR` | `ATR` | S3 | new state | plain | high, low, close | period=14 | (one column) |
| `AVGDEV` | `AvgDev` | S3 | new state (mean deviation needs the window) | plain | real | period=14 | (one column) |
| `BBANDS` | `BollingerBands` | S3 | dependent: `Mean`, `Std` (SMA type); new state otherwise | Group / plain | real | period=20, nbdevup=2, nbdevdn=2, matype=:sma | upperband, middleband, lowerband |
| `CVI` | `CVI` | S3 | new state | plain | high, low | period=10, rocperiod=10 | (one column) |
| `DONCHIAN` | `Donchian` | S3 | dependent: `Max`, `Min` | Monoid | high, low | period=20 | upperband, middleband, lowerband |
| `DX` | `DX` | S3 | new state | plain | high, low, close | period=14 | (one column) |
| `KC` | `KeltnerChannels` | S3 | new state | plain | high, low, close | period=20, atrperiod=10, nbdev=2 | upperband, middleband, lowerband |
| `MASSI` | `MassIndex` | S3 | new state | plain | high, low | fastperiod=9, slowperiod=25 | (one column) |
| `MINUS_DI` | `MinusDI` | S3 | new state | plain | high, low, close | period=14 | (one column) |
| `MINUS_DM` | `MinusDM` | S3 | new state | plain | high, low | period=14 | (one column) |
| `NATR` | `NATR` | S3 | new state | plain | high, low, close | period=14 | (one column) |
| `PLUS_DI` | `PlusDI` | S3 | new state | plain | high, low, close | period=14 | (one column) |
| `PLUS_DM` | `PlusDM` | S3 | new state | plain | high, low | period=14 | (one column) |
| `RVI` | `RVI` | S3 | new state | plain | real | period=14, stddevperiod=10 | (one column) |
| `SAR` | `SAR` | S3 | new state | plain | high, low | acceleration=0.02, maximum=0.2 | (one column) |
| `SAREXT` | `SARExt` | S3 | new state | plain | high, low | startvalue=0, offsetonreverse=0, accelerationinitlong=0.02, accelerationlong=0.02, accelerationmaxlong=0.2, accelerationinitshort=0.02, accelerationshort=0.02, accelerationmaxshort=0.2 | (one column) |
| `STDDEV` | `StdDev` | S3 | dependent: `Std(corrected=false)` | Group | real | period=5, nbdev=1 | (one column) |
| `SUPERTREND` | `SuperTrend` | S3 | new state | plain | high, low, close | period=10, multiplier=3.0 | supertrend, trend |
| `TRANGE` | `TRange` | S3 | new state (previous close) | plain | high, low, close | — | (one column) |
| `VAR` | `Var` | S3 | CausalFrames only: `Variance(corrected=false)` | Group | real | period=5, nbdev=1 | (one column) |
| `AD` | `AD` | S4 | dependent (upstream): row-term `Sum` (no window) | Group | high, low, close, volume | — | (one column) |
| `ADOSC` | `ADOSC` | S4 | new state | plain | high, low, close, volume | fastperiod=3, slowperiod=10 | (one column) |
| `BETA` | `Beta` | S4 | new state (returns need the previous bar) | plain | real0, real1 | period=5 | (one column) |
| `CMF` | `CMF` | S4 | dependent (upstream): row-term `Sum`, `Sum` | Group | high, low, close, volume | period=20 | (one column) |
| `CORREL` | `Correl` | S4 | CausalFrames only: `Correlation` | Group | real0, real1 | period=30 | (one column) |
| `EFI` | `EFI` | S4 | new state | plain | close, volume | period=13 | (one column) |
| `LINEARREG` | `LinearReg` | S4 | dependent (upstream): recency sum, `Sum`, `SumPower`, `Count` | Group | real | period=14 | (one column) |
| `LINEARREG_ANGLE` | `LinearRegAngle` | S4 | dependent (upstream): recency sum, `Sum`, `Count` | Group | real | period=14 | (one column) |
| `LINEARREG_INTERCEPT` | `LinearRegIntercept` | S4 | dependent (upstream): recency sum, `Sum`, `Count` | Group | real | period=14 | (one column) |
| `LINEARREG_SLOPE` | `LinearRegSlope` | S4 | dependent (upstream): recency sum, `Sum`, `Count` | Group | real | period=14 | (one column) |
| `MARKETFI` | `MarketFI` | S4 | dependent: `Last` | Monoid | high, low, volume | — | (one column) |
| `NVI` | `NVI` | S4 | new state | plain | close, volume | — | (one column) |
| `OBV` | `OBV` | S4 | new state (previous close) | plain | real, volume | — | (one column) |
| `PERCENTILE` | `Percentile` | S4 | new state (order statistic) | plain | real | period=30, percentile=50 | (one column) |
| `PERCENTRANK` | `PercentRank` | S4 | new state (order statistic) | plain | real | period=100 | (one column) |
| `PVI` | `PVI` | S4 | new state | plain | close, volume | — | (one column) |
| `PVO` | `PVO` | S4 | new state | plain | volume | fastperiod=12, slowperiod=26, matype=:ema | (one column) |
| `PVT` | `PVT` | S4 | new state | plain | close, volume | — | (one column) |
| `RVOL` | `RVOL` | S4 | dependent: `Sum`, `Last` over n+1 bars | Monoid | volume | period=20 | (one column) |
| `TSF` | `TSF` | S4 | dependent (upstream): recency sum, `Sum`, `Count` | Group | real | period=14 | (one column) |
| `VWAP` | `VWAP` | S4 | dependent (upstream): row-term `Sum`, `Sum` (no window) | Group | high, low, close, volume | — | (one column) |
| `AC` | `AC` | S5 | new state | plain | high, low | fastperiod=5, slowperiod=34, signalperiod=5 | (one column) |
| `AO` | `AO` | S5 | new state (two `Mean` windows) | plain | high, low | fastperiod=5, slowperiod=34 | (one column) |
| `CMOU` | `CMOU` | S5 | new state (previous bar) | plain | real | period=14 | (one column) |
| `COPPOCK` | `Coppock` | S5 | new state | plain | real | wmaperiod=10, roc1period=11, roc2period=14 | (one column) |
| `DPO` | `DPO` | S5 | new state | plain | real | period=20 | (one column) |
| `ER` | `ER` | S5 | new state | plain | real | period=10 | (one column) |
| `ERI` | `ERI` | S5 | new state | plain | high, low, close | period=13 | bullpower, bearpower |
| `FOSC` | `FOSC` | S5 | new state | plain | real | period=5 | (one column) |
| `FRACTAL` | `Fractal` | S5 | new state | plain | high, low | leftbars=2, rightbars=2 | swinghigh, swinglow |
| `HA` | `HeikinAshi` | S5 | new state | plain | open, high, low, close | — | haopen, hahigh, halow, haclose |
| `IMI` | `IMI` | S5 | dependent (upstream): row-term `Sum`s | Group | open, close | period=14 | (one column) |
| `KDJ` | `KDJ` | S5 | new state | plain | high, low, close | fastkperiod=9, slowkperiod=3, slowkmatype=:rma, slowdperiod=3, slowdmatype=:rma | k, d, j |
| `QSTICK` | `QStick` | S5 | dependent (upstream): row-term `Sum`, `Count` | Group | open, close | period=10 | (one column) |
| `SMI` | `SMI` | S5 | new state | plain | high, low, close | period=13, fastperiod=2, slowperiod=25, signalperiod=9 | smi, smisignal |
| `TSI` | `TSI` | S5 | new state | plain | real | firstperiod=25, secondperiod=13 | (one column) |
| `VHF` | `VHF` | S5 | new state | plain | real | period=28 | (one column) |
| `VORTEX` | `Vortex` | S5 | new state | plain | high, low, close | period=14 | plusvi, minusvi |
| `WAD` | `WAD` | S5 | new state | plain | high, low, close | — | (one column) |
| `HT_DCPERIOD` | `HTDCPeriod` | S6 | new state | plain | real | — | (one column) |
| `HT_DCPHASE` | `HTDCPhase` | S6 | new state | plain | real | — | (one column) |
| `HT_PHASOR` | `HTPhasor` | S6 | new state | plain | real | — | inphase, quadrature |
| `HT_SINE` | `HTSine` | S6 | new state | plain | real | — | sine, leadsine |
| `HT_TRENDLINE` | `HTTrendline` | S6 | new state | plain | real | — | (one column) |
| `HT_TRENDMODE` | `HTTrendMode` | S6 | new state | plain | real | — | (one column) |
| `MAMA` | `MAMA` | S6 | new state | plain | real | fastlimit=0.5, slowlimit=0.05 | mama, fama |
| `CDL2CROWS` | `Candles.TwoCrows` | S7 | new state (shared `CandleAverages`) | plain | open, high, low, close | — | (one column) |
| `CDL3BLACKCROWS` | `Candles.ThreeBlackCrows` | S7 | new state (shared `CandleAverages`) | plain | open, high, low, close | — | (one column) |
| `CDL3INSIDE` | `Candles.ThreeInside` | S7 | new state (shared `CandleAverages`) | plain | open, high, low, close | — | (one column) |
| `CDL3LINESTRIKE` | `Candles.ThreeLineStrike` | S7 | new state (shared `CandleAverages`) | plain | open, high, low, close | — | (one column) |
| `CDL3OUTSIDE` | `Candles.ThreeOutside` | S7 | new state (shared `CandleAverages`) | plain | open, high, low, close | — | (one column) |
| `CDL3STARSINSOUTH` | `Candles.ThreeStarsInTheSouth` | S7 | new state (shared `CandleAverages`) | plain | open, high, low, close | — | (one column) |
| `CDL3WHITESOLDIERS` | `Candles.ThreeWhiteSoldiers` | S7 | new state (shared `CandleAverages`) | plain | open, high, low, close | — | (one column) |
| `CDLABANDONEDBABY` | `Candles.AbandonedBaby` | S7 | new state (shared `CandleAverages`) | plain | open, high, low, close | penetration=0.3 | (one column) |
| `CDLADVANCEBLOCK` | `Candles.AdvanceBlock` | S7 | new state (shared `CandleAverages`) | plain | open, high, low, close | — | (one column) |
| `CDLBELTHOLD` | `Candles.BeltHold` | S7 | new state (shared `CandleAverages`) | plain | open, high, low, close | — | (one column) |
| `CDLBREAKAWAY` | `Candles.Breakaway` | S7 | new state (shared `CandleAverages`) | plain | open, high, low, close | — | (one column) |
| `CDLCLOSINGMARUBOZU` | `Candles.ClosingMarubozu` | S7 | new state (shared `CandleAverages`) | plain | open, high, low, close | — | (one column) |
| `CDLCONCEALBABYSWALL` | `Candles.ConcealingBabySwallow` | S7 | new state (shared `CandleAverages`) | plain | open, high, low, close | — | (one column) |
| `CDLCOUNTERATTACK` | `Candles.Counterattack` | S7 | new state (shared `CandleAverages`) | plain | open, high, low, close | — | (one column) |
| `CDLDARKCLOUDCOVER` | `Candles.DarkCloudCover` | S7 | new state (shared `CandleAverages`) | plain | open, high, low, close | penetration=0.5 | (one column) |
| `CDLDOJI` | `Candles.Doji` | S7 | new state (shared `CandleAverages`) | plain | open, high, low, close | — | (one column) |
| `CDLDOJISTAR` | `Candles.DojiStar` | S7 | new state (shared `CandleAverages`) | plain | open, high, low, close | — | (one column) |
| `CDLDRAGONFLYDOJI` | `Candles.DragonflyDoji` | S7 | new state (shared `CandleAverages`) | plain | open, high, low, close | — | (one column) |
| `CDLENGULFING` | `Candles.Engulfing` | S7 | new state (shared `CandleAverages`) | plain | open, high, low, close | — | (one column) |
| `CDLEVENINGDOJISTAR` | `Candles.EveningDojiStar` | S7 | new state (shared `CandleAverages`) | plain | open, high, low, close | penetration=0.3 | (one column) |
| `CDLEVENINGSTAR` | `Candles.EveningStar` | S7 | new state (shared `CandleAverages`) | plain | open, high, low, close | penetration=0.3 | (one column) |
| `CDLGAPSIDESIDEWHITE` | `Candles.GapSideSideWhite` | S7 | new state (shared `CandleAverages`) | plain | open, high, low, close | — | (one column) |
| `CDLGRAVESTONEDOJI` | `Candles.GravestoneDoji` | S7 | new state (shared `CandleAverages`) | plain | open, high, low, close | — | (one column) |
| `CDLHAMMER` | `Candles.Hammer` | S7 | new state (shared `CandleAverages`) | plain | open, high, low, close | — | (one column) |
| `CDLHANGINGMAN` | `Candles.HangingMan` | S7 | new state (shared `CandleAverages`) | plain | open, high, low, close | — | (one column) |
| `CDLHARAMI` | `Candles.Harami` | S7 | new state (shared `CandleAverages`) | plain | open, high, low, close | — | (one column) |
| `CDLHARAMICROSS` | `Candles.HaramiCross` | S7 | new state (shared `CandleAverages`) | plain | open, high, low, close | — | (one column) |
| `CDLHIGHWAVE` | `Candles.HighWave` | S7 | new state (shared `CandleAverages`) | plain | open, high, low, close | — | (one column) |
| `CDLHIKKAKE` | `Candles.Hikkake` | S7 | new state (shared `CandleAverages`) | plain | open, high, low, close | — | (one column) |
| `CDLHIKKAKEMOD` | `Candles.HikkakeMod` | S7 | new state (shared `CandleAverages`) | plain | open, high, low, close | — | (one column) |
| `CDLHOMINGPIGEON` | `Candles.HomingPigeon` | S7 | new state (shared `CandleAverages`) | plain | open, high, low, close | — | (one column) |
| `CDLIDENTICAL3CROWS` | `Candles.IdenticalThreeCrows` | S7 | new state (shared `CandleAverages`) | plain | open, high, low, close | — | (one column) |
| `CDLINNECK` | `Candles.InNeck` | S7 | new state (shared `CandleAverages`) | plain | open, high, low, close | — | (one column) |
| `CDLINVERTEDHAMMER` | `Candles.InvertedHammer` | S7 | new state (shared `CandleAverages`) | plain | open, high, low, close | — | (one column) |
| `CDLKICKING` | `Candles.Kicking` | S7 | new state (shared `CandleAverages`) | plain | open, high, low, close | — | (one column) |
| `CDLKICKINGBYLENGTH` | `Candles.KickingByLength` | S7 | new state (shared `CandleAverages`) | plain | open, high, low, close | — | (one column) |
| `CDLLADDERBOTTOM` | `Candles.LadderBottom` | S7 | new state (shared `CandleAverages`) | plain | open, high, low, close | — | (one column) |
| `CDLLONGLEGGEDDOJI` | `Candles.LongLeggedDoji` | S7 | new state (shared `CandleAverages`) | plain | open, high, low, close | — | (one column) |
| `CDLLONGLINE` | `Candles.LongLine` | S7 | new state (shared `CandleAverages`) | plain | open, high, low, close | — | (one column) |
| `CDLMARUBOZU` | `Candles.Marubozu` | S7 | new state (shared `CandleAverages`) | plain | open, high, low, close | — | (one column) |
| `CDLMATCHINGLOW` | `Candles.MatchingLow` | S7 | new state (shared `CandleAverages`) | plain | open, high, low, close | — | (one column) |
| `CDLMATHOLD` | `Candles.MatHold` | S7 | new state (shared `CandleAverages`) | plain | open, high, low, close | penetration=0.5 | (one column) |
| `CDLMORNINGDOJISTAR` | `Candles.MorningDojiStar` | S7 | new state (shared `CandleAverages`) | plain | open, high, low, close | penetration=0.3 | (one column) |
| `CDLMORNINGSTAR` | `Candles.MorningStar` | S7 | new state (shared `CandleAverages`) | plain | open, high, low, close | penetration=0.3 | (one column) |
| `CDLONNECK` | `Candles.OnNeck` | S7 | new state (shared `CandleAverages`) | plain | open, high, low, close | — | (one column) |
| `CDLPIERCING` | `Candles.Piercing` | S7 | new state (shared `CandleAverages`) | plain | open, high, low, close | — | (one column) |
| `CDLRICKSHAWMAN` | `Candles.RickshawMan` | S7 | new state (shared `CandleAverages`) | plain | open, high, low, close | — | (one column) |
| `CDLRISEFALL3METHODS` | `Candles.RiseFallThreeMethods` | S7 | new state (shared `CandleAverages`) | plain | open, high, low, close | — | (one column) |
| `CDLSEPARATINGLINES` | `Candles.SeparatingLines` | S7 | new state (shared `CandleAverages`) | plain | open, high, low, close | — | (one column) |
| `CDLSHOOTINGSTAR` | `Candles.ShootingStar` | S7 | new state (shared `CandleAverages`) | plain | open, high, low, close | — | (one column) |
| `CDLSHORTLINE` | `Candles.ShortLine` | S7 | new state (shared `CandleAverages`) | plain | open, high, low, close | — | (one column) |
| `CDLSPINNINGTOP` | `Candles.SpinningTop` | S7 | new state (shared `CandleAverages`) | plain | open, high, low, close | — | (one column) |
| `CDLSTALLEDPATTERN` | `Candles.StalledPattern` | S7 | new state (shared `CandleAverages`) | plain | open, high, low, close | — | (one column) |
| `CDLSTICKSANDWICH` | `Candles.StickSandwich` | S7 | new state (shared `CandleAverages`) | plain | open, high, low, close | — | (one column) |
| `CDLTAKURI` | `Candles.Takuri` | S7 | new state (shared `CandleAverages`) | plain | open, high, low, close | — | (one column) |
| `CDLTASUKIGAP` | `Candles.TasukiGap` | S7 | new state (shared `CandleAverages`) | plain | open, high, low, close | — | (one column) |
| `CDLTHRUSTING` | `Candles.Thrusting` | S7 | new state (shared `CandleAverages`) | plain | open, high, low, close | — | (one column) |
| `CDLTRISTAR` | `Candles.Tristar` | S7 | new state (shared `CandleAverages`) | plain | open, high, low, close | — | (one column) |
| `CDLUNIQUE3RIVER` | `Candles.UniqueThreeRiver` | S7 | new state (shared `CandleAverages`) | plain | open, high, low, close | — | (one column) |
| `CDLUPSIDEGAP2CROWS` | `Candles.UpsideGapTwoCrows` | S7 | new state (shared `CandleAverages`) | plain | open, high, low, close | — | (one column) |
| `CDLXSIDEGAP3METHODS` | `Candles.XSideGapThreeMethods` | S7 | new state (shared `CandleAverages`) | plain | open, high, low, close | — | (one column) |
