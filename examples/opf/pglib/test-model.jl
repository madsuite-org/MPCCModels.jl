# Model checks run in the optional PGLib environment; no optimizer is needed.
using Test, NLPModels, MPCCModels, PowerModels
include("transmission-opf.jl")
using .TransmissionOPF

function fd_jacobian(f, x; step = 1e-6)
    return hcat(map(eachindex(x)) do i
        xp, xm = copy(x), copy(x)
        xp[i] += step
        xm[i] -= step
        return (f(xp)-f(xm))/(2*step)
    end...)
end

@testset "Authoritative network overlays and joint curve targets" begin
    d = pglib_control_case(:ieee14)
    original = deepcopy(d.pm)
    changed = transmission_overlay(
        d;
        load_scale = 1.1,
        buses = [(id = 1, vmax = 1.07)],
        generators = [(id = 2, qmax = 0.31)],
        branches = [(id = 1, rate = 1.2, amax = 0.1)],
    )
    @test d.pm == original
    @test changed.pm !== d.pm
    @test isempty(changed.targets) && isempty(changed.network_targets)
    @test changed.buses[1].vmax == 1.07
    @test changed.generators[2].qmax == 0.31
    @test changed.branches[1].rate == 1.2
    @test changed.branches[1].amax == 0.1
    @test sum(b.pd for b in changed.buses) ≈ 1.1*sum(b.pd for b in d.buses)
    m = TransmissionOPFModel(changed)
    l = transmission_layout(changed)
    x = get_x0(m)
    balance, _ = TransmissionOPF._physical_balance(changed, x, l)
    @test cons(m, x)[l.balance_p] ≈ real.(balance) atol = 1e-12
    @test cons(m, x)[l.balance_q] ≈ imag.(balance) atol = 1e-12
    stale = copy(d.buses)
    stale[2] = merge(stale[2], (pd = stale[2].pd+0.1,))
    @test_throws ArgumentError TransmissionOPFModel(merge(d, (buses = stale,)))
    @test_throws ArgumentError transmission_overlay(d; buses = [(id = 1, vmin = 2.0)])
    @test_throws ArgumentError transmission_overlay(d; branches = [(id = 1, rate = -1.0)])
    @test_throws ArgumentError transmission_overlay(d; generators = [(id = 2, qmin = 1.0)])
    @test_throws ArgumentError transmission_overlay(d; buses = [(id = 1000, vmax = 1.1)])
    @test_throws ArgumentError transmission_overlay(d; load_scale = Inf)
    @test_throws ArgumentError transmission_overlay(
        d;
        branches = [(id = 1, rate = 1.0), (id = 1, rate = 2.0)],
    )
    # Both requested regions intersect the bus box separately, but VV asks for
    # v<=1.01 and VW for v>1.01015. Their shared-voltage intersection is empty.
    targets = copy(d.targets)
    targets[1] = merge(targets[1], (vv_region = :segment_2, vv_position = nothing))
    @test_throws ArgumentError TransmissionOPFModel(merge(d, (targets = targets,)))
    # Incompatible finite-fraction windows on otherwise identical ramp domains.
    targets[1] =
        merge(d.targets[1], (vv_position = (0.1, 0.15), vw_position = (0.01, 0.05)))
    @test_throws ArgumentError TransmissionOPFModel(merge(d, (targets = targets,)))
    no_vv = pglib_control_case(:ieee14; laws = :vw)
    targets = copy(no_vv.targets)
    targets[1] = merge(targets[1], (vv_position = (0.1, 0.2),))
    @test_throws ArgumentError TransmissionOPFModel(merge(no_vv, (targets = targets,)))
    @test_throws ArgumentError controller_population_case(d; copies = 0)
    @test_throws ArgumentError controller_placement_case(:ieee14; placement = :missing)
    @test_throws ArgumentError controller_placement_case(:ieee14; penetration = 0.0)
    # Quadratic costs must scale with population to preserve aggregate cost.
    parent = merge(d.controllers[1], (quadratic_cost = 2.0,))
    child = TransmissionOPF._scale_controller(parent, 0.25)
    p = 0.1
    @test 4*(child.cost*p/4+child.quadratic_cost*(p/4)^2/2) ≈
          parent.cost*p+parent.quadratic_cost*p^2/2
