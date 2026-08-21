######################### Implementing NLPModels API #########################
"""
  Evaluates the MPCC objective ``f(x)``
"""
NLPModels.obj(mpcc::AbstractMPCCModel, x::AbstractVector) = NLPModels.obj(mpcc.nlp, x)

"""
  Evaluates in place the gradient of the MPCC objective ``\\nabla f(x)``
"""
function NLPModels.grad!(mpcc::AbstractMPCCModel, x::AbstractVector, gx::AbstractVector)
    NLPModels.grad!(mpcc.nlp, x, gx)
    return gx
end

"""
  Evaluates the gradient of the MPCC objective ``\\nabla f(x)`` to a newly allocated vector.
"""
function NLPModels.grad(mpcc::AbstractMPCCModel{T}, x::AbstractVector{T}) where {T}
    g = Vector{T}(undef, get_nvar(mpcc))
    return grad!(mpcc, x, g)
end

"""
  Evaluates in place the gradient of the MPCC objective ``\\nabla f(x)`` and returns the objective ``f(x)``.
"""
function NLPModels.objgrad!(mpcc::AbstractMPCCModel, x::AbstractVector, g::AbstractVector)
    return NLPModels.objgrad!(mpcc.nlp, x, g)
end

"""
  Evaluates the constraints ``c(x)`` excluding any which appear in ``G(x)`` or ``H(x)``, to a newly allocated vector.
"""
function NLPModels.cons(mpcc::AbstractMPCCModel{T,VT}, x::AbstractVector) where {T,VT}
    c = VT(undef, get_ncon(mpcc))
    cons!(mpcc, x, c)
    return c
end

"""
  Evaluates the constraints ``c(x)`` excluding any which appear in ``G(x)`` or ``H(x)``, in place.
"""
function NLPModels.cons!(mpcc::AbstractMPCCModel, x::AbstractVector, cx::AbstractVector)
    cons!(mpcc.nlp, x, mpcc._c1)
    @views cx .= mpcc._c1[get_ind_c(mpcc)]
    return cx
end

function NLPModels.cons_lin!(mpcc::AbstractMPCCModel, x::AbstractVector, cx::AbstractVector)
    _c_lin = view(mpcc._c1, 1:get_nlin(mpcc.nlp))
    cons_lin!(mpcc.nlp, x, _c_lin)
    @views cx .= _c_lin[get_c_lin(mpcc)]
    return cx
end

function NLPModels.cons_nln!(mpcc::AbstractMPCCModel, x::AbstractVector, cx::AbstractVector)
    _c_nln = view(mpcc._c1, 1:get_nnln(mpcc.nlp))
    cons_nln!(mpcc.nlp, x, _c_nln)
    @views cx .= _c_lin[get_c_nln(mpcc)]
    return cx
end

"""
  Evaluates the constraint jacobian ``\\nabla c(x)`` excluding any constraints which appear in ``G(x)`` or ``H(x)``.
"""
function NLPModels.jac(mpcc::AbstractMPCCModel, x::AbstractVector)
    I, J = jac_structure(mpcc)
    V = jac_coord(mpcc, x)
    return sparse(I, J, V, get_ncon(mpcc), get_nvar(mpcc))
end

"""
  Evaluates the COO structure of jacobian ``\\nabla c(x)`` excluding any constraints which appear in ``G(x)`` or ``H(x)``, in place.
"""
function NLPModels.jac_structure!(
    mpcc::AbstractMPCCModel,
    rows::AbstractVector{<:Integer},
    cols::AbstractVector{<:Integer},
)
    jac_structure!(mpcc.nlp, mpcc._i1, mpcc._i2) # get including complementarities
    @views begin
        rows .= mpcc._i1[get_ind_j_triplets(mpcc)]
        cols .= mpcc._i2[get_ind_j_triplets(mpcc)]
    end
    return rows, cols
end

"""
  Evaluates the COO structure of jacobian ``\\nabla c(x)`` excluding any constraints which appear in ``G(x)`` or ``H(x)``, to newly allocated vectors.
"""
function NLPModels.jac_structure(mpcc::AbstractMPCCModel)
    rows = Vector{Int}(undef, get_nnzj(mpcc))
    cols = Vector{Int}(undef, get_nnzj(mpcc))
    return jac_structure!(mpcc, rows, cols)
