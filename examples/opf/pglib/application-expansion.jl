# Optional application policy and fleet variants; ordinary data -> existing model builder.
export application_policy_card, application_policy_case, application_policy_cases
export application_fleet_case, application_fleet_start

const APPLICATION_POLICIES = (
    :absorption_service,
    :injection_service,
    :early_export_backstop,
    :early_absorption_backstop,
    :middle_absorption_backstop,
    :late_absorption_backstop,
    :gentle_watt_cap,
    :firm_watt_cap,
    :steep_watt_cap,
)

"""Explicit synthetic operating policies; intended regimes are not solver targets.

Voltage knots are relative to the original plant-specific profile shifts. Reactive
service limits and active export caps are policy settings, inside the unchanged
hardware boxes. No setting is a prescribed grid-code value.
"""
function application_policy_card(policy::Symbol; network::Symbol = :ieee118)
    network==:ieee300 && return _ieee300_policy_card(policy)
    network==:ieee118 || throw(ArgumentError("unsupported policy network"))
    policy in APPLICATION_POLICIES || throw(ArgumentError("unknown application policy"))
    defaults=(
        policy = policy,
        family = :renewable_surplus,
        level = :elevated,
        parameters = (availability = 0.9,),
        vv_knots = (0.95, 0.99, 1.01, 1.05),
        vv_values = (0.4, 0.0, 0.0, -0.4),
    )
    specific=if policy==:absorption_service
        (
            parameters = (availability = 0.85,),
            vv_knots = (0.95, 0.985, 1.0, 1.02),
            vv_values = (0.25, 0.0, 0.0, -0.25),
            vw_knots = (1.04, 1.053),
            vw_values = (1.0, 0.2),
            rationale = "Reactive absorption service saturates before a delayed active-power backstop",
            intended = "VV absorption plateau with hardware headroom",
        )
    elseif policy==:injection_service
        (
            family = :reactive_support,
            level = :severe,
            parameters = (q_support = 0.3, availability = 0.85),
            vv_knots = (1.025, 1.04, 1.047, 1.053),
            vv_values = (0.12, 0.0, 0.0, -0.25),
            vw_knots = (1.022, 1.052),
            vw_values = (1.0, 0.2),
            rationale = "Limited inverter reactive-service participation with a higher voltage-support setpoint",
            intended = "VV injection saturation under restricted conventional reactive support",
        )
    elseif policy==:early_export_backstop
        (
            family = :export_corridor,
            level = :elevated,
            parameters = (export_rating = 0.8,),
            vv_knots = (0.95, 0.99, 1.035, 1.052),
            vv_values = (0.25, 0.0, 0.0, -0.25),
            vw_knots = (1.0, 1.02),
            vw_values = (1.0, 0.65),
            rationale = "Conservative voltage-based export backstop with a wide reactive deadband",
            intended = "VW lower plateau and strict curtailment",
        )
    elseif policy in (
        :early_absorption_backstop,
        :middle_absorption_backstop,
        :late_absorption_backstop,
    )
        i=findfirst(
            ==(policy),
            (
                :early_absorption_backstop,
                :middle_absorption_backstop,
                :late_absorption_backstop,
            ),
        )
        onset=(1.0165, 1.0285, 1.0405)[i]
        (
            vw_knots = (onset, onset+0.012),
            vw_values = (1.0, 0.2),
            rationale = "Progressively delayed active-power intervention on the same absorption droop",
            intended = "Different absorption-ramp positions; positions are measured after solving",
        )
    else
        i=findfirst(==(policy), (:gentle_watt_cap, :firm_watt_cap, :steep_watt_cap))
        (
            vw_knots = (1.0, 1.04),
            vw_values = (0.82, (0.815, 0.80, 0.76)[i]),
            rationale = "An interconnection export ceiling with increasing voltage-backstop gain",
            intended = "Strict VW limitation away from availability crossover and varied VW ramp positions",
        )
    end
    return merge(defaults, specific)
end

