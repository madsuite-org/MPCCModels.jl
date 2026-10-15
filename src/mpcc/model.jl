
"""
  Concrete type for problems in the form:

    min f(x)
    s.t. lbc ≤ c(x) ≤ ubc
         lbG ≤ G(x) ⟂ H(x) ≥ lbH

  where G(x) and H(x) are defined by index sets into the x and c(x) of an NLP of the from:

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

function _check_index_set(indices::IndexSet, upper::Int, name::AbstractString)
    all(i -> 1 <= i <= upper, indices) ||
        throw(ArgumentError("$name contains an index outside 1:$upper"))
    return indices
end

function _mpcc_constraint_data(nlp::AbstractNLPModel, ind_c::IndexSet)
    # `ind_c` is kept in the underlying NLP's constraint order. All public
    # constraint rows are compacted to this order.
    ind_c = sort!(unique!(copy(ind_c)))
    kept = Set(ind_c)
    source_lin = get_lin(nlp)
    source_nln = get_nln(nlp)
    source_lin_set = Set(source_lin)
    source_nln_set = Set(source_nln)
    kept_lin = [row for row in source_lin if row in kept]
    kept_nln = [row for row in source_nln if row in kept]

    rows, _ = NLPModels.jac_structure(nlp)
    ind_j_triplets = findall(row -> row in kept, rows)
    ind_j_lin_triplets = findall(row -> row in kept && row in source_lin_set, rows)
    ind_j_nln_triplets = findall(row -> row in kept && row in source_nln_set, rows)

    # These maps accept original NLP row numbers. The Jacobian helper methods
    # use full-NLP COO data and map the rows into the filtered MPCC outputs.
    ind_j_lin_row_map = Dict(row => i for (i, row) in enumerate(kept_lin))
    ind_j_nln_row_map = Dict(row => i for (i, row) in enumerate(kept_nln))

    return (; ind_c,
        ncon = length(ind_c),
        nlin = length(kept_lin),
        nnln = length(kept_nln),
        c_lin = findall(row -> row in kept, source_lin),
        c_nln = findall(row -> row in kept, source_nln),
        ind_j_triplets,
        ind_j_lin_triplets,
        ind_j_nln_triplets,
        ind_j_lin_row_map,
        ind_j_nln_row_map)
end

"""
    _complementarity_jacobian_data(rows, ind_cc) -> triplets, output_rows

Map the COO entries of the parent Jacobian onto complementarity rows. `rows`
contains the parent constraint row for each Jacobian triplet, and `ind_cc`
lists the parent constraint rows used by each complementarity component.

