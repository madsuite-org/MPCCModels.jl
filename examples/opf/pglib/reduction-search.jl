# Controlled reductions; included inside HardCaseSearch.
export reduction_case,
    reduction_witness, reduction_activity, run_reduction_search, summarize_reductions

"""Central IEEE 118 case with independent encoding, policy-count and plateau axes.

The first `controlled` original device IDs retain both laws. All three hardware
records, attachment buses, availability, costs and the network stay fixed.
`:crossing` raises only the upper VW ordinate from .8S to .9S, putting the
availability crossover 1/7 of the way along the unchanged VW ramp. Removing laws
changes the physical feasible set; sharing exact bus/knot hinges does not.
"""
function reduction_case(; encoding = :separate, controlled = 3, plateau = :equal)
    encoding in (:separate, :shared) || throw(ArgumentError("invalid encoding"))
    controlled isa Int && controlled in 1:3 || throw(ArgumentError("invalid policy count"))
    plateau in (:equal, :crossing) || throw(ArgumentError("invalid plateau"))
    base = transition_case()
    controllers = [
        i > controlled ? merge(c, (vv = nothing, vw = nothing)) :
        plateau == :equal ? c :
        merge(c, (vw = opf_curve(c.vw.knots, c.smax .* [0.9, 0.2]),)) for
        (i, c) in enumerate(base.controllers)
    ]
    return transmission_overlay(
        base;
        controllers,
        hinge_encoding = encoding,
        name = Symbol("ieee118_reduction_", encoding, "_", controlled, "_", plateau),
    )
end

const REDUCTION_RECEIPT = evidence_file("ieee118-transitions-q45.toml")

"""Transfer the archived central feasible point and independently check the target case.

This is a constructed numerical witness, not a new solver result or a selected-
sector optimum of the reduced case. Every physical variable is preserved.
"""
function reduction_witness(data; tolerance = 1e-7)
    receipt = TOML.parsefile(REDUCTION_RECEIPT)
    row = only(filter(c -> c["offset"] == 0 && c["qmax"] == 0.35, receipt["cases"]))
    source = transition_case()
    x = transmission_start(data, source, row["witness"]["x"])
    metrics = _metrics(TransmissionOPFModel(data), data, x, tolerance)
    metrics["physically_feasible"] || error("transferred point is not a verified witness")
    return (; point = x, metrics, receipt_sha256 = _sha(REDUCTION_RECEIPT))
end

function reduction_activity(data, x; tolerance = 1e-6)
    l = transmission_layout(data)
    reports = transmission_coverage(data, x; tight_tol = tolerance)
    active = findall(c -> !isnothing(c.vv), data.controllers)
    g = findfirst(g -> g.id == 45, data.generators)
    return Dict(
        "voltage"=>x[l.v[95]],
        "q45_upper_margin"=>data.generators[g].qmax-x[l.qg[g]],
        "controlled_ids"=>string.([data.controllers[i].id for i in active]),
        "simultaneous_controllers"=>count(
            i ->
                max(
                    abs(x[l.v[95]]-data.controllers[i].vv.knots[3]),
                    abs(x[l.v[95]]-data.controllers[i].vw.knots[1]),
                ) <= tolerance,
            active,
        ),
        "controllers"=>_plain(reports.controllers),
        "tolerance"=>tolerance,
    )
end

function _reduction_case_record(directory; encoding, controlled, plateau, tolerance)
    data = reduction_case(; encoding, controlled, plateau)
    key = "$(encoding)-$(controlled)-$(plateau)"
    path = joinpath(directory, "cases", key, "input.toml")
    snapshot = _snapshot(data)
    isfile(path) ?
    (_digest(TOML.parsefile(path)) == _digest(snapshot) || error("stored case differs")) :
    _write(path, snapshot)
    witness = reduction_witness(data; tolerance)
    file = joinpath(dirname(path), "witness.toml")
    record = Dict(
        "method"=>"verified_physical_transfer_without_solver",
        "x"=>witness.point,
        "point_sha256"=>_digest(Dict("x"=>witness.point)),
        "case_sha256"=>_sha(path),
        "source_receipt_sha256"=>witness.receipt_sha256,
        "tolerance"=>tolerance,
        "metrics"=>witness.metrics,
        "activity"=>reduction_activity(data, witness.point),
    )
    isfile(file) ? (TOML.parsefile(file) == record || error("stored witness differs")) :
    _write(file, record)
    return (; data, key, path, witness = witness.point)
end

function _read_reduction_witness(directory, key, data, input)
    record = TOML.parsefile(joinpath(directory, "cases", key, "witness.toml"))
    _sha(input) == record["case_sha256"] || error("witness belongs to another case")
    _digest(Dict("x"=>record["x"])) == record["point_sha256"] ||
        error("witness point checksum mismatch")
    metrics = _metrics(TransmissionOPFModel(data), data, record["x"], record["tolerance"])
    return metrics["physically_feasible"] ? record : nothing
end

