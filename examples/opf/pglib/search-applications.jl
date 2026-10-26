include("hard-search.jl")
using .HardCaseSearch

function main_applications(args)
    "--help" in args && return println(
        "search-applications.jl --out=DIR [--network=ieee118|ieee300] [--families=renewable_surplus,reactive_support,export_corridor] [--levels=nominal,elevated,severe] [--profiles=current,ratio_one] [--seeds=20261025,20261026] [--max-iter=500] [--max-wall=60] [--trace-every=0] [--resume] | --summarize=DIR",
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
        return summarize_applications(values["summarize"])
    end
    haskey(values, "out") || throw(ArgumentError("--out is required"))
    kwargs=Dict{Symbol,Any}()
    for (k, v) in values
        k=="out" && continue
        if k=="network"
            kwargs[:network]=Symbol(v)
        elseif k in ("families", "levels", "profiles")
            kwargs[Symbol(k)]=Symbol.(split(v, ','))
        elseif k=="seeds"
            kwargs[:seeds]=parse.(Int, split(v, ','))
        elseif k in ("max-iter", "trace-every")
            kwargs[Symbol(replace(k, '-'=>'_'))]=parse(Int, v)
        elseif k=="max-wall"
            kwargs[:max_wall_time]=parse(Float64, v)
        else
            throw(ArgumentError("unknown option"))
        end
    end
    return run_application_search(values["out"]; kwargs..., resume)
end
abspath(PROGRAM_FILE)==abspath(@__FILE__) && main_applications(ARGS)
