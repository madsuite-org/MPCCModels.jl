module TransmissionOPF

using ADNLPModels, MPCCModels, NLPModels, PowerModels, SHA

include("../balanced-ac-opf.jl")
using .BalancedACOPF: opf_curve, opf_controller, opf_volt_var, opf_volt_watt
import .BalancedACOPF: _opf_curve_weights

export transmission_case, transmission_cases, transmission_layout, TransmissionOPFModel
export transmission_residuals, transmission_coverage, transmission_flows
export opf_curve, opf_controller, transmission_start

const PGLIB_REVISION = "dc6be4b2f85ca0e776952ec22cbd4c22396ea5a3"
const PGLIB_FILES = (
    ieee14 = "pglib_opf_case14_ieee.m",
    ieee118 = "pglib_opf_case118_ieee.m",
    ieee14_api = "pglib_opf_case14_ieee__api.m",
    ieee118_api = "pglib_opf_case118_ieee__api.m",
    ieee300 = "pglib_opf_case300_ieee.m",
)

# Frozen solved overlays; additional source networks have separate application catalogs.
const LEGACY_NETWORKS = (:ieee14, :ieee118, :ieee14_api, :ieee118_api)

"""Read an unchanged, hash-verified PGLib fixture and convert to per unit.

PowerModels parses the MATPOWER text; no MATLAB code is evaluated. Its network
repair pass is deliberately disabled. This example supports one connected AC
network, active buses/branches/generators, polynomial costs of degree at most
two, and fixed taps/phase shifts. DC lines, storage and switches are rejected.
The returned `pm` dictionary is the unmodified canonical baseline in per unit.
"""
function transmission_case(
    network::Symbol;
    controllers = [],
    targets = [],
    network_targets = nothing,
    name = network,
    hinge_encoding = :separate,
)
    hasproperty(PGLIB_FILES, network) || throw(ArgumentError("unknown PGLib network"))
    filename = getproperty(PGLIB_FILES, network)
    path = joinpath(@__DIR__, "data", filename)
    hashes = Dict(
        reverse(split(line)) for
        line in readlines(joinpath(@__DIR__, "data", "SHA256SUMS"))
    )
    bytes2hex(sha256(read(path))) == hashes[filename] || error("PGLib checksum mismatch")
    pm = PowerModels.parse_file(path; validate = false)
    PowerModels.make_per_unit!(pm)
    for key in ("dcline", "storage", "switch")
        isempty(get(pm, key, Dict())) || throw(ArgumentError("unsupported $key"))
    end
    return _transmission_data(
        pm;
        network,
        controllers,
        targets,
        network_targets,
        name,
        provenance = (revision = PGLIB_REVISION, file = filename),
        hinge_encoding,
    )
end

