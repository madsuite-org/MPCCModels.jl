# Included inside HardCaseSearch; all numerical solves use the existing recorder.
export run_operating_matrix
_condition_key(s) = string(s.network, "-", s.id)

function _condition_transfer(data, source, x)
    a, b=transmission_layout(data), transmission_layout(source)
    [g.id for g in data.generators]==[g.id for g in source.generators] || error("condition source generator IDs differ")
    result=zeros(a.nvar)
    for key in (:v, :theta, :pg, :qg)
        result[getproperty(a, key)].=x[getproperty(b, key)]
    end
    templates=hasproperty(data.provenance, :fleet_templates) ?
              data.provenance.fleet_templates : eachindex(data.controllers)
    for (i, c) in enumerate(data.controllers)
        j=templates[i]
        j<=length(source.controllers) || error("condition source profile mixture differs")
        ratio=c.smax/source.controllers[j].smax
        v=result[a.v[c.bus]]
        q=TransmissionOPF.BalancedACOPF.opf_volt_var(v, c)
        result[a.q[i]]=isnothing(q) ? x[b.q[j]]*ratio : q
        cap=TransmissionOPF.BalancedACOPF.opf_volt_watt(v, c)
        available=min(c.p_available, sqrt(max(c.smax^2-result[a.q[i]]^2, 0.0)))
        !isnothing(cap) && (available=min(available, cap))
        result[a.p[i]]=clamp(x[b.p[j]]*ratio, 0.0, available)
    end
    for h in eachindex(a.knots)
        delta=result[a.v[data.controllers[a.devices[h]].bus]]-a.knots[h]
        result[a.r[h]], result[a.s[h]]=max(delta, 0), max(-delta, 0)
    end
    return result
end

function _condition_anchor(spec)
    source_file=_expansion_source_file(spec.network)
    receipt=TOML.parsefile(source_file)
    row=only(
        filter(
            r->r["family"]==string(spec.family) && r["level"]==string(spec.level),
            receipt["cases"],
        ),
    )
    haskey(row, "witness") || error("no archived anchor for requested condition")
    source=application_case(spec.family; network = spec.network, level = spec.level)
    _digest(_snapshot(source))==row["input_snapshot_sha256"] ||
        error("anchor input changed")
    x=row["witness"]["x"]
    maximum(values(transmission_residuals(TransmissionOPFModel(source), source, x)))<=1e-7 ||
        error("archived condition anchor no longer verifies")
    return (; data = source, point = x, receipt_sha256 = _sha(source_file))
end

function _condition_input(directory, spec; laws = :both)
    data=operating_condition_case(spec; laws)
    key=_condition_key(spec)*"-"*string(laws)
    path=joinpath(directory, "cases", key, "input.toml")
    snapshot=_snapshot(data)
    isfile(path) ? (_sha(path)==_digest(snapshot) || error("condition input changed")) :
    _write(path, snapshot)
    return (; data, key, path)
end

