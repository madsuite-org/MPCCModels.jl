# Optional environment: julia --project=examples/opf/pglib examples/opf/pglib/solve.jl
using CCOpt, MPCCModels, NLPModels

include("transmission-opf.jl")
using .TransmissionOPF

function successful_status(status)
    return status in (CCOpt.MadNLP.SOLVE_SUCCEEDED, CCOpt.MadNLP.SOLVED_TO_ACCEPTABLE_LEVEL)
end

"""Solve from the model's flat-voltage start and check original feasibility.

Optional branch refinement selects its sector only from the homotopy iterate.
Both stages and diagnostics are retained. This is not a full MPCC stationarity
or global optimality certificate. Coverage targets are required only when the
data declares them; exploratory solves report `missing` otherwise.
"""
function solve_transmission(data; verbose = true, polish = true, require_targets = false)
    model = TransmissionOPFModel(data)
    if model isa AbstractMPCCModel
        options = CCOpt.RelaxationOptions(;
            sigma_min = 1e-14,
            relaxation_update = CCOpt.ProportionalRelaxationUpdate{Float64}(;
                sigma_min = 1e-14,
                sigma_mu_ratio = 0.01,
            ),
            print_level = CCOpt.MadNLP.ERROR,
        )
        solver = CCOpt.RelaxationSolver(
            model;
            solver_opts = options,
            bound_relax_factor = 0.0,
            bound_push = 1e-6,
            bound_fac = 1e-6,
            tol = 1e-9,
            max_iter = 500,
            print_level = CCOpt.MadNLP.ERROR,
        )
        raw = CCOpt.solve_homotopy!(solver)
    else
        raw = CCOpt.MadNLP.madnlp(
            model;
            bound_relax_factor = 0.0,
            bound_push = 1e-6,
            bound_fac = 1e-6,
            tol = 1e-9,
            max_iter = 500,
            print_level = CCOpt.MadNLP.ERROR,
        )
    end
    stats = raw
    raw_residuals = transmission_residuals(model, data, raw.solution)
    raw_coverage = transmission_coverage(data, raw.solution)
    polished = false
    if model isa AbstractMPCCModel &&
       polish &&
       successful_status(raw.status) &&
       (maximum(values(raw_residuals)) > 1e-5 || raw_coverage.targets_met === false)
        branch = CCOpt.BranchNLP(
            model,
            Vector{Bool}(comp_left(model, raw.solution) .> comp_right(model, raw.solution)),
        )
        get_x0(branch) .= raw.solution
        stats = CCOpt.MadNLP.madnlp(
            branch;
            bound_relax_factor = 0.0,
            bound_push = 1e-6,
            bound_fac = 1e-6,
            tol = 1e-9,
            max_iter = 500,
            print_level = CCOpt.MadNLP.ERROR,
        )
        polished = true
    end
    residuals = transmission_residuals(model, data, stats.solution)
    coverage = transmission_coverage(data, stats.solution)
    valid =
        successful_status(raw.status) &&
        successful_status(stats.status) &&
        maximum(values(residuals)) <= 1e-5 &&
        coverage.targets_met !== false &&
        (!require_targets || coverage.targets_met === true)
    if verbose || !valid
        println((
            case = data.name,
            status = stats.status,
            raw_status = raw.status,
            objective = obj(model, stats.solution),
            polished = polished,
            residuals = residuals,
            targets_met = coverage.targets_met,
            nvar = get_nvar(model),
            ncon = get_ncon(model),
            ncc = length(transmission_layout(data).r),
        ))
        foreach(println, coverage.controllers)
        isempty(coverage.network_misses) ||
            println((network_misses = coverage.network_misses,))
    end
    valid || error("transmission solve/feasibility/coverage failed for $(data.name)")
    return (;
        data,
        model,
        stats,
        raw,
        polished,
        raw_residuals,
        raw_coverage,
        residuals,
        coverage,
    )
end

function main(args)
    if args == ["all"]
        for spec in transmission_cases()
            data =
                spec.laws == :canonical ? transmission_case(spec.network) :
                pglib_control_case(spec.network; laws = spec.laws, scenario = spec.scenario)
            solve_transmission(data; require_targets = true)
        end
        return nothing
    end
    network = isempty(args) ? :ieee14 : Symbol(args[1])
    law = length(args) <= 1 ? :both : Symbol(args[2])
    scenario = length(args) <= 2 ? :mixed : Symbol(args[3])
    length(args) <= 3 || throw(ArgumentError("expected network, optional law and scenario"))
    law == :canonical &&
        scenario != :mixed &&
        throw(ArgumentError("canonical cases have no overlay scenario"))
    data =
        law == :canonical ? transmission_case(network) :
        pglib_control_case(network; laws = law, scenario = scenario)
    return solve_transmission(data)
end

if abspath(PROGRAM_FILE) == abspath(@__FILE__)
    main(ARGS)
end
