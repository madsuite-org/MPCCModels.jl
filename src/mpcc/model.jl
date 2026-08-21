
"""
  Concrete type for problems in the form:

    min f(x)
    s.t. lbc ≤ c(x) ≤ ubc
         lbG ≤ G(x) ⟂ H(x) ≥ lbH

  where G(x) and H(x) are defined by index sets into the x and c(x) of an nlp of the from:

    min f(x)
    s.t. lbc ≤ c(x) ≤ ubc
"""
struct MPCCModel{T,VT,NLP<:NLPModels.AbstractNLPModel{T,VT},NMT} <: AbstractMPCCModel{T,VT}
    nlp::NLP
    meta::MPCCModelMeta{T,VT,NMT}
    _c1::VT       # [nlp.ncon]
    _j1::VT       # [nlp.nnzj]
    _i1::IndexSet # [nlp.nnzj]
    _i2::IndexSet # [nlp.nnzj]
    _cc1::VT      # [ncc]
    _cc2::VT      # [ncc]
    counters::NLPModels.Counters
end

######################### MPCC Constructors #########################
"""
  Constructor for `MPCCModel` in the form:

     min f(x)
     s.t. lbc ≤ c(w) ≤ ubc
          lbx₁ ≤ x₁ ⟂x₂ ≥ lbx₂

  where x₁ and x₂ are defined by index sets ind_vcc1 and ind_vcc2.
"""
function MPCCModel(
    nlp::AbstractNLPModel{T,VT},
    ind_vcc1::IndexSet,
    ind_vcc2::IndexSet,
) where {T,VT}
    # compute sizes
    ncc = length(ind_vcc1)
    ncon = get_ncon(nlp)
    nlin = get_nlin(nlp)
    nnln = get_nnln(nlp)

    # compute non-complementarity variables/constraints
    ind_x = setdiff(1:get_nvar(nlp), union(ind_vcc1, ind_vcc2))
    ind_c = collect(1:get_ncon(nlp))

    # compute jacobian structure indexset
    ind_j_triplets = collect(1:get_nnzj(nlp))
    ind_j_lin_triplets = collect(1:get_lin_nnzj(nlp))
    ind_j_nln_triplets = collect(1:get_nln_nnzj(nlp))
    ind_j_lin_row_map = Dict(zip(1:nlin, 1:nlin))
    ind_j_nln_row_map = Dict(zip(1:nnln, 1:nnln))

    ind_j_comp_left_triplets::IndexSet = []
    ind_j_comp_right_triplets::IndexSet = []
    ind_j_comp_left_row_map = Dict{Int,Int}()
    ind_j_comp_right_row_map = Dict{Int,Int}()
    # compute nln and lin index sets
    lin = get_lin(nlp)
    nln = get_nln(nlp)
    nlin = length(lin)
    nnln = length(nln)
    c_lin = collect(1:nlin)
    c_nln = collect(1:nnln)
    cc_l::IndexSet = []
    cc_r::IndexSet = []

    # Complementarity Constraints
    ind_cc1 = ind_vcc1
    ind_cc2 = ind_vcc2
    cc_types = fill!(Vector{CCType}(undef, ncc), VarVar)

    # nnzj updates:
    nnzj = get_nnzj(nlp)
    lin_nnzj = get_lin_nnzj(nlp)
    nln_nnzj = get_nln_nnzj(nlp)
    comp_left_nnzj = ncc
    comp_right_nnzj = ncc

    meta = MPCCModelMeta(
        Ref(nlp.meta),
        ncc,
        ncon,
        nlin,
        nnln,
        nnzj,
        lin_nnzj,
        nln_nnzj,
        comp_left_nnzj,
        comp_right_nnzj,
        lin,
        nln,
        c_lin,
        c_nln,
        cc_l,
        cc_r,
        ind_cc1,
        ind_cc2,
        cc_types,
        ind_x,
        ind_c,
        ind_j_triplets,
        ind_j_lin_triplets,
        ind_j_nln_triplets,
        ind_j_comp_left_triplets,
        ind_j_comp_right_triplets,
        ind_j_comp_left_row_map,
        ind_j_comp_right_row_map,
        ind_j_lin_row_map,
        ind_j_nln_row_map,
    )

    # Build work vectors
    _c1 = VT(undef, get_ncon(nlp))
    _j1 = VT(undef, get_nnzj(nlp))
    _i1 = IndexSet(undef, get_nnzj(nlp))
    _i2 = IndexSet(undef, get_nnzj(nlp))
    _cc1 = VT(undef, ncc)
    _cc2 = VT(undef, ncc)

    return MPCCModel(nlp, meta, _c1, _j1, _i1, _i2, _cc1, _cc2, nlp.counters)
end

