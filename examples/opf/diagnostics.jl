"""
    opf_residuals(mpcc, x, data)

Maximum original NLP, bound, nonnegative-pair complementarity, direct VV error,
and direct VW-cap violation in per unit. All must be small for a feasible point.
Disabled laws are skipped. Nonfinite iterates return infinite residuals.
"""
function opf_residuals(mpcc, x::AbstractVector, data)
    length(x) == get_nvar(mpcc) || throw(DimensionMismatch("incorrect OPF point length"))
    if !all(isfinite, x)
        return (
            constraints = Inf,
            bounds = Inf,
            complementarity = Inf,
            volt_var = Inf,
            volt_watt = Inf,
        )
    end
    layout = opf_layout(data)
    layout.nvar == length(x) ||
        throw(DimensionMismatch("data do not match model dimensions"))
    cx = cons(mpcc, x)
    constraints =
        max(zero(eltype(x)), maximum(get_lcon(mpcc) .- cx), maximum(cx .- get_ucon(mpcc)))
    bounds =
        max(zero(eltype(x)), maximum(get_lvar(mpcc) .- x), maximum(x .- get_uvar(mpcc)))
    vv, vw = zero(eltype(x)), zero(eltype(x))
    for (i, c) in enumerate(data.controllers)
        v = _opf_voltage(data, layout, x, c.bus)
        isnothing(c.vv) || (vv = max(vv, abs(x[layout.q[i]] - opf_volt_var(v, c))))
        isnothing(c.vw) || (vw = max(vw, x[layout.p[i]] - opf_volt_watt(v, c)))
    end
    return (
        constraints = constraints,
        bounds = bounds,
        complementarity = maximum(abs.(min.(x[layout.r], x[layout.s]))),
        volt_var = vv,
        volt_watt = vw,
    )
end

function _opf_curve_position(v, curve, tol)
    isnothing(curve) && return (region = :disabled, fraction = nothing)
    k = findfirst(knot -> abs(v - knot) <= tol, curve.knots)
    isnothing(k) || return (region = Symbol("knot_$k"), fraction = nothing)
    v < first(curve.knots) && return (region = :below, fraction = nothing)
    v > last(curve.knots) && return (region = :above, fraction = nothing)
    k = searchsortedlast(curve.knots, v)
    return (
        region = Symbol("segment_$k"),
        fraction = (v - curve.knots[k]) / (curve.knots[k+1] - curve.knots[k]),
    )
end

"""
    opf_coverage(data, x; voltage_tol = 1e-6, tight_tol = 1e-5, slack_tol = 1e-4)

Classify the actual solution, independently of its reference: per-device curve
regions/fractions, voltage window, tight power limits and slack competitors.
Also report branch-end, bus and source margins in physical per-unit units.
`targets_met` is `missing` when no targets are supplied. This report does not
replace `opf_residuals`, solver status, or an optimality check.
"""
function opf_coverage(
    data,
    x::AbstractVector;
    voltage_tol = 1e-6,
    tight_tol = 1e-5,
    slack_tol = 1e-4,
)
    all(isfinite, (voltage_tol, tight_tol, slack_tol)) &&
    voltage_tol > 0 &&
    0 < tight_tol < slack_tol || throw(ArgumentError("invalid coverage tolerances"))
    layout = opf_layout(data)
    length(x) == layout.nvar || throw(DimensionMismatch("incorrect OPF point length"))
    all(isfinite, x) ||
        return (targets_met = false, controllers = NamedTuple[], network = nothing)
    targets = hasproperty(data, :targets) ? data.targets : nothing
    if !isnothing(targets)
        ids = [target.id for target in targets]
        length(ids) == length(unique(ids)) == length(data.controllers) &&
        Set(ids) == Set(c.id for c in data.controllers) ||
            throw(ArgumentError("coverage targets must match controller IDs exactly"))
    end
    reports = map(enumerate(data.controllers)) do (i, c)
        v = _opf_voltage(data, layout, x, c.bus)
        p, q = x[layout.p[i]], x[layout.q[i]]
        vv, vw = _opf_curve_position(v, c.vv, voltage_tol),
        _opf_curve_position(v, c.vw, voltage_tol)
        slacks = (
            availability = c.p_available - p,
            volt_watt = isnothing(c.vw) ? Inf : opf_volt_watt(v, c) - p,
            capability = c.smax - hypot(p, q),
            p_lower = p,
            q_lower = q - c.qmin,
            q_upper = c.qmax - q,
        )
        active = Tuple(
            key for key in keys(slacks) if abs(getproperty(slacks, key)) <= tight_tol
        )
        misses = String[]
        if !isnothing(targets)
            target = only(t for t in targets if t.id == c.id)
            vv.region == target.vv_region || push!(misses, "volt-var region")
            vw.region == target.vw_region || push!(misses, "volt-watt region")
            target.voltage_window[1] <= v <= target.voltage_window[2] ||
                push!(misses, "voltage window")
            for key in (target.tight..., target.slack...)
                hasproperty(slacks, key) ||
                    throw(ArgumentError("unknown target limit: $key"))
            end
            for key in target.tight
                abs(getproperty(slacks, key)) <= tight_tol || push!(misses, "tight $key")
            end
            for key in target.slack
                getproperty(slacks, key) >= slack_tol || push!(misses, "slack $key")
            end
        end
        return (
            id = c.id,
            bus = c.bus,
            voltage = v,
            p = p,
            q = q,
            volt_var = vv,
            volt_watt = vw,
            slacks = slacks,
            tight_limits = active,
            target_met = isnothing(targets) ? missing : isempty(misses),
            misses = misses,
        )
    end
    flows = _opf_flows(data, layout, x)
    branches = [
        (
            from = b.from,
            to = b.to,
            from_margin = b.rate_from - hypot(f.pf, f.qf),
            to_margin = b.rate_to - hypot(f.pt, f.qt),
        ) for (b, f) in zip(data.branches, flows)
    ]
    buses = [
        (
            bus = i,
            lower_margin = _opf_voltage(data, layout, x, i) - b.vmin,
            upper_margin = b.vmax - _opf_voltage(data, layout, x, i),
            angle_margin = b.angle_max - abs(_opf_angle(data, layout, x, i)),
        ) for (i, b) in enumerate(data.buses)
    ]
    source = (
        p_lower = x[layout.pg] - data.source.pmin,
        p_upper = data.source.pmax - x[layout.pg],
        q_lower = x[layout.qg] - data.source.qmin,
        q_upper = data.source.qmax - x[layout.qg],
    )
    return (
        targets_met = isnothing(targets) ? missing : all(r -> r.target_met, reports),
        controllers = reports,
        network = (branches = branches, buses = buses, source = source),
    )
end
