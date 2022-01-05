using AtomGraphs
using Documenter

DocMeta.setdocmeta!(AtomGraphs, :DocTestSetup, :(using AtomGraphs); recursive=true)

makedocs(;
    modules=[AtomGraphs],
    authors="Rachel Kurchin <rkurchin@cmu.edu> and contributors",
    repo="https://github.com/rkurchin/AtomGraphs.jl/blob/{commit}{path}#{line}",
    sitename="AtomGraphs.jl",
    format=Documenter.HTML(;
        prettyurls=get(ENV, "CI", "false") == "true",
        canonical="https://rkurchin.github.io/AtomGraphs.jl",
        assets=String[],
    ),
    pages=[
        "Home" => "index.md",
    ],
)

deploydocs(;
    repo="github.com/rkurchin/AtomGraphs.jl",
    devbranch="main",
)
