# One case-driven recorder for policy and fleet expansions; included in HardCaseSearch.
export run_expansion_search, summarize_expansions

const EXPANSION_SOURCE=evidence_file("ieee118-applications.toml")
function _expansion_key(s)
    key=s.kind==:coverage ? "policy-$(s.policy)" :
        s.kind==:reserve ? "reserve-$(s.reserve)" :
        "fleet-$(s.family)-$(s.level)-$(s.count)-$(s.placement)"
    network=get(s, :network, :ieee118)
    return network==:ieee118 ? key : "$(network)-$(key)"
end
function _expansion_source_file(network)
    network in (:ieee118, :ieee300) || throw(ArgumentError("unsupported source network"))
    return network==:ieee118 ? EXPANSION_SOURCE : evidence_file("ieee300-applications.toml")
end
function _expansion_coverage(data, x)
    return data.network==:ieee300 ? application_policy_coverage(data, x) :
           application_coverage(data, x)
end

function _expansion_source(data, spec)
    family=Symbol(data.provenance.application_family)
    level=Symbol(data.provenance.operating_level)
    source_file=_expansion_source_file(data.network)
    receipt=TOML.parsefile(source_file)
    row=only(
        filter(
            r->r["family"]==string(family) && r["level"]==string(level),
            receipt["cases"],
        ),
    )
    base=application_case(family; network = data.network, level)
    _digest(_snapshot(base))==row["input_snapshot_sha256"] ||
        error("source input identity changed")
    x=row["witness"]["x"]
    maximum(values(transmission_residuals(TransmissionOPFModel(base), base, x)))<=1e-7 ||
        error("source witness no longer verifies")
    transferred=spec.kind==:fleet ? application_fleet_start(data, base, x) :
                transmission_start(data, base, x)
    return (; point = transferred, source_sha256 = _sha(source_file), family, level)
end

function _save_expansion(directory, spec; laws = :both, hinge_encoding = :separate)
    data=application_expansion_case(spec; laws, hinge_encoding)
    key=_expansion_key(spec)*"-"*string(laws)
    path=joinpath(directory, "cases", key, "input.toml")
    snapshot=_snapshot(data)
    isfile(path) ?
    (
        _digest(TOML.parsefile(path))==_digest(snapshot) ||
        error("stored expansion differs")
    ) : _write(path, snapshot)
    return (; data, key, path)
end

function _source_point_record(directory, case, source; tolerance)
    path=joinpath(directory, "cases", case.key, "source-point.toml")
    record=Dict(
        "method"=>"physical_transfer_without_solver",
        "x"=>source.point,
        "point_sha256"=>_digest(Dict("x"=>source.point)),
        "case_sha256"=>_sha(case.path),
        "source_receipt_sha256"=>source.source_sha256,
        "source_family"=>string(source.family),
        "source_level"=>string(source.level),
        "tolerance"=>tolerance,
        "metrics"=>_metrics(
            TransmissionOPFModel(case.data),
            case.data,
            source.point,
            tolerance,
        ),
    )
    isfile(path) ? (TOML.parsefile(path)==record || error("stored source point differs")) :
    _write(path, record)
    return path
end

function _prepared_point(directory, case, receipt; tolerance)
    rows=TOML.parsefile(receipt)["cases"]
    matches=filter(r->r["case_key"]==case.key, rows)
    length(matches)==1 || error("prepared reference missing or duplicated")
    row=only(matches)
    row["case_sha256"]==_sha(case.path) || error("prepared reference input mismatch")
    row["point_sha256"]==_digest(Dict("x"=>row["x"])) ||
        error("prepared reference point mismatch")
    metrics=_metrics(TransmissionOPFModel(case.data), case.data, row["x"], tolerance)
    metrics["physically_feasible"] || error("prepared reference is not original-feasible")
    record=merge(
        copy(row),
        Dict(
            "method"=>"prevalidated_reference",
            "origin_reference_kind"=>get(
                row,
                "origin_reference_kind",
                get(row, "reference_origin", get(row, "reference_kind", "unknown")),
            ),
            "source_receipt_sha256"=>_sha(receipt),
            "metrics"=>metrics,
            "tolerance"=>tolerance,
        ),
    )
    path=joinpath(directory, "cases", case.key, "prepared-point.toml")
    isfile(path) ? (TOML.parsefile(path)==record || error("prepared point changed")) :
    _write(path, record)
    return path
