using Test, SHA, NLPModels, MPCCModels, JuMP, LinearAlgebra, Random
include("model.jl")
using .DroopExamples

@testset "Fixed-droop model collection" begin
    for line in eachline(joinpath(@__DIR__, "data", "SHA256SUMS"))
        hash, file = split(line; limit = 2)
        @test bytes2hex(sha256(read(joinpath(@__DIR__, "data", strip(file))))) == hash
    end
    @test_throws ArgumentError droop_case(:unknown)
    for name in (:zero, :narrow, :wide)
        data = droop_case(name)
        built = build_droop(data)
        x = lift_state(built, data.states["reference"])
        report = replay(data, data.states["reference"])
        @test report.valid
        @test report.loss ≈ data.meta["reference_objective_pu"] atol=1e-12
        @test obj(built.nlp, x) ≈ report.loss atol=1e-12
        @test obj(built.mpcc, x) ≈ obj(built.nlp, x) atol=1e-12
        @test is_vertical(built.mpcc)
        @test built.mpcc.meta.ncc == (name==:zero ? 102 : 204)
        @test built.nlp.meta.nvar == (name==:zero ? 1435 : 1639)
        @test length(x) == built.nlp.meta.nvar
        # MathOptNLPModel's variable mapping agrees with explicit JuMP indices.
        @test built.nlp.meta.x0 == start_value.(all_variables(built.model))
        residual = model_residuals(built, x)
        @test residual.bounds <= 1e-6
        @test residual.constraints <= 1e-5
        @test residual.products <= 1e-5
        @test comp_left(built.mpcc, x) ==
              [x[JuMP.index(a).value] for (a, b) in built.layout.pairs]
        @test comp_right(built.mpcc, x) ==
              [x[JuMP.index(b).value] for (a, b) in built.layout.pairs]
        # Exercise derivatives off the saved point, including all variable groups.
        rng = MersenneTwister(42)
        z = x .+ 1e-3 .* randn(rng, length(x))
        d = randn(rng, length(x))
        d ./= norm(d)
        h = 1e-6
        j = jac(built.nlp, z)
        @test j*d ≈ (cons(built.nlp, z+h*d)-cons(built.nlp, z-h*d))/(2h) rtol=1e-6 atol=1e-6
        @test dot(grad(built.nlp, z), d) ≈
              (obj(built.nlp, z+h*d)-obj(built.nlp, z-h*d))/(2h) atol=1e-7
        y = randn(rng, built.nlp.meta.ncon)
        hd = hess(built.nlp, z, y)*d
        lag_grad(t) = grad(built.nlp, t)+jac(built.nlp, t)'*y
        @test hd ≈ (lag_grad(z+h*d)-lag_grad(z-h*d))/(2h) rtol=1e-5 atol=1e-4
        @test cons(built.mpcc, z) ≈ cons(built.nlp, z)
        @test jac(built.mpcc, z) ≈ j
        @test jprod!(built.mpcc, z, d, zeros(length(y))) ≈ j*d
        @test jtprod!(built.mpcc, z, y, zeros(length(z))) ≈ j'*y
        @test hess(built.mpcc, z, y) ≈ hess(built.nlp, z, y)
        bad = deepcopy(data.states["reference"])
        bad["vm"][1] += 0.02
        @test !replay(data, bad).valid
        bad = deepcopy(data.states["reference"])
        bad["pg"][1] += 0.01
        @test !replay(data, bad).valid
        a = first(built.layout.aux)
        bad = deepcopy(data.states["reference"])
        bad["qg"][a.i] += 0.01
        @test replay(data, bad).droop > 1e-5
        # Break only complementarity: increase both projection multipliers.
        corrupt = copy(x)
        corrupt[JuMP.index(a.ml).value] += 0.1
        corrupt[JuMP.index(a.mu).value] += 0.1
        @test model_residuals(built, corrupt).products > 1e-5
        relaxed = build_droop(data; encoding = :relaxed)
        @test relaxed.mpcc === nothing
        @test relaxed.nlp.meta.nvar == length(x)
        smooth = build_droop(data; encoding = :smooth)
        @test smooth.mpcc === nothing
        @test smooth.nlp.meta.nvar == 1180
    end
end
