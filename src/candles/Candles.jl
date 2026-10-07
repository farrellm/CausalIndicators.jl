"""
    CausalIndicators.Candles

TA-Lib's 61 candlestick patterns (S7). Each is a plain summarizer over the
`open`, `high`, `low` and `close` columns that emits `Int`: 100 for a bullish
pattern, −100 for a bearish one, 0 otherwise, with 80 for the weaker forms of
`Engulfing`, `Harami` and `HaramiCross` and 200 for a Hikkake confirmation.
The names are kept out of the top level: write `using CausalIndicators.Candles`
or `Candles.Hammer()`. The thresholds the patterns compare against are a
[`CandleSettings`](@ref), passed as `settings`.
"""
module Candles

using CausalFrames
using CausalFrames: ColumnSpec, colname, fresh, fresh!
using ..CausalIndicators: CandleSettings, CandleSetting, CandleKernel, HikkakeState,
    stepbars!, candleclean, candlebars, op, hi, lo, cl, avg, body, upper, lower, color,
    white, black, bodytop, bodybot, bodygapup, bodygapdown, gapup, gapdown, cmin, cmax,
    barindicator, checkrange
import ..CausalIndicators: barkernel, barouttype, barstep!

export CandleSettings, CandleSetting

include("single.jl")
include("double.jl")
include("triple.jl")
include("multi.jl")

# P is the pattern's Julia name.
struct CandleSpec{P}
    settings::CandleSettings
    penetration::Float64
end

hikkakestate(::Val, ::Type) = nothing

function barkernel(s::CandleSpec{P}, ::Type{T}) where {P,T}
    names, nbars = candleshape(Val(P))
    return CandleKernel{P}(T, s.settings, s.penetration, candlelookback(Val(P), s.settings),
        nbars, names, hikkakestate(Val(P), T))
end
barouttype(::CandleSpec, ::Type) = Int

# A bar with a non-finite price or threshold among those the pattern reads
# matches nothing (TA-Lib's comparisons with NaN are all false).
@inline function barstep!(k::CandleKernel{P,T,A,L,Nothing}, o::T, h::T, l::T,
    c::T) where {P,T,A,L}
    stepbars!(k, o, h, l, c)
    k.n > k.lookback || return nothing
    return (candleclean(k) ? candle(Val(P), candlebars(k))::Int : 0,)
end

@inline function barstep!(k::CandleKernel{P,T,A,L,<:HikkakeState}, o::T, h::T, l::T,
    c::T) where {P,T,A,L}
    stepbars!(k, o, h, l, c)
    k.n > k.lookback - 3 || return nothing
    b = candlebars(k)
    v = hikkakestep!(k.hikkake, b, candleclean(k) && hikkakepattern(Val(P), b), c)
    k.n > k.lookback || return nothing
    return (v,)
end

const CANDLE_DOC = """
The pattern compares candle parts against the averages in `settings` (a
[`CandleSettings`](@ref), TA-Lib's defaults unless given). Its lookback is
TA-Lib's, which follows the settings' averaging periods, and the output is
`missing` for those bars. It is a plain summarizer (no `combine!`), so it
belongs under `addsummarycolumns`. Under `addrollingcolumns` each window
re-folds from a fresh state.

A bar with any input `missing` leaves the state unchanged and emits `missing`.
A bar with a non-finite price emits 0, as do the bars that read it back,
directly or through an average, until it is out of their reach: TA-Lib's
comparisons with NaN are false, though its running averages never recover.
"""

const PENETRATION_DOC = """
`penetration` is how far into the first candle's real body, as a fraction of
it, the last candle must close.
"""

