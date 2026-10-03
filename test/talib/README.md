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
- [ ] `test_rolling_extremum.c`: the block-scan oracle for MIN, MAX, MINMAX,
      MIDPOINT, MIDPRICE and WILLR. The S1 part (all but WILLR) is ported as
      a naive window scan over periods straddling the block edges; WILLR
      lands in S2.
- [x] `test_zlema.c`: the pandas and Tulip oracles at 1e-12, period 1 and the
      inherited EMA unstable period (S1). Its arrays use anonymous structs,
      which the extractor does not read, so the values are copied into
      `test/overlap.jl`.
- [x] `test_cumsum.c`: the C40 golden and the (3, 7) slice (S1)

Not ported, being out of scope:

- `test_div_zero.c` covers `DIV`, an element-wise operator
- `test_stream_finite.c` covers the C API's rejection of non-finite single
  values, which has no counterpart here
