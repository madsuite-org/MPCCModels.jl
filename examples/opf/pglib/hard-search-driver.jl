# Persistence/experiment orchestration; included inside HardCaseSearch.
function _source_files()
    files = [
        joinpath(HERE, n) for n in (
            "transmission-opf.jl",
            "cases.jl",
            "application-cases.jl",
            "application-expansion.jl",
            "application-policy-matrix.jl",
            "operating-conditions.jl",
            "operating-search.jl",
            "search-operating-conditions.jl",
            "studies.jl",
            "diagnostics.jl",
            "hard-search.jl",
            "benchmark-evidence.jl",
            "hard-search-driver.jl",
            "transition-search.jl",
            "search-trace.jl",
            "reduction-search.jl",
            "search-reductions.jl",
            "application-search.jl",
            "search-applications.jl",
            "expansion-search.jl",
            "search-expansions.jl",
            "search-hard-cases.jl",
            "Project.toml",
        )
    ]
    append!(
        files,
        [
            joinpath(HERE, "..", n) for
            n in ("balanced-ac-opf.jl", "data.jl", "cases.jl", "diagnostics.jl")
        ],
    )
    push!(files, joinpath(HERE, "hard-cases", "evidence", "index.toml"))
    push!(files, joinpath(ROOT, "Project.toml"))
    for (directory, _, names) in walkdir(joinpath(ROOT, "src"))
        append!(files, [joinpath(directory, n) for n in names if endswith(n, ".jl")])
    end
    return sort!(normpath.(files))
end

function _environment()
    files = _source_files()
    hashes = Dict(relpath(f, ROOT)=>_sha(f) for f in files)
    versions = Dict(
        "CCOpt"=>string(pkgversion(CCOpt)),
        "MadNLP"=>string(pkgversion(CCOpt.MadNLP)),
        "MPCCModels"=>string(pkgversion(MPCCModels)),
        "NLPModels"=>string(pkgversion(NLPModels)),
        "ADNLPModels"=>string(pkgversion(TransmissionOPF.ADNLPModels)),
        "PowerModels"=>string(pkgversion(TransmissionOPF.PowerModels)),
    )
    revision = try
        readchomp(`git -C $ROOT rev-parse HEAD`)
    catch
        "unavailable"
    end
    return Dict(
        "julia"=>string(VERSION),
        "packages"=>versions,
        "source_hashes"=>hashes,
        "source_fingerprint"=>_digest(hashes),
        "git_head"=>revision,
        "cpu"=>Sys.CPU_NAME,
        "kernel"=>string(Sys.KERNEL),
        "architecture"=>string(Sys.ARCH),
        "julia_threads"=>Threads.nthreads(),
        "active_project_sha256"=>_sha(Base.active_project()),
        "manifest_sha256"=>isfile(
            joinpath(dirname(Base.active_project()), "Manifest.toml"),
        ) ? _sha(joinpath(dirname(Base.active_project()), "Manifest.toml")) : "unavailable",
    )
end

function _capture_environment(directory, environment)
    isfile(joinpath(directory, "environment.toml")) ||
        _write(joinpath(directory, "environment.toml"), environment)
    for f in _source_files()
        target = joinpath(directory, "source", relpath(f, ROOT))
        mkpath(dirname(target))
        isfile(target) ? (_sha(target) == _sha(f) || error("captured source differs")) :
        cp(f, target)
    end
    mkpath(joinpath(directory, "environment"))
    for name in ("Project.toml", "Manifest.toml")
        path = joinpath(dirname(Base.active_project()), name)
        target = joinpath(directory, "environment", name)
        isfile(path) && !isfile(target) && cp(path, target)
    end
    for name in ("LICENSE", "README.md")
        source = joinpath(HERE, "data", name)
        target = joinpath(directory, "source_data", name)
        mkpath(dirname(target))
        isfile(target) || cp(source, target)
    end
    return nothing
end

