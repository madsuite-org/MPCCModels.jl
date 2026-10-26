@testset "MPCCModel Tests" begin
    @testset "VarVar complementarity Jacobians with mixed constraints" for T in (
        Float64,
        Float32,
    )
        f(x) = sum(abs2, x)
        c(x) = [x[1]^2 + x[3]]
        nlp = ADNLPModel(
            f,
            ones(T, 3),
            zeros(T, 3),
            fill(T(Inf), 3),
            [1, 1],
            [1, 2],
            T[1, 2],
            c,
            T[0, 0],
            T[0, Inf],
        )
        mpcc = MPCCModel(nlp, [1], [3])
        x = get_x0(mpcc)
        @test get_lin_nnzj(nlp) != get_nnzj(nlp)
        @test jac_comp_left_structure(mpcc) == ([1], [1])
        @test jac_comp_right_structure(mpcc) == ([1], [3])
        @test jac_comp_left(mpcc, x) ≈ T[1 0 0]
        @test jac_comp_right(mpcc, x) ≈ T[0 0 1]
        linear = zeros(T, 1)
        nonlinear = zeros(T, 1)
        cons_lin!(mpcc, x, linear)
        cons_nln!(mpcc, x, nonlinear)
        @test linear ≈ cons(mpcc, x)[get_lin(mpcc)]
        @test nonlinear ≈ cons(mpcc, x)[get_nln(mpcc)]
        @test jac_lin(mpcc, x) ≈ jac(mpcc, x)[get_lin(mpcc), :]
        @test jac_nln(mpcc, x) ≈ jac(mpcc, x)[get_nln(mpcc), :]
        v = T[0.2, -0.4, 0.7]
        w = T[0.3]
        for (jv!, jtv!, J) in (
            (jprod_lin!, jtprod_lin!, jac_lin(mpcc, x)),
            (jprod_nln!, jtprod_nln!, jac_nln(mpcc, x)),
        )
            Jv = zeros(T, 1)
            Jtw = zeros(T, 3)
            @test jv!(mpcc, x, v, Jv) ≈ J * v
            @test jtv!(mpcc, x, w, Jtw) ≈ J' * w
        end
    end

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
