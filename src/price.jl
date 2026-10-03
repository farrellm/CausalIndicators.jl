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
