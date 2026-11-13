module DroopExamples

using JSON, JuMP, NLPModels, NLPModelsJuMP, MPCCModels, LogExpFunctions

export droop_case, build_droop, lift_state, replay, model_residuals
const DATA = joinpath(@__DIR__, "data")

"""Load a nominal 500-bus fixed-control case: :zero, :narrow or :wide.
All powers use the 100 MVA system base; voltage angles are radians.
"""
function droop_case(name::Symbol)
    name in (:zero, :narrow, :wide) || throw(ArgumentError("unknown droop case: $name"))
    data = JSON.parsefile(joinpath(DATA, "network.json"))
    meta = JSON.parsefile(joinpath(DATA, "provenance.json"))["cases"][string(name)]
    for control in data["case"]["controls"]
        schedule = control["schedule"]
        schedule["v_db_low"] = schedule["v_ref"] - meta["half_width"]
        schedule["v_db_high"] = schedule["v_ref"] + meta["half_width"]
    end
    states = JSON.parsefile(joinpath(DATA, "$name.json"))
    states["start"] = JSON.parsefile(joinpath(DATA, "start.json"))
    angles = Dict(
        string(b["id"])=>data["angle_limit"] for b in data["case"]["network"]["branches"]
    )
    return (; name, case = data["case"], angles, meta, states)
end

function primitives(data)
    c = data.case
    buses = c["network"]["buses"]
    indices = Dict(b["id"] => i for (i, b) in enumerate(buses))
    branches = filter(b -> b["available"], c["network"]["branches"])
    terminal = map(branches) do b
        y = inv(complex(b["resistance"], b["reactance"]))
        yc = complex(0, b["charging"] / 2)
        a = b["tap_ratio"] * cis(b["phase_shift"])
        return (;
            from = indices[b["from_bus"]],
            to = indices[b["to_bus"]],
            ff = (y+yc)/abs2(a),
            ft = -y/conj(a),
            tf = -y/a,
            tt = y+yc,
            branch = b,
        )
    end
    shunts = zeros(ComplexF64, length(buses))
    for s in c["network"]["shunts"]
        s["available"] || continue
        shunts[indices[s["bus_id"]]] += complex(s["conductance"], s["susceptance"])
    end
    for s in c["network"]["banks"]
        s["available"] || continue
        shunts[indices[s["bus_id"]]] +=
            sum(s["state"] .* complex.(s["step_conductances"], s["step_susceptances"]))
    end
    pd, qd = zeros(length(buses)), zeros(length(buses))
    for load in c["loads"]
        pd[indices[load["bus_id"]]] += load["p"]
        qd[indices[load["bus_id"]]] += load["q"]
    end
    return (; buses, indices, terminal, shunts, pd, qd)
end