end

function NLPModels.jac_lin_structure!(
    mpcc::AbstractMPCCModel,
    rows::AbstractVector{<:Integer},
    cols::AbstractVector{<:Integer},
)
    _rows = view(mpcc._i1, 1:get_lin_nnzj(mpcc.nlp))
    _cols = view(mpcc._i2, 1:get_lin_nnzj(mpcc.nlp))
    jac_lin_structure!(mpcc.nlp, _rows, _cols) # get including complementarities
    @views begin
        rows .= _rows[get_ind_j_lin_triplets(mpcc)]
        cols .= _cols[get_ind_j_lin_triplets(mpcc)]
    end
    # Convert row values adjusting for the number of linear complementarities
    map!((x) -> get_ind_j_lin_row_map(mpcc)[x], rows, rows)

    return rows, cols
end

function NLPModels.jac_nln_structure!(
    mpcc::AbstractMPCCModel,
    rows::AbstractVector{<:Integer},
    cols::AbstractVector{<:Integer},
)
    _rows = view(mpcc._i1, 1:get_nln_nnzj(mpcc.nlp))
    _cols = view(mpcc._i2, 1:get_nln_nnzj(mpcc.nlp))
    jac_nln_structure!(mpcc.nlp, _rows, _cols) # get including complementarities
    @views begin
        rows .= _rows[get_ind_j_nln_triplets(mpcc)]
        cols .= _cols[get_ind_j_nln_triplets(mpcc)]
    end
    # Convert row values adjusting for the number of nonlinear complementarities
    map!((x) -> get_ind_j_nln_row_map(mpcc)[x], rows, rows)

    return rows, cols
end

"""
  Evaluates the COO values of jacobian ``\\nabla c(x)`` excluding any constraints which appear in ``G(x)`` or ``H(x)``, in place.
"""
function NLPModels.jac_coord!(mpcc::AbstractMPCCModel, x::AbstractVector, j::AbstractVector)
    jac_coord!(mpcc.nlp, x, mpcc._j1)
    @views j .= mpcc._j1[get_ind_j_triplets(mpcc)]
    return j
end

"""
  Evaluates the COO values of jacobian ``\\nabla c(x)`` excluding any constraints which appear in ``G(x)`` or ``H(x)``, to a newly allocated vector.
"""
function NLPModels.jac_coord(mpcc::AbstractMPCCModel{T}, x::AbstractVector) where {T}
    vals = Vector{T}(undef, get_nnzj(mpcc))
    return jac_coord!(mpcc, x, vals)
end

function NLPModels.jac_lin_coord!(
    mpcc::AbstractMPCCModel,
    x::AbstractVector,
    j::AbstractVector,
)
    _j = view(mpcc._j1, 1:get_lin_nnzj(mpcc.nlp))
    jac_lin_coord!(mpcc.nlp, x, _j)
    @views j .= _j[get_ind_j_lin_triplets(mpcc)]
    return j
end

function NLPModels.jac_nln_coord!(
    mpcc::AbstractMPCCModel,
    x::AbstractVector,
    j::AbstractVector,
)
    _j = view(mpcc._j1, 1:get_nln_nnzj(mpcc.nlp))
    jac_lin_coord!(mpcc.nlp, x, _j)
    @views j .= _j[get_ind_j_nln_triplets(mpcc)]
    return j
end

function NLPModels.jprod!(
    mpcc::AbstractMPCCModel,
    x::AbstractVector,
    v::AbstractVector,
    Jv::AbstractVector,
)
    Jv[1:get_ncon(mpcc)] .= jac(mpcc, x) * v
    return Jv
end

function NLPModels.jprod_lin!(
    mpcc::AbstractMPCCModel,
    x::AbstractVector,
    v::AbstractVector,
    Jv::AbstractVector,
)
    # TODO(@anton) do this in a smarter way?
    Jv[1:get_nlin(mpcc)] .= jac_lin(mpcc, x) * v
    return Jv
end

function NLPModels.jprod_nln!(
    mpcc::AbstractMPCCModel,
    x::AbstractVector,
    v::AbstractVector,
    Jv::AbstractVector,
)
    # TODO(@anton) do this in a smarter way?
    Jv[1:get_nnln(mpcc)] .= jac_nln(mpcc, x) * v
    return Jv