function _attempt(parent, id; resume)
    mkpath(parent)
    names = sort(filter(n -> startswith(n, id*"-attempt-"), readdir(parent)))
    if !isempty(names)
        resume || throw(ArgumentError("attempt already exists"))
        for name in reverse(names)
            path = joinpath(parent, name)
            if isfile(joinpath(path, "request.toml")) &&
               isfile(joinpath(path, "result.toml"))
                saved = read_trial(path)
                saved.result["state"] == "complete" && return (path, true)
            end
        end
    end
    # A running/incomplete attempt stays untouched; resume creates a new one.
    return (joinpath(parent, id*"-attempt-"*lpad(length(names)+1, 3, '0')), false)
end

function _ensure_trial(data, start, profile, parent, id; resume, kwargs...)
    path, done = _attempt(parent, id; resume)
    done || run_trial(data, start, profile, path; kwargs...)
    return path
end

function _point(path)
    return Float64.(TOML.parsefile(joinpath(path, "solution.toml"))["x"])
end

function _perturb(data, point, seed)
    model = TransmissionOPFModel(data)
    l = transmission_layout(data)
    rng = MersenneTwister(seed)
    x = copy(point)
    x[l.v] .+= 0.005 .* (2 .* rand(rng, length(l.v)) .- 1)
    x[l.theta] .+= 0.01 .* (2 .* rand(rng, length(l.theta)) .- 1)
    for (i, c) in enumerate(data.controllers)
        x[l.p[i]] += 0.02*c.smax*(2*rand(rng)-1)
        x[l.q[i]] += 0.02*c.smax*(2*rand(rng)-1)
    end
    x .= clamp.(x, get_lvar(model), get_uvar(model))
    # Recompute hinges from voltage, keeping perturbation physically interpretable.
    for h in eachindex(l.knots)
        difference = x[l.v[data.controllers[l.devices[h]].bus]]-l.knots[h]
        x[l.r[h]], x[l.s[h]] = max(difference, 0), max(-difference, 0)
    end
    return x
end

function _save_case(directory, factor)
    data = capability_case(factor)
    key = "cap-"*_digest(Dict("factor"=>factor))[1:12]
    path = joinpath(directory, "cases", key, "input.toml")
    snapshot = _snapshot(data)
    if isfile(path)
        _digest(TOML.parsefile(path)) == _digest(snapshot) ||
            error("stored case differs from requested case")
    else
        _write(path, snapshot)
    end
    return (; data, key, path)
end

function _register_witness(directory, case, trial; tolerance)
    read_trial(trial).request["case_sha256"] == _sha(case.path) ||
        error("witness belongs to another case")
    point = verified_point(trial; tolerance)
    isnothing(point) && return nothing
    _write(
        joinpath(directory, "cases", case.key, "witness.toml"),
        Dict(
            "trial"=>relpath(trial, directory),
            "verified_tolerance"=>tolerance,
            "solution_sha256"=>_sha(joinpath(trial, "solution.toml")),
            "verified_utc"=>_utc(),
        ),
    )
    return point
end

function _witness_reference(directory, case; tolerance)
    path = joinpath(directory, "cases", case.key, "witness.toml")
    isfile(path) || return nothing
    record = TOML.parsefile(path)
    trial = normpath(joinpath(directory, record["trial"]))
    _sha(joinpath(trial, "solution.toml")) == record["solution_sha256"] ||
        error("witness checksum mismatch")
    read_trial(trial).request["case_sha256"] == _sha(case.path) ||
        error("witness belongs to another case")
    x = verified_point(trial; tolerance)
    isnothing(x) && return nothing
    return (; point = x, trial)
end

function _unavailable(data, c, case_file, directory; label, provenance, reason)
    mkpath(directory)
    start = _write(joinpath(directory, "start.toml"), Dict("available"=>false))
    _write(
        joinpath(directory, "request.toml"),
        Dict(
            "schema"=>SCHEMA,
            "role"=>"raw",
            "start_label"=>string(label),
            "profile"=>_plain(c),
            "case_file"=>relpath(case_file, directory),
            "case_sha256"=>_sha(case_file),
            "start_sha256"=>_sha(start),
            "provenance"=>provenance,
        ),
    )
    _write(
        joinpath(directory, "result.toml"),
        Dict(
            "schema"=>SCHEMA,
            "state"=>"complete",
            "classification"=>"unavailable_start",
            "status"=>"not_run",
            "reason"=>reason,
            "solver_success"=>false,
            "physically_feasible"=>false,
            "has_solution"=>false,
            "completed_utc"=>_utc(),
        ),
    )
    return nothing
