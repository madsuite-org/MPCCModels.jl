# Numerical receipt only; does not rerun or overwrite solver attempts.
# julia --project=examples/opf/pglib examples/opf/pglib/hard-cases/curate-policy-matrix.jl SEARCH_DIR REFERENCE_DIR OUTPUT
include("curate-ieee300.jl")

function curate_policy_matrix(directory, references, output)
    rows=H.summarize_expansions(directory)
    @assert length(rows)==36 && all(r->!r["superseded"], rows)
    summary=TOML.parsefile(joinpath(directory, "summary.toml"))
    plan=TOML.parsefile(joinpath(directory, "plan.toml"))
    prepared=TOML.parsefile(joinpath(references, "references.toml"))
    @assert H._sha(joinpath(references, "references.toml"))==plan["prepared_reference_sha256"]
    @assert length(prepared["cases"])==9
    cases=Dict{String,Any}[]
    for (key, info) in sort(collect(summary["cases"]); by = first)
        row=merge(copy(info), Dict("case_key"=>key))
        @assert info["witness_available"]
        input=joinpath(directory, "cases", key, "input.toml")
        row["input_snapshot_sha256"]=H._sha(input)
        ref=only(filter(r->r["case_key"]==key, prepared["cases"]))
        @assert ref["case_sha256"]==row["input_snapshot_sha256"]
        row["reference_record"]=portable_record(
            joinpath(references, ref["reference_trial"]),
            references,
        )
        @assert !isnothing(
            H.verified_point(
                joinpath(references, ref["reference_trial"]);
                tolerance = 1e-7,
            ),
        )
        baseline=replace(key, r"-both$"=>"-dispatchable")
        attempts=sort(
            filter(
                n->startswith(n, baseline*"-attempt-"),
                readdir(joinpath(directory, "counterfactuals")),
            ),
        )
        path=joinpath(directory, "counterfactuals", last(attempts))
        row["counterfactual_record"]=portable_record(path, directory)
        point=H.verified_point(path; tolerance = 1e-5)
        if !isnothing(point)
            p=H.read_trial(path).request
            data=H.load_case(
                normpath(joinpath(path, p["case_file"]));
                expected_sha = p["case_sha256"],
            )
            row["counterfactual_coverage"]=H._plain(
                T.application_policy_coverage(data, point),
            )
        end
        push!(cases, row)
    end
    trials=Dict{String,Any}[]
    for info in rows
        row=portable_record(joinpath(directory, info["trial"]), directory)
        for k in ("case_key", "spec", "finding", "witness_available", "nvar", "ncon", "ncc")
            row[k]=info[k]
        end
        push!(trials, row)
    end
    classification=Dict(
        k=>count(r->r["classification"]==k, trials) for
        k in unique(r["classification"] for r in trials)
    )
    file=T.PGLIB_FILES.ieee300
    fixture=Dict(
        "schema"=>1,
        "network"=>"ieee300",
        "source_revision"=>T.PGLIB_REVISION,
        "source_file"=>file,
        "source_file_sha256"=>H._sha(joinpath(H.HERE, "data", file)),
        "source_application_sha256"=>plan["source_witness_sha256"],
        "prepared_reference_sha256"=>plan["prepared_reference_sha256"],
        "reference_environment"=>TOML.parsefile(joinpath(references, "environment.toml")),
        "plan"=>plan,
        "classifications"=>classification,
        "cases"=>cases,
        "trials"=>trials,
    )
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
    length(ARGS)==3 || error("expected SEARCH_DIR REFERENCE_DIR OUTPUT")
    curate_policy_matrix(ARGS...)
end
