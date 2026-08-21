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
