include("hard-search.jl")
using .HardCaseSearch

function main_expansions(args)
    "--help" in args && return println(
        "search-expansions.jl --out=DIR [--network=ieee118|ieee300] [--kind=coverage|fleet|reserve|policy_matrix] [--profiles=current,ratio_one] [--references=FILE] [--max-iter=500] [--max-wall=60] [--resume] | --summarize=DIR",
    )
    values=Dict{String,String}()
    resume=false
    for arg in args
        if arg=="--resume"
            resume=true
        elseif startswith(arg, "--") && occursin('=', arg)
            k, v=split(arg[3:end], '='; limit = 2)
            haskey(values, k) && throw(ArgumentError("duplicate option"))
            values[k]=v
        else
            throw(ArgumentError("invalid argument"))
        end
    end
    if haskey(values, "summarize")
        length(values)==1 && !resume ||
            throw(ArgumentError("summarize accepts no other options"))
        return summarize_expansions(values["summarize"])
    end
    haskey(values, "out") || throw(ArgumentError("--out is required"))
    all(
        k->k in
           ("out", "network", "kind", "profiles", "max-iter", "max-wall", "references"),
        keys(values),
    ) || throw(ArgumentError("unknown option"))
    kind=Symbol(get(values, "kind", "coverage"))
    kwargs=Dict{Symbol,Any}()
    haskey(values, "references") && (kwargs[:reference_receipt]=values["references"])
    haskey(values, "profiles") &&
        (kwargs[:profiles]=Symbol.(split(values["profiles"], ',')))
    haskey(values, "max-iter") && (kwargs[:max_iter]=parse(Int, values["max-iter"]))
    haskey(values, "max-wall") &&
        (kwargs[:max_wall_time]=parse(Float64, values["max-wall"]))
    return run_expansion_search(
        values["out"];
        specs = HardCaseSearch.TransmissionOPF.application_expansion_specs(
            kind;
            network = Symbol(get(values, "network", "ieee118")),
        ),
        kwargs...,
        resume,
    )
end
abspath(PROGRAM_FILE)==abspath(@__FILE__) && main_expansions(ARGS)
