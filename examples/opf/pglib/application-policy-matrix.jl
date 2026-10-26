# IEEE 300 operating policies reuse the application hardware and model builder.
export application_reserve_card, application_reserve_case, application_policy_coverage

const IEEE300_POLICIES=(
    :gentle_watt_cap,
    :firm_watt_cap,
    :steep_watt_cap,
    :absorption_service,
    :injection_service,
    :early_export_backstop,
)
const IEEE300_RESERVES=(:mild, :moderate, :strong)

function _ieee300_policy_card(policy::Symbol)
    policy in IEEE300_POLICIES || throw(ArgumentError("unknown IEEE 300 policy"))
    common=(
        network = :ieee300,
        policy = policy,
        family = :renewable_surplus,
        level = :elevated,
        parameters = (availability = 0.9,),
        vv_knots = (0.95, 0.99, 1.01, 1.05),
        vv_values = (0.4, 0.0, 0.0, -0.4),
    )
    specific=if policy in (:gentle_watt_cap, :firm_watt_cap, :steep_watt_cap)
        i=findfirst(==(policy), (:gentle_watt_cap, :firm_watt_cap, :steep_watt_cap))
        (
            vw_knots = (1.0, 1.04),
            vw_values = (0.82, (0.815, 0.8, 0.76)[i]),
            rationale = "Interconnection active-export ceiling with increasing voltage-backstop gain",
            intended = "Strict VW limitation away from availability and capability; measured ramp positions",
        )
    elseif policy==:absorption_service
        (
            parameters = (availability = 0.85,),
            vv_knots = (0.95, 0.985, 1.0, 1.02),
            vv_values = (0.25, 0.0, 0.0, -0.25),
            vw_knots = (1.04, 1.053),
            vw_values = (1.0, 0.2),
            rationale = "Bounded reactive absorption participation before a delayed active-power backstop",
            intended = "Strict VV absorption plateau",
        )
    elseif policy==:injection_service
        (
            family = :reactive_support,
            level = :nominal,
            parameters = (;),
            vv_knots = (1.025, 1.04, 1.047, 1.053),
            vv_values = (0.25, 0.0, 0.0, -0.25),
            vw_knots = (1.022, 1.052),
            vw_values = (1.0, 0.2),
            rationale = "Bounded reactive injection service at the verified nominal reactive-support operating point",
            intended = "Strict VV injection plateau without the unresolved signed Q-interval contractions",
        )
    else
        (
            family = :export_corridor,
            level = :nominal,
            parameters = (;),
            vv_knots = (0.95, 0.99, 1.035, 1.052),
            vv_values = (0.25, 0.0, 0.0, -0.25),
            vw_knots = (1.0, 1.02),
            vw_values = (1.0, 0.65),
            rationale = "Earlier voltage-based export intervention at a verified export operating point",
            intended = "VW lower plateau; classify cap activity independently of curve position",
        )
    end
    return merge(common, specific)
end

"""One-sided conventional Q-upper contraction, retaining every original lower bound.

factor=1 retains the nominal IEEE 300 reactive-support input. A factor f replaces
Qmax with Qmin+f*(Qmax-Qmin), so the boxes are nested even when Qmin is positive.
The factor scales interval width, not signed Qmax, apparent power or plant size.
"""
function application_reserve_card(reserve::Symbol)
    reserve in IEEE300_RESERVES || throw(ArgumentError("unknown reserve level"))
    factor=(0.98, 0.95, 0.9)[findfirst(==(reserve), IEEE300_RESERVES)]
    return (
        network = :ieee300,
        reserve = reserve,
        family = :reactive_support,
        level = :nominal,
        factor = factor,
        rationale = "Reduced conventional upper reactive headroom at fixed mandatory lower injection, active limits/costs and inverter hardware/policies",
        intended = "Feasible conventional-Q limit pressure with measured controller regimes",
    )
end