function application_policy_case(
    policy::Symbol;
    network::Symbol = :ieee118,
    laws = :both,
    hinge_encoding = :separate,
    parameters = (;),
)
    laws in (:dispatchable, :vv, :vw, :both) || throw(ArgumentError("invalid policies"))
    parameters isa NamedTuple ||
        throw(ArgumentError("policy parameters must be a named tuple"))
    card=application_policy_card(policy; network)
    base=application_case(
        card.family;
        network,
        level = card.level,
        parameters = merge(card.parameters, parameters),
    )
    shifts=(-0.006, 0.006, 0.0, -0.003, 0.003, -0.004)
    controllers=map(enumerate(base.controllers)) do (i, c)
        offset=shifts[i]+base.provenance.parameters.profile_shift
        vv=opf_curve(collect(card.vv_knots) .+ offset, c.smax .* collect(card.vv_values))
        vw=opf_curve(collect(card.vw_knots) .+ offset, c.smax .* collect(card.vw_values))
        b=base.buses[c.bus]
        all(k->b.vmin<=k<=b.vmax, [vv.knots; vw.knots]) ||
            throw(ArgumentError("policy knots leave original voltage band"))
        maximum(vv.values)<=c.qmax && minimum(vv.values)>=c.qmin ||
            throw(ArgumentError("policy exceeds hardware Q boxes"))
        return merge(
            c,
            (
                vv = laws in (:vv, :both) ? vv : nothing,
                vw = laws in (:vw, :both) ? vw : nothing,
            ),
        )
    end
    data=transmission_overlay(
        base;
        controllers,
        hinge_encoding,
        name = Symbol(network, "_policy_", policy, "_", laws, "_", hinge_encoding),
    )
    return merge(
        data,
        (
            provenance = merge(
                data.provenance,
                (
                    policies = string(laws),
                    application_extension = "coverage",
                    policy_variant = string(policy),
                    policy_definition = card,
                    rationale = card.rationale,
                    intended = card.intended,
                ),
            ),
        ),
    )
end

function application_policy_cases(; network::Symbol = :ieee118)
    application_policy_card(:absorption_service; network)
    return network==:ieee118 ?
           [(kind = :coverage, policy = p) for p in APPLICATION_POLICIES] :
           [(kind = :coverage, policy = p, network = network) for p in IEEE300_POLICIES]
end

# Nested deterministic site lists, preserving the original six sites as anchors.
function _application_fleet_sites(base, count, placement)
    placement in (:same_sites, :clustered, :dispersed) ||
        throw(ArgumentError("invalid fleet placement"))
    anchors=[c.bus for c in base.controllers]
    if placement==:same_sites
        return [anchors[mod1(i, length(anchors))] for i in 1:count]
    end
    neighbors=[Int[] for _ in base.buses]
    for b in base.branches
        push!(neighbors[b.from], b.to)
        push!(neighbors[b.to], b.from)
    end
    function distance(seed)
        d=fill(typemax(Int), length(base.buses))
        d[seed]=0
        queue=[seed]
        for i in queue, j in neighbors[i]
            if d[j]==typemax(Int)
                d[j]=d[i]+1
                push!(queue, j)
            end
        end
        return d
    end
    candidates=[
        i for i in eachindex(base.buses) if
        i!=base.reference_bus && base.buses[i].vmin<=0.944 && base.buses[i].vmax>=1.059
    ]
    count<=length(candidates) || throw(ArgumentError("not enough valid fleet sites"))
    if placement==:clustered
        distances=distance(first(anchors))
        return sort(candidates; by = i->(distances[i], base.buses[i].id))[1:count]
    end
    selected=[first(anchors)]
    distances=distance(first(anchors))
    while length(selected)<count
        remaining=filter(i->!(i in selected), candidates)
        next=first(sort(remaining; by = i->(-distances[i], base.buses[i].id)))
        push!(selected, next)
        distances=min.(distances, distance(next))
    end
    return selected
end

"""Fixed-total heterogeneous 6/12/24-unit fleets with separately defined geography.

Each of the six original profile classes is split equally into 1/2/4 units.
Class S/P/Q totals and normalized curves are preserved exactly up to floating
arithmetic. Same-site replicas preserve aggregate physical feasibility; distinct-
site clustered/dispersed populations intentionally change geography. Their site
sets are nested and topology-based, not sensitivity-ranked. No activity is assumed.
"""
function application_fleet_case(
    family::Symbol = :reactive_support;
    level = :elevated,
    count::Int = 6,
    placement = :same_sites,
    laws = :both,
    hinge_encoding = :separate,
    network = :ieee118,
    parameters = (;),
    policy = :standard,
)
    base=policy==:standard ? application_case(family; network, level, laws, parameters) :
         application_policy_case(policy; network, laws, parameters)
    Symbol(base.provenance.application_family)==family &&
    Symbol(base.provenance.operating_level)==level ||
        throw(ArgumentError("fleet family/level must match policy anchor"))
    n=length(base.controllers)
    count>=n && count % n==0 ||
        throw(ArgumentError("count must be a positive multiple of template population"))
    copies=div(count, n)
    sites=_application_fleet_sites(base, count, placement)
    templates=[mod1(i, n) for i in 1:count]
    controllers=[
        _scale_controller(
            base.controllers[templates[i]],
            1/copies;
            id = Symbol(base.controllers[templates[i]].id, "_unit", div(i-1, n)+1),
            bus = sites[i],
        ) for i in 1:count
    ]
    data=transmission_overlay(
        base;
        controllers,
        hinge_encoding,
        name = Symbol(
            network,
            "_fleet_",
            family,
            "_",
            level,
            "_",
            count,
            "_",
            placement,
            "_",
            laws,
            "_",
            hinge_encoding,
        ),
    )
    return merge(
        data,
        (
            provenance = merge(
                data.provenance,
                (
                    application_extension = "fleet",
                    fleet_count = count,
                    fleet_placement = string(placement),
                    fleet_templates = templates,
                    fleet_copies = copies,
                    fleet_sites = [data.buses[i].id for i in sites],
                    interpretation_population = "Fixed rating-weighted mixture; distinct-site count also changes geography",
                ),
            ),
        ),
    )
