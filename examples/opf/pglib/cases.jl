export pglib_control_case

"""First transmission overlays: three added inverters, unchanged conventional fleet.

`laws` is `:dispatchable`, `:vv`, `:vw` or `:both`. Curves are synthetic study
profiles, not grid-code settings. Power ratings/outputs are system-base per unit.
Baseline PGLib data, hardware, availability and costs are identical across laws.
"""
function pglib_control_case(
    network::Symbol;
    laws::Symbol = :both,
    scenario::Symbol = :mixed,
    targets = nothing,
    network_targets = nothing,
)
    laws in (:dispatchable, :vv, :vw, :both) || throw(ArgumentError("unknown law variant"))
    scenario in (:mixed, :watt_limited, :capability_limited) ||
        throw(ArgumentError("unknown scenario"))
    scenario != :mixed &&
        network != :ieee14 &&
        throw(ArgumentError("limit overlays are currently validated on IEEE 14 only"))
    is14 = network in (:ieee14, :ieee14_api)
    network in LEGACY_NETWORKS || throw(ArgumentError("unknown legacy overlay network"))
    buses = is14 ? (5, 9, 14) : (20, 45, 95)
    ratings = is14 ? (0.25, 0.35, 0.20) : (0.8, 1.2, 1.0)
    controllers = map(1:3) do i
        s = ratings[i]
        center = (1.00, 1.03, 1.06)[i]
        vv = opf_curve(center .+ [-0.04, -0.01, 0.01, 0.04], s .* [0.4, 0, 0, -0.4])
        vw = opf_curve((1.01, 1.05, 1.02)[i] .+ [0, 0.03], s .* [1.0, 0.2])
        smax = s
        if i == 3 && scenario == :watt_limited
            # A gentle ramp gives a strict VW-limited interior optimum rather
            # than returning to the availability crossover by lowering voltage.
            vw = opf_curve([1.02, 1.05], s .* [0.70, 0.69])
        elseif i == 3 && scenario == :capability_limited
            # Availability exceeds AC capability; VW remains a slack competitor.
            smax = 0.78*s
            vw = opf_curve([1.05, 1.08], s .* [1.0, 0.2])
        end
        return opf_controller(
            Symbol("ibr", i),
            buses[i];
            vv = laws in (:vv, :both) ? vv : nothing,
            vw = laws in (:vw, :both) ? vw : nothing,
            p_available = 0.8*s,
            smax = smax,
            qmin = -0.5*s,
            qmax = 0.5*s,
            cost = 0.0,
            quadratic_cost = 0.0,
        )
    end
    # The initial limit overlays freeze VV+VW coverage only. Their other law
    # variants remain available for matched counterfactual/sensitivity studies.
    selected = isnothing(targets) ? _control_targets(network, laws, scenario) : targets
    nt =
        isnothing(network_targets) ? _network_targets(network, laws, scenario) :
        network_targets
    return transmission_case(
        network;
        controllers = controllers,
        targets = selected,
        network_targets = nt,
        name = Symbol(network, "_", scenario, "_", laws),
    )
end

"""Network/law combinations available to the optional runner."""
function transmission_cases()
    cases = [
        (network = network, laws = laws, scenario = :mixed) for
        network in LEGACY_NETWORKS for
        laws in (:canonical, :dispatchable, :vv, :vw, :both)
    ]
    append!(
        cases,
        [
            (network = :ieee14, laws = :both, scenario = scenario) for
            scenario in (:watt_limited, :capability_limited)
        ],
    )
    return cases
end

# Independently declared expected regions and broad interior-fraction windows,
# frozen after deterministic flat-start exploration; never computed by the
# classifier or used to choose a complementarity sector or starting point.
function _target(
    i,
    vv,
    vw;
    vf = nothing,
    wf = nothing,
    tight = (:availability,),
    slack = (:capability, :q_lower, :q_upper),
)
    return (
        id = Symbol("ibr", i),
        vv_region = vv,
        vw_region = vw,
        vv_position = vf,
        vw_position = wf,
        tight = tight,
        slack = slack,
    )
end

