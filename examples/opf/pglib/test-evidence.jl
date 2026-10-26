using Test, TOML, SHA
include("curate-fast-fixtures.jl")

@testset "Lossless receipt archive integrity and corrupt-cache rejection" begin
    index=TOML.parsefile(joinpath(BenchmarkEvidence.DIRECTORY, "index.toml"))
    @test length(index["receipts"])==8
    mktempdir() do cache
        for (name, entry) in index["receipts"]
            file=evidence_file(name; cache)
            @test filesize(file)==entry["bytes"]
            @test bytes2hex(sha256(read(file)))==entry["sha256"]
            @test !isempty(TOML.parsefile(file))
            @test evidence_file(name; cache)==file
        end
        name=first(sort(collect(keys(index["receipts"]))))
        file=evidence_file(name; cache)
        write(file, "corrupt")
        @test_throws ErrorException evidence_file(name; cache)
        rm(file)
        @test filesize(evidence_file(name; cache))==index["receipts"][name]["bytes"]
        @test_throws ArgumentError evidence_file("../unknown.toml"; cache)
    end
    mktempdir() do directory
        cp(
            joinpath(BenchmarkEvidence.DIRECTORY, "index.toml"),
            joinpath(directory, "index.toml"),
        )
        name=first(sort(collect(keys(index["receipts"]))))
        write(joinpath(directory, index["receipts"][name]["file"]), "corrupt")
        @test_throws ErrorException evidence_file(name; directory)
    end
    mktempdir() do directory
        output=joinpath(directory, "fast.toml")
        curate_fast_fixtures(output)
        @test read(output)==read(joinpath(@__DIR__, "hard-cases", "fast-witnesses.toml"))
    end
end
