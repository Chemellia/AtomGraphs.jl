using PythonCall
using AtomsBase
using AtomsIO
using Unitful
using NearestNeighbors
include("utils.jl")

# options for decay of bond weights with distance...
# user can of course write their own as well
inverse_square(x) = x^-2.0
exp_decay(x) = exp(-x)

"""
Build graph from a file storing a crystal structure (will be read in using AtomsIO, which in turn calls ASE). Returns the weight matrix and elements used for constructing an `AtomGraph`.

# Arguments
## Required Arguments
- `file_path::String`: Path to ASE-readable file containing a molecule/crystal structure

## Keyword Arguments
- `use_voronoi::bool`: if true, use Voronoi method for neighbor lists, if false use cutoff method

    (The rest of these parameters are only used if `use_voronoi==false`)

- `cutoff_radius::Real=8.0`: cutoff radius for atoms to be considered neighbors (in angstroms)
- `max_num_nbr::Integer=12`: maximum number of neighbors to include (even if more fall within cutoff radius)
- `dist_decay_func::Function=inverse_square`: function to determine falloff of graph edge weights with neighbor distance
"""
function build_graph(
    file_path::String;
    use_voronoi::Bool = false,
    cutoff_radius::Real = 8.0,
    max_num_nbr::Integer = 12,
    dist_decay_func::Function = inverse_square,
)
    c = load_system(abspath(file_path))
    atom_ids = String.(atomic_symbol(c))

    if use_voronoi
        @info "Note that building neighbor lists and edge weights via the Voronoi method requires the assumption of periodic boundaries. If you are building a graph for a molecule, you probably do not want this..."
        s = pyimport("pymatgen.core.structure")
        struc = s.Structure.from_file(file_path)
        weight_mat = weights_voronoi(struc)
        return weight_mat, atom_ids, struc
    else
        build_graph(
            c;
            cutoff_radius = cutoff_radius,
            max_num_nbr = max_num_nbr,
            dist_decay_func = dist_decay_func,
        )
    end

end

atomic_symbol(c::Crystal) = c.atoms.species

"""
Build graph from an object. Currently only supports the "cutoff" method of neighbor list/weight calculation (not Voronoi).
This dispatch exists to support autodiff of graph-building.

# Arguments
## Required Arguments
- `sys`: either an Xtals Crystal object or an AtomsBase AbstractSystem representing the atomic geometry from which to build a graph

## Keyword Arguments
- `cutoff_radius::Real=8.0`: cutoff radius for atoms to be considered neighbors (in angstroms)
- `max_num_nbr::Integer=12`: maximum number of neighbors to include (even if more fall within cutoff radius)
- `dist_decay_func::Function=inverse_square`: function to determine falloff of graph edge weights with neighbor distance
"""
function build_graph(
    sys;
    cutoff_radius::Real = 8.0,
    max_num_nbr::Integer = 12,
    dist_decay_func::Function = inverse_square,
)

    is, js, dists = neighbor_list(sys; cutoff_radius = cutoff_radius)
    weight_mat = weights_cutoff(
        is,
        js,
        dists;
        max_num_nbr = max_num_nbr,
        dist_decay_func = dist_decay_func,
    )
    return weight_mat, String.(atomic_symbol(sys)), sys
end

