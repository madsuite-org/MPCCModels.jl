# Application characterization uses the existing failure-retaining recorder.
export run_application_search, summarize_applications

function _save_application(
    directory,
    family,
    level,
    laws;
    network::Symbol = :ieee118,
    overrides = (;),
    hinge_encoding = :separate,
)
    data = application_case(
        family;
        network,
        level,
        laws,
        parameters = overrides,
        hinge_encoding,
    )
    key = "$(family)-$(level)-$(laws)"
    path = joinpath(directory, "cases", key, "input.toml")
    snapshot = _snapshot(data)
    isfile(path) ?
    (
        _digest(TOML.parsefile(path))==_digest(snapshot) ||
        error("stored application differs")
    ) : _write(path, snapshot)
    return (; data, key, path)
end

"""Characterize physical application families, keeping all raw outcomes and separate witnesses.

Both-law flat/profile trials run before witness work. Sector witnesses are
selected only from actual finite solver iterates, then from a verified neighboring
operating point if necessary. No desired region selects a sector. Dispatchable
counterfactuals are ordinary NLPs with identical physical inputs. Profiles/starts
and original physical feasibility are reported independently of intended effects.
"""
function run_application_search(
    directory;
    network::Symbol = :ieee118,
    families = collect(TransmissionOPF.APPLICATION_FAMILIES),
    levels = collect(TransmissionOPF.APPLICATION_LEVELS),
    profiles = [:current, :ratio_one],
    seeds = Int[],
    overrides = Dict{Symbol,NamedTuple}(),
    hinge_encoding = :separate,
    max_iter = 500,
    max_wall_time = 60.0,
    tolerance = 1e-5,
    witness_tolerance = 1e-7,
    trace_every = 0,
    resume = false,
    progress = true,
)
    all(a->!isempty(a) && allunique(a), (families, levels, profiles)) &&
    allunique(seeds) &&
    all(s->s isa Int && s>=0, seeds) &&
    all(k->k in families, keys(overrides)) &&
    isfinite(tolerance) &&
    0<witness_tolerance<=tolerance &&
    trace_every>=0 || throw(ArgumentError("invalid application search plan"))
    for family in families, level in levels
        application_case(
            family;
            network,
            level,
            parameters = get(overrides, family, (;)),
            hinge_encoding,
        )
    end
    settings = [solver_profile(p; max_iter, max_wall_time) for p in profiles]
    witness_profile = solver_profile(:current; max_iter, max_wall_time)
    environment = _environment()
    delete!(environment, "git_head")
    plan = Dict(
        "schema"=>SCHEMA,
        "family"=>"application_catalog",
        "network"=>string(network),
        "families"=>string.(families),
        "levels"=>string.(levels),
        "profiles"=>_plain(settings),
        "seeds"=>seeds,
        "overrides"=>_plain(overrides),
        "hinge_encoding"=>string(hinge_encoding),
        "tolerance"=>tolerance,
        "witness_tolerance"=>witness_tolerance,
        "trace_every"=>trace_every,
        "environment"=>environment,
    )
    directory = abspath(directory)
    if ispath(directory)
        resume ||
            throw(ArgumentError("output already exists; choose a new directory or resume"))
        TOML.parsefile(joinpath(directory, "plan.toml"))==plan ||
            error("resume plan/source/environment mismatch")
    else
        mkpath(directory)
        _write(joinpath(directory, "plan.toml"), plan)
    end
    _capture_environment(directory, _environment())
    warm = _save_application(
        directory,
        first(families),
        first(levels),
        :both;
        network,
        overrides = get(overrides, first(families), (;)),
        hinge_encoding,
    )
    for c in settings
        _ensure_trial(
            warm.data,
            nothing,
            merge(c, (max_iter = 1,)),
            joinpath(directory, "warmup"),
            string(c.name);
            resume = true,
            role = "warmup",
            start_label = "flat",
            case_file = warm.path,
            tolerance,
            trace_every,
        )
    end
    done_count=0
    total=length(families)*length(levels)*length(settings)*(2+length(seeds))
    for family in families
        neighbor=nothing
        for level in levels
            override=get(overrides, family, (;))
            case=_save_application(
                directory,
                family,
                level,
                :both;
                network,
                overrides = override,
                hinge_encoding,
            )
            baseline=_save_application(
                directory,
                family,
                level,
                :dispatchable;
                network,
                overrides = override,
                hinge_encoding,
            )
            _ensure_trial(
                baseline.data,
                nothing,
                witness_profile,
                joinpath(directory, "counterfactuals"),
                baseline.key;
                resume = true,
                role = "counterfactual",
                start_label = "flat",
                case_file = baseline.path,
                tolerance,
                trace_every,
                provenance = Dict("family"=>string(family), "level"=>string(level)),
            )
            provenance=Dict(
                "case_key"=>case.key,
                "family"=>string(family),
                "level"=>string(level),
                "seed"=>-1,
            )
            flats=String[]
            for c in settings
                path=_ensure_trial(
                    case.data,
                    nothing,
                    c,
                    joinpath(directory, "trials"),
                    "$(case.key)-flat-$(c.name)";
                    resume = true,
                    start_label = "flat",
                    case_file = case.path,
                    tolerance,
                    provenance,
                    trace_every,
                )
                push!(flats, path)
                done_count+=1
                progress && println((
                    completed = done_count,
                    total,
                    family,
                    level,
                    start = :flat,
                    profile = c.name,
                    result = read_trial(path).result["classification"],
                ))
                flush(stdout)
            end
            witness=_witness_reference(directory, case; tolerance = witness_tolerance)
            for (i, path) in enumerate(flats)
                !isnothing(witness) && break
                x=_register_witness(directory, case, path; tolerance = witness_tolerance)
                if !isnothing(x)
                    witness=(point = x, trial = path)
                    break
                end
                get(read_trial(path).result, "has_solution", false) || continue
                x=_point(path)
                all(isfinite, x) || continue
                l=transmission_layout(case.data)
                mask=Vector{Bool}(x[l.r] .> x[l.s])
                refined=_ensure_trial(
                    case.data,
                    x,
                    witness_profile,
                    joinpath(directory, "witnesses"),
                    "$(case.key)-from-$(settings[i].name)";
                    resume = true,
                    role = "witness",
                    start_label = "raw_iterate",
                    case_file = case.path,
                    tolerance = witness_tolerance,
                    mask,
                    provenance = Dict("selected_from"=>relpath(path, directory)),
                )
                point=_register_witness(
                    directory,
                    case,
                    refined;
                    tolerance = witness_tolerance,
                )
                !isnothing(point) && (witness=(point = point, trial = refined))
            end
            if isnothing(witness) && !isnothing(neighbor)
                x=transmission_start(case.data, neighbor.data, neighbor.point)
                l=transmission_layout(case.data)
                mask=Vector{Bool}(x[l.r] .> x[l.s])
                refined=_ensure_trial(
                    case.data,
                    x,
                    witness_profile,
                    joinpath(directory, "witnesses"),
                    "$(case.key)-neighbor";
                    resume = true,
                    role = "witness",
                    start_label = "neighbor",
                    case_file = case.path,
                    tolerance = witness_tolerance,
                    mask,
                    provenance = Dict("selected_from"=>relpath(neighbor.trial, directory)),
                )
                point=_register_witness(
                    directory,
                    case,
                    refined;
                    tolerance = witness_tolerance,
                )
                !isnothing(point) && (witness=(point = point, trial = refined))
            end
            !isnothing(witness) &&
                (neighbor=(data = case.data, point = witness.point, trial = witness.trial))
            for (label, seed) in
                [(:witness, -1), [(:perturbed_witness, s) for s in seeds]...],
                c in settings

                x=isnothing(witness) ? nothing :
                  label==:witness ? witness.point : _perturb(case.data, witness.point, seed)
                p=merge(copy(provenance), Dict("seed"=>seed))
                !isnothing(witness) &&
                    (p["witness_trial"]=relpath(witness.trial, directory))
                id="$(case.key)-$(label)-$(seed)-$(c.name)"
                path, done=_attempt(joinpath(directory, "trials"), id; resume = true)
                if !done
                    if isnothing(x)
                        _unavailable(
                            case.data,
                            c,
                            case.path,
                            path;
                            label,
                            provenance = p,
                            reason = "no independently verified witness; feasibility unresolved",
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
                            provenance = p,
                            trace_every,
                        )
                    end
                end
                done_count+=1
                progress && println((
                    completed = done_count,
                    total,
                    family,
                    level,
                    start = label,
                    profile = c.name,
                    result = read_trial(path).result["classification"],
                ))
                flush(stdout)
            end
            summarize_applications(directory)
        end
    end
    return summarize_applications(directory)
