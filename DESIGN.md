# CausalIndicators.jl — Design

CausalIndicators provides the technical indicators of
[TA-Lib](https://github.com/TA-Lib/ta-lib) as causal, streaming building blocks
for [CausalFrames.jl](https://github.com/farrellm/CausalFrames.jl) pipelines.
An indicator here is a CausalFrames `Summarizer`. The transforms CausalFrames
already has fold it one bar at a time, per key, across chunk boundaries. The
package adds no pipeline machinery. Everything generic it needs, including the
bar-count window and the context-widening `warmup`, is added to CausalFrames
first (see "Upstream prerequisites").

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

indicators(p) = p |>
    addrollingcolumns((b20 = Bars(20),),
        [Mean(:close), Std(:close; corrected = false), MidPrice(), WillR()];
        key = :symbol) |>
    addsummarycolumns([RSI(:close), MACD(:close), ATR()]; key = :symbol)

frame = load(Context(DateTime(2026, 1, 5), DateTime(2026, 2, 1)),
             bars |> warmup(Day(3), indicators))
```

This emits `:b20_close_mean`, `:b20_close_std`, `:b20_midprice`, `:b20_willr`,
`:close_rsi`, the three `:close_macd_*` columns and `:atr`.

The structured indicators (sums, extrema, and their dependents) go under
`addrollingcolumns` with a bar-count window, where CausalFrames' running and
tree fast paths apply. The recursive ones go under `addsummarycolumns`. They are
kept in separate calls because a single plain summarizer in an
`addrollingcolumns` call puts the whole call on the re-fold path.

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
- **Bit-for-bit agreement with TA-Lib.** Every sum is a CausalFrames compensated
  sum (see "Warm-up"), so values match TA-Lib to the golden tolerance, not
  exactly.
- **Acausal variants.** TA-Lib 0.8.1 is causal throughout. For example, `FRACTAL`
  reports a pivot on its confirmation bar, and `DPO` is written at the bar whose
  average produced it. So nothing here belongs in CausalFrames' `Acausal`
  submodule. If the caller wants a centred or shifted plotting convention, they
  apply `Acausal.lead` themselves.

**Pinned reference.** TA-Lib 0.8.1, commit
[`2aa8eb0`](https://github.com/TA-Lib/ta-lib/tree/2aa8eb0d79bcfc4d2ff3f7b445d37958c48e0788).
Each function's contract comes from two files, and each docstring cites both:

- `ta_codegen/input/<fn>/<fn>.yaml`: inputs, parameter ranges and defaults,
  outputs, and the `unstable_period`/`path_dependent` flags
- `<fn>.md`: the formula and edge cases

Moving to a later TA-Lib is a deliberate PR that regenerates the extracted tests
and goldens (see "Testing").

## No duplication with CausalFrames

**No summarizer, state or kernel in this package may compute something
CausalFrames already computes.** Every TA-Lib function that overlaps CausalFrames
is resolved in exactly one of three ways. The "Relation" column of the name
table records which:

1. **CausalFrames only.** If the value is *identical* to a CausalFrames
   summarizer under some window, that summarizer is the implementation. This
   package contributes only the TA-Lib tests for it, and **no constructor**.
   Structured indicators take their window from the transform (see "Windows"),
   so a TA-Lib-named constructor would be a bare alias: `SMA(:x)` would just be
   `Mean(:x)`. The name table maps each such function to its CausalFrames
   spelling, and the README gives the same list.
   - `SMA` → `Mean`, `SUM` → `Sum`, `MAX`/`MIN`/`MINMAX` → `Max`/`Min`,
     `VAR` → `Variance(corrected = false)`, `CORREL` → `Correlation`, all under
     `Bars(period)`
   - `CUMSUM` → `Sum` under `addsummarycolumns`, with no window

   CausalFrames bakes `corrected` into the state type, not the output name. So
   `VAR` (and `StdDev`, through its hidden `Std(corrected = false)`) cannot sit
   in the same call as a user's corrected `Variance(:x)` or `Std(:x)` over the
   same column. The docstrings say so, and the fix is a second call.
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
   - `ROC` reads `First` and `Last` over its window.
   - `TRange` reads `Last(:high)`, `Last(:low)` and `First(:close)` over
     `Bars(2)`.
   - `AvgPrice` reads `Last` of four columns.
3. **Move it into CausalFrames.** If an indicator needs a *generic* accumulator
   or operator that CausalFrames lacks, it is first added to CausalFrames as a
   prerequisite PR, with its own tests, docs and DESIGN.md entry. The indicator
   here then becomes case 2. The upstream additions are listed under
   "Upstream prerequisites". The rule also runs the other way: if a CausalFrames
   summarizer ever turns out to be indicator-specific, it moves here instead of
   being mirrored.

The rule also binds internal code:

- **Windows inside recursive indicators.** Some recursive indicators need a
  window sum, mean or extremum, such as KAMA's volatility sum, CCI's mean, AO's
  two means and Stoch's %K range. They embed CausalFrames states through the
  upstream count-window helper. They never hand-roll a compensated sum, a ring
  buffer or a monotone deque.
- **Linear regression.** CausalFrames already has `LinearRegression`, but it
  regresses on predictor *columns*. The `LINEARREG` family regresses on the bar
  position, which is not a column. Its closed forms in `n` (`Σx`, `Σx²`) are
  therefore the only regression code here, and they sit on the upstream
  recency-weighted sum.

### Upstream prerequisites

These are added to CausalFrames before the stages that need them (stage S0).
The exact public names and output suffixes are settled in their CausalFrames
PRs (see "Open questions").

a. **`warmup(lookback, transform)`.** This is a transform of transforms:
   it runs `transform(p)` over `[start − lookback, stop)` and drops the output
   rows with `time < start`.
   - **Causality.** An output row at `t` still depends only on input rows at or
     before `t`.
   - **Why it is generic.** Every stateful transform loses the
     chunk-concatenation property over split contexts, not only indicators.
     This includes `addsummarycolumns` (a cumulative `Sum` or a running `Mean`),
     `forwardfill` and bar-count windows. `warmup` restores the property once
     `lookback` covers the state's effective memory.
   - **Where it goes.** It sits in the "Causality and streaming" section, next to
     `lag`/`lagcontext`, whose context-shifting it mirrors. It is lowercase,
     following CausalFrames' naming rule.
   - **Chunk protocol.** It keeps the no-empty-chunk rule.

b. **A bar-count look-back for `addrollingcolumns`:** `Bars(n)` as a window
   value, as in `(b20 = Bars(20),)`, which can be mixed with time look-backs in
   one call.
   - **Membership.** The window holds the last `n` summarized rows with
     `time ≤ t` under the row's key.
   - **Ties.** Rows sharing a timestamp share a window, as they do under time
     look-backs. This matches TA-Lib only when times are unique per key, which
     bar data gives.
   - **Partial windows.** A window holding fewer than `n` rows emits `missing`
     for every output, even for `Sum` and `Count`, whose empty value is `0`.
     This is exactly TA-Lib's lookback, and it makes the columns
     `Union{Missing, T}`.
   - **Context.** A bar count has no time span, so the context is not widened.
     `warmup` is the documented remedy.
   - **Fast paths.** Running mode evicts the oldest row once a window exceeds
     `n` rows. Tree mode's head index is `count − n`. Re-fold mode is
     unchanged.
   - **Why a look-back rather than a `Bars(n, s)` summarizer wrapper.**
     Dependency expansion and name-keyed deduplication work unchanged, so
     `Mean(:x)` and `Std(:x)` under the same `Bars(20)` share one `Sum(:x)`. A
     wrapper would fold each inner dependency closure privately.

c. **The oldest-first `downdate!` law, and two groups under it.**
   CausalFrames' `downdate!` contract removes *any* previously folded row. Its
   running modes (`addrollingcolumns`, `summarizewindows`) and the count-window
   helper (g) only ever evict oldest-first, though, so a new, documented law
   lets a group rely on that. Two summarizers need it:
   - **A recency-weighted sum** `Σₖ k·yₖ`, where `k` is the number of bars
     since that row (0 for the newest). It carries its own count and `Σy`,
     because a state cannot read a sibling state during `update!`.
     - `update!` adds `Σy` to the weighted sum, then adds `y` to `Σy`.
     - `downdate!` removes the oldest row by subtracting `(n−1)·y`.
     - `combine!(a, b)` gives `a.S₂ + a.S₁·b.n + b.S₂`.
     - It uses the sum family's representation: compensated for
       fixed-precision floats, and counting nonfinite and `missing` terms, so
       rolling windows recover.

     With `Count` and `Sum` it gives `WMA` and the whole `LINEARREG` family,
     including `TSF`, as dependents.
   - **`Last` as a group.** Evicting the oldest row never changes the last
     value unless it empties the window, so `Last` keeps a live-row count and
     its `downdate!` decrements it, clearing the value at zero. A count rather
     than the last row's time is what makes ties unambiguous. `Last` leaves
     the state it shares with `Min`/`Max`/`First`. `First` cannot follow: the
     oldest row is exactly the one it reports.

     This moves every dependent that reads only `Last` and group accumulators
     into the Group tier: the bar-local price transforms, `RVOL` and
     `PercentRank`.

d. **`MaxIndex`/`MinIndex` monoids.** Each is the arg-extreme, carried as a
   value plus a bars-since position that `combine!` shifts by the right
   operand's count.
   - **Tie-break.** It is defined upstream as most recent wins, meaning the
     smallest bars-since. That is expected to match TA-Lib's `>=` scans, and
     must be checked against the pinned source before the upstream PR, since
     CausalFrames cannot depend on TA-Lib goldens.
   - **Users.** These give `RollingMaxIndex`, `RollingMinIndex`,
     `RollingMinMaxIndex`, `Aroon` and `AroonOsc`.

e. **Row-expression terms for the sum family.** `Sum` and `DotProduct` can
   fold a named row function (`Sum(:mfv => r -> clv(r) * r.volume)`) as well as
   a column. The output name is the given name.
   - **Accumulator type.** It is `sumtype(Base.promote_op(f, rowtype))`, so the
     term is formed at accumulator width like the existing term functors.
   - **Deduplication.** Deduplication is by output name, so `Sum(:mfv => f)`
     and `Sum(:mfv => g)` would silently merge. The function's type is part of
     the configuration: equal names with different functions are an
     `ArgumentError`.
   - **Names.** The dependents here namespace their hidden terms (`:cmf_mfv`)
     so that they never collide with the user's.

   This keeps `CMF`, `AD`, `VWAP`, `ADR`, `QStick`, `IMI` and `AccBands` as
   pure dependents, rather than needing their own sum states or an
   `addcolumns` step before them.

f. **A sorted-multiset accumulator**, with dependents `Quantile(:x, p)` and
   `PercentRank(:x)`, the rank of the newest value (`Last`) in the window.
   - **Structure.** Insertion and deletion are inverses and `combine!` is a
     merge, so it is a `GroupSummarizer`.
   - **Size.** Its state is O(window). It documents that, as `CountDistinct`
     does.
   - **Interpolation.** `Quantile`'s interpolation rule is a keyword, and
     TA-Lib's rule must be one of its values.
   - **Allocation.** The accumulator's own value is a borrowed read-only view,
     like the segment tree's query result, so emitting it does not allocate.
   - **Newest value.** `PercentRank` reads it from `Last`, which must be a
     group (c): a monoid in the call would demote it from running mode to tree
     mode, where each `combine!` of this state is an O(window) merge.

   `Percentile` and `PercentRank` are then case 2 in the Group tier.

g. **A count-window state helper**, unexported extension API like `fresh` and
   `update!`, for embedding inside other states. It wraps a structured state
   over the last `n` rows:
   - **Group state.** A typed ring buffer of the `n` live rows. Each new row is
     `update!`d and the evicted row `downdate!`d, so each row costs O(1).
   - **Monoid state.** A two-stack queue of `combine!`d states, with all of them
     preallocated, O(1) amortized per row.
   - **Missing.** It reports `missing` until `n` rows have arrived.

   Now that bar windows are a transform, recursive states cannot get a window
   through one, so they need this helper. Its users are KAMA, CCI, AvgDev, AO,
   TRIMA, the Stoch family's %K, `MAKernel`'s `:sma`, non-SMA
   `BollingerBands` and `CandleAverages`. It also serves (b) internally if that
   proves simpler, so there is one ring buffer in the two packages.

## Model

- **One row is one bar.** Indicators never look at `:time` except through the
  transform folding them. Bars come from anywhere, whether a bar file, or
  `intervalize`/`summarizecycles` over ticks, as in the example above. Under
  `addsummarycolumns`, rows sharing a timestamp are distinct bars. Under a
  `Bars` window they share a window (see (b)). With `key`, each key has its own
  series.
- **An indicator is a `Summarizer`.** The configuration is immutable.
  - Its input column names are type parameters, so output names are known to
    the compiler, and its numeric parameters are fields.
  - Parameters are validated at construction against the YAML `range`s, with an
    `ArgumentError` naming the TA-Lib limit.
  - States are typed from the input schema (`fresh(s, intypes)`) and reset in
    place (`fresh!`), exactly per CausalFrames' summarizer interface.
- **Inputs.** A single-series indicator takes the column positionally:
  `RSI(:close)`, `MidPoint(:close)`. A price-bar indicator takes its columns as
  keywords defaulting to the conventional names:
  `ATR(; high = :high, low = :low, close = :close)`,
  `CMF(; high, low, close, volume = :volume)`.
- **Parameters** are lowercase keywords with the TA-Lib defaults.
  - **Naming.** `TimePeriod` becomes `period`, and the rest lose their `optIn`
    prefix and underscores (`fastperiod`, `nbdevup`, `slowkmatype`).
  - **Structured indicators have no window parameter.** Their TA-Lib
    `TimePeriod` is the transform's window, and the name table gives the
    default as `window: Bars(n)`.
  - **MA types** are symbols (`:sma`, `:ema`, `:wma`, `:dema`, `:tema`,
    `:trima`, `:kama`, `:mama`, `:t3`, `:hma`, `:zlema`, `:rma`). They are
    dispatched at construction into a type parameter so that the fold never
    branches on them.
- **Output names** follow CausalFrames' suffixing rule.
  - A single-series indicator suffixes its input: `RSI(:close)` gives
    `:close_rsi`.
  - A price-bar indicator uses its bare lowercase name: `:atr`.
  - A multi-output indicator appends each output's suffix from the name table:
    `:close_macd_macd`, `:close_macd_macdsignal`, `:close_macd_macdhist`.
  - Under `addrollingcolumns`, the window name is prefixed, as for every
    summarizer: `:b14_willr`.
  - A `name` keyword on a plain indicator replaces the stem, which is how two
    periods of the same indicator coexist in one call:
    `RSI(:close; period = 7, name = :rsi7)`. Structured indicators do not need
    one, because two periods are two windows.
- **Integer inputs** are widened to `Float64` (or to the column's float type if
  it is wider).
- **Integer outputs.**
  - Candlestick patterns emit `Int`: −100, 0 or 100.
  - The index forms emit `Int` *bars since* the extreme (0 = this bar), not
    TA-Lib's absolute array index, which is meaningless in a stream. The tests
    convert between the two.

## Semantics

### Warm-up

An indicator emits `missing` until it has folded its **lookback** plus
`unstable` further bars. The lookback is TA-Lib's `TA_<FN>_Lookback` at the
given parameters.

- **`unstable`.** The keyword defaults to 0 and exists on every function whose
  YAML carries `unstable_period`. Setting `unstable = k` reproduces exactly the
  rows TA-Lib emits under `TA_SetUnstablePeriod(…, k)`, which is how the
  unstable-period test rows are checked.
- **Output types.** Output columns are therefore `Union{Missing, T}`. This
  matches CausalFrames' empty-summary convention, and `forwardfill` and
  `fillmissing` apply directly.
- **Structured indicators.** The partial-window rule of `Bars` produces their
  lookback (see (b)).

Seeding follows TA-Lib's rules exactly, meaning which bars seed and in what
order:

- EMA is seeded with the SMA of its first `period` values.
- Wilder smoothing (RSI, ATR, ±DM, ±DI, DX, ADX) is seeded with the sum or mean
  of its first `period` values.
- T3, TEMA and similar chain their seeds in the same way.

**Every sum is a CausalFrames compensated sum,** including these seeds, which
come from embedded CausalFrames `Sum`/`Mean` states rather than a plain `+=`
loop. There is one summation implementation across both packages, with no
sliding-sum drift. Values therefore agree with TA-Lib to the golden tolerance,
usually more accurately than TA-Lib's own running sums, but they are not
bit-identical.

### Split contexts and `warmup`

An indicator's state starts at the context's first bar, so loading `[a, c)` is
not the concatenation of `[a, b)` and `[b, c)`. The upstream `warmup` (see (a))
restores that property. Loading with `warmup(lookback, …)` concatenates over
split contexts once `lookback` spans at least the indicator's lookback plus its
effective memory in bars:

- for finite-window indicators, the concatenation is exact
- for recursive ones, it holds to the tolerance of the decayed seed

A bar count cannot be turned into a time span in general, so the caller chooses
`lookback`. No indicator widens its own context.

**Path-dependent indicators** are those TA-Lib flags `path_dependent`: `AD`,
`ADOSC`, `OBV`, `NVI`, `PVI`, `PVT`, `WAD`, `VWAP`, `CUMSUM` (a windowless
`Sum`), `SAR`, `SARExt` and `SuperTrend`.

- They are anchored at the first bar they see, so their values depend on where
  the context starts, and no finite `warmup` makes them split-invariant. Their
  docstrings say so.
- The idiomatic session reset is a key. For example, `VWAP()` under
  `key = [:symbol, :date]` restarts each day.

### Missing and non-finite inputs

- **`missing` in recursive states.** A `missing` input bar leaves a recursive
  state **unchanged** and emits `missing` for that row. It is skipped, not
  treated as poison.
  - The CausalFrames accumulators poison on `missing`, because a sum with an
    unknown term is unknown.
  - A recursive state has no inverse, though, so poison would be permanent.
    Skipping is the only recoverable choice.
- **`missing` in structured indicators.** They inherit CausalFrames' own
  `missing` rules unchanged, since their state *is* the CausalFrames state.
- **`NaN` and `±Inf`** propagate as IEEE arithmetic and TA-Lib do.
  - The `RVOL` and `VWMA` zero-volume cases follow their YAML notes.
  - Structured indicators recover once a nonfinite bar leaves the window,
    because CausalFrames' sums are compensated and count nonfinite terms.
  - Recursive ones do not recover, as in TA-Lib.

## Structure and fast paths

Every indicator is placed in the most structured tier it can lawfully claim.
The name table's "Tier" column records it.

- **Group** (`GroupSummarizer`, running O(1) with `downdate!`). The value is a
  function of invertible sums, the sorted multiset, or `Last` (c):
  - `SMA`, `SUM`, `VAR`, `StdDev`, `Correl`, `VWMA`
  - `WMA`, the `LINEARREG` family
  - `CMF`, `ADR`, `QStick`, `IMI`, `AccBands`, `AD`, `VWAP`
  - `BollingerBands()` (SMA middle band)
  - `Percentile`, `PercentRank`
  - `RVOL` (`Sum` and `Last`)
  - the bar-local price transforms (`AvgPrice`, `MedPrice`, `TypPrice`,
    `WclPrice`, `BOP`, `MarketFI`), which are `Last`-dependents

  By the no-duplication rule, each of these is a CausalFrames summarizer or a
  dependent over CausalFrames accumulators. A dependent is automatically a
  group, because its effective structure is its dependencies'.
- **Monoid** (`MonoidSummarizer`, segment tree O(log n) with `combine!`). The
  value is combinable over ordered sub-ranges:
  - `MAX`/`MIN`/`MINMAX`
  - the index forms
  - `MidPoint`, `MidPrice`, `Donchian`, `WillR`, `Aroon`/`AroonOsc`
  - `MOM`/`ROC*` (`First`/`Last`)
  - `TRange` (`First`/`Last` under `Bars(2)`)
- **Plain** (`Summarizer`). These have no lawful `combine!`, so they are folded
  row by row:
  - recursive filters: the EMA family, Wilder smoothing, `MACD`, `KAMA`, `T3`,
    `MAMA`, the Hilbert family
  - everything with an `matype` keyword: `MA`, `MACDExt`, `APO`/`PPO`/`PVO`,
    `Stoch*`, `KDJ`, and `BollingerBands(; matype)` with a non-SMA `matype`
  - path-dependent states: `SAR`, `SuperTrend`, `OBV`
  - mean-deviation indicators: `CCI`, `AvgDev`
  - indicators that feed a per-row term needing the previous bar into a window
    or a recursion: `ATR`, `MFI`, `Beta` returns, `Vortex`
  - candlesticks

  A plain indicator that needs a window takes TA-Lib's `period` keyword and
  embeds it through the count-window helper (g).

### Windows

A structured indicator is **window-agnostic**. It is defined once, with no
period, and the transform supplies the window:

- a *bar count*, through `addrollingcolumns((b14 = Bars(14),), …)`, which is
  TA-Lib's windowing
- a *time* window, through `addrollingcolumns((h1 = Hour(1),), MidPrice())` or
  `summarizewindows`
- an *interval*, through `intervalize`

In every case CausalFrames' running and tree fast paths apply. The same
implementation serves all three, and the tests hold the bar-count and
uniformly-spaced time forms against each other.

TA-Lib's default window is listed as `window: Bars(n)` in the name table.

- **Previous-bar functions.** The functions that compare with the bar `period`
  back (`MOM`, the `ROC` family) and `RVOL` read `First`/`Last` over the whole
  window. TA-Lib's `period = p` is therefore `Bars(p + 1)`, and their docstrings
  say so.
- **`TRange`** is fixed at `Bars(2)`. Its TA-Lib lookback of 1 comes from the
  partial-window rule.

A plain indicator can still be passed to `addrollingcolumns`, which re-folds
each window from a fresh state. That is correct but means a cold start per
window, which is rarely what a recursive indicator wants. Its docstring says so.

## Implementation architecture

- **Kernels** (`src/kernels/`) cover only what CausalFrames does not:
  - `EMAKernel` and `WilderKernel`, seeded through an embedded CausalFrames
    `Sum` state
  - `MAKernel{M}`: the moving-average family behind a type parameter.
    - It is used by `MA`, `MACDExt`, `APO`/`PPO`/`PVO`, `Stoch*`, `KDJ` and
      non-SMA `BollingerBands`.
    - Its `:sma` form is the count-window helper around `Mean`.
  - `CandleAverages`: TA-Lib's per-setting body and shadow averages, built on
    count-windowed CausalFrames `Mean` states.

  Window sums, extrema and the ring buffer are never kernels. They are
  CausalFrames states and the upstream count-window helper.
- **State layout.** States compose kernels as concrete fields, with no `Any` and
  no abstract field types.
  - `update!` allocates nothing, and `fresh!` zeroes everything in place.
    Allocation tests pin both.
  - The per-row work sits behind CausalFrames' existing function barriers, so no
    new barrier is needed.
- **`MA(:x; period, matype)`** is a constructor function mirroring TA-Lib's
  `MA` dispatch. It always returns a plain summarizer over `MAKernel`. The
  window-agnostic SMA is `Mean`, under a `Bars` window.
- **Candlesticks** live in the `CausalIndicators.Candles` submodule.
  - It re-exports nothing into the top level. That keeps 61 pattern names out of
    user namespaces: users write `using CausalIndicators.Candles` or
    `Candles.Hammer()`.
  - The 11 TA-Lib candle settings form an immutable `CandleSettings`, passed as
    a keyword and defaulting to TA-Lib's defaults. They are `BodyLong`,
    `BodyVeryLong`, `BodyShort`, `BodyDoji`, `ShadowLong`, `ShadowVeryLong`,
    `ShadowShort`, `ShadowVeryShort`, `Near`, `Far` and `Equal`.
  - TA-Lib has a global settings table instead, which is not reproduced.

### Module layout

| File | Content |
|---|---|
| `src/CausalIndicators.jl` | module, includes, exports |
| `src/kernels/*.jl` | `EMAKernel`, `WilderKernel`, `MAKernel`, `CandleAverages` |
| `src/overlap.jl` | moving averages and bands |
| `src/momentum.jl` | momentum indicators |
| `src/volatility.jl` | volatility indicators |
| `src/statistics.jl` | statistic functions |
| `src/volume.jl` | volume indicators |
| `src/price.jl` | price transforms |
| `src/rolling.jl` | the rolling index operators (the TA-Lib *Math Operators* group not covered by CausalFrames) |
| `src/cycle.jl` | the Hilbert-transform family and `MAMA` |
| `src/candles/*.jl` | the `Candles` submodule |
| `test/foldseries.jl` | the test-only batch driver |
| `gen/` | the TA-Lib test extractor and golden generator (not part of the package) |

The file groups follow TA-Lib's own `group` field, so the YAML says where a
function lives.

## Testing

TA-Lib's own regression suite is the oracle. It is taken over in two
complementary forms, both pinned to the reference commit.

**`foldseries`.** `foldseries(s, table; window = nothing) -> NamedTuple` is a
test-only helper in `test/foldseries.jl`, not part of the package.

- It adds a synthetic integer `:time` column and runs the table through
  `readtable`. It then applies `addsummarycolumns(s)`, or
  `addrollingcolumns((w = window,), s)` when a window is given, and returns one
  plain vector per output column.
- It has no fold logic of its own, so what the tests check is exactly what
  pipelines run.

**Extracted test tables.**

- `gen/extract_talib_tests.jl` parses each
  `src/tools/ta_regtest/ta_test_func/test_*.c`. From each file it reads:
  - the file's own `typedef struct … TA_Test` field list, which differs from
    file to file
  - the `tableTest[]` initializer rows
  - the `TA_*_TEST` and `TA_MAType_*` identifiers

  It evaluates the rows' constant expressions (`252-14`) and writes
  `test/talib/tables/<file>.toml`, which is committed with the source path and
  commit.
- A small hand-written adapter per file maps each test identifier to a Julia
  summarizer and, for structured indicators, a `Bars` window. Each row asserts:
  - the value at `expectedBegIdx + index` matches to the precision the C test
    uses (the expected values are rounded to 2–4 decimals)
  - the first non-`missing` row is `expectedBegIdx` (lookback + `unstable`)
  - the number of non-`missing` rows is `expectedNbElement`

  Rows exercising `startIdx`/`endIdx` sub-ranges run over the corresponding
  slice. Rows asserting TA-Lib error codes become constructor `ArgumentError`
  tests.
- C tests that are not tables are ported by hand and listed in
  `test/talib/README.md`. These include the candlestick settings matrix, the
  division-by-zero cases and the stream/finite-value checks.
- The reference data is extracted once to `test/data/*.csv`. It is
  `TA_SREF_*_daily_ref_0_PRIV` (252 OHLCV bars) and the 10,000-bar `gData*`
  set.

**Full-series goldens.** The tables check a handful of points per function, so
the goldens check every bar.

- **Generator.** `gen/golden/dump_golden.c` links a pinned TA-Lib build and
  uses its abstract interface (`TA_GetFuncHandle`, `TA_CallFunc`). It runs every
  in-scope function over both datasets, at its defaults and at every parameter
  set the tables use, and writes `test/golden/<FN>.csv`.
- **Comparison.** Every output is compared bar by bar, with the lookback rows
  required to be `missing`.
  - Float outputs use `rtol = 1e-9` together with an `atol` scaled to the
    magnitude of the function's inputs. A relative tolerance alone would fail on
    near-zero outputs: the variance of a flat window, a flat `LINEARREG` slope,
    `CORREL` at ±1 (which CausalFrames clamps and TA-Lib does not). It would
    also fail on the gap between compensated sums and TA-Lib's drifting running
    sums.
  - Integer outputs must match exactly.
- **Running it.** The generator runs by hand when the pin moves. It is not
  built in CI, so CI needs no C toolchain.

**Streaming properties**, tested for every indicator:

- `load` through the pipeline equals `foldseries`
- random re-chunkings of the input (via `readtable` over small partitions) give
  identical output
- a keyed run equals separate per-key runs, with keys interleaved
- a `warmup` smoke test: with a sufficient look-back, split contexts
  concatenate to the whole context (the operator's own property tests are
  upstream)
- for structured indicators:
  - under a `Bars` window, the running or tree path equals the re-fold path
  - on uniformly spaced bars, a time window equals the matching `Bars` window
- zero allocations per row in the fold, and JET cleanliness on the per-row path

Aqua runs as in CausalFrames.

## Staging

One PR per stage. Each lands its code, extracted tables, goldens, docs and
README rows together, and updates this document where reality differs.

- **S0, upstream prerequisites (CausalFrames PRs):** items (a)–(g) under
  "Upstream prerequisites".
  - `warmup`
  - the `Bars` look-back
  - the oldest-first `downdate!` law, with the recency-weighted sum and `Last`
    as a group
  - `MaxIndex`/`MinIndex`
  - row-expression sum terms
  - the sorted multiset with `Quantile`/`PercentRank`
  - the count-window helper
- **S0′, scaffolding:**
  - the CausalFrames dependency. It is unregistered, so this uses `[sources]`
    on Julia ≥ 1.11 plus a CI `Pkg.develop(url = …)` step on 1.10.
  - the kernels
  - the extractor, the golden generator, the extracted data and
    `test/foldseries.jl`
  - CI with Aqua and JET
- **S1:** moving averages, the rolling operators and price transforms (28
  functions, of which 6 are CausalFrames-only and need only tests).
- **S2:** momentum I (23): the MOM/ROC family, RSI, CMO, the MACD family,
  APO/PPO, TRIX, the stochastics, WillR, CCI, BOP, Aroon, ULTOSC, MFI.
- **S3:** directional movement and volatility (24): TRange, ATR, NATR, ±DM,
  ±DI, DX, ADX, ADXR, SAR, SARExt, BollingerBands, StdDev, Var, AvgDev,
  AccBands, Keltner, Donchian, SuperTrend, ADR, CVI, MassIndex, RVI.
- **S4:** statistics and volume (21).
- **S5:** the TA-Lib 0.8 additions (18): AC, AO, CMOU, Coppock, DPO, ERI, ER,
  FOSC, Fractal, IMI, KDJ, QStick, SMI, TSI, VHF, Vortex, WAD, HeikinAshi.
- **S6:** the Hilbert-transform cycle family and `MAMA` (7).
- **S7:** the 61 candlestick patterns and `CandleSettings`.

A stage PR may find that an indicator can claim a stronger tier, or needs
another upstream addition. It then amends the name table and "Upstream
prerequisites" in the same PR.

## Open questions

- **Registering CausalFrames**, which would replace the `[sources]` and CI
  workaround with a plain `[compat]` entry.
- **The exact public shape of the upstream additions**, meaning type names and
  output suffixes. This is settled in their CausalFrames PRs, and the name table
  follows.
- **`PERCENTILE`'s interpolation rule** at the pin, and whether `PercentRank`'s
  definition is generic enough for CausalFrames. If it is not, it becomes a
  dependent here, over the upstream sorted multiset and `Last`.

## Name table

All 182 in-scope TA-Lib functions. The table is generated from the pinned YAML.

- **Relation** is the no-duplication resolution:
  - *CausalFrames only* (case 1)
  - *dependent* (case 2)
  - *dependent (upstream)* (case 2, over an S0 addition)
  - *new state* (no CausalFrames equivalent)
  - *constructor* (dispatch only)
- **Tier** only applies under a window; a *no window* row runs under
  `addsummarycolumns`.
- **Keywords** are the Julia keywords with TA-Lib's defaults. For a structured
  indicator, `window: Bars(n)` is TA-Lib's default window, supplied by the
  transform rather than a keyword (see "Windows").
- **Julia** is the CausalFrames summarizer itself for *CausalFrames only* rows;
  no TA-Lib-named constructor exists for them.
- **Output suffixes** name the columns of a multi-output indicator.

| TA-Lib | Julia | Stage | Relation to CausalFrames | Tier | Inputs | Keywords (defaults) | Output suffixes |
|---|---|---|---|---|---|---|---|
| `AVGPRICE` | `AvgPrice` | S1 | dependent: `Last` | Group | open, high, low, close | any window (bar-local) | (one column) |
| `CUMSUM` | `Sum(:x)` | S1 | CausalFrames only: `Sum` (no window) | Group | real | no window (`addsummarycolumns`) | (one column) |
| `DEMA` | `DEMA` | S1 | new state | plain | real | period=30 | (one column) |
| `EMA` | `EMA` | S1 | new state | plain | real | period=30 | (one column) |
| `HMA` | `HMA` | S1 | new state | plain | real | period=20 | (one column) |
| `KAMA` | `KAMA` | S1 | new state | plain | real | period=30 | (one column) |
| `MA` | `MA` | S1 | constructor (dispatches on `matype`) | per MA type | real | period=30, matype=:sma | (one column) |
| `MAVP` | `MAVP` | S1 | new state | plain | real, periods | minperiod=2, maxperiod=30, matype=:sma | (one column) |
| `MAX` | `Max(:x)` | S1 | CausalFrames only: `Max` | Monoid | real | window: Bars(30) | (one column) |
| `MAXINDEX` | `RollingMaxIndex` | S1 | dependent (upstream): `MaxIndex` | Monoid | real | window: Bars(30) | (one column) |
| `MEDPRICE` | `MedPrice` | S1 | dependent: `Last` | Group | high, low | any window (bar-local) | (one column) |
| `MIDPOINT` | `MidPoint` | S1 | dependent: `Max`, `Min` | Monoid | real | window: Bars(14) | (one column) |
| `MIDPRICE` | `MidPrice` | S1 | dependent: `Max`, `Min` | Monoid | high, low | window: Bars(14) | (one column) |
| `MIN` | `Min(:x)` | S1 | CausalFrames only: `Min` | Monoid | real | window: Bars(30) | (one column) |
| `MININDEX` | `RollingMinIndex` | S1 | dependent (upstream): `MinIndex` | Monoid | real | window: Bars(30) | (one column) |
| `MINMAX` | `Min(:x)`, `Max(:x)` | S1 | CausalFrames only: `Min`, `Max` | Monoid | real | window: Bars(30) | min, max |
| `MINMAXINDEX` | `RollingMinMaxIndex` | S1 | dependent (upstream): `MinIndex`, `MaxIndex` | Monoid | real | window: Bars(30) | minidx, maxidx |
| `RMA` | `RMA` | S1 | new state | plain | real | period=30 | (one column) |
| `SMA` | `Mean(:x)` | S1 | CausalFrames only: `Mean` | Group | real | window: Bars(30) | (one column) |
| `SUM` | `Sum(:x)` | S1 | CausalFrames only: `Sum` | Group | real | window: Bars(30) | (one column) |
| `T3` | `T3` | S1 | new state | plain | real | period=5, vfactor=0.7 | (one column) |
| `TEMA` | `TEMA` | S1 | new state | plain | real | period=30 | (one column) |
| `TRIMA` | `TRIMA` | S1 | new state (nested `Mean` windows) | plain | real | period=30 | (one column) |
| `TYPPRICE` | `TypPrice` | S1 | dependent: `Last` | Group | high, low, close | any window (bar-local) | (one column) |
| `VWMA` | `VWMA` | S1 | dependent: `DotProduct`, `Sum` | Group | real, volume | window: Bars(30) | (one column) |
| `WCLPRICE` | `WclPrice` | S1 | dependent: `Last` | Group | high, low, close | any window (bar-local) | (one column) |
| `WMA` | `WMA` | S1 | dependent (upstream): recency sum, `Sum`, `Count` | Group | real | window: Bars(30) | (one column) |
| `ZLEMA` | `ZLEMA` | S1 | new state | plain | real | period=30 | (one column) |
| `APO` | `APO` | S2 | new state | plain | real | fastperiod=12, slowperiod=26, matype=:ema | (one column) |
| `AROON` | `Aroon` | S2 | dependent (upstream): `MaxIndex`, `MinIndex` | Monoid | high, low | window: Bars(14) | aroondown, aroonup |
| `AROONOSC` | `AroonOsc` | S2 | dependent (upstream): `MaxIndex`, `MinIndex` | Monoid | high, low | window: Bars(14) | (one column) |
| `BOP` | `BOP` | S2 | dependent: `Last` | Group | open, high, low, close | any window (bar-local) | (one column) |
| `CCI` | `CCI` | S2 | new state (mean deviation needs the window) | plain | high, low, close | period=14 | (one column) |
| `CMO` | `CMO` | S2 | new state | plain | real | period=14 | (one column) |
| `MACD` | `MACD` | S2 | new state | plain | real | fastperiod=12, slowperiod=26, signalperiod=9 | macd, macdsignal, macdhist |
| `MACDEXT` | `MACDExt` | S2 | new state | plain | real | fastperiod=12, fastmatype=:sma, slowperiod=26, slowmatype=:sma, signalperiod=9, signalmatype=:sma | macd, macdsignal, macdhist |
| `MACDFIX` | `MACDFix` | S2 | new state | plain | real | signalperiod=9 | macd, macdsignal, macdhist |
| `MFI` | `MFI` | S2 | new state | plain | high, low, close, volume | period=14 | (one column) |
| `MOM` | `MOM` | S2 | dependent: `First`, `Last` | Monoid | real | window: Bars(11) | (one column) |
| `PPO` | `PPO` | S2 | new state | plain | real | fastperiod=12, slowperiod=26, matype=:ema | (one column) |
| `ROC` | `ROC` | S2 | dependent: `First`, `Last` | Monoid | real | window: Bars(11) | (one column) |
| `ROCP` | `ROCP` | S2 | dependent: `First`, `Last` | Monoid | real | window: Bars(11) | (one column) |
| `ROCR` | `ROCR` | S2 | dependent: `First`, `Last` | Monoid | real | window: Bars(11) | (one column) |
| `ROCR100` | `ROCR100` | S2 | dependent: `First`, `Last` | Monoid | real | window: Bars(11) | (one column) |
| `RSI` | `RSI` | S2 | new state | plain | real | period=14 | (one column) |
| `STOCH` | `Stoch` | S2 | new state | plain | high, low, close | fastkperiod=5, slowkperiod=3, slowkmatype=:sma, slowdperiod=3, slowdmatype=:sma | slowk, slowd |
| `STOCHF` | `StochF` | S2 | new state (%K is `WillR`'s dependent) | plain | high, low, close | fastkperiod=5, fastdperiod=3, fastdmatype=:sma | fastk, fastd |
| `STOCHRSI` | `StochRSI` | S2 | new state | plain | real | period=14, fastkperiod=5, fastdperiod=3, fastdmatype=:sma | fastk, fastd |
| `TRIX` | `TRIX` | S2 | new state | plain | real | period=30 | (one column) |
| `ULTOSC` | `ULTOSC` | S2 | new state | plain | high, low, close | timeperiod1=7, timeperiod2=14, timeperiod3=28 | (one column) |
| `WILLR` | `WillR` | S2 | dependent: `Max`, `Min`, `Last` | Monoid | high, low, close | window: Bars(14) | (one column) |
| `ACCBANDS` | `AccBands` | S3 | dependent (upstream): row-term `Sum`, `Count` | Group | high, low, close | window: Bars(20) | upperband, middleband, lowerband |
| `ADR` | `ADR` | S3 | dependent (upstream): row-term `Sum`, `Count` | Group | high, low | window: Bars(14) | (one column) |
| `ADX` | `ADX` | S3 | new state | plain | high, low, close | period=14 | (one column) |
| `ADXR` | `ADXR` | S3 | new state | plain | high, low, close | period=14 | (one column) |
| `ATR` | `ATR` | S3 | new state | plain | high, low, close | period=14 | (one column) |
| `AVGDEV` | `AvgDev` | S3 | new state (mean deviation needs the window) | plain | real | period=14 | (one column) |
| `BBANDS` | `BollingerBands` | S3 | dependent: `Mean`, `Std` (no `matype`); new state with `matype` | Group / plain | real | window: Bars(20), nbdevup=2, nbdevdn=2; with `matype`: period=20, matype=:sma | upperband, middleband, lowerband |
| `CVI` | `CVI` | S3 | new state | plain | high, low | period=10, rocperiod=10 | (one column) |
| `DONCHIAN` | `Donchian` | S3 | dependent: `Max`, `Min` | Monoid | high, low | window: Bars(20) | upperband, middleband, lowerband |
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
| `STDDEV` | `StdDev` | S3 | dependent: `Std(corrected=false)` | Group | real | window: Bars(5), nbdev=1 | (one column) |
| `SUPERTREND` | `SuperTrend` | S3 | new state | plain | high, low, close | period=10, multiplier=3.0 | supertrend, trend |
| `TRANGE` | `TRange` | S3 | dependent: `Last`, `First` | Monoid | high, low, close | window: Bars(2) (fixed) | (one column) |
| `VAR` | `Variance(:x; corrected=false)` | S3 | CausalFrames only: `Variance(corrected=false)` | Group | real | window: Bars(5) (TA-Lib ignores nbdev) | (one column) |
| `AD` | `AD` | S4 | dependent (upstream): row-term `Sum` (no window) | Group | high, low, close, volume | no window (`addsummarycolumns`) | (one column) |
| `ADOSC` | `ADOSC` | S4 | new state | plain | high, low, close, volume | fastperiod=3, slowperiod=10 | (one column) |
| `BETA` | `Beta` | S4 | new state (returns need the previous bar) | plain | real0, real1 | period=5 | (one column) |
| `CMF` | `CMF` | S4 | dependent (upstream): row-term `Sum`, `Sum` | Group | high, low, close, volume | window: Bars(20) | (one column) |
| `CORREL` | `Correlation(:a, :b)` | S4 | CausalFrames only: `Correlation` | Group | real0, real1 | window: Bars(30) | (one column) |
| `EFI` | `EFI` | S4 | new state | plain | close, volume | period=13 | (one column) |
| `LINEARREG` | `LinearReg` | S4 | dependent (upstream): recency sum, `Sum`, `Count` | Group | real | window: Bars(14) | (one column) |
| `LINEARREG_ANGLE` | `LinearRegAngle` | S4 | dependent (upstream): recency sum, `Sum`, `Count` | Group | real | window: Bars(14) | (one column) |
| `LINEARREG_INTERCEPT` | `LinearRegIntercept` | S4 | dependent (upstream): recency sum, `Sum`, `Count` | Group | real | window: Bars(14) | (one column) |
| `LINEARREG_SLOPE` | `LinearRegSlope` | S4 | dependent (upstream): recency sum, `Sum`, `Count` | Group | real | window: Bars(14) | (one column) |
| `MARKETFI` | `MarketFI` | S4 | dependent: `Last` | Group | high, low, volume | any window (bar-local) | (one column) |
| `NVI` | `NVI` | S4 | new state | plain | close, volume | — | (one column) |
| `OBV` | `OBV` | S4 | new state (previous close) | plain | real, volume | — | (one column) |
| `PERCENTILE` | `Percentile` | S4 | dependent (upstream): sorted multiset | Group | real | window: Bars(30), percentile=50 | (one column) |
| `PERCENTRANK` | `PercentRank` | S4 | dependent (upstream): sorted multiset, `Last` | Group | real | window: Bars(100) | (one column) |
| `PVI` | `PVI` | S4 | new state | plain | close, volume | — | (one column) |
| `PVO` | `PVO` | S4 | new state | plain | volume | fastperiod=12, slowperiod=26, matype=:ema | (one column) |
| `PVT` | `PVT` | S4 | new state | plain | close, volume | — | (one column) |
| `RVOL` | `RVOL` | S4 | dependent: `Sum`, `Last` over n+1 bars | Group | volume | window: Bars(21) | (one column) |
| `TSF` | `TSF` | S4 | dependent (upstream): recency sum, `Sum`, `Count` | Group | real | window: Bars(14) | (one column) |
| `VWAP` | `VWAP` | S4 | dependent (upstream): row-term `Sum`, `Sum` (no window) | Group | high, low, close, volume | no window (`addsummarycolumns`) | (one column) |
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
| `IMI` | `IMI` | S5 | dependent (upstream): row-term `Sum`s | Group | open, close | window: Bars(14) | (one column) |
| `KDJ` | `KDJ` | S5 | new state | plain | high, low, close | fastkperiod=9, slowkperiod=3, slowkmatype=:rma, slowdperiod=3, slowdmatype=:rma | k, d, j |
| `QSTICK` | `QStick` | S5 | dependent (upstream): row-term `Sum`, `Count` | Group | open, close | window: Bars(10) | (one column) |
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