function _condition_reference(
    directory,
    case,
    spec,
    anchor,
    neighbors,
    profile;
    resume,
    tolerance,
)
    file=joinpath(directory, "cases", case.key, "reference.toml")
    if isfile(file)
        row=TOML.parsefile(file)
        row["case_sha256"]==_sha(case.path) || error("reference input changed")
        if row["verified"]
            row["point_sha256"]==_digest(Dict("x"=>row["x"])) ||
                error("reference point changed")
            _metrics(TransmissionOPFModel(case.data), case.data, row["x"], tolerance)["physically_feasible"] ||
                error("saved reference no longer verifies")
        end
        return row
    end
    seed=_condition_transfer(case.data, anchor.data, anchor.point)
    model=TransmissionOPFModel(case.data)
    transfer_metrics=_metrics(model, case.data, seed, tolerance)
    _write(
        joinpath(directory, "cases", case.key, "transferred-start.toml"),
        Dict(
            "method"=>"physical_transfer_without_solver",
            "x"=>seed,
            "point_sha256"=>_digest(Dict("x"=>seed)),
            "case_sha256"=>_sha(case.path),
            "source_receipt_sha256"=>anchor.receipt_sha256,
            "metrics"=>transfer_metrics,
        ),
    )
    neighbor_key=(spec.network, spec.family, spec.policy, spec.placement, spec.count)
    starts=[("anchor", seed)]
    if haskey(neighbors, neighbor_key)
        previous=neighbors[neighbor_key]
        pushfirst!(
            starts,
            ("neighbor", _condition_transfer(case.data, previous.data, previous.point)),
        )
    end
    selected=nothing
    point=nothing
    attempts=String[]
    function attempt(x, label)
        l=transmission_layout(case.data)
        path=_ensure_trial(
            case.data,
            x,
            profile,
            joinpath(directory, "references"),
            case.key*"-"*label;
            resume,
            role = "reference",
            start_label = label,
            case_file = case.path,
            mask = Vector{Bool}(x[l.r] .> x[l.s]),
            tolerance,
            provenance = Dict(
                "spec"=>_plain(spec),
                "source_receipt_sha256"=>anchor.receipt_sha256,
            ),
        )
        push!(attempts, relpath(path, directory))
        return verified_point(path; tolerance), relpath(path, directory)
    end
    for (label, x) in starts
        point, selected=attempt(x, label)
        !isnothing(point) && break
    end
    if isnothing(point)
        screen=_ensure_trial(
            case.data,
            nothing,
            solver_profile(:current; max_iter = 100, max_wall_time = profile.max_wall_time),
            joinpath(directory, "screening"),
            case.key;
            resume,
            role = "screening",
            case_file = case.path,
        )
        push!(attempts, relpath(screen, directory))
        get(read_trial(screen).result, "has_solution", false) &&
            ((point, selected)=attempt(_point(screen), "screened_iterate"))
    end
    origin="selected_sector_solver_point"
    if isnothing(point) && transfer_metrics["physically_feasible"]
        point=seed
        selected=relpath(
            joinpath(directory, "cases", case.key, "transferred-start.toml"),
            directory,
        )
        origin="physical_transfer_without_solver"
    end
    row=Dict{String,Any}(
        "case_key"=>case.key,
        "case_sha256"=>_sha(case.path),
        "spec"=>_plain(spec),
        "verified"=>!isnothing(point),
        "attempts"=>attempts,
        "source_receipt_sha256"=>anchor.receipt_sha256,
    )
    if !isnothing(point)
        row["x"]=point
        row["point_sha256"]=_digest(Dict("x"=>point))
        row["reference_kind"]=origin
        row["reference_path"]=selected
        row["metrics"]=_metrics(model, case.data, point, tolerance)
        row["coverage"]=_plain(operating_condition_coverage(case.data, point))
    end
    _write(file, row)
    return row
end

