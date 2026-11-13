# Read-only curation of a completed research matrix. Never runs or changes a solve.
using TOML, SHA
include("hard-search.jl")
const H=HardCaseSearch
const T=H.TransmissionOPF
_point_bits(x) = bytes2hex(sha256(join(bitstring.(Float64.(x)), "\n")))
_condition_group(id) = first(split(string(id), "_"))

function condition_features(data, x)
    coverage=T.operating_condition_coverage(data, x)
    features=Set(String.(coverage["combined_activity"]))
    boundary=Set(data.provenance.export_boundary)
    thermal=Set(
        vcat(
            coverage["network_tight"]["thermal_from"],
            coverage["network_tight"]["thermal_to"],
        ),
    )
    !isempty(intersect(boundary, thermal)) && push!(features, "export_boundary_thermal")
    for (key, ids) in coverage["network_tight"]
        !isempty(ids) && push!(features, "native:"*key)
    end
    for key in (
        "vv_injection_plateau",
        "vv_absorption_plateau",
        "vw_lower_plateau",
        "strict_vw_binding",
        "capability_binding",
    )
        !isempty(coverage[key]) && push!(features, key)
    end
    for (i, c) in enumerate(coverage["controllers"])
        for law in (:vv, :vw)
            position=getproperty(c, law)
            push!(features, "$(law):$(position.region)")
            getproperty(c.knot_distance, law)<=1e-4 && push!(features, "$(law):near_knee")
            if !isnothing(position.fraction)
                curve=getproperty(data.controllers[i], law)
                k=parse(Int, split(string(position.region), "_")[end])
                curve.values[k]==curve.values[k+1] && continue
                stratum=position.fraction<0.35 ? "early" :
                        position.fraction>0.65 ? "late" : "middle"
                push!(features, "$(law):ramp_$(stratum)")
                law==:vw &&
                    string(c.id) in coverage["strict_vw_binding"] &&
                    push!(features, "strict_vw:ramp_$(stratum)")
            end
        end
    end
    return sort!(collect(features))
end

"""Deterministic bounded selection of verified inputs, balancing networks and difficulty.

Reserve/export anchors are represented for each network. Then observed difficulty
strata and study groups are filled, followed by marginal physical coverage. Ties
use case IDs, not solver runtime. Unresolved inputs remain in the full census.
"""
function select_operating_cases(candidates; limit = 12)
    limit>=4 && iseven(limit) ||
        throw(ArgumentError("selection limit must be even and at least four"))
    available=sort(filter(r->r["reference_available"], candidates); by = r->r["case_key"])
    selected=Dict{String,Any}[]
    covered=Set{String}()
    quota=div(limit, 2)
    function choose(pool)
        eligible=filter(
            r->!(r in selected) &&
               count(s->s["spec"]["network"]==r["spec"]["network"], selected)<quota,
            pool,
        )
        isempty(eligible) && return false
        sort!(
            eligible;
            by = r->(-length(setdiff(Set(r["features"]), covered)), r["case_key"]),
        )
        row=first(eligible)
        push!(selected, row)
        union!(covered, row["features"])
        return true
    end
    for network in ("ieee118", "ieee300"), group in ("reserve", "export")
        length(selected)>=limit && break
        choose(filter(r->r["spec"]["network"]==network && r["group"]==group, available))
    end
    for network in ("ieee118", "ieee300"),
        difficulty in ("easy", "mixed", "difficult_under_budget")

        length(selected)>=limit && break
        any(r->r["spec"]["network"]==network && r["difficulty"]==difficulty, selected) &&
            continue
        choose(
            filter(
                r->r["spec"]["network"]==network && r["difficulty"]==difficulty,
                available,
            ),
        )
    end
    for group in sort(unique(r["group"] for r in available))
        length(selected)>=limit && break
        any(r->r["group"]==group, selected) && continue
        choose(filter(r->r["group"]==group, available))
    end
    while length(selected)<limit && choose(available)
    end
    return sort!(selected; by = r->r["case_key"])
end