"""Build the exact vertical-form MPCC, without loading or invoking a solver.
The optional start is a physical VM/VA/PG/QG record, lifted to auxiliary variables.
The smooth and product-relaxed variants are benchmark helpers, not MPCCModel results.
"""
function build_droop(
    data;
    start = data.states["start"],
    encoding = :exact,
    epsilon = 1e-7,
    sigma = 1e-8,
)
    encoding in (:exact, :smooth, :relaxed) || throw(ArgumentError("unknown encoding"))
    epsilon > 0 && sigma >= 0 || throw(ArgumentError("invalid numerical parameter"))
    p = primitives(data)
    c = data.case
    generators, controls = c["generators"], c["controls"]
    nb, ng = length(p.buses), length(generators)
    gindex = Dict(g["id"] => i for (i, g) in enumerate(generators))
    model = Model()
    if encoding == :smooth
        JuMP.register(
            model,
            :softplus,
            1,
            z -> epsilon*log1pexp(z/epsilon);
            autodiff = true,
        )
    end
    @variable(model, vm[1:nb])
    @variable(model, va[1:nb])
    @variable(model, pg[1:ng])
    @variable(model, qg[1:ng])
    for (i, bus) in enumerate(p.buses)
        set_lower_bound(vm[i], bus["v_min"])
        set_upper_bound(vm[i], bus["v_max"])
        set_lower_bound(va[i], -pi)
        set_upper_bound(va[i], pi)
        bus["reference"] && fix(va[i], 0; force = true)
    end
    for (i, g) in enumerate(generators)
        isnothing(g["s_rated"]) ||
            throw(ArgumentError("this collection uses box capability only"))
        if g["available"]
            set_lower_bound(pg[i], g["p_min"])
            set_upper_bound(pg[i], g["p_max"])
            set_lower_bound(qg[i], g["q_min"])
            set_upper_bound(qg[i], g["q_max"])
        else
            fix(pg[i], 0; force = true)
            fix(qg[i], 0; force = true)
        end
    end
    # Branch-end powers use the full pi model with a from-side complex tap.
    flows = map(p.terminal) do t
        i, j = t.from, t.to
        gff, bff, gft, bft, gtf, btf, gtt, btt = real(t.ff),
        imag(t.ff),
        real(t.ft),
        imag(t.ft),
        real(t.tf),
        imag(t.tf),
        real(t.tt),
        imag(t.tt)
        pf = @NLexpression(
            model,
            gff*vm[i]^2 + vm[i]*vm[j]*(gft*cos(va[i]-va[j]) + bft*sin(va[i]-va[j]))
        )
        qf = @NLexpression(
            model,
            -bff*vm[i]^2 + vm[i]*vm[j]*(gft*sin(va[i]-va[j]) - bft*cos(va[i]-va[j]))
        )
        pt = @NLexpression(
            model,
            gtt*vm[j]^2 + vm[i]*vm[j]*(gtf*cos(va[j]-va[i]) + btf*sin(va[j]-va[i]))
        )
        qt = @NLexpression(
            model,
            -btt*vm[j]^2 + vm[i]*vm[j]*(gtf*sin(va[j]-va[i]) - btf*cos(va[j]-va[i]))
        )
        rate = t.branch["thermal_limit"]
        @NLconstraint(model, pf^2 + qf^2 <= rate^2)
        @NLconstraint(model, pt^2 + qt^2 <= rate^2)
        lo, hi = data.angles[string(t.branch["id"])]
        @constraint(model, lo <= va[i]-va[j] <= hi)
        return (; pf, qf, pt, qt)
    end
    for i in 1:nb
        gi = findall(g -> g["available"] && p.indices[g["bus_id"]] == i, generators)
        outgoing = findall(t -> t.from == i, p.terminal)
        incoming = findall(t -> t.to == i, p.terminal)
        g, b = real(p.shunts[i]), imag(p.shunts[i])
        pd, qd = p.pd[i], p.qd[i]
        @NLconstraint(
            model,
            sum(pg[k] for k in gi) - pd ==
            sum(flows[k].pf for k in outgoing) +
            sum(flows[k].pt for k in incoming) +
            g*vm[i]^2
        )
        @NLconstraint(
            model,
            sum(qg[k] for k in gi) - qd ==
            sum(flows[k].qf for k in outgoing) + sum(flows[k].qt for k in incoming) -
            b*vm[i]^2
        )
    end
    pairs = Tuple{VariableRef,VariableRef}[]
    aux = Any[]
    for attachment in c["attachments"]
        k = attachment["control_id"]
        ctrl = controls[k]
        i = gindex[attachment["generator_id"]]
        generators[i]["available"] || continue
        attachment["location"]["kind"] == "bus" ||
            throw(ArgumentError("expected bus regulation"))
        j = p.indices[attachment["location"]["bus_id"]]
        cap, schedule = ctrl["capability"], ctrl["schedule"]
        qlo, qhi = max(cap["q_min"], generators[i]["q_min"]),
        min(cap["q_max"], generators[i]["q_max"])
        set_lower_bound(pg[i], max(cap["p_min"], generators[i]["p_min"]))
        set_upper_bound(pg[i], min(cap["p_max"], generators[i]["p_max"]))
        m, q0 = ctrl["slope"], ctrl["q_at_deadband"]
        lo, hi = schedule["v_db_low"], schedule["v_db_high"]
        if encoding == :smooth
            # DroopOPF uses stable softplus and a difference of positive parts.
            raw = if lo == hi
                @NLexpression(model, q0+(lo-vm[j])/m)
            else
                @NLexpression(model, q0+(softplus(lo-vm[j])-softplus(vm[j]-hi))/m)
            end
            @NLconstraint(model, qg[i] == qlo+softplus(raw-qlo)-softplus(raw-qhi))
            continue
        end
        raw = @variable(model)
        sl = @variable(model, lower_bound=0)
        ml = @variable(model, lower_bound=0)
        su = @variable(model, lower_bound=0)
        mu = @variable(model, lower_bound=0)
        hinges = nothing
        if lo == hi
            @constraint(model, raw == q0 + (lo-vm[j])/m)
        else
            lower = @variable(model, lower_bound=0)
            lower_c = @variable(model, lower_bound=0)
            upper = @variable(model, lower_bound=0)
            upper_c = @variable(model, lower_bound=0)
            @constraint(model, lower_c-lower+lo-vm[j] == 0)
            @constraint(model, upper_c-upper+vm[j]-hi == 0)
            @constraint(model, raw == q0+(lower-upper)/m)
            append!(pairs, [(lower, lower_c), (upper, upper_c)])
            hinges = (; lower, lower_c, upper, upper_c)
        end
        @constraint(model, sl == qg[i]-qlo)
        @constraint(model, su == qhi-qg[i])
        @constraint(model, qg[i]-raw-ml+mu == 0)
        append!(pairs, [(sl, ml), (su, mu)])
        push!(aux, (; i, j, raw, sl, ml, su, mu, hinges, qlo, qhi, lo, hi, m, q0))
    end
    @objective(model, Min, sum(pg)-sum(p.pd))
    layout = (; vm, va, pg, qg, aux, pairs)
    x0 = lift_state(model, layout, start; project_q = true)
    for (v, x) in zip(all_variables(model), x0)
        set_start_value(v, x)
    end
    if encoding == :relaxed
        for (a, b) in pairs
            @constraint(model, a*b <= sigma)
        end
    end
    nlp = MathOptNLPModel(model; name = "Fixed droop 500 ($(data.name), $encoding)")
    # The adapter preserves JuMP variable order; assert this in the test suite.
    index(v) = JuMP.index(v).value
    mpcc =
        encoding == :exact ?
        MPCCModel(nlp, [index(a) for (a, b) in pairs], [index(b) for (a, b) in pairs]) :
        nothing
    return (; data, model, layout, nlp, mpcc)
