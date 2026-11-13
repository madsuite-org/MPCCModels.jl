using Test
include("solve.jl")

@testset "PGLib solved activity and matched controls" begin
    results = Dict()
    for spec in transmission_cases()
        @testset "$(spec.network)/$(spec.scenario)/$(spec.laws)" begin
            data =
                spec.laws == :canonical ? transmission_case(spec.network) :
                pglib_control_case(spec.network; laws = spec.laws, scenario = spec.scenario)
            result = solve_transmission(data; verbose = false, require_targets = true)
            results[(spec.network, spec.scenario, spec.laws)] = result
            @test result.coverage.targets_met === true
            @test maximum(values(result.residuals)) < 1e-5
            @test successful_status(result.raw.status)
            @test successful_status(result.stats.status)
            @test isempty(result.coverage.network_misses)
            @test length(result.coverage.controllers) == length(data.controllers)
            if spec.laws != :canonical
                @test length(data.targets) == 3
                @test all(isempty(c.misses) for c in result.coverage.controllers)
            end
        end
    end
    for network in TransmissionOPF.LEGACY_NETWORKS
        baseline = results[(network, :mixed, :dispatchable)]
        hardware = [
            (c.bus, c.p_available, c.smax, c.qmin, c.qmax, c.cost, c.quadratic_cost) for
            c in baseline.data.controllers
        ]
        for laws in (:vv, :vw, :both)
            result = results[(network, :mixed, laws)]
            @test [
                (c.bus, c.p_available, c.smax, c.qmin, c.qmax, c.cost, c.quadratic_cost) for
                c in result.data.controllers
            ] == hardware
            @test result.data.buses == baseline.data.buses
            @test result.data.branches == baseline.data.branches
            @test result.data.generators == baseline.data.generators
            # Added laws restrict the same hardware feasible set. The observed
            # local solutions must respect the expected objective ordering here.
            @test obj(result.model, result.stats.solution) >=
                  obj(baseline.model, baseline.stats.solution)-1e-4
        end
    end
    # A feasible solution can miss the scientific coverage target. Assert that
    # independent target mutation catches this without changing the model.
    result = results[(:ieee14, :mixed, :both)]
    wrong = copy(result.data.targets)
    wrong[1] = merge(wrong[1], (vv_region = :segment_2, vv_position = nothing))
    data = merge(result.data, (targets = wrong,))
    @test maximum(
        values(transmission_residuals(result.model, data, result.stats.solution)),
    ) < 1e-5
    @test transmission_coverage(data, result.stats.solution).targets_met === false
    wrong_network = [(kind = :branch, id = 1, limit = :from, state = :tight)]
    @test transmission_coverage(
        merge(result.data, (network_targets = wrong_network,)),
        result.stats.solution,
    ).targets_met === false
end

@testset "Limit perturbations change the intended dispatch" begin
    # Strict competitors are slack in these two scenarios. Small rating/profile
    # relaxations must change controller 3 output and lower production cost.
    for scenario in (:watt_limited, :capability_limited)
        data = pglib_control_case(:ieee14; scenario = scenario)
        original = solve_transmission(data; verbose = false, require_targets = true)
        controllers = copy(data.controllers)
        c = controllers[3]
        if scenario == :watt_limited
            controllers[3] = merge(c, (vw = opf_curve(c.vw.knots, c.vw.values .+ 0.001),))
        else
            controllers[3] = merge(c, (smax = c.smax+0.001,))
        end
        perturbed = merge(
            data,
            (
                controllers = controllers,
                targets = [],
                network_targets = [],
                name = Symbol(scenario, "_relaxed"),
            ),
        )
        changed = solve_transmission(perturbed; verbose = false)
        l = transmission_layout(data)
        @test changed.stats.solution[l.p[3]] > original.stats.solution[l.p[3]]+1e-4
        @test obj(changed.model, changed.stats.solution) <
              obj(original.model, original.stats.solution)-1e-3
    end
end