end

function NLPModels.jtprod!(
    mpcc::AbstractMPCCModel,
    x::AbstractVector,
    v::AbstractVector,
    Jtv::AbstractVector,
)
    # TODO(@anton) do this in a smarter way?
    Jtv[1:get_nvar(mpcc)] .= jac(mpcc, x)' * v
    return Jtv
end

function NLPModels.jtprod_lin!(
    mpcc::AbstractMPCCModel,
    x::AbstractVector,
    v::AbstractVector,
    Jtv::AbstractVector,
)
    # TODO(@anton) do this in a smarter way?
    Jtv[1:get_nvar(mpcc)] .= jac_lin(mpcc, x)' * v
    return Jtv
end

function NLPModels.jtprod_nln!(
    mpcc::AbstractMPCCModel,
    x::AbstractVector,
    v::AbstractVector,
    Jtv::AbstractVector,
)
    # TODO(@anton) do this in a smarter way?
    Jv[1:get_nvar(mpcc)] .= jac_nln(mpcc, x)' * v
    return Jtv
end

"""
  Evaluates the Hessian of the Lagrangian, without the complementarity contribution.

  Assumes zero multipliers.
"""
function NLPModels.hess(
    mpcc::AbstractMPCCModel{T,VT},
    x::AbstractVector,
    y::AbstractVector;
    obj_weight::Real = one(T),
) where {T,VT}
    rows, cols = hess_structure(mpcc)
    vals = hess_coord(mpcc, x, y, obj_weight = obj_weight)
    return Symmetric(sparse(rows, cols, vals, get_nvar(mpcc), get_nvar(mpcc)), :L)
end

"""
  Evaluates the Hessian of the Lagrangian, without the complementarity contribution.
"""

function NLPModels.hess(
    mpcc::AbstractMPCCModel{T},
    x::AbstractVector;
    obj_weight::Real = one(T),
) where {T}
    rows, cols = hess_structure(mpcc)
    vals = hess_coord(mpcc, x, obj_weight = obj_weight)
    return Symmetric(sparse(rows, cols, vals, get_nvar(mpcc), get_nvar(mpcc)), :L)
end

"""
  Evaluates the COO structure of the Hessian of the Lagrangian, without the complementarity contribution, to newly allocated vectors.
"""
function NLPModels.hess_structure(mpcc::AbstractMPCCModel)
    rows = Vector{Int}(undef, get_nnzh(mpcc))
    cols = Vector{Int}(undef, get_nnzh(mpcc))
    hess_structure!(mpcc, rows, cols)
end

"""
  Evaluates the COO structure of the Hessian of the Lagrangian, without the complementarity contribution, in place.
"""
function NLPModels.hess_structure!(
    mpcc::AbstractMPCCModel,
    rows::AbstractVector{<:Integer},
    cols::AbstractVector{<:Integer},
)
    # TODO(@anton) This currently includes the contribution from the nonlinear complementarity constraint multipliers
    #              which is not correct, but this is hard to mask out so it is fine for now.
    return hess_structure!(mpcc.nlp, rows, cols)
end

"""
  Evaluates the COO values of the Hessian of the Lagrangian, without the complementarity contribution, to newly allocated vectors.

  Assumes zero multipliers.
"""
function NLPModels.hess_coord(
    mpcc::AbstractMPCCModel{T,VT},
    x::AbstractVector;
    obj_weight::Real = one(T),
) where {T,VT}
    vals = VT(undef, get_nnzh(mpcc))
    return hess_coord!(mpcc, x, vals; obj_weight = obj_weight)
end

"""
  Evaluates the COO values of the Hessian of the Lagrangian, without the complementarity contribution, to newly allocated vectors.
"""
function NLPModels.hess_coord(
    mpcc::AbstractMPCCModel{T,VT},
    x::AbstractVector,
    y::AbstractVector;
    obj_weight::Real = one(T),
) where {T,VT}
    vals = VT(undef, get_nnzh(mpcc))
    return hess_coord!(mpcc, x, y, vals; obj_weight = obj_weight)
end

