# Mandatory PR checks: no optimizer invocation or fresh difficulty search.
using Test, TOML, SHA, NLPModels, MPCCModels
include("hard-search.jl")
const H=HardCaseSearch
const T=H.TransmissionOPF

@testset "Compact physical witnesses and authoritative receipt identities" begin
    fixture=TOML.parsefile(joinpath(@__DIR__, "hard-cases", "fast-witnesses.toml"))
    index=TOML.parsefile(joinpath(@__DIR__, "hard-cases", "evidence", "index.toml"))
    @test count(r->r["spec"]["kind"]!="operating", fixture["points"])==14
    @test 4<=count(r->r["spec"]["kind"]=="operating", fixture["points"])<=6
    for (name, hash) in fixture["source_receipts"]
        @test hash==index["receipts"][name]["sha256"]
    end
    for row in fixture["points"]
        spec=row["spec"]
        network=Symbol(spec["network"])
        data=if spec["kind"]=="canonical"
            T.transmission_case(network)
        elseif spec["kind"]=="application"
            T.application_case(
                Symbol(spec["family"]);
                network,
                level = Symbol(spec["level"]),
            )
        elseif spec["kind"]=="operating"
            T.operating_condition_case(spec["condition"])
        else
            T.application_expansion_case((; (Symbol(k)=>Symbol(v) for (k, v) in spec)...))
        end
        @test H._digest(H._snapshot(data))==row["input_snapshot_sha256"]
        x=row["x"]
        @test bytes2hex(sha256(join(bitstring.(Float64.(x)), "\n")))==row["point_bits_sha256"]
        model=T.TransmissionOPFModel(data)
        @test maximum(values(T.transmission_residuals(model, data, x)))<=1e-7
        @test obj(model, x)≈row["objective"] atol=1e-5
        if haskey(row, "policy_activity")
            coverage=T.application_policy_coverage(data, x)
            @test all(coverage[k]==v for (k, v) in row["policy_activity"])
        end
    end
end

include("test-reporting.jl")
