using Test
include("run-studies.jl")

function bus_injections(result)
    d, x = result.data, result.stats.solution
    l = transmission_layout(d)
    p, q = zeros(length(d.buses)), zeros(length(d.buses))
    for (i, c) in enumerate(d.controllers)
        p[c.bus] += x[l.p[i]]
        q[c.bus] += x[l.q[i]]
    end
    return p, q
end

@testset "Population at fixed aggregate size" begin
    for network in (:ieee14, :ieee118)
        base = solve_transmission(
            pglib_control_case(network);
            verbose = false,
            require_targets = true,
        )
        for copies in (2, 4)
            data = controller_population_case(base.data; copies)
            result = solve_transmission(data; verbose = false, require_targets = true)
            @test length(data.controllers) == 3*copies
            @test length(transmission_layout(data).r) == 18*copies
            @test sum(c.smax for c in data.controllers) ≈
                  sum(c.smax for c in base.data.controllers)
            @test sum(c.p_available for c in data.controllers) ≈
                  sum(c.p_available for c in base.data.controllers)
            @test bus_injections(result)[1] ≈ bus_injections(base)[1] atol = 1e-6
            @test bus_injections(result)[2] ≈ bus_injections(base)[2] atol = 1e-6
            @test obj(result.model, result.stats.solution) ≈
                  obj(base.model, base.stats.solution) atol = 1e-4
        end
    end
end

@testset "Placement holds population, profiles and capacity fixed" begin
    for network in (:ieee14, :ieee118)
        base = controller_placement_case(network)
        for placement in (:clustered, :colocated)
            data = controller_placement_case(network; placement)
            @test data.buses == base.buses
            @test data.branches == base.branches
            @test data.generators == base.generators
            @test [Base.structdiff(c, (bus = c.bus,)) for c in data.controllers] == [Base.structdiff(c, (bus = c.bus,)) for c in base.controllers]
            result = solve_transmission(data; verbose = false)
            @test maximum(values(result.residuals)) < 1e-5
            @test [c.vv.region for c in result.coverage.controllers] == [:segment_3, :segment_1, :below]
            @test [c.vw.region for c in result.coverage.controllers] == [:segment_1, :below, :below]
            @test result.coverage.controllers[1].vw.fraction ≈ 0.25 atol = 1e-4
            if placement == :colocated
                @test length(unique(c.voltage for c in result.coverage.controllers)) == 1
                # Heterogeneous laws can occupy different regions at one voltage.
                @test length(unique(c.vv.region for c in result.coverage.controllers)) == 3
                homogeneous = solve_transmission(
                    controller_placement_case(network; placement, profiles = :homogeneous);
                    verbose = false,
                )
                @test length(
                    unique(c.vv.region for c in homogeneous.coverage.controllers),
                ) == 1
                @test all(c -> c.vv.region == :segment_3, homogeneous.coverage.controllers)
                qnorm = [
                    c.q/d.smax for (c, d) in
                    zip(homogeneous.coverage.controllers, homogeneous.data.controllers)
                ]
                @test maximum(qnorm)-minimum(qnorm) < 1e-6
            end
        end
        for penetration in (0.5, 2.0)
            data = controller_placement_case(network; penetration)
            @test sum(c.smax for c in data.controllers) ≈
                  penetration*sum(c.smax for c in base.controllers)
            @test [c.bus for c in data.controllers] == [c.bus for c in base.controllers]
            result = solve_transmission(data; verbose = false)
            @test maximum(values(result.residuals)) < 1e-5
        end
        if network == :ieee118
            # An observed knee produced by electrical coupling, without fixing
            # voltage or selecting a sector using a desired curve region.
            knee = solve_transmission(
                controller_placement_case(
                    network;
                    placement = :clustered,
                    profiles = :homogeneous,
                );
                verbose = false,
            )
            @test [c.vv.region for c in knee.coverage.controllers] == [:segment_3, :segment_2, :knot_3]
            @test knee.coverage.controllers[3].knot_distance.vv <= 1e-6
        end
    end