end

function lift_state(model, layout, state; project_q = false)
    x = zeros(num_variables(model))
    put(v, z) = (x[JuMP.index(v).value] = z)
    for field in (:vm, :va, :pg, :qg)
        values = state[string(field)]
        length(values) == length(getproperty(layout, field)) ||
            throw(DimensionMismatch("$field length"))
        foreach(vz -> put(vz...), zip(getproperty(layout, field), values))
    end
    for a in layout.aux
        v = state["vm"][a.j]
        lower, upper = max(a.lo-v, 0), max(v-a.hi, 0)
        raw = a.q0+(lower-upper)/a.m
        q = project_q ? clamp(raw, a.qlo, a.qhi) : state["qg"][a.i]
        project_q && put(layout.qg[a.i], q)
        for (var, z) in (
            (a.raw, raw),
            (a.sl, q-a.qlo),
            (a.su, a.qhi-q),
            (a.ml, max(q-raw, 0)),
            (a.mu, max(raw-q, 0)),
        )
            put(var, z)
        end
        if a.hinges !== nothing
            for (var, z) in (
                (a.hinges.lower, lower),
                (a.hinges.lower_c, max(v-a.lo, 0)),
                (a.hinges.upper, upper),
                (a.hinges.upper_c, max(a.hi-v, 0)),
            )
                put(var, z)
            end
        end
    end
    return x
end
function lift_state(built, state; kwargs...)
    return lift_state(built.model, built.layout, state; kwargs...)
end

"""Bound, ordinary-constraint and complementarity residuals in original units."""
function model_residuals(built, x)
    nlp = built.nlp
    c = cons(nlp, x)
    bounds = maximum(max.(nlp.meta.lvar .- x, x .- nlp.meta.uvar, 0))
    constraints = maximum(max.(nlp.meta.lcon .- c, c .- nlp.meta.ucon, 0); init = 0.0)
    products = maximum(
        (
            abs(x[JuMP.index(a).value]*x[JuMP.index(b).value]) for
            (a, b) in built.layout.pairs
        );
        init = 0.0,
    )
    return (; bounds, constraints, products)
end

include("replay.jl")
end
