# The three-bar patterns. Bar 2 is the first, bar 0 the current.

# ta_CDL2CROWS.c
candleshape(::Val{:TwoCrows}) = ((:bodylong,), 3)
candlelookback(::Val{:TwoCrows}, s) = s.bodylong.avgperiod + 2
@inline candle(::Val{:TwoCrows}, b) =
    white(b, 2) && body(b, 2) > avg(b, :bodylong, 2) && black(b, 1) &&
    bodygapup(b, 1, 2) && black(b, 0) && op(b, 0) < op(b, 1) && op(b, 0) > cl(b, 1) &&
    cl(b, 0) > op(b, 2) && cl(b, 0) < cl(b, 2) ? -100 : 0

# ta_CDL3INSIDE.c
candleshape(::Val{:ThreeInside}) = ((:bodyshort, :bodylong), 3)
candlelookback(::Val{:ThreeInside}, s) =
    max(s.bodyshort.avgperiod, s.bodylong.avgperiod) + 2
@inline candle(::Val{:ThreeInside}, b) =
    cmax(cl(b, 1), op(b, 1)) < cmax(cl(b, 2), op(b, 2)) &&
    cmin(cl(b, 1), op(b, 1)) > cmin(cl(b, 2), op(b, 2)) &&
    (
        (white(b, 2) && black(b, 0) && cl(b, 0) < op(b, 2)) ||
        (black(b, 2) && white(b, 0) && cl(b, 0) > op(b, 2))
    ) &&
    body(b, 2) > avg(b, :bodylong, 2) &&
    body(b, 1) <= avg(b, :bodyshort, 1) ? -color(b, 2) * 100 : 0

# ta_CDL3OUTSIDE.c
candleshape(::Val{:ThreeOutside}) = ((), 3)
candlelookback(::Val{:ThreeOutside}, s) = 3
@inline candle(::Val{:ThreeOutside}, b) =
    (
        white(b, 1) && black(b, 2) && cl(b, 1) > op(b, 2) && op(b, 1) < cl(b, 2) &&
        cl(b, 0) > cl(b, 1)
    ) ||
    (
        black(b, 1) && white(b, 2) && op(b, 1) > cl(b, 2) && cl(b, 1) < op(b, 2) &&
        cl(b, 0) < cl(b, 1)
    ) ? color(b, 1) * 100 : 0

# ta_CDL3STARSINSOUTH.c
candleshape(::Val{:ThreeStarsInTheSouth}) =
    ((:shadowveryshort, :shadowlong, :bodylong, :bodyshort), 3)
candlelookback(::Val{:ThreeStarsInTheSouth}, s) =
    max(s.shadowveryshort.avgperiod, s.shadowlong.avgperiod, s.bodylong.avgperiod,
        s.bodyshort.avgperiod) + 2
@inline candle(::Val{:ThreeStarsInTheSouth}, b) =
    black(b, 2) && black(b, 1) && black(b, 0) && body(b, 2) > avg(b, :bodylong, 2) &&
    lower(b, 2) > avg(b, :shadowlong, 2) && body(b, 1) < body(b, 2) &&
    op(b, 1) > cl(b, 2) && op(b, 1) <= hi(b, 2) && lo(b, 1) < cl(b, 2) &&
    lo(b, 1) >= lo(b, 2) && lower(b, 1) > avg(b, :shadowveryshort, 1) &&
    body(b, 0) < avg(b, :bodyshort, 0) && lower(b, 0) < avg(b, :shadowveryshort, 0) &&
    upper(b, 0) < avg(b, :shadowveryshort, 0) && lo(b, 0) > lo(b, 1) &&
    hi(b, 0) < hi(b, 1) ? 100 : 0

# ta_CDL3WHITESOLDIERS.c
candleshape(::Val{:ThreeWhiteSoldiers}) = ((:shadowveryshort, :bodyshort, :far, :near), 3)
candlelookback(::Val{:ThreeWhiteSoldiers}, s) =
    max(s.shadowveryshort.avgperiod, s.bodyshort.avgperiod, s.far.avgperiod,
        s.near.avgperiod) + 2
@inline candle(::Val{:ThreeWhiteSoldiers}, b) =
    white(b, 2) && upper(b, 2) < avg(b, :shadowveryshort, 2) && white(b, 1) &&
    upper(b, 1) < avg(b, :shadowveryshort, 1) && white(b, 0) &&
    upper(b, 0) < avg(b, :shadowveryshort, 0) && cl(b, 0) > cl(b, 1) &&
    cl(b, 1) > cl(b, 2) && op(b, 1) > op(b, 2) &&
    op(b, 1) <= cl(b, 2) + avg(b, :near, 2) && op(b, 0) > op(b, 1) &&
    op(b, 0) <= cl(b, 1) + avg(b, :near, 1) &&
    body(b, 1) > body(b, 2) - avg(b, :far, 2) &&
    body(b, 0) > body(b, 1) - avg(b, :far, 1) &&
    body(b, 0) > avg(b, :bodyshort, 0) ? 100 : 0