end

@testset "Growing fleets on nested distinct sites" begin
    for network in (:ieee14, :ieee118)
        reference = controller_placement_case(network)
        for placement in (:dispersed, :clustered)
            previous = Int[]
            for count in (1, 3, 6, 12)
                data = controller_fleet_case(network; placement, count)
                sites = [c.bus for c in data.controllers]
                @test length(unique(sites)) == count
                @test sites[1:length(previous)] == previous
                @test !(data.reference_bus in sites)
                @test sum(c.smax for c in data.controllers) ≈
                      sum(c.smax for c in reference.controllers)
                @test sum(c.p_available for c in data.controllers) ≈
                      sum(c.p_available for c in reference.controllers)
                normalized = [c.vv.values/c.smax for c in data.controllers]
                @test all(v -> v ≈ first(normalized), normalized)
                result = solve_transmission(data; verbose = false)
                @test maximum(values(result.residuals)) < 1e-5
                @test result.coverage.targets_met === missing
                previous = sites
            end
        end
    end
end

function check_isolation(result, spec)
    network = result.coverage.network
    margins = []
    if spec.kind == :bus
        append!(
            margins,
            [getproperty(b, spec.limit) for b in network.buses if b.id != spec.id],
        )
    elseif spec.kind == :generator
        keys = spec.limit == :p_upper ? (:p_lower, :p_upper) : (:q_lower, :q_upper)
        for g in network.generators
            (spec.limit == :p_upper ? g.fixed_p : g.fixed_q) && continue
            append!(
                margins,
                [getproperty(g, k) for k in keys if !(g.id == spec.id && k == spec.limit)],
            )
        end
    elseif spec.field == :rate
        for b in network.branches
            append!(
                margins,
                [
                    getproperty(b, k) for
                    k in (:from, :to) if !(b.id == spec.id && k == spec.limit)
                ],
            )
        end
    else
        for b in network.branches
            append!(
                margins,
                [
                    getproperty(b, k) for k in (:angle_lower, :angle_upper) if
                    !(b.id == spec.id && k == spec.limit)
                ],
            )
        end
    end
    @test minimum(margins) > 1e-4
    if spec.name == :thermal_from
        # Stronger isolation: every other nonfixed network constraint is slack.
        @test minimum(min(b.lower, b.upper) for b in network.buses) > 1e-4
        @test minimum(min(b.angle_lower, b.angle_upper) for b in network.branches) > 1e-4
        @test minimum(min(g.q_lower, g.q_upper) for g in network.generators if !g.fixed_q) >
              1e-4
        @test minimum(min(g.p_lower, g.p_upper) for g in network.generators if !g.fixed_p) >
              1e-4
    end
end

@testset "Isolated network RHS sensitivities" begin
    for spec in network_limit_studies()
        @testset "$(spec.name)" begin
            result = sensitivity_study(spec.name)
            @test result.costs[1] > result.costs[2]+1e-6
            @test result.costs[2] > result.costs[3]+1e-6
            @test all(isfinite, result.slopes)
            @test minimum(result.slopes) > 0
            for r in result.results
                @test r.coverage.targets_met === true
                @test maximum(values(r.residuals)) < 1e-5
                check_isolation(r, spec)
            end
            # Check that monotone response persists at half the perturbation
            # size. Do not equate these finite differences with NLP duals.
            half = sensitivity_study(spec.name; step_scale = 0.5, counterfactual = false)
            @test half.costs[1] > half.costs[2]+1e-6
            @test half.costs[2] > half.costs[3]+1e-6
            controlled = result.results[2]
            @test obj(result.dispatchable.model, result.dispatchable.stats.solution) <=
                  result.costs[2]+1e-4
            @test controlled.data.buses == result.dispatchable.data.buses
            @test controlled.data.generators == result.dispatchable.data.generators
            @test controlled.data.branches == result.dispatchable.data.branches
            println((study = spec.name, costs = result.costs, slopes = result.slopes))
        end
    end
end
