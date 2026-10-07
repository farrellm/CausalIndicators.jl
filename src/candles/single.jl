# The one-bar patterns. Each pattern `P` gives `candleshape(Val(P))` (the
# settings it reads and the bars it reads back), `candlelookback(Val(P), s)`
# (its `TA_CDL*_Lookback`), and `candle(Val(P), b)`, its condition copied term
# by term from `ta_CDL<P>.c` over the `CandleBars` `b`. `avg(b, :s, ℓ)` is
# `TA_CANDLEAVERAGE(s, …, i − ℓ)`.

# ta_CDLBELTHOLD.c
candleshape(::Val{:BeltHold}) = ((:bodylong, :shadowveryshort), 1)
candlelookback(::Val{:BeltHold}, s) = max(s.bodylong.avgperiod, s.shadowveryshort.avgperiod)
@inline candle(::Val{:BeltHold}, b) =
    body(b, 0) > avg(b, :bodylong, 0) &&
    (
        (white(b, 0) && lower(b, 0) < avg(b, :shadowveryshort, 0)) ||
        (black(b, 0) && upper(b, 0) < avg(b, :shadowveryshort, 0))
    ) ? color(b, 0) * 100 : 0

# ta_CDLCLOSINGMARUBOZU.c
candleshape(::Val{:ClosingMarubozu}) = ((:bodylong, :shadowveryshort), 1)
candlelookback(::Val{:ClosingMarubozu}, s) =
    max(s.bodylong.avgperiod, s.shadowveryshort.avgperiod)
@inline candle(::Val{:ClosingMarubozu}, b) =
    body(b, 0) > avg(b, :bodylong, 0) &&
    (
        (white(b, 0) && upper(b, 0) < avg(b, :shadowveryshort, 0)) ||
        (black(b, 0) && lower(b, 0) < avg(b, :shadowveryshort, 0))
    ) ? color(b, 0) * 100 : 0

# ta_CDLDOJI.c
candleshape(::Val{:Doji}) = ((:bodydoji,), 1)
candlelookback(::Val{:Doji}, s) = s.bodydoji.avgperiod
@inline candle(::Val{:Doji}, b) = body(b, 0) <= avg(b, :bodydoji, 0) ? 100 : 0

# ta_CDLDRAGONFLYDOJI.c
candleshape(::Val{:DragonflyDoji}) = ((:bodydoji, :shadowveryshort), 1)
candlelookback(::Val{:DragonflyDoji}, s) =
    max(s.bodydoji.avgperiod, s.shadowveryshort.avgperiod)
@inline candle(::Val{:DragonflyDoji}, b) =
    body(b, 0) <= avg(b, :bodydoji, 0) && upper(b, 0) < avg(b, :shadowveryshort, 0) &&
    lower(b, 0) > avg(b, :shadowveryshort, 0) ? 100 : 0

# ta_CDLGRAVESTONEDOJI.c
candleshape(::Val{:GravestoneDoji}) = ((:bodydoji, :shadowveryshort), 1)
candlelookback(::Val{:GravestoneDoji}, s) =
    max(s.bodydoji.avgperiod, s.shadowveryshort.avgperiod)
@inline candle(::Val{:GravestoneDoji}, b) =
    body(b, 0) <= avg(b, :bodydoji, 0) && lower(b, 0) < avg(b, :shadowveryshort, 0) &&
    upper(b, 0) > avg(b, :shadowveryshort, 0) ? 100 : 0

# ta_CDLHIGHWAVE.c
candleshape(::Val{:HighWave}) = ((:bodyshort, :shadowverylong), 1)
candlelookback(::Val{:HighWave}, s) = max(s.bodyshort.avgperiod, s.shadowverylong.avgperiod)
@inline candle(::Val{:HighWave}, b) =
    body(b, 0) < avg(b, :bodyshort, 0) && upper(b, 0) > avg(b, :shadowverylong, 0) &&
    lower(b, 0) > avg(b, :shadowverylong, 0) ? color(b, 0) * 100 : 0

