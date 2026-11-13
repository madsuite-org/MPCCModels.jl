# Opt-in benchmark. No solves occur when loading the example module or its tests.
using CCOpt, Ipopt, MadNLP, JSON, JuMP, NLPModels, Pkg, SHA
include("../model.jl")
using .DroopExamples

function run_case(arguments = ARGS)
    length(arguments) >= 3 || error(
        "usage: run.jl CASE ccopt|ipopt-smooth|ipopt-relaxed OUTPUT [start|reference] [SECONDS]",
    )
    name, backend, output = Symbol(arguments[1]), arguments[2], abspath(arguments[3])
    backend in ("ccopt", "ipopt-smooth", "ipopt-relaxed") || error("unknown backend")
    start_kind = length(arguments)>=4 ? arguments[4] : "start"
    start_kind in ("start", "reference") || error("unknown start")
    seconds = length(arguments)>=5 ? parse(Float64, arguments[5]) : 60.0
    isfinite(seconds) && seconds>0 || error("invalid budget")
    ispath(output) && error("refusing to overwrite an existing receipt")
    data = droop_case(name)
    encoding = backend=="ccopt" ? :exact : backend=="ipopt-smooth" ? :smooth : :relaxed
    build_time =
        @elapsed built = build_droop(data; start = data.states[start_kind], encoding)
    record = Dict{String,Any}(
        "case"=>string(name),
        "backend"=>backend,
        "start"=>start_kind,
        "seconds_budget"=>seconds,
        "iteration_budget"=>2000,
        "epsilon"=>1e-7,
        "sigma"=>(encoding==:relaxed ? 1e-8 : nothing),
        "julia"=>string(VERSION),
        "build_seconds"=>build_time,
        "data_sha256"=>bytes2hex(
            sha256(read(joinpath(@__DIR__, "..", "data", "SHA256SUMS"))),
        ),
        "model_sha256"=>bytes2hex(sha256(read(joinpath(@__DIR__, "..", "model.jl")))),
        "replay_sha256"=>bytes2hex(sha256(read(joinpath(@__DIR__, "..", "replay.jl")))),
        "numerical_options"=>Dict(
            "ccopt_tol"=>1e-11,
            "ipopt_tol"=>1e-9,
            "bound_relax_factor"=>0.0,
            "ccopt_bound_push"=>1e-8,
            "ccopt_sigma_min"=>1e-14,
        ),
        "variables"=>built.nlp.meta.nvar,
        "constraints"=>built.nlp.meta.ncon,
        "complementarity_pairs"=>length(built.layout.pairs),
        "packages"=>Dict(
            p.name=>string(p.version) for p in values(Pkg.dependencies()) if p.name in (
                "MPCCModels",
                "CCOpt",
                "MadNLP",
                "Ipopt",
                "JuMP",
                "NLPModelsJuMP",
                "NLPModels",
            )
        ),
    )
    try
        if backend=="ccopt"
            options = CCOpt.RelaxationOptions(
                relaxation_update = CCOpt.ProportionalRelaxationUpdate(sigma_min = 1e-14),
            )
            barrier = MadNLP.MonotoneUpdate(1e-11, 10.0)
            barrier.mu_init = 1e-6
            record["barrier"] = string(barrier)
            solver = CCOpt.RelaxationSolver(
                built.mpcc;
                solver_opts = options,
                max_iter = 2000,
                max_wall_time = seconds,
                tol = 1e-11,
                acceptable_tol = 1e-11,
                bound_push = 1e-8,
                bound_fac = 1e-8,
                bound_relax_factor = 0.0,
                barrier = barrier,
            )
            record["solve_seconds"] = @elapsed stats = CCOpt.solve_homotopy!(solver)
            x = stats.solution[1:built.nlp.meta.nvar]
            record["status"] = string(stats.status)
            record["native_success"] =
                stats.status in (MadNLP.SOLVE_SUCCEEDED, MadNLP.SOLVED_TO_ACCEPTABLE_LEVEL)
            record["dual_feasibility"] = stats.dual_feas
        else
            set_optimizer(built.model, Ipopt.Optimizer)
            set_silent(built.model)
            for (key, value) in (
                ("mu_strategy", "adaptive"),
                ("max_iter", 2000),
                ("max_cpu_time", seconds),
                ("tol", 1e-9),
                ("acceptable_tol", 1e-9),
                ("bound_relax_factor", 0.0),
            )
                set_optimizer_attribute(built.model, key, value)
            end
            record["solve_seconds"] = @elapsed optimize!(built.model)
            record["status"] = string(termination_status(built.model))
            record["native_success"] = termination_status(built.model) in
            (MOI.LOCALLY_SOLVED, MOI.ALMOST_LOCALLY_SOLVED, MOI.OPTIMAL)
            has_values(built.model) || error("solver returned no primal values")
            x = value.(all_variables(built.model))
        end
        state = DroopExamples.physical_state(built, x)
        record["state"] = state
        record["physics"] = replay(data, state)
        record["residuals"] = model_residuals(built, x)
        record["objective_pu"] = obj(built.nlp, x)
        record["accepted"] =
            record["native_success"] &&
            record["physics"].valid &&
            record["residuals"].bounds<=1e-6 &&
            record["residuals"].constraints<=1e-5 &&
            record["residuals"].products<=1e-5
    catch error
        record["error"] = sprint(showerror, error)
        record["accepted"] = false
    end
    open(output, "w") do io
        return JSON.print(io, record, 2)
    end
    return println("receipt: ", output, "; accepted=", record["accepted"])
end

abspath(PROGRAM_FILE) == (@__FILE__) && run_case()
