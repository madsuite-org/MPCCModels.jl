struct MPCCModelMeta{T,VT,MT<:AbstractNLPModelMeta{T,VT}} <: AbstractNLPModelMeta{T,VT}
    nlp_meta::Base.RefValue{MT}

    ncc::Int
    ncon::Int # This may or may not be different depending on the type of constraints
    nlin::Int # This may or may not be different depending on the type of constraints
    nnln::Int # This may or may not be different depending on the type of constraints

    nnzj::Int
    lin_nnzj::Int
    nln_nnzj::Int
    comp_left_nnzj::Int
    comp_right_nnzj::Int

    lin::IndexSet
    nln::IndexSet

    c_lin::IndexSet
    c_nln::IndexSet
    cc_l::IndexSet
    cc_r::IndexSet

    # Index Sets of complementarity variables
    ind_cc1::IndexSet
    ind_cc2::IndexSet
    cc_types::Vector{CCType} # VarCon, VarVar, ConCon

    # Index Sets of noncomplementarity variables and constraints
    ind_x::IndexSet
    ind_c::IndexSet

    # Index set of the jacobian triplets to keep.
    ind_j_triplets::IndexSet
    ind_j_lin_triplets::IndexSet
    ind_j_nln_triplets::IndexSet
    ind_j_comp_left_triplets::IndexSet
    ind_j_comp_right_triplets::IndexSet
    ind_j_comp_left_row_map::Dict{Int,Int}
    ind_j_comp_right_row_map::Dict{Int,Int}

    ind_j_lin_row_map::Dict{Int,Int}
    ind_j_nln_row_map::Dict{Int,Int}
end

######################## Typed gets #######################
for field in fieldnames(NLPModelMeta) ∪ fieldnames(MPCCModelMeta)
    meth = Symbol("get_", field)
    if field ∈ fieldnames(NLPModelMeta)
        if field ∈ fieldnames(MPCCModelMeta)
            @eval NLPModels.$meth(meta::MPCCModelMeta) =
                getproperty(meta, $(QuoteNode(field)))
        else
            @eval NLPModels.$meth(meta::MPCCModelMeta) = $meth(meta.nlp_meta[])
        end
        @eval NLPModels.$meth(mpcc::AbstractMPCCModel) = $meth(mpcc.meta)
    else
        @eval begin
            """
                  $($meth)(nlp)
                  $($meth)(meta)
                  Return the value $($(QuoteNode(field))) from meta or nlp.meta.
            """
            $meth(meta::MPCCModelMeta) = getproperty(meta, $(QuoteNode(field)))
        end
        @eval $meth(mpcc::AbstractMPCCModel) = $meth(mpcc.meta)
        @eval export $meth
    end
end