end

function _expansion_witness(directory, case; tolerance)
    witness=_witness_reference(directory, case; tolerance)
    !isnothing(witness) && return (
        point = witness.point,
        path = witness.trial,
        kind = "solver_point",
        origin = "solver_point",
    )
    for (name, kind) in (
        ("prepared-point.toml", "prevalidated_reference"),
        ("source-point.toml", "physical_transfer"),
    )
        file=joinpath(directory, "cases", case.key, name)
        isfile(file) || continue
        record=TOML.parsefile(file)
        record["case_sha256"]==_sha(case.path) ||
            error("reference point belongs to another input")
        record["point_sha256"]==_digest(Dict("x"=>record["x"])) ||
            error("reference point checksum mismatch")
        metrics=_metrics(TransmissionOPFModel(case.data), case.data, record["x"], tolerance)
        metrics["physically_feasible"] && return (
            point = Float64.(record["x"]),
            path = file,
            kind = kind,
            origin = get(record, "origin_reference_kind", get(record, "method", "unknown")),
        )
    end
    return nothing
end

"""Record application coverage/population studies with raw results and explicit references.

Without a prepared receipt, operating reference attempts use the transferred
voltage of an archived application point, followed by actual returned-iterate
sectors. Neither uses intended coverage labels. Prepared points are hash-checked
and re-evaluated against original inputs before any raw solve; their provenance
and numerical evidence are retained. All verified references are reported. Raw homotopies and dispatchable counterfactuals are never
polished or replaced. No unsuccessful reference is an infeasibility certificate.
"""
function run_expansion_search(
    directory;
    specs = application_expansion_specs(:coverage),
    profiles = [:current, :ratio_one],
    reference_receipt = nothing,
    hinge_encoding = :separate,
    max_iter = 500,
    max_wall_time = 60.0,
    tolerance = 1e-5,
    witness_tolerance = 1e-7,
    trace_every = 0,
    resume = false,
    progress = true,
)
    !isempty(specs) &&
    allunique(_expansion_key.(specs)) &&
    !isempty(profiles) &&
    allunique(profiles) &&
    isfinite(tolerance) &&
    0<witness_tolerance<=tolerance &&
    trace_every>=0 || throw(ArgumentError("invalid expansion plan"))
    for spec in specs
        application_expansion_case(spec; hinge_encoding)
    end
    networks=unique(application_expansion_case(s).network for s in specs)
    length(networks)==1 || throw(ArgumentError("one network per expansion run"))
    source_file=_expansion_source_file(only(networks))
    settings=[solver_profile(p; max_iter, max_wall_time) for p in profiles]
    reference_profile=solver_profile(:current; max_iter, max_wall_time)
    environment=_environment()
    delete!(environment, "git_head")
    plan=Dict(
        "schema"=>SCHEMA,
        "family"=>"application_expansion",
        "specs"=>_plain(specs),
        "profiles"=>_plain(settings),
        "hinge_encoding"=>string(hinge_encoding),
        "trace_every"=>trace_every,
        "tolerance"=>tolerance,
        "witness_tolerance"=>witness_tolerance,
        "source_witness_sha256"=>_sha(source_file),
        "environment"=>environment,
    )
    !isnothing(reference_receipt) &&
        (plan["prepared_reference_sha256"]=_sha(reference_receipt))
    directory=abspath(directory)
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
    cp(source_file, joinpath(directory, "source-reference.toml"); force = true)
    if !isnothing(reference_receipt)
        saved=joinpath(directory, "prepared-references.toml")
        isfile(saved) ?
        (_sha(saved)==_sha(reference_receipt) || error("prepared receipt changed")) :
        cp(reference_receipt, saved)
        for spec in specs
            case=_save_expansion(directory, spec; hinge_encoding)
            _prepared_point(directory, case, saved; tolerance = witness_tolerance)
        end
    end
    warm=_save_expansion(directory, first(specs); hinge_encoding)
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
    completed=0
    for spec in specs
        case=_save_expansion(directory, spec; hinge_encoding)
        baseline=_save_expansion(directory, spec; laws = :dispatchable, hinge_encoding)
        _ensure_trial(
            baseline.data,
            nothing,
            reference_profile,
            joinpath(directory, "counterfactuals"),
            baseline.key;
            resume = true,
            role = "counterfactual",
            start_label = "flat",
            case_file = baseline.path,
            tolerance,
            trace_every,
        )
        provenance=Dict("case_key"=>case.key, "spec"=>_plain(spec))
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
            completed+=1
            progress && println((
                completed,
                total = 2*length(specs)*length(settings),
                case = case.key,
                start = :flat,
                profile = c.name,
                result = read_trial(path).result["classification"],
            ))
            flush(stdout)
        end
        refs=String[]
        source=_expansion_source(case.data, spec)
        _source_point_record(directory, case, source; tolerance = witness_tolerance)
        l=transmission_layout(case.data)
        mask=Vector{Bool}(source.point[l.r] .> source.point[l.s])
        if isnothing(reference_receipt)
            operating=_ensure_trial(
                case.data,
                source.point,
                reference_profile,
                joinpath(directory, "references"),
                "$(case.key)-operating";
                resume = true,
                role = "operating_reference",
                start_label = "archived_application",
                case_file = case.path,
                tolerance = witness_tolerance,
                mask,
                provenance = Dict(
                    "source_receipt_sha256"=>source.source_sha256,
                    "source_family"=>string(source.family),
                    "source_level"=>string(source.level),
                ),
            )
            push!(refs, operating)
            for (i, path) in enumerate(flats)
                saved=read_trial(path)
                get(saved.result, "has_solution", false) || continue
                x=_point(path)
                all(isfinite, x) || continue
                mask=Vector{Bool}(x[l.r] .> x[l.s])
                returned=_ensure_trial(
                    case.data,
                    x,
                    reference_profile,
                    joinpath(directory, "references"),
                    "$(case.key)-returned-$(settings[i].name)";
                    resume = true,
                    role = "returned_reference",
                    start_label = "raw_iterate",
                    case_file = case.path,
                    tolerance = witness_tolerance,
                    mask,
                    provenance = Dict("selected_from"=>relpath(path, directory)),
                )
                push!(refs, returned)
                !isnothing(verified_point(returned; tolerance = witness_tolerance)) && break
            end
        end
        witness=_expansion_witness(directory, case; tolerance = witness_tolerance)
        if isnothing(witness)
            # Prefer the predeclared operating continuation, then observed raw sectors.
            for path in [refs; flats]
                point=_register_witness(
                    directory,
                    case,
                    path;
                    tolerance = witness_tolerance,
                )
                if !isnothing(point)
                    witness=(point = point, path = path, kind = "solver_point")
                    break
                end
            end
        end
        _write(
            joinpath(directory, "cases", case.key, "references.toml"),
            Dict("trials"=>relpath.(refs, Ref(directory))),
        )
        for c in settings
            id="$(case.key)-witness-$(c.name)"
            path, done=_attempt(joinpath(directory, "trials"), id; resume = true)
            if !done
                if isnothing(witness)
                    _unavailable(
                        case.data,
                        c,
                        case.path,
                        path;
                        label = :witness,
                        provenance,
                        reason = "no verified reference; feasibility unresolved",
                    )
                else
                    run_trial(
                        case.data,
                        witness.point,
                        c,
                        path;
                        start_label = "witness",
                        case_file = case.path,
                        tolerance,
                        trace_every,
                        provenance = merge(
                            copy(provenance),
                            Dict(
                                "witness_reference"=>relpath(witness.path, directory),
                                "reference_kind"=>witness.kind,
                                "reference_origin"=>witness.origin,
                            ),
                        ),
                    )
                end
            end
            completed+=1
            progress && println((
                completed,
                total = 2*length(specs)*length(settings),
                case = case.key,
                start = :witness,
                profile = c.name,
                result = read_trial(path).result["classification"],
            ))
            flush(stdout)
        end
        summarize_expansions(directory)
    end
    return summarize_expansions(directory)
