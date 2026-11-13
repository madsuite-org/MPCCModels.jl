using Test, TOML
include("hard-search.jl")
using .HardCaseSearch

@testset "Hard-case inputs and controlled profiles" begin
    base = capability_case(1.0)
    changed = capability_case(0.82)
    @test changed.buses == base.buses
    @test changed.branches == base.branches
    @test changed.generators == base.generators
    for i in 1:3
        c, b = changed.controllers[i], base.controllers[i]
        @test c.p_available == b.p_available
        @test c.vv == b.vv && c.vw == b.vw
        @test c.qmin == b.qmin && c.qmax == b.qmax
        @test c.smax == (i == 3 ? 0.82*b.smax : b.smax)
    end
    current = solver_profile(:current)
    for (name, field, value) in (
        (:looser_inner, :tol, 1e-8),
        (:ratio_one, :sigma_mu_ratio, 1.0),
        (:higher_floor, :sigma_min, 1e-8),
    )
        profile = solver_profile(name)
        @test getproperty(profile, field) == value
        @test all(
            k -> getproperty(profile, k) == getproperty(current, k),
            setdiff(collect(keys(current)), [:name, field]),
        )
    end
    @test_throws ArgumentError capability_case(0)
    @test_throws ArgumentError solver_profile(:missing)
    @test_throws ArgumentError solver_profile(:current; max_iter = 0)
end

@testset "Recorder retains exceptions, failed points and unavailable verification" begin
    mktempdir() do dir
        data = capability_case(0.82)
        profile = solver_profile(:current; max_iter = 1)
        throwing(model, config; mask = nothing) = error("injected solver exception")
        failure(model, config; mask = nothing) = Dict(
            "status"=>"TEST_LIMIT",
            "solver_success"=>false,
            "iterations"=>1,
            "solution"=>copy(HardCaseSearch.get_x0(model)),
            "point_source"=>"returned_solution",
        )
        exception_dir = joinpath(dir, "exception")
        exception = run_trial(data, nothing, profile, exception_dir; executor = throwing)
        @test exception["classification"] == "exception"
        @test occursin("injected solver exception", exception["exception"])
        @test exception["state"] == "complete"
        @test !exception["has_solution"]
        @test isfile(joinpath(exception_dir, "solver.log"))
        @test isnothing(verified_point(exception_dir))
        failed_dir = joinpath(dir, "failure")
        failed = run_trial(data, nothing, profile, failed_dir; executor = failure)
        @test failed["classification"] == "solver_failure"
        @test failed["has_solution"]
        @test !failed["physically_feasible"]
        @test isnothing(verified_point(failed_dir))
        saved = read_trial(failed_dir)
        @test saved.result["status"] == "TEST_LIMIT"
        @test saved.request["start_label"] == "custom"
        @test saved.request["profile"]["max_iter"] == 1
        restored = load_case(
            joinpath(failed_dir, "input.toml");
            expected_sha = saved.request["case_sha256"],
        )
        @test restored.buses == data.buses
        @test restored.branches == data.branches
        @test restored.controllers == data.controllers
        @test_throws ArgumentError run_trial(
            data,
            nothing,
            profile,
            failed_dir;
            executor = failure,
        )
        # Unknown witness status is not promoted to an infeasibility claim.
        @test !haskey(failed, "infeasible_problem")
        # Interrupted markers survive; resume creates a new attempt.
        marker = copy(saved.result)
        marker["state"] = "running"
        HardCaseSearch._write(joinpath(failed_dir, "result.toml"), marker)
        @test read_trial(failed_dir).result["state"] == "running"
        parent = joinpath(dir, "attempts")
        mkpath(joinpath(parent, "case-attempt-001"))
        next, done = HardCaseSearch._attempt(parent, "case"; resume = true)
        @test endswith(next, "case-attempt-002") && !done
        # Hashes are checked before replay or witness reuse.
        open(joinpath(failed_dir, "solution.toml"), "a") do io
            println(io, "# changed bytes")
        end
        @test_throws ErrorException read_trial(failed_dir)
    end
end

@testset "Small real search continues and safely resumes" begin
    mktempdir() do directory
        output = joinpath(directory, "search")
        kwargs = (
            capabilities = [0.82],
            starts = [:flat, :witness],
            profiles = [:current],
            max_iter = 1,
            max_wall_time = 10.0,
            warmup = false,
            progress = false,
        )
        rows = run_search(output; kwargs...)
        @test length(rows) == 2
        @test all(
            r -> r["classification"] in (
                "success",
                "solver_failure",
                "physical_violation",
                "exception",
                "unavailable_start",
            ),
            rows,
        )
        @test isfile(joinpath(output, "cases.tsv"))
        @test isfile(joinpath(output, "environment", "Manifest.toml"))
        @test isfile(
            joinpath(output, "source", "examples", "opf", "pglib", "hard-search.jl"),
        )
        @test_throws ArgumentError run_search(output; kwargs...)
        files = Dict(
            r["trial"]=>read(joinpath(output, r["trial"], "result.toml"), String) for
            r in rows
        )
        again = run_search(output; kwargs..., resume = true)
        @test length(again) == 2
        @test all(
            r ->
                read(joinpath(output, r["trial"], "result.toml"), String) ==
                files[r["trial"]],
            again,
        )
        @test_throws ErrorException run_search(output; kwargs..., resume = true, seed = 1)
        raw = only(filter(r -> r["start"] == "flat", rows))
        replay = replay_trial(joinpath(output, raw["trial"]), joinpath(directory, "replay"))
        @test replay["state"] == "complete"
        @test read_trial(joinpath(directory, "replay")).request["profile"]["max_iter"] == 1
        missing_start = only(filter(r -> r["start"] == "witness", rows))
        if missing_start["classification"] == "unavailable_start"
            @test_throws ErrorException replay_trial(
                joinpath(output, missing_start["trial"]),
                joinpath(directory, "no-start"),
            )
        end
    end
