using AtomGraphs
using Test

@testset "AtomGraphs.jl" begin
    include("AtomGraph_tests.jl")
    include("graph_building_tests.jl")
end
