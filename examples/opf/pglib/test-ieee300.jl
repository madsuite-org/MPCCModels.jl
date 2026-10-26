# Optional IEEE 300 import, application invariants and portable research evidence.
using Test, TOML, NLPModels, MPCCModels, Random
include("hard-search.jl")
using .HardCaseSearch
const H=HardCaseSearch
const T=H.TransmissionOPF
include("hard-cases/study-ieee300-limits.jl")

@testset "IEEE 300 canonical import and original-ID mapping" begin
    data=T.transmission_case(:ieee300)
    l=T.transmission_layout(data)
    @test (length(data.buses), length(data.branches), length(data.generators))==(
        300,
        411,
        69,
    )
    @test (l.nvar, l.ncon, length(l.r))==(738, 1833, 0)
    @test !(T.TransmissionOPFModel(data) isa AbstractMPCCModel)
    @test sum(b.pd for b in data.buses)≈235.2585
    @test sum(b.qd for b in data.buses)≈77.8797
    @test [g.id for g in data.generators if g.qmin>0]==[5, 44, 45]
    @test data.buses[end].id==9533
    @test isempty(data.targets) && isempty(data.network_targets)
    @test length(T.transmission_cases())==22
    @test_throws ArgumentError T.pglib_control_case(:ieee300)
    @test_throws ArgumentError T.application_card(:renewable_surplus; network = :ieee14)
    @test_throws ArgumentError T.application_cases(; network = :unknown)
    @test H._sha(joinpath(@__DIR__, "data", data.provenance.file))=="7ecf056d5942135765200ad7ae8791c28f0d35fb1dc888ba2c32dfc950f3c2f5"
end

@testset "IEEE 300 application hardware, cutset and matched policies" begin
    base=T.transmission_case(:ieee300)
    source=deepcopy(base.pm)
    @test length(T.application_cases(; network = :ieee300))==9
    @test all(c->c.network==:ieee300, T.application_cases(; network = :ieee300))
    @test T.application_cases()==[
        (family = f, level = l) for f in T.APPLICATION_FAMILIES for
        l in T.APPLICATION_LEVELS
    ]
    for spec in T.application_cases(; network = :ieee300)
        family, level=spec.family, spec.level
        card=T.application_card(family; network = :ieee300)
        p=T.application_parameters(family, level; network = :ieee300)
        data=T.application_case(family; network = :ieee300, level)
        @test data.network==:ieee300 && card.network==:ieee300
        @test [data.buses[c.bus].id for c in data.controllers]==collect(card.sites)
        @test allunique(c.bus for c in data.controllers)
        @test sum(c.smax for c in data.controllers)≈p.penetration*sum(card.ratings)
        @test all(c->c.p_available≈p.availability*c.smax, data.controllers)
        @test data.buses==[
            merge(b, (pd = p.load_scale*b.pd, qd = p.load_scale*b.qd)) for b in base.buses
        ]
        @test data.generators==[
            merge(g, (qmin = p.q_support*g.qmin, qmax = p.q_support*g.qmax)) for
            g in base.generators
        ]
        boundary=Set(
            b.id for b in base.branches if
            (base.buses[b.from].id in card.zone)!=(base.buses[b.to].id in card.zone)
        )
        @test Set(data.provenance.export_boundary)==boundary
        @test length(boundary)==(family==:export_corridor ? 2 : 0)
        @test data.branches==[
            b.id in boundary ? merge(b, (rate = p.export_rating*b.rate,)) : b for
            b in base.branches
        ]
        @test isempty(data.targets) && isempty(data.network_targets)
        for laws in (:dispatchable, :vv, :vw, :both)
            other=T.application_case(family; network = :ieee300, level, laws)
            @test other.pm==data.pm
            @test [merge(c, (vv = nothing, vw = nothing)) for c in other.controllers]==[merge(c, (vv = nothing, vw = nothing)) for c in data.controllers]
            @test all(c->isnothing(c.vv)==!(laws in (:vv, :both)), other.controllers)
            @test all(c->isnothing(c.vw)==!(laws in (:vw, :both)), other.controllers)
            l=T.transmission_layout(other)
            @test length(l.r)==length(data.controllers)*(
                laws==:both ? 6 : laws==:vv ? 4 : laws==:vw ? 2 : 0
            )
        end
    end
    @test base.pm==source
end

