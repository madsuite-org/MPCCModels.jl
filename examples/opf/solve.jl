# From the repository root:
# julia --project=examples/opf examples/opf/solve.jl [case_name | all]
using CCOpt, MPCCModels, NLPModels

include("balanced-ac-opf.jl")
using .BalancedACOPF

function solve_opf_case(name::Symbol; verbose::Bool = true, polish::Bool = true)
    data = balanced_ac_opf_case(name)
    mpcc = BalancedACOPFModel(data)
    # At a breakpoint both hinge members can be small, so a small product
    # alone need not give an equally small error in the physical curve.
    options = CCOpt.RelaxationOptions(;
        sigma_min = 1e-14,
        relaxation_update = CCOpt.ProportionalRelaxationUpdate{Float64}(
            sigma_min = 1e-14,
            sigma_mu_ratio = 0.01,
        ),
        print_level = CCOpt.MadNLP.ERROR,
    )
    solver = CCOpt.RelaxationSolver(
        mpcc;
        solver_opts = options,
        bound_relax_factor = 0.0,
        # All quantities are per unit. Avoid moving zero hinge members farther
        # than the deliberately close left/right knot-neighbor offsets.
        bound_push = 1e-6,
        bound_fac = 1e-6,
        tol = 1e-10,
        max_iter = 300,
        print_level = CCOpt.MadNLP.ERROR,
    )
    homotopy = CCOpt.solve_homotopy!(solver)
    successful_status(status) =
        status in (CCOpt.MadNLP.SOLVE_SUCCEEDED, CCOpt.MadNLP.SOLVED_TO_ACCEPTABLE_LEVEL)
    stats = homotopy
    x = stats.solution
    residuals = opf_residuals(mpcc, x, data)
    coverage = opf_coverage(data, x)
    homotopy_residuals, homotopy_coverage = residuals, coverage
    polished = false
    # A product-based homotopy stopping test can leave larger physical curve
    # errors near a biactive knot. Polish on the branch selected by the iterate,
    # without consulting a reference point or target to choose that branch.
    # This is not a full MPCC stationarity/crossover test.
    if polish &&
       successful_status(homotopy.status) &&
       (maximum(values(residuals)) > 1e-5 || coverage.targets_met !== true)
        mask = Vector{Bool}(comp_left(mpcc, x) .> comp_right(mpcc, x))
        branch = CCOpt.BranchNLP(mpcc, mask)
        get_x0(branch) .= x
        stats = CCOpt.MadNLP.madnlp(
            branch;
            bound_relax_factor = 0.0,
            bound_push = 1e-6,
            bound_fac = 1e-6,
            tol = 1e-10,
            max_iter = 300,
            print_level = CCOpt.MadNLP.ERROR,
        )
        x = stats.solution
        residuals = opf_residuals(mpcc, x, data)
        coverage = opf_coverage(data, x)
        polished = true
    end
    successful = successful_status(homotopy.status) && successful_status(stats.status)
    feasible = maximum(values(residuals)) <= 1e-5
    covered = coverage.targets_met === true
    if verbose || !(successful && feasible && covered)
        println((
            case = name,
            homotopy_status = homotopy.status,
            status = stats.status,
            polished = polished,
            homotopy_residuals = homotopy_residuals,
            homotopy_targets_met = homotopy_coverage.targets_met,
            objective = obj(mpcc, x),
            residuals = residuals,
            targets_met = coverage.targets_met,
        ))
        for device in coverage.controllers
            println(device)
        end
    end
    # Independently check the original equations and curves. Passing these
    # checks establishes numerical feasibility, not global optimality.
    successful || error("OPF solve failed for $name")
    feasible || error("OPF residual check failed for $name")
    covered || error("OPF coverage target missed for $name")
    return (
        model = mpcc,
        data = data,
        stats = stats,
        homotopy = homotopy,
        homotopy_residuals = homotopy_residuals,
        homotopy_coverage = homotopy_coverage,
        polished = polished,
        residuals = residuals,
        coverage = coverage,
    )
end

function main(args)
    length(args) <= 1 || throw(ArgumentError("expected a case name or all"))
    names =
        isempty(args) ? (:curtailment,) :
        only(args) == "all" ? balanced_ac_opf_cases() : (Symbol(only(args)),)
    for name in names
        solve_opf_case(name)
    end
    return nothing
end

if abspath(PROGRAM_FILE) == abspath(@__FILE__)
    main(ARGS)
end
