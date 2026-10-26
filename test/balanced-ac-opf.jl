include(joinpath(@__DIR__, "..", "examples", "opf", "balanced-ac-opf.jl"))
using .BalancedACOPF

# Independent complex-voltage calculation, including every branch and device.
function opf_test_powers(data, x)
    l = opf_layout(data)
    v = [
        i == data.source.bus ? complex(data.source.voltage) :
        x[l.v[i]] * cis(x[l.theta[i]]) for i in eachindex(data.buses)
    ]
    injections = zeros(eltype(v), length(v))
    flows = map(data.branches) do b
        current = (v[b.from] - v[b.to]) / complex(b.resistance, b.reactance)
        sf, st = v[b.from] * conj(current), -v[b.to] * conj(current)
        injections[b.from] += sf
        injections[b.to] += st
        return (from = sf, to = st, current = current)
    end
    return injections, flows
end

function opf_test_jacobian(f, x; step = 1e-5)
    columns = map(eachindex(x)) do i
        xp, xm = copy(x), copy(x)
        xp[i] += step
        xm[i] -= step
        return (f(xp) - f(xm)) / (2 * step)
    end
    return hcat(columns...)
end

function opf_test_balance(data, x)
    l = opf_layout(data)
    injections, flows = opf_test_powers(data, x)
    net = [-complex(b.pload, b.qload) for b in data.buses]
    net[data.source.bus] += complex(x[l.pg], x[l.qg])
    for (i, c) in enumerate(data.controllers)
        net[c.bus] += complex(x[l.p[i]], x[l.q[i]])
    end
    return net - injections, flows
end

function opf_test_reverse_devices(data)
    return merge(
        data,
        (
            controllers = reverse(data.controllers),
            reference = merge(
                data.reference,
                (p = reverse(data.reference.p), q = reverse(data.reference.q)),
            ),
        ),
    )
end

function opf_test_relabel(data, order)
    inverse = invperm(order)
    return merge(
        data,
        (
            buses = data.buses[order],
            source = merge(data.source, (bus = inverse[data.source.bus],)),
            branches = [
                merge(b, (from = inverse[b.from], to = inverse[b.to])) for
                b in data.branches
            ],
            controllers = [merge(c, (bus = inverse[c.bus],)) for c in data.controllers],
            reference = merge(
                data.reference,
                (
                    voltage = data.reference.voltage[order],
                    angle = data.reference.angle[order],
                ),
            ),
        ),
    )
end

