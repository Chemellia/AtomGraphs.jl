module AtomGraphs

using Graphs
using SimpleWeightedGraphs
using LinearAlgebra
using GraphPlot
using Colors
using PyCall
using Serialization
using Xtals
#rc[:paths][:crystals] = @__DIR__ # so that Xtals.jl knows where things are
using MolecularGraph

include("atomgraph.jl")
export AtomGraph

include("graph_building.jl")
export build_graph
export inverse_square, exp_decay

end