end

@testset "PGLib import and transmission physics" begin
    for (network, nb, ne, ng) in (
        (:ieee14, 14, 20, 5),
        (:ieee118, 118, 186, 54),
        (:ieee14_api, 14, 20, 5),
        (:ieee118_api, 118, 186, 54),
    )
        d = transmission_case(network)
        @test length(d.buses) == nb
        @test length(d.branches) == ne
        @test length(d.generators) == ng
        @test d.pm["per_unit"]
        @test d.base_mva == 100.0
        @test d.provenance.revision == TransmissionOPF.PGLIB_REVISION
        @test any(b -> b.bs != 0, d.buses)
        @test any(b -> b["tap"] != 1, values(d.pm["branch"]))
        l = transmission_layout(d)
        m = TransmissionOPFModel(d)
        @test !(m isa AbstractMPCCModel)
        @test get_nvar(m) == 2*nb+2*ng
        @test get_ncon(m) == 2*nb+3*ne
        @test get_lvar(m)[l.v[d.reference_bus]] < get_uvar(m)[l.v[d.reference_bus]]
        @test get_lvar(m)[l.theta[d.reference_bus]] ==
              get_uvar(m)[l.theta[d.reference_bus]] ==
              0
        # Non-flat point exercises angles, taps, charging, shunts and costs.
        x = copy(get_x0(m))
        x[l.v] .= 1 .+ 0.015 .* sin.(1:nb)
        x[l.theta] .= 0.02 .* cos.(1:nb)
        x[l.theta[d.reference_bus]] = 0
        for (i, b) in enumerate(d.buses)
            d.pm["bus"][string(b.id)]["vm"] = x[l.v[i]]
            d.pm["bus"][string(b.id)]["va"] = x[l.theta[i]]
        end
        pmflows = PowerModels.calc_branch_flow_ac(d.pm)["branch"]
        for (b, f) in zip(d.branches, transmission_flows(d, x))
            ref = pmflows[string(b.id)]
            @test collect(values(f)) ≈ [ref[k] for k in ("pf", "qf", "pt", "qt")] atol = 1e-12
        end
        balance, _ = TransmissionOPF._physical_balance(d, x, l)
        actual = cons(m, x)
        @test actual[l.balance_p] ≈ real.(balance) atol = 1e-12
        @test actual[l.balance_q] ≈ imag.(balance) atol = 1e-12
        no_targets = merge(d, (network_targets = [],))
        @test transmission_coverage(no_targets, x).targets_met === missing
    end
end

@testset "Transmission hinges, variants and derivatives" begin
    for laws in (:dispatchable, :vv, :vw, :both)
        d = pglib_control_case(:ieee14; laws = laws)
        d = transmission_overlay(
            d;
            generators = [(id = 1, c2 = 3.0)],
            targets = d.targets,
            network_targets = d.network_targets,
        )
        controllers = copy(d.controllers)
        controllers[1] = merge(controllers[1], (cost = 0.7, quadratic_cost = 0.2))
        d = merge(d, (controllers = controllers,))
        l = transmission_layout(d)
        m = TransmissionOPFModel(d)
        @test (m isa AbstractMPCCModel) == (laws != :dispatchable)
        @test length(l.r) == (laws == :both ? 18 : laws == :vv ? 12 : laws == :vw ? 6 : 0)
        @test length(l.r) == length(l.s)
        x = copy(get_x0(m))
        x[l.v] .= 1 .+ 0.01 .* sin.(1:14)
        x[l.theta] .= 0.03 .* cos.(1:14)
        for h in eachindex(l.knots)
            diff = x[l.v[d.controllers[l.devices[h]].bus]]-l.knots[h]
            x[l.r[h]], x[l.s[h]] = max(diff, 0), max(-diff, 0)
        end
        for (i, c) in enumerate(d.controllers)
            !isnothing(c.vv) &&
                (x[l.q[i]] = TransmissionOPF.BalancedACOPF.opf_volt_var(x[l.v[c.bus]], c))
            !isnothing(c.vw) && (
                x[l.p[i]] =
                    min(
                        c.p_available,
                        TransmissionOPF.BalancedACOPF.opf_volt_watt(x[l.v[c.bus]], c),
                    )/2
            )
        end
        residual = transmission_residuals(m, d, x)
        @test residual.volt_var < 1e-12
        @test residual.volt_watt == 0
        @test residual.complementarity == 0
        @test Matrix(jac(m, x)) ≈ fd_jacobian(z -> cons(m, z), x) atol = 1e-7 rtol = 1e-7
        @test grad(m, x) ≈ vec(fd_jacobian(z -> [obj(m, z)], x)) atol = 1e-6 rtol = 1e-7
        y = sin.(1:get_ncon(m))
        # NLP Hessian has ordinary constraints only; MPCC variable pairs are linear.
        nlp = m isa AbstractMPCCModel ? m.nlp : m
        h = Matrix(hess(nlp, x, y))
        @test h ≈ fd_jacobian(z -> grad(nlp, z)+jtprod(nlp, z, y), x) atol = 3e-6 rtol =
            1e-6
        @test_throws DimensionMismatch TransmissionOPFModel(d; x0 = zeros(2))
        @test_throws ArgumentError TransmissionOPFModel(d; x0 = fill(Inf, l.nvar))
        @test all(isinf, values(transmission_residuals(m, d, fill(NaN, l.nvar))))
    end
    @test_throws ArgumentError transmission_case(:missing)
    @test_throws ArgumentError pglib_control_case(:ieee14; laws = :missing)
    c = opf_controller(:invalid, 1000)
    @test_throws ArgumentError transmission_case(:ieee14; controllers = [c])
