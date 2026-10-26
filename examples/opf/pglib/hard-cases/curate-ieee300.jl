# Manual research receipt builder; does not run or alter any solver attempt.
# julia --project=examples/opf/pglib examples/opf/pglib/hard-cases/curate-ieee300.jl SEARCH_DIR CANONICAL_DIR OUTPUT SENSITIVITY_DIR
using TOML, Ipopt
include("../hard-search.jl")
using .HardCaseSearch
const H=HardCaseSearch
const T=H.TransmissionOPF
bits(x) = bytes2hex(H.sha256(join(bitstring.(Float64.(x)), "\n")))

function portable_record(path, root)
    p, r=read_trial(path)
    row=merge(
        copy(r),
        Dict{String,Any}(
            "trial"=>relpath(path, root),
            "case_sha256"=>p["case_sha256"],
            "profile"=>p["profile"],
            "role"=>p["role"],
            "start_label"=>p["start_label"],
            "tolerance"=>get(p, "tolerance", NaN),
            "provenance"=>p["provenance"],
            "environment"=>get(p, "environment", Dict()),
        ),
    )
    haskey(p, "sector_mask") && (row["sector_mask"]=p["sector_mask"])
    start=TOML.parsefile(joinpath(path, "start.toml"))
    if haskey(start, "x")
        row["start"]=start["x"]
        row["start_bits_sha256"]=bits(row["start"])
    end
    if get(r, "has_solution", false)
        row["x"]=H._point(path)
        row["point_bits_sha256"]=bits(row["x"])
    end
    return row
end

function curate_ieee300(directory, canonical, output; sensitivities = nothing)
    rows=summarize_applications(directory)
    @assert length(rows)==36 && all(r->!r["superseded"], rows)
    summary=TOML.parsefile(joinpath(directory, "summary.toml"))
    plan=TOML.parsefile(joinpath(directory, "plan.toml"))
    @assert plan["network"]=="ieee300"
    cases=Dict{String,Any}[]
    for (key, info) in sort(collect(summary["cases"]); by = first)
        input=joinpath(directory, "cases", key, "input.toml")
        data=H.load_case(input)
        row=merge(copy(info), Dict("input_snapshot_sha256"=>H._sha(input)))
        if info["witness_available"]
            path=joinpath(directory, info["witness_trial"])
            @assert !isnothing(verified_point(path; tolerance = 1e-7))
            row["witness"]=portable_record(path, directory)
        end
        path=joinpath(directory, info["counterfactual"])
        row["counterfactual_record"]=portable_record(path, directory)
        push!(cases, row)
    end
    trials=Dict{String,Any}[]
    for info in rows
        row=portable_record(joinpath(directory, info["trial"]), directory)
        for k in (
            "family",
            "level",
            "network",
            "finding",
            "witness_available",
            "nvar",
            "ncon",
            "ncc",
        )
            row[k]=info[k]
        end
        push!(trials, row)
    end
    data=T.transmission_case(:ieee300)
    pm=TOML.parsefile(joinpath(canonical, "canonical-powermodels.toml"))
    pm["validation_solver"]="PowerModels ACPPowerModel / Ipopt"
    pm["ipopt_version"]=string(pkgversion(Ipopt))
    pm["validation_options"]=Dict("tol"=>1e-9, "bound_relax_factor"=>0.0)
    own=portable_record(joinpath(canonical, "canonical"), canonical)
    @assert own["physically_feasible"] && pm["physically_feasible"]
    @assert own["case_sha256"]==H._digest(H._snapshot(data))
    classification=Dict(
        k=>count(r->r["classification"]==k, trials) for
        k in unique(r["classification"] for r in trials)
    )
    fixture=Dict(
        "schema"=>1,
        "network"=>"ieee300",
        "source_revision"=>T.PGLIB_REVISION,
        "source_file"=>data.provenance.file,
        "source_file_sha256"=>H._sha(joinpath(H.HERE, "data", data.provenance.file)),
        "plan"=>plan,
        "classifications"=>classification,
        "canonical"=>Dict(
            "input_snapshot_sha256"=>own["case_sha256"],
            "madnlp"=>own,
            "powermodels"=>pm,
        ),
        "cases"=>cases,
        "trials"=>trials,
    )
    if !isnothing(sensitivities)
        studies=Dict{String,Any}[]
        for name in sort(readdir(sensitivities))
            path=joinpath(sensitivities, name)
            isfile(joinpath(path, "request.toml")) || continue
            record=portable_record(path, sensitivities)
            row=Dict{String,Any}(
                "family"=>record["provenance"]["family"],
                "label"=>record["provenance"]["label"],
                "record"=>record,
            )
            row["verified"]=!isnothing(verified_point(path; tolerance = 1e-7))
            row["verified"] &&
                (row["coverage"]=TOML.parsefile(joinpath(path, "coverage.toml")))
            push!(studies, row)
        end
        @assert length(studies)==4
        fixture["sensitivities"]=studies
    end
    H._write(output, fixture)
    cp(
        joinpath(directory, "summary.tsv"),
        replace(output, r"\.toml$"=>"-sweep.tsv");
        force = true,
    )
    println((cases = length(cases), classifications = classification, output))
    return nothing
end

if abspath(PROGRAM_FILE)==abspath(@__FILE__)
    length(ARGS)==4 || error("expected SEARCH_DIR CANONICAL_DIR OUTPUT SENSITIVITY_DIR")
    curate_ieee300(ARGS[1], ARGS[2], ARGS[3]; sensitivities = ARGS[4])
end