The returned `triplets` contains parent Jacobian triplet indices, and
`output_rows` contains the corresponding complementarity row for each index.
The vectors have equal length and aligned entries. If a parent constraint row
appears multiple times in `ind_cc`, each of its Jacobian triplets is repeated
once for every corresponding complementarity row.
"""
function _complementarity_jacobian_data(rows::AbstractVector{<:Integer}, ind_cc::IndexSet)
    cc_rows_by_source = Dict{Int,IndexSet}()
    for (cc_row, source_row) in enumerate(ind_cc)
        push!(get!(cc_rows_by_source, source_row, IndexSet()), cc_row)
    end

    triplets = IndexSet()
    output_rows = IndexSet()
    for (triplet, source_row) in enumerate(rows)
        if haskey(cc_rows_by_source, source_row)
            for cc_row in cc_rows_by_source[source_row]
                push!(triplets, triplet)
                push!(output_rows, cc_row)
            end
        end
    end

    return triplets, output_rows
end

function _build_mpcc_meta(
    nlp::AbstractNLPModel,
    ncc::Int,
    data,
    ind_cc1::IndexSet,
    ind_cc2::IndexSet,
    cc_types::Vector{CCType},
    ind_j_comp_left_triplets::IndexSet,
    ind_j_comp_right_triplets::IndexSet,
    ind_j_comp_left_rows::IndexSet,
    ind_j_comp_right_rows::IndexSet,
)
    comp_left_nnzj = length(ind_j_comp_left_triplets) +
                     count(t -> t in (VarVar, VarCon), cc_types)
    comp_right_nnzj = length(ind_j_comp_right_triplets) +
                      count(t -> t in (VarVar, ConVar), cc_types)
    return MPCCModelMeta(
        Ref(nlp.meta), ncc, data.ncon, data.nlin, data.nnln,
        length(data.ind_j_triplets), length(data.ind_j_lin_triplets),
        length(data.ind_j_nln_triplets), comp_left_nnzj, comp_right_nnzj,
        data.c_lin, data.c_nln,
        ind_cc1, ind_cc2, cc_types, data.ind_c,
        data.ind_j_triplets, data.ind_j_lin_triplets, data.ind_j_nln_triplets,
        ind_j_comp_left_triplets, ind_j_comp_right_triplets,
        ind_j_comp_left_rows, ind_j_comp_right_rows,
        data.ind_j_lin_row_map, data.ind_j_nln_row_map,
    )
end

function _make_mpcc(nlp::AbstractNLPModel{T,VT}, meta::MPCCModelMeta, ncc::Int) where {T,VT}
    _c1 = VT(undef, get_ncon(nlp))
    _j1 = VT(undef, get_nnzj(nlp))
    _i1 = IndexSet(undef, get_nnzj(nlp))
    _i2 = IndexSet(undef, get_nnzj(nlp))
    _cc1 = VT(undef, ncc)
    _cc2 = VT(undef, ncc)
    return MPCCModel(nlp, meta, _c1, _j1, _i1, _i2, _cc1, _cc2, nlp.counters)
end

"""
Constructor for `MPCCModel` in the form:

     min f(x)
     s.t. lbc ≤ c(w) ≤ ubc
          lbx₁ ≤ x₁ ⟂ x₂ ≥ lbx₂

where x₁ and x₂ are defined by index sets `ind_vcc1` and `ind_vcc2`.
"""
function MPCCModel(
    nlp::AbstractNLPModel{T,VT},
    ind_vcc1::IndexSet,
    ind_vcc2::IndexSet,
) where {T,VT}
    return MPCCModel(nlp, ind_vcc1, ind_vcc2, fill(VarVar, length(ind_vcc1)))
end

"""
Construct a constraint–constraint MPCC, with both complementarity sides
selected from rows of `nlp`'s constraint vector. Every selected row must
have a finite lower bound and an upper bound of `Inf`; selected rows are
removed from the ordinary constraint API.
"""
function MPCCModelConCon(
    nlp::AbstractNLPModel{T,VT},
    ind_ccc1::IndexSet,
    ind_ccc2::IndexSet,
) where {T,VT}
    return MPCCModel(nlp, ind_ccc1, ind_ccc2, fill(ConCon, length(ind_ccc1)))
end

"""
Construct a variable–constraint MPCC. `ind_vcc1` indexes variables for the
left complementarity side, and `ind_ccc2` indexes constraint rows for the
right side. Every selected constraint row must have a finite lower bound
and an upper bound of `Inf`; selected rows are removed from the ordinary
constraint API.
"""
function MPCCModelVarCon(
    nlp::AbstractNLPModel{T,VT},
    ind_vcc1::IndexSet,
    ind_ccc2::IndexSet,
) where {T,VT}
    return MPCCModel(nlp, ind_vcc1, ind_ccc2, fill(VarCon, length(ind_vcc1)))
end

"""
Construct an `MPCCModel` with one complementarity pair per entry of `cc_types`.
The corresponding entries of `ind_cc1` and `ind_cc2` index variables or
constraint rows according to the complementarity type:

