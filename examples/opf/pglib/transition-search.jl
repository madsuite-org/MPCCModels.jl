# Included inside HardCaseSearch; optional research cases, outside the regression registry.
export transition_case, transition_activity, run_transition_search, summarize_transitions

"""Three IEEE 118 controllers at bus 95; VV absorption knee and VW onset near `knee`.

All ratings, availability, hardware boxes and costs retain the original mixed-case
values. Only placement/laws and generator 45 (bus 100)'s Q upper bound change.
Power is system-base pu (100 MVA); voltage is pu. Coincident knots deliberately
retain separate hinges. These are search inputs, not accepted solved regimes.
"""
function transition_case(; knee = 1.02, offset = 0.0, qmax = 0.35)
    all(isfinite, (knee, offset, qmax)) || throw(ArgumentError("nonfinite case parameter"))
    d = pglib_control_case(:ieee118; targets = [], network_targets = [])
    vmin, vmax = d.buses[95].vmin, d.buses[95].vmax
    vmin <= knee-0.06 < knee+0.02 <= vmax &&
    vmin <= knee+offset < knee+offset+0.015 <= vmax ||
        throw(ArgumentError("transition knots must lie in the original voltage band"))
    -0.5 < qmax <= 1.55 ||
        throw(ArgumentError("Q upper limit must tighten the original nonfixed box"))
    cs = [
        opf_controller(
            c.id,
            95;
            smax = c.smax,
            p_available = c.p_available,
            qmin = c.qmin,
            qmax = c.qmax,
            cost = c.cost,
            quadratic_cost = c.quadratic_cost,
            vv = opf_curve(knee .+ [-0.06, -0.02, 0.0, 0.02], c.smax .* [0.4, 0, 0, -0.4]),
            vw = opf_curve([knee+offset, knee+offset+0.015], c.smax .* [0.8, 0.2]),
        ) for c in d.controllers
    ]
    return transmission_overlay(
        d;
        controllers = cs,
        generators = [(id = 45, qmax = qmax)],
        name = Symbol("ieee118_transition_", knee, "_", offset, "_", qmax),
    )
end

"""Achieved transition distances and nonfixed generator-Q tightness; feasibility is separate."""
function transition_activity(data, x; knee_tolerance = 1e-6, q_tolerance = 1e-6)
    all(t -> isfinite(t) && t > 0, (knee_tolerance, q_tolerance)) ||
        throw(ArgumentError("invalid activity tolerance"))
    l = transmission_layout(data)
    i = findfirst(g -> g.id == 45, data.generators)
    g = data.generators[i]
    vv = [abs(x[l.v[c.bus]]-c.vv.knots[3]) for c in data.controllers]
    vw = [abs(x[l.v[c.bus]]-c.vw.knots[1]) for c in data.controllers]
    margin = g.qmax-x[l.qg[i]]
    return Dict(
        "voltage"=>x[l.v[95]],
        "q45"=>x[l.qg[i]],
        "q45_upper_margin"=>margin,
        "q45_binding"=>g.qmax > g.qmin && abs(margin) <= q_tolerance,
        "vv_knee_distances"=>vv,
        "vw_knee_distances"=>vw,
        "simultaneous_controllers"=>count(
            j -> max(vv[j], vw[j]) <= knee_tolerance,
            eachindex(vv),
        ),
        "knee_tolerance"=>knee_tolerance,
        "q_tolerance"=>q_tolerance,
    )
end

function _save_transition(directory; knee, offset, qmax)
    data = transition_case(; knee, offset, qmax)
    key = "transition-"*_digest(Dict("knee"=>knee, "offset"=>offset, "qmax"=>qmax))[1:16]
    path = joinpath(directory, "cases", key, "input.toml")
    snapshot = _snapshot(data)
    if isfile(path)
        _digest(TOML.parsefile(path)) == _digest(snapshot) || error("stored case differs")
    else
        _write(path, snapshot)
    end
    return (; data, key, path)
end

