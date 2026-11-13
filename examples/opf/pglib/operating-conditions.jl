# Data-only operating variants: every case uses the unchanged TransmissionOPFModel.
export operating_condition_specs, operating_condition_case, operating_condition_coverage

function _condition_spec(
    id;
    network,
    family = :reactive_support,
    level = :nominal,
    policy = :standard,
    parameters = (;),
    q_upper_fraction = 1.0,
    count = 6,
    placement = :original,
)
    return (;
        id,
        network,
        family,
        level,
        policy,
        parameters,
        q_upper_fraction = Float64(q_upper_fraction),
        count,
        placement,
    )
end

"""Focused physical sequences and selected interactions, not a Cartesian product.

Curves and costs stay fixed within reserve/export/penetration/placement sequences.
Each row is an independent single-state OPF. Severity does not predict difficulty.
"""
function operating_condition_specs(; network = :ieee118)
    network in (:ieee118, :ieee300) || throw(ArgumentError("unsupported condition network"))
    specs=NamedTuple[]
    for (label, fraction) in
        zip((:reference, :q98, :q95, :q90, :q80), (1.0, 0.98, 0.95, 0.9, 0.8))
        push!(
            specs,
            _condition_spec(
                Symbol("reserve_", label);
                network,
                q_upper_fraction = fraction,
            ),
        )
    end
    for (label, rating) in
        zip((:r120, :r100, :r85, :r70, :r55), (1.2, 1.0, 0.85, 0.7, 0.55))
        push!(
            specs,
            _condition_spec(
                Symbol("export_", label);
                network,
                family = :export_corridor,
                count = 3,
                parameters = (export_rating = rating,),
            ),
        )
    end
    card=application_policy_card(:early_export_backstop; network)
    for (label, rating) in zip((:r100, :r85, :r70), (1.0, 0.85, 0.7))
        push!(
            specs,
            _condition_spec(
                Symbol("backstop_", label);
                network,
                family = card.family,
                level = card.level,
                policy = card.policy,
                count = 3,
                parameters = (export_rating = rating,),
            ),
        )
    end
    for (label, penetration) in zip((:p45, :p65, :p85), (0.45, 0.65, 0.85))
        push!(
            specs,
            _condition_spec(
                Symbol("penetration_", label);
                network,
                family = :renewable_surplus,
                level = :elevated,
                policy = :gentle_watt_cap,
                parameters = (; penetration),
            ),
        )
    end
    for (count, placement) in ((6, :clustered), (6, :dispersed), (12, :same_sites))
        push!(
            specs,
            _condition_spec(
                Symbol("placement_", count, "_", placement);
                network,
                family = :renewable_surplus,
                level = :elevated,
                policy = :gentle_watt_cap,
                count,
                placement,
            ),
        )
    end
    card=application_policy_card(:injection_service; network)
    for (label, fraction) in zip((:q98, :q90), (0.98, 0.9))
        push!(
            specs,
            _condition_spec(
                Symbol("injection_", label);
                network,
                family = card.family,
                level = card.level,
                policy = card.policy,
                q_upper_fraction = fraction,
            ),
        )
    end
    for (label, availability) in zip((:a85, :a98), (0.85, 0.98))
        push!(
            specs,
            _condition_spec(
                Symbol("absorption_", label);
                network,
                family = :renewable_surplus,
                level = :elevated,
                policy = :absorption_service,
                parameters = (; availability),
            ),
        )
    end
    return specs
end

function _condition_spec(row::AbstractDict)
    keys_expected=(
        :id,
        :network,
        :family,
        :level,
        :policy,
        :parameters,
        :q_upper_fraction,
        :count,
        :placement,
    )
    Set(keys(row))==Set(string.(keys_expected)) ||
        throw(ArgumentError("invalid condition fields"))
    parameters=(; (Symbol(k)=>v for (k, v) in sort(collect(row["parameters"])))...)
    return _condition_spec(
        Symbol(row["id"]);
        network = Symbol(row["network"]),
        family = Symbol(row["family"]),
        level = Symbol(row["level"]),
        policy = Symbol(row["policy"]),
        parameters,
        q_upper_fraction = row["q_upper_fraction"],
        count = row["count"],
        placement = Symbol(row["placement"]),
    )
