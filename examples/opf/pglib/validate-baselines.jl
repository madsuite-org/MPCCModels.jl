# Independently solve the canonical formulation in PowerModels/Ipopt, and
# evaluate our equations at that solution as well as our own flat-start solve.
using Test, PowerModels, Ipopt, JuMP
include("solve.jl")

@testset "Canonical PGLib baselines against PowerModels" begin
    for network in (:ieee14, :ieee118, :ieee14_api, :ieee118_api, :ieee300)
        @testset "$network" begin
            d = transmission_case(network)
            result = solve_transmission(d; verbose = false)
            pm = PowerModels.solve_ac_opf(
                deepcopy(d.pm),
                JuMP.optimizer_with_attributes(
                    Ipopt.Optimizer,
                    "print_level" => 0,
                    "tol" => 1e-9,
                    "bound_relax_factor" => 0.0,
                ),
            )
            @test pm["termination_status"] in
                  (JuMP.MOI.LOCALLY_SOLVED, JuMP.MOI.ALMOST_LOCALLY_SOLVED)
            l = transmission_layout(d)
            xp = copy(get_x0(result.model))
            for (i, b) in enumerate(d.buses)
                r = pm["solution"]["bus"][string(b.id)]
                xp[l.v[i]], xp[l.theta[i]] = r["vm"], r["va"]
            end
            for (i, g) in enumerate(d.generators)
                r = pm["solution"]["gen"][string(g.id)]
                xp[l.pg[i]], xp[l.qg[i]] = r["pg"], r["qg"]
            end
            @test maximum(values(transmission_residuals(result.model, d, xp))) < 1e-5
            @test obj(result.model, xp) ≈ pm["objective"] atol = 1e-5 rtol = 1e-10
            # This suite freezes cases for which the two local solves agree.
            # Agreement is evidence of consistency, not a global certificate.
            @test obj(result.model, result.stats.solution) ≈ pm["objective"] atol = 1e-4 rtol =
                1e-8
            println((
                network = network,
                ours = obj(result.model, result.stats.solution),
                powermodels = pm["objective"],
            ))
        end
    end
end
