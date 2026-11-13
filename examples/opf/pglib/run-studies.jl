# julia --project=examples/opf/pglib examples/opf/pglib/run-studies.jl
include("solve.jl")

function sensitivity_study(name; step_scale = 1.0, counterfactual = true)
    results = [
        solve_transmission(
            network_limit_case(name; change, step_scale);
            verbose = false,
            require_targets = true,
        ) for change in (:tightened, :base, :relaxed)
    ]
    costs = [obj(r.model, r.stats.solution) for r in results]
    spec = only(filter(s -> s.name == name, network_limit_studies()))
    changes = diff(costs)
    # Positive values quantify the local cost of losing one unit of permitted
    # range. These are finite differences, not multipliers/global derivatives.
    slopes = (-changes[1]/(spec.step*step_scale), -changes[2]/(spec.step*step_scale))
    dispatchable =
        counterfactual ?
        solve_transmission(
            network_limit_case(name; laws = :dispatchable);
            verbose = false,
        ) : nothing
    return (; spec, results, costs, slopes, dispatchable)
end

function main_studies()
    for network in (:ieee14, :ieee118),
        placement in (:dispersed, :clustered, :colocated),
        profiles in (:heterogeneous, :homogeneous)

        data = controller_placement_case(network; placement, profiles)
        result = solve_transmission(data; verbose = false)
        println((
            case = data.name,
            objective = obj(result.model, result.stats.solution),
            controllers = result.coverage.controllers,
            network = result.coverage.network,
        ))
    end
    for network in (:ieee14, :ieee118)
        for copies in (1, 2, 4)
            result = solve_transmission(
                controller_population_case(pglib_control_case(network); copies);
                verbose = false,
                require_targets = true,
            )
            println((
                case = result.data.name,
                count = length(result.data.controllers),
                ncc = length(transmission_layout(result.data).r),
                objective = obj(result.model, result.stats.solution),
            ))
        end
        for penetration in (0.5, 2.0)
            result = solve_transmission(
                controller_placement_case(network; penetration);
                verbose = false,
            )
            println((
                case = result.data.name,
                objective = obj(result.model, result.stats.solution),
                controllers = result.coverage.controllers,
            ))
        end
        for placement in (:dispersed, :clustered), count in (1, 3, 6, 12)
            result = solve_transmission(
                controller_fleet_case(network; placement, count);
                verbose = false,
            )
            println((
                case = result.data.name,
                sites = [result.data.buses[c.bus].id for c in result.data.controllers],
                objective = obj(result.model, result.stats.solution),
                controllers = result.coverage.controllers,
            ))
        end
    end
    for spec in network_limit_studies()
        result = sensitivity_study(spec.name)
        println((
            study = spec.name,
            costs = result.costs,
            local_cost_slopes = result.slopes,
            dispatchable_cost = obj(
                result.dispatchable.model,
                result.dispatchable.stats.solution,
            ),
        ))
    end
    return nothing
end

if abspath(PROGRAM_FILE) == abspath(@__FILE__)
    main_studies()
end
