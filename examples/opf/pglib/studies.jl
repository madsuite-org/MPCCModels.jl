export transmission_overlay, controller_placement_case, controller_population_case
export network_limit_studies, network_limit_case
export controller_fleet_case

"""Rebuild a study overlay from a deep copy of the authoritative per-unit data.

Updates use original PGLib IDs, not vector positions. `buses` accepts vmin/vmax;
`generators` accepts P/Q bounds and c2/c1/c0 system-base cost coefficients;
`branches` accepts rate/amin/amax. Positive `load_scale` scales P and Q together.
Network records and independent complex-current checks are rebuilt together.
Existing coverage targets are cleared unless explicitly supplied. Files and the
input case remain unchanged. All powers are system-base pu; angles are radians.
"""
function transmission_overlay(
    data;
    buses = [],
    generators = [],
    branches = [],
    load_scale = 1.0,
    controllers = data.controllers,
    targets = [],
    network_targets = [],
    name = Symbol(data.name, "_overlay"),
    hinge_encoding = data.hinge_encoding,
)
    isfinite(load_scale) && load_scale > 0 || throw(ArgumentError("invalid load scale"))
    pm = deepcopy(data.pm)
    for (updates, kind, mapping) in (
        (buses, "bus", (vmin = "vmin", vmax = "vmax")),
        (
            generators,
            "gen",
            (
                pmin = "pmin",
                pmax = "pmax",
                qmin = "qmin",
                qmax = "qmax",
                c2 = "c2",
                c1 = "c1",
                c0 = "c0",
            ),
        ),
        (branches, "branch", (rate = "rate_a", amin = "angmin", amax = "angmax")),
    )
        length(unique(u.id for u in updates)) == length(updates) ||
            throw(ArgumentError("duplicate overlay ID"))
        for update in updates
            update.id isa Int || throw(ArgumentError("overlay ID must be an integer"))
            key = string(update.id)
            haskey(pm[kind], key) || throw(ArgumentError("unknown $kind ID"))
            record = pm[kind][key]
            for field in keys(update)
                field == :id && continue
                hasproperty(mapping, field) ||
                    throw(ArgumentError("unsupported overlay field $field"))
                value = getproperty(update, field)
                value isa Real && isfinite(value) ||
                    throw(ArgumentError("nonfinite overlay value"))
                if field in (:c2, :c1, :c0)
                    costs = [zeros(3-length(record["cost"])); record["cost"]]
                    costs[field == :c2 ? 1 : field == :c1 ? 2 : 3] = value
                    record["cost"], record["ncost"] = costs, 3
                else
                    record[getproperty(mapping, field)] = value
                end
            end
        end
    end
    for load in values(pm["load"])
        load["pd"] *= load_scale
        load["qd"] *= load_scale
    end
    return _transmission_data(
        pm;
        network = data.network,
        controllers,
        targets,
        network_targets,
        name,
        provenance = data.provenance,
        hinge_encoding,
    )
end

function _scale_controller(c, factor; id = c.id, bus = c.bus)
    isfinite(factor) && factor > 0 || throw(ArgumentError("invalid controller scale"))
    scale(curve) =
        isnothing(curve) ? nothing : opf_curve(curve.knots, factor .* curve.values)
    return opf_controller(
        id,
        bus;
        vv = scale(c.vv),
        vw = scale(c.vw),
        p_available = factor*c.p_available,
        smax = factor*c.smax,
        qmin = factor*c.qmin,
        qmax = factor*c.qmax,
        cost = c.cost,
        quadratic_cost = c.quadratic_cost/factor,
    )
end

"""Three-device placement/penetration study with fixed profiles and total ratings.

Placement is dispersed, clustered or colocated. Profiles are heterogeneous
(the initial mixed profiles), or homogeneous (normalized device-2 profiles).
For fixed profiles/penetration, placement changes only attachment buses. The
positive penetration multiplier scales all device ratings, availability and
curve power outputs, not network demand. These are exploratory cases until
solved activity targets are supplied; no initial three-device targets survive.
"""
function controller_placement_case(
    network::Symbol;
    placement = :dispersed,
    profiles = :heterogeneous,
    penetration = 1.0,
    laws = :both,
    targets = [],
    network_targets = [],
)
    placement in (:dispersed, :clustered, :colocated) ||
        throw(ArgumentError("unknown placement"))
    profiles in (:heterogeneous, :homogeneous) || throw(ArgumentError("unknown profiles"))
    base = pglib_control_case(network; laws, targets = [], network_targets = [])
    is14 = network in (:ieee14, :ieee14_api)
    bus_ids =
        placement == :dispersed ? (is14 ? (5, 9, 14) : (20, 45, 95)) :
        placement == :clustered ? (is14 ? (9, 10, 14) : (94, 95, 96)) :
        (is14 ? (14, 14, 14) : (95, 95, 95))
    positions = Dict(b.id => i for (i, b) in enumerate(base.buses))
    controllers = map(enumerate(base.controllers)) do (i, c)
        if profiles == :homogeneous
            template = _scale_controller(
                base.controllers[2],
                c.smax/base.controllers[2].smax;
                id = c.id,
                bus = c.bus,
            )
            c = merge(c, (vv = template.vv, vw = template.vw))
        end
        return _scale_controller(c, penetration; bus = positions[bus_ids[i]])
    end
    return transmission_overlay(
        base;
        controllers,
        targets,
        network_targets,
        name = Symbol(network, "_", placement, "_", profiles, "_", laws, "_", penetration),
    )