function _network_records(pm)
    records(key, status) =
        sort([v for v in values(pm[key]) if v[status] != 0]; by = v -> v["index"])
    raw_buses = [v for v in values(pm["bus"]) if v["bus_type"] != 4]
    sort!(raw_buses; by = v -> v["index"])
    ids = Dict(b["bus_i"] => i for (i, b) in enumerate(raw_buses))
    buses = [
        (
            id = b["bus_i"],
            vmin = b["vmin"],
            vmax = b["vmax"],
            pd = 0.0,
            qd = 0.0,
            gs = 0.0,
            bs = 0.0,
        ) for b in raw_buses
    ]
    for load in values(pm["load"])
        load["status"] == 0 && continue
        i = ids[load["load_bus"]]
        b = buses[i]
        buses[i] = merge(b, (pd = b.pd + load["pd"], qd = b.qd + load["qd"]))
    end
    for shunt in values(pm["shunt"])
        shunt["status"] == 0 && continue
        i = ids[shunt["shunt_bus"]]
        b = buses[i]
        buses[i] = merge(b, (gs = b.gs + shunt["gs"], bs = b.bs + shunt["bs"]))
    end
    all(b -> all(isfinite, values(b)) && 0 < b.vmin <= b.vmax, buses) ||
        throw(ArgumentError("invalid bus bounds or coefficients"))
    branches = [_branch_record(b, ids) for b in records("branch", "br_status")]
    generators = map(records("gen", "gen_status")) do g
        g["model"] == 2 && length(g["cost"]) <= 3 ||
            throw(ArgumentError("only polynomial costs of degree ≤ 2 are supported"))
        c = [zeros(3-length(g["cost"])); g["cost"]]
        all(isfinite, (g["pmin"], g["pmax"], g["qmin"], g["qmax"], c...)) &&
        g["pmin"] <= g["pmax"] &&
        g["qmin"] <= g["qmax"] ||
            throw(ArgumentError("invalid generator bounds or costs"))
        return (
            id = g["index"],
            bus = ids[g["gen_bus"]],
            pmin = g["pmin"],
            pmax = g["pmax"],
            qmin = g["qmin"],
            qmax = g["qmax"],
            c2 = c[1],
            c1 = c[2],
            c0 = c[3],
        )
    end
    refs = findall(b -> b["bus_type"] == 3, raw_buses)
    length(refs) == 1 || throw(ArgumentError("exactly one reference bus required"))
    return (
        buses = buses,
        branches = branches,
        generators = generators,
        reference_bus = only(refs),
    )
end

function _transmission_data(
    pm;
    network,
    controllers,
    targets,
    network_targets,
    name,
    provenance,
    hinge_encoding = :separate,
)
    records = _network_records(pm)
    if isnothing(network_targets)
        network_targets =
            isempty(controllers) ? _network_targets(network, :canonical, :mixed) : []
    end
    data = (
        name = name,
        network = network,
        buses = records.buses,
        branches = records.branches,
        generators = records.generators,
        reference_bus = records.reference_bus,
        controllers = collect(controllers),
        targets = collect(targets),
        network_targets = collect(network_targets),
        pm = pm,
        base_mva = pm["baseMVA"],
        provenance = provenance,
        hinge_encoding = hinge_encoding,
    )
    _validate(data)
    return data
end

function _branch_record(b, ids)
    all(
        isfinite,
        (
            b["br_r"],
            b["br_x"],
            b["tap"],
            b["shift"],
            b["angmin"],
            b["angmax"],
            b["g_fr"],
            b["b_fr"],
            b["g_to"],
            b["b_to"],
        ),
    ) &&
    b["br_r"]^2+b["br_x"]^2 > 0 &&
    b["tap"] > 0 &&
    b["angmin"] <= b["angmax"] ||
        throw(ArgumentError("invalid branch coefficients or angle bounds"))
    rate = get(b, "rate_a", Inf)
    rate > 0 && !isnan(rate) || throw(ArgumentError("invalid branch rating"))
    y = inv(complex(b["br_r"], b["br_x"]))
    tap = b["tap"] * cis(b["shift"])
    yff = (y + complex(b["g_fr"], b["b_fr"])) / abs2(tap)
    yft, ytf = -y / conj(tap), -y / tap
    ytt = y + complex(b["g_to"], b["b_to"])
    return (
        id = b["index"],
        from = ids[b["f_bus"]],
        to = ids[b["t_bus"]],
        gff = real(yff),
        bff = imag(yff),
        gft = real(yft),
        bft = imag(yft),
        gtf = real(ytf),
        btf = imag(ytf),
        gtt = real(ytt),
        btt = imag(ytt),
        rate = rate,
        amin = b["angmin"],
        amax = b["angmax"],
    )
end

