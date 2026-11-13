using Test, TOML, NLPModels, Random
include("hard-search.jl")
using .HardCaseSearch
const H=HardCaseSearch
const T=H.TransmissionOPF

@testset "Operating policy definitions and matched hardware" begin
    @test length(T.application_policy_cases())==9
    for spec in T.application_policy_cases()
        card=T.application_policy_card(spec.policy)
        base=T.application_case(
            card.family;
            level = card.level,
            parameters = card.parameters,
        )
        data=T.application_policy_case(spec.policy)
        @test data.pm==base.pm
        @test data.buses==base.buses &&
              data.generators==base.generators &&
              data.branches==base.branches
        @test data.provenance.policy_variant==string(spec.policy)
        @test isempty(data.targets) && isempty(data.network_targets)
        for laws in (:both, :vv, :vw, :dispatchable)
            variant=T.application_policy_case(spec.policy; laws)
            @test variant.pm==data.pm
            for (c, b) in zip(variant.controllers, base.controllers)
                @test Base.structdiff(c, (vv = c.vv, vw = c.vw))==Base.structdiff(
                    b,
                    (vv = b.vv, vw = b.vw),
                )
                @test isnothing(c.vv)==!(laws in (:vv, :both))
                @test isnothing(c.vw)==!(laws in (:vw, :both))
                for curve in (c.vv, c.vw)
                    isnothing(curve) && continue
                    @test all(
                        k->variant.buses[c.bus].vmin<=k<=variant.buses[c.bus].vmax,
                        curve.knots,
                    )
                end
            end
        end
        mktempdir() do dir
            file=H._write(joinpath(dir, "input.toml"), H._snapshot(data))
            @test H._snapshot(load_case(file))==H._snapshot(data)
        end
    end
    @test_throws ArgumentError T.application_policy_case(:unknown)
    @test_throws ArgumentError T.application_policy_case(
        :absorption_service;
        laws = :unknown,
    )
end

@testset "Fixed-total heterogeneous populations and distinct-site geography" begin
    base=T.application_case(:reactive_support; level = :elevated)
    source=TOML.parsefile(H.EXPANSION_SOURCE)
    row=only(
        filter(
            r->r["family"]=="reactive_support" && r["level"]=="elevated",
            source["cases"],
        ),
    )
    x=row["witness"]["x"]
    base_layout=T.transmission_layout(base)
    for placement in (:same_sites, :clustered, :dispersed), count in (6, 12, 24)
        data=T.application_fleet_case(; count, placement)
        @test length(data.controllers)==count
        @test data.pm==base.pm
        @test data.buses==base.buses &&
              data.generators==base.generators &&
              data.branches==base.branches
        @test sum(c.smax for c in data.controllers)≈sum(c.smax for c in base.controllers)
        @test sum(c.p_available for c in data.controllers)≈sum(
            c.p_available for c in base.controllers
        )
        @test data.provenance.fleet_copies==count÷6
        for i in 1:6
            selected=findall(==(i), data.provenance.fleet_templates)
            c=base.controllers[i]
            @test sum(data.controllers[j].smax for j in selected)≈c.smax
            @test sum(data.controllers[j].p_available for j in selected)≈c.p_available
            @test sum(data.controllers[j].qmin for j in selected)≈c.qmin
            @test sum(data.controllers[j].qmax for j in selected)≈c.qmax
            for j in selected
                d=data.controllers[j]
                @test d.vv.knots==c.vv.knots && d.vw.knots==c.vw.knots
                @test d.vv.values/d.smax≈c.vv.values/c.smax
                @test d.vw.values/d.smax≈c.vw.values/c.smax
            end
        end
        y=T.application_fleet_start(data, base, x)
        l=T.transmission_layout(data)
        @test length(y)==l.nvar
        @test y[l.v]==x[base_layout.v] && y[l.pg]==x[base_layout.pg]
        @test sum(y[l.p])≈sum(x[base_layout.p])
        @test sum(y[l.q])≈sum(x[base_layout.q])
        model=T.TransmissionOPFModel(data)
        @test obj(model, y)≈obj(T.TransmissionOPFModel(base), x) atol=1e-8
        if placement==:same_sites
            @test length(unique(c.bus for c in data.controllers))==6
            @test maximum(values(T.transmission_residuals(model, data, y)))<=1e-7
        else
            @test allunique(c.bus for c in data.controllers)
            @test !(data.reference_bus in [c.bus for c in data.controllers])
        end
        dispatchable=T.application_fleet_case(; count, placement, laws = :dispatchable)
        @test dispatchable.pm==data.pm
        @test all(c->isnothing(c.vv) && isnothing(c.vw), dispatchable.controllers)
    end
    for placement in (:clustered, :dispersed)
        sites6=T.application_fleet_case(; count = 6, placement).provenance.fleet_sites
        sites12=T.application_fleet_case(; count = 12, placement).provenance.fleet_sites
        sites24=T.application_fleet_case(; count = 24, placement).provenance.fleet_sites
        @test sites6==sites12[1:6]==sites24[1:6]
        @test sites12==sites24[1:12]
    end
    @test length(T.application_expansion_specs(:fleet))==9
    @test length(T.application_expansion_specs())==18
    @test_throws ArgumentError T.application_fleet_case(; count = 7)
    @test_throws ArgumentError T.application_fleet_case(;
        count = 120,
        placement = :dispersed,
    )
    @test_throws ArgumentError T.application_fleet_case(; placement = :unknown)
