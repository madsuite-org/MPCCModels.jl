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

    @testset "Nonvertical VarCon API" for T in [Float64, Float32],
        M in [NLPModelMeta, SimpleNLPMeta]

        nlp = SimpleNLPModel(T, M)
        get_ucon(nlp)[1] = T(Inf)
        mpcc = MPCCModelVarCon(nlp, Int[1], Int[1])
        x = T[-0.5, -0.25]
        y = T[0.7]

        c_lin(x) = T[x[1] - 2x[2] + 1]
        c_nln(x) = T[-x[1]^2 / 4 - x[2]^2 + 1]
        J_nln(x) = T[-0.5x[1] -2x[2]]
        H_obj = T[2 0; 0 2]
        H_nln = T[-0.5 0; 0 -2]

        @test !is_vertical(mpcc)
        @test get_ncon(mpcc) == 1
        @test get_nlin(mpcc) == 0
        @test get_nnln(mpcc) == 1
        @test get_lcon(mpcc) ≈ T[0]
        @test get_ucon(mpcc) ≈ T[Inf]

        @test cons(mpcc, x) ≈ c_nln(x)
        @test cons_lin(mpcc, x) ≈ T[]
        @test cons_nln(mpcc, x) ≈ c_nln(x)
        @test jac(mpcc, x) ≈ J_nln(x)
        @test jac_lin(mpcc, x) ≈ zeros(T, 0, 2)
        @test jac_nln(mpcc, x) ≈ J_nln(x)
        @test jac_structure(mpcc) == ([1, 1], [1, 2])
        @test jac_nln_coord(mpcc, x) ≈ J_nln(x)[:]

        nln_product = zeros(T, 2)
        jtprod_nln!(mpcc, x, T[1], nln_product)
        @test nln_product ≈ vec(J_nln(x))

        @test hess(mpcc, x) ≈ H_obj
        @test hess(mpcc, x, y) ≈ H_obj + y[1] * H_nln

        G(x) = T[x[1]]
        H(x) = c_lin(x)
        JG(x) = T[1 0]
        JH(x) = T[1 -2]
        @test comp_left(mpcc, x) ≈ G(x)
        @test comp_right(mpcc, x) ≈ H(x)
        @test comp_res_left(mpcc, x) ≈ G(x)
        @test comp_res_right(mpcc, x) ≈ H(x)
        @test jac_comp_left(mpcc, x) ≈ JG(x)
        @test jac_comp_right(mpcc, x) ≈ JH(x)
        @test comp_residual(mpcc, x) ≈ -0.5
        @test comp_residual_product(mpcc, x) ≈ -0.5
        @test comp_residual_sum(mpcc, x) ≈ -0.5

        # Keeping the linear row also exercises the linear-only API and its
        # compact row mapping when the nonlinear row is used for complementarity.
        mpcc_keep_linear = MPCCModelVarCon(nlp, Int[1], Int[2])
        J_lin(x) = T[1 -2]
        @test get_ncon(mpcc_keep_linear) == 1
        @test get_nlin(mpcc_keep_linear) == 1
        @test get_nnln(mpcc_keep_linear) == 0
        @test cons(mpcc_keep_linear, x) ≈ c_lin(x)
        @test cons_lin(mpcc_keep_linear, x) ≈ c_lin(x)
        @test cons_nln(mpcc_keep_linear, x) ≈ T[]
        @test jac(mpcc_keep_linear, x) ≈ J_lin(x)
        @test jac_lin(mpcc_keep_linear, x) ≈ J_lin(x)
        @test jac_nln(mpcc_keep_linear, x) ≈ zeros(T, 0, 2)
        @test comp_right(mpcc_keep_linear, x) ≈ c_nln(x)
        @test jac_comp_right(mpcc_keep_linear, x) ≈ J_nln(x)
    end

    @testset "Nonvertical ConCon API" for T in [Float64, Float32],
        M in [NLPModelMeta, SimpleNLPMeta]

        nlp = SimpleNLPModel(T, M)
        get_ucon(nlp)[1] = T(Inf)
        mpcc = MPCCModelConCon(nlp, Int[1], Int[2])
        x = T[0.5, 0.25]

        c_left(x) = T[x[1] - 2x[2] + 1]
        c_right(x) = T[-x[1]^2 / 4 - x[2]^2 + 1]
        J_left(x) = T[1 -2]
        J_right(x) = T[-0.5x[1] -2x[2]]

        @test !is_vertical(mpcc)
        @test get_ncon(mpcc) == 0
        @test get_nlin(mpcc) == 0
        @test get_nnln(mpcc) == 0
        @test get_lcon(mpcc) ≈ T[]
        @test get_ucon(mpcc) ≈ T[]

        @test cons(mpcc, x) ≈ T[]
        @test cons_lin(mpcc, x) ≈ T[]
        @test cons_nln(mpcc, x) ≈ T[]
        @test jac(mpcc, x) ≈ zeros(T, 0, 2)
        @test jac_lin(mpcc, x) ≈ zeros(T, 0, 2)
        @test jac_nln(mpcc, x) ≈ zeros(T, 0, 2)

        @test comp_left(mpcc, x) ≈ c_left(x)
        @test comp_right(mpcc, x) ≈ c_right(x)
        @test comp_res_left(mpcc, x) ≈ c_left(x)
        @test comp_res_right(mpcc, x) ≈ c_right(x)
        @test jac_comp_left(mpcc, x) ≈ J_left(x)
        @test jac_comp_right(mpcc, x) ≈ J_right(x)
        @test jac_comp_left_structure(mpcc) == ([1, 1], [1, 2])
        @test jac_comp_right_structure(mpcc) == ([1, 1], [1, 2])
        @test jac_comp_left_coord(mpcc, x) ≈ vec(J_left(x))
        @test jac_comp_right_coord(mpcc, x) ≈ vec(J_right(x))
        @test comp_residual(mpcc, x) ≈ c_right(x)[1]
        @test comp_residual_product(mpcc, x) ≈ c_left(x)[1] * c_right(x)[1]
        @test comp_residual_sum(mpcc, x) ≈ c_left(x)[1] * c_right(x)[1]
        @test hess(mpcc, x, T[]) ≈ T[2 0; 0 2]
    end
end
