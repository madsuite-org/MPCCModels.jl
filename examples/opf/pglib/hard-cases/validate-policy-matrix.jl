# Validate operating references before launching the raw CCOpt policy matrix.
# julia --project=examples/opf/pglib examples/opf/pglib/hard-cases/validate-policy-matrix.jl OUT
using TOML
include("../hard-search.jl")

function validate_policy_matrix(directory)
    H=HardCaseSearch
    T=H.TransmissionOPF
    ispath(directory) && throw(ArgumentError("choose a fresh reference directory"))
    directory=abspath(directory)
    mkpath(directory)
    H._capture_environment(directory, H._environment())
    cp(@__FILE__, joinpath(directory, "validation-driver.jl"))
    cp(H._expansion_source_file(:ieee300), joinpath(directory, "source-reference.toml"))
    specs=T.application_expansion_specs(:policy_matrix; network = :ieee300)
    profile=H.solver_profile(:current)
    accepted=Dict{String,Any}[]
    candidates=Dict{String,Any}[]
    neighbors=Dict{Tuple,Any}()
    for spec in specs
        case=H._save_expansion(directory, spec)
        baseline=H._save_expansion(directory, spec; laws = :dispatchable)
        H.run_trial(
            baseline.data,
            nothing,
            profile,
            joinpath(directory, "counterfactuals", baseline.key);
            role = "reference_counterfactual",
            case_file = baseline.path,
        )
        source=H._expansion_source(case.data, spec)
        H._source_point_record(directory, case, source; tolerance = 1e-7)
        l=T.transmission_layout(case.data)
        paths=String[]
        function attempt(x, label)
            mask=Vector{Bool}(x[l.r] .> x[l.s])
            path=joinpath(directory, "references", case.key*"-"*label)
            H.run_trial(
                case.data,
                x,
                profile,
                path;
                mask,
                role = "reference",
                start_label = label,
                case_file = case.path,
                tolerance = 1e-7,
                provenance = Dict(
                    "spec"=>H._plain(spec),
                    "source_receipt_sha256"=>source.source_sha256,
                ),
            )
            push!(paths, path)
            return H.verified_point(path; tolerance = 1e-7)
        end
        neighbor_key=(spec.kind, source.family, source.level)
        point=attempt(source.point, "operating")
        selected=last(paths)
        if isnothing(point) && haskey(neighbors, neighbor_key)
            neighbor=neighbors[neighbor_key]
            point=attempt(
                T.transmission_start(case.data, neighbor.data, neighbor.point),
                "neighbor",
            )
            selected=last(paths)
        end
        if isnothing(point)
            path=joinpath(directory, "screening", case.key)
            H.run_trial(
                case.data,
                nothing,
                H.solver_profile(:current; max_iter = 100),
                path;
                role = "screening",
                case_file = case.path,
            )
            record=H.read_trial(path)
            if get(record.result, "has_solution", false)
                x=H._point(path)
                if all(isfinite, x)
                    point=attempt(x, "screened_iterate")
                    selected=last(paths)
                end
            end
        end
        info=Dict{String,Any}(
            "case_key"=>case.key,
            "spec"=>H._plain(spec),
            "case_sha256"=>H._sha(case.path),
            "verified"=>!isnothing(point),
            "attempts"=>relpath.(paths, Ref(directory)),
        )
        if !isnothing(point)
            neighbors[neighbor_key]=(data = case.data, point = point)
            info["coverage"]=H._plain(T.application_policy_coverage(case.data, point))
            entry=merge(
                copy(info),
                Dict(
                    "x"=>point,
                    "point_sha256"=>H._digest(Dict("x"=>point)),
                    "reference_kind"=>"selected_sector_solver_point",
                    "reference_trial"=>relpath(selected, directory),
                    "source_fingerprint"=>H._environment()["source_fingerprint"],
                ),
            )
            push!(accepted, entry)
        end
        push!(candidates, info)
        H._write(joinpath(directory, "candidates.toml"), Dict("cases"=>candidates))
        H._write(
            joinpath(directory, "references.toml"),
            Dict("schema"=>1, "cases"=>accepted),
        )
        cv=get(info, "coverage", Dict())
        println((
            case = case.key,
            verified = !isnothing(point),
            strict_vw = get(cv, "strict_vw_binding", []),
            injection = get(cv, "vv_injection_plateau", []),
            absorption = get(cv, "vv_absorption_plateau", []),
            lower_vw = get(cv, "vw_lower_plateau", []),
        ))
        flush(stdout)
    end
    return nothing
end
if abspath(PROGRAM_FILE)==abspath(@__FILE__)
    length(ARGS)==1 || error("expected OUT")
    validate_policy_matrix(only(ARGS))
end