function _condition_portable(path, directory, configurations)
    saved=H.read_trial(path)
    p, r=saved.request, saved.result
    settings=Dict(k=>r[k] for k in ("resolved_ipm", "resolved_relaxation") if haskey(r, k))
    digest=H._digest(settings)
    configurations[digest]=settings
    result=Dict{String,Any}(
        "trial"=>relpath(path, directory),
        "case_sha256"=>p["case_sha256"],
        "request_sha256"=>H._sha(joinpath(path, "request.toml")),
        "result_sha256"=>H._sha(joinpath(path, "result.toml")),
        "profile"=>p["profile"],
        "start_label"=>p["start_label"],
        "role"=>p["role"],
        "tolerance"=>p["tolerance"],
        "configuration_sha256"=>digest,
        "source_fingerprint"=>p["environment"]["source_fingerprint"],
    )
    for (k, v) in r
        k in ("resolved_ipm", "resolved_relaxation", "controllers", "initial") ||
            (result[k]=v)
    end
    start=TOML.parsefile(joinpath(path, "start.toml"))
    if haskey(start, "x")
        result["start"]=start["x"]
        result["start_bits_sha256"]=_point_bits(start["x"])
    end
    if get(r, "has_solution", false)
        result["x"]=H._point(path)
        result["point_bits_sha256"]=_point_bits(result["x"])
    end
    return result
end