end

"""Build one physical operating variant with existing constructors and overlays.

Q-upper fractions contract the anchor interval at fixed Qmin, including positive
Qmin. Penetration scales hardware and normalized curve ordinates together.
Placement/population preserve the anchor's aggregate profile mixture and hardware.
Existing policy cards define the curves; no intended activity is imposed.
"""
function operating_condition_case(row::AbstractDict; kwargs...)
    return operating_condition_case(_condition_spec(row); kwargs...)
end
function operating_condition_case(
    spec::NamedTuple;
    laws = :both,
    hinge_encoding = :separate,
)
    Set(keys(spec))==Set(keys(_condition_spec(:check; network = :ieee118))) ||
        throw(ArgumentError("invalid condition fields"))
    spec.id isa Symbol &&
    !isempty(string(spec.id)) &&
    spec.count isa Int &&
    spec.count>0 &&
    spec.q_upper_fraction isa Real &&
    isfinite(spec.q_upper_fraction) &&
    0<spec.q_upper_fraction<=1 || throw(ArgumentError("invalid condition input"))
    base=spec.policy==:standard ?
         application_case(
        spec.family;
        network = spec.network,
        level = spec.level,
        parameters = spec.parameters,
        laws,
        hinge_encoding,
    ) :
         application_policy_case(
        spec.policy;
        network = spec.network,
        parameters = spec.parameters,
        laws,
        hinge_encoding,
    )
    Symbol(base.provenance.application_family)==spec.family &&
    Symbol(base.provenance.operating_level)==spec.level ||
        throw(ArgumentError("condition family/level must match policy anchor"))
    if spec.placement==:original
        spec.count==length(base.controllers) ||
            throw(ArgumentError("original population differs"))
    else
        base=application_fleet_case(
            spec.family;
            network = spec.network,
            level = spec.level,
            parameters = spec.parameters,
            policy = spec.policy,
            count = spec.count,
            placement = spec.placement,
            laws,
            hinge_encoding,
        )
    end
    f=spec.q_upper_fraction
    generators=f==1 ? [] :
               [(id = g.id, qmax = g.qmin+f*(g.qmax-g.qmin)) for g in base.generators]
    data=transmission_overlay(
        base;
        generators,
        name = Symbol(spec.network, "_condition_", spec.id, "_", laws, "_", hinge_encoding),
    )
    return merge(
        data,
        (
            provenance = merge(
                data.provenance,
                (
                    application_extension = "operating_conditions",
                    condition_id = string(spec.id),
                    condition_q_upper_fraction = Float64(f),
                    condition_count = spec.count,
                    condition_placement = string(spec.placement),
                    condition_policy = string(spec.policy),
                ),
            ),
        ),
    )
end

"""Achieved policy/bound combinations at a point; check original feasibility first."""
function operating_condition_coverage(data, x; tolerance = 1e-5)
    cv=application_policy_coverage(data, x; tolerance)
    n=cv["network_tight"]
    any_q=!isempty(n["generator_q_upper"])
    any_v=!isempty(n["voltage_lower"]) || !isempty(n["voltage_upper"])
    any_t=!isempty(n["thermal_from"]) || !isempty(n["thermal_to"])
    vv=!isempty(cv["vv_injection_plateau"]) || !isempty(cv["vv_absorption_plateau"])
    vw=!isempty(cv["strict_vw_binding"])
    regiondiversity=length(cv["vv_regions"])>1 || length(cv["vw_regions"])>1
    features=String[]
    for (label, active) in (
        ("strict_vw_and_q_upper", vw && any_q),
        ("strict_vw_and_thermal", vw && any_t),
        ("vv_plateau_and_q_upper", vv && any_q),
        ("vv_plateau_and_voltage", vv && any_v),
        ("vv_plateau_and_thermal", vv && any_t),
        ("capability_and_vw", !isempty(cv["capability_binding"]) && vw),
        ("heterogeneous_regions", regiondiversity),
    )
        active && push!(features, label)
    end
    return merge(cv, Dict("combined_activity"=>features))
end
