# Typealias for sets of indices
const IndexSet = Vector{Int}

"""
  Enum for types of complementarity constraints
"""
@enum CCType::Clonglong begin
    VarVar=Clonglong(0)
    VarCon=Clonglong(1)
    ConVar=Clonglong(2)
    ConCon=Clonglong(3)
end

######################### Helper functions for AbstractMPCCModel #########################
function is_vertical(mpcc::AbstractMPCCModel)
    return all(map((x)->x==VarVar, get_cc_types(mpcc)))
end

"""
Return the unique variable indices that participate in complementarity constraints.
"""
function get_cc_var_indices(mpcc::AbstractMPCCModel)
    ind_cc1 = get_ind_cc1(mpcc)
    ind_cc2 = get_ind_cc2(mpcc)
    cc_types = get_cc_types(mpcc)
    ind_vars = Int[]
    for i in eachindex(cc_types)
        cc_types[i] in (VarVar, VarCon) && push!(ind_vars, ind_cc1[i])
        cc_types[i] in (VarVar, ConVar) && push!(ind_vars, ind_cc2[i])
    end
    return unique(ind_vars)
end