function _control_targets(network, laws, scenario)
    scenario != :mixed && laws != :both && return []
    if scenario == :watt_limited
        return [
            _target(
                1,
                :segment_3,
                :segment_1;
                vf = (0.23, 0.27),
                wf = (0.23, 0.27),
                tight = (:availability, :volt_watt),
            ),
            _target(
                2,
                :segment_3,
                :below;
                vf = (0.08, 0.2),
                slack = (:volt_watt, :capability),
            ),
            _target(
                3,
                :segment_1,
                :segment_1;
                vf = (0.45, 0.65),
                wf = (0.45, 0.65),
                tight = (:volt_watt,),
                slack = (:availability, :capability, :q_lower, :q_upper),
            ),
        ]
    elseif scenario == :capability_limited
        return [
            _target(
                1,
                :segment_3,
                :segment_1;
                vf = (0.23, 0.27),
                wf = (0.23, 0.27),
                tight = (:availability, :volt_watt),
            ),
            _target(
                2,
                :segment_3,
                :below;
                vf = (0.15, 0.3),
                slack = (:volt_watt, :capability),
            ),
            _target(
                3,
                :segment_1,
                :below;
                vf = (0.65, 0.8),
                tight = (:capability,),
                slack = (:availability, :volt_watt, :q_lower, :q_upper),
            ),
        ]
    end
    if laws == :dispatchable
        return [_target(i, :disabled, :disabled; slack = (:capability,)) for i in 1:3]
    end
    # (VV regions, finite-segment windows) for each network under VV only/both.
    vv_specs = if network == :ieee14
        laws == :vv ?
        ((:segment_3, :segment_3, :segment_1), ((0.25, 0.4), (0.15, 0.3), (0.65, 0.8))) :
        ((:segment_3, :segment_2, :segment_1), ((0.03, 0.15), (0.4, 0.65), (0.23, 0.27)))
    elseif network == :ieee118
        laws == :vv ?
        ((:segment_3, :segment_3, :segment_1), ((0.5, 0.7), (0.05, 0.2), (0.6, 0.75))) :
        ((:segment_3, :segment_3, :segment_1), ((0.23, 0.27), (0.05, 0.17), (0.23, 0.27)))
    elseif network == :ieee14_api
        laws == :vv ?
        ((:segment_2, :segment_3, :segment_1), ((0.6, 0.85), (0.005, 0.05), (0.23, 0.4))) :
        ((:segment_2, :segment_2, :segment_1), ((0.5, 0.8), (0.9, 0.99), (0.23, 0.27)))
    else
        ((:segment_1, :segment_1, :below), ((0.3, 0.5), (0.7, 0.85), nothing))
    end
    vw_regions = if network == :ieee118_api
        (:below, :below, :below)
    elseif network == :ieee14_api && laws == :both
        (:below, :below, :segment_1)
    elseif network in (:ieee118, :ieee14_api) && laws == :vw
        (:segment_1, :segment_1, :segment_1)
    else
        (:segment_1, :below, :segment_1)
    end
    return map(1:3) do i
        vv = laws == :vw ? :disabled : vv_specs[1][i]
        vf = laws == :vw ? nothing : vv_specs[2][i]
        vw = laws == :vv ? :disabled : vw_regions[i]
        crossover =
            laws != :vv &&
            network != :ieee118_api &&
            (
                i == 3 || (
                    i == 1 && (
                        laws == :vw && network != :ieee14_api ||
                        laws == :both && network == :ieee118
                    )
                )
            )
        tight = crossover ? (:availability, :volt_watt) : (:availability,)
        slack =
            laws == :vv || crossover ? (:capability, :q_lower, :q_upper) :
            (:volt_watt, :capability)
        # In VW-only studies Q is dispatchable and may hit its hardware box.
        laws == :vw && (slack = crossover ? (:capability,) : (:volt_watt, :capability))
        wf = vw != :segment_1 ? nothing : crossover ? (0.23, 0.27) : (0.005, 0.2)
        return _target(i, vv, vw; vf = vf, wf = wf, tight = tight, slack = slack)
    end
end

function _network_targets(network, laws, scenario)
    network in LEGACY_NETWORKS || return []
    scenario != :mixed && return []
    bus = network in (:ieee14, :ieee14_api) ? 1 : network == :ieee118 ? 9 : 4
    targets = [(kind = :bus, id = bus, limit = :upper, state = :tight)]
    if network == :ieee118
        push!(targets, (kind = :branch, id = 163, limit = :from, state = :tight))
        push!(targets, (kind = :branch, id = 163, limit = :to, state = :slack))
    elseif network == :ieee118_api
        push!(targets, (kind = :branch, id = 116, limit = :from, state = :tight))
        push!(targets, (kind = :branch, id = 116, limit = :to, state = :slack))
        push!(targets, (kind = :bus, id = 74, limit = :lower, state = :tight))
    elseif network == :ieee14_api
        for id in (2, 3)
            push!(
                targets,
                (
                    kind = :branch,
                    id = id,
                    limit = :from,
                    state = laws == :canonical ? :tight : :slack,
                ),
            )
        end
    end
    if network == :ieee14 && laws == :both && scenario == :mixed
        push!(targets, (kind = :generator, id = 2, limit = :q_upper, state = :tight))
        push!(targets, (kind = :generator, id = 2, limit = :p_lower, state = :tight))
    end
    return targets
end