# Constructor
function MPCCModelConCon(
    nlp::AbstractNLPModel{T,VT},
    ind_ccc1::IndexSet,
    ind_ccc2::IndexSet,
) where {T,VT}
    # compute sizes
    ncc = length(ind_ccc1)
    ncon = get_ncon(nlp) - 2*ncc

    # compute non-complementarity variables/constraints
    ind_x = collect(1:get_nvar(nlp))
    ind_c = setdiff(1:get_ncon(nlp), union(ind_ccc1, ind_ccc2))

    # compute jacobian structure indexset
    rows, cols = NLPModels.jac_structure(nlp)
    ind_j_triplets = findall(x->x ∈ ind_c, rows)
    if hasmethod(jac_lin_structure!, (typeof(nlp), IndexSet, IndexSet))
        lin_rows, lin_cols = NLPModels.jac_lin_structure(nlp)
        nln_rows, nln_cols = NLPModels.jac_nln_structure(nlp)
        for i in 1:get_nlin(nlp)
            lin_rows[i] += count(x < get_lin(nlp)[lin_rows[i]] for x in get_nln(nlp))
        end
        for i in 1:get_nnln(nlp)
            nln_rows[i] += count(x < get_nln(nlp)[nln_rows[i]] for x in get_lin(nlp))
        end
        ind_j_lin_triplets = findall(x->!((x∈ind_ccc1) || (x∈ind_ccc2)), lin_rows)
        ind_j_nln_triplets = findall(x->!((x∈ind_ccc1) || (x∈ind_ccc2)), nln_rows)

        # compute nln and lin index sets
        lin = intersect(get_lin(nlp), ind_c)
        nln = intersect(get_nln(nlp), ind_c)
        nlin = length(lin)
        nnln = length(nln)
        c_lin = [i for i in 1:nlin if get_lin(nlp)[i] ∈ ind_c]
        cc_lin = [i for i in 1:nlin if get_lin(nlp)[i] ∉ ind_c]
        c_nln = [i for i in 1:nnln if get_nln(nlp)[i] ∈ ind_c]
        cc_nln = [i for i in 1:nnln if get_nln(nlp)[i] ∉ ind_c]

        ind_j_lin_row_map =
            Dict((i, i-count([x < i for x in cc_lin])) for i in 1:get_nlin(nlp))
        ind_j_nln_row_map =
            Dict((i, i-count([x < i for x in cc_nln])) for i in 1:get_nnln(nlp))
    else
        ind_j_lin_triplets::IndexSet = []
        ind_j_nln_triplets = ind_j_triplets
        lin::IndexSet = []
        nln = get_nln(nlp)
        nlin = get_nlin(nlp)
        nnln = get_nnln(nlp)
        c_lin::IndexSet = []
        cc_lin::IndexSet = []
        c_nln = [i for i in 1:nnln if get_nln(nlp)[i] ∈ ind_c]
        cc_nln = [i for i in 1:nnln if get_nln(nlp)[i] ∉ ind_c]

        ind_j_lin_row_map = Dict{Int,Int}()
        ind_j_nln_row_map::Dict{Int,Int} =
            Dict((i, i-count([x < i for x in cc_nln])) for i in 1:get_nnln(nlp))
    end
    ind_j_comp_left_triplets = findall(x->x∈ind_ccc1, rows);
    ind_j_comp_right_triplets = findall(x->x∈ind_ccc2, rows);
    ind_j_comp_left_row_map = Dict{Int,Int}(zip(ind_ccc1, 1:ncc))
    ind_j_comp_right_row_map = Dict{Int,Int}(zip(ind_ccc2, 1:ncc))

    # Complementarity Constraints
    ind_cc1 = ind_ccc1;
    ind_cc2 = ind_ccc2;
    cc_types = fill!(Vector{CCType}(undef, ncc), ConCon)
    cc_l = [i for i in 1:get_ncon(nlp) if i ∈ ind_cc1]
    cc_r = [i for i in 1:get_ncon(nlp) if i ∈ ind_cc2]

    # nnzj updates:
    lin_nnzj = length(ind_j_lin_triplets)
    nln_nnzj = length(ind_j_nln_triplets)
    nnzj = lin_nnzj + nln_nnzj
    comp_left_nnzj = length(ind_j_comp_left_triplets)
    comp_right_nnzj = length(ind_j_comp_right_triplets)

    meta = MPCCModelMeta(
        Ref(nlp.meta),
        ncc,
        ncon,
        nlin,
        nnln,
        nnzj,
        lin_nnzj,
        nln_nnzj,
        comp_left_nnzj,
        comp_right_nnzj,
        lin,
        nln,
        c_lin,
        c_nln,
        cc_l,
        cc_r,
        ind_cc1,
        ind_cc2,
        cc_types,
        ind_x,
        ind_c,
        ind_j_triplets,
        ind_j_lin_triplets,
        ind_j_nln_triplets,
        ind_j_comp_left_triplets,
        ind_j_comp_right_triplets,
        ind_j_comp_left_row_map,
        ind_j_comp_right_row_map,
        ind_j_lin_row_map,
        ind_j_nln_row_map,
    )

    # Build work vectors
    _c1 = VT(undef, get_ncon(nlp))
    _j1 = VT(undef, get_nnzj(nlp))
    _i1 = IndexSet(undef, get_nnzj(nlp))
    _i2 = IndexSet(undef, get_nnzj(nlp))
    _cc1 = VT(undef, ncc)
    _cc2 = VT(undef, ncc)

    return MPCCModel(nlp, meta, _c1, _j1, _i1, _i2, _cc1, _cc2, nlp.counters)
