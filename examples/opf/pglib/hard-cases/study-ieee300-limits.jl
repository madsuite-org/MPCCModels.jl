# Selected-sector local physical sensitivities, separate from raw CCOpt trials.
# Include after hard-search.jl to reuse the case recipe, or run with SEARCH_DIR OUT FAMILY.
function ieee300_sensitivity_case(family::Symbol; modified = false)
    T=HardCaseSearch.TransmissionOPF
    family in (:renewable_surplus, :export_corridor) ||
        throw(ArgumentError("no verified sensitivity recipe for this family"))
    return if !modified
        T.application_case(family; network = :ieee300, level = :severe)
    elseif family==:renewable_surplus
        base=T.application_case(family; network = :ieee300, level = :severe)
        T.transmission_overlay(
            base;
            controllers = [merge(c, (smax = 1.1*c.smax,)) for c in base.controllers],
            name = Symbol(base.name, "_oversized"),
        )
    else
        @assert family==:export_corridor
        T.application_case(
            family;
            network = :ieee300,
            level = :severe,
            parameters = (export_rating = 1.0,),
        )
    end
end

function study_ieee300_limits(source, out, family::Symbol)
    H=HardCaseSearch
    T=H.TransmissionOPF
    family_arg=string(family)
    key="$(family)-severe-both"
    reference_input=joinpath(source, "cases", key, "input.toml")
    original=H.load_case(reference_input)
    case=(data = original, key = key, path = reference_input)
    witness=H._witness_reference(source, case; tolerance = 1e-7)
    @assert !isnothing(witness)
    x=witness.point
    l=T.transmission_layout(original)
    mask=Vector{Bool}(x[l.r] .> x[l.s])
    H._capture_environment(out, H._environment())
    driver=joinpath(out, "study-driver-"*H._sha(@__FILE__)[1:12]*".jl")
    isfile(driver) || cp(@__FILE__, driver)
    for modified in (false, true)
        data=ieee300_sensitivity_case(family; modified)
        label=modified ? "modified" : "reference"
        path=joinpath(out, "$(family)-$(label)")
        result=H.run_trial(
            data,
            x,
            H.solver_profile(:current),
            path;
            role = "limit_sensitivity",
            start_label = "verified_reference",
            tolerance = 1e-7,
            mask,
            provenance = Dict(
                "family"=>family_arg,
                "label"=>label,
                "source_input_sha256"=>H._sha(reference_input),
                "source_witness"=>witness.trial,
            ),
        )
        point=H.verified_point(path; tolerance = 1e-7)
        if !isnothing(point)
            H._write(joinpath(path, "coverage.toml"), T.application_coverage(data, point))
        end
        println((
            family,
            label,
            status = result["status"],
            feasible = !isnothing(point),
            objective = get(result, "objective", NaN),
        ))
    end
    return nothing
end

if abspath(PROGRAM_FILE)==abspath(@__FILE__)
    include("../hard-search.jl")
    length(ARGS)==3 || error("expected SEARCH_DIR OUT FAMILY")
    study_ieee300_limits(ARGS[1], ARGS[2], Symbol(ARGS[3]))
end
