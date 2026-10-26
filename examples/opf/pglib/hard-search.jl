module HardCaseSearch

using CCOpt, MPCCModels, NLPModels, TOML, SHA, Dates, Random
include("benchmark-evidence.jl")
using .BenchmarkEvidence: evidence_file
include("transmission-opf.jl")
using .TransmissionOPF

export capability_case, solver_profile, run_trial, run_search, read_trial, replay_trial
export summarize_search, load_case, verified_point

const SCHEMA = 1
const HERE = @__DIR__
const ROOT = normpath(joinpath(HERE, "..", "..", ".."))
const STARTS = (:flat, :neighbor, :perturbed_neighbor, :witness)
const PROFILES = (:defaults, :current, :looser_inner, :ratio_one, :higher_floor)

_utc() = string(Dates.now(Dates.UTC))*"Z"
_sha(path) = bytes2hex(sha256(read(path)))
function _success(status)
    return status in (CCOpt.MadNLP.SOLVE_SUCCEEDED, CCOpt.MadNLP.SOLVED_TO_ACCEPTABLE_LEVEL)
end

function _plain(x)
    x isa NamedTuple && return Dict(string(k)=>_plain(v) for (k, v) in pairs(x))
    x isa AbstractDict && return Dict(string(k)=>_plain(v) for (k, v) in x)
    (x isa Tuple || x isa AbstractArray) && return [_plain(v) for v in x]
    (x isa Symbol || x isa VersionNumber || x isa Type || x isa Enum) && return string(x)
    (isnothing(x) || ismissing(x)) && return "unavailable"
    x isa Union{AbstractString,Real,Bool} && return x
    return string(x)
end

function _options(x, depth = 0)
    (
        x isa Type ||
        x isa Function ||
        x isa Enum ||
        x isa AbstractArray ||
        x isa AbstractDict ||
        x isa Number ||
        x isa AbstractString ||
        x isa Symbol ||
        isnothing(x)
    ) && return _plain(x)
    depth >= 3 && return string(x)
    result = Dict{String,Any}("_type"=>string(typeof(x)))
    for key in fieldnames(typeof(x))
        result[string(key)] = _options(getfield(x, key), depth+1)
    end
    return result
end

function _toml(x)
    return sprint(io -> TOML.print(io, _plain(x); sorted = true))
end
_digest(x) = bytes2hex(sha256(_toml(x)))

function _write(path, x)
    mkpath(dirname(path))
    temporary, io = mktemp(dirname(path))
    try
        TOML.print(io, _plain(x); sorted = true)
        close(io)
        mv(temporary, path; force = true)
    finally
        isopen(io) && close(io)
        isfile(temporary) && rm(temporary)
    end
    return path
end

"""IEEE 118 with only ibr3's S rating changed; availability and laws stay fixed."""
function capability_case(factor::Real)
    isfinite(factor) && factor > 0 ||
        throw(ArgumentError("capability factor must be positive and finite"))
    data = pglib_control_case(:ieee118; targets = [], network_targets = [])
    controllers = copy(data.controllers)
    controllers[3] = merge(controllers[3], (smax = Float64(factor)*controllers[3].smax,))
    return transmission_overlay(
        data;
        controllers,
        name = Symbol("ieee118_capability_", factor),
    )
end

"""Explicit profiles. Four vary one parameter from `current`; defaults is a baseline.

`current`: sigma floor 1e-14, sigma/mu ratio .01, NLP tol 1e-9, bound push/factor
1e-6. Variants change only NLP tol (looser_inner), ratio (ratio_one), or floor
(higher_floor). `defaults` pins the observed CCOpt 0.1/MadNLP defaults, with
bound relaxation disabled and explicit iteration/wall budgets in every profile.
"""
function solver_profile(name::Symbol; max_iter::Int = 500, max_wall_time::Real = 60.0)
    name in PROFILES || throw(ArgumentError("unknown solver profile"))
    max_iter > 0 && isfinite(max_wall_time) && max_wall_time > 0 ||
        throw(ArgumentError("invalid solver budget"))
    return (
        name = name,
        sigma_min = name in (:defaults, :higher_floor) ? 1e-8 : 1e-14,
        sigma_mu_ratio = name in (:defaults, :ratio_one) ? 1.0 : 0.01,
        tol = name in (:defaults, :looser_inner) ? 1e-8 : 1e-9,
        bound_push = name == :defaults ? 1e-2 : 1e-6,
        bound_fac = name == :defaults ? 1e-2 : 1e-6,
        bound_relax_factor = 0.0,
        max_iter = max_iter,
        max_wall_time = Float64(max_wall_time),
    )
end

