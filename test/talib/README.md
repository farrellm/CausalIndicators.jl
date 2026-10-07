# TA-Lib regression tests

`tables/*.toml` are extracted from TA-Lib 0.8.1 (commit `2aa8eb0`)
`src/tools/ta_regtest/ta_test_func/test_*.c` by `gen/extract_talib_tests.jl`;
`../data/*.csv` by `gen/extract_talib_data.jl`; `../golden/*.csv.gz` by
`gen/golden/generate.jl`; `candles/mcdc.txt.gz` by `gen/candles/capture.jl`.
See the repository README for regenerating them, and DESIGN.md "Testing" for
how they are used.

## Hand-ported tests

Checks that are code rather than file-scope tables are ported by hand, in the
stage that implements the function. Each entry is ticked when its port lands.

These files have no file-scope tables at all:

- [x] `test_beta.c`, in part: a two-pass oracle over TA_SREF at periods 1, 2,
      5 and 20, a series against itself, the flat index (flat and varying
      other series), the zero previous price and price-scale invariance (S4).
      The Wilkinson, NIST Norris and outlier-transit legs wait for
      `test_reference.c`.
- [x] `test_cmou.c`: the Tulip/pandas oracle at 1e-12, the all-up, all-down,
      flat and hand-computed windows, and the empty window over the spiked
      LCG corpus (`lcgsym`), exactly 0 at all 18,096 flat bars (S5)
- [x] `test_correl.c`, in part: a two-pass oracle, the [−1, 1] range,
      self-correlation, affine invariance with the sign of the scale, and the
      flat window, which gives `NaN` where TA-Lib gives 0 (DESIGN.md,
      "Testing") (S4). The pandas, NIST Norris and small-scale legs wait for
      `test_reference.c`.
- [x] `test_linearreg.c`, in part: a direct least-squares fit of every window,
      the internal consistency of the five outputs, the affine identity, the
      constant window, an exact line and the large print leaving no residue
      (S4). The Wilkinson, ladder and NIST NumAcc legs wait for
      `test_reference.c`; the reseed legs test TA-Lib's running sums, which
      CausalFrames' compensated sums replace.
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

- [x] `test_candlestick.c` (S7). The `cdlGlobalsMatrix` settings rows are
      oracled by goldens: every CDL* golden also runs at rows 1–4 on both
      datasets (`cdlrow=r`), since the C test only compares languages with
      each other there. The MC/DC pattern builders (`pb_*`, the Hikkake and
      marquee predicate gates) are not ported. Instead `gen/candles/capture.c`
      links the C test with every `TA_CDL*` entry point wrapped and records
      each builder call's bars and TA-Lib's answers in
      `candles/mcdc.txt.gz`, which `test/candles.jl` replays exactly. Its
      `tableTest` rows (bar 0 alone, no output) are checked too. Not ported:
      `doRangeTest`, the per-setting coverage sweep and the server legs, which
      have no stream counterpart.
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
      has no counterpart for, and test_bbands.c's legs built on
      `ta_test_reference.c` data (NumAcc, pandas, tick ladder).
- [x] `test_bbands.c` MAMA alignment (#99): at periods 20, 33, 34, 40, 50 and
      100 the bands start at `max(32, period − 1)` and the middle band is
      `MA(:mama)` (S6). The `startIdx` cases re-anchor TA-Lib's MAMA, which a
      stream has no counterpart for.
- [x] `test_stddev.c`: its table, STDDEV and VAR non-negativity, shift
      invariance, the exactly constant window, scale invariance at periods 2,
      10 and 25, and the flat tail. The flat tail is held to var.c's relative floor rather than exact
      0 (DESIGN.md, "Testing"). The legs run on the C test's own LCG data
      (`lcgsym`) (S3). The `ta_test_reference.c` legs
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

- [x] `test_per_hlcv.c`, `test_per_hl.c`, `test_per_cv.c`: the AD, ADOSC,
      BETA, CORREL, NVI, PVI and PVT rows, the PVT oracle at 1e-12 and the
      zero-previous-close and overflow edges (S4)
- [x] `test_cmf.c`: the shapes and range, the oracle at 1e-13, TA-Lib's own
      pinned output at 1e-15 (it pins it bitwise), and the zero-volume, flat,
      malformed, close-at-high/low/middle, full-window and short-input edges
      (S4)
- [x] `test_marketfi.c`: the pins at 1e-12 and the zero-volume bar (S4)
- [x] `test_percentile.c`: the oracle bit for bit, the textbook example, the
      exact integer rank against sorted windows and the 0/100 extremes (S4)
- [x] `test_percentrank.c`: the oracle bit for bit, the count map and the
      strict tie rule (S4)
- [x] `test_rvol.c`: the oracle at 1e-13 and the dead window (S4)
- [x] `test_vwap.c`: both shapes' oracle and pinned values at 1e-14 relative,
      the leading zero volume, the zero-volume and non-finite bars, and the
      session reset by key (S4)

- [x] `test_dpo.c`: the Tulip/pandas oracle at 1e-12, the Tulip and Achelis
      book vectors, both arms of the lookback and the constants of a line (S5)
- [x] `test_fosc.c`: the Achelis and Tulip book vectors, the Tulip and
      trading-signals oracles at 1e-10, FOSC as TSF one bar earlier, and the
      zero close (S5)
- [x] `test_vhf.c`: the oracle at 1e-12, the book vectors, a direct scan of
      every window with the [0, 1] bound, and the flat 0 (S5)
- [x] `test_eri.c`: the pins at 1e-12, the shared EMA, the period-1 copy on
      the non-Sterbenz pair, and the unstable grid (S5)
- [x] `test_vortex.c`: the pins at 1e-12, TRange and the movements through
      window sums at every grid period, and the halt after a spread bar (S5)
- [x] `test_tsi.c`: the oracle and the trading-signals tail at 1e-12, the
      unstable grid's lookback, and the flat 0 (S5)
- [x] `test_imi.c`: its table, and the flat (50), all-up and all-down windows
      (S5)
- [x] `test_kdj.c`: the Tulip (RMA) and trading-signals (SMA) oracles at
      2e-12, and the delegation to Stoch with J = 3K − 2D over the grid and
      three MA types (S5)
- [x] `test_fractal.c`: the corpus and synthetic flag lists in full, the bars
      where both fire, and the flat and monotone shapes (S5)
- [x] `test_ha.c`: both oracles exactly, the signed zeros' sign bits and the
      unstable period (S5)
- [x] `test_composite1.c`, S5 part: AO and AC against SMAs of the median price,
      QStick's book vectors and its SMA of the body (S5)
- [x] `test_composite2.c`, S5 part: Coppock as the WMA of two ROCs, SMI from
      the window's extremes and chained EMAs, and ER as the ratio KAMA adapts
      to (S5)
- [x] `test_quote_unit.c`, S5 part: the 2^-60 CMOU and SMI oracles and their
      [−100, 100] range (S5)
- [x] `test_per_hlc.c` WAD: its table rows and the book and Tulip vectors (S5)
- [x] `test_1in_1out.c`, `test_1in_2out.c` and `test_ma.c`'s MAMA/FAMA rows:
      the tables, on the median price as the C tests feed them (S6)

Not ported, being out of scope:

- `test_div_zero.c` covers `DIV`, an element-wise operator
- `test_stream_finite.c` covers the C API's rejection of non-finite single
  values, which has no counterpart here