end

"""Recheck witnesses and characterize achieved physical activity, separately from difficulty."""
function summarize_applications(directory)
    rows=Dict{String,Any}[]
    cases=Dict{String,Any}()
    parent=joinpath(directory, "trials")
    isdir(parent) || return rows
    plan=TOML.parsefile(joinpath(directory, "plan.toml"))
    for name in sort(readdir(parent))
        path=joinpath(parent, name)
        isfile(joinpath(path, "request.toml")) || continue
        p, r=read_trial(path)
        input=normpath(joinpath(path, p["case_file"]))
        data=load_case(input; expected_sha = p["case_sha256"])
        key=p["provenance"]["case_key"]
        case=(; data, key, path = input)
        witness=_witness_reference(directory, case; tolerance = plan["witness_tolerance"])
        category=r["state"]=="complete" ? r["classification"] : "unfinished"
        l=transmission_layout(data)
        row=merge(
            copy(p["provenance"]),
            Dict{String,Any}(
                "trial"=>relpath(path, directory),
                "network"=>string(data.network),
                "trial_id"=>first(split(name, "-attempt-")),
                "start"=>p["start_label"],
                "profile"=>p["profile"]["name"],
                "status"=>get(r, "status", "unfinished"),
                "classification"=>category,
                "finding"=>category=="solver_failure" ?
                           (
                    isnothing(witness) ? "unresolved_feasibility" :
                    "known_feasible_failure"
                ) : category=="physical_violation" ? "accuracy_gap" : category,
                "witness_available"=>!isnothing(witness),
                "physically_feasible"=>get(r, "physically_feasible", false),
                "iterations"=>get(r, "iterations", -1),
                "nvar"=>l.nvar,
                "ncon"=>l.ncon,
                "ncc"=>length(l.r),
            ),
        )
        if get(r, "has_solution", false)
            row["residuals"]=get(r, "residuals", Dict())
            row["objective"]=get(r, "objective", NaN)
            x=_point(path)
            all(isfinite, x) && (row["coverage"]=_plain(application_coverage(data, x)))
        end
        if !haskey(cases, key)
            card=application_card(Symbol(p["provenance"]["family"]); network = data.network)
            cases[key]=Dict(
                "family"=>p["provenance"]["family"],
                "level"=>p["provenance"]["level"],
                "card"=>_plain(card),
                "provenance"=>_plain(data.provenance),
                "witness_available"=>!isnothing(witness),
            )
            if !isnothing(witness)
                cases[key]["witness_trial"]=relpath(witness.trial, directory)
                cases[key]["witness_coverage"]=_plain(
                    application_coverage(data, witness.point),
                )
            end
            baseline_parent=joinpath(directory, "counterfactuals")
            prefix="$(p["provenance"]["family"])-$(p["provenance"]["level"])-dispatchable-attempt-"
            candidates=isdir(baseline_parent) ?
                       reverse(
                sort(filter(n->startswith(n, prefix), readdir(baseline_parent))),
            ) : String[]
            baseline=nothing
            for candidate in candidates
                candidate_path=joinpath(baseline_parent, candidate)
                isfile(joinpath(candidate_path, "request.toml")) &&
                isfile(joinpath(candidate_path, "result.toml")) || continue
                if read_trial(candidate_path).result["state"]=="complete"
                    baseline=candidate_path
                    break
                end
            end
            if !isnothing(baseline)
                cases[key]["counterfactual"]=relpath(baseline, directory)
                cases[key]["counterfactual_result"]=read_trial(baseline).result
                point=verified_point(baseline; tolerance = plan["tolerance"])
                if !isnothing(point)
                    saved=read_trial(baseline).request
                    d=load_case(
                        normpath(joinpath(baseline, saved["case_file"]));
                        expected_sha = saved["case_sha256"],
                    )
                    cases[key]["counterfactual_coverage"]=_plain(
                        application_coverage(d, point),
                    )
                end
            end
        end
        push!(rows, row)
    end
    latest=Dict{String,Dict{String,Any}}()
    for row in rows
        latest[row["trial_id"]]=row
    end
    for row in rows
        row["superseded"]=latest[row["trial_id"]] !== row
    end
    _write(
        joinpath(directory, "summary.toml"),
        Dict("schema"=>SCHEMA, "trials"=>rows, "cases"=>cases),
    )
    columns=[
        "trial",
        "superseded",
        "network",
        "family",
        "level",
        "start",
        "profile",
        "seed",
        "nvar",
        "ncon",
        "ncc",
        "status",
        "classification",
        "finding",
        "witness_available",
        "physically_feasible",
        "iterations",
        "constraints",
        "bounds",
        "physical_balance",
        "complementarity",
        "volt_var",
        "volt_watt",
        "curtailed_mw",
        "curtailment_fraction",
    ]
    open(joinpath(directory, "summary.tsv"), "w") do io
        println(io, join(columns, '\t'))
        for row in rows
            flat=merge(
                copy(row),
                get(row, "residuals", Dict()),
                get(row, "coverage", Dict()),
            )
            println(io, join([_cell(get(flat, k, NaN)) for k in columns], '\t'))
        end
    end
    return rows
end