function _ipm_kwargs(c)
    return (
        tol = c["tol"],
        bound_push = c["bound_push"],
        bound_fac = c["bound_fac"],
        bound_relax_factor = c["bound_relax_factor"],
        max_iter = c["max_iter"],
        max_wall_time = c["max_wall_time"],
        print_level = CCOpt.MadNLP.ERROR,
        file_print_level = CCOpt.MadNLP.ERROR,
        rethrow_error = true,
    )
end

# Exceptions are retained, with the current IPM point when it can be unpacked.
# No target, witness or post-solve polishing changes the raw homotopy result.
function _execute(model, c; mask = nothing, trace = nothing)
    result = Dict{String,Any}("solver_success"=>false, "status"=>"not_started")
    ipm, solver, stats = nothing, nothing, nothing
    initial = time_ns()
    try
        if !(model isa AbstractMPCCModel)
            isnothing(mask) ||
                throw(ArgumentError("ordinary NLP has no complementarity sector"))
            observer = isnothing(trace) ? (;) : (intermediate_callback = trace,)
            ipm = CCOpt.MadNLP.MadNLPSolver(model; _ipm_kwargs(c)..., observer...)
        elseif isnothing(mask)
            options = CCOpt.RelaxationOptions(
                sigma_min = c["sigma_min"],
                relaxation_update = CCOpt.ProportionalRelaxationUpdate{Float64}(
                    sigma_min = c["sigma_min"],
                    sigma_mu_ratio = c["sigma_mu_ratio"],
                ),
                print_level = CCOpt.MadNLP.ERROR,
                file_print_level = CCOpt.MadNLP.ERROR,
            )
            observer = isnothing(trace) ? (;) : (intermediate_callback = trace,)
            solver = CCOpt.RelaxationSolver(
                model;
                solver_opts = options,
                _ipm_kwargs(c)...,
                observer...,
            )
            ipm = solver.ipm
            result["resolved_relaxation"] = _options(solver.opts)
        else
            branch = CCOpt.BranchNLP(model, Vector{Bool}(mask))
            observer = isnothing(trace) ? (;) : (intermediate_callback = trace,)
            ipm = CCOpt.MadNLP.MadNLPSolver(branch; _ipm_kwargs(c)..., observer...)
        end
        result["resolved_ipm"] = _options(ipm.opt)
        result["initialization_seconds"] = (time_ns()-initial)/1e9
        start = time_ns()
        try
            stats =
                isnothing(solver) ? CCOpt.MadNLP.solve!(ipm) : CCOpt.solve_homotopy!(solver)
        finally
            result["solve_call_seconds"] = (time_ns()-start)/1e9
        end
        !isnothing(trace) &&
            _sample_trace!(trace, ipm, CCOpt.MadNLP.UserCallbackRegular(); force = true)
        result["status"] = string(stats.status)
        result["solver_success"] = _success(stats.status)
        result["solution"] = copy(stats.solution)
        result["point_source"] = "returned_solution"
        result["iterations"] = stats.iter
        result["solver_counters"] = _options(stats.counters)
        for key in (:primal_feas, :dual_feas, :inf_pr_cc)
            hasproperty(stats, key) && (result[string(key)] = getproperty(stats, key))
        end
    catch err
        err isa InterruptException && rethrow()
        result["exception"] = sprint(showerror, err, catch_backtrace())
        result["exception_type"] = string(typeof(err))
        result["status"] = isnothing(ipm) ? "construction_exception" : string(ipm.status)
        if !isnothing(ipm) && ipm.status != CCOpt.MadNLP.INITIAL
            try
                x = zeros(get_nvar(model))
                CCOpt.MadNLP.unpack_x!(x, ipm.cb, CCOpt.MadNLP.variable(ipm.x))
                result["solution"] = x
                result["point_source"] = "exception_iterate"
                result["iterations"] = ipm.cnt.k
            catch capture_error
                result["capture_error"] = sprint(showerror, capture_error)
            end
        end
    end
    return result
end

function _snapshot(data)
    snapshot = Dict(
        "schema"=>SCHEMA,
        "network"=>string(data.network),
        "name"=>string(data.name),
        "pm"=>data.pm,
        "controllers"=>_plain(data.controllers),
        "provenance"=>_plain(data.provenance),
    )
    # Preserve byte-compatible historical separate-encoding input snapshots.
    data.hinge_encoding != :separate &&
        (snapshot["hinge_encoding"] = string(data.hinge_encoding))
    return snapshot
end

