# The four- and five-bar patterns, and the Hikkake family, whose pattern state
# carries a confirmation across bars.

# ta_CDL3BLACKCROWS.c: bar 3 is the white candle before the crows.
candleshape(::Val{:ThreeBlackCrows}) = ((:shadowveryshort,), 4)
candlelookback(::Val{:ThreeBlackCrows}, s) = s.shadowveryshort.avgperiod + 3
@inline candle(::Val{:ThreeBlackCrows}, b) =
    white(b, 3) && black(b, 2) && black(b, 1) && black(b, 0) && op(b, 1) < op(b, 2) &&
    op(b, 1) > cl(b, 2) && op(b, 0) < op(b, 1) && op(b, 0) > cl(b, 1) &&
    hi(b, 3) > cl(b, 2) && cl(b, 2) > cl(b, 1) && cl(b, 1) > cl(b, 0) &&
    lower(b, 2) < avg(b, :shadowveryshort, 2) &&
    lower(b, 1) < avg(b, :shadowveryshort, 1) &&
    lower(b, 0) < avg(b, :shadowveryshort, 0) ? -100 : 0

# ta_CDL3LINESTRIKE.c
candleshape(::Val{:ThreeLineStrike}) = ((:near,), 4)
candlelookback(::Val{:ThreeLineStrike}, s) = s.near.avgperiod + 3
@inline candle(::Val{:ThreeLineStrike}, b) =
    color(b, 3) == color(b, 2) && color(b, 2) == color(b, 1) &&
    color(b, 0) == -color(b, 1) &&
    op(b, 2) >= cmin(op(b, 3), cl(b, 3)) - avg(b, :near, 3) &&
    op(b, 2) <= cmax(op(b, 3), cl(b, 3)) + avg(b, :near, 3) &&
    op(b, 1) >= cmin(op(b, 2), cl(b, 2)) - avg(b, :near, 2) &&
    op(b, 1) <= cmax(op(b, 2), cl(b, 2)) + avg(b, :near, 2) &&
    (
        (
            white(b, 1) && cl(b, 1) > cl(b, 2) && cl(b, 2) > cl(b, 3) &&
            op(b, 0) > cl(b, 1) &&
            cl(b, 0) < op(b, 3)
        ) ||
        (
            black(b, 1) && cl(b, 1) < cl(b, 2) && cl(b, 2) < cl(b, 3) &&
            op(b, 0) < cl(b, 1) &&
            cl(b, 0) > op(b, 3)
        )
    ) ? color(b, 1) * 100 : 0

# ta_CDLCONCEALBABYSWALL.c
candleshape(::Val{:ConcealingBabySwallow}) = ((:shadowveryshort,), 4)
candlelookback(::Val{:ConcealingBabySwallow}, s) = s.shadowveryshort.avgperiod + 3
@inline candle(::Val{:ConcealingBabySwallow}, b) =
    black(b, 3) && black(b, 2) && black(b, 1) && black(b, 0) &&
    lower(b, 3) < avg(b, :shadowveryshort, 3) &&
    upper(b, 3) < avg(b, :shadowveryshort, 3) &&
    lower(b, 2) < avg(b, :shadowveryshort, 2) &&
    upper(b, 2) < avg(b, :shadowveryshort, 2) &&
    bodygapdown(b, 1, 2) && upper(b, 1) > avg(b, :shadowveryshort, 1) &&
    hi(b, 1) > cl(b, 2) && hi(b, 0) > hi(b, 1) && lo(b, 0) < lo(b, 1) ? 100 : 0

# ta_CDLBREAKAWAY.c
candleshape(::Val{:Breakaway}) = ((:bodylong,), 5)
candlelookback(::Val{:Breakaway}, s) = s.bodylong.avgperiod + 4
@inline candle(::Val{:Breakaway}, b) =
    color(b, 4) == color(b, 3) && color(b, 3) == color(b, 1) &&
    color(b, 1) == -color(b, 0) && body(b, 4) > avg(b, :bodylong, 4) &&
    (
        (
            black(b, 4) && bodygapdown(b, 3, 4) && hi(b, 2) < hi(b, 3) &&
            lo(b, 2) < lo(b, 3) &&
            hi(b, 1) < hi(b, 2) && lo(b, 1) < lo(b, 2) && cl(b, 0) > op(b, 3) &&
            cl(b, 0) < cl(b, 4)
        ) ||
        (
            white(b, 4) && bodygapup(b, 3, 4) && hi(b, 2) > hi(b, 3) &&
            lo(b, 2) > lo(b, 3) &&
            hi(b, 1) > hi(b, 2) && lo(b, 1) > lo(b, 2) && cl(b, 0) < op(b, 3) &&
            cl(b, 0) > cl(b, 4)
        )
    ) ? color(b, 0) * 100 : 0

# ta_CDLLADDERBOTTOM.c
candleshape(::Val{:LadderBottom}) = ((:shadowveryshort,), 5)
candlelookback(::Val{:LadderBottom}, s) = s.shadowveryshort.avgperiod + 4
@inline candle(::Val{:LadderBottom}, b) =
    black(b, 4) && black(b, 3) && black(b, 2) && op(b, 4) > op(b, 3) &&
    op(b, 3) > op(b, 2) && cl(b, 4) > cl(b, 3) && cl(b, 3) > cl(b, 2) && black(b, 1) &&
    upper(b, 1) > avg(b, :shadowveryshort, 1) && white(b, 0) && op(b, 0) > op(b, 1) &&
    cl(b, 0) > hi(b, 1) ? 100 : 0