# (Julia name, TA-Lib name, penetration default or nothing, description)
const CANDLES = (
    (:TwoCrows, "CDL2CROWS", nothing,
        "a long white candle, a black candle gapping up, and a black candle opening " *
        "within the second's body and closing within the first's: −100"),
    (:ThreeBlackCrows, "CDL3BLACKCROWS", nothing,
        "three declining black candles with very short lower shadows, each opening " *
        "within the previous body, after a white candle: −100"),
    (:ThreeInside, "CDL3INSIDE", nothing,
        "a harami (a long candle, then a short one inside its body) confirmed by a " *
        "third candle closing beyond the first's open: 100 up, −100 down"),
    (:ThreeLineStrike, "CDL3LINESTRIKE", nothing,
        "three same-colored candles stepping in one direction, struck by a fourth " *
        "of the opposite color that closes beyond the first's open: the sign of the " *
        "three"),
    (:ThreeOutside, "CDL3OUTSIDE", nothing,
        "an engulfing pair confirmed by a third candle closing further in its " *
        "direction: 100 up, −100 down"),
    (:ThreeStarsInTheSouth, "CDL3STARSINSOUTH", nothing,
        "three shrinking black candles, the first long with a long lower shadow and " *
        "the last a small marubozu inside the second's range: 100"),
    (:ThreeWhiteSoldiers, "CDL3WHITESOLDIERS", nothing,
        "three advancing white candles with very short upper shadows, each opening " *
        "within or near the previous body and none far shorter: 100"),
    (:AbandonedBaby, "CDLABANDONEDBABY", 0.3,
        "a long candle, a doji gapping away from it, and a candle gapping back the " *
        "other way and closing well into the first's body: 100 bullish, −100 bearish"),
    (:AdvanceBlock, "CDLADVANCEBLOCK", nothing,
        "three advancing white candles that weaken, through shrinking bodies or " *
        "growing upper shadows: −100"),
    (:BeltHold, "CDLBELTHOLD", nothing,
        "a long candle opening at its extreme (a very short lower shadow if white, " *
        "upper if black): 100 white, −100 black"),
    (:Breakaway, "CDLBREAKAWAY", nothing,
        "a long candle, a gap, three candles continuing the move, and a fifth of the " *
        "opposite color closing within the gap: the fifth candle's sign"),
    (:ClosingMarubozu, "CDLCLOSINGMARUBOZU", nothing,
        "a long candle closing at its extreme (a very short upper shadow if white, " *
        "lower if black): 100 white, −100 black"),
    (:ConcealingBabySwallow, "CDLCONCEALBABYSWALL", nothing,
        "two black marubozu, a black candle gapping down whose upper shadow reaches " *
        "into the second, and a black candle engulfing it, shadows included: 100"),
    (:Counterattack, "CDLCOUNTERATTACK", nothing,
        "two long candles of opposite colors closing at the same level: the second " *
        "candle's sign"),
    (:DarkCloudCover, "CDLDARKCLOUDCOVER", 0.5,
        "a long white candle and a black candle opening above its high and closing " *
        "well into its body: −100"),
    (:Doji, "CDLDOJI", nothing,
        "a candle whose real body is a doji's, at most a tenth of the average range by " *
        "default: 100"),
    (:DojiStar, "CDLDOJISTAR", nothing,
        "a long candle and a doji whose body gaps away from it: −100 after a white " *
        "candle, 100 after a black one"),
    (:DragonflyDoji, "CDLDRAGONFLYDOJI", nothing,
        "a doji with a very short upper shadow and a longer lower one: 100"),
    (:Engulfing, "CDLENGULFING", nothing,
        "a candle whose body engulfs the previous body of the opposite color: ±100, " *
        "or ±80 when one end of the bodies matches, signed by the second candle"),
    (:EveningDojiStar, "CDLEVENINGDOJISTAR", 0.3,
        "a long white candle, a doji gapping up, and a black candle closing well into " *
        "the first's body: −100"),
    (:EveningStar, "CDLEVENINGSTAR", 0.3,
        "a long white candle, a short candle gapping up, and a black candle closing " *
        "well into the first's body: −100"),
    (:GapSideSideWhite, "CDLGAPSIDESIDEWHITE", nothing,
        "two similar white candles side by side after a gap: 100 after an up gap, " *
        "−100 after a down gap"),
    (:GravestoneDoji, "CDLGRAVESTONEDOJI", nothing,
        "a doji with a very short lower shadow and a longer upper one: 100"),
    (:Hammer, "CDLHAMMER", nothing,
        "a small body with a long lower shadow and almost no upper shadow, at or near " *
        "the previous candle's low: 100"),
    (:HangingMan, "CDLHANGINGMAN", nothing,
        "a small body with a long lower shadow and almost no upper shadow, at or near " *
        "the previous candle's high: −100"),
    (:Harami, "CDLHARAMI", nothing,
        "a long candle and a short one whose body lies inside the first's: ±100, or " *
        "±80 when one end of the bodies matches, against the first candle's color"),
    (:HaramiCross, "CDLHARAMICROSS", nothing,
        "a long candle and a doji whose body lies inside the first's: ±100, or ±80 " *
        "when one end of the bodies matches, against the first candle's color"),
    (:HighWave, "CDLHIGHWAVE", nothing,
        "a small body with very long shadows on both sides: 100 white, −100 black"),
    (:Hikkake, "CDLHIKKAKE", nothing,
        "an inside bar followed by a breakout bar (lower high and low: 100, higher: " *
        "−100), and 200 or −200 if a close beyond the inside bar's high or low " *
        "confirms it within three bars"),
    (:HikkakeMod, "CDLHIKKAKEMOD", nothing,
        "Hikkake after two inside bars, with the second bar closing near its low " *
        "(bullish, 100) or high (bearish, −100), and 200 or −200 on a confirmation " *
        "within three bars"),
    (:HomingPigeon, "CDLHOMINGPIGEON", nothing,
        "a long black candle and a short black candle whose body lies inside it: 100"),
    (:IdenticalThreeCrows, "CDLIDENTICAL3CROWS", nothing,
        "three declining black candles with very short lower shadows, each opening at " *
        "the previous close: −100"),
    (:InNeck, "CDLINNECK", nothing,
        "a long black candle and a white candle opening below its low and closing at " *
        "or just above its close: −100"),
    (:InvertedHammer, "CDLINVERTEDHAMMER", nothing,
        "a small body gapping below the previous body, with a long upper shadow and " *
        "almost no lower one: 100"),
    (:Kicking, "CDLKICKING", nothing,
        "two marubozu of opposite colors with a gap between them: the second " *
        "candle's sign"),
    (:KickingByLength, "CDLKICKINGBYLENGTH", nothing,
        "two marubozu of opposite colors with a gap between them: the longer " *
        "candle's sign"),
    (:LadderBottom, "CDLLADDERBOTTOM", nothing,
        "three declining black candles, a black candle with an upper shadow, and a " *
        "white candle closing above its high: 100"),
    (:LongLeggedDoji, "CDLLONGLEGGEDDOJI", nothing,
        "a doji with a long shadow on at least one side: 100"),
    (:LongLine, "CDLLONGLINE", nothing,
        "a long body with short shadows: 100 white, −100 black"),
    (:Marubozu, "CDLMARUBOZU", nothing,
        "a long body with very short shadows: 100 white, −100 black"),
    (:MatchingLow, "CDLMATCHINGLOW", nothing,
        "two black candles closing at the same level: 100"),
    (:MatHold, "CDLMATHOLD", 0.5,
        "a long white candle, a small black candle gapping up, two more small " *
        "candles drifting down within the first's body, and a white candle closing " *
        "above them all: 100"),
    (:MorningDojiStar, "CDLMORNINGDOJISTAR", 0.3,
        "a long black candle, a doji gapping down, and a white candle closing well " *
        "into the first's body: 100"),
    (:MorningStar, "CDLMORNINGSTAR", 0.3,
        "a long black candle, a short candle gapping down, and a white candle closing " *
        "well into the first's body: 100"),
    (:OnNeck, "CDLONNECK", nothing,
        "a long black candle and a white candle opening below its low and closing at " *
        "its low: −100"),
    (:Piercing, "CDLPIERCING", nothing,
        "a long black candle and a long white candle opening below its low and " *
        "closing above its midpoint, but below its open: 100"),
    (:RickshawMan, "CDLRICKSHAWMAN", nothing,
        "a doji with two long shadows and its body near the middle of its range: 100"),
    (:RiseFallThreeMethods, "CDLRISEFALL3METHODS", nothing,
        "a long candle, three small ones of the opposite color drifting against it " *
        "within its range, and a long candle resuming the move to a new close: the " *
        "first candle's sign"),
    (:SeparatingLines, "CDLSEPARATINGLINES", nothing,
        "two candles of opposite colors opening at the same level, the second a long " *
        "belt hold: the second candle's sign"),
    (:ShootingStar, "CDLSHOOTINGSTAR", nothing,
        "a small body gapping above the previous body, with a long upper shadow and " *
        "almost no lower one: −100"),
    (:ShortLine, "CDLSHORTLINE", nothing,
        "a short body with short shadows: 100 white, −100 black"),
    (:SpinningTop, "CDLSPINNINGTOP", nothing,
        "a small body with shadows longer than it on both sides: 100 white, " *
        "−100 black"),
    (:StalledPattern, "CDLSTALLEDPATTERN", nothing,
        "two long advancing white candles and a small one riding on the second's " *
        "shoulder: −100"),
    (:StickSandwich, "CDLSTICKSANDWICH", nothing,
        "a black candle, a white candle trading above its close, and a black candle " *
        "closing at the first's close: 100"),
    (:Takuri, "CDLTAKURI", nothing,
        "a dragonfly doji with a very long lower shadow: 100"),
    (:TasukiGap, "CDLTASUKIGAP", nothing,
        "a gap, a candle continuing it, and a candle of the opposite color and " *
        "similar size closing inside the gap's near edge: the second candle's sign"),
    (:Thrusting, "CDLTHRUSTING", nothing,
        "a long black candle and a white candle opening below its low and closing " *
        "into its body, but not past its midpoint: −100"),
    (:Tristar, "CDLTRISTAR", nothing,
        "three doji, the middle one gapping away: −100 after an up gap, 100 after a " *
        "down gap"),
    (:UniqueThreeRiver, "CDLUNIQUE3RIVER", nothing,
        "a long black candle, a black harami with a lower low, and a small white " *
        "candle opening above that low: 100"),
    (:UpsideGapTwoCrows, "CDLUPSIDEGAP2CROWS", nothing,
        "a long white candle, a small black candle gapping up, and a black candle " *
        "engulfing it but closing above the first's close: −100"),
    (:XSideGapThreeMethods, "CDLXSIDEGAP3METHODS", nothing,
        "two same-colored candles with a gap between their bodies, and a third of " *
        "the opposite color opening in the second body and closing in the first: the " *
        "first candle's sign"),
)

