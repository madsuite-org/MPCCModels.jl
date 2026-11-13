# Application definitions belong to the optional transmission example, not the runtime registry.
export application_card, application_parameters, application_case, application_cases

const APPLICATION_LEVELS = (:nominal, :elevated, :severe)
const APPLICATION_FAMILIES = (:renewable_surplus, :reactive_support, :export_corridor)

"""Application rationale and synthetic balanced-study design, independent of solver outcomes."""
function application_card(family::Symbol; network::Symbol = :ieee118)
    family in APPLICATION_FAMILIES || throw(ArgumentError("unknown application family"))
    network in (:ieee118, :ieee300) ||
        throw(ArgumentError("unsupported application network"))
    common = (
        family = family,
        network = network,
        interpretation = "Balanced steady-state transmission proxy for voltage-responsive aggregate inverter plants",
        policy = "Synthetic heterogeneous local VV equality and VW cap; independent hardware circle/boxes; no priority/clipping policy",
        scope = "Study instances, not calibrated feeder models, dynamic studies or prescribed grid-code settings",
    )
    specific = if family == :renewable_surplus
        (
            title = "High renewable output with light demand",
            sites = (20, 45, 53, 70, 95, 110),
            ratings = (1.6, 2.0, 2.4, 1.8, 2.2, 2.0),
            intended = "Absorption, voltage upper margins, VW curtailment and capability headroom",
            knobs = (:load_scale, :penetration, :availability, :profile_shift),
            zone = (),
        )
    elseif family == :reactive_support
        (
            title = "Limited conventional reactive support",
            sites = (44, 45, 46, 94, 95, 96),
            ratings = (1.6, 2.0, 2.4, 1.8, 2.2, 2.0),
            intended = "Injection, conventional Q limits and competing inverter capability/active-power headroom",
            knobs = (:load_scale, :penetration, :availability, :q_support, :profile_shift),
            zone = (),
        )
    else
        (
            title = "Renewable export through a constrained corridor",
            sites = (20, 21, 22),
            ratings = (2.4, 2.2, 2.4),
            intended = "Boundary thermal limits and network-driven curtailment versus binding VW caps",
            knobs = (
                :load_scale,
                :penetration,
                :availability,
                :export_rating,
                :profile_shift,
            ),
            zone = (20, 21, 22),
        )
    end
    if network == :ieee300
        placement = if family == :renewable_surplus
            (
                sites = (5, 59, 125, 170, 200, 243),
                ratings = (9.0, 11.0, 13.0, 10.0, 12.0, 11.0),
                zone = (),
                placement = "Distributed load-area connection points spanning the numbered transmission network",
            )
        elseif family == :reactive_support
            (
                sites = (118, 120, 121, 140, 171, 178),
                ratings = (9.0, 11.0, 13.0, 10.0, 12.0, 11.0),
                zone = (),
                placement = "Reactive-demand buses, including the 650-Mvar demand at bus 118; clustered support at 118/120/121",
            )
        else
            (
                sites = (25, 26, 27),
                ratings = (13.0, 12.0, 13.0),
                zone = (25, 26, 27, 320),
                placement = "Connected 25/26/27/320 pocket with two transmission boundary branches; all boundary ratings scale together",
            )
        end
        specific = merge(specific, placement)
    end
    return merge(common, specific)
end