end

function summarize_expansions(directory)
    parent=joinpath(directory, "trials")
    isdir(parent) || return Dict[]
    plan=TOML.parsefile(joinpath(directory, "plan.toml"))
    rows=Dict{String,Any}[]
    cases=Dict{String,Any}()
    for name in sort(readdir(parent))
        path=joinpath(parent, name)
        isfile(joinpath(path, "request.toml")) || continue
        p, r=read_trial(path)
        input=normpath(joinpath(path, p["case_file"]))
        data=load_case(input; expected_sha = p["case_sha256"])
        key=p["provenance"]["case_key"]
        case=(; data, key, path = input)
        witness=_expansion_witness(directory, case; tolerance = plan["witness_tolerance"])
        category=r["state"]=="complete" ? r["classification"] : "unfinished"
        l=transmission_layout(data)
        row=Dict{String,Any}(
            "trial"=>relpath(path, directory),
            "trial_id"=>first(split(name, "-attempt-")),
            "case_key"=>key,
            "spec"=>p["provenance"]["spec"],
            "start"=>p["start_label"],
            "profile"=>p["profile"]["name"],
            "nvar"=>l.nvar,
            "ncon"=>l.ncon,
            "ncc"=>length(l.r),
            "status"=>get(r, "status", "unfinished"),
            "classification"=>category,
            "witness_available"=>!isnothing(witness),
            "physically_feasible"=>get(r, "physically_feasible", false),
            "finding"=>category=="solver_failure" ?
                       (
                isnothing(witness) ? "unresolved_feasibility" : "known_feasible_failure"
            ) : category=="physical_violation" ? "accuracy_gap" : category,
            "iterations"=>get(r, "iterations", -1),
        )
        if get(r, "has_solution", false)
            row["residuals"]=get(r, "residuals", Dict())
            row["objective"]=get(r, "objective", NaN)
            x=_point(path)
            all(isfinite, x) && (row["coverage"]=_plain(_expansion_coverage(data, x)))
        end
        if !haskey(cases, key)
            info=Dict{String,Any}(
                "spec"=>row["spec"],
                "provenance"=>_plain(data.provenance),
                "witness_available"=>!isnothing(witness),
                "references"=>Dict[],
            )
            prepared=joinpath(directory, "cases", key, "prepared-point.toml")
            isfile(prepared) && (info["prepared_reference"]=TOML.parsefile(prepared))
            refsfile=joinpath(directory, "cases", key, "references.toml")
            if isfile(refsfile)
                for ref in TOML.parsefile(refsfile)["trials"]
                    point=verified_point(
                        joinpath(directory, ref);
                        tolerance = plan["witness_tolerance"],
                    )
                    item=Dict{String,Any}(
                        "trial"=>ref,
                        "verified"=>!isnothing(point),
                        "role"=>read_trial(joinpath(directory, ref)).request["role"],
                    )
                    !isnothing(point) &&
                        (item["coverage"]=_plain(_expansion_coverage(data, point)))
                    push!(info["references"], item)
                end
            end
            if !isnothing(witness)
                info["witness_reference"]=relpath(witness.path, directory)
                info["reference_kind"]=witness.kind
                info["reference_origin"]=witness.origin
                info["witness_coverage"]=_plain(_expansion_coverage(data, witness.point))
            end
            cases[key]=info
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
        "case_key",
        "kind",
        "start",
        "profile",
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
    ]
    open(joinpath(directory, "summary.tsv"), "w") do io
        println(io, join(columns, '\t'))
        for row in rows
            flat=merge(
                copy(row),
                get(row, "residuals", Dict()),
                get(row, "coverage", Dict()),
                Dict("kind"=>row["spec"]["kind"]),
            )
            println(io, join([_cell(get(flat, k, NaN)) for k in columns], '\t'))
        end
    end
    return rows
end
