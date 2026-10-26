# Direct complex-current evaluation from the original PowerModels dictionary,
# independent of the polar branch coefficients used by the NLP.
function _physical_balance(data, x, l)
    ids = Dict(b.id => i for (i, b) in enumerate(data.buses))
    voltage = x[l.v] .* cis.(x[l.theta])
    balance = zeros(ComplexF64, length(data.buses))
    for (i, g) in enumerate(data.generators)
        balance[g.bus] += complex(x[l.pg[i]], x[l.qg[i]])
    end
    for (i, c) in enumerate(data.controllers)
        balance[c.bus] += complex(x[l.p[i]], x[l.q[i]])
    end
    for load in values(data.pm["load"])
        load["status"] == 0 && continue
        balance[ids[load["load_bus"]]] -= complex(load["pd"], load["qd"])
    end
    for shunt in values(data.pm["shunt"])
        shunt["status"] == 0 && continue
        i = ids[shunt["shunt_bus"]]
        balance[i] -= conj(complex(shunt["gs"], shunt["bs"])) * abs2(voltage[i])
    end
    flows = Dict{Int,Tuple{ComplexF64,ComplexF64}}()
    for b in values(data.pm["branch"])
        b["br_status"] == 0 && continue
        i, j = ids[b["f_bus"]], ids[b["t_bus"]]
        tap = b["tap"] * cis(b["shift"])
        y = inv(complex(b["br_r"], b["br_x"]))
        # Currents on each side of the ideal transformer and pi branch.
        internal = voltage[i]/tap
        series = (internal-voltage[j])*y
        current_from = (series+complex(b["g_fr"], b["b_fr"])*internal)/conj(tap)
        current_to = -series+complex(b["g_to"], b["b_to"])*voltage[j]
        sf, st = voltage[i]*conj(current_from), voltage[j]*conj(current_to)
        balance[i] -= sf
        balance[j] -= st
        flows[b["index"]] = (sf, st)
    end
    return balance, flows
end

"""Original constraints/boxes, complementarity, complex AC balance and direct laws.

`constraints` includes squared apparent-power residuals; `physical_balance` and
curve errors are system-base per unit. Use coverage for unsquared S margins.
"""
function transmission_residuals(model, data, x)
    l = transmission_layout(data)
    length(x) == l.nvar == get_nvar(model) ||
        throw(DimensionMismatch("incorrect model/point"))
    bad = (
        constraints = Inf,
        bounds = Inf,
        physical_balance = Inf,
        complementarity = Inf,
        volt_var = Inf,
        volt_watt = Inf,
    )
    all(isfinite, x) || return bad
    violation(y, lo, hi) = maximum(max.(lo .- y, y .- hi, 0.0); init = 0.0)
    cv = violation(cons(model, x), get_lcon(model), get_ucon(model))
    bv = violation(x, get_lvar(model), get_uvar(model))
    cc = maximum(abs.(min.(x[l.r], x[l.s])); init = 0.0)
    balance, _ = _physical_balance(data, x, l)
    physical = max(maximum(abs.(real.(balance))), maximum(abs.(imag.(balance))))
    vv, vw = 0.0, 0.0
    for (i, c) in enumerate(data.controllers)
        v = x[l.v[c.bus]]
        if !isnothing(c.vv)
            vv = max(vv, abs(x[l.q[i]]-opf_volt_var(v, c)))
        end
        if !isnothing(c.vw)
            vw = max(vw, x[l.p[i]]-opf_volt_watt(v, c), 0.0)
        end
    end
    return (
        constraints = cv,
        bounds = bv,
        physical_balance = physical,
        complementarity = cc,
        volt_var = vv,
        volt_watt = vw,
    )
end

