# The two-bar patterns, and the one-bar ones that compare with the bar before
# (hammers and stars). Bar 1 is the earlier, bar 0 the current.

# ta_CDLHAMMER.c
candleshape(::Val{:Hammer}) = ((:bodyshort, :shadowlong, :shadowveryshort, :near), 2)
candlelookback(::Val{:Hammer}, s) =
    max(s.bodyshort.avgperiod, s.shadowlong.avgperiod, s.shadowveryshort.avgperiod,
        s.near.avgperiod) + 1
@inline candle(::Val{:Hammer}, b) =
    body(b, 0) < avg(b, :bodyshort, 0) && lower(b, 0) > avg(b, :shadowlong, 0) &&
    upper(b, 0) < avg(b, :shadowveryshort, 0) &&
    cmin(cl(b, 0), op(b, 0)) <= lo(b, 1) + avg(b, :near, 1) ? 100 : 0

# ta_CDLHANGINGMAN.c
candleshape(::Val{:HangingMan}) = ((:bodyshort, :shadowlong, :shadowveryshort, :near), 2)
candlelookback(::Val{:HangingMan}, s) =
    max(s.bodyshort.avgperiod, s.shadowlong.avgperiod, s.shadowveryshort.avgperiod,
        s.near.avgperiod) + 1
@inline candle(::Val{:HangingMan}, b) =
    body(b, 0) < avg(b, :bodyshort, 0) && lower(b, 0) > avg(b, :shadowlong, 0) &&
    upper(b, 0) < avg(b, :shadowveryshort, 0) &&
    cmin(cl(b, 0), op(b, 0)) >= hi(b, 1) - avg(b, :near, 1) ? -100 : 0

# ta_CDLINVERTEDHAMMER.c
candleshape(::Val{:InvertedHammer}) = ((:bodyshort, :shadowlong, :shadowveryshort), 2)
candlelookback(::Val{:InvertedHammer}, s) =
    max(s.bodyshort.avgperiod, s.shadowlong.avgperiod, s.shadowveryshort.avgperiod) + 1
@inline candle(::Val{:InvertedHammer}, b) =
    bodygapdown(b, 0, 1) && body(b, 0) < avg(b, :bodyshort, 0) &&
    upper(b, 0) > avg(b, :shadowlong, 0) &&
    lower(b, 0) < avg(b, :shadowveryshort, 0) ? 100 : 0

# ta_CDLSHOOTINGSTAR.c
candleshape(::Val{:ShootingStar}) = ((:bodyshort, :shadowlong, :shadowveryshort), 2)
candlelookback(::Val{:ShootingStar}, s) =
    max(s.bodyshort.avgperiod, s.shadowlong.avgperiod, s.shadowveryshort.avgperiod) + 1
@inline candle(::Val{:ShootingStar}, b) =
    bodygapup(b, 0, 1) && body(b, 0) < avg(b, :bodyshort, 0) &&
    upper(b, 0) > avg(b, :shadowlong, 0) &&
    lower(b, 0) < avg(b, :shadowveryshort, 0) ? -100 : 0

# ta_CDLCOUNTERATTACK.c
candleshape(::Val{:Counterattack}) = ((:bodylong, :equal), 2)
candlelookback(::Val{:Counterattack}, s) = max(s.equal.avgperiod, s.bodylong.avgperiod) + 1
@inline candle(::Val{:Counterattack}, b) =
    color(b, 1) == -color(b, 0) && body(b, 1) > avg(b, :bodylong, 1) &&
    body(b, 0) > avg(b, :bodylong, 0) && cl(b, 0) <= cl(b, 1) + avg(b, :equal, 1) &&
    cl(b, 0) >= cl(b, 1) - avg(b, :equal, 1) ? color(b, 0) * 100 : 0

# ta_CDLDARKCLOUDCOVER.c
candleshape(::Val{:DarkCloudCover}) = ((:bodylong,), 2)
candlelookback(::Val{:DarkCloudCover}, s) = s.bodylong.avgperiod + 1
@inline candle(::Val{:DarkCloudCover}, b) =
    white(b, 1) && body(b, 1) > avg(b, :bodylong, 1) && black(b, 0) &&
    op(b, 0) > hi(b, 1) && cl(b, 0) > op(b, 1) &&
    cl(b, 0) < cl(b, 1) - body(b, 1) * b.penetration ? -100 : 0

