# this should likely be moved to a separate package in JMS eventually since (once it's made nice and hopefully more general) it's really a utility on top of AtomsBase, so for now I'm at least putting it in its own file

using StaticArrays
using AtomsBase

"""
    Build a supercell from the provided AbstractSystem object. `repfactors` specifies the multiplier on each lattice vector.

    This is adapted from the implementation in Xtals.jl but should work in arbitrary dimensions.

    For now, returns the new bounding box, list of atomic symbols, and list of positions. Eventually, we probably want a more general way to use propertynames(sys) or similar to get all the arguments one would need to actually just return a new object of the same type with velocities, etc. if present. Basically, we would need a set of rules that tell us how to scale up different types of properties and maybe some interface functions for doing so.
"""
function build_supercell(sys::AbstractSystem, repfactors)
    @assert length(repfactors) == n_dimensions(sys) "Your list of replication factors doesn't match the dimensionality of the system!"

    old_box = bounding_box(sys)
    new_box = repfactors .* old_box
    symbols = repeat(atomic_symbol(sys), prod(repfactors))

    integer_offsets = Iterators.product(range.(Ref(0), repfactors .- 1, step=1)...)
    position_offsets = [sum(offset .* old_box) for offset in integer_offsets]

    old_positions = position(sys)
    new_positions = repeat(MArray.(position(sys)), prod(repfactors))

    for (i, offset) in enumerate(position_offsets)
        indices = (1:length(sys)) .+ (i-1) * length(sys)
        for (j, pos) in enumerate(old_positions)
            new_positions[indices[j]] = pos .+ offset
        end
    end

    return new_box, symbols, SVector.(new_positions)
end