"""Run independent operating inputs with separate references and unmodified raw trials.

The reference phase uses observed anchor/continuation/returned-iterate sectors;
no coverage target fixes voltage or selects a sector. Full raw attempts, including
unavailable starts, stay on disk. Resume requires identical inputs, source and
solver settings. `benchmark=false` prepares references without running the raw matrix.
"""
function run_operating_matrix(
    directory;
    specs = vcat(
        operating_condition_specs(),
        operating_condition_specs(; network = :ieee300),
    ),
    profiles = [:current, :ratio_one],
    max_iter = 500,
    max_wall_time = 30.0,
    reference_max_iter = 500,
    reference_max_wall_time = 15.0,
    tolerance = 1e-5,
    witness_tolerance = 1e-7,
    benchmark = true,
    resume = false,
    progress = true,
)
    !isempty(specs) &&
    allunique(_condition_key.(specs)) &&
    !isempty(profiles) &&
    allunique(profiles) &&
    0<witness_tolerance<=tolerance &&
    isfinite(tolerance) || throw(ArgumentError("invalid operating matrix plan"))
    foreach(operating_condition_case, specs)
    settings=[solver_profile(p; max_iter, max_wall_time) for p in profiles]
    reference_profile=solver_profile(
        :current;
        max_iter = reference_max_iter,
        max_wall_time = reference_max_wall_time,
    )
    environment=_environment()
    delete!(environment, "git_head")
    plan=Dict(
        "schema"=>1,
        "family"=>"operating_conditions",
        "specs"=>_plain(specs),
        "profiles"=>_plain(settings),
        "reference_profile"=>_plain(reference_profile),
        "tolerance"=>tolerance,
        "witness_tolerance"=>witness_tolerance,
        "environment"=>environment,
        "source_receipts"=>Dict(
            string(n)=>_sha(_expansion_source_file(n)) for
            n in unique(s.network for s in specs)
        ),
    )
    directory=abspath(directory)
    if ispath(directory)
        resume || throw(ArgumentError("choose a fresh operating matrix directory"))
        TOML.parsefile(joinpath(directory, "plan.toml"))==plan ||
            error("operating resume plan/source/environment mismatch")
    else
        mkpath(directory)
        _write(joinpath(directory, "plan.toml"), plan)
    end
    _capture_environment(directory, _environment())
    anchors=Dict()
    neighbors=Dict()
    summary=Dict{String,Any}[]
    for spec in specs
        case=_condition_input(directory, spec)
        key=(spec.network, spec.family, spec.level)
        haskey(anchors, key) || (anchors[key]=_condition_anchor(spec))
        baseline=_condition_input(directory, spec; laws = :dispatchable)
        basepath=_ensure_trial(
            baseline.data,
            nothing,
            reference_profile,
            joinpath(directory, "counterfactuals"),
            baseline.key;
            resume,
            role = "counterfactual",
            case_file = baseline.path,
            tolerance = witness_tolerance,
        )
        reference=_condition_reference(
            directory,
            case,
            spec,
            anchors[key],
            neighbors,
            reference_profile;
            resume,
            tolerance = witness_tolerance,
        )
        reference["verified"] && (
            neighbors[(
                spec.network,
                spec.family,
                spec.policy,
                spec.placement,
                spec.count,
            )] = (data = case.data, point = reference["x"])
        )
        row=Dict{String,Any}(
            "case_key"=>case.key,
            "spec"=>_plain(spec),
            "input_snapshot_sha256"=>_sha(case.path),
            "reference"=>reference,
            "counterfactual"=>relpath(basepath, directory),
            "trials"=>String[],
        )
        if benchmark
            for profile in settings, start_label in ("flat", "witness")
                id=case.key*"-"*string(profile.name)*"-"*start_label
                if start_label=="witness" && !reference["verified"]
                    path, done=_attempt(joinpath(directory, "trials"), id; resume)
                    done || _unavailable(
                        case.data,
                        profile,
                        case.path,
                        path;
                        label = start_label,
                        provenance = Dict("spec"=>_plain(spec)),
                        reason = "no original-feasible reference",
                    )
                else
                    start=start_label=="flat" ? nothing : reference["x"]
                    path=_ensure_trial(
                        case.data,
                        start,
                        profile,
                        joinpath(directory, "trials"),
                        id;
                        resume,
                        start_label,
                        case_file = case.path,
                        tolerance,
                        provenance = Dict(
                            "spec"=>_plain(spec),
                            "reference_available"=>reference["verified"],
                        ),
                    )
                end
                push!(row["trials"], relpath(path, directory))
            end
        end
        passed=count(
            p->read_trial(joinpath(directory, p)).result["classification"]=="success",
            row["trials"],
        )
        row["successes"]=passed
        row["difficulty"]=!reference["verified"] ? "unresolved_reference" :
                          isempty(row["trials"]) ? "not_benchmarked" :
                          passed==length(row["trials"]) ? "easy" :
                          passed==0 ? "difficult_under_budget" : "mixed"
        push!(summary, row)
        _write(joinpath(directory, "summary.toml"), Dict("schema"=>1, "cases"=>summary))
        progress && (
            println((
                case = case.key,
                reference = reference["verified"],
                successes = passed,
                difficulty = row["difficulty"],
                features = reference["verified"] ?
                           reference["coverage"]["combined_activity"] : [],
            ));
            flush(stdout)
        )
    end
    return summary
end