end

"""Split each controller into identical colocated copies at fixed aggregate size.

This isolates complementarity population from network size and penetration.
Ratings, availability and curve outputs divide by `copies`; quadratic cost
coefficients multiply by `copies` to preserve aggregate cost at equal sharing.
Existing targets are cloned with new IDs. Compare bus injections/objectives,
not individual dispatch when optimal sharing is nonunique.
"""
function controller_population_case(data; copies::Int = 2)
    copies >= 1 || throw(ArgumentError("copies must be positive"))
    isempty(data.controllers) &&
        throw(ArgumentError("population study requires controllers"))
    controllers = [
        _scale_controller(c, 1/copies; id = Symbol(c.id, "_", j)) for
        c in data.controllers for j in 1:copies
    ]
    targets =
        [merge(t, (id = Symbol(t.id, "_", j),)) for t in data.targets for j in 1:copies]
    return transmission_overlay(
        data;
        controllers,
        targets,
        network_targets = data.network_targets,
        name = Symbol(data.name, "_copies_", copies),
    )
end

function _site_order(data, placement)
    placement in (:dispersed, :clustered) || throw(ArgumentError("unknown fleet placement"))
    nb = length(data.buses)
    neighbors = [Int[] for _ in 1:nb]
    for b in data.branches
        push!(neighbors[b.from], b.to)
        push!(neighbors[b.to], b.from)
    end
    function distances(seed)
        d = fill(typemax(Int), nb)
        d[seed] = 0
        queue = [seed]
        for i in queue, j in neighbors[i]
            if d[j] == typemax(Int)
                d[j] = d[i]+1
                push!(queue, j)
            end
        end
        return d
    end
    seed_id = data.network in (:ieee14, :ieee14_api) ? 14 : 95
    seed = only(findall(b -> b.id == seed_id, data.buses))
    candidates = [i for i in 1:nb if i != data.reference_bus]
    d = distances(seed)
    if placement == :clustered
        return sort(candidates; by = i -> (d[i], data.buses[i].id))
    end
    selected = [seed]
    while length(selected) < length(candidates)
        remaining = filter(i -> !(i in selected), candidates)
        next = first(sort(remaining; by = i -> (-d[i], data.buses[i].id)))
        push!(selected, next)
        d = min.(d, distances(next))
    end
    return selected
end

"""A growing fleet on distinct buses, with constant aggregate inverter size.

The normalized device-2 profile is homogeneous for all counts, so changing count
does not also change the policy mixture. Sites form nested deterministic sets:
clustered uses shortest hop distance from bus 14/95; dispersed greedily maximizes
minimum hop distance to selected sites, with original bus ID breaking ties.
These are topology-based placements, not voltage-sensitivity rankings. They may
include zero-load or conventional-generator buses. The reference bus is excluded.
Unlike replica populations, growing site sets intentionally change physical
placement as well as controller count. No solved region is assumed in advance.
"""
function controller_fleet_case(
    network::Symbol;
    count::Int = 3,
    placement = :dispersed,
    penetration = 1.0,
    laws = :both,
)
    base = pglib_control_case(network; laws, targets = [], network_targets = [])
    sites = _site_order(base, placement)
    1 <= count <= length(sites) || throw(ArgumentError("invalid fleet size"))
    total = sum(c.smax for c in base.controllers)
    template = base.controllers[2]
    controllers = [
        _scale_controller(
            template,
            penetration*total/(count*template.smax);
            id = Symbol("fleet", i),
            bus = sites[i],
        ) for i in 1:count
    ]
    return transmission_overlay(
        base;
        controllers,
        name = Symbol(
            network,
            "_fleet_",
            placement,
            "_",
            count,
            "_",
            penetration,
            "_",
            laws,
        ),
    )
end

