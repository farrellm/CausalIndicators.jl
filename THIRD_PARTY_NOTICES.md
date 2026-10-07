# Third-party notices

CausalIndicators reimplements the technical indicators of
[TA-Lib](https://ta-lib.org) ([source](https://github.com/TA-Lib/ta-lib)) in
Julia, against TA-Lib 0.8.1, commit `2aa8eb0d79bcfc4d2ff3f7b445d37958c48e0788`.
It is not affiliated with or endorsed by TA-Lib or its authors.

The following are derived from TA-Lib:

- the indicator algorithms in `src/`, ported from TA-Lib's C sources and
  documentation (`ta_codegen/input/`);
- `test/data/*.csv`, the regression price data copied from TA-Lib's
  `src/tools/ta_regtest/` C literals;
- `test/talib/tables/*.toml`, the test tables extracted from
  `src/tools/ta_regtest/ta_test_func/test_*.c`;
- `test/golden/*.csv.gz` and `test/talib/candles/mcdc.txt.gz`, outputs of
  TA-Lib itself;
- `gen/`, which builds against TA-Lib and wraps its `test_candlestick.c`.

These are distributed under TA-Lib's license:

```text
Copyright (c) 1999-2026, Mario Fortier

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this
   list of conditions and the following disclaimer.

2. Redistributions in binary form must reproduce the above copyright notice,
   this list of conditions and the following disclaimer in the documentation
   and/or other materials provided with the distribution.

3. Neither the name of the copyright holder nor the names of its
   contributors may be used to endorse or promote products derived from
   this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
```
