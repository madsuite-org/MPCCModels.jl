# Read-only iteration observer, included inside HardCaseSearch.
mutable struct SearchTrace <: CCOpt.MadNLP.AbstractUserCallback
    sample::Function
    every::Int
    last::Tuple{Int,String}
    rows::Int
    errors::Vector{String}
end

function _sample_trace!(trace::SearchTrace, ipm, mode; force = false)
    key = (ipm.cnt.k, string(typeof(mode)))
    (force || key != trace.last && ipm.cnt.k % trace.every == 0) || return true
    try
        trace.sample(ipm, string(typeof(mode)))
        trace.last = key
        trace.rows += 1
    catch err
        err isa InterruptException && rethrow()
        push!(trace.errors, sprint(showerror, err, catch_backtrace()))
    end
    return true
end

function (trace::SearchTrace)(ipm, mode::CCOpt.MadNLP.AbstractUserCallbackStatus)
    return _sample_trace!(trace, ipm, mode)
end

function _execute_traced(executor, model, data, config, directory, mask, every)
    path = joinpath(directory, "trace.tsv")
    result = Dict{String,Any}()
    open(path, "w") do io
        fields = [
            "iteration",
            "phase",
            "elapsed_seconds",
            "mu",
            "sigma_min",
            "sigma_max",
            "ipm_primal",
            "ipm_dual",
            "ipm_complementarity",
            "objective",
            "constraints",
            "bounds",
            "physical_balance",
            "complementarity",
            "volt_var",
            "volt_watt",
        ]
        println(io, join(fields, '\t'))
        flush(io)
        initial = time_ns()
        function sample(ipm, mode)
            x = zeros(get_nvar(model))
            CCOpt.MadNLP.unpack_x!(x, ipm.cb, CCOpt.MadNLP.variable(ipm.x))
            residuals = transmission_residuals(model, data, x)
            sigma = hasproperty(ipm.nlp, :σ) ? ipm.nlp.σ : Float64[]
            row = [
                ipm.cnt.k,
                mode,
                (time_ns()-initial)/1e9,
                ipm.mu,
                isempty(sigma) ? NaN : minimum(sigma),
                isempty(sigma) ? NaN : maximum(sigma),
                ipm.inf_pr,
                ipm.inf_du,
                ipm.inf_compl,
                obj(model, x),
                (getproperty(residuals, Symbol(k)) for k in fields[11:end])...,
            ]
            println(io, join(row, '\t'))
            return flush(io)
        end
        trace = SearchTrace(sample, every, (-1, ""), 0, String[])
        try
            merge!(result, executor(model, config; mask, trace))
        finally
            result["trace_rows"] = trace.rows
            result["trace_errors"] = trace.errors
        end
    end
    result["trace_file"] = "trace.tsv"
    result["trace_sha256"] = _sha(path)
    return result
end