# ta_CDLABANDONEDBABY.c. The bullish arm forms its bound with fma, as TA-Lib
# does.
candleshape(::Val{:AbandonedBaby}) = ((:bodydoji, :bodylong, :bodyshort), 3)
candlelookback(::Val{:AbandonedBaby}, s) =
    max(s.bodydoji.avgperiod, s.bodylong.avgperiod, s.bodyshort.avgperiod) + 2
@inline candle(::Val{:AbandonedBaby}, b) =
    body(b, 2) > avg(b, :bodylong, 2) && body(b, 1) <= avg(b, :bodydoji, 1) &&
    body(b, 0) > avg(b, :bodyshort, 0) &&
    (
        (
            white(b, 2) && black(b, 0) &&
            cl(b, 0) < cl(b, 2) - body(b, 2) * b.penetration &&
            gapup(b, 1, 2) && gapdown(b, 0, 1)
        ) ||
        (
            black(b, 2) && white(b, 0) &&
            cl(b, 0) > fma(body(b, 2), b.penetration, cl(b, 2)) &&
            gapdown(b, 1, 2) && gapup(b, 0, 1)
        )
    ) ? color(b, 0) * 100 : 0

# ta_CDLADVANCEBLOCK.c: three advancing white candles that weaken, in any of
# four ways.
candleshape(::Val{:AdvanceBlock}) = ((:shadowlong, :shadowshort, :far, :near, :bodylong), 3)
candlelookback(::Val{:AdvanceBlock}, s) =
    max(s.shadowlong.avgperiod, s.shadowshort.avgperiod, s.far.avgperiod, s.near.avgperiod,
        s.bodylong.avgperiod) + 2
@inline candle(::Val{:AdvanceBlock}, b) =
    white(b, 2) && white(b, 1) && white(b, 0) && cl(b, 0) > cl(b, 1) &&
    cl(b, 1) > cl(b, 2) && op(b, 1) > op(b, 2) &&
    op(b, 1) <= cl(b, 2) + avg(b, :near, 2) && op(b, 0) > op(b, 1) &&
    op(b, 0) <= cl(b, 1) + avg(b, :near, 1) && body(b, 2) > avg(b, :bodylong, 2) &&
    upper(b, 2) < avg(b, :shadowshort, 2) &&
    (
        (
            body(b, 1) < body(b, 2) - avg(b, :far, 2) &&
            body(b, 0) < body(b, 1) + avg(b, :near, 1)
        ) ||
        body(b, 0) < body(b, 1) - avg(b, :far, 1) ||
        (
            body(b, 0) < body(b, 1) && body(b, 1) < body(b, 2) &&
            (upper(b, 0) > avg(b, :shadowshort, 0) || upper(b, 1) > avg(b, :shadowshort, 1))
        ) ||
        (body(b, 0) < body(b, 1) && upper(b, 0) > avg(b, :shadowlong, 0))
    ) ? -100 : 0

# ta_CDLEVENINGDOJISTAR.c
candleshape(::Val{:EveningDojiStar}) = ((:bodydoji, :bodylong, :bodyshort), 3)
candlelookback(::Val{:EveningDojiStar}, s) =
    max(s.bodydoji.avgperiod, s.bodylong.avgperiod, s.bodyshort.avgperiod) + 2
@inline candle(::Val{:EveningDojiStar}, b) =
    white(b, 2) && black(b, 0) && bodygapup(b, 1, 2) &&
    cl(b, 0) < cl(b, 2) - body(b, 2) * b.penetration && body(b, 2) > avg(b, :bodylong, 2) &&
    body(b, 1) <= avg(b, :bodydoji, 1) && body(b, 0) > avg(b, :bodyshort, 0) ? -100 : 0

# ta_CDLEVENINGSTAR.c
candleshape(::Val{:EveningStar}) = ((:bodyshort, :bodylong), 3)
candlelookback(::Val{:EveningStar}, s) =
    max(s.bodyshort.avgperiod, s.bodylong.avgperiod) + 2
@inline candle(::Val{:EveningStar}, b) =
    white(b, 2) && black(b, 0) && bodygapup(b, 1, 2) &&
    cl(b, 0) < cl(b, 2) - body(b, 2) * b.penetration && body(b, 2) > avg(b, :bodylong, 2) &&
    body(b, 1) <= avg(b, :bodyshort, 1) && body(b, 0) > avg(b, :bodyshort, 0) ? -100 : 0