"""
Build graph using neighbor number cutoff method adapted from original CGCNN.

!!! note
    `max_num_nbr` is a "soft" max, in that if there are more of the same distance as the last, all of those will be added.
"""
function weights_cutoff(is, js, dists; max_num_nbr = 12, dist_decay_func = inverse_square)
    # sort by distance
    ijd = sort([t for t in zip(is, js, dists)], by = t -> t[3])

    # initialize neighbor counts
    num_atoms = maximum(is)
    local nb_counts = Dict(i => 0 for i = 1:num_atoms)
    local longest_dists = Dict(i => 0.0 for i = 1:num_atoms)

    # iterate over list of tuples to build edge weights...
    # note that neighbor list double counts so we only have to increment one counter per pair
    weight_mat = zeros(Float32, num_atoms, num_atoms)
    for (i, j, d) in ijd
        # if we're under the max OR if it's at the same distance as the previous one
        if nb_counts[i] < max_num_nbr || isapprox(longest_dists[i], d)
            weight_mat[i, j] += dist_decay_func(d)
            longest_dists[i] = d
            nb_counts[i] += 1
        end
    end

    # average across diagonal, just in case
    weight_mat = 0.5 .* (weight_mat .+ weight_mat')

    # normalize weights
    weight_mat = weight_mat ./ maximum(weight_mat)
end

"""
Build graph using neighbors from faces of Voronoi polyedra and weights from areas. Based on the approach from https://github.com/ulissigroup/uncertainty_benchmarking/blob/aabb407807e35b5fd6ad06b14b440609ae09e6ef/BNN/data_pyro.py#L268
"""
function weights_voronoi(struc)
    num_atoms = length(struc)
    sa = pyimport("pymatgen.analysis.structure_analyzer")
    vc = sa.VoronoiConnectivity(struc)
    conn = vc.connectivity_array
    weight_mat = zeros(Float32, num_atoms, num_atoms)
    # loop over central atoms
    for atom_ind in range(0, stop = length(conn) - 1)
        # loop over neighbor atoms
        for nb_ind in range(0, stop = length(conn[0]) - 1)
            # loop over each possible PBC image for chosen image
            for image_ind in range(0, stop = length(conn[0][0]) - 1)
                # only add as neighbor if atom is not current center one AND there is connectivity to image
                if (atom_ind != image_ind) && (pyconvert(Float64, (conn[atom_ind][nb_ind][image_ind])) != 0)
                    conn_matrix = pyconvert(Matrix, conn[atom_ind])
                    weight_mat[atom_ind + 1, nb_ind + 1] +=
                        pyconvert(Float32, conn[atom_ind][nb_ind][image_ind]) / maximum(conn_matrix)
                end
            end
        end
    end

    # average across diagonal (because neighborness isn't strictly symmetric in the way we're defining it here)
    weight_mat = 0.5 .* (weight_mat .+ weight_mat')

    # normalize weights
    weight_mat = weight_mat ./ maximum(weight_mat)
end

# helper functions for dispatching neighbor_list on different types, see below
function nl_prep(crys::Crystal)
    min_celldim = min(crys.box.a, crys.box.b, crys.box.c)
    n_atoms = crys.atoms.n
    supercell = replicate(crys, (3, 3, 3))
    return min_celldim, n_atoms, Cart(supercell.atoms.coords, supercell.box).x
end

function nl_prep(sys::AbstractSystem)
    min_celldim = minimum([sqrt(sum(v.^2)) for v in ustrip.(bounding_box(sys))])
    n_atoms = length(sys)
    _, _, sc_pos = build_supercell(sys, (3,3,3))
    sc_pos = hcat(ustrip.(sc_pos)...)
    return min_celldim, n_atoms, sc_pos
end

"""
Find all lists of pairs of atoms in sys (which can be an Xtals.Crystal or any AtomsBase AbstractSystem object) that are within a distance of `cutoff_radius` of each other, respecting periodic boundary conditions.

Returns as is, js, dists to be compatible with ASE's output format for the analogous function.
"""
function neighbor_list(sys; cutoff_radius::Real = 8.0)
    # we make a 3 x 3 x 3 supercell and find indices of "middle" atoms
    # as well as index mapping from outer -> inner
    min_celldim, n_atoms, sc_pos = nl_prep(sys)

    if cutoff_radius >= min_celldim
        @warn "Your cutoff radius is quite large relative to the size of your unit cell. This may cause issues with neighbor list generation, and will definitely cause a very dense graph. To avoid issues, I'm setting it to be approximately equal to the smallest unit cell dimension."
        cutoff_radius = 0.99 * min_celldim
    end

    # todo: try BallTree, also perhaps other leafsize values
    # also, the whole supercell thing could probably be avoided (and this function sped up substantially) by doing this using something like:
    # ptree = BruteTree(hcat(ustrip.(position(s))...), PeriodicEuclidean([1,1,1]))
    # but I don't have time to carefully test that right now and I know the supercell thing should work
    tree = BruteTree(sc_pos)
    is_raw = 13*n_atoms+1:14*n_atoms
    js_raw = inrange(tree, sc_pos[:, is_raw], cutoff_radius)

    index_map(i) = (i - 1) % n_atoms + 1 # I suddenly understand why some people dislike 1-based indexing

    # this looks horrifying but it does do the right thing...
    #ijraw_pairs = [p for p in Iterators.flatten([Iterators.product([p for p in zip(is_raw, js_raw)][n]...) for n in 1:4]) if p[1]!=p[2]]
    split1 = map(zip(is_raw, js_raw)) do x
        return [
            p for p in [(x[1], [j for j in js if j != x[1]]...) for js in x[2]] if
            length(p) == 2
        ]
    end
    ijraw_pairs = [(split1...)...]
    get_pairdist((i,j)) = sqrt(sum((sc_pos[:, i] .- sc_pos[:, j]).^2))
    dists = get_pairdist.(ijraw_pairs)
    is = index_map.([t[1] for t in ijraw_pairs])
    js = index_map.([t[2] for t in ijraw_pairs])
    return is, js, dists
end

# TODO: graphs from SMILES via OpenSMILES.jl