candleindicator(::Val{P}, settings, penetration, name, open, high, low, close) where {P} =
    barindicator(CandleSpec{P}(settings, penetration), (name,), open, high, low, close)

for (J, ta, pen, desc) in CANDLES
    yaml = lowercase(ta)
    out = QuoteNode(Symbol(yaml))
    P = QuoteNode(J)
    lb = candlelookback(Val(J), CandleSettings())
    penkw = pen === nothing ? "" : "penetration = $pen, "
    sig =
        "$J(; open = :open, high = :high, low = :low, close = :close, $(penkw)" *
        "settings = CandleSettings(), name = :$yaml)"
    doc = """
        $sig

    TA-Lib's `$ta` in `:$yaml`: $desc. The lookback is $lb bars at the default
    settings.
    $(pen === nothing ? "" : "\n" * PENETRATION_DOC)
    $CANDLE_DOC
    TA-Lib: `ta_codegen/input/$yaml/$yaml.yaml`, `$yaml.md`.
    """
    if pen === nothing
        @eval begin
            @doc $doc function $J(; open::ColumnSpec = :open, high::ColumnSpec = :high,
                low::ColumnSpec = :low, close::ColumnSpec = :close,
                settings::CandleSettings = CandleSettings(), name::Symbol = $out)
                return candleindicator(Val($P), settings, 0.0, name, open, high, low, close)
            end
            export $J
        end
    else
        @eval begin
            @doc $doc function $J(; open::ColumnSpec = :open, high::ColumnSpec = :high,
                low::ColumnSpec = :low, close::ColumnSpec = :close,
                penetration::Real = $pen, settings::CandleSettings = CandleSettings(),
                name::Symbol = $out)
                checkrange($(string(J)), "penetration", penetration, 0, Inf)
                return candleindicator(Val($P), settings, Float64(penetration), name, open,
                    high, low, close)
            end
            export $J
        end
    end
end

end