end

"""Transfer an original application point to a fleet, splitting P/Q by profile class.

Physical V/angle/conventional generation are copied. For relocated devices this
is only a start, and may violate balances or laws; original feasibility must be
checked independently. Same-site proportional replicas preserve physical sums.
"""
function application_fleet_start(data, source, x)
    a, b=transmission_layout(data), transmission_layout(source)
    length(x)==b.nvar && all(isfinite, x) || throw(ArgumentError("invalid source point"))
    data.buses==source.buses &&
    data.generators==source.generators &&
    data.branches==source.branches ||
        throw(ArgumentError("fleet/source physical network differs"))
    hasproperty(data.provenance, :fleet_templates) ||
        throw(ArgumentError("not a fleet record"))
    templates=data.provenance.fleet_templates
    copies=data.provenance.fleet_copies
    length(source.controllers)*copies==length(data.controllers) ||
        throw(ArgumentError("template population differs"))
    result=zeros(a.nvar)
    for key in (:v, :theta, :pg, :qg)
        result[getproperty(a, key)] .= x[getproperty(b, key)]
    end
    for i in eachindex(templates)
        result[a.p[i]]=x[b.p[templates[i]]]/copies
        result[a.q[i]]=x[b.q[templates[i]]]/copies
    end
    for h in eachindex(a.knots)
        delta=result[a.v[data.controllers[a.devices[h]].bus]]-a.knots[h]
        result[a.r[h]], result[a.s[h]]=max(delta, 0), max(-delta, 0)
    end
    return result
end

export application_expansion_specs, application_expansion_case

function application_expansion_specs(kind::Symbol = :all; network::Symbol = :ieee118)
    network==:ieee300 && return _ieee300_expansion_specs(kind)
    network==:ieee118 || throw(ArgumentError("unsupported expansion network"))
    kind in (:all, :coverage, :fleet) || throw(ArgumentError("unknown expansion kind"))
    specs=NamedTuple[]
    kind in (:all, :coverage) && append!(specs, application_policy_cases())
    if kind in (:all, :fleet)
        append!(
            specs,
            [
                (
                    kind = :fleet,
                    family = :reactive_support,
                    level = :elevated,
                    count = n,
                    placement = p,
                ) for p in (:same_sites, :clustered, :dispersed) for n in (6, 12, 24)
            ],
        )
    end
    return specs
end

function application_expansion_case(
    spec::NamedTuple;
    laws = :both,
    hinge_encoding = :separate,
)
    haskey(spec, :kind) || throw(ArgumentError("missing expansion kind"))
    network=get(spec, :network, :ieee118)
    extra=haskey(spec, :network) ? (:network,) : ()
    if spec.kind==:coverage
        Set(keys(spec))==Set((:kind, :policy, extra...)) ||
            throw(ArgumentError("invalid policy spec"))
        return application_policy_case(spec.policy; network, laws, hinge_encoding)
    elseif spec.kind==:reserve
        Set(keys(spec))==Set((:kind, :reserve, :network)) ||
            throw(ArgumentError("invalid reserve spec"))
        network==:ieee300 || throw(ArgumentError("reserve matrix uses IEEE 300"))
        return application_reserve_case(spec.reserve; laws, hinge_encoding)
    elseif spec.kind==:fleet
        network==:ieee118 || throw(
            ArgumentError(
                "legacy expansion fleet specs use IEEE 118; use the operating matrix for IEEE 300",
            ),
        )
        Set(keys(spec))==Set((:kind, :family, :level, :count, :placement)) ||
            throw(ArgumentError("invalid fleet spec"))
        return application_fleet_case(
            spec.family;
            level = spec.level,
            count = spec.count,
            placement = spec.placement,
            laws,
            hinge_encoding,
        )
    end
    return throw(ArgumentError("unknown expansion kind"))
end
