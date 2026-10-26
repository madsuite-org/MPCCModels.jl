using Test, TOML, NLPModels, MPCCModels, Random
include("hard-search.jl")
using .HardCaseSearch
const H=HardCaseSearch
const T=H.TransmissionOPF
include("test-reporting.jl")

@testset "IEEE 300 policy cards, source anchors and matched laws" begin
    specs=T.application_expansion_specs(:policy_matrix; network = :ieee300)
    @test length(specs)==9
    @test length(T.application_policy_cases(; network = :ieee300))==6
    @test length(T.application_expansion_specs(:reserve; network = :ieee300))==3
    @test length(T.application_expansion_specs())==18
    @test length(T.application_policy_cases())==9
    for spec in specs
        data=T.application_expansion_case(spec)
        @test data.network==:ieee300
        @test isempty(data.targets) && isempty(data.network_targets)
        source=H._expansion_source(data, spec)
        @test length(source.point)==T.transmission_layout(data).nvar
        @test source.source_sha256==H._sha(H._expansion_source_file(:ieee300))
        @test source.level in (:nominal, :elevated)
        for laws in (:dispatchable, :vv, :vw, :both)
            d=T.application_expansion_case(spec; laws)
            @test d.pm==data.pm
            @test d.buses==data.buses &&
                  d.generators==data.generators &&
                  d.branches==data.branches
            @test [merge(c, (vv = nothing, vw = nothing)) for c in d.controllers]==[merge(c, (vv = nothing, vw = nothing)) for c in data.controllers]
            @test all(c->isnothing(c.vv)==!(laws in (:vv, :both)), d.controllers)
            @test all(c->isnothing(c.vw)==!(laws in (:vw, :both)), d.controllers)
            @test (T.TransmissionOPFModel(d) isa AbstractMPCCModel)==(laws!=:dispatchable)
        end
        if spec.kind==:coverage
            card=T.application_policy_card(spec.policy; network = :ieee300)
            base=T.application_case(
                card.family;
                network = :ieee300,
                level = card.level,
                parameters = card.parameters,
            )
            @test data.pm==base.pm
            @test [merge(c, (vv = nothing, vw = nothing)) for c in data.controllers]==[merge(c, (vv = nothing, vw = nothing)) for c in base.controllers]
            @test all(
                all(
                    k->data.buses[c.bus].vmin<=k<=data.buses[c.bus].vmax,
                    [c.vv.knots; c.vw.knots],
                ) for c in data.controllers
            )
        end
        mktempdir() do dir
            file=H._write(joinpath(dir, "input.toml"), H._snapshot(data))
            @test H._snapshot(load_case(file))==H._snapshot(data)
        end
    end
    @test_throws ArgumentError T.application_expansion_specs(:fleet; network = :ieee300)
    @test_throws ArgumentError T.application_policy_card(
        :early_absorption_backstop;
        network = :ieee300,
    )
    @test_throws ArgumentError T.application_expansion_case((
        kind = :reserve,
        reserve = :mild,
        network = :ieee118,
    ))
end

@testset "One-sided upper reserve preserves lower bounds, physics and hardware" begin
    base=T.application_case(:reactive_support; network = :ieee300, level = :nominal)
    saved=deepcopy(base.pm)
    previous=base
    for reserve in (:mild, :moderate, :strong)
        card=T.application_reserve_card(reserve)
        data=T.application_reserve_case(reserve)
        @test data.buses==base.buses && data.branches==base.branches
        @test data.controllers==base.controllers
        for (g, b, p) in zip(data.generators, base.generators, previous.generators)
            @test g.qmin==b.qmin
            @test g.qmin<=g.qmax<=p.qmax<=b.qmax
            @test g.qmax-g.qmin≈card.factor*(b.qmax-b.qmin)
            @test merge(g, (qmax = b.qmax,))==b
        end
        @test [g.id for g in data.generators if g.qmin>0]==[5, 44, 45]
        previous=data
    end
    restored=T.application_reserve_case(:mild; factor = 1)
    @test restored.generators==base.generators && restored.pm==base.pm
    @test base.pm==saved
    for factor in (0, -1, 1.1, NaN, Inf)
        @test_throws ArgumentError T.application_reserve_case(:mild; factor)
    end