function _validate(data)
    data.hinge_encoding in (:separate, :shared) ||
        throw(ArgumentError("unknown hinge encoding"))
    nb = length(data.buses)
    original = _network_records(data.pm)
    all(key -> getproperty(data, key) == getproperty(original, key), keys(original)) ||
        throw(ArgumentError("network records disagree with pm; use transmission_overlay"))
    seen = Set([data.reference_bus])
    for _ in 1:nb
        for b in data.branches
            if b.from in seen || b.to in seen
                push!(seen, b.from, b.to)
            end
        end
    end
    length(seen) == nb || throw(ArgumentError("disconnected AC network"))
    length(unique(c.id for c in data.controllers)) == length(data.controllers) ||
        throw(ArgumentError("controller IDs must be unique"))
    for c in data.controllers
        c.bus isa Int && 1 <= c.bus <= nb ||
            throw(ArgumentError("controller bus out of range"))
        all(isfinite, (c.p_available, c.smax, c.qmin, c.qmax, c.cost, c.quadratic_cost)) &&
        c.p_available >= 0 &&
        c.smax > 0 &&
        c.qmin <= c.qmax || throw(ArgumentError("invalid controller ratings"))
        for curve in (c.vv, c.vw)
            isnothing(curve) && continue
            # Revalidate custom records as well as factory-created profiles.
            opf_curve(curve.knots, curve.values)
        end
        !isnothing(c.vw) &&
            minimum(c.vw.values) < 0 &&
            throw(ArgumentError("negative VW cap"))
    end
    isempty(data.targets) ||
        Set(t.id for t in data.targets) == Set(c.id for c in data.controllers) ||
        throw(ArgumentError("targets must cover each controller exactly once"))
    length(unique(t.id for t in data.targets)) == length(data.targets) ||
        throw(ArgumentError("duplicate coverage targets"))
    for t in data.targets
        c = only(filter(c -> c.id == t.id, data.controllers))
        b = data.buses[c.bus]
        isempty(intersect(t.tight, t.slack)) ||
            throw(ArgumentError("target limit cannot be both tight and slack"))
        for key in (t.tight..., t.slack...)
            key in (:availability, :volt_watt, :capability, :p_lower, :q_lower, :q_upper) ||
                throw(ArgumentError("unknown controller limit"))
            key == :volt_watt &&
                isnothing(c.vw) &&
                throw(ArgumentError("target requires disabled VW limit"))
        end
        # VV and VW share one voltage; intersect their region/fraction windows.
        lo, hi = b.vmin, b.vmax
        lo_open, hi_open = false, false
        for (curve, region, key) in
            ((c.vv, t.vv_region, :vv_position), (c.vw, t.vw_region, :vw_position))
            window = hasproperty(t, key) ? getproperty(t, key) : nothing
            a, z, a_open, z_open = _target_voltage_interval(curve, region, window)
            if a > lo
                lo, lo_open = a, a_open
            elseif a == lo
                lo_open |= a_open
            end
            if z < hi
                hi, hi_open = z, z_open
            elseif z == hi
                hi_open |= z_open
            end
        end
        (lo < hi || lo == hi && !lo_open && !hi_open) ||
            throw(ArgumentError("VV/VW targets have no common voltage within bus bounds"))
    end
    for t in data.network_targets
        records =
            t.kind == :bus ? data.buses :
            t.kind == :generator ? data.generators :
            t.kind == :branch ? data.branches :
            throw(ArgumentError("unknown network target kind"))
        any(r -> r.id == t.id, records) || throw(ArgumentError("unknown network target ID"))
        limits =
            t.kind == :bus ? (:lower, :upper) :
            t.kind == :generator ? (:p_lower, :p_upper, :q_lower, :q_upper) :
            (:from, :to, :angle_lower, :angle_upper)
        t.limit in limits && t.state in (:tight, :slack) ||
            throw(ArgumentError("invalid network target"))
    end
    return nothing
end