end

@testset "Curated feasible witness and preserved raw outcomes" begin
    fixture = TOML.parsefile(HardCaseSearch.evidence_file("ieee118-capability-082.toml"))
    data = capability_case(fixture["factor"])
    @test fixture["source_file_sha256"] ==
          HardCaseSearch._sha(joinpath(@__DIR__, "data", fixture["source_file"]))
    model = HardCaseSearch.TransmissionOPFModel(data)
    witness = fixture["witness"]["x"]
    bits_sha(x) = bytes2hex(HardCaseSearch.sha256(join(bitstring.(Float64.(x)), "\n")))
    @test bits_sha(witness) == fixture["witness"]["point_bits_sha256"]
    metrics = HardCaseSearch._metrics(model, data, witness, fixture["witness"]["tolerance"])
    @test metrics["physically_feasible"]
    @test metrics["objective"] ≈ fixture["witness"]["objective"] atol=1e-5
    @test abs(metrics["controllers"][3]["margins"]["capability"]) < 1e-7
    @test abs(metrics["controllers"][3]["margins"]["volt_watt"]) < 1e-7
    @test metrics["controllers"][3]["margins"]["availability"] > 1e-3
    for trial in fixture["trials"]
        @test bits_sha(trial["x"]) == trial["point_bits_sha256"]
        @test bits_sha(trial["start"]) == trial["start_bits_sha256"]
        actual = HardCaseSearch._metrics(model, data, trial["x"], 1e-5)
        @test actual["physically_feasible"] == trial["physically_feasible"]
        for (key, value) in trial["residuals"]
            @test actual["residuals"][key] ≈ value atol=1e-10
        end
    end
    # Feasibility does not require a success termination, and it must not turn
    # the failed termination into a successful homotopy record.
    mktempdir() do directory
        feasible_failure(m, c; mask = nothing) = Dict(
            "status"=>"TEST_LIMIT",
            "solver_success"=>false,
            "iterations"=>1,
            "solution"=>copy(witness),
            "point_source"=>"returned_solution",
        )
        trial = joinpath(directory, "feasible-failure")
        result = run_trial(
            data,
            nothing,
            solver_profile(:current),
            trial;
            executor = feasible_failure,
        )
        @test result["classification"] == "solver_failure"
        @test result["physically_feasible"]
        @test verified_point(trial) ≈ witness
        case = HardCaseSearch._save_case(directory, 0.82)
        @test HardCaseSearch._register_witness(directory, case, trial; tolerance = 1e-7) ≈
              witness
        other_case = HardCaseSearch._save_case(directory, 0.84)
        @test_throws ErrorException HardCaseSearch._register_witness(
            directory,
            other_case,
            trial;
            tolerance = 1e-7,
        )
    end
end

