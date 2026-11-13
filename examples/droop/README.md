# Fixed-droop AC OPF examples

Three nominal-demand, single-state AC optimal power-flow models exercise exact
voltage deadbands and reactive saturation in MPCCModels. They share one 500-bus
network, fixed equipment, fixed droop slopes and fixed voltage references.
Only the symmetric deadband half-width changes.

| Name | Half-width (pu) | Historical Ipopt | Historical CCOpt |
|---|---:|---|---|
| `:zero` | 0 | Accepted | Accepted (successful reference) |
| `:narrow` | 0.005 | Accepted | 60 s time limit; 180 s retry also timed out |
| `:wide` | 0.01 | Accepted | 60 s time limit; 180 s retry also timed out |

These labels describe saved DroopOPF attempts from 26 October 2026. The two retries
started from the accepted Ipopt physical states. Ipopt used softplus smoothing of
1e-7 pu; CCOpt used exact complementarity with a numerical relaxation. They are
not identical algebraic formulations, and the timings are not a solver ranking.
Failure within a budget is not an infeasibility proof. Future solvers need not
repeat historical failures. The source campaign was still marked running at
export; this is a snapshot of completed attempts, not its final sealed report.
The historical environment was Julia 1.12.4, CCOpt 0.1.0, Ipopt 1.16.0 and
MadNLP 0.10.3 on Apple M1 with one Julia/BLAS thread.
Compact original statuses, budgets, settings and source hashes are in
[`data/provenance.json`](data/provenance.json).

## Local export verification

The model/replay suite passes 99 checks on Julia 1.10.12 and 1.12.4, and the
unchanged upstream package tests pass on Julia 1.12.4. With CCOpt 0.1.0,
MadNLP 0.10.3 and the recorded strict barrier settings, the exported zero-width
model converges and passes physical replay; both positive-width models reach
the 60-second native wall limit and fail physical acceptance. Ipopt 1.16.0
converges on both positive-width smooth models and passes the same physical
replay. These are local observations, not CI assertions or guarantees of future
solver behavior. CI contains no optimization runs.

## Construct and check a model

From the repository root:

```sh
julia --project=examples/droop -e 'using Pkg; Pkg.develop(path=pwd()); Pkg.instantiate()'
julia --project=examples/droop examples/droop/test.jl
```

```julia
include("examples/droop/model.jl")
using .DroopExamples, NLPModels, MPCCModels

data = droop_case(:narrow)
built = build_droop(data)
mpcc = built.mpcc
x = lift_state(built, data.states["reference"])
model_residuals(built, x)
replay(data, data.states["reference"])
```

`built.nlp` is an ordinary `MathOptNLPModel` built through JuMP/NLPModelsJuMP.
`built.mpcc` wraps it with explicit nonnegative variable-variable pairs in
vertical form. No solver is imported by the example model or its tests. Example
dependencies are isolated from MPCCModels' runtime dependencies. Tests check
objective/constraint evaluations, derivatives, complementarity indexing,
physical replay and deliberately corrupted points; they never assert a solver
failure or a particular locally optimal objective.

`lift_state` retains the supplied physical state by default. Model initialization
uses `project_q=true` to initialize auxiliary saturation quantities consistently
with voltage, matching the original exact-builder convention. This may change
initial Q and does not repair AC balance. `data.states["start"]` is the shared
historical physical seed, separate from the reference. Positive-width references
come from accepted smoothed Ipopt runs; the zero-width reference comes from
accepted CCOpt. They are approximate feasible points under the declared checks,
not exact arithmetic witnesses or global-optimality certificates.

## Equations and scope

With fixed lower/upper voltage knees L and U, slope m > 0 and reference Q0:

```text
lower = max(L - V, 0), upper = max(V - U, 0)
Qraw = Q0 + (lower - upper)/m
Q = clamp(Qraw, Qmin, Qmax)
```

Each positive part has two nonnegative variables with a linking equality and
zero product. Saturation has nonnegative slacks and multipliers:

