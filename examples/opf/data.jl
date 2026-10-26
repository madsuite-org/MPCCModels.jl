"""
    opf_curve(knots, values)

A continuous piecewise-linear curve with constant extrapolation. Knots must
be finite and strictly increasing. Values use the common system power base.
"""
function opf_curve(knots::AbstractVector, values::AbstractVector)
    length(knots) == length(values) >= 2 ||
        throw(ArgumentError("a curve needs at least two equally sized knot/value arrays"))
    all(x -> x isa Real && isfinite(x), knots) &&
    all(x -> x isa Real && isfinite(x), values) ||
        throw(ArgumentError("curve coefficients must be finite"))
    all(diff(knots) .> 0) || throw(ArgumentError("curve knots must increase strictly"))
    return (knots = float.(copy(knots)), values = float.(copy(values)))
end

function _opf_curve_value(v, curve)
    v <= first(curve.knots) && return first(curve.values)
    v >= last(curve.knots) && return last(curve.values)
    k = searchsortedlast(curve.knots, v)
    t = (v - curve.knots[k]) / (curve.knots[k+1] - curve.knots[k])
    return (1 - t) * curve.values[k] + t * curve.values[k+1]
end

# Changes in slope, including transitions from/to the constant outer plateaus.
function _opf_curve_weights(curve)
    slopes = diff(curve.values) ./ diff(curve.knots)
    return [first(slopes); diff(slopes); -last(slopes)]
end

"""
    opf_bus(T = Float64; pload = 0, qload = 0, vmin = 0.88, vmax = 1.18,
            angle_max = 0.3)

Bus data in per unit, with angle bounds in radians. Positive load consumes
power; negative reactive load represents a capacitive injection.
"""
function opf_bus(
    ::Type{T} = Float64;
    pload = 0,
    qload = 0,
    vmin = 0.88,
    vmax = 1.18,
    angle_max = 0.3,
) where {T<:AbstractFloat}
    return (
        pload = T(pload),
        qload = T(qload),
        vmin = T(vmin),
        vmax = T(vmax),
        angle_max = T(angle_max),
    )
end

"""
    opf_branch(from, to, resistance, reactance, T = Float64;
               rate_from = 1.5, rate_to = rate_from)

A series-only AC branch. The apparent-power ratings apply separately at its
two ends. Parallel branches are allowed; shunts, taps and phase shifts are absent.
"""
function opf_branch(
    from::Int,
    to::Int,
    resistance,
    reactance,
    ::Type{T} = Float64;
    rate_from = 1.5,
    rate_to = rate_from,
) where {T<:AbstractFloat}
    for rating in (rate_from, rate_to)
        isfinite(rating) &&
            !isfinite(T(rating)) &&
            throw(ArgumentError("branch rating overflows the model type"))
    end
    return (
        from = from,
        to = to,
        resistance = T(resistance),
        reactance = T(reactance),
        rate_from = T(rate_from),
        rate_to = T(rate_to),
    )
end

"""
    opf_controller(id, bus, T = Float64; vv, vw, p_available = 0.8, smax = 1,
                   qmin = -0.4, qmax = 0.4, cost = 0, quadratic_cost = 0)

Inverter data. The default curves have four VV and two VW knots. Either law
can be disabled with `nothing`. Hardware Q bounds are separate from curve
plateaus. The objective adds `cost*p + quadratic_cost*p^2/2` for each device.
"""
function opf_controller(
    id::Symbol,
    bus::Int,
    ::Type{T} = Float64;
    vv = opf_curve(T[0.94, 0.98, 1.02, 1.06], T[0.3, 0, 0, -0.3]),
    vw = opf_curve(T[1.07, 1.12], T[1, 0.2]),
    p_available = 0.8,
    smax = 1,
    qmin = -0.4,
    qmax = 0.4,
    cost = 0,
    quadratic_cost = 0,
) where {T<:AbstractFloat}
    return (
        id = id,
        bus = bus,
        vv = vv,
        vw = vw,
        p_available = T(p_available),
        smax = T(smax),
        qmin = T(qmin),
        qmax = T(qmax),
        cost = T(cost),
        quadratic_cost = T(quadratic_cost),
    )