"""Per-device curve positions, physical margins and independently declared targets.

Targets name `vv_region`, `vw_region`, optional `(min,max)` positions inside
finite segments, and `tight`/`slack` controller limits. No targets means
`targets_met = missing`, not a coverage certificate. Network activity is reported
separately with original bus, generator and branch IDs. Tightness alone does not
establish that a bound affects the optimum.
"""
function transmission_coverage(
    data,
    x;
    voltage_tol = 1e-6,
    tight_tol = 1e-5,
    slack_tol = 1e-4,
)
    l = transmission_layout(data)
    length(x) == l.nvar || throw(DimensionMismatch("incorrect point"))
    all(t -> isfinite(t) && t > 0, (voltage_tol, tight_tol, slack_tol)) ||
        throw(ArgumentError("invalid coverage tolerances"))
    if !all(isfinite, x)
        return (
            controllers = [],
            network = nothing,
            network_misses = [],
            targets_met = false,
        )
    end
    targets = Dict(t.id => t for t in data.targets)
    reports = map(enumerate(data.controllers)) do (i, c)
        v, p, q = x[l.v[c.bus]], x[l.p[i]], x[l.q[i]]
        vv = BalancedACOPF._opf_curve_position(v, c.vv, voltage_tol)
        vw = BalancedACOPF._opf_curve_position(v, c.vw, voltage_tol)
        cap = opf_volt_watt(v, c)
        margins = (
            availability = c.p_available-p,
            volt_watt = isnothing(cap) ? Inf : cap-p,
            capability = c.smax-hypot(p, q),
            p_lower = p,
            q_lower = q-c.qmin,
            q_upper = c.qmax-q,
        )
        misses = Symbol[]
        if haskey(targets, c.id)
            t = targets[c.id]
            vv.region == t.vv_region || push!(misses, :vv_region)
            vw.region == t.vw_region || push!(misses, :vw_region)
            for (key, position) in
                ((:vv_position, vv.fraction), (:vw_position, vw.fraction))
                if hasproperty(t, key)
                    window = getproperty(t, key)
                    !isnothing(window) &&
                        (isnothing(position) || !(window[1] <= position <= window[2])) &&
                        push!(misses, key)
                end
            end
            for key in t.tight
                abs(getproperty(margins, key)) <= tight_tol || push!(misses, key)
            end
            for key in t.slack
                getproperty(margins, key) >= slack_tol || push!(misses, key)
            end
        end
        return (
            id = c.id,
            bus = data.buses[c.bus].id,
            voltage = v,
            p = p,
            q = q,
            vv = vv,
            vw = vw,
            margins = margins,
            normalized_margins = map(m -> m/c.smax, margins),
            knot_distance = (
                vv = isnothing(c.vv) ? Inf : minimum(abs.(v .- c.vv.knots)),
                vw = isnothing(c.vw) ? Inf : minimum(abs.(v .- c.vw.knots)),
            ),
            misses = misses,
        )
    end
    _, flows = _physical_balance(data, x, l)
    network = (
        buses = [
            (id = b.id, lower = x[l.v[i]]-b.vmin, upper = b.vmax-x[l.v[i]]) for
            (i, b) in enumerate(data.buses)
        ],
        generators = [
            (
                id = g.id,
                p_lower = x[l.pg[i]]-g.pmin,
                p_upper = g.pmax-x[l.pg[i]],
                q_lower = x[l.qg[i]]-g.qmin,
                q_upper = g.qmax-x[l.qg[i]],
                fixed_p = g.pmin == g.pmax,
                fixed_q = g.qmin == g.qmax,
            ) for (i, g) in enumerate(data.generators)
        ],
        branches = [
            (
                id = b.id,
                from = b.rate-abs(flows[b.id][1]),
                to = b.rate-abs(flows[b.id][2]),
                angle_lower = x[l.theta[b.from]]-x[l.theta[b.to]]-b.amin,
                angle_upper = b.amax-x[l.theta[b.from]]+x[l.theta[b.to]],
            ) for b in data.branches
        ],
    )
    network_misses = []
    for t in data.network_targets
        records =
            t.kind == :bus ? network.buses :
            t.kind == :generator ? network.generators : network.branches
        report = only(filter(r -> r.id == t.id, records))
        margin = getproperty(report, t.limit)
        met = t.state == :tight ? abs(margin) <= tight_tol : margin >= slack_tol
        met || push!(network_misses, t)
    end
    declared = !isempty(data.targets) || !isempty(data.network_targets)
    met =
        declared ? all(isempty(r.misses) for r in reports) && isempty(network_misses) :
        missing
    return (
        controllers = reports,
        network = network,
        network_misses = network_misses,
        targets_met = met,
    )
end