```text
sl = Q - Qmin, su = Qmax - Q
Q - Qraw - ml + mu = 0
0 <= sl perpendicular to ml >= 0
0 <= su perpendicular to mu >= 0
```

For zero width, `lower-upper = Vref-V` eliminates the voltage hinges exactly.
Thus the zero-width model has 1,435 variables / 102 pairs, and each positive-width
model has 1,639 variables / 204 pairs. The ordinary constraints include polar AC
nodal balance, full pi branches with charging and fixed complex transformer taps,
both-end apparent-power ratings, angle-difference limits and fixed bus shunts.
The objective is total generation minus load, in pu active loss, including shunt
conductance losses. One bus angle is fixed to zero. Offline units remain in the
physical state vectors and have zero P/Q. No costs, outages, relief, optimized
equipment, curve design, apparent-rating circles or temporal constraints are
introduced.

Physical acceptance retains the source thresholds: 1e-6 pu nodal P/Q balance,
1e-5 pu direct exact-droop error, 1e-6 pu operating limits and 1e-6 rad angle
limits. NLP constraint residuals and complementarity products are also reported
separately; these are not stationarity certificates. `replay.jl` independently
uses complex terminal currents and direct clipping, without model callbacks.

## Optional numerical runs

Solver packages live in the separate benchmark environment:

```sh
julia --project=examples/droop/benchmark -e 'using Pkg; Pkg.develop(path=pwd()); Pkg.instantiate()'
julia --project=examples/droop/benchmark examples/droop/benchmark/run.jl zero ccopt zero.json start 60
julia --project=examples/droop/benchmark examples/droop/benchmark/run.jl narrow ccopt narrow.json start 60
julia --project=examples/droop/benchmark examples/droop/benchmark/run.jl wide ccopt wide.json reference 180
julia --project=examples/droop/benchmark examples/droop/benchmark/run.jl narrow ipopt-smooth smooth.json start 60
julia --project=examples/droop/benchmark examples/droop/benchmark/run.jl narrow ipopt-relaxed relaxed.json start 60
```

Choose `zero`, `narrow` or `wide`; `start` or the saved `reference`; and a native
seconds budget. CCOpt uses a wall-time limit, Ipopt a CPU-time limit. Receipts
retain returned states and failures, package versions, statuses, budgets,
objectives and independent residuals; existing files are never overwritten.
`ipopt-relaxed` solves the exported exact model with each product <= 1e-8; it is
a single relaxed NLP, not an exact-MPCC solver or a full homotopy comparison.
`ipopt-smooth` uses the original stable softplus law, with exact affine raw
response at zero width. Translation changes constraint ordering/representation,
so new numerical outcomes must be reported separately from historical attempts.
The 500-bus optimization runs are excluded from CI; the separate
workflow evaluates models and saved points without solver calls.

## Data and attribution

The network derives from ARPA-E Grid Optimization Competition Challenge 1,
Network Model 01 Scenario 02, distributed in
[PowerModelsSecurityConstrained.jl](https://github.com/lanl-ansi/PowerModelsSecurityConstrained.jl/tree/master/test/data/c1/scenario_02).
It is a study variant: Pmin=0, symmetric Q boxes, calibrated fixed taps/shunts and
generic static generator droop. Those settings are part of the supplied model;
replacing them with original RAW values changes the benchmark. Static generic
droop is not an AVR, transient or inverter-dynamics claim.

Equations and cases are adapted from DroopOPF.jl (`src/complementarity.jl`,
`src/physics.jl`, `src/jump.jl`, `examples/deadband_s1_s2.jl` and its saved
fixed-control comparisons). Original research archives are not included.
[`NETWORK_LICENSE.md`](data/NETWORK_LICENSE.md) and
[`DROOPOPF_LICENSE`](data/DROOPOPF_LICENSE) retain the respective BSD-3-Clause
notices. [`SHA256SUMS`](data/SHA256SUMS) covers the complete data collection.