end

@testset "Policy matrix nonflat physics and sparse derivatives" begin
    rng=MersenneTwister(30025)
    for spec in T.application_expansion_specs(:policy_matrix; network = :ieee300)
        data=T.application_expansion_case(spec)
        model=T.TransmissionOPFModel(data)
        nlp=model.nlp
        l=T.transmission_layout(data)
        x=copy(get_x0(model))
        x[l.v].+=0.01*randn(rng, length(l.v))
        x[l.theta].+=0.01*randn(rng, length(l.theta))
        balance, _=T._physical_balance(data, x, l)
        @test cons(model, x)[l.balance_p]≈real.(balance) atol=1e-9
        @test cons(model, x)[l.balance_q]≈imag.(balance) atol=1e-9
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

@testset "Portable IEEE 300 policy references, physical regimes and CCOpt evidence" begin
    fixture=TOML.parsefile(HardCaseSearch.evidence_file("ieee300-policy-matrix.toml"))
    bits(x) = bytes2hex(H.sha256(join(bitstring.(Float64.(x)), "\n")))
    @test fixture["network"]=="ieee300"
    @test fixture["source_revision"]==T.PGLIB_REVISION
    @test fixture["source_file_sha256"]==H._sha(
        joinpath(@__DIR__, "data", fixture["source_file"]),
    )
    @test fixture["source_application_sha256"]==H._sha(H._expansion_source_file(:ieee300))
    @test fixture["prepared_reference_sha256"]==fixture["plan"]["prepared_reference_sha256"]
    @test fixture["reference_environment"]["source_fingerprint"]==fixture["plan"]["environment"]["source_fingerprint"]
    specs=T.application_expansion_specs(:policy_matrix; network = :ieee300)
    by_key=Dict(H._expansion_key(s)*"-both"=>s for s in specs)
    @test length(fixture["cases"])==9 && length(fixture["trials"])==36
    @test fixture["plan"]["specs"]==H._plain(specs)
    function check_point(data, row)
        @test length(row["x"])==T.transmission_layout(data).nvar
        @test bits(row["x"])==row["point_bits_sha256"]
        @test bits(row["start"])==row["start_bits_sha256"]
        metrics=H._metrics(T.TransmissionOPFModel(data), data, row["x"], row["tolerance"])
        @test metrics["physically_feasible"]==row["physically_feasible"]
        @test metrics["objective"]≈row["objective"] atol=1e-5
        for (k, v) in row["residuals"]
            @test metrics["residuals"][k]≈v atol=1e-8
        end
        return metrics
    end
    references=Dict{String,Any}()
    ramp_positions=Float64[]
    for row in fixture["cases"]
        spec=by_key[row["case_key"]]
        key=H._expansion_key(spec)*"-both"
        data=T.application_expansion_case(spec)
        @test H._digest(H._snapshot(data))==row["input_snapshot_sha256"]
        @test row["reference_kind"]=="prevalidated_solver_point"
        point=row["reference_record"]
        @test maximum(values(check_point(data, point)["residuals"]))<=1e-7
        @test haskey(point, "sector_mask")
        references[key]=point["x"]
        cv=H._plain(T.application_policy_coverage(data, point["x"]))
        @test cv==row["witness_coverage"]
        prepared=row["prepared_reference"]
        @test prepared["x"]==point["x"]
        @test prepared["point_sha256"]==H._digest(Dict("x"=>point["x"]))
        baseline=T.application_expansion_case(spec; laws = :dispatchable)
        @test H._digest(H._snapshot(baseline))==row["counterfactual_record"]["case_sha256"]
        check_point(baseline, row["counterfactual_record"])
        if haskey(row, "counterfactual_coverage")
            @test H._plain(
                T.application_policy_coverage(baseline, row["counterfactual_record"]["x"]),
            )==row["counterfactual_coverage"]
        end
        if spec.kind==:coverage
            if spec.policy in (:gentle_watt_cap, :firm_watt_cap, :steep_watt_cap)
                @test length(cv["strict_vw_binding"])>=3
                @test all(
                    c->!(c["id"] in cv["strict_vw_binding"]) || (
                        c["margins"]["availability"]>1e-5 &&
                        c["margins"]["capability"]>1e-5
                    ),
                    cv["controllers"],
                )
                for c in cv["controllers"]
                    c["id"] in cv["strict_vw_binding"] &&
                        c["vw"]["region"]=="segment_1" &&
                        push!(ramp_positions, c["vw"]["fraction"])
                end
            elseif spec.policy==:injection_service
                @test length(cv["vv_injection_plateau"])>=1
            elseif spec.policy==:absorption_service
                @test length(cv["vv_absorption_plateau"])>=1
            else
                @test length(cv["vw_lower_plateau"])>=1
                @test length(cv["strict_vw_binding"])>=1
            end
        end
    end
    @test minimum(ramp_positions)<0.3 && maximum(ramp_positions)>0.75
    expected=Dict(
        k=>count(r->r["classification"]==k, fixture["trials"]) for
        k in keys(fixture["classifications"])
    )
    @test expected==fixture["classifications"]
    for row in fixture["trials"]
        spec=by_key[row["case_key"]]
        data=T.application_expansion_case(spec)
        @test H._plain(spec)==row["spec"]
        @test H._digest(H._snapshot(data))==row["case_sha256"]
        @test row["environment"]["source_fingerprint"]==fixture["plan"]["environment"]["source_fingerprint"]
        @test H._category(row)==row["classification"]
        @test !haskey(row, "sector_mask")
        @test row["profile"]["max_iter"]==500
        @test row["profile"]["max_wall_time"]==60
        if row["start_label"]=="witness"
            @test row["start"]==references[row["case_key"]]
            @test maximum(
                values(
                    T.transmission_residuals(
                        T.TransmissionOPFModel(data),
                        data,
                        row["start"],
                    ),
                ),
            )<=1e-7
        else
            @test row["start"]==get_x0(T.TransmissionOPFModel(data))
        end
        haskey(row, "x") && check_point(data, row)
    end
    @test length(
        readlines(joinpath(@__DIR__, "hard-cases", "ieee300-policy-matrix-sweep.tsv")),
    )==37
    mktempdir() do dir
        selected=first(specs)
        key=H._expansion_key(selected)*"-both"
        case=only(filter(r->r["case_key"]==key, fixture["cases"]))
        entry=deepcopy(case["prepared_reference"])
        receipt=H._write(joinpath(dir, "prepared.toml"), Dict("cases"=>[entry]))
        out=joinpath(dir, "search")
        kw=(
            specs = [selected],
            profiles = [:ratio_one],
            reference_receipt = receipt,
            max_iter = 1,
            max_wall_time = 10.0,
            progress = false,
        )
        rows=run_expansion_search(out; kw...)
        @test length(rows)==2 && all(r->r["witness_available"], rows)
        summary=TOML.parsefile(joinpath(out, "summary.toml"))
        @test only(values(summary["cases"]))["reference_kind"]=="prevalidated_reference"
        saved=Dict(r["trial"]=>read(joinpath(out, r["trial"], "result.toml")) for r in rows)
        again=run_expansion_search(out; kw..., resume = true)
        @test length(again)==2
        @test all(
            r->read(joinpath(out, r["trial"], "result.toml"))==saved[r["trial"]],
            again,
        )
        entry["annotation"]="changed receipt"
        H._write(receipt, Dict("cases"=>[entry]))
        @test_throws ErrorException run_expansion_search(out; kw..., resume = true)
    end
end