# ta_CDLMATHOLD.c
candleshape(::Val{:MatHold}) = ((:bodyshort, :bodylong), 5)
candlelookback(::Val{:MatHold}, s) = max(s.bodyshort.avgperiod, s.bodylong.avgperiod) + 4
@inline function candle(::Val{:MatHold}, b)
    floor_ = cl(b, 4) - body(b, 4) * b.penetration
    return white(b, 4) && black(b, 3) && white(b, 0) && bodygapup(b, 3, 4) &&
           cmin(op(b, 2), cl(b, 2)) < cl(b, 4) && cmin(op(b, 1), cl(b, 1)) < cl(b, 4) &&
           cmin(op(b, 2), cl(b, 2)) > floor_ && cmin(op(b, 1), cl(b, 1)) > floor_ &&
           cmax(cl(b, 2), op(b, 2)) < op(b, 3) &&
           cmax(cl(b, 1), op(b, 1)) < cmax(cl(b, 2), op(b, 2)) && op(b, 0) > cl(b, 1) &&
           cl(b, 0) > cmax(cmax(hi(b, 3), hi(b, 2)), hi(b, 1)) &&
           body(b, 4) > avg(b, :bodylong, 4) && body(b, 3) < avg(b, :bodyshort, 3) &&
           body(b, 2) < avg(b, :bodyshort, 2) &&
           body(b, 1) < avg(b, :bodyshort, 1) ? 100 : 0
end

# ta_CDLRISEFALL3METHODS.c: the first candle's color `d` orients the
# comparisons.
candleshape(::Val{:RiseFallThreeMethods}) = ((:bodyshort, :bodylong), 5)
candlelookback(::Val{:RiseFallThreeMethods}, s) =
    max(s.bodyshort.avgperiod, s.bodylong.avgperiod) + 4
@inline function candle(::Val{:RiseFallThreeMethods}, b)
    d = color(b, 4)
    return color(b, 4) == -color(b, 3) && color(b, 3) == color(b, 2) &&
           color(b, 2) == color(b, 1) && color(b, 1) == -color(b, 0) &&
           cmin(op(b, 3), cl(b, 3)) < hi(b, 4) && cmax(op(b, 3), cl(b, 3)) > lo(b, 4) &&
           cmin(op(b, 2), cl(b, 2)) < hi(b, 4) && cmax(op(b, 2), cl(b, 2)) > lo(b, 4) &&
           cmin(op(b, 1), cl(b, 1)) < hi(b, 4) && cmax(op(b, 1), cl(b, 1)) > lo(b, 4) &&
           cl(b, 2) * d < cl(b, 3) * d && cl(b, 1) * d < cl(b, 2) * d &&
           op(b, 0) * d > cl(b, 1) * d && cl(b, 0) * d > cl(b, 4) * d &&
           body(b, 4) > avg(b, :bodylong, 4) && body(b, 3) < avg(b, :bodyshort, 3) &&
           body(b, 2) < avg(b, :bodyshort, 2) && body(b, 1) < avg(b, :bodyshort, 1) &&
           body(b, 0) > avg(b, :bodylong, 0) ? 100 * d : 0
end

# ta_CDLHIKKAKE.c and ta_CDLHIKKAKEMOD.c. A pattern bar emits ±100 and arms a
# confirmation for the next three bars: a close beyond the high (low) the
# pattern saved emits ±200. A new pattern on a confirmation bar wins. The state
# steps from bar `lookback − 3`, where TA-Lib starts it.
candleshape(::Val{:Hikkake}) = ((), 3)
candlelookback(::Val{:Hikkake}, s) = 5
hikkakestate(::Val{:Hikkake}, ::Type{T}) where {T} = HikkakeState{T}()
@inline hikkakepattern(::Val{:Hikkake}, b) =
    hi(b, 1) < hi(b, 2) && lo(b, 1) > lo(b, 2) &&
    (
        (hi(b, 0) < hi(b, 1) && lo(b, 0) < lo(b, 1)) ||
        (hi(b, 0) > hi(b, 1) && lo(b, 0) > lo(b, 1))
    )

# The modified Hikkake also wants an earlier inside bar, and the second bar's
# close near its low (bullish) or high (bearish).
candleshape(::Val{:HikkakeMod}) = ((:near,), 4)
candlelookback(::Val{:HikkakeMod}, s) = max(1, s.near.avgperiod) + 5
hikkakestate(::Val{:HikkakeMod}, ::Type{T}) where {T} = HikkakeState{T}()
@inline hikkakepattern(::Val{:HikkakeMod}, b) =
    hi(b, 2) < hi(b, 3) && lo(b, 2) > lo(b, 3) && hi(b, 1) < hi(b, 2) &&
    lo(b, 1) > lo(b, 2) &&
    (
        (
            hi(b, 0) < hi(b, 1) && lo(b, 0) < lo(b, 1) &&
            cl(b, 2) <= lo(b, 2) + avg(b, :near, 2)
        ) ||
        (
            hi(b, 0) > hi(b, 1) && lo(b, 0) > lo(b, 1) &&
            cl(b, 2) >= hi(b, 2) - avg(b, :near, 2)
        )
    )

# One bar of the Hikkake state, `c` the bar's own close (a NaN close confirms
# nothing).
@inline function hikkakestep!(st::HikkakeState, b, pattern::Bool, c)
    if pattern
        st.result = 100 * (hi(b, 0) < hi(b, 1) ? 1 : -1)
        st.high, st.low = hi(b, 1), lo(b, 1)
        st.count = 4
        out = st.result
    elseif st.count > 0 &&
           ((st.result > 0 && c > st.high) || (st.result < 0 && c < st.low))
        out = st.result + 100 * (st.result > 0 ? 1 : -1)
        st.count = 0
    else
        out = 0
    end
    st.count > 0 && (st.count -= 1)
    return out
end