end

# Constructor
function MPCCModelVarCon(
    nlp::AbstractNLPModel{T,VT},
    ind_vcc1::IndexSet,
    ind_ccc2::IndexSet,
) where {T,VT}
    # compute sizes
    ncc = length(ind_vcc1)
    ncon = get_ncon(nlp) - ncc
    # compute non-complementarity variables/constraints
    ind_x = setdiff(1:get_nvar(nlp), ind_vcc1)
    ind_c = setdiff(1:get_ncon(nlp), ind_ccc2)

    # compute jacobian structure indexset
    rows, cols = NLPModels.jac_structure(nlp)
    ind_j_triplets = findall(x->x ∈ ind_c, rows)
    if hasmethod(jac_lin_structure!, (typeof(nlp), IndexSet, IndexSet))
        lin_rows, lin_cols = NLPModels.jac_lin_structure(nlp)
        nln_rows, nln_cols = NLPModels.jac_nln_structure(nlp)
        # Convert to true row numbers
        for i in 1:get_nlin(nlp)
            lin_rows[i] += count(x < get_lin(nlp)[lin_rows[i]] for x in get_nln(nlp))
        end
        for i in 1:get_nnln(nlp)
            nln_rows[i] += count(x < get_nln(nlp)[nln_rows[i]] for x in get_lin(nlp))
        end
        # Keep only the "correct" indices
        ind_j_lin_triplets = findall(x->!(x∈ind_ccc2), lin_rows)
        ind_j_nln_triplets = findall(x->!(x∈ind_ccc2), nln_rows)

        # compute nln and lin index sets
        lin = intersect(get_lin(nlp), ind_c)
        nln = intersect(get_nln(nlp), ind_c)
        nlin = length(lin)
        nnln = length(nln)
        c_lin = [i for i in 1:nlin if get_lin(nlp)[i] ∈ ind_c]
        cc_lin = [i for i in 1:nlin if get_lin(nlp)[i] ∉ ind_c]
        c_nln = [i for i in 1:nnln if get_nln(nlp)[i] ∈ ind_c]
        cc_nln = [i for i in 1:nnln if get_nln(nlp)[i] ∉ ind_c]

        ind_j_lin_row_map =
            Dict((i, i-count([x < i for x in cc_lin])) for i in 1:get_nlin(nlp))
        ind_j_nln_row_map =
            Dict((i, i-count([x < i for x in cc_nln])) for i in 1:get_nnln(nlp))
    else
        ind_j_lin_triplets::IndexSet = []
        ind_j_nln_triplets = ind_j_triplets
        lin::IndexSet = []
        nln = get_nln(nlp)
        nlin = get_nlin(nlp)
        nnln = get_nnln(nlp)
        c_lin::IndexSet = []
        cc_lin::IndexSet = []
        c_nln = [i for i in 1:nnln if get_nln(nlp)[i] ∈ ind_c]
        cc_nln = [i for i in 1:nnln if get_nln(nlp)[i] ∉ ind_c]

        ind_j_lin_row_map = Dict{Int,Int}()
        ind_j_nln_row_map::Dict{Int,Int} =
            Dict((i, i-count([x < i for x in cc_nln])) for i in 1:get_nnln(nlp))
    end
    ind_j_comp_left_triplets::IndexSet = [];
    ind_j_comp_right_triplets = findall(x->x∈ind_ccc2, rows);
    ind_j_comp_left_row_map = Dict{Int,Int}()
    ind_j_comp_right_row_map = Dict{Int,Int}(zip(ind_ccc2, 1:ncc))

    # UNUSED
    ind_cc1 = ind_vcc1;
    ind_cc2 = ind_ccc2;
    cc_types = fill!(Vector{CCType}(undef, ncc), VarCon)
    cc_l::IndexSet = [];
    cc_r = [i for i in 1:get_ncon(nlp) if i ∈ ind_cc2]

    # nnzj updates:
    lin_nnzj = length(ind_j_lin_triplets)
    nln_nnzj = length(ind_j_nln_triplets)
    nnzj = lin_nnzj + nln_nnzj
    comp_left_nnzj = ncc
    comp_right_nnzj = length(ind_j_comp_right_triplets)

    meta = MPCCModelMeta(
        Ref(nlp.meta),
        ncc,
        ncon,
        nlin,
        nnln,
        nnzj,
        lin_nnzj,
        nln_nnzj,
        comp_left_nnzj,
        comp_right_nnzj,
        lin,
        nln,
        c_lin,
        c_nln,
        cc_l,
        cc_r,
        ind_cc1,
        ind_cc2,
        cc_types,
        ind_x,
        ind_c,
        ind_j_triplets,
        ind_j_lin_triplets,
        ind_j_nln_triplets,
        ind_j_comp_left_triplets,
        ind_j_comp_right_triplets,
        ind_j_comp_left_row_map,
        ind_j_comp_right_row_map,
        ind_j_lin_row_map,
        ind_j_nln_row_map,
    )

    # Build work vectors
    _c1 = VT(undef, get_ncon(nlp))
    _j1 = VT(undef, get_nnzj(nlp))
    _i1 = IndexSet(undef, get_nnzj(nlp))
    _i2 = IndexSet(undef, get_nnzj(nlp))
    _cc1 = VT(undef, ncc)
    _cc2 = VT(undef, ncc)

    return MPCCModel(nlp, meta, _c1, _j1, _i1, _i2, _cc1, _cc2, nlp.counters)
