include("hard-search.jl")
using .HardCaseSearch

function main_reductions(args)
    "--help" in args && return println(
        "search-reductions.jl --out=DIR [--encodings=separate,shared] [--counts=1,2,3] [--plateaus=equal,crossing] [--starts=flat,witness,perturbed_witness] [--seeds=20261025,20261026,20261027] [--no-reference] [--max-iter=500] [--max-wall=60] [--reference-iter=2000] [--reference-wall=180] [--trace-every=10] [--resume] | --summarize=DIR",
    )
    values = Dict{String,String}()
    resume = false
    reference = true
    for arg in args
        if arg == "--resume"
            resume = true
        elseif arg == "--no-reference"
            reference = false
        elseif startswith(arg, "--") && occursin('=', arg)
            k, v = split(arg[3:end], '='; limit = 2)
            haskey(values, k) && throw(ArgumentError("duplicate option"))
            values[k] = v
        else
            throw(ArgumentError("invalid argument"))
        end
    end
    if haskey(values, "summarize")
        length(values)==1 && !resume ||
            throw(ArgumentError("summarize accepts no other options"))
        return summarize_reductions(values["summarize"])
    end
    haskey(values, "out") || throw(ArgumentError("--out is required"))
    kwargs = Dict{Symbol,Any}()
    for (key, value) in values
        key == "out" && continue
        if key in ("encodings", "plateaus", "starts")
            kwargs[Symbol(key)] = Symbol.(split(value, ','))
        elseif key in ("counts", "seeds")
            kwargs[Symbol(key)] = parse.(Int, split(value, ','))
        elseif key in ("max-iter", "reference-iter", "trace-every")
            kwargs[Symbol(replace(key, '-'=>'_'))] = parse(Int, value)
        elseif key in ("max-wall", "reference-wall")
            kwargs[key=="max-wall" ? :max_wall_time : :reference_wall_time] =
                parse(Float64, value)
        else
            throw(ArgumentError("unknown option"))
        end
    end
    return run_reduction_search(values["out"]; kwargs..., resume, reference)
end

abspath(PROGRAM_FILE) == abspath(@__FILE__) && main_reductions(ARGS)