"""Nominal/elevated/severe physical parameters; labels are not difficulty predictions.

Penetration scales plant S ratings and hardware Q boxes at constant normalized
profiles. Availability is P_available/S. q_support scales both original bounds
of every conventional Q operating interval; export_rating scales only the zone
boundary ratings. Powers remain on the original 100-MVA system base.
"""
function application_parameters(
    family::Symbol,
    level::Symbol = :nominal;
    overrides = (;),
    network::Symbol = :ieee118,
)
    card = application_card(family; network)
    level in APPLICATION_LEVELS || throw(ArgumentError("unknown operating level"))
    i = findfirst(==(level), APPLICATION_LEVELS)
    parameters = if family == :renewable_surplus
        (
            load_scale = (1.0, 0.85, 0.65)[i],
            penetration = (0.35, 0.65, 1.0)[i],
            availability = (0.75, 0.9, 1.0)[i],
            q_support = 1.0,
            export_rating = 1.0,
            profile_shift = 0.0,
        )
    elseif family == :reactive_support
        (
            load_scale = (1.0, 1.05, 1.1)[i],
            penetration = (0.5, 0.75, 1.0)[i],
            availability = (0.6, 0.85, 0.95)[i],
            q_support = (1.0, 0.5, 0.2)[i],
            export_rating = 1.0,
            profile_shift = 0.0,
        )
    else
        (
            load_scale = (1.0, 0.95, 0.9)[i],
            penetration = (0.35, 0.7, 1.0)[i],
            availability = (0.75, 0.9, 0.98)[i],
            q_support = 1.0,
            export_rating = (1.0, 1.0, 0.7)[i],
            profile_shift = 0.0,
        )
    end
    overrides isa NamedTuple && all(k->k in card.knobs, keys(overrides)) ||
        throw(ArgumentError("override must name applicable physical parameters"))
    p = merge(parameters, overrides)
    all(v->v isa Real && isfinite(v), values(p)) &&
    p.load_scale > 0 &&
    p.penetration > 0 &&
    0 < p.availability <= 1 &&
    0 < p.q_support <= 1 &&
    p.export_rating > 0 || throw(ArgumentError("invalid operating parameters"))
    return map(Float64, p)
end

"""Construct a heterogeneous multi-plant IEEE 118 or IEEE 300 application input.

All policy variants share physical hardware, availability and authoritative
network overlays. No achieved curve region or bound activity is assumed by the
constructor. Source data are unchanged; parameters and cutset IDs are recorded
in provenance. Severe inputs may be difficult or unresolved and remain outside
the original solved-case registry.
"""
function application_case(
    family::Symbol;
    network::Symbol = :ieee118,
    level::Symbol = :nominal,
    laws::Symbol = :both,
    parameters = (;),
    hinge_encoding = :separate,
)
    laws in (:dispatchable, :vv, :vw, :both) || throw(ArgumentError("invalid policies"))
    card = application_card(family; network)
    p = application_parameters(family, level; overrides = parameters, network)
    base = transmission_case(network; targets = [], network_targets = [])
    positions = Dict(b.id=>i for (i, b) in enumerate(base.buses))
    shifts = (-0.006, 0.006, 0.0, -0.003, 0.003, -0.004)
    controllers = map(eachindex(card.sites)) do i
        s = p.penetration*card.ratings[i]
        offset = shifts[i]+p.profile_shift
        vv_knots =
            family == :reactive_support ? [0.95, 1.025, 1.04, 1.053] :
            [0.95, 0.99, 1.01, 1.05]
        vv = opf_curve(vv_knots .+ offset, s .* [0.4, 0.0, 0.0, -0.4])
        vw = opf_curve([1.022, 1.052] .+ offset, s .* [1.0, 0.2])
        bus = positions[card.sites[i]]
        b = base.buses[bus]
        all(k->b.vmin <= k <= b.vmax, [vv.knots; vw.knots]) || throw(
            ArgumentError("application control knots leave the original bus voltage band"),
        )
        return opf_controller(
            Symbol("plant", i),
            bus;
            smax = s,
            p_available = p.availability*s,
            qmin = -0.5*s,
            qmax = 0.5*s,
            cost = 0.0,
            quadratic_cost = 0.0,
            vv = laws in (:vv, :both) ? vv : nothing,
            vw = laws in (:vw, :both) ? vw : nothing,
        )
    end
    generators =
        p.q_support==1 ? [] :
        [
            (id = g.id, qmin = p.q_support*g.qmin, qmax = p.q_support*g.qmax) for
            g in base.generators
        ]
    boundary = [
        b.id for b in base.branches if
        (base.buses[b.from].id in card.zone) != (base.buses[b.to].id in card.zone)
    ]
    branches = [
        (id = b.id, rate = p.export_rating*b.rate) for
        b in base.branches if b.id in boundary
    ]
    data = transmission_overlay(
        base;
        controllers,
        generators,
        branches,
        load_scale = p.load_scale,
        hinge_encoding,
        name = Symbol(network, "_", family, "_", level, "_", laws, "_", hinge_encoding),
    )
    # Metadata do not alter physical records; the model validates them against pm.
    return merge(
        data,
        (
            provenance = merge(
                data.provenance,
                (
                    application_family = string(family),
                    operating_level = string(level),
                    policies = string(laws),
                    interpretation = card.interpretation,
                    parameters = p,
                    export_zone = collect(card.zone),
                    export_boundary = boundary,
                ),
            ),
        ),
    )