- `VarVar`: both indices refer to variables.
- `VarCon`: `ind_cc1` refers to a variable and `ind_cc2` to a constraint row.
- `ConVar`: `ind_cc1` refers to a constraint row and `ind_cc2` to a variable.
- `ConCon`: both indices refer to constraint rows.

Each constraint row used in a complementarity pair must have a finite lower
bound and an upper bound of `Inf`. Such rows are removed from the ordinary
constraint API.
"""
function MPCCModel(
    nlp::AbstractNLPModel,
    ind_cc1::IndexSet,
    ind_cc2::IndexSet,
    cc_types::AbstractVector{CCType},
)
    left = copy(ind_cc1)
    right = copy(ind_cc2)
    types = collect(cc_types)
    ncc = length(left)
    length(right) == ncc || throw(ArgumentError("complementarity index sets must have equal lengths"))
    length(types) == ncc || throw(ArgumentError("one complementarity type is required per pair"))
    nvar = get_nvar(nlp)
    ncon = get_ncon(nlp)

    left_var = [left[i] for i in 1:ncc if types[i] in (VarVar, VarCon)]
    right_var = [right[i] for i in 1:ncc if types[i] in (VarVar, ConVar)]
    left_con = [left[i] for i in 1:ncc if types[i] in (ConVar, ConCon)]
    right_con = [right[i] for i in 1:ncc if types[i] in (VarCon, ConCon)]
    _check_index_set(left_var, nvar, "left variable indices")
    _check_index_set(right_var, nvar, "right variable indices")
    _check_index_set(left_con, ncon, "left constraint indices")
    _check_index_set(right_con, ncon, "right constraint indices")

    comp_constraints = union(left_con, right_con)
    lcon = get_lcon(nlp)
    ucon = get_ucon(nlp)
    for row in comp_constraints
        isfinite(lcon[row]) || throw(ArgumentError(
            "constraint row $row used in complementarity must have a finite lower bound",
        ))
        (isinf(ucon[row]) && ucon[row] > 0) || throw(ArgumentError(
            "constraint row $row used in complementarity must have an upper bound of Inf",
        ))
    end
    data = _mpcc_constraint_data(nlp, setdiff(1:ncon, comp_constraints))
    rows, _ = NLPModels.jac_structure(nlp)
    left_triplets, left_rows = _complementarity_jacobian_data(rows, left_con)
    right_triplets, right_rows =  _complementarity_jacobian_data(rows, right_con)
    meta = _build_mpcc_meta(
        nlp, ncc, data, left, right, types,
        left_triplets, right_triplets,
        left_rows, right_rows,
    )
    return _make_mpcc(nlp, meta, ncc)
end

"""
  "Verticalize" a generic MPCC by lifting the nonscalar components of ``G(x)`` and ``H(x)``
  with two slacks ``s_1`` and ``s_2``.
"""
function vertical_form(mpcc::AbstractMPCCModel)
    left = copy(get_ind_cc1(mpcc))
    right = copy(get_ind_cc2(mpcc))
    types = get_cc_types(mpcc)
    left_con = [left[i] for i in 1:get_ncc(mpcc) if types[i] in (ConVar, ConCon)]
    right_con = [right[i] for i in 1:get_ncc(mpcc) if types[i] in (VarCon, ConCon)]
    ind_lift = Base.unique(vcat(left_con, right_con))
    vnlp = LiftedNLPModel(mpcc.nlp, ind_lift)
    nvar = get_nvar(mpcc.nlp)
    lift_var = Dict(row => nvar + i for (i, row) in enumerate(ind_lift))
    ind_vcc1 = copy(left)
    ind_vcc2 = copy(right)
    for i in 1:get_ncc(mpcc)
        if types[i] in (ConVar, ConCon)
            ind_vcc1[i] = lift_var[left[i]]
        end
        if types[i] in (VarCon, ConCon)
            ind_vcc2[i] = lift_var[right[i]]
        end
    end

    return MPCCModel(vnlp, ind_vcc1, ind_vcc2)
end