@testset "Simultaneous-transition case invariants and independent activity" begin
    T = HardCaseSearch.TransmissionOPF
    base = T.pglib_control_case(:ieee118; targets = [], network_targets = [])
    data = transition_case()
    @test data.buses == base.buses
    @test data.branches == base.branches
    @test length(data.generators) == 54
    for (g, b) in zip(data.generators, base.generators)
        @test g == (g.id == 45 ? merge(b, (qmax = 0.35,)) : b)
    end
    @test all(c -> c.bus == 95, data.controllers)
    @test data.buses[data.generators[45].bus].id == 100
    @test data.generators[45].id == 45
    @test length(T.transmission_layout(data).r) == 18
    for (c, b) in zip(data.controllers, base.controllers)
        @test (c.smax, c.p_available, c.qmin, c.qmax, c.cost, c.quadratic_cost) ==
              (b.smax, b.p_available, b.qmin, b.qmax, b.cost, b.quadratic_cost)
        @test c.vv.knots[3] == c.vw.knots[1] == 1.02
        @test c.vw.values[1] ≈ c.p_available
    end
    l = T.transmission_layout(data)
    x = copy(HardCaseSearch.get_x0(T.TransmissionOPFModel(data)))
    x[l.v[95]] = 1.02
    x[l.qg[45]] = 0.35
    activity = transition_activity(data, x)
    @test activity["simultaneous_controllers"] == 3
    @test activity["q45_binding"]
    @test !HardCaseSearch._metrics(T.TransmissionOPFModel(data), data, x, 1e-5)["physically_feasible"]
    separated = transition_case(; offset = 1e-4)
    @test transition_activity(separated, x)["simultaneous_controllers"] == 0
    @test separated.controllers[1].vv == data.controllers[1].vv
    @test separated.generators == data.generators
    @test_throws ArgumentError transition_case(; qmax = -0.5)
    @test_throws ArgumentError transition_case(; knee = 0.95)
    @test_throws ArgumentError transition_case(; offset = Inf)
    @test_throws ArgumentError transition_activity(data, x; q_tolerance = 0)
    mktempdir() do dir
        output = joinpath(dir, "search")
        kw = (
            offsets = [0.0],
            qmaxes = [0.35],
            seeds = [7, 8],
            max_iter = 1,
            max_wall_time = 10.0,
            progress = false,
        )
        rows = run_transition_search(output; kw...)
        @test length(rows) == 5
        @test count(r -> r["start"] == "flat", rows) == 1
        @test sort([r["seed"] for r in rows if r["start"] == "perturbed_neighbor"]) == [7, 8]
        @test all(r -> !r["witness_available"], rows)
        @test any(r -> r["classification"] == "unavailable_start", rows)
        files = Dict(
            r["trial"]=>read(joinpath(output, r["trial"], "result.toml")) for r in rows
        )
        again = run_transition_search(output; kw..., resume = true)
        @test all(
            r -> read(joinpath(output, r["trial"], "result.toml")) == files[r["trial"]],
            again,
        )
        @test_throws ErrorException run_transition_search(
            output;
            kw...,
            resume = true,
            knee = 1.03,
        )
    end
end

@testset "Archived transition witnesses and ratio-one raw points" begin
    fixture = TOML.parsefile(HardCaseSearch.evidence_file("ieee118-transitions-q45.toml"))
    @test fixture["source_file_sha256"] ==
          HardCaseSearch._sha(joinpath(@__DIR__, "data", fixture["source_file"]))
    @test length(fixture["cases"]) == 9
    @test length(fixture["trials"]) == 6
    bits_sha(x) = bytes2hex(HardCaseSearch.sha256(join(bitstring.(Float64.(x)), "\n")))
    for case in fixture["cases"]
        data = transition_case(;
            knee = case["knee"],
            offset = case["offset"],
            qmax = case["qmax"],
        )
        @test bytes2hex(
            HardCaseSearch.sha256(HardCaseSearch._toml(HardCaseSearch._snapshot(data))),
        ) == case["input_snapshot_sha256"]
        witness = case["witness"]
        @test bits_sha(witness["start"]) == witness["start_bits_sha256"]
        @test bits_sha(witness["x"]) == witness["point_bits_sha256"]
        model = HardCaseSearch.TransmissionOPFModel(data)
        metrics = HardCaseSearch._metrics(model, data, witness["x"], 1e-7)
        @test metrics["physically_feasible"]
        @test metrics["objective"] ≈ witness["objective"] atol = 1e-5
        @test all(c -> c["margins"]["capability"] > 0.1, metrics["controllers"])
        activity = transition_activity(data, witness["x"])
        @test activity == case["witness_activity"]
        @test activity["q45_binding"]
        @test activity["simultaneous_controllers"] == (case["offset"] == 0 ? 3 : 0)
        @test all(d -> d <= 1e-6, activity["vw_knee_distances"])
        for (key, value) in witness["residuals"]
            @test metrics["residuals"][key] ≈ value atol = 1e-10
        end
    end
    sensitivity = fixture["q_sensitivity"]["cases"]
    @test [r["qmax"] for r in sensitivity] == [0.349, 0.35, 0.351]
    @test sensitivity[1]["objective"] >
          sensitivity[2]["objective"] >
          sensitivity[3]["objective"]
    for row in sensitivity
        data = transition_case(; qmax = row["qmax"])
        witness = row["witness"]
        @test bits_sha(witness["x"]) == witness["point_bits_sha256"]
        actual = HardCaseSearch._metrics(
            HardCaseSearch.TransmissionOPFModel(data),
            data,
            witness["x"],
            1e-7,
        )
        @test actual["physically_feasible"]
        @test actual["objective"] ≈ row["objective"] atol = 1e-5
        @test transition_activity(data, witness["x"])["q45_binding"]
    end
    for trial in fixture["trials"]
        data = transition_case(;
            knee = trial["knee"],
            offset = trial["offset"],
            qmax = trial["qmax"],
        )
        @test trial["profile"]["name"] == "ratio_one"
        @test trial["profile"]["sigma_mu_ratio"] == 1.0
        @test bits_sha(trial["start"]) == trial["start_bits_sha256"]
        @test bits_sha(trial["x"]) == trial["point_bits_sha256"]
        actual = HardCaseSearch._metrics(
            HardCaseSearch.TransmissionOPFModel(data),
            data,
            trial["x"],
            trial["tolerance"],
        )
        @test actual["physically_feasible"] == trial["physically_feasible"]
        for (key, value) in trial["residuals"]
            @test actual["residuals"][key] ≈ value atol = 1e-10
        end
    end
end