# ta_CDLLONGLEGGEDDOJI.c
candleshape(::Val{:LongLeggedDoji}) = ((:bodydoji, :shadowlong), 1)
candlelookback(::Val{:LongLeggedDoji}, s) =
    max(s.bodydoji.avgperiod, s.shadowlong.avgperiod)
@inline candle(::Val{:LongLeggedDoji}, b) =
    body(b, 0) <= avg(b, :bodydoji, 0) &&
    (lower(b, 0) > avg(b, :shadowlong, 0) || upper(b, 0) > avg(b, :shadowlong, 0)) ? 100 : 0

# ta_CDLLONGLINE.c
candleshape(::Val{:LongLine}) = ((:bodylong, :shadowshort), 1)
candlelookback(::Val{:LongLine}, s) = max(s.bodylong.avgperiod, s.shadowshort.avgperiod)
@inline candle(::Val{:LongLine}, b) =
    body(b, 0) > avg(b, :bodylong, 0) && upper(b, 0) < avg(b, :shadowshort, 0) &&
    lower(b, 0) < avg(b, :shadowshort, 0) ? color(b, 0) * 100 : 0

# ta_CDLMARUBOZU.c
candleshape(::Val{:Marubozu}) = ((:bodylong, :shadowveryshort), 1)
candlelookback(::Val{:Marubozu}, s) = max(s.bodylong.avgperiod, s.shadowveryshort.avgperiod)
@inline candle(::Val{:Marubozu}, b) =
    body(b, 0) > avg(b, :bodylong, 0) && upper(b, 0) < avg(b, :shadowveryshort, 0) &&
    lower(b, 0) < avg(b, :shadowveryshort, 0) ? color(b, 0) * 100 : 0

# ta_CDLRICKSHAWMAN.c: a doji with two long shadows and its body near the
# middle of its range.
candleshape(::Val{:RickshawMan}) = ((:bodydoji, :shadowlong, :near), 1)
candlelookback(::Val{:RickshawMan}, s) =
    max(s.bodydoji.avgperiod, s.shadowlong.avgperiod, s.near.avgperiod)
@inline function candle(::Val{:RickshawMan}, b)
    mid = lo(b, 0) + (hi(b, 0) - lo(b, 0)) / 2
    return body(b, 0) <= avg(b, :bodydoji, 0) && lower(b, 0) > avg(b, :shadowlong, 0) &&
           upper(b, 0) > avg(b, :shadowlong, 0) &&
           (
               bodybot(b, 0) <= mid + avg(b, :near, 0) &&
               bodytop(b, 0) >= mid - avg(b, :near, 0)
           ) ? 100 : 0
end

# ta_CDLSHORTLINE.c
candleshape(::Val{:ShortLine}) = ((:bodyshort, :shadowshort), 1)
candlelookback(::Val{:ShortLine}, s) = max(s.bodyshort.avgperiod, s.shadowshort.avgperiod)
@inline candle(::Val{:ShortLine}, b) =
    body(b, 0) < avg(b, :bodyshort, 0) && upper(b, 0) < avg(b, :shadowshort, 0) &&
    lower(b, 0) < avg(b, :shadowshort, 0) ? color(b, 0) * 100 : 0

# ta_CDLSPINNINGTOP.c
candleshape(::Val{:SpinningTop}) = ((:bodyshort,), 1)
candlelookback(::Val{:SpinningTop}, s) = s.bodyshort.avgperiod
@inline candle(::Val{:SpinningTop}, b) =
    upper(b, 0) > body(b, 0) && lower(b, 0) > body(b, 0) &&
    body(b, 0) < avg(b, :bodyshort, 0) ? color(b, 0) * 100 : 0

# ta_CDLTAKURI.c
candleshape(::Val{:Takuri}) = ((:bodydoji, :shadowveryshort, :shadowverylong), 1)
candlelookback(::Val{:Takuri}, s) =
    max(s.bodydoji.avgperiod, s.shadowveryshort.avgperiod, s.shadowverylong.avgperiod)
@inline candle(::Val{:Takuri}, b) =
    body(b, 0) <= avg(b, :bodydoji, 0) && upper(b, 0) < avg(b, :shadowveryshort, 0) &&
    lower(b, 0) > avg(b, :shadowverylong, 0) ? 100 : 0