"""Failure-retaining ratio-one matrix with independently labelled exact-sector witnesses.

A relaxed-Q neighboring case is solved separately. Its returned point selects
one consistent sector by hinge sign; only an independently verified sector point
can seed raw neighboring starts. Each case also has its own sector witness.
Raw homotopy runs are never refined or replaced. Perturbation seeds identify
separate actual start vectors; flat/neighbor/witness runs are not duplicated.
"""
function run_transition_search(
    directory;
    knee = 1.02,
    offsets = [-1e-4, 0.0, 1e-4],
    qmaxes = [0.2, 0.35, 0.5],
    seeds = [20261024, 20261025, 20261026],
    max_iter = 500,
    max_wall_time = 60.0,
    tolerance = 1e-5,
    witness_tolerance = 1e-7,
    resume = false,
    progress = true,
)
    !isempty(offsets) &&
    allunique(offsets) &&
    !isempty(qmaxes) &&
    allunique(qmaxes) &&
    !isempty(seeds) &&
    allunique(seeds) &&
    all(s -> s isa Int && s >= 0, seeds) || throw(ArgumentError("invalid matrix axes"))
    0 < witness_tolerance <= tolerance && isfinite(tolerance) ||
        throw(ArgumentError("invalid tolerances"))
    # Validate every input before creating the output directory.
    for offset in offsets, qmax in [1.55; qmaxes]
        transition_case(; knee, offset, qmax)
    end
    profile = solver_profile(:ratio_one; max_iter, max_wall_time)
    environment = _environment()
    plan = Dict(
        "schema"=>SCHEMA,
        "family"=>"ieee118_transitions_q45",
        "knee"=>knee,
        "offsets"=>offsets,
        "qmaxes"=>qmaxes,
        "seeds"=>seeds,
        "profile"=>_plain(profile),
        "tolerance"=>tolerance,
        "witness_tolerance"=>witness_tolerance,
        "environment"=>environment,
    )
    # Git commit may change when documenting results; source hashes remain strict.
    delete!(plan["environment"], "git_head")
    directory = abspath(directory)
    if ispath(directory)
        resume ||
            throw(ArgumentError("output already exists; choose a new directory or resume"))
        TOML.parsefile(joinpath(directory, "plan.toml")) == plan ||
            error("resume plan/source/environment mismatch")
    else
        mkpath(directory)
        _write(joinpath(directory, "plan.toml"), plan)
    end
    _capture_environment(directory, _environment())
    completed = 0
    for offset in offsets
        neighbor = _save_transition(directory; knee, offset, qmax = 1.55)
        setup = _ensure_trial(
            neighbor.data,
            nothing,
            profile,
            joinpath(directory, "setup"),
            neighbor.key;
            resume = true,
            role = "setup",
            start_label = "flat",
            case_file = neighbor.path,
            tolerance,
        )
        saved = read_trial(setup)
        seed_point = get(saved.result, "has_solution", false) ? _point(setup) : nothing
        neighbor_point, neighbor_trial = nothing, setup
        mask = nothing
        if !isnothing(seed_point) && all(isfinite, seed_point)
            l = transmission_layout(neighbor.data)
            mask = Vector{Bool}(seed_point[l.r] .> seed_point[l.s])
            neighbor_trial = _ensure_trial(
                neighbor.data,
                seed_point,
                profile,
                joinpath(directory, "setup"),
                neighbor.key*"-sector";
                resume = true,
                role = "witness",
                start_label = "setup_iterate",
                mask,
                case_file = neighbor.path,
                tolerance = witness_tolerance,
                provenance = Dict("selected_from"=>relpath(setup, directory)),
            )
            neighbor_point = verified_point(neighbor_trial; tolerance = witness_tolerance)
        end
        for qmax in qmaxes
            case = _save_transition(directory; knee, offset, qmax)
            if !isnothing(neighbor_point)
                attempt = _ensure_trial(
                    case.data,
                    neighbor_point,
                    profile,
                    joinpath(directory, "witnesses"),
                    case.key;
                    resume = true,
                    role = "witness",
                    start_label = "neighbor",
                    mask,
                    case_file = case.path,
                    tolerance = witness_tolerance,
                    provenance = Dict("selected_from"=>relpath(neighbor_trial, directory)),
                )
                _register_witness(directory, case, attempt; tolerance = witness_tolerance)
            end
            witness = _witness_reference(directory, case; tolerance = witness_tolerance)
            starts = [
                (:flat, -1),
                (:neighbor, -1),
                (:witness, -1),
                [(:perturbed_neighbor, s) for s in seeds]...,
            ]
            for (label, seed) in starts
                x =
                    label == :flat ? nothing :
                    label == :witness ? (isnothing(witness) ? nothing : witness.point) :
                    isnothing(neighbor_point) ? nothing :
                    label == :neighbor ? neighbor_point :
                    _perturb(case.data, neighbor_point, seed)
                provenance = Dict(
                    "case_key"=>case.key,
                    "knee"=>knee,
                    "offset"=>offset,
                    "qmax"=>qmax,
                    "seed"=>seed,
                    "neighbor_trial"=>relpath(neighbor_trial, directory),
                )
                !isnothing(witness) &&
                    (provenance["witness_trial"] = relpath(witness.trial, directory))
                id =
                    _digest(Dict("case"=>case.key, "start"=>string(label), "seed"=>seed))[1:20]
                path, done = _attempt(joinpath(directory, "trials"), id; resume = true)
                if !done
                    if label != :flat && isnothing(x)
                        _unavailable(
                            case.data,
                            profile,
                            case.path,
                            path;
                            label,
                            provenance,
                            reason = "requested start has no independently verified source point",
                        )
                    else
                        run_trial(
                            case.data,
                            x,
                            profile,
                            path;
                            start_label = label,
                            case_file = case.path,
                            tolerance,
                            provenance,
                        )
                    end
                end
                if isnothing(witness)
                    point = _register_witness(
                        directory,
                        case,
                        path;
                        tolerance = witness_tolerance,
                    )
                    !isnothing(point) && (witness = (point = point, trial = path))
                end
                completed += 1
                progress && println((
                    completed = completed,
                    total = length(offsets)*length(qmaxes)*(3+length(seeds)),
                    offset = offset,
                    qmax = qmax,
                    start = label,
                    seed = seed,
                    result = read_trial(path).result["classification"],
                ))
                flush(stdout)
            end
            summarize_transitions(directory)
        end
    end
    return summarize_transitions(directory)