# ta_CDLGAPSIDESIDEWHITE.c
candleshape(::Val{:GapSideSideWhite}) = ((:near, :equal), 3)
candlelookback(::Val{:GapSideSideWhite}, s) = max(s.near.avgperiod, s.equal.avgperiod) + 2
@inline candle(::Val{:GapSideSideWhite}, b) =
    (
        (bodygapup(b, 1, 2) && bodygapup(b, 0, 2)) ||
        (bodygapdown(b, 1, 2) && bodygapdown(b, 0, 2))
    ) && white(b, 1) && white(b, 0) &&
    body(b, 0) >= body(b, 1) - avg(b, :near, 1) &&
    body(b, 0) <= body(b, 1) + avg(b, :near, 1) &&
    op(b, 0) >= op(b, 1) - avg(b, :equal, 1) &&
    op(b, 0) <= op(b, 1) + avg(b, :equal, 1) ? (bodygapup(b, 1, 2) ? 100 : -100) : 0

# ta_CDLIDENTICAL3CROWS.c
candleshape(::Val{:IdenticalThreeCrows}) = ((:shadowveryshort, :equal), 3)
candlelookback(::Val{:IdenticalThreeCrows}, s) =
    max(s.shadowveryshort.avgperiod, s.equal.avgperiod) + 2
@inline candle(::Val{:IdenticalThreeCrows}, b) =
    black(b, 2) && lower(b, 2) < avg(b, :shadowveryshort, 2) && black(b, 1) &&
    lower(b, 1) < avg(b, :shadowveryshort, 1) && black(b, 0) &&
    lower(b, 0) < avg(b, :shadowveryshort, 0) && cl(b, 2) > cl(b, 1) &&
    cl(b, 1) > cl(b, 0) && op(b, 1) <= cl(b, 2) + avg(b, :equal, 2) &&
    op(b, 1) >= cl(b, 2) - avg(b, :equal, 2) && op(b, 0) <= cl(b, 1) + avg(b, :equal, 1) &&
    op(b, 0) >= cl(b, 1) - avg(b, :equal, 1) ? -100 : 0

# ta_CDLMORNINGDOJISTAR.c
candleshape(::Val{:MorningDojiStar}) = ((:bodydoji, :bodylong, :bodyshort), 3)
candlelookback(::Val{:MorningDojiStar}, s) =
    max(s.bodydoji.avgperiod, s.bodylong.avgperiod, s.bodyshort.avgperiod) + 2
@inline candle(::Val{:MorningDojiStar}, b) =
    black(b, 2) && white(b, 0) && bodygapdown(b, 1, 2) &&
    cl(b, 0) > fma(body(b, 2), b.penetration, cl(b, 2)) &&
    body(b, 2) > avg(b, :bodylong, 2) && body(b, 1) <= avg(b, :bodydoji, 1) &&
    body(b, 0) > avg(b, :bodyshort, 0) ? 100 : 0

# ta_CDLMORNINGSTAR.c
candleshape(::Val{:MorningStar}) = ((:bodyshort, :bodylong), 3)
candlelookback(::Val{:MorningStar}, s) =
    max(s.bodyshort.avgperiod, s.bodylong.avgperiod) + 2
@inline candle(::Val{:MorningStar}, b) =
    black(b, 2) && white(b, 0) && bodygapdown(b, 1, 2) &&
    cl(b, 0) > fma(body(b, 2), b.penetration, cl(b, 2)) &&
    body(b, 2) > avg(b, :bodylong, 2) && body(b, 1) <= avg(b, :bodyshort, 1) &&
    body(b, 0) > avg(b, :bodyshort, 0) ? 100 : 0

# ta_CDLSTALLEDPATTERN.c
candleshape(::Val{:StalledPattern}) = ((:bodylong, :bodyshort, :shadowveryshort, :near), 3)
candlelookback(::Val{:StalledPattern}, s) =
    max(s.bodylong.avgperiod, s.bodyshort.avgperiod, s.shadowveryshort.avgperiod,
        s.near.avgperiod) + 2
@inline candle(::Val{:StalledPattern}, b) =
    white(b, 2) && white(b, 1) && white(b, 0) && cl(b, 0) > cl(b, 1) &&
    cl(b, 1) > cl(b, 2) && body(b, 2) > avg(b, :bodylong, 2) &&
    body(b, 1) > avg(b, :bodylong, 1) && upper(b, 1) < avg(b, :shadowveryshort, 1) &&
    op(b, 1) > op(b, 2) && op(b, 1) <= cl(b, 2) + avg(b, :near, 2) &&
    body(b, 0) < avg(b, :bodyshort, 0) &&
    op(b, 0) >= cl(b, 1) - body(b, 0) - avg(b, :near, 1) ? -100 : 0