@testset "Balanced AC OPF" begin
    @testset "Network references ($T)" for T in (Float64, Float32)
        tol = T == Float64 ? 1e-11 : 2e-5
        names = balanced_ac_opf_cases()
        @test length(names) == length(unique(names)) == 37
        for name in names
            data = balanced_ac_opf_case(name, T)
            l = opf_layout(data)
            model = BalancedACOPFModel(data)
            x = balanced_ac_opf_reference(data)
            nc, nb, ne = length(data.controllers), length(data.buses), length(data.branches)
            @test eltype(x) == T
            @test get_ncc(model) == 6 * nc
            @test get_nvar(model) == 2*(nb-1) + 2 + 2*nc + 12*nc
            @test get_nlin(model) == 8 * nc
            @test get_ncon(model) == 8*nc + 2*nb + nc + 2*ne
            @test is_vertical(model)
            @test get_ind_cc1(model) == l.r
            @test get_ind_cc2(model) == l.s
            @test all(get_lvar(model)[[l.r; l.s]] .== 0)
            @test maximum(values(opf_residuals(model, x, data))) < tol
            @test comp_residual_product(model, x) == 0
            @test opf_coverage(data, x).targets_met === true
            @test get_x0(model) != x
            @test all(get_lvar(model) .<= get_x0(model) .<= get_uvar(model))
            balance, flows = opf_test_balance(data, x)
            @test maximum(abs.(balance)) < tol
            for (b, f) in zip(data.branches, flows)
                @test real(f.from + f.to) ≈ b.resistance * abs2(f.current) atol = tol
                @test imag(f.from + f.to) ≈ b.reactance * abs2(f.current) atol = tol
            end
            @test all(b -> b.pload >= 0 && b.qload >= 0, data.buses)
            if nc == 1
                @test l.r == collect(7:12)
                @test l.s == collect(13:18)
                @test (get_nvar(model), get_ncon(model)) == (18, 15)
            end
        end
    end

    @testset "Explicit regime and position coverage" begin
        for (name, v, p, q) in (
            (:low_voltage_saturation, 0.92, 0.8, 0.3),
            (:reactive_injection, 0.96, 0.8, 0.15),
            (:deadband, 1.0, 0.8, 0.0),
            (:reactive_absorption, 1.04, 0.8, -0.15),
            (:curtailment, 1.09, 0.68, -0.3),
            (:high_voltage_saturation, 1.14, 0.2, -0.3),
            (:saturated_var_flat_watt, 1.065, 0.8, -0.3),
            (:early_watt_ramp, 1.07625, 0.8, -0.3),
            (:availability_watt_crossover, 1.0825, 0.8, -0.3),
        )
            data = balanced_ac_opf_case(name)
            l = opf_layout(data)
            x = balanced_ac_opf_reference(data)
            @test x[l.v[2]] ≈ v
            @test only(x[l.p]) ≈ p
            @test only(x[l.q]) ≈ q atol = 1e-13
        end
        for (name, law, fraction) in (
            (:vv_injection_20, :volt_var, 0.2),
            (:reactive_injection, :volt_var, 0.5),
            (:vv_injection_80, :volt_var, 0.8),
            (:vv_absorption_20, :volt_var, 0.2),
            (:reactive_absorption, :volt_var, 0.5),
            (:vv_absorption_80, :volt_var, 0.8),
            (:vw_ramp_20, :volt_watt, 0.2),
            (:vw_ramp_50, :volt_watt, 0.5),
            (:vw_ramp_80, :volt_watt, 0.8),
        )
            data = balanced_ac_opf_case(name)
            report = only(opf_coverage(data, balanced_ac_opf_reference(data)).controllers)
            @test getproperty(report, law).fraction ≈ fraction
        end
        for (name, law, knot) in (
            (:vv_lower_knee, :vv, 1),
            (:vv_deadband_lower, :vv, 2),
            (:vv_deadband_upper, :vv, 3),
            (:vv_upper_knee, :vv, 4),
            (:vw_upper_knee, :vw, 1),
            (:vw_lower_knee, :vw, 2),
        )
            data = balanced_ac_opf_case(name)
            l = opf_layout(data)
            x = balanced_ac_opf_reference(data)
            pairs = law == :vv ? l.vv_pairs[1] : l.vw_pairs[1]
            @test x[l.r[pairs[knot]]] == x[l.s[pairs[knot]]] == 0
            @test x[l.v[2]] == getproperty(only(data.controllers), law).knots[knot]
        end
    end

    @testset "Generic curves and disabled control blocks" begin
        data = balanced_ac_opf_case(:curtailment)
        controller = merge(
            only(data.controllers),
            (
                vv = opf_curve([0.93, 1.0, 1.08], [0.2, 0, -0.1]),
                vw = opf_curve([0.95, 1.01, 1.09, 1.15], [1, 0.9, 0.4, 0.2]),
            ),
        )
        data = merge(data, (controllers = [controller], targets = nothing))
        l = opf_layout(data)
        model = BalancedACOPFModel(data)
        @test get_ncc(model) == 7
        knots = l.knots
        for v in [0.9; knots; knots .- 1e-5; knots .+ 1e-5; 1.18]
            x = copy(get_x0(model))
            x[l.v[2]] = v
            x[l.p[1]], x[l.q[1]] = opf_volt_watt(v, controller), opf_volt_var(v, controller)
            x[l.r] .= max.(v .- knots, 0)
            x[l.s] .= max.(knots .- v, 0)
            c = cons(model, x)
            @test c[1:length(knots)] ≈ -knots
            @test c[l.vv_rows[1]] ≈ first(controller.vv.values) atol = 1e-13
            @test c[l.vw_rows[1]] ≈ first(controller.vw.values) atol = 1e-13
            @test comp_residual(model, x) == 0
        end
        data = balanced_ac_opf_case(:colocated_controllers)
        controllers = [
            merge(data.controllers[1], (vw = nothing,)),
            merge(data.controllers[2], (vv = nothing,)),
        ]
        data = merge(data, (controllers = controllers, targets = nothing))
        l = opf_layout(data)
        model = BalancedACOPFModel(data)
        x = balanced_ac_opf_reference(data)
        @test get_ncc(model) == 4 + 2
        @test l.vw_rows[1] == l.vv_rows[2] == 0
        @test maximum(values(opf_residuals(model, x, data))) < 1e-11
        report = opf_coverage(data, x)
        @test ismissing(report.targets_met)
        @test report.controllers[1].volt_watt.region == :disabled
        @test report.controllers[2].volt_var.region == :disabled
        @test isnothing(opf_volt_watt(1.0, controllers[1]))
        @test isnothing(opf_volt_var(1.0, controllers[2]))
        # A flat curve keeps its knots/pairs even when every hinge weight is zero.
        original = balanced_ac_opf_case(:deadband)
        flat =
            merge(only(original.controllers), (vv = opf_curve([0.94, 1.06], [0.1, 0.1]),))
        changed = merge(original, (controllers = [flat], targets = nothing))
        layout = opf_layout(changed)
        model = BalancedACOPFModel(changed)
        @test get_ncc(model) == 4
        @test layout.vv_pairs[1] == [1, 2]
        for v in (0.9, 1.0, 1.15)
            point = copy(get_x0(model))
            point[layout.v[2]], point[layout.q[1]] = v, 0.1
            point[layout.r] .= max.(v .- layout.knots, 0)
            point[layout.s] .= max.(layout.knots .- v, 0)
            @test cons(model, point)[layout.vv_rows[1]] ≈ 0.1
        end
    end

    @testset "Device aggregation, permutation and bus relabeling" begin
        for name in
            (:fork_mixed_reactive, :chain_remote_curtailment, :colocated_controllers)
            data = balanced_ac_opf_case(name)
            original = balanced_ac_opf_reference(data)
            original_obj = obj(BalancedACOPFModel(data), original)
            for changed in (
                opf_test_reverse_devices(data),
                opf_test_relabel(data, reverse(collect(eachindex(data.buses)))),
            )
                x = balanced_ac_opf_reference(changed)
                @test maximum(
                    values(opf_residuals(BalancedACOPFModel(changed), x, changed)),
                ) < 1e-11
                @test obj(BalancedACOPFModel(changed), x) ≈ original_obj
                report = opf_coverage(changed, x)
                @test report.targets_met === true
                for device in report.controllers
                    old = only(
                        r for r in opf_coverage(data, original).controllers if
                        r.id == device.id
                    )
                    @test device.p ≈ old.p
                    @test device.q ≈ old.q
                    @test device.volt_var == old.volt_var
                end
            end
        end
        # Heterogeneous knot counts catch offset mistakes hidden by identical curves.
        data = balanced_ac_opf_case(:fork_mixed_reactive)
        controllers = [
            merge(
                data.controllers[1],
                (vw = nothing, vv = opf_curve([0.92, 0.96, 1.0], [0.3, 0.15, 0])),
            ),
            data.controllers[2],
        ]
        data = merge(data, (controllers = controllers, targets = nothing))
        for changed in (data, opf_test_reverse_devices(data))
            x = balanced_ac_opf_reference(changed)
            model = BalancedACOPFModel(changed)
            @test get_ncc(model) == 3 + 6
            @test maximum(values(opf_residuals(model, x, changed))) < 1e-11
        end
        # A controller can be attached to the fixed-voltage source as well.
        data = balanced_ac_opf_case(:colocated_controllers)
        c = opf_controller(:at_source, data.source.bus)
        q = opf_volt_var(data.source.voltage, c)
        data = merge(
            data,
            (
                controllers = [data.controllers; c],
                targets = nothing,
                reference = merge(
                    data.reference,
                    (p = [data.reference.p; 0.2], q = [data.reference.q; q]),
                ),
            ),
        )
        model = BalancedACOPFModel(data)
        x = balanced_ac_opf_reference(data)
        @test get_ncc(model) == 18
        @test maximum(values(opf_residuals(model, x, data))) < 1e-11
    end

    @testset "Coverage rejects missed targets independently of feasibility" begin
        data = balanced_ac_opf_case(:curtailment)
        l = opf_layout(data)
        model = BalancedACOPFModel(data)
        x = balanced_ac_opf_reference(data)
        wrong = merge(data, (targets = [merge(only(data.targets), (vv_region = :below,))],))
        @test maximum(values(opf_residuals(model, x, wrong))) < 1e-11
        @test opf_coverage(wrong, x).targets_met === false
        # Coverage must not inspect reference values.
        @test opf_coverage(merge(data, (reference = nothing,)), x).targets_met === true

        # Another feasible high-voltage dispatch is strictly below the VW cap.
        b, bus = only(data.branches), data.buses[2]
        p, q = 0.3, -0.3
        pnet, qnet = p - bus.pload, q - bus.qload
        a = data.source.voltage^2 + 2*(b.resistance*pnet + b.reactance*qnet)
        d = (b.resistance^2+b.reactance^2)*(pnet^2+qnet^2)
        v = sqrt((a + sqrt(a^2 - 4*d))/2)
        v0 = v - complex(b.resistance, b.reactance)*complex(pnet, -qnet)/v
        x[l.v[2]], x[l.theta[2]] = v, -angle(v0)
        injections, _ = opf_test_powers(data, x)
        x[l.pg], x[l.qg] = real(injections[1]), imag(injections[1])
        x[l.p[1]], x[l.q[1]] = p, q
        x[l.r] .= max.(v .- l.knots, 0)
        x[l.s] .= max.(l.knots .- v, 0)
        @test maximum(values(opf_residuals(model, x, data))) < 1e-11
        report = opf_coverage(data, x)
        @test report.targets_met === false
        @test only(report.controllers).slacks.volt_watt > 0.1
        @test "tight volt_watt" in only(report.controllers).misses
        @test cons(model, x)[l.vw_rows[1]] < get_ucon(model)[l.vw_rows[1]] - 0.1
    end

    @testset "Physical violations and malformed inputs" begin
        data = balanced_ac_opf_case(:curtailment)
        l = opf_layout(data)
        model = BalancedACOPFModel(data)
        reference = balanced_ac_opf_reference(data)
        x = copy(reference)
        x[l.pg] += 0.1
        @test opf_residuals(model, x, data).constraints ≈ 0.1
        @test comp_residual(model, x) == 0
        x = copy(reference)
        x[l.p[1]] = 1.1
        @test cons(model, x)[l.capability[1]] > get_ucon(model)[l.capability[1]]
        @test opf_residuals(model, x, data).bounds > 0
        @test opf_residuals(model, x, data).volt_watt > 0
        x = copy(reference)
        x[l.v[2]] = 0.9
        @test any(
            cons(model, x)[[l.branch_from; l.branch_to]] .>
            get_ucon(model)[[l.branch_from; l.branch_to]],
        )
        x = copy(reference)
        h = first(l.vv_pairs[1])
        x[l.r[h]] += 0.002
        x[l.s[h]] += 0.002
        x[l.q[1]] -= 0.3 / 0.04 * 0.002
        @test cons(model, x)[[collect(1:length(l.r)); l.vv_rows]] ≈
              get_ucon(model)[[collect(1:length(l.r)); l.vv_rows]]
        @test opf_residuals(model, x, data).complementarity ≈ 0.002
        @test opf_residuals(model, x, data).volt_var ≈ 0.015
        x = copy(reference)
        x[last(l.r)] = -1e-4
        @test opf_residuals(model, x, data).bounds ≈ 1e-4
        for value in (NaN, Inf)
            x = copy(reference)
            x[1] = value
            @test all(isinf, values(opf_residuals(model, x, data)))
            @test opf_coverage(data, x).targets_met === false
        end
        @test_throws ArgumentError balanced_ac_opf_case(:unknown)
        @test_throws DimensionMismatch BalancedACOPFModel(data; x0 = zeros(17))
        @test_throws ArgumentError BalancedACOPFModel(data; x0 = fill(NaN, l.nvar))
        @test_throws ArgumentError BalancedACOPFModel(Float32; x0 = fill(1e40, 18))
        @test get_x0(BalancedACOPFModel(data; x0 = reference)) == reference
        @test get_x0(BalancedACOPFModel(data; x0 = reference)) !== reference
        @test_throws DimensionMismatch opf_residuals(model, zeros(17), data)
        @test_throws DimensionMismatch opf_coverage(data, zeros(17))
        @test_throws ArgumentError opf_curve([1.0, 1.0], [1.0, 0.0])
        @test_throws ArgumentError opf_curve([1.0, 1.1], [1.0])
        @test_throws ArgumentError opf_curve([1.0, Inf], [1.0, 0.0])
        @test_throws ArgumentError opf_curve([1.0, 1.1], ComplexF64[0, 1])
        @test_throws ArgumentError opf_branch(1, 2, 0.02, 0.08, Float32; rate_from = 1e40)
        for changed in (
            merge(data, (source = merge(data.source, (bus = 1.0,)),)),
            merge(data, (branches = [merge(only(data.branches), (from = 1.0,))],)),
            merge(data, (branches = [merge(only(data.branches), (rate_from = 1e200,))],)),
            merge(data, (controllers = [merge(only(data.controllers), (bus = 2.0,))],)),
            merge(
                data,
                (
                    branches = [
                        merge(only(data.branches), (resistance = 0.0, reactance = 0.0)),
                    ],
                ),
            ),
            merge(data, (branches = [merge(only(data.branches), (from = 3,))],)),
            merge(data, (branches = [merge(only(data.branches), (rate_from = NaN,))],)),
            merge(data, (branches = typeof(only(data.branches))[],)),
            merge(data, (controllers = [only(data.controllers), only(data.controllers)],)),
            merge(data, (controllers = [merge(only(data.controllers), (bus = 3,))],)),
            merge(data, (controllers = [merge(only(data.controllers), (smax = -1.0,))],)),
            merge(
                data,
                (
                    controllers = [
                        merge(only(data.controllers), (vv = nothing, vw = nothing)),
                    ],
                ),
            ),
            merge(
                data,
                (
                    controllers = [
                        merge(
                            only(data.controllers),
                            (vv = (knots = [1.0, 0.9], values = [0.0, 0.3]),),
                        ),
                    ],
                ),
            ),
        )
            @test_throws ArgumentError BalancedACOPFModel(changed)
        end
        @test_throws ArgumentError opf_coverage(
            data,
            reference;
            tight_tol = 1e-3,
            slack_tol = 1e-4,
        )
        @test_throws ArgumentError opf_coverage(merge(data, (targets = [],)), reference)
        invalid_target = merge(only(data.targets), (tight = (:unknown,),))
        @test_throws ArgumentError opf_coverage(
            merge(data, (targets = [invalid_target],)),
            reference,
        )
    end

    @testset "Independent AC equations, derivatives and split API" begin
        mesh = balanced_ac_opf_case(:fork_mixed_reactive)
        mesh = merge(
            mesh,
            (
                branches = [mesh.branches; opf_branch(2, 3, 0.1, 0.15)],
                controllers = [
                    merge(c, (cost = 0.2, quadratic_cost = 0.1)) for c in mesh.controllers
                ],
                targets = nothing,
            ),
        )
        for data in (
            balanced_ac_opf_case(:curtailment),
            balanced_ac_opf_case(:chain_remote_curtailment),
            mesh,
        )
            l = opf_layout(data)
            model = BalancedACOPFModel(data)
            x = get_x0(model) + 0.01*sin.(collect(1:l.nvar))
            c = cons(model, x)
            balances, flows = opf_test_balance(data, x)
            @test c[l.balance_p] ≈ real.(balances)
            @test c[l.balance_q] ≈ imag.(balances)
            @test c[l.branch_from] ≈ [abs2(f.from) for f in flows]
            @test c[l.branch_to] ≈ [abs2(f.to) for f in flows]
            @test c[l.capability] ≈ x[l.p] .^ 2 + x[l.q] .^ 2
            expected_obj =
                data.source.cost*x[l.pg] + sum(
                    device.cost*x[l.p[i]] + device.quadratic_cost*x[l.p[i]]^2/2 for
                    (i, device) in enumerate(data.controllers)
                )
            @test obj(model, x) ≈ expected_obj
            @test grad(model, x) ≈ vec(opf_test_jacobian(z -> [obj(model, z)], x)) atol =
                1e-9
            J = jac(model, x)
            @test Matrix(J) ≈ opf_test_jacobian(z -> cons(model, z), x) rtol = 1e-7 atol =
                1e-7
            weights = cos.(collect(1:l.ncon))
            lag_grad(z) = 0.7*grad(model, z) + jac(model, z)'*weights
            @test Matrix(hess(model, x, weights; obj_weight = 0.7)) ≈
                  opf_test_jacobian(lag_grad, x) rtol = 1e-7 atol = 1e-7
            @test Matrix(jac_comp_left(model, x)) ≈
                  opf_test_jacobian(z -> comp_left(model, z), x) atol = 1e-9
            @test Matrix(jac_comp_right(model, x)) ≈
                  opf_test_jacobian(z -> comp_right(model, z), x) atol = 1e-9
            cl, cn = zeros(get_nlin(model)), zeros(get_nnln(model))
            @test cons_lin!(model, x, cl) ≈ c[get_lin(model)]
            @test cons_nln!(model, x, cn) ≈ c[get_nln(model)]
            @test jac_lin(model, x) ≈ J[get_lin(model), :]
            @test jac_nln(model, x) ≈ J[get_nln(model), :]
            direction = cos.(collect(1:l.nvar))
            for (jv!, jtv!, indices) in (
                (jprod_lin!, jtprod_lin!, get_lin(model)),
                (jprod_nln!, jtprod_nln!, get_nln(model)),
            )
                w = sin.(collect(1:length(indices)))
                @test jv!(model, x, direction, zeros(length(indices))) ≈
                      J[indices, :]*direction
                @test jtv!(model, x, w, zeros(l.nvar)) ≈ J[indices, :]'*w
            end
        end
    end
end
