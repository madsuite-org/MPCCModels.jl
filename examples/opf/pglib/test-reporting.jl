# Included after HardCaseSearch is loaded; these checks invoke no optimizer.
@testset "Independent policy-limit and strict plateau classification" begin
    data=T.application_policy_case(:gentle_watt_cap; network = :ieee300)
    model=T.TransmissionOPFModel(data)
    l=T.transmission_layout(data)
    x=copy(get_x0(model))
    c=first(data.controllers)
    v=sum(c.vw.knots)/2
    x[l.v[c.bus]]=v
    x[l.p[1]]=T.BalancedACOPF.opf_volt_watt(v, c)
    x[l.q[1]]=T.BalancedACOPF.opf_volt_var(v, c)
    cv=T.application_policy_coverage(data, x)
    @test "plant1" in cv["strict_vw_binding"]
    @test !("plant1" in cv["availability_vw_joint"])
    joint=T.transmission_overlay(
        data;
        controllers = [merge(c, (p_available = x[l.p[1]],)); data.controllers[2:end]],
    )
    cj=T.application_policy_coverage(joint, x)
    @test !("plant1" in cj["strict_vw_binding"])
    @test "plant1" in cj["availability_vw_joint"]
    @test !haskey(T.application_coverage(data, x), "strict_vw_binding")
    # This diagnostic point deliberately need not satisfy network balance.
    @test maximum(values(T.transmission_residuals(model, data, x)))>1e-5
    injection=T.application_policy_case(:injection_service; network = :ieee300)
    li=T.transmission_layout(injection)
    xi=copy(get_x0(T.TransmissionOPFModel(injection)))
    xi[li.v[injection.controllers[1].bus]]=injection.controllers[1].vv.knots[1]-1e-4
    @test "plant1" in T.application_policy_coverage(injection, xi)["vv_injection_plateau"]
    # Plateau polarity follows Q, including one-sided and reversed curves.
    for values in ([0.0, 0.0], [0.0, -0.1], [0.1, 0.0], [-0.1, 0.1])
        curve=T.BalancedACOPF.opf_curve([1.0, 1.02], values)
        custom=T.transmission_overlay(
            injection;
            controllers = [
                merge(injection.controllers[1], (vv = curve,));
                injection.controllers[2:end]
            ],
        )
        xc=T.transmission_start(custom, injection, xi)
        for (voltage, q) in
            ((0.99, first(values)), (1.03, last(values)), (1.0, 0.0), (1.02, 0.0))
            xc[T.transmission_layout(custom).v[custom.controllers[1].bus]]=voltage
            coverage=T.application_policy_coverage(custom, xc)
            @test ("plant1" in coverage["vv_injection_plateau"])==(q>1e-5)
            @test ("plant1" in coverage["vv_absorption_plateau"])==(q < -1e-5)
        end
    end
    for tol in (0, NaN, Inf)
        @test_throws ArgumentError T.application_policy_coverage(
            data,
            x;
            voltage_tolerance = tol,
        )
    end
end

@testset "Prepared references reject mismatches and original infeasibility" begin
    mktempdir() do dir
        data=T.application_case(:reactive_support; network = :ieee300, level = :nominal)
        source=TOML.parsefile(H._expansion_source_file(:ieee300))
        row=only(
            filter(
                r->r["family"]=="reactive_support" && r["level"]=="nominal",
                source["cases"],
            ),
        )
        x=row["witness"]["x"]
        # Reproduce the reporting bug at an original-feasible zero-Q operating point.
        layout=T.transmission_layout(data)
        i=argmin(abs.(x[layout.q]))
        controller=data.controllers[i]
        voltage=x[layout.v[controller.bus]]
        controllers=copy(data.controllers)
        controllers[i]=merge(
            controller,
            (vv = T.opf_curve([voltage+0.002, voltage+0.004], [0.0, 0.0]),),
        )
        zero=T.transmission_overlay(data; controllers)
        transferred=T.transmission_start(zero, data, x)
        @test maximum(
            values(
                T.transmission_residuals(T.TransmissionOPFModel(zero), zero, transferred),
            ),
        )<=1e-7
        coverage=T.application_policy_coverage(zero, transferred)
        @test !(string(controller.id) in coverage["vv_injection_plateau"])
        @test !(string(controller.id) in coverage["vv_absorption_plateau"])
        input=H._write(joinpath(dir, "input.toml"), H._snapshot(data))
        case=(data = data, key = "anchor", path = input)
        entry=Dict(
            "case_key"=>case.key,
            "case_sha256"=>H._sha(input),
            "x"=>x,
            "point_sha256"=>H._digest(Dict("x"=>x)),
            "reference_kind"=>"archived_solver_point",
        )
        receipt=H._write(joinpath(dir, "receipt.toml"), Dict("cases"=>[entry]))
        file=H._prepared_point(dir, case, receipt; tolerance = 1e-7)
        @test isfile(file)
        witness=H._expansion_witness(dir, case; tolerance = 1e-7)
        @test witness.point==x && witness.kind=="prevalidated_reference"
        @test TOML.parsefile(file)["origin_reference_kind"]=="archived_solver_point"
        @test H._prepared_point(dir, case, receipt; tolerance = 1e-7)==file
        for origin in ("physical_transfer_without_solver", "unrecognized_origin", nothing)
            changed=copy(entry)
            isnothing(origin) ? delete!(changed, "reference_kind") :
            (changed["reference_kind"]=origin)
            path=H._write(joinpath(dir, "origin.toml"), Dict("cases"=>[changed]))
            @test_throws ErrorException H._prepared_point(dir, case, path; tolerance = 1e-7)
            mktempdir() do fresh
                prepared=H._prepared_point(fresh, case, path; tolerance = 1e-7)
                @test TOML.parsefile(prepared)["method"]=="prevalidated_reference"
                @test TOML.parsefile(prepared)["origin_reference_kind"]==something(
                    origin,
                    "unknown",
                )
                @test H._expansion_witness(fresh, case; tolerance = 1e-7).kind=="prevalidated_reference"
                @test H._expansion_witness(fresh, case; tolerance = 1e-7).origin==something(
                    origin,
                    "unknown",
                )
            end
        end
        # Revalidating an already prepared reference must retain its deeper origin.
        for field in ("origin_reference_kind", "reference_origin")
            prepared_entry=merge(
                copy(entry),
                Dict(
                    "reference_kind"=>"prevalidated_reference",
                    field=>"physical_transfer_without_solver",
                ),
            )
            path=H._write(joinpath(dir, "reused.toml"), Dict("cases"=>[prepared_entry]))
            mktempdir() do fresh
                H._prepared_point(fresh, case, path; tolerance = 1e-7)
                witness=H._expansion_witness(fresh, case; tolerance = 1e-7)
                @test witness.kind=="prevalidated_reference"
                @test witness.origin=="physical_transfer_without_solver"
            end
        end
        bad=copy(entry)
        bad["case_sha256"]="bad"
        path=H._write(joinpath(dir, "bad.toml"), Dict("cases"=>[bad]))
        @test_throws ErrorException H._prepared_point(dir, case, path; tolerance = 1e-7)
        bad=copy(entry)
        bad["x"]=zeros(length(x))
        bad["point_sha256"]=H._digest(Dict("x"=>bad["x"]))
        H._write(path, Dict("cases"=>[bad]))
        @test_throws ErrorException H._prepared_point(dir, case, path; tolerance = 1e-7)
        bad["point_sha256"]="bad"
        H._write(path, Dict("cases"=>[bad]))
        @test_throws ErrorException H._prepared_point(dir, case, path; tolerance = 1e-7)
    end
end
