using ZygoteRules: @adjoint

@adjoint function Dict(g::Base.Generator)
  ys, backs = Zygote.unzip([Zygote.pullback(g.f, args) for args in g.iter])
  Dict(ys...), Δ -> begin
    dd = Dict(k => b(Δ)[1].second for (b,(k,v)) in zip(backs, pairs(Δ)))
    ((x for x in dd),)
  end
end

@adjoint function _cutoff!(weight_mat, f, ijd,
                           nb_counts, longest_dists;
                           max_num_nbr = 12)
  y, ld = _cutoff!(weight_mat, f, ijd,
               nb_counts, longest_dists;
               max_num_nbr = max_num_nbr)
  function cutoff_pb((Δ,nt))
    s = size(Δ)
    Δ = vec(collect(Δ))
    for (ix, (_,_,d)) in zip(eachindex(Δ), ijd)
      y_, back_ = Zygote.pullback(f, d)
      Δ[ix] *= first(back_(Zygote.sensitivity(d)))
    end
    (reshape(Δ, s), nothing,
    collect(zip(fill(nothing, size(Δ,1)),
                fill(nothing, size(Δ,1)),
                Δ)),
    nothing,
    nothing)
  end

  (y,ld), cutoff_pb
end
