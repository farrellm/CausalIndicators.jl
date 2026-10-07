"""
    CausalIndicators

TA-Lib's technical indicators as causal, streaming CausalFrames summarizers.
One row is one bar, of any size: every period counts bars, not days. TA-Lib's
defaults are its authors' parameters for daily bars, so choose the parameters
for yours. See DESIGN.md for the design and the staging of the implementation.
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
    StdDev, LinearReg, LinearRegSlope, LinearRegIntercept, LinearRegAngle, TSF,
    PercentRank100, Beta,
    AD, ADOSC, CMF, EFI, MarketFI, NVI, OBV, PVI, PVO, PVT, RVOL, VWAP,
    AC, AO, CMOU, Coppock, DPO, ER, ERI, FOSC, Fractal, IMI, KDJ, QStick, SMI, TSI, VHF,
    Vortex, WAD, HeikinAshi,
    HTDCPeriod, HTDCPhase, HTPhasor, HTSine, HTTrendline, HTTrendMode, MAMA

include("kernels/common.jl")
include("kernels/ema.jl")
include("kernels/wilder.jl")
include("kernels/sma.jl")
include("kernels/wma.jl")
include("kernels/kama.jl")
include("kernels/hilbert.jl")
include("kernels/ma.jl")
include("kernels/gainloss.jl")
include("kernels/stoch.jl")
include("kernels/atr.jl")
include("kernels/dm.jl")

include("barindicator.jl")

include("overlap.jl")
include("price.jl")
include("momentum.jl")
include("volatility.jl")
include("statistics.jl")
include("volume.jl")
include("cycle.jl")

end