function _target_voltage_interval(curve, region, window)
    if isnothing(curve)
        region == :disabled && isnothing(window) ||
            throw(ArgumentError("invalid disabled-law target"))
        return -Inf, Inf, false, false
    end
    k = curve.knots
    regions =
        Dict(:below => (-Inf, first(k), true, true), :above => (last(k), Inf, true, true))
    for i in eachindex(k)
        regions[Symbol("knot_", i)] = (k[i], k[i], false, false)
        i < length(k) && (regions[Symbol("segment_", i)] = (k[i], k[i+1], true, true))
    end
    haskey(regions, region) || throw(ArgumentError("unknown curve region"))
    a, b, ao, bo = regions[region]
    if !isnothing(window)
        startswith(string(region), "segment_") ||
            throw(ArgumentError("fraction window requires a finite segment"))
        length(window) == 2 && all(isfinite, window) && 0 <= window[1] <= window[2] <= 1 ||
            throw(ArgumentError("invalid finite-segment target window"))
        width = b-a
        a, b = a+window[1]*width, a+window[2]*width
        ao, bo = window[1] == 0, window[2] == 1
    end
    return a, b, ao, bo
end

"""Variable/row maps. Shared encoding reuses exact `(bus,knot)` pairs across laws/devices."""
function transmission_layout(data)
    nb, ng, nc, ne = length(data.buses),
    length(data.generators),
    length(data.controllers),
    length(data.branches)
    v, theta = collect(1:nb), collect((nb+1):(2*nb))
    pg, qg = collect((2*nb+1):(2*nb+ng)), collect((2*nb+ng+1):(2*nb+2*ng))
    p, q = collect((2*nb+2*ng+1):(2*nb+2*ng+nc)), collect((2*nb+2*ng+nc+1):(2*nb+2*ng+2*nc))
    knots, devices = Float64[], Int[]
    vv_pairs, vw_pairs = [Int[] for _ in 1:nc], [Int[] for _ in 1:nc]
    shared = Dict{Tuple{Int,Float64},Int}()
    for (i, c) in enumerate(data.controllers)
        for (curve, pairs) in ((c.vv, vv_pairs[i]), (c.vw, vw_pairs[i]))
            isnothing(curve) && continue
            for k in curve.knots
                key = (c.bus, Float64(k))
                if data.hinge_encoding == :shared && haskey(shared, key)
                    push!(pairs, shared[key])
                else
                    push!(knots, k)
                    push!(devices, i)
                    shared[key] = length(knots)
                    push!(pairs, length(knots))
                end
            end
        end
    end
    nh = length(knots)
    offset = 2*nb+2*ng+2*nc
    r, s = collect((offset+1):(offset+nh)), collect((offset+nh+1):(offset+2*nh))
    vv_rows, vw_rows = zeros(Int, nc), zeros(Int, nc)
    row = nh
    for (i, c) in enumerate(data.controllers)
        for (curve, rows) in ((c.vv, vv_rows), (c.vw, vw_rows))
            isnothing(curve) && continue
            row += 1
            rows[i] = row
        end
    end
    angle = collect((row+1):(row+ne))
    nlin = row+ne
    balance_p, balance_q = collect((nlin+1):2:(nlin+2*nb)), collect((nlin+2):2:(nlin+2*nb))
    capability = collect((nlin+2*nb+1):(nlin+2*nb+nc))
    branch_from, branch_to = collect((nlin+2*nb+nc+1):2:(nlin+2*nb+nc+2*ne)),
    collect((nlin+2*nb+nc+2):2:(nlin+2*nb+nc+2*ne))
    return (;
        v,
        theta,
        pg,
        qg,
        p,
        q,
        r,
        s,
        knots,
        devices,
        vv_pairs,
        vw_pairs,
        vv_rows,
        vw_rows,
        angle,
        balance_p,
        balance_q,
        capability,
        branch_from,
        branch_to,
        nlin,
        nvar = offset+2*nh,
        ncon = nlin+2*nb+nc+2*ne,
    )
end