"""Single-bound RHS studies on IEEE 14; source data and controllers otherwise fixed.

`step` is in system pu for power, pu voltage, or radians for angles. Each case
isolates one bound within its family; other families may remain active. The
thermal-from case additionally has all other nonfixed network limits slack.
"""
function network_limit_studies()
    return (
        (
            name = :voltage_upper,
            kind = :bus,
            id = 1,
            field = :vmax,
            value = 1.06,
            step = 1e-4,
            limit = :upper,
        ),
        (
            name = :voltage_lower,
            kind = :bus,
            id = 3,
            field = :vmin,
            value = 1.005,
            step = 1e-4,
            limit = :lower,
        ),
        (
            name = :generator_p,
            kind = :generator,
            id = 1,
            field = :pmax,
            value = 1.8,
            step = 1e-3,
            limit = :p_upper,
        ),
        (
            name = :generator_q,
            kind = :generator,
            id = 2,
            field = :qmax,
            value = 0.3,
            step = 1e-3,
            limit = :q_upper,
        ),
        (
            name = :thermal_from,
            kind = :branch,
            id = 1,
            field = :rate,
            value = 1.2,
            step = 1e-3,
            limit = :from,
        ),
        (
            name = :thermal_to,
            kind = :branch,
            id = 6,
            field = :rate,
            value = 0.33,
            step = 2e-4,
            limit = :to,
        ),
        (
            name = :angle_upper,
            kind = :branch,
            id = 1,
            field = :amax,
            value = 0.075,
            step = 1e-4,
            limit = :angle_upper,
        ),
        (
            name = :angle_lower,
            kind = :branch,
            id = 6,
            field = :amin,
            value = -0.06,
            step = 1e-4,
            limit = :angle_lower,
        ),
    )
end

function network_limit_case(name::Symbol; change = :base, laws = :both, step_scale = 1.0)
    change in (:tightened, :base, :relaxed) || throw(ArgumentError("unknown perturbation"))
    isfinite(step_scale) && step_scale > 0 ||
        throw(ArgumentError("invalid perturbation scale"))
    specs = filter(s -> s.name == name, network_limit_studies())
    isempty(specs) && throw(ArgumentError("unknown network sensitivity"))
    spec = only(specs)
    orientation = spec.field in (:vmin, :amin, :pmin, :qmin) ? -1 : 1
    offset =
        change == :base ? 0.0 :
        (change == :relaxed ? 1 : -1)*orientation*spec.step*step_scale
    update = merge((id = spec.id,), NamedTuple{(spec.field,)}((spec.value+offset,)))
    kwargs = NamedTuple{(
        spec.kind == :bus ? :buses : spec.kind == :generator ? :generators : :branches,
    )}(([update],))
    base = pglib_control_case(:ieee14; laws, targets = [], network_targets = [])
    targets = if laws == :both
        [
            _target(
                1,
                name == :thermal_from ? :segment_1 : :segment_3,
                name == :thermal_from ? :below : :segment_1;
                vf = name == :thermal_from ? (0.7, 0.85) : (0.005, 0.95),
                wf = name == :thermal_from ? nothing : (0.005, 0.95),
                slack = (:capability, :q_lower, :q_upper),
            ),
            _target(
                2,
                :segment_2,
                :below;
                vf = (0.005, 0.995),
                slack = (:volt_watt, :capability, :q_lower, :q_upper),
            ),
            _target(
                3,
                :segment_1,
                :segment_1;
                vf = (0.23, 0.27),
                wf = (0.23, 0.27),
                tight = (:availability, :volt_watt),
            ),
        ]
    else
        []
    end
    if laws == :both && name == :thermal_to
        # Congestion curtails device 2 even though its VW and S limits are slack;
        # device 3 is strictly VW-limited away from the availability crossover.
        targets[2] = _target(
            2,
            :segment_2,
            :below;
            vf = (0.95, 0.995),
            tight = (),
            slack = (:availability, :volt_watt, :capability, :q_lower, :q_upper),
        )
        targets[3] = _target(
            3,
            :segment_1,
            :segment_1;
            vf = (0.33, 0.4),
            wf = (0.33, 0.4),
            tight = (:volt_watt,),
            slack = (:availability, :capability, :q_lower, :q_upper),
        )
    end
    opposite =
        spec.limit == :upper ? :lower :
        spec.limit == :lower ? :upper :
        spec.limit == :p_upper ? :p_lower :
        spec.limit == :q_upper ? :q_lower :
        spec.limit == :from ? :to :
        spec.limit == :to ? :from : spec.limit == :angle_upper ? :angle_lower : :angle_upper
    nt =
        laws == :both ?
        [
            (kind = spec.kind, id = spec.id, limit = spec.limit, state = :tight),
            (kind = spec.kind, id = spec.id, limit = opposite, state = :slack),
        ] : []
    return transmission_overlay(
        base;
        kwargs...,
        targets,
        network_targets = nt,
        name = Symbol("ieee14_", name, "_", change, "_", laws),
    )
end