end

"""Recheck witnesses and report every raw attempt, including original-activity diagnostics."""
function summarize_transitions(directory)
    rows = Dict{String,Any}[]
    for name in sort(readdir(joinpath(directory, "trials")))
        path = joinpath(directory, "trials", name)
        isfile(joinpath(path, "request.toml")) || continue
        saved = read_trial(path)
        p, r = saved.request, saved.result
        key = p["provenance"]["case_key"]
        file = normpath(joinpath(path, p["case_file"]))
        data = load_case(file; expected_sha = p["case_sha256"])
        case = (; data, key, path = file)
        witness = _witness_reference(
            directory,
            case;
            tolerance = TOML.parsefile(joinpath(directory, "plan.toml"))["witness_tolerance"],
        )
        category = r["state"] == "complete" ? r["classification"] : "unfinished"
        row = merge(
            copy(p["provenance"]),
            Dict{String,Any}(
                "trial"=>relpath(path, directory),
                "trial_id"=>first(split(name, "-attempt-")),
                "start"=>p["start_label"],
                "status"=>get(r, "status", "unfinished"),
                "classification"=>category,
                "finding"=>category == "solver_failure" ?
                           (
                    isnothing(witness) ? "unresolved_feasibility" :
                    "known_feasible_failure"
                ) : category,
                "witness_available"=>!isnothing(witness),
                "iterations"=>get(r, "iterations", -1),
                "physically_feasible"=>get(r, "physically_feasible", false),
            ),
        )
        if get(r, "has_solution", false)
            row["activity"] = transition_activity(data, _point(path))
            row["residuals"] = get(r, "residuals", Dict())
        end
        !isnothing(witness) &&
            (row["witness_activity"] = transition_activity(data, witness.point))
        push!(rows, row)
    end
    latest = Dict{String,Dict{String,Any}}()
    for row in rows
        latest[row["trial_id"]] = row
    end
    for row in rows
        row["superseded"] = latest[row["trial_id"]] !== row
    end
    _write(joinpath(directory, "summary.toml"), Dict("schema"=>SCHEMA, "trials"=>rows))
    columns = [
        "trial",
        "superseded",
        "offset",
        "qmax",
        "start",
        "seed",
        "status",
        "classification",
        "finding",
        "witness_available",
        "physically_feasible",
        "iterations",
    ]
    open(joinpath(directory, "summary.tsv"), "w") do io
        println(io, join(columns, '\t'))
        for row in rows
            println(io, join([_cell(row[k]) for k in columns], '\t'))
        end
    end
    return rows
end