end

"""Run a resumable matrix; solver failures do not stop or disappear from the search.

Witness sectors come from the separately solved nominal case. They never choose
the raw homotopy sector. Raw starts are independently recorded; `witness` is an
explicit diagnostic start, not a replacement for a failed flat-start result.
"""
function run_search(
    directory;
    capabilities = [0.78, 0.80, 0.81, 0.82, 0.83, 0.84, 0.86, 1.0],
    starts = collect(STARTS),
    profiles = collect(PROFILES),
    seed::Int = 20261024,
    repetitions::Int = 1,
    max_iter::Int = 500,
    max_wall_time::Real = 60.0,
    tolerance::Real = 1e-5,
    witness_tolerance::Real = 1e-7,
    warmup::Bool = true,
    resume::Bool = false,
    progress::Bool = true,
)
    factors = Float64.(capabilities)
    !isempty(factors) && all(f -> isfinite(f) && f > 0, factors) && allunique(factors) ||
        throw(ArgumentError("invalid capability list"))
    !isempty(starts) && all(s -> s in STARTS, starts) && allunique(starts) ||
        throw(ArgumentError("invalid starts"))
    !isempty(profiles) && allunique(profiles) || throw(ArgumentError("invalid profiles"))
    settings = [solver_profile(p; max_iter, max_wall_time) for p in profiles]
    repetitions > 0 &&
    seed >= 0 &&
    isfinite(tolerance) &&
    isfinite(witness_tolerance) &&
    0 < witness_tolerance <= tolerance || throw(ArgumentError("invalid search controls"))
    environment = _environment()
    plan = Dict(
        "schema"=>SCHEMA,
        "capabilities"=>factors,
        "starts"=>string.(starts),
        "profiles"=>_plain(settings),
        "seed"=>seed,
        "repetitions"=>repetitions,
        "tolerance"=>Float64(tolerance),
        "witness_tolerance"=>Float64(witness_tolerance),
        "warmup"=>warmup,
        "source_fingerprint"=>environment["source_fingerprint"],
        "packages"=>environment["packages"],
        "julia"=>environment["julia"],
        "cpu"=>environment["cpu"],
        "julia_threads"=>environment["julia_threads"],
        "manifest_sha256"=>environment["manifest_sha256"],
        "active_project_sha256"=>environment["active_project_sha256"],
    )
    directory = abspath(directory)
    if ispath(directory)
        resume ||
            throw(ArgumentError("output already exists; choose a new directory or resume"))
        isfile(joinpath(directory, "plan.toml")) || error("output has no search plan")
        TOML.parsefile(joinpath(directory, "plan.toml")) == plan ||
            error("resume plan/source/environment mismatch")
    else
        mkpath(directory)
        _write(joinpath(directory, "plan.toml"), plan)
    end
    _capture_environment(directory, environment)
    nominal = _save_case(directory, 1.0)
    setup_profile = solver_profile(:current; max_iter, max_wall_time)
    seed_trial = _ensure_trial(
        nominal.data,
        nothing,
        setup_profile,
        joinpath(directory, "setup"),
        "nominal";
        resume = true,
        role = "setup",
        start_label = "flat",
        case_file = nominal.path,
        tolerance = witness_tolerance,
        provenance = Dict("factor"=>1.0),
    )
    nominal_point = verified_point(seed_trial; tolerance = witness_tolerance)
    # A separate exact-sector solve may also verify the nominal seed if its
    # raw homotopy did not reach the stricter witness threshold.
    if isnothing(nominal_point) && get(read_trial(seed_trial).result, "has_solution", false)
        x = _point(seed_trial)
        if all(isfinite, x)
            l = transmission_layout(nominal.data)
            mask = Vector{Bool}(x[l.r] .> x[l.s])
            attempt = _ensure_trial(
                nominal.data,
                x,
                setup_profile,
                joinpath(directory, "setup"),
                "nominal-sector";
                resume = true,
                role = "witness",
                start_label = "nominal_iterate",
                mask,
                case_file = nominal.path,
                tolerance = witness_tolerance,
                provenance = Dict(
                    "selected_from"=>relpath(seed_trial, directory),
                    "factor"=>1.0,
                ),
            )
            nominal_point = verified_point(attempt; tolerance = witness_tolerance)
            !isnothing(nominal_point) && (seed_trial = attempt)
        end
    end
    if warmup
        for c in settings
            _ensure_trial(
                nominal.data,
                nothing,
                c,
                joinpath(directory, "warmup"),
                string(c.name);
                resume = true,
                role = "warmup",
                start_label = "flat",
                case_file = nominal.path,
                tolerance,
                provenance = Dict("factor"=>1.0),
            )
        end
    end
    completed = 0
    for factor in factors
        case = _save_case(directory, factor)
        if !isnothing(nominal_point)
            l = transmission_layout(case.data)
            mask = Vector{Bool}(nominal_point[l.r] .> nominal_point[l.s])
            attempt = _ensure_trial(
                case.data,
                nominal_point,
                setup_profile,
                joinpath(directory, "witnesses"),
                case.key;
                resume = true,
                role = "witness",
                start_label = "neighbor",
                mask,
                case_file = case.path,
                tolerance = witness_tolerance,
                provenance = Dict(
                    "selected_from"=>relpath(seed_trial, directory),
                    "factor"=>factor,
                ),
            )
            _register_witness(directory, case, attempt; tolerance = witness_tolerance)
        end
        witness = _witness_reference(directory, case; tolerance = witness_tolerance)
        for repetition in 1:repetitions, label in starts, c in settings
            x =
                label == :flat ? nothing :
                label == :neighbor ? nominal_point :
                label == :perturbed_neighbor ?
                (
                    isnothing(nominal_point) ? nothing :
                    _perturb(case.data, nominal_point, seed+repetition-1)
                ) : isnothing(witness) ? nothing : witness.point
            provenance = Dict{String,Any}(
                "factor"=>factor,
                "case_key"=>case.key,
                "repeat"=>repetition,
                "seed"=>seed+repetition-1,
                "nominal_trial"=>relpath(seed_trial, directory),
            )
            !isnothing(witness) &&
                (provenance["witness_trial"] = relpath(witness.trial, directory))
            id = _digest(
                Dict(
                    "factor"=>factor,
                    "profile"=>_plain(c),
                    "start"=>string(label),
                    "repeat"=>repetition,
                ),
            )[1:20]
            path, done = _attempt(joinpath(directory, "trials"), id; resume = true)
            if !done
                if label != :flat && isnothing(x)
                    _unavailable(
                        case.data,
                        c,
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
                        c,
                        path;
                        start_label = label,
                        case_file = case.path,
                        tolerance,
                        provenance,
                    )
                end
            end
            saved = read_trial(path)
            if isnothing(witness) &&
               get(saved.result, "has_solution", false) &&
               haskey(saved.result, "residuals") &&
               maximum(values(saved.result["residuals"])) <= witness_tolerance
                point =
                    _register_witness(directory, case, path; tolerance = witness_tolerance)
                !isnothing(point) && (witness = (point = point, trial = path))
            end
            completed += 1
            progress && println((
                completed = completed,
                total = length(factors)*length(starts)*length(settings)*repetitions,
                factor = factor,
                start = label,
                profile = c.name,
                result = saved.result["classification"],
            ))
            flush(stdout)
        end
        summarize_search(directory)
    end
    return summarize_search(directory)