function curate_operating_conditions(directory, output; limit = 12)
    endswith(output, ".toml") || throw(ArgumentError("receipt must have a .toml suffix"))
    outputs=(
        output,
        replace(output, r"\.toml$"=>"-census.tsv"),
        replace(output, r"\.toml$"=>"-sweep.tsv"),
    )
    any(ispath, outputs) && throw(ArgumentError("choose fresh receipt/table paths"))
    plan=TOML.parsefile(joinpath(directory, "plan.toml"))
    summary=TOML.parsefile(joinpath(directory, "summary.toml"))["cases"]
    length(summary)==length(plan["specs"]) || error("incomplete condition census")
    all(length(r["trials"])==2length(plan["profiles"]) for r in summary) ||
        error("incomplete raw matrix")
    configurations=Dict{String,Any}()
    candidates=Dict{String,Any}[]
    for row in summary
        reference=row["reference"]
        candidate=Dict{String,Any}(
            k=>row[k] for
            k in ("case_key", "spec", "input_snapshot_sha256", "difficulty", "successes")
        )
        candidate["group"]=_condition_group(row["spec"]["id"])
        candidate["reference_available"]=reference["verified"]
        candidate["features"]=String[]
        candidate["raw_classifications"]=[
            H.read_trial(joinpath(directory, p)).result["classification"] for
            p in row["trials"]
        ]
        if reference["verified"]
            data=T.operating_condition_case(row["spec"])
            H._digest(H._snapshot(data))==row["input_snapshot_sha256"] ||
                error("candidate input changed")
            metrics=H._metrics(
                T.TransmissionOPFModel(data),
                data,
                reference["x"],
                plan["witness_tolerance"],
            )
            metrics["physically_feasible"] ||
                error("candidate reference no longer verifies")
            candidate["features"]=condition_features(data, reference["x"])
            candidate["export_boundary_binding"]="export_boundary_thermal" in
                                                 candidate["features"]
            cv=T.operating_condition_coverage(data, reference["x"])
            candidate["reference_max_residual"]=maximum(values(metrics["residuals"]))
            candidate["curtailed_mw"]=cv["curtailed_mw"]
            candidate["strict_vw_count"]=length(cv["strict_vw_binding"])
            candidate["capability_count"]=length(cv["capability_binding"])
            candidate["vv_injection_count"]=length(cv["vv_injection_plateau"])
            candidate["vv_absorption_count"]=length(cv["vv_absorption_plateau"])
            candidate["q_upper_count"]=length(cv["network_tight"]["generator_q_upper"])
            candidate["thermal_ends"]=length(cv["network_tight"]["thermal_from"])+length(
                cv["network_tight"]["thermal_to"],
            )
        end
        push!(candidates, candidate)
    end
    selected=select_operating_cases(candidates; limit)
    records=Dict{String,Any}[]
    for selected_row in selected
        row=only(filter(r->r["case_key"]==selected_row["case_key"], summary))
        reference=row["reference"]
        data=T.operating_condition_case(row["spec"])
        record=copy(selected_row)
        record["reference"]=Dict(
            "x"=>reference["x"],
            "point_bits_sha256"=>_point_bits(reference["x"]),
            "point_sha256"=>reference["point_sha256"],
            "reference_kind"=>reference["reference_kind"],
            "reference_path"=>reference["reference_path"],
            "attempts"=>reference["attempts"],
            "metrics"=>reference["metrics"],
            "source_receipt_sha256"=>reference["source_receipt_sha256"],
            "coverage"=>H._plain(T.operating_condition_coverage(data, reference["x"])),
        )
        record["trials"]=[
            _condition_portable(joinpath(directory, p), directory, configurations) for
            p in row["trials"]
        ]
        record["counterfactual"]=_condition_portable(
            joinpath(directory, row["counterfactual"]),
            directory,
            configurations,
        )
        record["population"]=length(data.controllers)
        record["nvar"]=T.transmission_layout(data).nvar
        record["ncc"]=length(T.transmission_layout(data).r)
        push!(records, record)
    end
    source_files=Dict(
        string(n)=>H._sha(joinpath(@__DIR__, "data", getproperty(T.PGLIB_FILES, n))) for
        n in (:ieee118, :ieee300)
    )
    receipt=Dict(
        "schema"=>1,
        "family"=>"operating_conditions",
        "source_revision"=>T.PGLIB_REVISION,
        "source_files"=>source_files,
        "plan_sha256"=>H._sha(joinpath(directory, "plan.toml")),
        "curator_source_sha256"=>H._sha(@__FILE__),
        "plan"=>plan,
        "selection_limit"=>limit,
        "selection_policy"=>"network quotas; reserve/export; observed difficulty; study groups; marginal activity; lexicographic ties",
        "candidates"=>candidates,
        "cases"=>records,
        "configurations"=>configurations,
    )
    H._write(output, receipt)
    census=replace(output, r"\.toml$"=>"-census.tsv")
    open(census, "w") do io
        println(
            io,
            join(
                (
                    "case",
                    "group",
                    "network",
                    "reference",
                    "successes",
                    "difficulty",
                    "strict_vw",
                    "capability",
                    "vv_injection",
                    "vv_absorption",
                    "q_upper",
                    "thermal_ends",
                    "curtailed_mw",
                    "features",
                ),
                '\t',
            ),
        )
        for r in candidates
            println(
                io,
                join(
                    (
                        r["case_key"],
                        r["group"],
                        r["spec"]["network"],
                        r["reference_available"],
                        r["successes"],
                        r["difficulty"],
                        get(r, "strict_vw_count", ""),
                        get(r, "capability_count", ""),
                        get(r, "vv_injection_count", ""),
                        get(r, "vv_absorption_count", ""),
                        get(r, "q_upper_count", ""),
                        get(r, "thermal_ends", ""),
                        get(r, "curtailed_mw", ""),
                        join(r["features"], ";"),
                    ),
                    '\t',
                ),
            )
        end
    end
    trials=replace(output, r"\.toml$"=>"-sweep.tsv")
    open(trials, "w") do io
        println(
            io,
            "case\tprofile\tstart\tclassification\tstatus\titerations\tphysical_max\tobjective\ttrial",
        )
        for row in summary, p in row["trials"]
            request, result=H.read_trial(joinpath(directory, p))
            residual=get(result, "residuals", Dict{String,Any}())
            println(
                io,
                join(
                    (
                        row["case_key"],
                        request["profile"]["name"],
                        request["start_label"],
                        result["classification"],
                        result["status"],
                        get(result, "iterations", ""),
                        isempty(residual) ? "" : maximum(values(residual)),
                        get(result, "objective", ""),
                        p,
                    ),
                    '\t',
                ),
            )
        end
    end
    println((
        candidates = length(candidates),
        references = count(r->r["reference_available"], candidates),
        retained = length(records),
        output,
    ))
    return receipt
end

if abspath(PROGRAM_FILE)==@__FILE__
    length(ARGS)==2 || error("expected COMPLETED_SEARCH_DIR OUTPUT.toml")
    curate_operating_conditions(ARGS[1], ARGS[2])
end
