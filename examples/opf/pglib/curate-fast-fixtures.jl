# Derive a small, solver-free PR fixture from the lossless historical receipts.
using TOML, SHA
include("benchmark-evidence.jl")
using .BenchmarkEvidence

function curate_fast_fixtures(output)
    entries=Dict{String,Any}[]
    sources=Dict{String,String}()
    function add_point(name, row, point, spec; coverage = nothing)
        path=evidence_file(name)
        sources[name]=bytes2hex(sha256(read(path)))
        entry=Dict(
            "receipt"=>name,
            "spec"=>spec,
            "input_snapshot_sha256"=>row["input_snapshot_sha256"],
            "point_bits_sha256"=>point["point_bits_sha256"],
            "x"=>point["x"],
            "objective"=>point["objective"],
        )
        if !isnothing(coverage)
            entry["policy_activity"]=Dict(
                k=>coverage[k] for k in (
                    "strict_vw_binding",
                    "availability_vw_joint",
                    "strict_capability_binding",
                    "vv_injection_plateau",
                    "vv_absorption_plateau",
                    "vw_lower_plateau",
                )
            )
        end
        return push!(entries, entry)
    end
    name="ieee118-applications.toml"
    for row in TOML.parsefile(evidence_file(name))["cases"]
        row["level"]=="nominal" || continue
        spec=Dict(
            "kind"=>"application",
            "network"=>"ieee118",
            "family"=>row["family"],
            "level"=>row["level"],
        )
        add_point(name, row, row["witness"], spec)
    end
    name="ieee300-applications.toml"
    canonical=TOML.parsefile(evidence_file(name))["canonical"]
    for solver in ("madnlp", "powermodels")
        add_point(
            name,
            canonical,
            canonical[solver],
            Dict("kind"=>"canonical", "network"=>"ieee300", "solver"=>solver),
        )
    end
    name="ieee300-policy-matrix.toml"
    for row in TOML.parsefile(evidence_file(name))["cases"]
        add_point(
            name,
            row,
            row["reference_record"],
            row["spec"];
            coverage = row["witness_coverage"],
        )
    end
    name="operating-conditions.toml"
    operating=TOML.parsefile(evidence_file(name))["cases"]
    for network in ("ieee118", "ieee300"),
        difficulty in ("easy", "mixed", "difficult_under_budget")

        matching=filter(
            r->r["spec"]["network"]==network && r["difficulty"]==difficulty,
            operating,
        )
        isempty(matching) && continue
        row=first(sort(matching; by = r->r["case_key"]))
        reference=row["reference"]
        point=Dict(
            "x"=>reference["x"],
            "point_bits_sha256"=>reference["point_bits_sha256"],
            "objective"=>reference["metrics"]["objective"],
        )
        spec=Dict("kind"=>"operating", "network"=>network, "condition"=>row["spec"])
        add_point(name, row, point, spec; coverage = reference["coverage"])
    end
    open(output, "w") do io
        return TOML.print(
            io,
            Dict("schema"=>1, "source_receipts"=>sources, "points"=>entries);
            sorted = true,
        )
    end
end

if abspath(PROGRAM_FILE)==@__FILE__
    length(ARGS)==1 || error("expected OUTPUT.toml")
    curate_fast_fixtures(only(ARGS))
end