function application_reserve_case(
    reserve::Symbol;
    factor = nothing,
    laws = :both,
    hinge_encoding = :separate,
)
    card=application_reserve_card(reserve)
    if !isnothing(factor)
        factor isa Real && isfinite(factor) && 0<factor<=1 ||
            throw(ArgumentError("invalid reserve factor"))
        card=merge(card, (factor = Float64(factor),))
    end
    base=application_case(
        card.family;
        network = card.network,
        level = card.level,
        laws,
        hinge_encoding,
    )
    updates=[
        (id = g.id, qmax = card.factor==1 ? g.qmax : g.qmin+card.factor*(g.qmax-g.qmin)) for
        g in base.generators
    ]
    data=transmission_overlay(
        base;
        generators = updates,
        name = Symbol("ieee300_reserve_", reserve, "_", laws, "_", hinge_encoding),
    )
    return merge(
        data,
        (
            provenance = merge(
                data.provenance,
                (
                    application_extension = "reserve",
                    reserve_variant = string(reserve),
                    reserve_definition = card,
                ),
            ),
        ),
    )
end

function _ieee300_expansion_specs(kind)
    kind in (:all, :policy_matrix, :coverage, :reserve) ||
        throw(ArgumentError("unsupported IEEE 300 matrix kind"))
    specs=NamedTuple[]
    kind in (:all, :policy_matrix, :coverage) &&
        append!(specs, application_policy_cases(; network = :ieee300))
    kind in (:all, :policy_matrix, :reserve) && append!(
        specs,
        [(kind = :reserve, reserve = r, network = :ieee300) for r in IEEE300_RESERVES],
    )
    return specs
end

"""Measured policy regimes and separated competing P limits; not a feasibility certificate.

Strict VW means a tight cap with slack availability and S-circle margins and
positive P. Joint availability/VW activity is reported separately. Power margins
are system-base pu; strict plateau separation is voltage pu. Native network
limits may still bind, so these activity labels do not identify a unique cause.
The legacy application_coverage schema is deliberately unchanged.
"""
function application_policy_coverage(data, x; tolerance = 1e-5, voltage_tolerance = 1e-5)
    isfinite(voltage_tolerance) && voltage_tolerance>0 ||
        throw(ArgumentError("invalid voltage tolerance"))
    cv=application_coverage(data, x; tolerance)
    reports=cv["controllers"]
    ids(test) = [string(c.id) for (i, c) in enumerate(reports) if test(i, c)]
    strict_vw=ids(
        (i, c)->!isnothing(data.controllers[i].vw) &&
                abs(c.margins.volt_watt)<=tolerance &&
                c.margins.availability>tolerance &&
                c.margins.capability>tolerance &&
                c.margins.p_lower>tolerance,
    )
    joint=ids(
        (i, c)->!isnothing(data.controllers[i].vw) &&
                abs(c.margins.volt_watt)<=tolerance &&
                abs(c.margins.availability)<=tolerance,
    )
    strict_s=ids(
        (i, c)->abs(c.margins.capability)<=tolerance &&
                c.margins.availability>tolerance &&
                c.margins.volt_watt>tolerance,
    )
    function plateau_value(i, c)
        curve=data.controllers[i].vv
        isnothing(curve) && return 0.0
        c.voltage<first(curve.knots)-voltage_tolerance && return first(curve.values)
        c.voltage>last(curve.knots)+voltage_tolerance && return last(curve.values)
        return 0.0
    end
    injection=ids((i, c)->plateau_value(i, c)>tolerance)
    absorption=ids((i, c)->plateau_value(i, c)<-tolerance)
    lower_vw=ids(
        (i, c)->!isnothing(data.controllers[i].vw) &&
                c.voltage>data.controllers[i].vw.knots[end]+voltage_tolerance,
    )
    return merge(
        cv,
        Dict(
            "voltage_tolerance"=>voltage_tolerance,
            "strict_vw_binding"=>strict_vw,
            "availability_vw_joint"=>joint,
            "strict_capability_binding"=>strict_s,
            "vv_injection_plateau"=>injection,
            "vv_absorption_plateau"=>absorption,
            "vw_lower_plateau"=>lower_vw,
        ),
    )
end