"""
  Evaluates the COO structure of the Hessian of the Lagrangian, without the complementarity contribution, in place.
"""
function NLPModels.hess_coord!(
    mpcc::AbstractMPCCModel{T,VT},
    x::AbstractVector{T},
    y::AbstractVector{T},
    H::AbstractVector;
    obj_weight::Real = one(T),
) where {T,VT}
    mpcc._c1 .= T(0.0)
    mpcc._c1[get_ind_c(mpcc)] .= y
    return hess_coord!(mpcc.nlp, x, mpcc._c1, H; obj_weight = obj_weight)
end

"""
  Evaluates the COO structure of the Hessian of the Lagrangian, without the complementarity contribution, in place.

  Assumes zero multipliers.
"""
function NLPModels.hess_coord!(
    mpcc::AbstractMPCCModel{T,VT},
    x::AbstractVector{T},
    H::AbstractVector;
    obj_weight::Real = one(T),
) where {T,VT}
    return hess_coord!(mpcc.nlp, x, H; obj_weight = obj_weight)
end

function NLPModels.hprod!(
    mpcc::AbstractMPCCModel{T,VT},
    x::AbstractVector{T},
    y::AbstractVector{T},
    v::AbstractVector{T},
    Hv::AbstractVector;
    obj_weight::Real = one(T),
) where {T,VT}
    mpcc._c1 .= T(0.0)
    mpcc._c1[get_ind_c(mpcc)] .= y
    return hprod!(mpcc.nlp, x, mpcc._c1, v, Hv; obj_weight = obj_weight)
end

"""
  Evaluates G(x).
"""
function comp_left(mpcc::AbstractMPCCModel{T,VT}, x::AbstractVector{T}) where {T,VT}
    ccx = VT(undef, get_ncc(mpcc))
    return comp_left!(mpcc, x, ccx)
end

"""
  Evaluates G(x) in place.
"""
function comp_left!(
    mpcc::AbstractMPCCModel{T,VT},
    x::AbstractVector{T},
    ccx::AbstractVector{T},
) where {T,VT}
    @lencheck get_ncc(mpcc) ccx
    @lencheck get_nvar(mpcc) x
    cvar = 0
    vert = true
    # First get variables:
    for i = 1:get_ncc(mpcc)
        if get_cc_types(mpcc)[i] ∈ [VarVar, VarCon]
            ccx[i] = x[get_ind_cc1(mpcc)[i]]
            cvar += 1
        else
            vert = false
        end
    end
    # TODO(@anton) this should be done via multiple dispatch probably
    if !vert
        # TODO(@anton) I am not sure anymore if this is correct for non-vertical form
        cons!(mpcc.nlp, x, mpcc._c1)
        @views ccx[(cvar+1):end] .= mpcc._c1[get_cc_l(mpcc)]
    end
    return ccx
end

"""
  Evaluates H(x)
"""
function comp_right(mpcc::AbstractMPCCModel{T,VT}, x::AbstractVector{T}) where {T,VT}
    ccx = VT(undef, get_ncc(mpcc))
    return comp_right!(mpcc, x, ccx)
end

"""
  Evaluates H(x) in place.
"""
function comp_right!(
    mpcc::AbstractMPCCModel{T,VT},
    x::AbstractVector{T},
    ccx::AbstractVector{T},
) where {T,VT}
    @lencheck get_ncc(mpcc) ccx
    @lencheck get_nvar(mpcc) x
    cvar = 0
    vert = true
    # First get variables:
    for i = 1:get_ncc(mpcc)
        if get_cc_types(mpcc)[i] ∈ [VarVar, ConVar]
            ccx[i] = x[get_ind_cc2(mpcc)[i]]
            cvar += 1
        else
            vert = false
        end
    end

    if !vert
        # TODO(@anton) I am not sure anymore if this is correct for non-vertical form
        cons!(mpcc.nlp, x, mpcc._c1)
        @views ccx[(cvar+1):end] .= mpcc._c1[get_cc_r(mpcc)]
    end
    return ccx
end

"""
  Evaluates ``\\ell_G``.
"""
function lcomp_left(mpcc::AbstractMPCCModel{T,VT}) where {T,VT}
    lccx = VT(undef, get_ncc(mpcc))
    return lcomp_left!(mpcc, lccx)
end

