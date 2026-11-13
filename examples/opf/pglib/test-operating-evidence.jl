# Optional exhaustive evidence gate: never requires a new solver to repeat failures.
using Test, Random, NLPModels, MPCCModels
include("curate-operating-conditions.jl")

@testset "Deterministic compact selection balances scope without losing census" begin
    rows=Dict{String,Any}[]
    for n in ("ieee118", "ieee300"),
        g in (
            "reserve",
            "export",
            "backstop",
            "penetration",
            "placement",
            "injection",
            "absorption",
        ),
        (i, difficulty) in enumerate(("easy", "mixed", "difficult_under_budget"))

        push!(
            rows,
            Dict(
                "case_key"=>"$n-$g-$i",
                "reference_available"=>true,
                "spec"=>Dict("network"=>n),
                "group"=>g,
                "difficulty"=>difficulty,
                "features"=>[g, "feature-$i"],
            ),
        )
    end
    push!(rows, Dict("case_key"=>"unresolved", "reference_available"=>false))
    original=deepcopy(rows)
    selected=select_operating_cases(rows)
    @test rows==original
    @test length(selected)==12
    @test select_operating_cases(shuffle(MersenneTwister(26), rows))==selected
    @test all(r["reference_available"] for r in selected)
    for n in ("ieee118", "ieee300")
        @test count(r->r["spec"]["network"]==n, selected)==6
        @test all(
            any(r->r["spec"]["network"]==n && r["difficulty"]==d, selected) for
            d in ("easy", "mixed", "difficult_under_budget")
        )
    end
    @test Set(r["group"] for r in selected)==Set((
        "reserve",
        "export",
        "backstop",
        "penetration",
        "placement",
        "injection",
        "absorption",
    ))
    @test_throws ArgumentError select_operating_cases(rows; limit = 3)
end

@testset "Retained operating references and all raw numerical outcomes" begin
    fixture=TOML.parsefile(H.evidence_file("operating-conditions.toml"))
    @test fixture["source_revision"]==T.PGLIB_REVISION
    for (network, hash) in fixture["source_files"]
        @test H._sha(
            joinpath(@__DIR__, "data", getproperty(T.PGLIB_FILES, Symbol(network))),
        )==hash
    end
    @test length(fixture["candidates"])==46
    @test length(fixture["cases"])==12
    selected=select_operating_cases(
        fixture["candidates"];
        limit = fixture["selection_limit"],
    )
    @test [r["case_key"] for r in selected]==[r["case_key"] for r in fixture["cases"]]
    for (hash, settings) in fixture["configurations"]
        @test H._digest(settings)==hash
    end
    function check_point(data, record)
        @test _point_bits(record["x"])==record["point_bits_sha256"]
        metrics=H._metrics(
            T.TransmissionOPFModel(data),
            data,
            record["x"],
            record["tolerance"],
        )
        @test metrics["physically_feasible"]==record["physically_feasible"]
        @test isequal(metrics["objective"], record["objective"]) ||
              isapprox(metrics["objective"], record["objective"]; atol = 1e-5)
        for (k, v) in record["residuals"]
            @test metrics["residuals"][k]≈v atol=1e-8
        end
    end
    for row in fixture["cases"]
        data=T.operating_condition_case(row["spec"])
        @test H._digest(H._snapshot(data))==row["input_snapshot_sha256"]
        reference=row["reference"]
        @test _point_bits(reference["x"])==reference["point_bits_sha256"]
        @test H._digest(Dict("x"=>reference["x"]))==reference["point_sha256"]
        @test maximum(
            values(
                T.transmission_residuals(
                    T.TransmissionOPFModel(data),
                    data,
                    reference["x"],
                ),
            ),
        )<=1e-7
        @test H._plain(T.operating_condition_coverage(data, reference["x"]))==reference["coverage"]
        @test condition_features(data, reference["x"])==row["features"]
        @test length(row["trials"])==4
        successes=0
        for trial in row["trials"]
            @test trial["case_sha256"]==row["input_snapshot_sha256"]
            @test trial["source_fingerprint"]==fixture["plan"]["environment"]["source_fingerprint"]
            @test haskey(fixture["configurations"], trial["configuration_sha256"])
            @test H._category(trial)==trial["classification"]
            @test trial["profile"]["max_iter"]==500 &&
                  trial["profile"]["max_wall_time"]==30.0
            @test _point_bits(trial["start"])==trial["start_bits_sha256"]
            @test !haskey(trial, "sector_mask")
            @test trial["start"]==(
                trial["start_label"]=="witness" ? reference["x"] :
                get_x0(T.TransmissionOPFModel(data))
            )
            haskey(trial, "x") && check_point(data, trial)
            successes+=trial["classification"]=="success"
        end
        @test successes==row["successes"]
        @test row["difficulty"]==(
            successes==4 ? "easy" : successes==0 ? "difficult_under_budget" : "mixed"
        )
        baseline=T.operating_condition_case(row["spec"]; laws = :dispatchable)
        @test H._digest(H._snapshot(baseline))==row["counterfactual"]["case_sha256"]
        haskey(row["counterfactual"], "x") && check_point(baseline, row["counterfactual"])
        projected=T.transmission_start(baseline, data, reference["x"])
        @test maximum(
            values(
                T.transmission_residuals(
                    T.TransmissionOPFModel(baseline),
                    baseline,
                    projected,
                ),
            ),
        )<=1e-7
    end
    @test length(
        readlines(joinpath(@__DIR__, "hard-cases", "operating-conditions-census.tsv")),
    )==47
    @test length(
        readlines(joinpath(@__DIR__, "hard-cases", "operating-conditions-sweep.tsv")),
    )==185
end

@testset "Recorder preserves starts, failed iterations and resume identity" begin
    mktempdir() do directory
        out=joinpath(directory, "matrix")
        kwargs=(
            specs = [first(T.operating_condition_specs())],
            profiles = [:current],
            max_iter = 1,
            max_wall_time = 2.0,
            reference_max_iter = 100,
            reference_max_wall_time = 10.0,
            progress = false,
        )
        rows=H.run_operating_matrix(out; kwargs...)
        @test only(rows)["reference"]["verified"]
        @test length(only(rows)["trials"])==2
        saved=Dict(p=>read(joinpath(out, p, "result.toml")) for p in only(rows)["trials"])
        @test H.run_operating_matrix(out; kwargs..., resume = true)==rows
        @test all(read(joinpath(out, p, "result.toml"))==bytes for (p, bytes) in saved)
        @test_throws ErrorException H.run_operating_matrix(
            out;
            merge(kwargs, (max_iter = 2,))...,
            resume = true,
        )
        input=H._condition_input(out, only(kwargs.specs))
        ref=joinpath(out, "cases", input.key, "reference.toml")
        receipt=TOML.parsefile(ref)
        receipt["x"][1]+=0.01
        H._write(ref, receipt)
        @test_throws ErrorException H.run_operating_matrix(out; kwargs..., resume = true)
    end
end