@testset "IEEE 300 nonflat physics and sparse directional derivatives" begin
    rng=MersenneTwister(300)
    for family in (:canonical, T.APPLICATION_FAMILIES...)
        data=family==:canonical ? T.transmission_case(:ieee300) :
             T.application_case(family; network = :ieee300, level = :severe)
        model=T.TransmissionOPFModel(data)
        nlp=model isa AbstractMPCCModel ? model.nlp : model
        l=T.transmission_layout(data)
        x=copy(get_x0(model))
        x[l.v].+=0.01*randn(rng, length(l.v))
        x[l.theta].+=0.01*randn(rng, length(l.theta))
        balance, flows=T._physical_balance(data, x, l)
        cx=cons(model, x)
        @test cx[l.balance_p]≈real.(balance) atol=1e-9
        @test cx[l.balance_q]≈imag.(balance) atol=1e-9
        @test cx[l.branch_from]≈[abs2(flows[b.id][1]) for b in data.branches] atol=1e-8
        @test cx[l.branch_to]≈[abs2(flows[b.id][2]) for b in data.branches] atol=1e-8
        direction=randn(rng, length(x))
        lambda=randn(rng, get_ncon(model))
        h=1e-6
        @test jprod(nlp, x, direction)≈(
            cons(model, x+h*direction)-cons(model, x-h*direction)
        )/(2*h) rtol=1e-6 atol=1e-5
        laggrad(z) = grad(nlp, z)+jtprod(nlp, z, lambda)
        @test hprod(nlp, x, lambda, direction)≈(
            laggrad(x+h*direction)-laggrad(x-h*direction)
        )/(2*h) rtol=1e-6 atol=1e-4
    end
end

@testset "IEEE 300 recorder selects the requested network and preserves attempts" begin
    mktempdir() do dir
        out=joinpath(dir, "search")
        kw=(
            network = :ieee300,
            families = [:export_corridor],
            levels = [:nominal],
            profiles = [:ratio_one],
            max_iter = 1,
            max_wall_time = 10.0,
            progress = false,
        )
        rows=run_application_search(out; kw...)
        @test length(rows)==2
        @test TOML.parsefile(joinpath(out, "plan.toml"))["network"]=="ieee300"
        summary=TOML.parsefile(joinpath(out, "summary.toml"))
        @test first(values(summary["cases"]))["card"]["network"]=="ieee300"
        request=read_trial(joinpath(out, first(rows)["trial"])).request
        data=H.load_case(
            normpath(joinpath(out, first(rows)["trial"], request["case_file"])),
        )
        @test data.network==:ieee300
        before=Dict(
            r["trial"]=>read(joinpath(out, r["trial"], "result.toml")) for r in rows
        )
        again=run_application_search(out; kw..., resume = true)
        @test all(
            r->read(joinpath(out, r["trial"], "result.toml"))==before[r["trial"]],
            again,
        )
        @test_throws ErrorException run_application_search(
            out;
            merge(kw, (network = :ieee118,))...,
            resume = true,
        )
    end
end

@testset "Isolated IEEE 300 physical limits" begin
    for family in (:renewable_surplus, :export_corridor)
        base=ieee300_sensitivity_case(family)
        modified=ieee300_sensitivity_case(family; modified = true)
        @test base.network==modified.network==:ieee300
        @test base.buses==modified.buses
        if family==:renewable_surplus
            @test modified.pm==base.pm
            @test modified.controllers==[
                merge(c, (smax = 1.1*c.smax,)) for c in base.controllers
            ]
        else
            @test modified.generators==base.generators &&
                  modified.controllers==base.controllers
            boundary=base.provenance.export_boundary
            @test [merge(b, (rate = 0.0,)) for b in modified.branches]==[merge(b, (rate = 0.0,)) for b in base.branches]
            @test all(
                a.rate≈(b.id in boundary ? b.rate/0.7 : b.rate) for
                (a, b) in zip(modified.branches, base.branches)
            )
        end
    end
    @test_throws ArgumentError ieee300_sensitivity_case(:unknown)
    @test_throws ArgumentError ieee300_sensitivity_case(:reactive_support; modified = true)
end

