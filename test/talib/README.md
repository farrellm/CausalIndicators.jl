# TA-Lib regression tests

`tables/*.toml` are extracted from TA-Lib 0.8.1 (commit `2aa8eb0`)
`src/tools/ta_regtest/ta_test_func/test_*.c` by `gen/extract_talib_tests.jl`;
`../data/*.csv` by `gen/extract_talib_data.jl`; `../golden/*.csv.gz` by
`gen/golden/generate.jl`. See the repository README for regenerating them, and
DESIGN.md "Testing" for how they are used.

## Hand-ported tests

Checks that are code rather than file-scope tables are ported by hand, in the
stage that implements the function. Each entry is ticked when its port lands.

These files have no file-scope tables at all:

- [ ] `test_beta.c`
- [ ] `test_cmou.c`
- [ ] `test_correl.c`
- [ ] `test_linearreg.c`
- [x] `test_mavp.c`: the per-bar oracle (MAVP equals `MA(p)` started at
      MAVP's first output) for every MA type, with and without an unstable
      period, and the min/max/NaN clamping (S1). The in-place and truncation
      legs have no counterpart in a stream.
- [ ] `test_open_contract.c`
- [ ] `test_reference.c` (with `ta_test_reference.c` and its golden header)
- [ ] `test_s_overflow.c`
- [ ] `test_variants.c`
- [x] `test_wma.c`: W2 (drift does not grow down an 8000-bar series) and W3
      (a 1000× print does not contaminate later windows), against an exact
      per-window WMA (S1). W1 needs `test_reference.c`'s golden header and
      lands with it.

These files have checks outside their extracted tables:

- [ ] `test_candlestick.c`: the `cdlGlobalsMatrix` settings matrix drives
      `CandleSettings` (S7)
- [ ] `test_period_boundary.c`: period-1 and minimum-period boundaries, and
      the abstract sweep over every parameter grid
- [x] `test_rolling_extremum.c`: the block-scan oracle for MIN, MAX, MINMAX,
      MIDPOINT, MIDPRICE and WILLR, ported as a naive window scan over periods
      straddling the block edges (S1; WILLR in S2).
- [x] `test_mfi.c`: the Tulip/pandas-ta oracle at 2e-12 with natural and
      2^-60 volume, the bit-exact power-of-two volume-scale invariance, the
      [0, 100] range over periods 2–60, and the exact-zero empty window
      (flat and halted shapes, 24 phases) (S2).
- [x] `test_po.c`: APO and PPO default to EMA (S2).
- [x] `test_zlema.c`: the pandas and Tulip oracles at 1e-12, period 1 and the
      inherited EMA unstable period (S1). Its arrays use anonymous structs,
      which the extractor does not read, so the values are copied into
      `test/overlap.jl`.
- [x] `test_cumsum.c`: the C40 golden and the (3, 7) slice (S1)
- [x] `test_adx.c`, `test_trange.c`, `test_sar.c`, `test_bbands.c`,
      `test_avgdev.c`: their tables (S3). Not ported: in-place aliasing,
      `checkDataSame` and the `doRangeTest` sub-range sweeps, which a stream
      has no counterpart for; test_bbands.c's MAMA alignment (S6) and its legs
      built on `ta_test_reference.c` data (NumAcc, pandas, tick ladder).
- [x] `test_stddev.c`: its table, STDDEV and VAR non-negativity, shift
      invariance, the exactly constant window, scale invariance at periods 10
      and 25, and the flat tail. The flat tail is held to var.c's relative floor rather than exact
      0 (DESIGN.md, "Testing"). The legs run on the C test's own LCG data
      (`lcgsym`) (S3). Scale invariance under `Bars(2)` is
      `@test_broken`: the windowed `Variance` keeps ~1e-7 error on a two-bar
      window (CausalFrames.jl#91). The `ta_test_reference.c` legs
      (two-pass oracle, NIST StRD, small-scale ladder) wait for that file's
      port.
- [x] `test_kc.c`: the gData and TA_SREF shapes and ta4j oracles, the
      composition (middle = EMA of the typical price from the first output,
      bands = middle ± nbdev·ATR) and nbdev 0 (S3)
- [x] `test_supertrend.c`: the shapes and ta4j oracles, the complete flip
      lists, the seed band and trend, the seed-upper construction, and the
      multiplier-0 and flat edges (S3)
- [x] `test_donchian.c`: the pandas and ta4j goldens bitwise, the identity
      with Max/Min/MidPrice, the flat series and period = length (S3)
- [x] `test_adr.c`: the kand vector, the TA_SREF oracle, period 1, a flat
      series giving +0.0 and `high < low` (S3)
- [x] `test_cvi.c`: the pandas/Tulip oracle, the n = 3 decay edge and the
      all-flat zero (S3)
- [x] `test_massi.c`: the pandas/Tulip/trading-signals oracle, the flat and
      constant-range edges (exactly `slowperiod`) and 2^-100 scale
      invariance (S3)
- [x] `test_rvi.c`: the trading-signals oracle, pandas-ta's converged tail,
      the period-1 tie counts and the flat 50 (S3)
- [x] `test_rma.c`: ATR equals RMA of TRange bit for bit, periods 1 to 100 (S3)
- [x] `test_period_boundary.c`, S3 part: ATR(1) and NATR(1) are TRange, and
      ±DI(1) is DM/TR without the factor 100. The abstract sweep is not ported.
- [x] `test_quote_unit.c`, S3 part: the 2^-60 oracles for NATR, ADX, ADXR,
      DX, ±DI and ACCBANDS, and the [0, 100] range of the DI family. The
      power-of-two invariance leg is not ported.

Not ported, being out of scope:

- `test_div_zero.c` covers `DIV`, an element-wise operator
- `test_stream_finite.c` covers the C API's rejection of non-finite single
  values, which has no counterpart here