end

function _opf_controller(data)
    return hasproperty(data, :controllers) ? only(data.controllers) : data
end

"""
    opf_volt_var(v, controller)

Independent piecewise evaluation of Q. Return `nothing` when VV is disabled.
A single-controller case may be passed in place of its controller.
"""
function opf_volt_var(v, data)
    controller = _opf_controller(data)
    return isnothing(controller.vv) ? nothing : _opf_curve_value(v, controller.vv)
end

"""
    opf_volt_watt(v, controller)

Independent piecewise evaluation of the active-power cap. Return `nothing`
when VW is disabled. This is not called by the underlying smooth NLP.
"""
function opf_volt_watt(v, data)
    controller = _opf_controller(data)
    return isnothing(controller.vw) ? nothing : _opf_curve_value(v, controller.vw)
end

function _validate_opf_data(data)
    nb = length(data.buses)
    nb >= 2 || throw(ArgumentError("at least two buses are required"))
    source = data.source
    T = typeof(source.voltage)
    T <: AbstractFloat || throw(ArgumentError("source voltage must be floating point"))
    source.bus isa Int && 1 <= source.bus <= nb ||
        throw(ArgumentError("invalid source bus"))
    all(
        isfinite,
        T.((
            source.voltage,
            source.pmin,
            source.pmax,
            source.qmin,
            source.qmax,
            source.cost,
        )),
    ) || throw(ArgumentError("source data must be finite in the model type"))
    source.pmin <= source.pmax && source.qmin <= source.qmax ||
        throw(ArgumentError("source bounds are reversed"))
    for bus in data.buses
        all(isfinite, T.(values(bus))) ||
            throw(ArgumentError("bus data must be finite in the model type"))
        0 < bus.vmin <= bus.vmax && 0 < bus.angle_max < pi ||
            throw(ArgumentError("invalid bus voltage or angle bounds"))
        bus.pload >= 0 || throw(ArgumentError("active loads must be nonnegative"))
    end
    data.buses[source.bus].vmin <= source.voltage <= data.buses[source.bus].vmax ||
        throw(ArgumentError("fixed source voltage is outside its bus bounds"))
    reachable = Set([source.bus])
    for branch in data.branches
        branch.from isa Int &&
        branch.to isa Int &&
        1 <= branch.from <= nb &&
        1 <= branch.to <= nb &&
        branch.from != branch.to || throw(ArgumentError("invalid branch endpoints"))
        all(isfinite, T.((branch.resistance, branch.reactance))) &&
        branch.resistance >= 0 &&
        isfinite(branch.resistance^2 + branch.reactance^2) &&
        branch.resistance^2 + branch.reactance^2 > 0 ||
            throw(ArgumentError("invalid series impedance"))
        branch.rate_from > 0 && branch.rate_to > 0 ||
            throw(ArgumentError("branch ratings must be positive"))
        all(
            rate -> isinf(rate) || isfinite(T(rate)^2),
            (branch.rate_from, branch.rate_to),
        ) || throw(ArgumentError("squared branch ratings must be representable"))
    end
    for _ in 1:nb, branch in data.branches
        if branch.from in reachable || branch.to in reachable
            push!(reachable, branch.from, branch.to)
        end
    end
    length(reachable) == nb ||
        throw(ArgumentError("network must be connected to the source"))
    ids = [c.id for c in data.controllers]
    length(unique(ids)) == length(ids) ||
        throw(ArgumentError("controller IDs must be unique"))
    nh = 0
    for c in data.controllers
        c.bus isa Int && 1 <= c.bus <= nb || throw(ArgumentError("invalid controller bus"))
        all(
            isfinite,
            T.((c.p_available, c.smax, c.qmin, c.qmax, c.cost, c.quadratic_cost)),
        ) && isfinite(T(c.smax)^2) ||
            throw(ArgumentError("controller data must be finite in the model type"))
        c.p_available >= 0 && c.smax > 0 && c.qmin <= c.qmax && c.quadratic_cost >= 0 ||
            throw(ArgumentError("invalid controller bounds, rating or cost"))
        for curve in (c.vv, c.vw)
            isnothing(curve) && continue
            opf_curve(curve.knots, curve.values)
            all(isfinite, T.(curve.knots)) &&
            all(diff(T.(curve.knots)) .> 0) &&
            all(isfinite, T.(curve.values)) &&
            all(isfinite, T.(_opf_curve_weights(curve))) ||
                throw(ArgumentError("curve cannot be represented in the model's type"))
            nh += length(curve.knots)
        end
        isnothing(c.vw) ||
            all(c.vw.values .>= 0) ||
            throw(ArgumentError("volt-watt cap values must be nonnegative"))
    end
    nh > 0 || throw(ArgumentError("at least one complementarity control law is required"))
    return nothing