"""Transfer physical variables by matching IDs, then construct exact target hinges.

This maps physical starts between encodings/policy variants. It does not map
relaxed hinge iterates or duals, and does not project physical variables onto
bounds or claim the target laws are feasible. Both cases must have matching
ordered bus/generator/controller IDs and controller attachment buses.
"""
function transmission_start(data, source, x)
    a, b = transmission_layout(data), transmission_layout(source)
    length(x) == b.nvar && all(isfinite, x) || throw(ArgumentError("invalid source point"))
    for kind in (:buses, :generators, :controllers)
        [r.id for r in getproperty(data, kind)] == [r.id for r in getproperty(source, kind)] ||
            throw(ArgumentError("physical record IDs differ"))
    end
    [c.bus for c in data.controllers] == [c.bus for c in source.controllers] || throw(ArgumentError("controller attachment buses differ"))
    result = zeros(a.nvar)
    for key in (:v, :theta, :pg, :qg, :p, :q)
        result[getproperty(a, key)] .= x[getproperty(b, key)]
    end
    for h in eachindex(a.knots)
        delta = result[a.v[data.controllers[a.devices[h]].bus]]-a.knots[h]
        result[a.r[h]], result[a.s[h]] = max(delta, 0), max(-delta, 0)
    end
    return result
end

function transmission_flows(data, x, layout = transmission_layout(data))
    return map(data.branches) do b
        vf, vt = x[layout.v[b.from]], x[layout.v[b.to]]
        d = x[layout.theta[b.from]]-x[layout.theta[b.to]]
        co, si = cos(d), sin(d)
        return (
            pf = b.gff*vf^2+vf*vt*(b.gft*co+b.bft*si),
            qf = -b.bff*vf^2+vf*vt*(b.gft*si-b.bft*co),
            pt = b.gtt*vt^2+vf*vt*(b.gtf*co-b.btf*si),
            qt = -b.btt*vt^2+vf*vt*(-b.gtf*si-b.btf*co),
        )
    end
end

