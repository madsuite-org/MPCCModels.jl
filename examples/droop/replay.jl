"""Replay physical VM/VA/PG/QG using complex terminal currents and direct clipping.
No optimization, auxiliary-variable repair, Ybus or model constraint callbacks.
"""
function replay(data, state)
    c = data.case
    buses = c["network"]["buses"]
    ids = Dict(b["id"] => i for (i, b) in enumerate(buses))
    vm, va, pg, qg = (state[k] for k in ("vm", "va", "pg", "qg"))
    length(vm) == length(va) == length(buses) || throw(DimensionMismatch("voltage"))
    length(pg) == length(qg) == length(c["generators"]) ||
        throw(DimensionMismatch("generation"))
    all(isfinite, vcat(vm, va, pg, qg)) ||
        return (; valid = false, balance = Inf, droop = Inf, limits = Inf, loss = Inf)
    v = vm .* cis.(va)
    residual = zeros(ComplexF64, length(buses))
    limits = 0.0
    for b in c["network"]["branches"]
        b["available"] || continue
        i, j = ids[b["from_bus"]], ids[b["to_bus"]]
        internal = v[i] / (b["tap_ratio"]*cis(b["phase_shift"]))
        series = (internal-v[j]) / complex(b["resistance"], b["reactance"])
        charging = complex(0, b["charging"]/2)
        sf = internal*conj(series+charging*internal)
        st = v[j]*conj(-series+charging*v[j])
        residual[i] -= sf
        residual[j] -= st
        lo, hi = data.angles[string(b["id"])]
        limits = max(
            limits,
            abs(sf)-b["thermal_limit"],
            abs(st)-b["thermal_limit"],
            lo-(va[i]-va[j]),
            va[i]-va[j]-hi,
        )
    end
    for s in c["network"]["shunts"]
        s["available"] || continue
        i = ids[s["bus_id"]]
        residual[i] -= abs2(v[i])*complex(s["conductance"], -s["susceptance"])
    end
    for s in c["network"]["banks"]
        s["available"] || continue
        i = ids[s["bus_id"]]
        for k in eachindex(s["state"])
            residual[i] -=
                abs2(v[i])*s["state"][k]*complex(
                    s["step_conductances"][k],
                    -s["step_susceptances"][k],
                )
        end
    end
    for (i, g) in enumerate(c["generators"])
        if g["available"]
            residual[ids[g["bus_id"]]] += complex(pg[i], qg[i])
            limits = max(
                limits,
                g["p_min"]-pg[i],
                pg[i]-g["p_max"],
                g["q_min"]-qg[i],
                qg[i]-g["q_max"],
            )
        else
            limits = max(limits, abs(pg[i]), abs(qg[i]))
        end
    end
    for load in c["loads"]
        residual[ids[load["bus_id"]]] -= complex(load["p"], load["q"])
    end
    for (i, b) in enumerate(buses)
        limits = max(limits, b["v_min"]-vm[i], vm[i]-b["v_max"], abs(va[i])-pi)
        b["reference"] && (limits=max(limits, abs(va[i])))
    end
    gidx = Dict(g["id"]=>i for (i, g) in enumerate(c["generators"]))
    droop = 0.0
    for a in c["attachments"]
        i = gidx[a["generator_id"]]
        g = c["generators"][i]
        g["available"] || continue
        ctrl = c["controls"][a["control_id"]]
        s = ctrl["schedule"]
        cap = ctrl["capability"]
        voltage = vm[ids[a["location"]["bus_id"]]]
        raw =
            ctrl["q_at_deadband"]+(
                max(s["v_db_low"]-voltage, 0)-max(voltage-s["v_db_high"], 0)
            )/ctrl["slope"]
        target = clamp(raw, max(g["q_min"], cap["q_min"]), min(g["q_max"], cap["q_max"]))
        droop = max(droop, abs(qg[i]-target))
        limits = max(limits, cap["p_min"]-pg[i], pg[i]-cap["p_max"])
    end
    balance = maximum(abs, vcat(real.(residual), imag.(residual)))
    loss = sum(pg)-sum(l["p"] for l in c["loads"])
    return (;
        valid = balance<=1e-6 && droop<=1e-5 && limits<=1e-6,
        balance,
        droop,
        limits,
        loss,
    )
end

function physical_state(built, x)
    return Dict(
        string(k)=>[x[JuMP.index(v).value] for v in getproperty(built.layout, k)] for
        k in (:vm, :va, :pg, :qg)
    )
end
