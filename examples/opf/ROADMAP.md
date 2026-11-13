# Balanced AC OPF contribution roadmap

Development branch: `codex/opf-volt-var-watt`.

## Scope

The initial scope was a self-contained two-bus AC optimal power flow example with
fixed volt-var and volt-watt curves. Port the exact nonnegative hinge pairs
from [BMOPFTools.jl PR #383](https://github.com/frederikgeth/BMOPFTools.jl/pull/383)
(source commit `faf3d455381e15b651808c489237c0dd921d7cf7`).
Use `ADNLPModels` and the existing `MPCCModel(nlp, ind_vcc1, ind_vcc2)`
constructor, following the package's small model constructors. Keep power-system
dependencies and solver dependencies out of the package runtime.

The network is synthetic and uses positive-sequence AC equations in per unit.
Volt-var fixes reactive injection; volt-watt is an active-power upper bound,
alongside availability and the inverter apparent-power limit. Fixed curves do
not implement controller tuning, dynamics, hysteresis, or additional priority
logic. Each operating case must identify a feasible physical reference point;
these reference points are not optimality certificates.

The completed expansion generalizes these blocks to explicit connected networks
and multiple controllers. It adds independent coverage targets and a separate
solver integration gate, with 37 named cases. Equipment-limited and larger
matrix studies remain follow-up scope below.

## Milestones

- [x] Review the package API, test style, and source hinge formulation.
- [x] Create a dedicated development branch and record the implementation scope.
- [x] Add the AC OPF constructor, hinge equations, and documented variable ordering.
- [x] Add cases for reactive injection/absorption, deadband, saturation,
      volt-watt curtailment, and every curve breakpoint.
- [x] Verify physical feasibility, exact control values, complementarity pairs,
      active bounds, and derivatives in the package test suite.
- [x] Add runnable example instructions and a documentation tutorial.
- [x] Run the complete tests, documentation checks, and optional CCOpt solves;
      record results and commit the finished contribution.

## Validation and review

The tests must evaluate AC balance independently from the model equations,
compare the hinge curves with direct piecewise evaluations, check both sides
of every breakpoint, and check nonnegativity as well as complementarity.
Finite differences must cover the objective, constraint Jacobian, and
Lagrangian Hessian at a point away from the reference start. Tests also need
to distinguish a volt-watt cap from a forced output equality and reject points
with violated network or inverter limits even when the hinge pairs are exact.

Keep solver experiments separate from model correctness tests. Report original
AC constraint violations, variable-bound violations, complementarity residuals,
and direct control-curve errors. Do not inherit solver-performance claims or
historical numerical results from the draft PR.

## Follow-up scope

The completed milestones above describe the initial two-bus contribution.
The [review and case-design matrix](CASE_DESIGN.md) records the next stage.

- [x] Validate custom starts after conversion to the model's numeric type.
- [x] Repair and test the inherited split NLP API failures exposed by this model.
- [x] Record and assert achieved curve regions and active constraints at solutions.
- [x] Add the missing saturated-VV/flat-VW interior, the early VW ramp with
      availability binding, and the availability/VW crossover.
- [x] Add several positions on each finite curve segment and solved neighbors
      of every breakpoint.
- [x] Generalize example data and index maps for several buses and controllers,
      preserving the existing constructors and named cases.
- [ ] Add isolated binding capability, branch-end, voltage, and source-bound cases.
- [x] Add the first two-controller fork, chain and colocated-controller cases.
- [ ] Add three-controller mixed-limit cases, heterogeneous colocated profiles,
      and a small mesh with interacting limits.
- [ ] Audit compatible combinations of curve region, limiting constraint,
      controller layout, and objective before extending the benchmark set.
- [ ] Port selected unbalanced BMOPF cases in a separate contribution.

Control-priority policies remain a separate modeling extension. Equipment limits
in this matrix continue to apply alongside the fixed reactive-power law.

## Validation record: initial two-bus contribution

- The mixed linear/nonlinear OPF exposed an existing complementarity-Jacobian
  structure bug. A separate prerequisite commit switches both sides to the full
  underlying Jacobian and adds a regression in Float32 and Float64.
- Complete `Pkg.test()` passes on Julia 1.10.12 and 1.12.6: 802 assertions
  (48 lifted-model, 118 MPCC API, and 636 OPF). The model uses coordinate arrays
  for its linear constraints, so the example needs no extra standard-library
  imports in the isolated test environment.
- All 12 Float64 reference points have maximum residual below `4e-15`.
  These are feasibility checks, not solve-performance results.
- The Documenter build passes, including all executable OPF examples and cross
  references. External link checking was disabled for the offline build;
  the normal documentation configuration still enables it. The build script
  now sets its root explicitly so it works from the repository root.
- The documented example environment resolves from a fresh manifest. With
  Julia 1.12.6, CCOpt 0.1.0, and MadNLP 0.10.1, `solve.jl all` returns
  `SOLVE_SUCCEEDED` for all 12 cases from the default flat starts. Maximum
  residuals across these runs are:

  | Check | Maximum residual (per unit) |
  | --- | ---: |
  | Original NLP constraints | `2.28e-15` |
  | Variable bounds | `0` |
  | Complementarity minimum residual | `3.11e-7` |
  | Direct volt-var error | `2.12e-6` |
  | Direct volt-watt cap violation | `4.97e-6` |

  The runner checks all five against `1e-5` and preserves the solver status.
  Relaxation-update options are supplied through `CCOpt.RelaxationOptions`;
  MadNLP tolerances and bound settings are supplied to `RelaxationSolver`.
  These experiments establish numerical feasibility, not global optimality
  or a performance comparison with other solvers.
- New Julia example and test files are formatted with the repository's
  JuliaFormatter configuration. `git diff --check` passes.

## Generalized examples

- Input conversion and split-API fixes are committed separately. Split
  constraint/Jacobian values and forward/transpose products are checked against
  full evaluations in Float32 and Float64.
- `data.jl`, `cases.jl` and `diagnostics.jl` provide validated explicit records,
  computed maps, generic constant-extrapolated hinges, and independent targets.
  The convenience model constructor and original variable ordering remain.
- The 37-case matrix contains 34 single-controller cases and three joint
  two-controller studies. VV/VW can also be enabled independently; tests cover
  heterogeneous knot counts, device order, bus relabeling, and source devices.
- Hardware Q bounds are wider than the VV plateaus, avoiding redundant bounds
  without changing the exact controlled feasible set. The former constraints
  and coverage audit in `CASE_DESIGN.md` are explicitly historical.
- Ordinary tests require no solver. `test-solves.jl` and a separate CI job
  check original feasibility and achieved coverage from flat starts.
- Final `Pkg.test()` passes on Julia 1.10.12 and 1.12.6: **2050 assertions**
  (48 lifted-model, 134 MPCC API, 1868 OPF). The OPF tests include constant
  curves with zero hinge weights and conversion/representation failures.
- The optional solved-coverage gate passes **151 assertions across 37 cases**
  on Julia 1.12.6 with CCOpt 0.1.0 and MadNLP 0.10.1. Every accepted final point
  satisfies all original feasibility checks at `1e-5` and its per-device targets.
  One local run needed conditional branch polishing at `vw_lower_knee`.
  The branch comes from the homotopy iterate, not a reference or target; both
  stages' statuses, residuals and coverage are retained. This is selected-sector
  refinement, not a full MPCC stationarity certificate.
- The example runner uses `tol = 1e-10`, relaxation floor `1e-14`, proportional
  relaxation/barrier ratio `0.01`, and per-unit initialization bound push/factor
  `1e-6`. The final physical and coverage tolerances have not been loosened.
- Documenter builds successfully with the executable 37-case reference and
  coverage checks, the multiple-controller tutorial and custom-data example.
  External link checks were disabled for the offline build; normal CI retains
  them. Local Markdown links and `git diff --check` pass.
- A separate Julia 1.12 CI job runs the solver integration gate. Its workflow
  has been added; no claim of a remote CI run is made before the PR is opened.

## PGLib transmission expansion

The next stage is tracked in the [PGLib roadmap](pglib/ROADMAP.md), including
canonical import validation, matched control overlays, solved regime coverage
and sensitivity checks for binding equipment limits.

The transmission expansion now includes independently validated IEEE 300 and
three network-specific application families. Its first 36-request matrix retains
16 solver failures on known-feasible inputs, an original-law accuracy gap and
unresolved reactive stress inputs separately. See the [IEEE 300 guide](pglib/IEEE300.md)
for measured physical coverage, local limit responses and the next case matrix.
