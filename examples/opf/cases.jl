# Targets are specified independently of the piecewise evaluator and classifier.
# Each row is (name, voltage, VV region, VW region, tight power limit).
const _OPF_SINGLE_CASES = (
    (:low_voltage_saturation, 0.92, :below, :below, :availability),
    (:reactive_injection, 0.96, :segment_1, :below, :availability),
    (:deadband, 1.00, :segment_2, :below, :availability),
    (:reactive_absorption, 1.04, :segment_3, :below, :availability),
    (:curtailment, 1.09, :above, :segment_1, :volt_watt),
    (:high_voltage_saturation, 1.14, :above, :above, :volt_watt),
    (:vv_lower_knee, 0.94, :knot_1, :below, :availability),
    (:vv_deadband_lower, 0.98, :knot_2, :below, :availability),
    (:vv_deadband_upper, 1.02, :knot_3, :below, :availability),
    (:vv_upper_knee, 1.06, :knot_4, :below, :availability),
    (:vw_upper_knee, 1.07, :above, :knot_1, :availability),
    (:vw_lower_knee, 1.12, :above, :knot_2, :volt_watt),
    (:saturated_var_flat_watt, 1.065, :above, :below, :availability),
    (:early_watt_ramp, 1.07625, :above, :segment_1, :availability),
    (:availability_watt_crossover, 1.0825, :above, :segment_1, :crossover),
    (:vv_injection_20, 0.948, :segment_1, :below, :availability),
    (:vv_injection_80, 0.972, :segment_1, :below, :availability),
    (:vv_absorption_20, 1.028, :segment_3, :below, :availability),
    (:vv_absorption_80, 1.052, :segment_3, :below, :availability),
    (:vw_ramp_20, 1.08, :above, :segment_1, :availability),
    (:vw_ramp_50, 1.095, :above, :segment_1, :volt_watt),
    (:vw_ramp_80, 1.11, :above, :segment_1, :volt_watt),
    (:vv_knot_1_left, 0.9399, :below, :below, :availability),
    (:vv_knot_1_right, 0.9401, :segment_1, :below, :availability),
    (:vv_knot_2_left, 0.9799, :segment_1, :below, :availability),
    (:vv_knot_2_right, 0.9801, :segment_2, :below, :availability),
    (:vv_knot_3_left, 1.0199, :segment_2, :below, :availability),
    (:vv_knot_3_right, 1.0201, :segment_3, :below, :availability),
    (:vv_knot_4_left, 1.0599, :segment_3, :below, :availability),
    (:vv_knot_4_right, 1.0601, :above, :below, :availability),
    (:vw_knot_1_left, 1.0699, :above, :below, :availability),
    (:vw_knot_1_right, 1.0701, :above, :segment_1, :availability),
    (:vw_knot_2_left, 1.1199, :above, :segment_1, :volt_watt),
    (:vw_knot_2_right, 1.1201, :above, :above, :volt_watt),
)

const _OPF_MULTI_CASES =
    (:fork_mixed_reactive, :chain_remote_curtailment, :colocated_controllers)

"""
    balanced_ac_opf_cases()

The named synthetic cases: 34 single-controller regimes/positions/boundaries
and three two-controller studies (fork, chain, and colocated devices).
"""
function balanced_ac_opf_cases()
    return (map(first, _OPF_SINGLE_CASES)..., _OPF_MULTI_CASES...)
end

function _opf_source(voltage::T; bus = 1) where {T<:AbstractFloat}
    return (
        bus = bus,
        voltage = voltage,
        pmin = T(-2),
        pmax = T(2),
        qmin = T(-2),
        qmax = T(2),
        cost = one(T),
    )
end

function _opf_target(id, voltage::T, vv, vw, limit) where {T<:AbstractFloat}
    tight = limit == :crossover ? (:availability, :volt_watt) : (limit,)
    slack =
        limit == :availability ? (:volt_watt, :capability) :
        limit == :volt_watt ? (:availability, :capability) : (:capability,)
    return (
        id = id,
        vv_region = vv,
        vw_region = vw,
        voltage_window = (voltage - T(1e-5), voltage + T(1e-5)),
        tight = tight,
        slack = slack,
    )
end

function _opf_single_case(spec, ::Type{T}) where {T<:AbstractFloat}
    name, voltage, vv, vw, limit = spec
    v = T(voltage)
    # The hardware Q box is wider than the curve plateaus. Equal bounds would
    # duplicate the saturated law without changing the exact feasible set.
    c = opf_controller(:pv, 2, T)
    p, q = min(c.p_available, opf_volt_watt(v, c)), opf_volt_var(v, c)
    branch = opf_branch(1, 2, 0.02, 0.08, T)
    pnet, qnet = p - T(0.4), q - T(0.1)
    # In the receiving-voltage frame, V0 = v - z * conj(S1) / v.
    vr0 = v - (branch.resistance*pnet + branch.reactance*qnet) / v
    vi0 = -(branch.reactance*pnet - branch.resistance*qnet) / v
    e, theta = hypot(vr0, vi0), -atan(vi0, vr0)
    return (
        name = name,
        buses = [opf_bus(T), opf_bus(T; pload = 0.4, qload = 0.1)],
        branches = [branch],
        source = _opf_source(e),
        controllers = [c],
        reference = (voltage = T[e, v], angle = T[0, theta], p = T[p], q = T[q]),
        targets = [_opf_target(:pv, v, vv, vw, limit)],
    )