end

# Verticalize generic CC types. Returns a vertical form MPCC
# TODO(@anton) we do no checks here :)
function MPCCModel(
    nlp::AbstractNLPModel,
    ind_cc1::IndexSet,
    ind_cc2::IndexSet,
    cc_types::AbstractVector{CCType},
)
    ncc = length(ind_cc1)
    nvar = get_nvar(nlp)

    ind_lift1::IndexSet = [i for i in 1:ncc if cc_types[i]∈[ConVar, ConCon]]
    ind_lift2::IndexSet = [i for i in 1:ncc if cc_types[i]∈[VarCon, ConCon]]
    nlift1 = length(ind_lift1)
    nlift2 = length(ind_lift2)

    ind_lift::IndexSet =
        vcat(map((i) -> ind_cc1[i], ind_lift1), map((i) -> ind_cc2[i], ind_lift2))
    vnlp = LiftedNLPModel(nlp, ind_lift)

    lift1 = (nvar+1):(nvar+nlift1)
    lift2 = (nvar+nlift1+1):(nvar+nlift1+nlift2)

    ind_vcc1 = ind_cc1
    ind_vcc1[ind_lift1] = lift1
    ind_vcc2 = ind_cc2
    ind_vcc2[ind_lift2] = lift2

    return MPCCModel(vnlp, ind_vcc1, ind_vcc2)
end

######################### Vertical Form Conversion #########################
"""
  "Verticalize" a generic MPCC by lifting the nonscalar compenents of ``G(x)`` and ``H(x)``.
"""
function vertical_form(mpcc::AbstractMPCCModel)
    ind_var1 = [
        get_ind_cc1(mpcc)[i] for
        i in 1:get_ncc(mpcc) if get_cc_types(mpcc)[i]∈[ConVar, ConCon]
    ]

    ind_lift1::IndexSet =
        [i for i in 1:get_ncc(mpcc) if get_cc_types(mpcc)[i]∈[ConVar, ConCon]]
    ind_lift2::IndexSet =
        [i for i in 1:get_ncc(mpcc) if get_cc_types(mpcc)[i]∈[VarCon, ConCon]]
    nlift1 = length(ind_lift1)
    nlift2 = length(ind_lift2)

    ind_lift::IndexSet = vcat(
        map((i) -> get_ind_cc1(mpcc)[i], ind_lift1),
        map((i) -> get_ind_cc2(mpcc)[i], ind_lift2),
    )
    vnlp = LiftedNLPModel(mpcc.nlp, ind_lift)

    lift1 = (get_nvar(mpcc.nlp)+1):(get_nvar(mpcc.nlp)+nlift1)
    lift2 = (get_nvar(mpcc.nlp)+nlift1+1):(get_nvar(mpcc.nlp)+nlift1+nlift2)

    ind_vcc1 = get_ind_cc1(mpcc)
    ind_vcc1[ind_lift1] = lift1
    ind_vcc2 = get_ind_cc2(mpcc)
    ind_vcc2[ind_lift2] = lift2

    return MPCCModel(vnlp, ind_vcc1, ind_vcc2)
end