end

@testset "Nonzero phase shift and unequal end shunts" begin
    d = transmission_case(:ieee14)
    ids = Dict(b.id => i for (i, b) in enumerate(d.buses))
    raw = d.pm["branch"]["1"]
    raw["shift"], raw["tap"] = 0.13, 0.96
    raw["g_fr"], raw["g_to"] = 0.003, 0.005
    raw["b_fr"], raw["b_to"] = 0.02, 0.03
    branches = copy(d.branches)
    branches[1] = TransmissionOPF._branch_record(raw, ids)
    d = merge(d, (branches = branches,))
    l = transmission_layout(d)
    m = TransmissionOPFModel(d)
    x = copy(get_x0(m))
    x[l.theta[2]] = -0.04
    for (i, b) in enumerate(d.buses)
        d.pm["bus"][string(b.id)]["vm"] = x[l.v[i]]
        d.pm["bus"][string(b.id)]["va"] = x[l.theta[i]]
    end
    pmflows = PowerModels.calc_branch_flow_ac(d.pm)["branch"]
    for (b, f) in zip(d.branches, transmission_flows(d, x))
        r = pmflows[string(b.id)]
        @test collect(values(f)) ≈ [r[k] for k in ("pf", "qf", "pt", "qt")] atol = 1e-12
    end
    balance, _ = TransmissionOPF._physical_balance(d, x, l)
    @test cons(m, x)[l.balance_p] ≈ real.(balance) atol = 1e-12
    @test cons(m, x)[l.balance_q] ≈ imag.(balance) atol = 1e-12
end

@testset "Impossible or inconsistent targets" begin
    d = pglib_control_case(:ieee14)
    targets = copy(d.targets)
    targets[1] = merge(targets[1], (vv_region = :missing,))
    @test_throws ArgumentError TransmissionOPFModel(merge(d, (targets = targets,)))
    targets[1] = merge(d.targets[1], (vv_region = :below,))
    controllers = copy(d.controllers)
    controllers[1] = merge(controllers[1], (vv = opf_curve([0.8, 0.9], [0.1, 0.0]),))
    @test_throws ArgumentError TransmissionOPFModel(
        merge(d, (targets = targets, controllers = controllers)),
    )
    @test_throws ArgumentError TransmissionOPFModel(merge(d, (targets = [d.targets[1]],)))
    @test_throws ArgumentError TransmissionOPFModel(
        merge(d, (targets = [d.targets[1], d.targets[1], d.targets[3]],)),
    )
    @test_throws ArgumentError transmission_coverage(
        d,
        zeros(transmission_layout(d).nvar);
        tight_tol = 0,
    )
end