# ta_CDLDOJISTAR.c
candleshape(::Val{:DojiStar}) = ((:bodylong, :bodydoji), 2)
candlelookback(::Val{:DojiStar}, s) = max(s.bodydoji.avgperiod, s.bodylong.avgperiod) + 1
@inline candle(::Val{:DojiStar}, b) =
    body(b, 1) > avg(b, :bodylong, 1) && body(b, 0) <= avg(b, :bodydoji, 0) &&
    ((white(b, 1) && bodygapup(b, 0, 1)) ||
     (black(b, 1) && bodygapdown(b, 0, 1))) ? -color(b, 1) * 100 : 0

# ta_CDLENGULFING.c: 100 when the bodies engulf strictly, 80 when one end
# matches.
candleshape(::Val{:Engulfing}) = ((), 2)
candlelookback(::Val{:Engulfing}, s) = 2
@inline function candle(::Val{:Engulfing}, b)
    o0, c0, o1, c1 = op(b, 0), cl(b, 0), op(b, 1), cl(b, 1)
    if (white(b, 0) && black(b, 1) && ((c0 >= o1 && o0 < c1) || (c0 > o1 && o0 <= c1))) ||
       (black(b, 0) && white(b, 1) && ((o0 >= c1 && c0 < o1) || (o0 > c1 && c0 <= o1)))
        return o0 != c1 && c0 != o1 ? color(b, 0) * 100 : color(b, 0) * 80
    end
    return 0
end

# ta_CDLHARAMI.c: 100 when the second body sits strictly inside the first,
# 80 when one end matches.
candleshape(::Val{:Harami}) = ((:bodylong, :bodyshort), 2)
candlelookback(::Val{:Harami}, s) = max(s.bodyshort.avgperiod, s.bodylong.avgperiod) + 1
@inline candle(::Val{:Harami}, b) =
    body(b, 1) > avg(b, :bodylong, 1) && body(b, 0) <= avg(b, :bodyshort, 0) ?
    haramiinside(b) : 0

# ta_CDLHARAMICROSS.c
candleshape(::Val{:HaramiCross}) = ((:bodylong, :bodydoji), 2)
candlelookback(::Val{:HaramiCross}, s) = max(s.bodydoji.avgperiod, s.bodylong.avgperiod) + 1
@inline candle(::Val{:HaramiCross}, b) =
    body(b, 1) > avg(b, :bodylong, 1) && body(b, 0) <= avg(b, :bodydoji, 0) ?
    haramiinside(b) : 0

@inline function haramiinside(b)
    t0, b0 = cmax(cl(b, 0), op(b, 0)), cmin(cl(b, 0), op(b, 0))
    t1, b1 = cmax(cl(b, 1), op(b, 1)), cmin(cl(b, 1), op(b, 1))
    t0 < t1 && b0 > b1 && return -color(b, 1) * 100
    t0 <= t1 && b0 >= b1 && return -color(b, 1) * 80
    return 0
end

# ta_CDLHOMINGPIGEON.c
candleshape(::Val{:HomingPigeon}) = ((:bodylong, :bodyshort), 2)
candlelookback(::Val{:HomingPigeon}, s) =
    max(s.bodyshort.avgperiod, s.bodylong.avgperiod) + 1
@inline candle(::Val{:HomingPigeon}, b) =
    black(b, 1) && black(b, 0) && body(b, 1) > avg(b, :bodylong, 1) &&
    body(b, 0) <= avg(b, :bodyshort, 0) && op(b, 0) < op(b, 1) &&
    cl(b, 0) > cl(b, 1) ? 100 : 0

# ta_CDLINNECK.c
candleshape(::Val{:InNeck}) = ((:bodylong, :equal), 2)
candlelookback(::Val{:InNeck}, s) = max(s.equal.avgperiod, s.bodylong.avgperiod) + 1
@inline candle(::Val{:InNeck}, b) =
    black(b, 1) && body(b, 1) > avg(b, :bodylong, 1) && white(b, 0) &&
    op(b, 0) < lo(b, 1) && cl(b, 0) <= cl(b, 1) + avg(b, :equal, 1) &&
    cl(b, 0) >= cl(b, 1) ? -100 : 0

# ta_CDLKICKING.c and ta_CDLKICKINGBYLENGTH.c: two opposite marubozu with a
# gap between them. Kicking takes its sign from the second, KickingByLength
# from the longer.
candleshape(::Val{:Kicking}) = ((:bodylong, :shadowveryshort), 2)
candlelookback(::Val{:Kicking}, s) =
    max(s.shadowveryshort.avgperiod, s.bodylong.avgperiod) + 1