end

# Joint calibration under one source: derive receiving loads from complex
# branch injections. This is independent of the model's polar implementation.
# Keep all resulting active/reactive loads nonnegative in the shipped fixtures.
function _opf_calibrated_case(name, source, branches, controllers, voltage, angle, targets)
    T = eltype(voltage)
    nb = length(voltage)
    phasors = voltage .* cis.(angle)
    injections = zeros(Complex{T}, nb)
    for b in branches
        current = (phasors[b.from] - phasors[b.to]) / complex(b.resistance, b.reactance)
        injections[b.from] += phasors[b.from] * conj(current)
        injections[b.to] -= phasors[b.to] * conj(current)
    end
    p = [min(c.p_available, opf_volt_watt(voltage[c.bus], c)) for c in controllers]
    q = [opf_volt_var(voltage[c.bus], c) for c in controllers]
    pload, qload = zeros(T, nb), zeros(T, nb)
    for (i, c) in enumerate(controllers)
        pload[c.bus] += p[i]
        qload[c.bus] += q[i]
    end
    for i in 1:nb
        i == source.bus && continue
        pload[i] -= real(injections[i])
        qload[i] -= imag(injections[i])
        pload[i] >= 0 && qload[i] >= 0 || error("negative calibrated load in $name")
    end
    buses = [opf_bus(T; pload = pload[i], qload = qload[i]) for i in 1:nb]
    return (
        name = name,
        buses = buses,
        branches = branches,
        source = source,
        controllers = controllers,
        reference = (voltage = voltage, angle = angle, p = p, q = q),
        targets = targets,
    )
end

function _opf_multi_case(name, ::Type{T}) where {T<:AbstractFloat}
    if name == :fork_mixed_reactive
        controllers = [opf_controller(:injecting, 2, T), opf_controller(:absorbing, 3, T)]
        return _opf_calibrated_case(
            name,
            _opf_source(T(1)),
            [opf_branch(1, 2, 0.02, 0.08, T), opf_branch(1, 3, 0.08, 0.02, T)],
            controllers,
            T[1, 0.96, 1.04],
            T[0, -0.02, 0.04],
            [
                _opf_target(:injecting, T(0.96), :segment_1, :below, :availability),
                _opf_target(:absorbing, T(1.04), :segment_3, :below, :availability),
            ],
        )
    elseif name == :chain_remote_curtailment
        controllers = [opf_controller(:near, 2, T), opf_controller(:remote, 3, T)]
        return _opf_calibrated_case(
            name,
            _opf_source(T(1.04)),
            [opf_branch(1, 2, 0.02, 0.08, T), opf_branch(2, 3, 0.2, 0.03, T)],
            controllers,
            T[1.04, 1, 1.09],
            T[0, -0.02, 0.06],
            [
                _opf_target(:near, T(1), :segment_2, :below, :availability),
                _opf_target(:remote, T(1.09), :above, :segment_1, :volt_watt),
            ],
        )
    elseif name == :colocated_controllers
        controllers =
            [opf_controller(:small, 2, T; p_available = 0.3), opf_controller(:large, 2, T)]
        v, pnet, qnet = T(1.04), T(0.7), T(-0.4)
        r, x = T(0.02), T(0.08)
        v0 = complex(v - (r*pnet + x*qnet)/v, -(x*pnet - r*qnet)/v)
        data = _opf_calibrated_case(
            name,
            _opf_source(abs(v0)),
            [opf_branch(1, 2, r, x, T)],
            controllers,
            T[abs(v0), v],
            T[0, -angle(v0)],
            [
                _opf_target(:small, v, :segment_3, :below, :availability),
                _opf_target(:large, v, :segment_3, :below, :availability),
            ],
        )
        return data
    end
    return throw(ArgumentError("unknown multiple-controller case: $name"))
end

"""
    balanced_ac_opf_case(name, T = Float64)

Explicit network, source, controller, reference and independent coverage-target
records for a named synthetic case. Indices of buses are positions in `buses`.
All powers use a common three-phase per-unit base. These fixed curves do not
claim grid-code compliance and their references are not optimality certificates.
"""
function balanced_ac_opf_case(name::Symbol, ::Type{T} = Float64) where {T<:AbstractFloat}
    name in _OPF_MULTI_CASES && return _opf_multi_case(name, T)
    index = findfirst(spec -> first(spec) == name, _OPF_SINGLE_CASES)
    isnothing(index) && throw(ArgumentError("unknown balanced AC OPF case: $name"))
    return _opf_single_case(_OPF_SINGLE_CASES[index], T)
end
