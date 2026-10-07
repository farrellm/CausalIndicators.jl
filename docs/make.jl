using CausalFrames
using CausalIndicators
using Documenter

DocMeta.setdocmeta!(CausalIndicators, :DocTestSetup,
    :(using CausalFrames, CausalIndicators);
    recursive = true)

const GITHUB = "https://github.com/farrellm/CausalIndicators.jl/blob/master"

# The home page is the README, generated here so there is no second copy to
# drift. `docs/src/index.md` is generated and gitignored; edit README.md.
#
# Three rewrites separate the GitHub audience from the docs site: the title
# gains the .jl, the badges (GitHub furniture) go, and links to repo files
# (which would 404 on the site) point at GitHub. Examples written as `julia`
# blocks with a `# output` section become one doctest session, sharing their
# variables in order, as GitHub renders a `jldoctest` block as plain text.
function readme_as_index(readme, index)
    text = read(readme, String)
    text = replace(text, r"^# CausalIndicators\n" => "# CausalIndicators.jl\n")
    text = replace(text, r"^\[!\[[^\n]*\n"m => "")
    text = replace(text, r"\n{3,}" => "\n\n")   # the blank run the badges left
    for file in ("DESIGN.md", "THIRD_PARTY_NOTICES.md")
        text = replace(text, "[$file]($file)" => "[$file]($GITHUB/$file)")
    end
    text = replace(text,
        r"```julia\n((?:(?!```)[\s\S])*?\n# output\n[\s\S]*?)```" =>
            s"```jldoctest readme\n\1```")
    return write(index, text)
end

readme_as_index(joinpath(@__DIR__, "..", "README.md"),
    joinpath(@__DIR__, "src", "index.md"))

makedocs(;
    modules = [CausalIndicators, CausalIndicators.Candles],
    authors = "Matthew Farrell",
    sitename = "CausalIndicators.jl",
    checkdocs = :exports,
    format = Documenter.HTML(;
        canonical = "https://farrellm.github.io/CausalIndicators.jl",
        edit_link = "master",
        assets = String[],
    ),
    pages = [
        "Home" => "index.md",
        "API" => [
            "Overview" => "api/index.md",
            "Overlap studies" => "api/overlap.md",
            "Price transforms" => "api/price.md",
            "Momentum" => "api/momentum.md",
            "Volatility" => "api/volatility.md",
            "Statistics" => "api/statistics.md",
            "Volume" => "api/volume.md",
            "Cycle indicators" => "api/cycle.md",
            "Candlestick patterns" => "api/candles.md",
        ],
    ],
)

deploydocs(;
    repo = "github.com/farrellm/CausalIndicators.jl",
    devbranch = "master",
)