"""
  Evaluates ``\\ell_G`` in place.
"""
function lcomp_left!(mpcc::AbstractMPCCModel{T,VT}, lccx::AbstractVector{T}) where {T,VT}
    @lencheck get_ncc(mpcc) lccx

    for i = 1:get_ncc(mpcc)
        if get_cc_types(mpcc)[i] ∈ [VarVar, VarCon]
            lccx[i] = get_lvar(mpcc.nlp)[get_ind_cc1(mpcc)[i]]
        else
            lccx[i] = get_lcon(mpcc.nlp)[get_ind_cc1(mpcc)[i]]
        end
    end
    return lccx
end

"""
  Evaluates ``\\ell_H``.
"""
function lcomp_right(mpcc::AbstractMPCCModel{T,VT}) where {T,VT}
    lccx = VT(undef, get_ncc(mpcc))
    return lcomp_right!(mpcc, lccx)
end

"""
  Evaluates ``\\ell_H`` in place.
"""
function lcomp_right!(mpcc::AbstractMPCCModel{T,VT}, lccx::AbstractVector{T}) where {T,VT}
    @lencheck get_ncc(mpcc) lccx

    for i = 1:get_ncc(mpcc)
        if get_cc_types(mpcc)[i] ∈ [VarVar, ConVar]
            lccx[i] = get_lvar(mpcc.nlp)[get_ind_cc2(mpcc)[i]]
        else
            lccx[i] = get_lcon(mpcc.nlp)[get_ind_cc2(mpcc)[i]]
        end
    end
    return lccx
end

"""
  Evaluates ``G(x) - \\ell_G``.
"""
function comp_res_left(mpcc::AbstractMPCCModel{T,VT}, x::AbstractVector{T}) where {T,VT}
    lccx = VT(undef, get_ncc(mpcc))
    return comp_res_left!(mpcc, x, lccx)
end

"""
  Evaluates ``G(x) - \\ell_G``, in place.
"""
function comp_res_left!(
    mpcc::AbstractMPCCModel{T,VT},
    x::AbstractVector{T},
    lccx::AbstractVector{T},
) where {T,VT}
    @lencheck get_ncc(mpcc) lccx
    @lencheck get_nvar(mpcc) x

    comp_left!(mpcc, x, lccx)

    for i = 1:get_ncc(mpcc)
        if get_cc_types(mpcc)[i] ∈ [VarVar, VarCon]
            lccx[i] -= get_lvar(mpcc.nlp)[get_ind_cc1(mpcc)[i]]
        else
            lccx[i] -= get_lcon(mpcc.nlp)[get_ind_cc1(mpcc)[i]]
        end
    end
    return lccx
end

"""
  Evaluates ``H(x) - \\ell_H``.
"""
function comp_res_right(mpcc::AbstractMPCCModel{T,VT}, x::AbstractVector{T}) where {T,VT}
    rccx = similar(mpcc._cc1, get_ncc(mpcc))
    return comp_res_right!(mpcc, x, rccx)
end

"""
  Evaluates ``H(x) - \\ell_H``, in place.
"""
function comp_res_right!(
    mpcc::AbstractMPCCModel{T,VT},
    x::AbstractVector{T},
    rccx::AbstractVector{T},
) where {T,VT}
    @lencheck get_ncc(mpcc) rccx
    @lencheck get_nvar(mpcc) x

    comp_right!(mpcc, x, rccx)

    for i = 1:get_ncc(mpcc)
        if get_cc_types(mpcc)[i] ∈ [VarVar, ConVar]
            rccx[i] -= get_lvar(mpcc.nlp)[get_ind_cc2(mpcc)[i]]
        else
            rccx[i] -= get_lcon(mpcc.nlp)[get_ind_cc2(mpcc)[i]]
        end
    end
    return rccx
end

"""
  Evaluates ``(G(x)-\\ell_G)\\odot(H(x)-\\ell_H)`` in place.
"""
function comp_res_prod!(
    mpcc::AbstractMPCCModel{T,VT},
    x::AbstractVector{T},
    ccx::AbstractVector{T},
) where {T,VT}
    comp_res_left!(mpcc, x, mpcc._cc1)
    comp_res_right!(mpcc, x, mpcc._cc2)
    ccx .= mpcc._cc1 .* mpcc._cc2
    return ccx
end