@inline candle(::Val{:Kicking}, b) = kicking(b) ? color(b, 0) * 100 : 0

candleshape(::Val{:KickingByLength}) = ((:bodylong, :shadowveryshort), 2)
candlelookback(::Val{:KickingByLength}, s) =
    max(s.shadowveryshort.avgperiod, s.bodylong.avgperiod) + 1
@inline candle(::Val{:KickingByLength}, b) =
    kicking(b) ? color(b, body(b, 0) > body(b, 1) ? 0 : 1) * 100 : 0

@inline kicking(b) =
    color(b, 1) == -color(b, 0) && body(b, 1) > avg(b, :bodylong, 1) &&
    upper(b, 1) < avg(b, :shadowveryshort, 1) &&
    lower(b, 1) < avg(b, :shadowveryshort, 1) &&
    body(b, 0) > avg(b, :bodylong, 0) && upper(b, 0) < avg(b, :shadowveryshort, 0) &&
    lower(b, 0) < avg(b, :shadowveryshort, 0) &&
    ((black(b, 1) && gapup(b, 0, 1)) || (white(b, 1) && gapdown(b, 0, 1)))

# ta_CDLMATCHINGLOW.c
candleshape(::Val{:MatchingLow}) = ((:equal,), 2)
candlelookback(::Val{:MatchingLow}, s) = s.equal.avgperiod + 1
@inline candle(::Val{:MatchingLow}, b) =
    black(b, 1) && black(b, 0) && cl(b, 0) <= cl(b, 1) + avg(b, :equal, 1) &&
    cl(b, 0) >= cl(b, 1) - avg(b, :equal, 1) ? 100 : 0

# ta_CDLONNECK.c
candleshape(::Val{:OnNeck}) = ((:bodylong, :equal), 2)
candlelookback(::Val{:OnNeck}, s) = max(s.equal.avgperiod, s.bodylong.avgperiod) + 1
@inline candle(::Val{:OnNeck}, b) =
    black(b, 1) && body(b, 1) > avg(b, :bodylong, 1) && white(b, 0) &&
    op(b, 0) < lo(b, 1) && cl(b, 0) <= lo(b, 1) + avg(b, :equal, 1) &&
    cl(b, 0) >= lo(b, 1) - avg(b, :equal, 1) ? -100 : 0

# ta_CDLPIERCING.c
candleshape(::Val{:Piercing}) = ((:bodylong,), 2)
candlelookback(::Val{:Piercing}, s) = s.bodylong.avgperiod + 1
@inline candle(::Val{:Piercing}, b) =
    black(b, 1) && body(b, 1) > avg(b, :bodylong, 1) && white(b, 0) &&
    body(b, 0) > avg(b, :bodylong, 0) && op(b, 0) < lo(b, 1) && cl(b, 0) < op(b, 1) &&
    cl(b, 0) > fma(body(b, 1), oftype(body(b, 1), 0.5), cl(b, 1)) ? 100 : 0

# ta_CDLSEPARATINGLINES.c
candleshape(::Val{:SeparatingLines}) = ((:shadowveryshort, :bodylong, :equal), 2)
candlelookback(::Val{:SeparatingLines}, s) =
    max(s.shadowveryshort.avgperiod, s.bodylong.avgperiod, s.equal.avgperiod) + 1
@inline candle(::Val{:SeparatingLines}, b) =
    color(b, 1) == -color(b, 0) && op(b, 0) <= op(b, 1) + avg(b, :equal, 1) &&
    op(b, 0) >= op(b, 1) - avg(b, :equal, 1) && body(b, 0) > avg(b, :bodylong, 0) &&
    (
        (white(b, 0) && lower(b, 0) < avg(b, :shadowveryshort, 0)) ||
        (black(b, 0) && upper(b, 0) < avg(b, :shadowveryshort, 0))
    ) ? color(b, 0) * 100 : 0

# ta_CDLTHRUSTING.c
candleshape(::Val{:Thrusting}) = ((:bodylong, :equal), 2)
candlelookback(::Val{:Thrusting}, s) = max(s.equal.avgperiod, s.bodylong.avgperiod) + 1
@inline candle(::Val{:Thrusting}, b) =
    black(b, 1) && body(b, 1) > avg(b, :bodylong, 1) && white(b, 0) &&
    op(b, 0) < lo(b, 1) && cl(b, 0) > cl(b, 1) + avg(b, :equal, 1) &&
    cl(b, 0) <= fma(body(b, 1), oftype(body(b, 1), 0.5), cl(b, 1)) ? -100 : 0