end

function _cell(x)
    return replace(string(x), '\t'=>' ', '\n'=>' ', '\r'=>' ')
end

"""Rebuild reports from stored trials, including interrupted attempts and all failures."""
function summarize_search(directory)
    rows = Dict{String,Any}[]
    witnesses = Dict{String,Bool}()
    parent = joinpath(directory, "trials")
    if isdir(parent)
        for name in sort(readdir(parent))
            path = joinpath(parent, name)
            isfile(joinpath(path, "request.toml")) || continue
            saved = read_trial(path)
            p, r = saved.request, saved.result
            key = p["provenance"]["case_key"]
            if !haskey(witnesses, key)
                file = joinpath(directory, "cases", key, "witness.toml")
                witnesses[key] = false
                if isfile(file)
                    ref = TOML.parsefile(file)
                    trial = normpath(joinpath(directory, ref["trial"]))
                    read_trial(trial).request["case_sha256"] ==
                    _sha(joinpath(directory, "cases", key, "input.toml")) ||
                        error("witness belongs to another case")
                    witnesses[key] =
                        !isnothing(
                            verified_point(trial; tolerance = ref["verified_tolerance"]),
                        )
                end
            end
            category = r["state"] == "complete" ? r["classification"] : "unfinished"
            tag =
                category == "solver_failure" ?
                (witnesses[key] ? "known_feasible_failure" : "unresolved_feasibility") :
                category == "physical_violation" ? "accuracy_gap" : category
            row = Dict{String,Any}(
                "trial"=>relpath(path, directory),
                "trial_id"=>first(split(name, "-attempt-")),
                "factor"=>p["provenance"]["factor"],
                "repeat"=>p["provenance"]["repeat"],
                "start"=>p["start_label"],
                "profile"=>p["profile"]["name"],
                "status"=>get(r, "status", "unfinished"),
                "classification"=>category,
                "finding"=>tag,
                "witness_available"=>witnesses[key],
                "solver_success"=>get(r, "solver_success", false),
                "physically_feasible"=>get(r, "physically_feasible", false),
                "iterations"=>get(r, "iterations", -1),
                "outer_seconds"=>get(r, "outer_seconds", NaN),
                "objective"=>get(r, "objective", NaN),
            )
            for k in (
                "constraints",
                "bounds",
                "physical_balance",
                "complementarity",
                "volt_var",
                "volt_watt",
            )
                row[k] = get(get(r, "residuals", Dict()), k, NaN)
            end
            push!(rows, row)
        end
    end
    latest = Dict{String,Dict{String,Any}}()
    for row in rows
        latest[row["trial_id"]] = row
    end
    for row in rows
        row["superseded"] = latest[row["trial_id"]] !== row
    end
    cases = Dict{String,Any}[]
    for factor in sort(unique([r["factor"] for r in rows]))
        selected = [r for r in values(latest) if r["factor"] == factor]
        push!(
            cases,
            Dict(
                "factor"=>factor,
                "trials"=>length(selected),
                "known_feasible_failures"=>count(
                    r -> r["finding"] == "known_feasible_failure",
                    selected,
                ),
                "accuracy_gaps"=>count(r -> r["finding"] == "accuracy_gap", selected),
                "successes"=>count(r -> r["classification"] == "success", selected),
                "exceptions"=>count(
                    r -> r["classification"] in ("exception", "diagnostic_error"),
                    selected,
                ),
                "unresolved_feasibility"=>count(
                    r -> r["finding"] == "unresolved_feasibility",
                    selected,
                ),
                "unavailable_starts"=>count(
                    r -> r["classification"] == "unavailable_start",
                    selected,
                ),
                "unfinished"=>count(r -> r["classification"] == "unfinished", selected),
                "witness_available"=>any(r -> r["witness_available"], selected),
            ),
        )
    end
    sort!(
        cases;
        by = c -> (-c["known_feasible_failures"], -c["accuracy_gaps"], c["factor"]),
    )
    _write(
        joinpath(directory, "summary.toml"),
        Dict("schema"=>SCHEMA, "trials"=>rows, "cases"=>cases),
    )
    open(joinpath(directory, "cases.tsv"), "w") do io
        headings = [
            "factor",
            "trials",
            "known_feasible_failures",
            "accuracy_gaps",
            "successes",
            "exceptions",
            "unresolved_feasibility",
            "unavailable_starts",
            "unfinished",
            "witness_available",
        ]
        println(io, join(headings, '\t'))
        for row in cases
            println(io, join([_cell(row[k]) for k in headings], '\t'))
        end
    end
    columns = [
        "trial",
        "superseded",
        "factor",
        "start",
        "profile",
        "repeat",
        "status",
        "classification",
        "finding",
        "witness_available",
        "solver_success",
        "physically_feasible",
        "iterations",
        "outer_seconds",
        "objective",
        "constraints",
        "bounds",
        "physical_balance",
        "complementarity",
        "volt_var",
        "volt_watt",
    ]
    open(joinpath(directory, "summary.tsv"), "w") do io
        println(io, join(columns, '\t'))
        for row in rows
            println(io, join([_cell(row[k]) for k in columns], '\t'))
        end
    end
    return rows
end