"""Run 12 matched variants with flat/witness starts and an explicit larger-budget reference.

Optional perturbation seeds add paired physical starts to every variant. Raw
homotopies are traced and never refined; witnesses are verified transfers of one
archived physical point. Safe resume requires identical source/environment/plan.
"""
function run_reduction_search(
    directory;
    encodings = [:separate, :shared],
    counts = [1, 2, 3],
    plateaus = [:equal, :crossing],
    seeds = Int[],
    starts = [:flat, :witness, :perturbed_witness],
    reference = true,
    max_iter = 500,
    max_wall_time = 60.0,
    reference_iter = 2000,
    reference_wall_time = 180.0,
    trace_every = 10,
    tolerance = 1e-5,
    witness_tolerance = 1e-7,
    resume = false,
    progress = true,
)
    all(a -> !isempty(a) && allunique(a), (encodings, counts, plateaus, starts)) &&
    all(s -> s in (:flat, :witness, :perturbed_witness), starts) &&
    any(s -> s != :perturbed_witness || !isempty(seeds), starts) &&
    allunique(seeds) &&
    all(s -> s isa Int && s >= 0, seeds) &&
    trace_every > 0 &&
    isfinite(tolerance) &&
    0 < witness_tolerance <= tolerance || throw(ArgumentError("invalid search plan"))
    for encoding in encodings, controlled in counts, plateau in plateaus
        reduction_case(; encoding, controlled, plateau)
    end
    profile = solver_profile(:ratio_one; max_iter, max_wall_time)
    reference_profile = solver_profile(
        :ratio_one;
        max_iter = reference_iter,
        max_wall_time = reference_wall_time,
    )
    environment = _environment()
    delete!(environment, "git_head")
    plan = Dict(
        "schema"=>SCHEMA,
        "family"=>"ieee118_reductions",
        "encodings"=>string.(encodings),
        "counts"=>counts,
        "plateaus"=>string.(plateaus),
        "seeds"=>seeds,
        "starts"=>string.(starts),
        "reference"=>reference,
        "profile"=>_plain(profile),
        "reference_profile"=>_plain(reference_profile),
        "trace_every"=>trace_every,
        "tolerance"=>tolerance,
        "witness_tolerance"=>witness_tolerance,
        "witness_source_sha256"=>_sha(REDUCTION_RECEIPT),
        "environment"=>environment,
    )
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
    cp(REDUCTION_RECEIPT, joinpath(directory, "source-witness.toml"); force = true)
    reference_case = _reduction_case_record(
        directory;
        encoding = :separate,
        controlled = 3,
        plateau = :equal,
        tolerance = witness_tolerance,
    )
    # Traced warmup pays callback compilation outside the matrix resource budgets.
    _ensure_trial(
        reference_case.data,
        reference_case.witness,
        solver_profile(:ratio_one; max_iter = 1, max_wall_time = 60.0),
        joinpath(directory, "warmup"),
        "traced";
        resume = true,
        role = "warmup",
        start_label = "witness",
        case_file = reference_case.path,
        tolerance,
        trace_every = 1,
    )
    base = reduction_case()
    common = reduction_witness(base; tolerance = witness_tolerance).point
    completed = 0
    for encoding in encodings, controlled in counts, plateau in plateaus
        case = _reduction_case_record(
            directory;
            encoding,
            controlled,
            plateau,
            tolerance = witness_tolerance,
        )
        scheduled = [
            (label, seed) for label in starts for
            seed in (label == :perturbed_witness ? seeds : [-1])
        ]
        for (label, seed) in scheduled
            x =
                label == :flat ? nothing :
                label == :witness ? case.witness :
                transmission_start(case.data, base, _perturb(base, common, seed))
            provenance = Dict(
                "case_key"=>case.key,
                "encoding"=>string(encoding),
                "controlled"=>controlled,
                "plateau"=>string(plateau),
                "seed"=>seed,
                "witness_file"=>"cases/$(case.key)/witness.toml",
            )
            id = "$(case.key)-$(label)-$(seed)"
            path = _ensure_trial(
                case.data,
                x,
                profile,
                joinpath(directory, "trials"),
                id;
                resume = true,
                start_label = label,
                case_file = case.path,
                tolerance,
                provenance,
                trace_every,
            )
            completed += 1
            progress && println((
                completed = completed,
                total = length(encodings)*length(counts)*length(plateaus)*length(scheduled),
                case = case.key,
                start = label,
                seed,
                result = read_trial(path).result["classification"],
            ))
            flush(stdout)
        end
        summarize_reductions(directory)
    end
    reference && _ensure_trial(
        reference_case.data,
        nothing,
        reference_profile,
        joinpath(directory, "references"),
        "separate-3-equal-flat";
        resume = true,
        role = "budget_reference",
        start_label = "flat",
        case_file = reference_case.path,
        tolerance,
        trace_every,
    )
    return summarize_reductions(directory)
end

function summarize_reductions(directory)
    rows = Dict{String,Any}[]
    parent = joinpath(directory, "trials")
    isdir(parent) || return rows
    for name in sort(readdir(parent))
        path = joinpath(parent, name)
        isfile(joinpath(path, "request.toml")) || continue
        saved = read_trial(path)
        p, r = saved.request, saved.result
        input = normpath(joinpath(path, p["case_file"]))
        data = load_case(input; expected_sha = p["case_sha256"])
        witness =
            _read_reduction_witness(directory, p["provenance"]["case_key"], data, input)
        category = r["state"] == "complete" ? r["classification"] : "unfinished"
        l = transmission_layout(data)
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
                "nvar"=>l.nvar,
                "ncon"=>l.ncon,
                "ncc"=>length(l.r),
                "iterations"=>get(r, "iterations", -1),
                "physically_feasible"=>get(r, "physically_feasible", false),
                "outer_seconds"=>get(r, "outer_seconds", NaN),
                "trace_errors"=>get(r, "trace_errors", []),
            ),
        )
        if get(r, "has_solution", false)
            row["residuals"] = get(r, "residuals", Dict())
            row["objective"] = get(r, "objective", NaN)
            row["activity"] = reduction_activity(data, _point(path))
        end
        !isnothing(witness) && (row["witness_activity"] = witness["activity"])
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
        "encoding",
        "controlled",
        "plateau",
        "start",
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
        "outer_seconds",
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
            flat = merge(copy(row), get(row, "residuals", Dict()))
            println(io, join([_cell(get(flat, k, NaN)) for k in columns], '\t'))
        end
    end
    return rows
end