"""Read a self-contained network/controller snapshot, validating its recorded hash."""
function load_case(path; expected_sha = nothing)
    !isnothing(expected_sha) &&
        _sha(path) != expected_sha &&
        error("case snapshot checksum mismatch")
    d = TOML.parsefile(path)
    d["schema"] == SCHEMA || error("unsupported case schema")
    restore(c) = opf_controller(
        Symbol(c["id"]),
        c["bus"];
        vv = c["vv"] == "unavailable" ? nothing :
             opf_curve(c["vv"]["knots"], c["vv"]["values"]),
        vw = c["vw"] == "unavailable" ? nothing :
             opf_curve(c["vw"]["knots"], c["vw"]["values"]),
        p_available = c["p_available"],
        smax = c["smax"],
        qmin = c["qmin"],
        qmax = c["qmax"],
        cost = c["cost"],
        quadratic_cost = c["quadratic_cost"],
    )
    return TransmissionOPF._transmission_data(
        d["pm"];
        network = Symbol(d["network"]),
        hinge_encoding = Symbol(get(d, "hinge_encoding", "separate")),
        name = Symbol(d["name"]),
        controllers = restore.(d["controllers"]),
        targets = [],
        network_targets = [],
        provenance = (; (Symbol(k)=>v for (k, v) in d["provenance"])...),
    )
end

function _metrics(model, data, x, tolerance)
    residuals = transmission_residuals(model, data, x)
    l = transmission_layout(data)
    finite = all(isfinite, x)
    curves = Dict{String,Any}[]
    if finite
        coverage = transmission_coverage(data, x)
        for (i, c) in enumerate(data.controllers)
            v = x[l.v[c.bus]]
            vv = TransmissionOPF.BalancedACOPF.opf_volt_var(v, c)
            vw = TransmissionOPF.BalancedACOPF.opf_volt_watt(v, c)
            push!(
                curves,
                merge(
                    _plain(coverage.controllers[i]),
                    Dict(
                        "vv_error_relative_smax"=>isnothing(vv) ? 0.0 :
                                                  abs(x[l.q[i]]-vv)/c.smax,
                        "vw_violation_relative_smax"=>isnothing(vw) ? 0.0 :
                                                      max(x[l.p[i]]-vw, 0.0)/c.smax,
                    ),
                ),
            )
        end
    end
    return Dict(
        "residuals"=>_plain(residuals),
        "finite"=>finite,
        "physically_feasible"=>finite && maximum(values(residuals)) <= tolerance,
        "complementarity_product"=>finite ? maximum(abs.(x[l.r] .* x[l.s]); init = 0.0) :
                                   Inf,
        "hinge_bound_violation"=>finite ? maximum(max.(-x[l.r], -x[l.s], 0.0); init = 0.0) :
                                 Inf,
        "objective"=>finite ? obj(model, x) : NaN,
        "controllers"=>curves,
    )
end

function _category(record)
    haskey(record, "exception") && return "exception"
    haskey(record, "diagnostic_error") && return "diagnostic_error"
    !get(record, "has_solution", false) && return "no_solution"
    !get(record, "solver_success", false) && return "solver_failure"
    !get(record, "physically_feasible", false) && return "physical_violation"
    return "success"
end