# ta_CDLSTICKSANDWICH.c
candleshape(::Val{:StickSandwich}) = ((:equal,), 3)
candlelookback(::Val{:StickSandwich}, s) = s.equal.avgperiod + 2
@inline candle(::Val{:StickSandwich}, b) =
    black(b, 2) && white(b, 1) && black(b, 0) && lo(b, 1) > cl(b, 2) &&
    cl(b, 0) <= cl(b, 2) + avg(b, :equal, 2) &&
    cl(b, 0) >= cl(b, 2) - avg(b, :equal, 2) ? 100 : 0

# ta_CDLTASUKIGAP.c
candleshape(::Val{:TasukiGap}) = ((:near,), 3)
candlelookback(::Val{:TasukiGap}, s) = s.near.avgperiod + 2
@inline candle(::Val{:TasukiGap}, b) =
    (
        bodygapup(b, 1, 2) && white(b, 1) && black(b, 0) && op(b, 0) < cl(b, 1) &&
        op(b, 0) > op(b, 1) && cl(b, 0) < op(b, 1) && cl(b, 0) > cmax(cl(b, 2), op(b, 2)) &&
        abs(body(b, 1) - body(b, 0)) < avg(b, :near, 1)
    ) ||
    (
        bodygapdown(b, 1, 2) && black(b, 1) && white(b, 0) && op(b, 0) < op(b, 1) &&
        op(b, 0) > cl(b, 1) && cl(b, 0) > op(b, 1) && cl(b, 0) < cmin(cl(b, 2), op(b, 2)) &&
        abs(body(b, 1) - body(b, 0)) < avg(b, :near, 1)
    ) ? color(b, 1) * 100 : 0

# ta_CDLTRISTAR.c: three doji, each held to the first's threshold.
candleshape(::Val{:Tristar}) = ((:bodydoji,), 3)
candlelookback(::Val{:Tristar}, s) = s.bodydoji.avgperiod + 2
@inline function candle(::Val{:Tristar}, b)
    d = avg(b, :bodydoji, 2)
    body(b, 2) <= d && body(b, 1) <= d && body(b, 0) <= d || return 0
    out = 0
    bodygapup(b, 1, 2) && cmax(op(b, 0), cl(b, 0)) < cmax(op(b, 1), cl(b, 1)) &&
        (out = -100)
    bodygapdown(b, 1, 2) && cmin(op(b, 0), cl(b, 0)) > cmin(op(b, 1), cl(b, 1)) &&
        (out = 100)
    return out
end

# ta_CDLUNIQUE3RIVER.c
candleshape(::Val{:UniqueThreeRiver}) = ((:bodyshort, :bodylong), 3)
candlelookback(::Val{:UniqueThreeRiver}, s) =
    max(s.bodyshort.avgperiod, s.bodylong.avgperiod) + 2
@inline candle(::Val{:UniqueThreeRiver}, b) =
    black(b, 2) && black(b, 1) && white(b, 0) && cl(b, 1) > cl(b, 2) &&
    op(b, 1) <= op(b, 2) && lo(b, 1) < lo(b, 2) && op(b, 0) > lo(b, 1) &&
    body(b, 2) > avg(b, :bodylong, 2) && body(b, 0) < avg(b, :bodyshort, 0) ? 100 : 0

# ta_CDLUPSIDEGAP2CROWS.c
candleshape(::Val{:UpsideGapTwoCrows}) = ((:bodyshort, :bodylong), 3)
candlelookback(::Val{:UpsideGapTwoCrows}, s) =
    max(s.bodyshort.avgperiod, s.bodylong.avgperiod) + 2
@inline candle(::Val{:UpsideGapTwoCrows}, b) =
    white(b, 2) && body(b, 2) > avg(b, :bodylong, 2) && black(b, 1) &&
    body(b, 1) <= avg(b, :bodyshort, 1) && bodygapup(b, 1, 2) && black(b, 0) &&
    op(b, 0) > op(b, 1) && cl(b, 0) < cl(b, 1) && cl(b, 0) > cl(b, 2) ? -100 : 0

# ta_CDLXSIDEGAP3METHODS.c
candleshape(::Val{:XSideGapThreeMethods}) = ((), 3)
candlelookback(::Val{:XSideGapThreeMethods}, s) = 2
@inline candle(::Val{:XSideGapThreeMethods}, b) =
    color(b, 2) == color(b, 1) && color(b, 1) == -color(b, 0) &&
    op(b, 0) < cmax(cl(b, 1), op(b, 1)) && op(b, 0) > cmin(cl(b, 1), op(b, 1)) &&
    cl(b, 0) < cmax(cl(b, 2), op(b, 2)) && cl(b, 0) > cmin(cl(b, 2), op(b, 2)) &&
    ((white(b, 2) && bodygapup(b, 1, 2)) ||
     (black(b, 2) && bodygapdown(b, 1, 2))) ? color(b, 2) * 100 : 0
