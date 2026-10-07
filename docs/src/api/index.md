# API overview

Each indicator is a CausalFrames summarizer. Structured indicators take their
window from `addrollingcolumns`; recursive ones take a `period` keyword and run
under `addsummarycolumns`. The [home page](../index.md) tables give every
indicator's TA-Lib name, signature and the transform it runs under; the pages
below hold the docstrings, grouped as TA-Lib groups them.

- [Overlap studies](overlap.md)
- [Price transforms](price.md)
- [Momentum](momentum.md)
- [Volatility](volatility.md)
- [Statistics](statistics.md)
- [Volume](volume.md)
- [Cycle indicators](cycle.md)
- [Candlestick patterns](candles.md)

```@docs
CausalIndicators
```