end

@testset "Expansion derivatives, record integrity and safe resume" begin
    rng=MersenneTwister(805)
    for data in (
        T.application_policy_case(:injection_service),
        T.application_fleet_case(; count = 24, placement = :dispersed),
    )
        model=T.TransmissionOPFModel(data)
        nlp=model.nlp
        x=copy(get_x0(model))
        d=randn(rng, length(x))
        lambda=randn(rng, get_ncon(model))
        h=1e-6
        @test jprod(nlp, x, d)≈(cons(model, x+h*d)-cons(model, x-h*d))/(2*h) rtol=1e-6 atol=1e-6
        laggrad(z) = grad(nlp, z)+jtprod(nlp, z, lambda)
        @test hprod(nlp, x, lambda, d)≈(laggrad(x+h*d)-laggrad(x-h*d))/(2*h) rtol=1e-6 atol=1e-5
    end
    mktempdir() do dir
        out=joinpath(dir, "search")
        kw=(
            specs = [(kind = :coverage, policy = :absorption_service)],
            profiles = [:ratio_one],
            max_iter = 1,
            max_wall_time = 10.0,
            progress = false,
        )
        rows=run_expansion_search(out; kw...)
        @test length(rows)==2
        summary=TOML.parsefile(joinpath(out, "summary.toml"))
        @test length(summary["cases"])==1
        info=first(values(summary["cases"]))
        @test length(info["references"])>=1
        saved=Dict(r["trial"]=>read(joinpath(out, r["trial"], "result.toml")) for r in rows)
        again=run_expansion_search(out; kw..., resume = true)
        @test length(again)==2
        @test all(
            r->read(joinpath(out, r["trial"], "result.toml"))==saved[r["trial"]],
            again,
        )
        @test_throws ErrorException run_expansion_search(
            out;
            kw...,
            resume = true,
            max_iter = 2,
        )
        fleet_out=joinpath(dir, "fleet")
        fleet_spec=(
            kind = :fleet,
            family = :reactive_support,
            level = :elevated,
            count = 12,
            placement = :same_sites,
        )
        fleet_rows=run_expansion_search(
            fleet_out;
            specs = [fleet_spec],
            profiles = [:ratio_one],
            max_iter = 1,
            max_wall_time = 10.0,
            progress = false,
        )
        @test length(fleet_rows)==2
        @test all(r->r["witness_available"], fleet_rows)
        fleet_case=first(
            values(TOML.parsefile(joinpath(fleet_out, "summary.toml"))["cases"]),
        )
        @test fleet_case["reference_kind"]=="physical_transfer"
        @test !any(r->r["classification"]=="unavailable_start", fleet_rows)
    end
end

