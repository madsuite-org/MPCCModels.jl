# Manual independent canonical validation with complete numerical receipts.
# julia --project=examples/opf/pglib examples/opf/pglib/hard-cases/validate-ieee300.jl OUT
using TOML, PowerModels, Ipopt, JuMP, NLPModels
include("../hard-search.jl")
using .HardCaseSearch
const H=HardCaseSearch
const T=H.TransmissionOPF

function validate_ieee300(directory)
    ispath(directory) && throw(ArgumentError("choose a new output directory"))
    directory=abspath(directory)
    mkpath(directory)
    H._capture_environment(directory, H._environment())
    cp(@__FILE__, joinpath(directory, "validation-driver.jl"))
    data=T.transmission_case(:ieee300)
    for name in (data.provenance.file, "SHA256SUMS")
        cp(joinpath(H.HERE, "data", name), joinpath(directory, "source_data", name))
    end
    own=run_trial(data, nothing, solver_profile(:current), joinpath(directory, "canonical"))
    @assert own["solver_success"] && own["physically_feasible"]
    pm=PowerModels.solve_ac_opf(
        deepcopy(data.pm),
        JuMP.optimizer_with_attributes(
            Ipopt.Optimizer,
            "print_level"=>0,
            "tol"=>1e-9,
            "bound_relax_factor"=>0.0,
        ),
    )
    @assert pm["termination_status"] in
            (JuMP.MOI.LOCALLY_SOLVED, JuMP.MOI.ALMOST_LOCALLY_SOLVED)
    l=T.transmission_layout(data)
    model=T.TransmissionOPFModel(data)
    x=copy(get_x0(model))
    for (i, b) in enumerate(data.buses)
        r=pm["solution"]["bus"][string(b.id)]
        x[l.v[i]], x[l.theta[i]]=r["vm"], r["va"]
    end
    for (i, g) in enumerate(data.generators)
        r=pm["solution"]["gen"][string(g.id)]
        x[l.pg[i]], x[l.qg[i]]=r["pg"], r["qg"]
    end
    metrics=H._metrics(model, data, x, 1e-7)
    @assert metrics["physically_feasible"]
    @assert isapprox(metrics["objective"], pm["objective"]; atol = 1e-5)
    @assert isapprox(metrics["objective"], own["objective"]; atol = 1e-4)
    H._write(
        joinpath(directory, "canonical-powermodels.toml"),
        merge(
            metrics,
            Dict(
                "x"=>x,
                "point_bits_sha256"=>bytes2hex(H.sha256(join(bitstring.(x), "\n"))),
                "termination_status"=>string(pm["termination_status"]),
                "objective_powermodels"=>pm["objective"],
                "tolerance"=>1e-7,
                "validation_solver"=>"PowerModels ACPPowerModel / Ipopt",
                "ipopt_version"=>string(pkgversion(Ipopt)),
                "validation_options"=>Dict("tol"=>1e-9, "bound_relax_factor"=>0.0),
            ),
        ),
    )
    println((
        canonical = own["objective"],
        powermodels = pm["objective"],
        residuals = metrics["residuals"],
    ))
    return nothing
end

if abspath(PROGRAM_FILE)==abspath(@__FILE__)
    length(ARGS)==1 || error("expected a new output directory")
    validate_ieee300(only(ARGS))
end
