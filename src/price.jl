# TA-Lib's price transforms: bar-local combinations of one bar's prices. Each is
# a dependent over CausalFrames' `Last`, so it is bar-local under
# `addsummarycolumns` and under any window, with no state of its own.

avgprice(o, h, l, c) = (o + h + l + c) / 4
medprice(h, l) = (h + l) / 2
typprice(h, l, c) = (h + l + c) / 3
wclprice(h, l, c) = (h + l + 2c) / 4

lastname(c) = Symbol(c, :_last)

"""
    AvgPrice(; open = :open, high = :high, low = :low, close = :close) -> Summarizer

TA-Lib's `AVGPRICE`, `(open + high + low + close) / 4`, in `:avgprice`. It is a
dependent over `Last`, and it is bar-local under any window, with lookback 0.

TA-Lib: `ta_codegen/input/avgprice/avgprice.yaml`, `avgprice.md`.
"""
struct AvgPrice{O,H,L,C} <: GroupSummarizer end
AvgPrice(; open::ColumnSpec = :open, high::ColumnSpec = :high, low::ColumnSpec = :low,
    close::ColumnSpec = :close) =
    withterms(AvgPrice{colname(open),colname(high),colname(low),colname(close)}(), open,
        high, low, close)

CausalFrames.dependencies(::AvgPrice{O,H,L,C}) where {O,H,L,C} =
    (Last(O), Last(H), Last(L), Last(C))
CausalFrames.emptyvalue(::AvgPrice) = (; avgprice = missing)
CausalFrames.fresh(::AvgPrice{O,H,L,C}, ::NamedTuple) where {O,H,L,C} =
    derivedvalue(:avgprice, map(lastname, (O, H, L, C)), avgprice)

"""
    MedPrice(; high = :high, low = :low) -> Summarizer

TA-Lib's `MEDPRICE`, `(high + low) / 2`, in `:medprice`. It is a dependent
over `Last`, and it is bar-local under any window, with lookback 0.

TA-Lib: `ta_codegen/input/medprice/medprice.yaml`, `medprice.md`.
"""
struct MedPrice{H,L} <: GroupSummarizer end
MedPrice(; high::ColumnSpec = :high, low::ColumnSpec = :low) =
    withterms(MedPrice{colname(high),colname(low)}(), high, low)

CausalFrames.dependencies(::MedPrice{H,L}) where {H,L} = (Last(H), Last(L))
CausalFrames.emptyvalue(::MedPrice) = (; medprice = missing)
CausalFrames.fresh(::MedPrice{H,L}, ::NamedTuple) where {H,L} =
    derivedvalue(:medprice, map(lastname, (H, L)), medprice)

"""
    TypPrice(; high = :high, low = :low, close = :close) -> Summarizer

TA-Lib's `TYPPRICE`, `(high + low + close) / 3`, in `:typprice`. It is a
dependent over `Last`, and it is bar-local under any window, with lookback 0.

TA-Lib: `ta_codegen/input/typprice/typprice.yaml`, `typprice.md`.
"""
struct TypPrice{H,L,C} <: GroupSummarizer end
TypPrice(; high::ColumnSpec = :high, low::ColumnSpec = :low, close::ColumnSpec = :close) =
    withterms(TypPrice{colname(high),colname(low),colname(close)}(), high, low, close)

CausalFrames.dependencies(::TypPrice{H,L,C}) where {H,L,C} = (Last(H), Last(L), Last(C))
CausalFrames.emptyvalue(::TypPrice) = (; typprice = missing)
CausalFrames.fresh(::TypPrice{H,L,C}, ::NamedTuple) where {H,L,C} =
    derivedvalue(:typprice, map(lastname, (H, L, C)), typprice)

"""
    WclPrice(; high = :high, low = :low, close = :close) -> Summarizer

TA-Lib's `WCLPRICE`, the weighted close `(high + low + 2·close) / 4`, in
`:wclprice`. It is a dependent over `Last`, and it is bar-local under any
window, with lookback 0.

TA-Lib: `ta_codegen/input/wclprice/wclprice.yaml`, `wclprice.md`.
"""
struct WclPrice{H,L,C} <: GroupSummarizer end
WclPrice(; high::ColumnSpec = :high, low::ColumnSpec = :low, close::ColumnSpec = :close) =
    withterms(WclPrice{colname(high),colname(low),colname(close)}(), high, low, close)

CausalFrames.dependencies(::WclPrice{H,L,C}) where {H,L,C} = (Last(H), Last(L), Last(C))
CausalFrames.emptyvalue(::WclPrice) = (; wclprice = missing)
CausalFrames.fresh(::WclPrice{H,L,C}, ::NamedTuple) where {H,L,C} =
    derivedvalue(:wclprice, map(lastname, (H, L, C)), wclprice)

# ---------------------------------------------------------------------------
# Heikin-Ashi (S5)

struct HASpec
    unstable::Int
end

mutable struct HAKernel{T}
    const unstable::Int
    n::Int
    open::T
    close::T
end

barkernel(s::HASpec, ::Type{T}) where {T} = HAKernel{T}(s.unstable, 0, zero(T), zero(T))
CausalFrames.fresh(k::HAKernel{T}) where {T} = HAKernel{T}(k.unstable, 0, zero(T), zero(T))
CausalFrames.fresh!(k::HAKernel{T}) where {T} =
    (k.n = 0; k.open = zero(T); k.close = zero(T); k)

@inline function barstep!(k::HAKernel{T}, o::T, h::T, l::T, c::T) where {T}
    # The open moves from the previous candle before the close is replaced
    # (ta_HA.c); the first candle opens at the midpoint of its own open and close.
    k.open = (k.n += 1) == 1 ? (o + c) / 2 : (k.open + k.close) / 2
    k.close = (((o + h) + l) + c) / 4
    k.n > k.unstable || return nothing
    a, b = k.open, k.close
    # Plain comparisons, as ta_HA.c spells the extremes.
    hi = h
    a > hi && (hi = a)
    b > hi && (hi = b)
    lo = l
    a < lo && (lo = a)
    b < lo && (lo = b)
    return (a, hi, lo, b)
end

"""
    HeikinAshi(; open = :open, high = :high, low = :low, close = :close, unstable = 0,
               name = :ha)

TA-Lib's `HA`, Heikin-Ashi candles, in `:ha_haopen`, `:ha_hahigh`, `:ha_halow`
and `:ha_haclose`. The close is the bar's mean price `(((o + h) + l) + c)/4`,
the open the midpoint of the previous candle's open and close (of the bar's own
open and close for the first candle), and the high and low widen the bar's to
contain them. `unstable` is TA-Lib's unstable period for HA: it delays the
first output without changing the values. The candles are recursive, so they
are anchored at the first bar seen, and the seed's weight halves each bar.

$PLAIN_DOC
A bar with any input `missing` leaves the state unchanged and emits `missing`.

TA-Lib: `ta_codegen/input/ha/ha.yaml`, `ha.md`.
"""
HeikinAshi(; open::ColumnSpec = :open, high::ColumnSpec = :high, low::ColumnSpec = :low,
    close::ColumnSpec = :close, unstable::Integer = 0, name::Symbol = :ha) =
    barindicator(HASpec(checkunstable(unstable)),
        outnames(nothing, name, (:haopen, :hahigh, :halow, :haclose)), open, high, low,
        close)
