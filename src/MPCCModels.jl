module MPCCModels
using NLPModels, LinearAlgebra, SparseArrays

"""
  Abstract type for problems in the form:

    min f(w)
    s.t. lbc ≤ c(w) ≤ ubc
         lbG ≤ G(w) ⟂ H(w) ≥ lbH
"""
abstract type AbstractMPCCModel{T,VT} end

include("utils.jl")
include("lifted_model.jl")
include("mpcc/meta.jl")
include("mpcc/model.jl")
include("mpcc/api.jl")

# types
export AbstractMPCCModel, MPCCModel, MPCCModelMeta, CCType
# constructors and verticalization
export MPCCModelVarCon, vertical_form, is_vertical
# API for MPCCs
export comp_left, comp_left!, comp_right, comp_right!
export lcomp_left, lcomp_left!, lcomp_right, lcomp_right!
export comp_res_left, comp_res_left!, comp_res_right, comp_res_right!
export comp_res_prod!
export jac_comp_left_structure,
    jac_comp_left_structure!, jac_comp_right_structure, jac_comp_right_structure!
export jac_comp_left_coord,
    jac_comp_left_coord!, jac_comp_right_coord, jac_comp_right_coord!
export jac_comp_left, jac_comp_right
export comp_residual, comp_residual_product, comp_residual_sum
end
