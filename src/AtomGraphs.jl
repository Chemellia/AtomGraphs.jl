module AtomGraphs

using Graphs
using SimpleWeightedGraphs
using LinearAlgebra
using Serialization
using Xtals
#rc[:paths][:crystals] = @__DIR__ # so that Xtals.jl knows where things are
using MolecularGraph

include("atomgraph.jl")
export AtomGraph, elements, visualize

include("graph_building.jl")
export inverse_square, exp_decay

end
