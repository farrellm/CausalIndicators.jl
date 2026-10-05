"""
    CausalIndicators

TA-Lib's technical indicators as causal, streaming CausalFrames summarizers.
See DESIGN.md for the design and the staging of the implementation.
"""
module CausalIndicators

using CausalFrames
using CausalFrames: fresh, fresh!, update!, value, ColumnSpec, colname, withterms

export MA, EMA, RMA, DEMA, TEMA, TRIMA, KAMA, T3, HMA, ZLEMA, MAVP, WMA, VWMA,
    MidPoint, MidPrice, AvgPrice, MedPrice, TypPrice, WclPrice,
    MOM, ROC, ROCP, ROCR, ROCR100, RSI, CMO, MACD, MACDFix, MACDExt, APO, PPO, TRIX,
    Stoch, StochF, StochRSI, WillR, CCI, BOP, Aroon, AroonOsc, ULTOSC, MFI,
    PlusDM, MinusDM, PlusDI, MinusDI, DX, ADX, ADXR,
    TRange, ATR, NATR, ADR, CVI, MassIndex, RVI,
    SAR, SARExt, BollingerBands, AccBands, KeltnerChannels, Donchian, SuperTrend,
    StdDev

include("kernels/common.jl")
include("kernels/ema.jl")
include("kernels/wilder.jl")
include("kernels/sma.jl")
include("kernels/wma.jl")
include("kernels/kama.jl")
include("kernels/ma.jl")
include("kernels/gainloss.jl")
include("kernels/stoch.jl")
include("kernels/atr.jl")
include("kernels/dm.jl")

include("overlap.jl")
include("price.jl")
include("momentum.jl")
include("volatility.jl")
include("statistics.jl")

end
