# Optional integration gate: original feasibility AND intended solved coverage.
using Test
include("solve.jl")

@testset "Solved OPF coverage" begin
    for name in balanced_ac_opf_cases()
        @testset "$name" begin
            result = solve_opf_case(name; verbose = false)
            @test result.coverage.targets_met === true
            @test maximum(values(result.residuals)) <= 1e-5
            @test length(result.coverage.controllers) == length(result.data.controllers)
            @test result.homotopy.status in
                  (CCOpt.MadNLP.SOLVE_SUCCEEDED, CCOpt.MadNLP.SOLVED_TO_ACCEPTABLE_LEVEL)
            if result.polished
                @test maximum(values(result.homotopy_residuals)) > 1e-5 ||
                      result.homotopy_coverage.targets_met !== true
                @test result.stats !== result.homotopy
                @test result.residuals.complementarity == 0
            end
        end
    end
end
