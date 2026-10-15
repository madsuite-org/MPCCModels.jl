@testset "MPCCModel Tests" begin
    @testset "VarVar API" for T in [Float64, Float32],
        M in [NLPModelMeta, SimpleNLPMeta]

        nlp = SimpleNLPModel(T, M)
        mpcc = MPCCModel(nlp, Int[1], Int[2])
        @test is_vertical(mpcc)

        n = get_nvar(mpcc)
        m = get_ncon(mpcc)
        @test n == 2
        @test m == 2
        @test get_nlin(mpcc) == 1
        @test get_nnln(mpcc) == 1
        @test get_ncc(mpcc) == 1

        @test get_lvar(mpcc) ≈ T[0.0, 0.0]
        @test get_uvar(mpcc) ≈ T[1.0, 1.0]
        @test get_lcon(mpcc) ≈ T[0.0, 0.0]
        @test get_ucon(mpcc) ≈ T[0.0, Inf]

        f(x) = (x[1] - 2)^2 + (x[2] - 1)^2
        ∇f(x) = T[2 * (x[1] - 2); 2 * (x[2] - 1)]
        H(x) = T[2.0 0; 0 2.0]
        c(x) = T[x[1] - 2 * x[2] + 1; -x[1]^2 / 4 - x[2]^2 + 1]
        J(x) = T[1 -2; -x[1] / 2 -2 * x[2]]
        H(x, y) = H(x) + y[2] * [-1/2 0; 0 -2]
        cc1(x) = T[x[1]]
        lcc1(x) = T[0.0]
        cc2(x) = T[x[2]]
        lcc2(x) = T[0.0]
        Jcc1(x) = T[1.0 0.0]
        Jcc2(x) = T[0.0 1.0]
        comp_res(x) = abs(min(x[1], x[2], 0.0))
        comp_res_prod(x) = abs(x[1] * x[2])
        comp_res_sum(x) = x[1] * x[2]

        x = randn(T, n)
        y = randn(T, m)
        v = randn(T, n)
        w = randn(T, m)

        # NLP api
        @test obj(mpcc, x) ≈ f(x)
        @test grad(mpcc, x) ≈ ∇f(x)
        @test hess(mpcc, x) ≈ H(x)
        @test cons(mpcc, x) ≈ c(x)
        @test cons_lin(mpcc, x) ≈ c(x)[1:1]
        @test cons_nln(mpcc, x) ≈ c(x)[2:2]
        @test jac(mpcc, x) ≈ J(x)
        @test jac_lin(mpcc, x) ≈ J(x)[1:1, :]
        @test jac_nln(mpcc, x) ≈ J(x)[2:2, :]
        @test jprod(mpcc, x, v) ≈ J(x) * v
        @test jprod_lin(mpcc, x, v) ≈ J(x)[1:1, :] * v
        @test jprod_nln(mpcc, x, v) ≈ J(x)[2:2, :] * v
        @test jtprod(mpcc, x, w) ≈ J(x)' * w
        @test jtprod_lin(mpcc, x, w[1:1]) ≈ J(x)[1:1, :]' * w[1:1]
        @test jtprod_nln(mpcc, x, w[2:2]) ≈ J(x)[2:2, :]' * w[2:2]
        @test hess(mpcc, x, y) ≈ H(x, y)
        @test hprod(mpcc, x, y, v) ≈ H(x, y) * v
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

    @testset "VarCon API" for T in [Float64, Float32],
        M in [NLPModelMeta, SimpleNLPMeta]

        nlp = SimpleNLPModel(T, M)
        mpcc = MPCCModelVarCon(nlp, Int[1], Int[2])
        @test !is_vertical(mpcc)

        n = get_nvar(mpcc)
        m = get_ncon(mpcc)
        @test n == 2
        @test m == 1
        @test get_nlin(mpcc) == 1
        @test get_nnln(mpcc) == 0
        @test get_ncc(mpcc) == 1

        @test get_lvar(mpcc) ≈ T[0.0, 0.0]
        @test get_uvar(mpcc) ≈ T[1.0, 1.0]
        @test get_lcon(mpcc) ≈ T[0.0]
        @test get_ucon(mpcc) ≈ T[0.0]

        f(x) = (x[1] - 2)^2 + (x[2] - 1)^2
        ∇f(x) = T[2 * (x[1] - 2); 2 * (x[2] - 1)]
        H(x) = T[2.0 0; 0 2.0]
        c(x) = T[x[1] - 2 * x[2] + 1]
        J(x) = T[1 -2]
        H(x, y) = H(x)
        cc1(x) = T[x[1]]
        lcc1(x) = T[0.0]
        cc2(x) = T[-x[1]^2 / 4 - x[2]^2 + 1]
        lcc2(x) = T[0.0]
        Jcc1(x) = T[1.0 0.0]
        Jcc2(x) = T[-x[1]/2 -2*x[2]]
        comp_res(x) = abs.(min.(cc1(x), cc2(x), 0.0))[1]
        comp_res_prod(x) = abs.(cc1(x) .* cc2(x))[1]
        comp_res_sum(x) = sum(cc1(x) .* cc2(x))

        x = randn(T, n)
        y = randn(T, m)
        v = randn(T, n)
        w = randn(T, m)

        # NLP api
        @test obj(mpcc, x) ≈ f(x)
        @test grad(mpcc, x) ≈ ∇f(x)
        @test hess(mpcc, x) ≈ H(x)
        @test cons(mpcc, x) ≈ c(x)
        @test cons_lin(mpcc, x) ≈ c(x)[1:1]
        @test cons_nln(mpcc, x) ≈ Array{T}(undef, 0)
        @test jac(mpcc, x) ≈ J(x)
        @test jac_lin(mpcc, x) ≈ J(x)[1:1, :]
        @test jac_nln(mpcc, x) ≈ Array{T}(undef, 0, n)
        @test jprod(mpcc, x, v) ≈ J(x) * v
        @test jprod_lin(mpcc, x, v) ≈ J(x)[1:1, :] * v
        @test jprod_nln(mpcc, x, v) ≈ Array{T}(undef, 0, n) * v
        @test jtprod(mpcc, x, w) ≈ J(x)' * w
        @test jtprod_lin(mpcc, x, w[1:1]) ≈ J(x)[1:1, :]' * w[1:1]
        @test jtprod_nln(mpcc, x, Array{T}(undef, 0)) ≈ zeros(T, n)
        @test hess(mpcc, x, y) ≈ H(x, y)
        @test hprod(mpcc, x, y, v) ≈ H(x, y) * v
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

    @testset "ConCon API" for T in [Float64, Float32],
        M in [NLPModelMeta, SimpleNLPMeta]

        nlp = SimpleNLPModel(T, M)
        get_ucon(nlp)[1] = T(Inf)
        mpcc = MPCCModelConCon(nlp, Int[1], Int[2])
        @test !is_vertical(mpcc)

        n = get_nvar(mpcc)
        m = get_ncon(mpcc)
        @test n == 2
        @test m == 0
        @test get_nlin(mpcc) == 0
        @test get_nnln(mpcc) == 0
        @test get_ncc(mpcc) == 1

        @test get_lvar(mpcc) ≈ T[0.0, 0.0]
        @test get_uvar(mpcc) ≈ T[1.0, 1.0]
        @test get_lcon(mpcc) ≈ T[]
        @test get_ucon(mpcc) ≈ T[]

        f(x) = (x[1] - 2)^2 + (x[2] - 1)^2
        ∇f(x) = T[2 * (x[1] - 2); 2 * (x[2] - 1)]
        H(x) = T[2.0 0; 0 2.0]
        c(x) = Array{T}(undef, m)
        J(x) = Array{T}(undef, m, n)
        H(x, y) = H(x)
        cc1(x) = T[x[1] - 2 * x[2] + 1]
        lcc1(x) = T[0.0]
        cc2(x) = T[-x[1]^2 / 4 - x[2]^2 + 1]
        lcc2(x) = T[0.0]
        Jcc1(x) = T[1 -2]
        Jcc2(x) = T[-x[1]/2 -2*x[2]]
        comp_res(x) = abs.(min.(cc1(x), cc2(x), 0.0))[1]
        comp_res_prod(x) = abs.(cc1(x) .* cc2(x))[1]
        comp_res_sum(x) = sum(cc1(x) .* cc2(x))

        x = randn(T, n)
        y = randn(T, m)
        v = randn(T, n)
        w = randn(T, m)

        # NLP api
        @test obj(mpcc, x) ≈ f(x)
        @test grad(mpcc, x) ≈ ∇f(x)
        @test hess(mpcc, x) ≈ H(x)
        @test cons(mpcc, x) ≈ c(x)
        @test cons_lin(mpcc, x) ≈ Array{T}(undef, 0)
        @test cons_nln(mpcc, x) ≈ Array{T}(undef, 0)
        @test jac(mpcc, x) ≈ J(x)
        @test jac_lin(mpcc, x) ≈ Array{T}(undef, 0, n)
        @test jac_nln(mpcc, x) ≈ Array{T}(undef, 0, n)
        @test jprod(mpcc, x, v) ≈ J(x) * v
        @test jprod_lin(mpcc, x, v) ≈ Array{T}(undef, 0, n) * v
        @test jprod_nln(mpcc, x, v) ≈ Array{T}(undef, 0, n) * v
        @test jtprod(mpcc, x, w) ≈ J(x)' * w
        @test jtprod_lin(mpcc, x, Array{T}(undef, 0)) ≈ zeros(T, n)
        @test jtprod_nln(mpcc, x, Array{T}(undef, 0)) ≈ zeros(T, n)
        @test hess(mpcc, x, y) ≈ H(x, y)
        @test hprod(mpcc, x, y, v) ≈ H(x, y) * v
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

        nlp = SimpleNLPModel(T, M)
        mpcc = MPCCModelVarCon(nlp, Int[1], Int[2])
        @test !is_vertical(mpcc)
        mpcc = vertical_form(mpcc)
        @test is_vertical(mpcc)

        n = get_nvar(mpcc)
        m = get_ncon(mpcc)
        @test n == 3
        @test m == 2
        @test get_nlin(mpcc) == 1
        @test get_nnln(mpcc) == 1
        @test get_ncc(mpcc) == 1

        @test get_lvar(mpcc) ≈ T[0.0, 0.0, 0.0]
        @test get_uvar(mpcc) ≈ T[1.0, 1.0, Inf]
        @test get_lcon(mpcc) ≈ T[0.0, 0.0]
        @test get_ucon(mpcc) ≈ T[0.0, 0.0]

        f(x) = (x[1] - 2)^2 + (x[2] - 1)^2
        ∇f(x) = T[2 * (x[1] - 2); 2 * (x[2] - 1); 0]
        H(x) = T[2 0 0; 0 2 0; 0 0 0]
        c(x) = T[x[1] - 2 * x[2] + 1; -x[1]^2 / 4 - x[2]^2 + 1 - x[3]]
        J(x) = T[1 -2 0; -x[1]/2 -2*x[2] -1]
        H(x, y) = H(x) + y[2] * [-1/2 0 0; 0 -2 0; 0 0 0]
        cc1(x) = T[x[1]]
        lcc1(x) = T[0.0]
        cc2(x) = T[x[3]]
        lcc2(x) = T[0.0]
        Jcc1(x) = T[1 0 0]
        Jcc2(x) = T[0 0 1]
        comp_res(x) = abs(min(x[1], x[3], 0.0))
        comp_res_prod(x) = abs(x[1] * x[3])
        comp_res_sum(x) = x[1] * x[3]

        x = randn(T, n)
        y = randn(T, m)
        v = randn(T, n)
        w = randn(T, m)

        # NLP api
        @test obj(mpcc, x) ≈ f(x)
        @test grad(mpcc, x) ≈ ∇f(x)
        @test hess(mpcc, x) ≈ H(x)
        @test cons(mpcc, x) ≈ c(x)
        @test cons_lin(mpcc, x) ≈ c(x)[1:1]
        @test cons_nln(mpcc, x) ≈ c(x)[2:2]
        @test jac(mpcc, x) ≈ J(x)
        @test jac_lin(mpcc, x) ≈ J(x)[1:1, :]
        @test jac_nln(mpcc, x) ≈ J(x)[2:2, :]
        @test jprod(mpcc, x, v) ≈ J(x) * v
        @test jprod_lin(mpcc, x, v) ≈ J(x)[1:1, :] * v
        @test jprod_nln(mpcc, x, v) ≈ J(x)[2:2, :] * v
        @test jtprod(mpcc, x, w) ≈ J(x)' * w
        @test jtprod_lin(mpcc, x, w[1:1]) ≈ J(x)[1:1, :]' * w[1:1]
        @test jtprod_nln(mpcc, x, w[2:2]) ≈ J(x)[2:2, :]' * w[2:2]
        @test hess(mpcc, x, y) ≈ H(x, y)
        @test hprod(mpcc, x, y, v) ≈ H(x, y) * v
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

    @testset "Lifted ConCon API" for T in [Float64, Float32],
        M in [NLPModelMeta, SimpleNLPMeta]

        nlp = SimpleNLPModel(T, M)
        get_ucon(nlp)[1] = T(Inf)
        mpcc = MPCCModelConCon(nlp, Int[1], Int[2])
        @test !is_vertical(mpcc)
        mpcc = vertical_form(mpcc)
        @test is_vertical(mpcc)

        n = get_nvar(mpcc)
        m = get_ncon(mpcc)
        @test n == 4
        @test m == 2
        @test get_nlin(mpcc) == 1
        @test get_nnln(mpcc) == 1
        @test get_ncc(mpcc) == 1

        @test get_lvar(mpcc) ≈ T[0.0, 0.0, 0.0, 0.0]
        @test get_uvar(mpcc) ≈ T[1.0, 1.0, Inf, Inf]
        @test get_lcon(mpcc) ≈ T[0.0, 0.0]
        @test get_ucon(mpcc) ≈ T[0.0, 0.0]

        f(x) = (x[1] - 2)^2 + (x[2] - 1)^2
        ∇f(x) = T[2 * (x[1] - 2); 2 * (x[2] - 1); 0; 0]
        H(x) = T[2 0 0 0; 0 2 0 0; 0 0 0 0; 0 0 0 0]
        c(x) = T[x[1] - 2 * x[2] + 1 - x[3]; -x[1]^2 / 4 - x[2]^2 + 1 - x[4]]
        J(x) = T[1 -2 -1 0; -x[1]/2 -2*x[2] 0 -1]
        H(x, y) = H(x) + y[2] * [-1/2 0 0 0; 0 -2 0 0; 0 0 0 0; 0 0 0 0]
        cc1(x) = T[x[3]]
        lcc1(x) = T[0.0]
        cc2(x) = T[x[4]]
        lcc2(x) = T[0.0]
        Jcc1(x) = T[0 0 1 0]
        Jcc2(x) = T[0 0 0 1]
        comp_res(x) = abs(min(x[3], x[4], 0.0))
        comp_res_prod(x) = abs(x[3] * x[4])
        comp_res_sum(x) = x[3] * x[4]

        x = randn(T, n)
        y = randn(T, m)
        v = randn(T, n)
        w = randn(T, m)

        # NLP api
        @test obj(mpcc, x) ≈ f(x)
        @test grad(mpcc, x) ≈ ∇f(x)
        @test hess(mpcc, x) ≈ H(x)
        @test cons(mpcc, x) ≈ c(x)
        @test cons_lin(mpcc, x) ≈ c(x)[1:1]
        @test cons_nln(mpcc, x) ≈ c(x)[2:2]
        @test jac(mpcc, x) ≈ J(x)
        @test jac_lin(mpcc, x) ≈ J(x)[1:1, :]
        @test jac_nln(mpcc, x) ≈ J(x)[2:2, :]
        @test jprod(mpcc, x, v) ≈ J(x) * v
        @test jprod_lin(mpcc, x, v) ≈ J(x)[1:1, :] * v
        @test jprod_nln(mpcc, x, v) ≈ J(x)[2:2, :] * v
        @test jtprod(mpcc, x, w) ≈ J(x)' * w
        @test jtprod_lin(mpcc, x, w[1:1]) ≈ J(x)[1:1, :]' * w[1:1]
        @test jtprod_nln(mpcc, x, w[2:2]) ≈ J(x)[2:2, :]' * w[2:2]
        @test hess(mpcc, x, y) ≈ H(x, y)
        @test hprod(mpcc, x, y, v) ≈ H(x, y) * v
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