"""Save one unpolished solve, including failed statuses, exceptions and raw points.

The request and exact start are saved before solver construction. Existing runs
are never overwritten. `mask` requests a separately labelled exact-sector solve
for witness construction. An interrupted attempt retains its running marker.
"""
function run_trial(
    data,
    x0,
    profile,
    directory;
    role = "raw",
    start_label = "custom",
    tolerance = 1e-5,
    case_file = nothing,
    mask = nothing,
    provenance = Dict(),
    executor = _execute,
    trace_every::Int = 0,
)
    isfinite(tolerance) && tolerance > 0 ||
        throw(ArgumentError("invalid feasibility tolerance"))
    trace_every >= 0 || throw(ArgumentError("invalid trace interval"))
    ispath(directory) && throw(ArgumentError("trial directory already exists"))
    mkpath(directory)
    case_file =
        isnothing(case_file) ? _write(joinpath(directory, "input.toml"), _snapshot(data)) :
        abspath(case_file)
    # Verify the in-memory problem matches the referenced snapshot.
    _digest(_snapshot(data)) == _digest(TOML.parsefile(case_file)) ||
        error("case snapshot does not match data")
    l = transmission_layout(data)
    start = isnothing(x0) ? copy(get_x0(TransmissionOPFModel(data))) : Float64.(x0)
    length(start) == l.nvar && all(isfinite, start) || throw(ArgumentError("invalid start"))
    start_file = _write(joinpath(directory, "start.toml"), Dict("x"=>start))
    request = Dict(
        "schema"=>SCHEMA,
        "role"=>role,
        "start_label"=>string(start_label),
        "profile"=>_plain(profile),
        "tolerance"=>tolerance,
        "provenance"=>_plain(provenance),
        "case_file"=>relpath(case_file, directory),
        "case_sha256"=>_sha(case_file),
        "start_sha256"=>_sha(start_file),
        "nvar"=>l.nvar,
        "ncon"=>l.ncon,
        "ncc"=>length(l.r),
        "environment"=>_environment(),
    )
    !isnothing(mask) && (request["sector_mask"] = collect(mask))
    trace_every > 0 && (request["trace_every"] = trace_every)
    _write(joinpath(directory, "request.toml"), request)
    result = Dict{String,Any}(
        "schema"=>SCHEMA,
        "state"=>"running",
        "started_utc"=>_utc(),
        "has_solution"=>false,
        "solver_success"=>false,
        "physically_feasible"=>false,
    )
    _write(joinpath(directory, "result.toml"), result)
    model = nothing
    outer = time_ns()
    try
        open(joinpath(directory, "solver.log"), "w") do log
            redirect_stdout(log) do
                redirect_stderr(log) do
                    model = TransmissionOPFModel(data; x0 = start)
                    result["model_build_seconds"] = (time_ns()-outer)/1e9
                    result["initial"] = _metrics(model, data, start, tolerance)
                    executed =
                        trace_every == 0 ? executor(model, request["profile"]; mask) :
                        _execute_traced(
                            executor,
                            model,
                            data,
                            request["profile"],
                            directory,
                            mask,
                            trace_every,
                        )
                    return merge!(result, executed)
                end
            end
        end
    catch err
        err isa InterruptException && rethrow()
        result["exception"] = sprint(showerror, err, catch_backtrace())
        result["exception_type"] = string(typeof(err))
        result["status"] = get(result, "status", "harness_exception")
    end
    result["outer_seconds"] = (time_ns()-outer)/1e9
    if haskey(result, "solution")
        x = pop!(result, "solution")
        file = _write(joinpath(directory, "solution.toml"), Dict("x"=>x))
        result["has_solution"] = true
        result["solution_sha256"] = _sha(file)
        try
            merge!(result, _metrics(model, data, x, tolerance))
        catch err
            result["diagnostic_error"] = sprint(showerror, err, catch_backtrace())
        end
    end
    result["classification"] = _category(result)
    result["completed_utc"] = _utc()
    result["state"] = "complete"
    _write(joinpath(directory, "result.toml"), result)
    return result
end

"""Read and integrity-check a completed or interrupted attempt without filtering failures."""
function read_trial(directory)
    request = TOML.parsefile(joinpath(directory, "request.toml"))
    request["schema"] == SCHEMA || error("unsupported trial schema")
    _sha(joinpath(directory, "start.toml")) == request["start_sha256"] ||
        error("start checksum mismatch")
    file = normpath(joinpath(directory, request["case_file"]))
    _sha(file) == request["case_sha256"] || error("case checksum mismatch")
    result = TOML.parsefile(joinpath(directory, "result.toml"))
    if get(result, "has_solution", false)
        _sha(joinpath(directory, "solution.toml")) == result["solution_sha256"] ||
            error("solution checksum mismatch")
    end
    if haskey(result, "trace_sha256")
        _sha(joinpath(directory, result["trace_file"])) == result["trace_sha256"] ||
            error("trace checksum mismatch")
    end
    return (; request, result)
end

"""Independently recheck a stored point before using it as a numerical feasibility witness."""
function verified_point(directory; tolerance = 1e-7)
    isfinite(tolerance) && tolerance > 0 ||
        throw(ArgumentError("invalid witness tolerance"))
    saved = read_trial(directory)
    get(saved.result, "has_solution", false) || return nothing
    data = load_case(
        normpath(joinpath(directory, saved.request["case_file"]));
        expected_sha = saved.request["case_sha256"],
    )
    x = TOML.parsefile(joinpath(directory, "solution.toml"))["x"]
    metrics = _metrics(TransmissionOPFModel(data), data, x, tolerance)
    return metrics["physically_feasible"] ? Float64.(x) : nothing
end

function replay_trial(directory, output)
    saved = read_trial(directory)
    data = load_case(
        normpath(joinpath(directory, saved.request["case_file"]));
        expected_sha = saved.request["case_sha256"],
    )
    stored_start = TOML.parsefile(joinpath(directory, "start.toml"))
    haskey(stored_start, "x") ||
        error("requested start was unavailable; there is no solve to replay")
    start = stored_start["x"]
    return run_trial(
        data,
        start,
        saved.request["profile"],
        output;
        role = saved.request["role"],
        start_label = saved.request["start_label"],
        tolerance = saved.request["tolerance"],
        mask = get(saved.request, "sector_mask", nothing),
        trace_every = get(saved.request, "trace_every", 0),
        provenance = Dict(
            "replayed_from"=>abspath(directory),
            "original_environment"=>get(saved.request, "environment", Dict()),
        ),
    )
end

include("search-trace.jl")
include("hard-search-driver.jl")
include("transition-search.jl")
include("reduction-search.jl")
include("application-search.jl")
include("expansion-search.jl")
include("operating-search.jl")
end