"""
  Evaluates ``\\nabla G(x)``.
"""
function jac_comp_left(mpcc::AbstractMPCCModel{T}, x::AbstractVector{T}) where {T}
    I, J = jac_comp_left_structure(mpcc)
    V = jac_comp_left_coord(mpcc, x)
    return sparse(I, J, V, get_ncc(mpcc), get_nvar(mpcc))
end

"""
  Evaluates ``\\nabla H(x)``.
"""
function jac_comp_right(mpcc::AbstractMPCCModel{T}, x::AbstractVector{T}) where {T}
    I, J = jac_comp_right_structure(mpcc)
    V = jac_comp_right_coord(mpcc, x)
    return sparse(I, J, V, get_ncc(mpcc), get_nvar(mpcc))
end

"""
  Evaluates COO structure of ``\\nabla G(x)``.
"""
function jac_comp_left_structure(mpcc::AbstractMPCCModel)
    rows = IndexSet(undef, get_comp_left_nnzj(mpcc))
    cols = IndexSet(undef, get_comp_left_nnzj(mpcc))

    return jac_comp_left_structure!(mpcc, rows, cols)
end

"""
  Evaluates COO structure of ``\\nabla G(x)``, in place.
"""
function jac_comp_left_structure!(
    mpcc::AbstractMPCCModel,
    rows::AbstractVector{<:Integer},
    cols::AbstractVector{<:Integer},
)
    _rows = mpcc._i1
    _cols = mpcc._i2
    jac_lin_structure!(mpcc.nlp, _rows, _cols) # get including complementarities

    @views begin
        rows[1:length(get_ind_j_comp_left_triplets(mpcc))] .=
            _rows[get_ind_j_comp_left_triplets(mpcc)]
        cols[1:length(get_ind_j_comp_left_triplets(mpcc))] .=
            _cols[get_ind_j_comp_left_triplets(mpcc)]
        map!(
            x -> get_ind_j_comp_left_row_map(mpcc)[x],
            rows[1:length(get_ind_j_comp_left_triplets(mpcc))],
            rows[1:length(get_ind_j_comp_left_triplets(mpcc))],
        )
    end

    i_var_comp = length(get_ind_j_comp_left_triplets(mpcc)) + 1
    # TODO(@anton) maybe vectorize
    for i = 1:get_ncc(mpcc)
        if get_cc_types(mpcc)[i] ∈ [VarVar, VarCon]
            rows[i_var_comp] = i;
            cols[i_var_comp] = get_ind_cc1(mpcc)[i]
            i_var_comp += 1
        end
    end
    return rows, cols
end

"""
  Evaluates COO structure of ``\\nabla H(x)``.
"""
function jac_comp_right_structure(mpcc::AbstractMPCCModel)
    rows = IndexSet(undef, get_comp_right_nnzj(mpcc))
    cols = IndexSet(undef, get_comp_right_nnzj(mpcc))

    return jac_comp_right_structure!(mpcc, rows, cols)
end

"""
  Evaluates COO structure of ``\\nabla H(x)``, in place.
"""
function jac_comp_right_structure!(
    mpcc::AbstractMPCCModel,
    rows::AbstractVector{<:Integer},
    cols::AbstractVector{<:Integer},
)
    _rows = mpcc._i1
    _cols = mpcc._i2
    jac_lin_structure!(mpcc.nlp, _rows, _cols) # get including complementarities

    @views begin
        rows[1:length(get_ind_j_comp_right_triplets(mpcc))] .=
            _rows[get_ind_j_comp_right_triplets(mpcc)]
        cols[1:length(get_ind_j_comp_right_triplets(mpcc))] .=
            _cols[get_ind_j_comp_right_triplets(mpcc)]

        map!(
            x -> get_ind_j_comp_right_row_map(mpcc)[x],
            rows[1:length(get_ind_j_comp_right_triplets(mpcc))],
            rows[1:length(get_ind_j_comp_right_triplets(mpcc))],
        )
    end

    i_var_comp = length(get_ind_j_comp_right_triplets(mpcc)) + 1
    # TODO(@anton) maybe vectorize
    for i = 1:get_ncc(mpcc)
        if get_cc_types(mpcc)[i] ∈ [VarVar, ConVar]
            rows[i_var_comp] = i;
            cols[i_var_comp] = get_ind_cc2(mpcc)[i]
            i_var_comp += 1
        end
    end
    return rows, cols
