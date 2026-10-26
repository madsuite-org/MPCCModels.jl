module BalancedACOPF

using ADNLPModels, MPCCModels, NLPModels

export BalancedACOPFModel, balanced_ac_opf_cases, balanced_ac_opf_case
export balanced_ac_opf_reference, opf_volt_var, opf_volt_watt, opf_residuals
export opf_curve, opf_bus, opf_branch, opf_controller, opf_layout, opf_coverage

include("data.jl")

function _opf_branch_power(vf, vt, delta, g, b)
    p = g * vf^2 - vf * vt * (g * cos(delta) + b * sin(delta))
    q = -b * vf^2 - vf * vt * (g * sin(delta) - b * cos(delta))
    return p, q
end

function _opf_voltage(data, layout, x, bus)
    return bus == data.source.bus ? data.source.voltage : x[layout.v[bus]]
end

function _opf_angle(data, layout, x, bus)
    return bus == data.source.bus ? zero(eltype(x)) : x[layout.theta[bus]]
end

function _opf_flows(data, layout, x)
    return map(data.branches) do branch
        vf = _opf_voltage(data, layout, x, branch.from)
        vt = _opf_voltage(data, layout, x, branch.to)
        delta =
            _opf_angle(data, layout, x, branch.from) -
            _opf_angle(data, layout, x, branch.to)
        z2 = branch.resistance^2 + branch.reactance^2
        g, b = branch.resistance / z2, -branch.reactance / z2
        pf, qf = _opf_branch_power(vf, vt, delta, g, b)
        pt, qt = _opf_branch_power(vt, vf, -delta, g, b)
        return (pf = pf, qf = qf, pt = pt, qt = qt)
    end
end

"""
    balanced_ac_opf_reference(data)

Assemble a feasible witness from a case's explicit reference voltages, angles,
and device P/Q values. Source P/Q follow from network balance. Hinge values
are initialized by direct piecewise evaluation. This is not an optimality
certificate; custom data without a reference can still build an OPF model.
"""
function balanced_ac_opf_reference(data)
    layout = opf_layout(data)
    hasproperty(data, :reference) || throw(ArgumentError("case has no reference point"))
    ref = data.reference
    nb, nc = length(data.buses), length(data.controllers)
    length(ref.voltage) == length(ref.angle) == nb &&
    length(ref.p) == length(ref.q) == nc ||
        throw(DimensionMismatch("incorrect reference dimensions"))
    T = typeof(data.source.voltage)
    x = zeros(T, layout.nvar)
    for i in 1:nb
        i == data.source.bus && continue
        x[layout.v[i]], x[layout.theta[i]] = ref.voltage[i], ref.angle[i]
    end
    ref.voltage[data.source.bus] == data.source.voltage &&
    ref.angle[data.source.bus] == 0 ||
        throw(ArgumentError("reference source must be fixed"))
    x[layout.p], x[layout.q] = ref.p, ref.q
    flows = _opf_flows(data, layout, x)
    bus = data.source.bus
    x[layout.pg], x[layout.qg] = data.buses[bus].pload, data.buses[bus].qload
    for (branch, flow) in zip(data.branches, flows)
        if branch.from == bus
            x[layout.pg] += flow.pf
            x[layout.qg] += flow.qf
        elseif branch.to == bus
            x[layout.pg] += flow.pt
            x[layout.qg] += flow.qt
        end
    end
    for (i, c) in enumerate(data.controllers)
        c.bus == bus || continue
        x[layout.pg] -= x[layout.p[i]]
        x[layout.qg] -= x[layout.q[i]]
    end
    _opf_start_hinges!(x, data, layout)
    all(isfinite, x) ||
        throw(ArgumentError("reference values must be finite in model type"))
    return x
end

function _opf_start_hinges!(x, data, layout)
    for h in eachindex(layout.knots)
        bus = data.controllers[layout.devices[h]].bus
        difference = _opf_voltage(data, layout, x, bus) - layout.knots[h]
        x[layout.r[h]] = max(difference, zero(eltype(x)))
        x[layout.s[h]] = max(-difference, zero(eltype(x)))
    end
    return x
end