@testset "Portable IEEE 300 canonical, application and CCOpt evidence" begin
    fixture=TOML.parsefile(HardCaseSearch.evidence_file("ieee300-applications.toml"))
    bits(x) = bytes2hex(H.sha256(join(bitstring.(Float64.(x)), "\n")))
    @test fixture["network"]=="ieee300"
    @test fixture["source_revision"]==T.PGLIB_REVISION
    @test fixture["source_file_sha256"]==H._sha(
        joinpath(@__DIR__, "data", fixture["source_file"]),
    )
    function check_point(data, row)
        @test bits(row["x"])==row["point_bits_sha256"]
        if haskey(row, "start")
            @test bits(row["start"])==row["start_bits_sha256"]
            @test length(row["start"])==T.transmission_layout(data).nvar
        end
        model=T.TransmissionOPFModel(data)
        metrics=H._metrics(model, data, row["x"], row["tolerance"])
        @test metrics["physically_feasible"]==row["physically_feasible"]
        @test metrics["objective"]≈row["objective"] atol=1e-5
        for (k, v) in row["residuals"]
            @test metrics["residuals"][k]≈v atol=1e-8
        end
        return metrics
    end
    canonical=T.transmission_case(:ieee300)
    base=fixture["canonical"]
    @test H._digest(H._snapshot(canonical))==base["input_snapshot_sha256"]
    for solver in ("madnlp", "powermodels")
        @test maximum(values(check_point(canonical, base[solver])["residuals"]))<=1e-7
    end
    @test base["madnlp"]["objective"]≈base["powermodels"]["objective_powermodels"] atol=1e-4
    @test length(fixture["cases"])==9
    @test length(fixture["trials"])==36
    expected=Dict(
        k=>count(r->r["classification"]==k, fixture["trials"]) for
        k in keys(fixture["classifications"])
    )
    @test expected==fixture["classifications"]
    for row in fixture["cases"]
        family, level=Symbol(row["family"]), Symbol(row["level"])
        data=T.application_case(family; network = :ieee300, level)
        @test H._digest(H._snapshot(data))==row["input_snapshot_sha256"]
        @test H._plain(T.application_card(family; network = :ieee300))==row["card"]
        if row["witness_available"]
            witness=row["witness"]
            @test maximum(values(check_point(data, witness)["residuals"]))<=1e-7
            @test H._plain(T.application_coverage(data, witness["x"]))==row["witness_coverage"]
        end
        baseline=T.application_case(family; network = :ieee300, level, laws = :dispatchable)
        check_point(baseline, row["counterfactual_record"])
        if haskey(row, "counterfactual_coverage")
            @test H._plain(
                T.application_coverage(baseline, row["counterfactual_record"]["x"]),
            )==row["counterfactual_coverage"]
        end
    end
    for row in fixture["trials"]
        @test row["network"]=="ieee300"
        data=T.application_case(
            Symbol(row["family"]);
            network = :ieee300,
            level = Symbol(row["level"]),
        )
        @test H._digest(H._snapshot(data))==row["case_sha256"]
        if row["classification"]=="unavailable_start"
            @test row["status"]=="not_run" && !haskey(row, "x")
        else
            @test row["environment"]["source_fingerprint"]==fixture["plan"]["environment"]["source_fingerprint"]
            @test H._category(row)==row["classification"]
        end
        haskey(row, "x") && check_point(data, row)
    end
    witnessed=filter(r->r["witness_available"], fixture["cases"])
    @test length(witnessed)==7
    @test all(
        all(
            c->!(c["id"] in row["witness_coverage"]["vw_binding"]) ||
               abs(c["margins"]["availability"])<=1e-5,
            row["witness_coverage"]["controllers"],
        ) for row in witnessed
    )
    severe=only(
        filter(r->r["family"]=="renewable_surplus" && r["level"]=="severe", witnessed),
    )["witness_coverage"]
    @test length(severe["capability_binding"])==3
    @test all(
        c->!(c["id"] in severe["capability_binding"]) ||
           (c["margins"]["availability"]>1e-5 && c["margins"]["volt_watt"]>1e-5),
        severe["controllers"],
    )
    export_case=only(
        filter(r->r["family"]=="export_corridor" && r["level"]=="severe", witnessed),
    )["witness_coverage"]
    @test Set([63, 66]) ⊆ Set(export_case["network_tight"]["thermal_to"])
    studies=fixture["sensitivities"]
    @test length(studies)==4
    for row in studies
        data=ieee300_sensitivity_case(
            Symbol(row["family"]);
            modified = row["label"]=="modified",
        )
        record=row["record"]
        @test H._digest(H._snapshot(data))==record["case_sha256"]
        check_point(data, record)
        if row["verified"]
            @test maximum(values(record["residuals"]))<=1e-7
            @test H._plain(T.application_coverage(data, record["x"]))==row["coverage"]
        end
    end
    for family in unique(r["family"] for r in studies)
        pair=filter(r->r["family"]==family, studies)
        a=only(filter(r->r["label"]=="reference", pair))["record"]
        b=only(filter(r->r["label"]=="modified", pair))["record"]
        @test a["start"]==b["start"]
        @test a["profile"]==b["profile"]
        @test a["sector_mask"]==b["sector_mask"]
    end
    oversized=only(
        filter(r->r["family"]=="renewable_surplus" && r["label"]=="modified", studies),
    )["coverage"]
    @test isempty(oversized["capability_binding"])
    @test length(oversized["vw_binding"])==3
    @test all(
        c->!(c["id"] in oversized["vw_binding"]) || abs(c["margins"]["availability"])<=1e-5,
        oversized["controllers"],
    )
    @test length(
        readlines(joinpath(@__DIR__, "hard-cases", "ieee300-applications-sweep.tsv")),
    )==37
end