end

"""
    opf_layout(data)

Computed variable, pair and constraint maps for a connected network and its
controllers. Source voltage and angle have index zero because they are fixed.
The original two-bus case retains its 18-variable and 15-constraint ordering.
"""
function opf_layout(data)
    _validate_opf_data(data)
    nb, nc = length(data.buses), length(data.controllers)
    T = typeof(data.source.voltage)
    free = [i for i in 1:nb if i != data.source.bus]
    v, theta = zeros(Int, nb), zeros(Int, nb)
    v[free] = 1:length(free)
    theta[free] = length(free) .+ (1:length(free))
    pg = 2 * length(free) + 1
    qg = pg + 1
    p = collect((qg+1):(qg+nc))
    q = collect((qg+nc+1):(qg+2*nc))
    knots, devices = T[], Int[]
    vv_pairs, vw_pairs = [Int[] for _ in 1:nc], [Int[] for _ in 1:nc]
    for (i, c) in enumerate(data.controllers)
        for (curve, pairs) in ((c.vv, vv_pairs[i]), (c.vw, vw_pairs[i]))
            isnothing(curve) && continue
            append!(pairs, (length(knots)+1):(length(knots)+length(curve.knots)))
            append!(knots, curve.knots)
            append!(devices, fill(i, length(curve.knots)))
        end
    end
    nh = length(knots)
    r = collect((qg+2*nc+1):(qg+2*nc+nh))
    s = r .+ nh
    vv_rows, vw_rows = zeros(Int, nc), zeros(Int, nc)
    row = nh
    for (i, c) in enumerate(data.controllers)
        isnothing(c.vv) && continue
        row += 1
        vv_rows[i] = row
    end
    for (i, c) in enumerate(data.controllers)
        isnothing(c.vw) && continue
        row += 1
        vw_rows[i] = row
    end
    nlin = row
    balance_p = nlin .+ collect(1:2:(2*nb))
    balance_q = balance_p .+ 1
    capability = nlin + 2*nb .+ collect(1:nc)
    branch_from = nlin + 2*nb + nc .+ collect(1:2:(2*length(data.branches)))
    branch_to = branch_from .+ 1
    return (
        v = v,
        theta = theta,
        pg = pg,
        qg = qg,
        p = p,
        q = q,
        r = r,
        s = s,
        knots = knots,
        devices = devices,
        vv_pairs = vv_pairs,
        vw_pairs = vw_pairs,
        vv_rows = vv_rows,
        vw_rows = vw_rows,
        balance_p = balance_p,
        balance_q = balance_q,
        capability = capability,
        branch_from = branch_from,
        branch_to = branch_to,
        nlin = nlin,
        nvar = qg + 2*nc + 2*nh,
        ncon = nlin + 2*nb + nc + 2*length(data.branches),
    )
end
