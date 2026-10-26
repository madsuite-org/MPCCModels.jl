include("hard-search.jl")
using .HardCaseSearch

function main_search(args)
    if "--help" in args
        println(
            "search-hard-cases.jl --out=DIR [--caps=.80,.82,.84] [--starts=flat,neighbor,perturbed_neighbor,witness] [--profiles=defaults,current,looser_inner,ratio_one,higher_floor] [--seed=20261024] [--repetitions=1] [--max-iter=500] [--max-wall=60] [--resume] [--no-warmup]",
        )
        println(
            "search-hard-cases.jl --transitions --out=DIR [--offsets=-.0001,0,.0001] [--qmaxes=.2,.35,.5] [--seeds=20261024,20261025,20261026] [--knee=1.02] [--max-iter=500] [--max-wall=60] [--resume]",
        )
        println("search-hard-cases.jl --replay=TRIAL_DIR --out=NEW_DIR")
        println("search-hard-cases.jl --summarize=SEARCH_DIR")
        return nothing
    end
    values = Dict{String,String}()
    flags = Set{String}()
    for arg in args
        if arg in ("--resume", "--no-warmup", "--transitions")
            push!(flags, arg)
        elseif startswith(arg, "--") && occursin('=', arg)
            k, v = split(arg[3:end], '='; limit = 2)
            haskey(values, k) && throw(ArgumentError("duplicate option $k"))
            values[k] = v
        else
            throw(ArgumentError("invalid argument $arg"))
        end
    end
    allowed = (
        "out",
        "offsets",
        "qmaxes",
        "seeds",
        "knee",
        "caps",
        "starts",
        "profiles",
        "seed",
        "repetitions",
        "max-iter",
        "max-wall",
        "replay",
        "summarize",
    )
    all(k -> k in allowed, keys(values)) || throw(ArgumentError("unknown option"))
    if haskey(values, "summarize")
        length(values) == 1 && all(f -> f == "--transitions", flags) ||
            throw(ArgumentError("summarize accepts no other options"))
        return "--transitions" in flags ? summarize_transitions(values["summarize"]) :
               summarize_search(values["summarize"])
    end
    haskey(values, "out") || throw(ArgumentError("--out is required"))
    if haskey(values, "replay")
        length(values) == 2 && isempty(flags) ||
            throw(ArgumentError("replay accepts only --out"))
        return replay_trial(values["replay"], values["out"])
    end
    if "--transitions" in flags
        all(
            k -> k in ("out", "offsets", "qmaxes", "seeds", "knee", "max-iter", "max-wall"),
            keys(values),
        ) && !("--no-warmup" in flags) ||
            throw(ArgumentError("unsupported transition-search option"))
        transition_kwargs = Dict{Symbol,Any}()
        for key in ("offsets", "qmaxes", "seeds")
            haskey(values, key) && (
                transition_kwargs[Symbol(key)] =
                    parse.(key == "seeds" ? Int : Float64, split(values[key], ','))
            )
        end
        for (key, dest, type) in (
            ("knee", :knee, Float64),
            ("max-iter", :max_iter, Int),
            ("max-wall", :max_wall_time, Float64),
        )
            haskey(values, key) && (transition_kwargs[dest] = parse(type, values[key]))
        end
        return run_transition_search(
            values["out"];
            transition_kwargs...,
            resume = "--resume" in flags,
        )
    end
    any(k -> k in ("offsets", "qmaxes", "seeds", "knee"), keys(values)) &&
        throw(ArgumentError("transition axes require --transitions"))
    kwargs = Dict{Symbol,Any}()
    for (key, dest) in
        (("caps", :capabilities), ("starts", :starts), ("profiles", :profiles))
        if haskey(values, key)
            kwargs[dest] =
                key == "caps" ? parse.(Float64, split(values[key], ',')) :
                Symbol.(split(values[key], ','))
        end
    end
    for (key, dest) in
        (("seed", :seed), ("repetitions", :repetitions), ("max-iter", :max_iter))
        haskey(values, key) && (kwargs[dest] = parse(Int, values[key]))
    end
    haskey(values, "max-wall") &&
        (kwargs[:max_wall_time] = parse(Float64, values["max-wall"]))
    return run_search(
        values["out"];
        kwargs...,
        resume = "--resume" in flags,
        warmup = !("--no-warmup" in flags),
    )
end

if abspath(PROGRAM_FILE) == abspath(@__FILE__)
    main_search(ARGS)
end