end

"""
  Evaluates COO values of ``\\nabla G(x)``.
"""
function jac_comp_left_coord(mpcc::AbstractMPCCModel{T,VT}, x::AbstractVector) where {T,VT}
    vals = VT(undef, get_comp_left_nnzj(mpcc))

    return jac_comp_left_coord!(mpcc, x, vals)
end

"""
  Evaluates COO values of ``\\nabla G(x)``, in place.
"""
function jac_comp_left_coord!(
    mpcc::AbstractMPCCModel,
    x::AbstractVector,
    vals::AbstractVector,
)
    # NOTE: Var type nnz triples come at end ALWAYS
    _vals = mpcc._j1
    NLPModels.jac_coord!(mpcc.nlp, x, _vals)
    @views vals[1:length(get_ind_j_comp_left_triplets(mpcc))] .=
        _vals[get_ind_j_comp_left_triplets(mpcc)]

    i_var_comp = length(get_ind_j_comp_left_triplets(mpcc)) + 1
    # TODO(@anton) maybe vectorize
    for i = 1:get_ncc(mpcc)
        if get_cc_types(mpcc)[i] ∈ [VarVar, VarCon]
            vals[i_var_comp] = 1.0;
            i_var_comp += 1
        end
    end
    return vals
end

"""
  Evaluates COO values of ``\\nabla H(x)``.
"""
function jac_comp_right_coord(mpcc::AbstractMPCCModel{T,VT}, x::AbstractVector) where {T,VT}
    vals = VT(undef, get_comp_left_nnzj(mpcc))

    return jac_comp_right_coord!(mpcc, x, vals)
end

"""
  Evaluates COO values of ``\\nabla G(x)``, in place.
"""
function jac_comp_right_coord!(
    mpcc::AbstractMPCCModel,
    x::AbstractVector,
    vals::AbstractVector,
)
    # NOTE: Var type nnz triples come at end ALWAYS
    _vals = mpcc._j1
    NLPModels.jac_coord!(mpcc.nlp, x, _vals)
    @views vals[1:length(get_ind_j_comp_right_triplets(mpcc))] .=
        _vals[get_ind_j_comp_right_triplets(mpcc)]

    i_var_comp = length(get_ind_j_comp_right_triplets(mpcc)) + 1
    # TODO(@anton) maybe vectorize
    for i = 1:get_ncc(mpcc)
        if get_cc_types(mpcc)[i] ∈ [VarVar, ConVar]
            vals[i_var_comp] = 1.0;
            i_var_comp += 1
        end
    end
    return vals
end

"""
  Evaluates ``\\vert\\min(G(x)-\\ell_G,H(x)-\\ell_H)\\vert_\\infty``.
"""
function comp_residual(mpcc::AbstractMPCCModel{T,VT}, x::AbstractVector) where {T,VT}
    # TODO(@anton): This can be done more efficiently in vertical form
    G = mpcc._cc1
    H = mpcc._cc2
    comp_res_left!(mpcc, x, G)
    comp_res_right!(mpcc, x, H)

    map!(min, G, G, H)
    return maximum(G)
end

"""
  Evaluates ``\\vert (G(x)-\\ell_G)\\odot(H(x)-\\ell_H)\\vert_\\infty``.
"""
function comp_residual_product(
    mpcc::AbstractMPCCModel{T,VT},
    x::AbstractVector,
) where {T,VT}
    # TODO(@anton): This can be done more efficiently in vertical form
    G = mpcc._cc1
    H = mpcc._cc2
    comp_res_left!(mpcc, x, G)
    comp_res_right!(mpcc, x, H)

    G .*= H
    return maximum(G)
end

"""
  Evaluates ``(G(x)-\\ell_G)\\cdot(H(x)-\\ell_H)``.
"""
function comp_residual_sum(mpcc::AbstractMPCCModel{T,VT}, x::AbstractVector) where {T,VT}
    # TODO(@anton): This can be done more efficiently in vertical form
    G = mpcc._cc1
    H = mpcc._cc2
    comp_res_left!(mpcc, x, G)
    comp_res_right!(mpcc, x, H)
    return dot(G, H)
end
