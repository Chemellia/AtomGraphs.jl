using Test
using Xtals
using AtomGraphs: build_graph
using AtomsBase
using Unitful

@testset "graph-building" begin
    path1 = abspath(@__DIR__, "strucs", "mp-195.cif")
    adj, els = build_graph(path1; use_voronoi = true)
    wm_true = [0.0 1.0 1.0 1.0; 1.0 0.0 1.0 1.0; 1.0 1.0 0.0 1.0; 1.0 1.0 1.0 0.0]
    els_true = ["Ho", "Pt", "Pt", "Pt"]

    @test adj == wm_true
    @test els == els_true

    adj, els = build_graph(path1; use_voronoi = false)
    @test adj == wm_true
    @test els == els_true

    # test that we get the same results building from a Crystal object
    c = Crystal(path1)
    adjc, elsc = build_graph(c)
    @test adjc == wm_true
    @test elsc == els_true

    # test that we get the same results building from an AtomsBase System
    # I'm planning on making a PR to AtomsBase that will make a lot of the setup machinations here unnecessary...
    els = element.(c.atoms.species)
    symbols = Symbol.(getproperty.(els, :symbol))
    masses = getproperty.(els, :atomic_mass)
    numbers = getproperty.(els, :number)

    box = c.box.f_to_c * u"Å"
    a₁ = box[:, 1]
    a₂ = box[:, 2]
    a₃ = box[:, 3]

    coords = Cart(c.atoms.coords, c.box).x * u"Å"
    coords = [coords[:, i] for i in 1:length(els)]

    bcs = [Periodic(), Periodic(), Periodic()]
    sys = FastSystem([a₁,a₂,a₃], bcs, coords, symbols, numbers, masses)

    adjs, elss = build_graph(sys)
    @test adjs == wm_true
    @test elss == els_true
end