"""Canonical transmission NLP, or MPCC when any control law is enabled.

Reference voltage magnitude is optimized; only its angle is fixed. Conventional
generators retain PGLib P/Q boxes and polynomial costs. Added inverters have the
same hardware bounds in every law variant. VV is an equality and VW a cap.
Hinges use the formulation in `BalancedACOPFModel`; no priority/clipping policy.
The returned model is an ordinary ADNLPModel or MPCCModel, not a new model type.
"""
function TransmissionOPFModel(data; x0 = nothing)
    _validate(data)
    l = transmission_layout(data)
    nb, nc = length(data.buses), length(data.controllers)
    lower, upper = fill(-Inf, l.nvar), fill(Inf, l.nvar)
    for (i, b) in enumerate(data.buses)
        lower[l.v[i]], upper[l.v[i]] = b.vmin, b.vmax
    end
    lower[l.theta[data.reference_bus]] = upper[l.theta[data.reference_bus]] = 0.0
    for (i, g) in enumerate(data.generators)
        lower[l.pg[i]], upper[l.pg[i]] = g.pmin, g.pmax
        lower[l.qg[i]], upper[l.qg[i]] = g.qmin, g.qmax
    end
    for (i, c) in enumerate(data.controllers)
        lower[l.p[i]], upper[l.p[i]] = 0.0, c.p_available
        lower[l.q[i]], upper[l.q[i]] = c.qmin, c.qmax
    end
    lower[l.r] .= 0
    lower[l.s] .= 0
    if isnothing(x0)
        x0 = zeros(l.nvar)
        for (i, b) in enumerate(data.buses)
            x0[l.v[i]] = clamp(1.0, b.vmin, b.vmax)
        end
        for (i, g) in enumerate(data.generators)
            x0[l.pg[i]] = (g.pmin+g.pmax)/2
            x0[l.qg[i]] = (g.qmin+g.qmax)/2
        end
        for (i, c) in enumerate(data.controllers)
            x0[l.p[i]] = min(c.p_available, c.smax)/2
            q = opf_volt_var(x0[l.v[c.bus]], c)
            x0[l.q[i]] = clamp(isnothing(q) ? 0.0 : q, c.qmin, c.qmax)
        end
        for h in eachindex(l.knots)
            d = x0[l.v[data.controllers[l.devices[h]].bus]]-l.knots[h]
            x0[l.r[h]], x0[l.s[h]] = max(d, 0), max(-d, 0)
        end
    else
        length(x0) == l.nvar || throw(DimensionMismatch("incorrect starting vector"))
        x0 = Float64.(x0)
    end
    all(isfinite, x0) || throw(ArgumentError("nonfinite start"))
    rows, cols, vals = Int[], Int[], Float64[]
    lc, uc = fill(-Inf, l.ncon), fill(Inf, l.ncon)
    for h in eachindex(l.knots)
        bus = data.controllers[l.devices[h]].bus
        append!(rows, [h, h, h])
        append!(cols, [l.r[h], l.s[h], l.v[bus]])
        append!(vals, [1.0, -1.0, -1.0])
        lc[h] = uc[h] = -l.knots[h]
    end
    for (i, c) in enumerate(data.controllers)
        for (curve, pairs, row, index, equality) in (
            (c.vv, l.vv_pairs[i], l.vv_rows[i], l.q[i], true),
            (c.vw, l.vw_pairs[i], l.vw_rows[i], l.p[i], false),
        )
            isnothing(curve) && continue
            append!(rows, fill(row, 1+length(pairs)))
            append!(cols, [index; l.r[pairs]])
            append!(vals, [1.0; -_opf_curve_weights(curve)])
            uc[row] = first(curve.values)
            equality && (lc[row] = uc[row])
        end
    end
    for (i, b) in enumerate(data.branches)
        append!(rows, [l.angle[i], l.angle[i]])
        append!(cols, [l.theta[b.from], l.theta[b.to]])
        append!(vals, [1.0, -1.0])
        lc[l.angle[i]], uc[l.angle[i]] = b.amin, b.amax
        uc[l.branch_from[i]] = uc[l.branch_to[i]] = b.rate^2
    end
    lc[l.balance_p] .= 0
    uc[l.balance_p] .= 0
    lc[l.balance_q] .= 0
    uc[l.balance_q] .= 0
    for (i, c) in enumerate(data.controllers)
        uc[l.capability[i]] = c.smax^2
    end
    function objective(x)
        f = zero(eltype(x))
        for (i, g) in enumerate(data.generators)
            f += g.c2*x[l.pg[i]]^2+g.c1*x[l.pg[i]]+g.c0
        end
        for (i, c) in enumerate(data.controllers)
            f += c.cost*x[l.p[i]]+c.quadratic_cost*x[l.p[i]]^2/2
        end
        return f
    end
    function constraints(x)
        c = zeros(eltype(x), l.ncon-l.nlin)
        for (i, b) in enumerate(data.buses)
            c[2*i-1] = -b.pd-b.gs*x[l.v[i]]^2
            c[2*i] = -b.qd+b.bs*x[l.v[i]]^2
        end
        for (i, g) in enumerate(data.generators)
            c[2*g.bus-1] += x[l.pg[i]]
            c[2*g.bus] += x[l.qg[i]]
        end
        for (i, d) in enumerate(data.controllers)
            c[2*d.bus-1] += x[l.p[i]]
            c[2*d.bus] += x[l.q[i]]
            c[2*nb+i] = x[l.p[i]]^2+x[l.q[i]]^2
        end
        for (i, (b, f)) in enumerate(zip(data.branches, transmission_flows(data, x, l)))
            c[2*b.from-1] -= f.pf
            c[2*b.from] -= f.qf
            c[2*b.to-1] -= f.pt
            c[2*b.to] -= f.qt
            c[2*nb+nc+2*i-1] = f.pf^2+f.qf^2
            c[2*nb+nc+2*i] = f.pt^2+f.qt^2
        end
        return c
    end
    nlp = ADNLPModel(
        objective,
        x0,
        lower,
        upper,
        rows,
        cols,
        vals,
        constraints,
        lc,
        uc;
        name = "PGLib transmission OPF ($(data.name))",
    )
    return isempty(l.r) ? nlp : MPCCModel(nlp, l.r, l.s)
end

include("diagnostics.jl")
include("cases.jl")
include("studies.jl")
include("application-cases.jl")
include("application-expansion.jl")
include("application-policy-matrix.jl")
include("operating-conditions.jl")

end