"""
    BalancedACOPFModel(data; x0 = nothing)
    BalancedACOPFModel(T = Float64; case = :curtailment, x0 = nothing)

Build a connected, balanced, series-branch AC OPF with one fixed-voltage source
and any number of bounded inverters. A controller can carry VV, VW, both, or
neither law. At least one law must be present in the case. Curves are fixed
continuous piecewise-linear functions with constant extrapolation.

VV sets reactive injection, VW caps active injection, and hardware bounds and
capability circles apply simultaneously. There is no implicit priority or
clipping policy. The objective is source procurement plus separable linear
and quadratic device costs. All powers and curve outputs use one system
per-unit base. Source P/Q can be positive or negative within explicit bounds.

Every curve knot contributes a linear hinge definition and a nonnegative
variable pair passed to `MPCCModel`. Power balance, inverter capability and
branch-end ratings form the nonlinear constraints. Use `opf_layout(data)` for
all variable/constraint indices. The twelve original named two-bus cases keep
their original ordering. The default flat start is separate from the witness.
"""
function BalancedACOPFModel(data::NamedTuple; x0::Union{Nothing,AbstractVector} = nothing)
    layout = opf_layout(data)
    T = typeof(data.source.voltage)
    nb, nc = length(data.buses), length(data.controllers)
    lvar, uvar = fill(T(-Inf), layout.nvar), fill(T(Inf), layout.nvar)
    for (i, bus) in enumerate(data.buses)
        i == data.source.bus && continue
        lvar[layout.v[i]], uvar[layout.v[i]] = bus.vmin, bus.vmax
        lvar[layout.theta[i]], uvar[layout.theta[i]] = -bus.angle_max, bus.angle_max
    end
    lvar[layout.pg], uvar[layout.pg] = data.source.pmin, data.source.pmax
    lvar[layout.qg], uvar[layout.qg] = data.source.qmin, data.source.qmax
    for (i, c) in enumerate(data.controllers)
        lvar[layout.p[i]], uvar[layout.p[i]] = 0, c.p_available
        lvar[layout.q[i]], uvar[layout.q[i]] = c.qmin, c.qmax
    end
    lvar[layout.r] .= 0
    lvar[layout.s] .= 0
    if isnothing(x0)
        x0 = zeros(T, layout.nvar)
        for (i, bus) in enumerate(data.buses)
            i == data.source.bus && continue
            x0[layout.v[i]] = clamp(data.source.voltage, bus.vmin, bus.vmax)
        end
        x0[layout.pg] = clamp(zero(T), data.source.pmin, data.source.pmax)
        x0[layout.qg] = clamp(zero(T), data.source.qmin, data.source.qmax)
        for (i, c) in enumerate(data.controllers)
            v = _opf_voltage(data, layout, x0, c.bus)
            cap = opf_volt_watt(v, c)
            q = opf_volt_var(v, c)
            x0[layout.p[i]] =
                min(c.p_available, c.smax, isnothing(cap) ? c.p_available : cap) / 2
            x0[layout.q[i]] = clamp(isnothing(q) ? zero(T) : q, c.qmin, c.qmax)
        end
        _opf_start_hinges!(x0, data, layout)
    else
        length(x0) == layout.nvar ||
            throw(DimensionMismatch("incorrect starting vector length"))
        x0 = T.(x0)
    end
    all(isfinite, x0) || throw(ArgumentError("converted starting values must be finite"))

    rows, cols, vals = Int[], Int[], T[]
    lcon, ucon = fill(T(-Inf), layout.ncon), fill(T(Inf), layout.ncon)
    for h in eachindex(layout.knots)
        bus = data.controllers[layout.devices[h]].bus
        append!(rows, [h, h])
        append!(cols, [layout.r[h], layout.s[h]])
        append!(vals, T[1, -1])
        rhs = -layout.knots[h]
        if bus == data.source.bus
            rhs += data.source.voltage
        else
            push!(rows, h)
            push!(cols, layout.v[bus])
            push!(vals, -one(T))
        end
        lcon[h] = ucon[h] = rhs
    end
    for (i, c) in enumerate(data.controllers)
        for (curve, pairs, row, index, equality) in (
            (c.vv, layout.vv_pairs[i], layout.vv_rows[i], layout.q[i], true),
            (c.vw, layout.vw_pairs[i], layout.vw_rows[i], layout.p[i], false),
        )
            isnothing(curve) && continue
            append!(rows, fill(row, 1+length(pairs)))
            append!(cols, [index; layout.r[pairs]])
            append!(vals, [one(T); -T.(_opf_curve_weights(curve))])
            ucon[row] = first(curve.values)
            equality && (lcon[row] = ucon[row])
        end
    end
    lcon[layout.balance_p] .= 0
    ucon[layout.balance_p] .= 0
    lcon[layout.balance_q] .= 0
    ucon[layout.balance_q] .= 0
    for (i, c) in enumerate(data.controllers)
        ucon[layout.capability[i]] = c.smax^2
    end
    for (i, b) in enumerate(data.branches)
        ucon[layout.branch_from[i]], ucon[layout.branch_to[i]] = b.rate_from^2, b.rate_to^2
    end
    function f(x)
        objective = data.source.cost * x[layout.pg]
        for (i, c) in enumerate(data.controllers)
            objective += c.cost * x[layout.p[i]] + c.quadratic_cost * x[layout.p[i]]^2 / 2
        end
        return objective
    end
    function constraints(x)
        c = similar(x, layout.ncon - layout.nlin)
        for (i, bus) in enumerate(data.buses)
            c[2*i-1], c[2*i] = -bus.pload, -bus.qload
        end
        c[2*data.source.bus-1] += x[layout.pg]
        c[2*data.source.bus] += x[layout.qg]
        for (i, controller) in enumerate(data.controllers)
            c[2*controller.bus-1] += x[layout.p[i]]
            c[2*controller.bus] += x[layout.q[i]]
            c[2*nb+i] = x[layout.p[i]]^2 + x[layout.q[i]]^2
        end
        for (i, (branch, flow)) in
            enumerate(zip(data.branches, _opf_flows(data, layout, x)))
            c[2*branch.from-1] -= flow.pf
            c[2*branch.from] -= flow.qf
            c[2*branch.to-1] -= flow.pt
            c[2*branch.to] -= flow.qt
            c[2*nb+nc+2*i-1] = flow.pf^2 + flow.qf^2
            c[2*nb+nc+2*i] = flow.pt^2 + flow.qt^2
        end
        return c
    end
    nlp = ADNLPModel(
        f,
        x0,
        lvar,
        uvar,
        rows,
        cols,
        vals,
        constraints,
        lcon,
        ucon;
        name = "Balanced AC OPF ($(data.name))",
    )
    return MPCCModel(nlp, layout.r, layout.s)
end

function BalancedACOPFModel(
    ::Type{T} = Float64;
    case::Symbol = :curtailment,
    x0::Union{Nothing,AbstractVector} = nothing,
) where {T<:AbstractFloat}
    return BalancedACOPFModel(balanced_ac_opf_case(case, T); x0 = x0)
end

include("cases.jl")
include("diagnostics.jl")

end