@testset "Archived operating coverage and fleet challenges" begin
    fixture=TOML.parsefile(HardCaseSearch.evidence_file("ieee118-expansions.toml"))
    bits(x) = bytes2hex(H.sha256(join(bitstring.(Float64.(x)), "\n")))
    restore(d) =
        d["kind"]=="coverage" ? (kind = :coverage, policy = Symbol(d["policy"])) :
        (
            kind = :fleet,
            family = Symbol(d["family"]),
            level = Symbol(d["level"]),
            count = d["count"],
            placement = Symbol(d["placement"]),
        )
    @test fixture["source_application_sha256"]==H._sha(H.EXPANSION_SOURCE)
    @test fixture["source_file_sha256"]==H._sha(
        joinpath(@__DIR__, "data", fixture["source_file"]),
    )
    @test length(fixture["cases"])==18
    @test fixture["classifications"]==Dict("success"=>36, "solver_failure"=>18)
    function check_record(data, r; tolerance = get(r, "tolerance", 1e-7))
        @test bits(r["x"])==r["point_bits_sha256"]
        model=T.TransmissionOPFModel(data)
        metrics=H._metrics(model, data, r["x"], tolerance)
        @test metrics["objective"]≈r["objective"] atol=1e-5
        for (k, v) in r["residuals"]
            @test metrics["residuals"][k]≈v atol=1e-9
        end
        if haskey(r, "start")
            @test bits(r["start"])==r["start_bits_sha256"]
        end
        coverage=T.application_coverage(data, r["x"])
        @test coverage["vv_regions"]==r["coverage"]["vv_regions"]
        @test coverage["vw_regions"]==r["coverage"]["vw_regions"]
        @test coverage["curtailed_mw"]≈r["coverage"]["curtailed_mw"] atol=1e-6
        return metrics
    end
    for row in fixture["cases"]
        spec=restore(row["spec"])
        data=T.application_expansion_case(spec)
        @test bytes2hex(H.sha256(H._toml(H._snapshot(data))))==row["input_snapshot_sha256"]
        layout=T.transmission_layout(data)
        @test (layout.nvar, layout.ncon, length(layout.r))==(
            row["nvar"],
            row["ncon"],
            row["ncc"],
        )
        @test 1<=row["primary_reference"]<=length(row["references"])
        for ref in row["references"]
            @test check_record(data, ref; tolerance = 1e-7)["physically_feasible"]
            if ref["kind"]=="physical_transfer"
                @test ref["method"]=="physical_start_transfer_without_solver" ||
                      ref["method"]=="physical_transfer_without_solver"
                @test !haskey(ref, "solver_success")
            end
        end
        baseline=T.application_expansion_case(spec; laws = :dispatchable)
        @test check_record(baseline, row["counterfactual"])["physically_feasible"]
    end
    for r in fixture["trials"]
        data=T.application_expansion_case(restore(r["spec"]))
        @test check_record(data, r)["physically_feasible"]==r["physically_feasible"]
    end
    function policy_refs(policy)
        row=only(filter(r->get(r["spec"], "policy", "")==string(policy), fixture["cases"]))
        return T.application_policy_case(policy), row["references"]
    end
    data, refs=policy_refs(:absorption_service)
    l=T.transmission_layout(data)
    @test any(
        any(
            x[l.v[c.bus]]>last(c.vv.knots)+1e-6 && abs(x[l.q[i]]-last(c.vv.values))<1e-6 for
            (i, c) in enumerate(data.controllers)
        ) for x in [r["x"] for r in refs]
    )
    data, refs=policy_refs(:injection_service)
    l=T.transmission_layout(data)
    @test any(
        any(
            x[l.v[c.bus]]<first(c.vv.knots)-1e-6 && abs(x[l.q[i]]-first(c.vv.values))<1e-6
            for (i, c) in enumerate(data.controllers)
        ) for x in [r["x"] for r in refs]
    )
    data, refs=policy_refs(:early_export_backstop)
    l=T.transmission_layout(data)
    @test any(
        any(
            x[l.v[c.bus]]>last(c.vw.knots)+1e-6 &&
                abs(x[l.p[i]]-last(c.vw.values))<1e-6 &&
                c.p_available-x[l.p[i]]>0.1*c.smax for (i, c) in enumerate(data.controllers)
        ) for x in [r["x"] for r in refs]
    )
    for (policy, target) in zip(
        (
            :early_absorption_backstop,
            :middle_absorption_backstop,
            :late_absorption_backstop,
        ),
        (0.2, 0.5, 0.8),
    )
        data, refs=policy_refs(policy)
        l=T.transmission_layout(data)
        @test any(
            any(
                abs((x[l.v[c.bus]]-c.vv.knots[3])/(c.vv.knots[4]-c.vv.knots[3])-target)<0.02
                for c in data.controllers
            ) for x in [r["x"] for r in refs]
        )
    end
    # Strict VW ramp operation, with availability genuinely slack.
    fractions=Float64[]
    for policy in (:gentle_watt_cap, :firm_watt_cap, :steep_watt_cap)
        data, refs=policy_refs(policy)
        l=T.transmission_layout(data)
        for ref in refs, (i, c) in enumerate(data.controllers)
            x=ref["x"]
            v=x[l.v[c.bus]]
            if first(c.vw.knots)<v<last(c.vw.knots) &&
               c.p_available-x[l.p[i]]>0.01*c.smax &&
               abs(T.opf_volt_watt(v, c)-x[l.p[i]])<1e-5
                push!(fractions, (v-first(c.vw.knots))/(last(c.vw.knots)-first(c.vw.knots)))
            end
        end
    end
    @test any(f->0.2<f<0.3, fractions)
    @test any(f->0.45<f<0.6, fractions)
    @test any(f->0.75<f<0.85, fractions)
    @test length(
        readlines(joinpath(@__DIR__, "hard-cases", "ieee118-expansions-sweep.tsv")),
    )==55
end
