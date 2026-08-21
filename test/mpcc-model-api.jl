@testset "MPCCModel Tests" begin
    @testset "VarVar API" for T in [Float64, Float32]
        f(x) = (x[1] - 1)^2 + (x[2] - 1)^2
        ∇f(x) = T[2 * (x[1] - 1); 2 * (x[2] - 1)]
        H(x) = T[2.0 0; 0 2.0]
        c(x) = T[]
        J(x) = Array{T,2}(undef, 0, 2)
        H(x, y) = H(x)
        cc1(x) = T[x[1]]
        lcc1(x) = T[0.0]
        cc2(x) = T[x[2]]
        lcc2(x) = T[0.0]
        Jcc1(x) = T[1.0 0.0]
        Jcc2(x) = T[0.0 1.0]
        comp_res(x) = min(x[1], x[2])
        comp_res_prod(x) = x[1]*x[2]
        comp_res_sum(x) = x[1]*x[2]

        mpcc = SimpleMPCCModel(T)
        n = get_nvar(mpcc)
        m = get_ncon(mpcc)
        ncc = get_ncc(mpcc)
        @test n == 2
        @test m == 0
        @test ncc == 1

        x = randn(T, n)
        y = randn(T, m)
        v = randn(T, n)
        w = randn(T, m)
        Jv = zeros(T, m)
        Jtw = zeros(T, n)
        Hv = zeros(T, n)
        Hvals = zeros(T, get_nnzh(mpcc))

        # NLP api subset
        @test obj(mpcc, x) ≈ f(x)
        @test grad(mpcc, x) ≈ ∇f(x)
        @test hess(mpcc, x) ≈ H(x)
        @test cons(mpcc, x) ≈ c(x)
        @test jac(mpcc, x) ≈ J(x)
        @test hess(mpcc, x, y) ≈ H(x, y)
        # MPCC api
        @test comp_res_left(mpcc, x) ≈ comp_left(mpcc, x)
        @test comp_res_left(mpcc, x) ≈ cc1(x)
        @test comp_res_right(mpcc, x) ≈ comp_right(mpcc, x)
        @test comp_res_right(mpcc, x) ≈ cc2(x)
        @test jac_comp_left(mpcc, x) ≈ Jcc1(x)
        @test jac_comp_right(mpcc, x) ≈ Jcc2(x)
        @test comp_residual(mpcc, x) ≈ comp_res(x)
        @test comp_residual_product(mpcc, x) ≈ comp_res_prod(x)
        @test comp_residual_sum(mpcc, x) ≈ comp_res_sum(x)
    end

    @testset "Lifted VarCon API" for T in [Float64, Float32],
        M in [NLPModelMeta, SimpleNLPMeta]

        f(x) = (x[1] - 2)^2 + (x[2] - 1)^2
        ∇f(x) = T[2 * (x[1] - 2); 2 * (x[2] - 1); 0]
        H(x) = T[2.0 0 0; 0 2.0 0; 0 0 0]
        c(x) = T[x[1] - 2x[2] + 1; -x[1]^2 / 4 - x[2]^2 + 1 - x[3]]
        J(x) = T[1.0 -2.0 0; -0.5x[1] -2.0x[2] -1]
        H(x, y) = H(x) + y[2] * T[-0.5 0 0; 0 -2.0 0; 0 0 0]
        cc1(x) = T[x[1]]
        lcc1(x) = T[0.0]
        cc2(x) = T[x[3]]
        lcc2(x) = T[0.0]
        Jcc1(x) = T[1.0 0.0 0.0]
        Jcc2(x) = T[0.0 0.0 1.0]
        comp_res(x) = min(x[1], x[3])
        comp_res_prod(x) = x[1]*x[3]
        comp_res_sum(x) = x[1]*x[3]

        snlp = SimpleNLPModel(T, M)
        mpcc_varcon = MPCCModelVarCon(snlp, Int[1], Int[2])
        mpcc = vertical_form(mpcc_varcon)

        n = get_nvar(mpcc)
        m = get_ncon(mpcc)
        ncc = get_ncc(mpcc)
        @test n == 3
        @test m == 2
        @test ncc == 1

        x = randn(T, n)
        y = randn(T, m)
        v = randn(T, n)
        w = randn(T, m)
        Jv = zeros(T, m)
        Jtw = zeros(T, n)
        Hv = zeros(T, n)
        Hvals = zeros(T, get_nnzh(mpcc))


        # NLP api subset
        @test obj(mpcc, x) ≈ f(x)
        @test grad(mpcc, x) ≈ ∇f(x)
        @test hess(mpcc, x) ≈ H(x)
        @test cons(mpcc, x) ≈ c(x)
        @test jac(mpcc, x) ≈ J(x)
        @test hess(mpcc, x, y) ≈ H(x, y)
        # MPCC api
        @test comp_res_left(mpcc, x) ≈ comp_left(mpcc, x)
        @test comp_res_left(mpcc, x) ≈ cc1(x)
        @test comp_res_right(mpcc, x) ≈ comp_right(mpcc, x)
        @test comp_res_right(mpcc, x) ≈ cc2(x)
        @test jac_comp_left(mpcc, x) ≈ Jcc1(x)
        @test jac_comp_right(mpcc, x) ≈ Jcc2(x)
        @test comp_residual(mpcc, x) ≈ comp_res(x)
        @test comp_residual_product(mpcc, x) ≈ comp_res_prod(x)
        @test comp_residual_sum(mpcc, x) ≈ comp_res_sum(x)
    end
end
