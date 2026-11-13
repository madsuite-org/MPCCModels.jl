# Solver-free construction, physical invariants and new optional API validation.
using Test, NLPModels, MPCCModels, Random
include("transmission-opf.jl")
const T=TransmissionOPF

@testset "Operating matrix dimensions, matched laws and independent axes" begin
    for network in (:ieee118, :ieee300)
        original_policy=T.application_policy_case(:gentle_watt_cap; network)
        shifted_policy=T.application_policy_case(
            :gentle_watt_cap;
            network,
            parameters = (profile_shift = 0.001,),
        )
        @test shifted_policy.pm==original_policy.pm
        for (shifted, original) in
            zip(shifted_policy.controllers, original_policy.controllers)
            @test shifted.vv.knots≈original.vv.knots .+ 0.001
            @test shifted.vw.knots≈original.vw.knots .+ 0.001
            @test shifted.vv.values==original.vv.values &&
                  shifted.vw.values==original.vw.values
        end
        specs=T.operating_condition_specs(; network)
        @test length(specs)==23 && allunique(s.id for s in specs)
        byid=Dict(s.id=>s for s in specs)
        reference=T.operating_condition_case(byid[:reserve_reference])
        for id in (:reserve_q98, :reserve_q95, :reserve_q90, :reserve_q80)
            spec=byid[id]
            data=T.operating_condition_case(spec)
            @test data.buses==reference.buses && data.branches==reference.branches
            @test data.controllers==reference.controllers
            for (g, original) in zip(data.generators, reference.generators)
                @test g.qmin==original.qmin
                @test g.qmax≈g.qmin+spec.q_upper_fraction*(original.qmax-g.qmin)
                @test merge(g, (qmax = original.qmax,))==original
            end
        end
        export_reference=T.operating_condition_case(byid[:export_r100])
        boundary=export_reference.provenance.export_boundary
        @test !isempty(boundary)
        for id in (:export_r120, :export_r85, :export_r70, :export_r55)
            spec=byid[id]
            data=T.operating_condition_case(spec)
            @test data.buses==export_reference.buses &&
                  data.generators==export_reference.generators
            @test data.controllers==export_reference.controllers
            for (branch, original) in zip(data.branches, export_reference.branches)
                @test branch.rate≈original.rate*(
                    branch.id in boundary ? spec.parameters.export_rating : 1.0
                )
                @test merge(branch, (rate = original.rate,))==original
            end
        end
        anchor=T.operating_condition_case(byid[:penetration_p65])
        for id in (:penetration_p45, :penetration_p85)
            data=T.operating_condition_case(byid[id])
            @test data.pm==anchor.pm
            for (c, a) in zip(data.controllers, anchor.controllers)
                @test c.vv.knots==a.vv.knots && c.vw.knots==a.vw.knots
                @test c.vv.values/c.smax≈a.vv.values/a.smax
                @test c.vw.values/c.smax≈a.vw.values/a.smax
                @test c.p_available/c.smax≈a.p_available/a.smax
            end
        end
        for id in (:placement_6_clustered, :placement_6_dispersed, :placement_12_same_sites)
            data=T.operating_condition_case(byid[id])
            @test data.pm==anchor.pm
            @test sum(c.smax for c in data.controllers)≈sum(
                c.smax for c in anchor.controllers
            )
            @test sum(c.p_available for c in data.controllers)≈sum(
                c.p_available for c in anchor.controllers
            )
            @test length(data.controllers)==byid[id].count
            @test !(data.reference_bus in [c.bus for c in data.controllers])
        end
        replicas=T.operating_condition_case(byid[:placement_12_same_sites])
        source_model=T.TransmissionOPFModel(anchor)
        x=copy(get_x0(source_model))
        split=T.application_fleet_start(replicas, anchor, x)
        @test T._physical_balance(anchor, x, T.transmission_layout(anchor))[1]≈T._physical_balance(
            replicas,
            split,
            T.transmission_layout(replicas),
        )[1] atol=1e-10
        @test obj(source_model, x)≈obj(T.TransmissionOPFModel(replicas), split) atol=1e-8
        @test T.transmission_residuals(source_model, anchor, x).physical_balance≈T.transmission_residuals(
            T.TransmissionOPFModel(replicas),
            replicas,
            split,
        ).physical_balance atol=1e-10
        for spec in specs
            data=T.operating_condition_case(spec)
            @test isempty(data.targets) && isempty(data.network_targets)
            @test data.network==network
            for laws in (:dispatchable, :vv, :vw)
                matched=T.operating_condition_case(spec; laws)
                @test data.pm==matched.pm
                @test [merge(c, (vv = nothing, vw = nothing)) for c in data.controllers] == [merge(c, (vv = nothing, vw = nothing)) for c in matched.controllers]
            end
        end
    end
    spec=first(T.operating_condition_specs())
    for fraction in (0.0, -1.0, 1.1, Inf, NaN)
        @test_throws ArgumentError T.operating_condition_case(
            merge(spec, (q_upper_fraction = fraction,)),
        )
    end
    @test_throws ArgumentError T.operating_condition_specs(; network = :ieee14)
    @test_throws ArgumentError T.operating_condition_case(merge(spec, (count = 12,)))
    @test_throws ArgumentError T.operating_condition_case(
        merge(spec, (placement = :unknown,)),
    )
    @test_throws ArgumentError T.operating_condition_case(Dict("id"=>"bad"))
end

@testset "Operating sparse derivatives and direct complex physics" begin
    rng=MersenneTwister(20261026)
    for network in (:ieee118, :ieee300)
        for id in (:reserve_q90, :placement_6_clustered)
            spec=only(filter(s->s.id==id, T.operating_condition_specs(; network)))
            data=T.operating_condition_case(spec)
            model=T.TransmissionOPFModel(data)
            nlp=model.nlp
            l=T.transmission_layout(data)
            x=copy(get_x0(model))
            x[l.v].+=0.005*randn(rng, length(l.v))
            x[l.theta].+=0.005*randn(rng, length(l.theta))
            balance, _=T._physical_balance(data, x, l)
            @test cons(model, x)[l.balance_p]≈real.(balance) atol=1e-8
            @test cons(model, x)[l.balance_q]≈imag.(balance) atol=1e-8
            direction=randn(rng, length(x))
            lambda=randn(rng, get_ncon(model))
            h=1e-6
            @test jprod(nlp, x, direction)≈(
                cons(nlp, x+h*direction)-cons(nlp, x-h*direction)
            )/(2h) rtol=1e-6 atol=1e-5
            laggrad(z) = grad(nlp, z)+jtprod(nlp, z, lambda)
            @test hprod(nlp, x, lambda, direction)≈(
                laggrad(x+h*direction)-laggrad(x-h*direction)
            )/(2h) rtol=1e-6 atol=1e-4
        end
    end
end