end

"""Initial nine physical operating points; policy variants are selected separately."""
function application_cases(; network::Symbol = :ieee118)
    application_card(first(APPLICATION_FAMILIES); network)
    cases =
        [(family = f, level = l) for f in APPLICATION_FAMILIES for l in APPLICATION_LEVELS]
    return network==:ieee118 ? cases : [merge(c, (network = network,)) for c in cases]
end

export application_coverage

"""Measured application coverage, not a claim that the point is feasible or optimal.

Device-cap slack with curtailment is only a candidate network/control interaction,
not a causal allocation. Full original feasibility must be checked separately.
Tight conventional fixed boxes are excluded from activity counts.
"""
function application_coverage(data, x; tolerance = 1e-5)
    isfinite(tolerance) && tolerance>0 || throw(ArgumentError("invalid activity tolerance"))
    all(isfinite, x) || throw(ArgumentError("nonfinite coverage point"))
    report = transmission_coverage(data, x; tight_tol = tolerance)
    l = transmission_layout(data)
    available = sum(c.p_available for c in data.controllers)
    injected = sum(x[l.p])
    curtailed =
        sum(max(c.p_available-x[l.p[i]], 0) for (i, c) in enumerate(data.controllers))
    count_regions(law) = Dict(
        string(region)=>count(c->getproperty(c, law).region==region, report.controllers) for region in unique(getproperty(c, law).region for c in report.controllers)
    )
    tight = Dict{String,Any}(
        "voltage_lower"=>[r.id for r in report.network.buses if abs(r.lower)<=tolerance],
        "voltage_upper"=>[r.id for r in report.network.buses if abs(r.upper)<=tolerance],
        "generator_p_lower"=>[
            r.id for
            r in report.network.generators if !r.fixed_p && abs(r.p_lower)<=tolerance
        ],
        "generator_p_upper"=>[
            r.id for
            r in report.network.generators if !r.fixed_p && abs(r.p_upper)<=tolerance
        ],
        "generator_q_lower"=>[
            r.id for
            r in report.network.generators if !r.fixed_q && abs(r.q_lower)<=tolerance
        ],
        "generator_q_upper"=>[
            r.id for
            r in report.network.generators if !r.fixed_q && abs(r.q_upper)<=tolerance
        ],
        "thermal_from"=>[r.id for r in report.network.branches if abs(r.from)<=tolerance],
        "thermal_to"=>[r.id for r in report.network.branches if abs(r.to)<=tolerance],
        "angle_lower"=>[
            r.id for r in report.network.branches if abs(r.angle_lower)<=tolerance
        ],
        "angle_upper"=>[
            r.id for r in report.network.branches if abs(r.angle_upper)<=tolerance
        ],
    )
    ids(condition) =
        [string(c.id) for (i, c) in enumerate(report.controllers) if condition(i, c)]
    return Dict(
        "system_base_mva"=>data.base_mva,
        "activity_tolerance"=>tolerance,
        "load_mw"=>data.base_mva*sum(b.pd for b in data.buses),
        "inverter_rating_mva"=>data.base_mva*sum(c.smax for c in data.controllers),
        "available_mw"=>data.base_mva*available,
        "injected_mw"=>data.base_mva*injected,
        "curtailed_mw"=>data.base_mva*curtailed,
        "curtailment_fraction"=>curtailed/available,
        "vv_regions"=>count_regions(:vv),
        "vw_regions"=>count_regions(:vw),
        "q_injecting"=>ids((i, c)->c.q>tolerance),
        "q_absorbing"=>ids((i, c)->c.q < -tolerance),
        "vw_binding"=>ids(
            (i, c)->!isnothing(data.controllers[i].vw) &&
                    abs(c.margins.volt_watt)<=tolerance,
        ),
        "capability_binding"=>ids((i, c)->abs(c.margins.capability)<=tolerance),
        "curtailed_with_slack_device_caps"=>ids(
            (i, c)->data.controllers[i].p_available-c.p>tolerance &&
                    c.margins.volt_watt>tolerance &&
                    c.margins.capability>tolerance &&
                    c.margins.p_lower>tolerance,
        ),
        "network_tight"=>tight,
        "controllers"=>report.controllers,
    )
end
