# Review and matrix for balanced AC OPF cases

Review baseline: `116f650` on `codex/opf-volt-var-watt`, 24 October 2026.
This note retains the baseline review and tracks the resulting expansion.
The input/split-API fixes, data-driven constructor, computed layout, actual
coverage checks, missing single-controller regimes, ramp strata, knot neighbors,
and M1/M2/M5 studies are now implemented. There are 37 named cases.
Equipment-limited and remaining M cases are still design targets. Current
validation results are recorded in [ROADMAP.md](ROADMAP.md).

## Historical baseline review: correctness and package consistency

The branch uses the package's existing design: an `ADNLPModel` supplies the
smooth NLP and `MPCCModel(nlp, ind_vcc1, ind_vcc2)` supplies variable-variable
complementarity. The eight linear constraints are represented by coordinate
arrays. There is no new runtime dependency, new MPCC subtype, or solver
dependency in the core tests. The full-Jacobian structure fix is consistent
with the full-Jacobian triplet indices stored by the MPCC constructors.

Review found no error in the two-bus AC power signs, constant extrapolation of
the curves, hinge equations, or distinction between a volt-watt cap and output
equality. Independent complex-phasor and finite-difference tests pass.
The review reran all 802 package assertions on Julia 1.12.6 and all twelve
CCOpt solves; every solve returned `SOLVE_SUCCEEDED`.

### Baseline findings (now fixed)

1. **Validate starting values after conversion.** `BalancedACOPFModel` checks
   `isfinite` before `T.(x0)`. For example,
   `BalancedACOPFModel(Float32; x0 = fill(1e40, 18))` currently constructs a
   model with infinite starting values. Convert first, then check finiteness;
   add an overflow regression alongside the existing NaN test.
2. **Validate achieved coverage in the solve runner.** `solve.jl` checks solver
   status and numerical feasibility, but never checks the intended curve
   region or binding constraint. The tests check constructed reference points.
   A different feasible local solution can therefore pass without fulfilling
   the case's intended coverage. Add separate target metadata and compare it
   with an independently classified solution.
3. **Audit the split NLP API before claiming general compatibility.** The new
   example exposes existing errors in `src/mpcc/api.jl`:
   `cons_nln!` reads an undefined `_c_lin`, `jtprod_nln!` writes an undefined
   `Jv`, and `jac_nln_coord!` calls `jac_lin_coord!` with a nonlinear-sized
   buffer. All three failures reproduce on the example. These lines are unchanged by
   this branch and do not affect the current full-Jacobian solve path. Track
   repairs and split-versus-full API regression tests separately from the
   power-system case expansion.

### Coverage limitations

The baseline constructor rebuilt fixed data from a case name and used fixed
variable ranges `7:12` and `13:18`. The expansion now exposes reusable records,
computed maps, and multiple controllers while preserving the original layout.

The capability limit is mathematically unreachable, not merely slack in the
observed solutions: `p <= 0.8` and `abs(q) <= 0.3` imply
`p^2 + q^2 <= 0.73 < smax^2 = 1`. The receiving-end apparent power satisfies
`abs(S10) <= sqrt(0.4^2 + 0.4^2) < 0.566`, well below the 1.5 rating.
Since every source voltage is below 1.18 and `v >= 0.88`, the sending-end power
is below `1.18 / 0.88 * sqrt(0.32) < 0.76`, also below its rating and the source
P/Q box bounds. New data are needed to activate these limits.

The baseline reactive bounds equaled the volt-var plateau outputs. A tight reactive bound
on a plateau is therefore implied by the control law; it is not evidence of
independent capability competition. Keep curve saturation and hardware limits
as distinct coverage labels. The generalized defaults now use wider hardware
Q bounds, removing this redundancy from the shipped cases.

## Historical baseline audit: twelve observed solutions

Audit configuration: Julia 1.12.6, CCOpt 0.1.0, MadNLP 0.10.1, the settings in
`solve.jl`, default flat starts. Voltage classification tolerance was `1e-6`;
power feasibility and cap tightness use `1e-5`. These classify numerical
neighborhoods of knots, not exact biactivity of a relaxed solver iterate.

| Case | Observed volt-var position | Observed volt-watt position | Tight active-power limit |
| --- | --- | --- | --- |
| `low_voltage_saturation` | Injection plateau | Upper plateau | Availability |
| `reactive_injection` | Injection ramp | Upper plateau | Availability |
| `deadband` | Deadband | Upper plateau | Availability |
| `reactive_absorption` | Absorption ramp | Upper plateau | Availability |
| `curtailment` | Absorption plateau | Descending ramp | Volt-watt |
| `high_voltage_saturation` | Absorption plateau | Lower plateau | Volt-watt |
| `vv_lower_knee` | First volt-var knot | Upper plateau | Availability |
| `vv_deadband_lower` | Second volt-var knot | Upper plateau | Availability |
| `vv_deadband_upper` | Third volt-var knot | Upper plateau | Availability |
| `vv_upper_knee` | Fourth volt-var knot | Upper plateau | Availability |
| `vw_upper_knee` | Absorption plateau | First volt-watt knot | Availability |
| `vw_lower_knee` | Absorption plateau | Second volt-watt knot | Volt-watt |

All twelve achieved their intended voltage neighborhoods in this run. All
five physical residual checks were below `5e-6`. The smallest observed physical
slacks across the twelve runs were:

| Constraint | Minimum slack | Units |
| --- | ---: | --- |
| Inverter apparent-power limit | 0.14560 | per-unit apparent power |
| Sending-end branch rating | 0.92188 | per-unit apparent power |
| Receiving-end branch rating | 0.93431 | per-unit apparent power |
| Lower voltage bound | 0.04000 | per-unit voltage |
| Upper voltage bound | 0.04000 | per-unit voltage |
| Angle bound | 0.26461 | radians |
| Source active-power box | 1.60327 | per-unit active power |
| Source reactive-power box | 1.57722 | per-unit reactive power |

## Matrix axes

Treat a case as a combination of independently described components:

| Axis | Choices | What it tests |
| --- | --- | --- |
| Network | Two buses; three-bus chain; three-bus fork; small mesh | Voltage coupling and competition for transfer capacity |
| Controller layout | One; two on separate buses; several along a feeder; several at one bus | Indexing, aggregation, and interaction |
| Controller modes | VV only; VW only; both | Different pair counts and optional control blocks |
| Profiles | Aligned; shifted; different slopes/ratings; overlapping VV/VW ramps | Which joint regimes are attainable |
| Curve position | Plateau; ramp interior; deadband; near a knot; at a knot | Smooth sectors and biactive boundaries |
| Limiting constraint | Availability; VW cap; inverter capability; branch end; voltage; source box | Different optimal active sets |
| Objective | Net import; procurement plus device costs; losses | Which limit opposes an improving dispatch move |
| Initial point | Flat; feasible reference; deterministic perturbed start | Dependence on initialization and alternative local solutions |

Generate a compatibility mask before selecting cases. Mark combinations as
verified, planned, unverified, or mathematically incompatible. A failed solve
is not a proof of infeasibility. Aim for pairwise coverage of compatible axes,
with additional explicit cases for coactive constraints and simultaneous knots.
Do not generate the full Cartesian product indiscriminately.

## Matrix A: joint curve regions for one controller

For the current profile, the same voltage feeds both curves. The strict
interior compatibility matrix is:

| Volt-var region | VW upper plateau, v < 1.07 | VW ramp, 1.07 < v < 1.12 | VW lower plateau, v > 1.12 |
| --- | --- | --- | --- |
| Injection plateau, v < 0.94 | Verified | Incompatible | Incompatible |
| Injection ramp, 0.94 < v < 0.98 | Verified | Incompatible | Incompatible |
| Deadband, 0.98 < v < 1.02 | Verified | Incompatible | Incompatible |
| Absorption ramp, 1.02 < v < 1.06 | Verified | Incompatible | Incompatible |
| Absorption plateau, v > 1.06 | Added: `saturated_var_flat_watt` | Verified, VW tight | Verified |

The joint interior `1.06 < v < 1.07`, absent from the baseline, is now covered
at `v = 1.065`. Endpoint cases alone do not cover it.

Also split the descending VW ramp by the *binding power limit*. With
availability 0.8, the cap crosses availability at `v = 1.0825`:

| Additional target | Suggested witness voltage | Expected power-limiting status |
| --- | ---: | --- |
| Saturated VV, flat VW | 1.065 | Availability tight, VW slack |
| Descending VW, availability still tighter | 1.07625 | Availability tight, VW slack |
| Availability/VW crossover | 1.0825 | Both geometrically tight |
| Descending VW, VW tighter | 1.09, already present | VW tight, availability slack |

For a finite linear segment define `t = (v - left_knot) / segment_width`.
Add targets near `t = 0.2, 0.5, 0.8`, subject to compatibility with the other
curve and the intended active limit. Sample the VW intervals before and after
the availability crossover separately. For constant plateaus, sample within
an explicitly chosen feasible voltage window, including near and far from
the nearest knot.

Keep the six exact-knot targets, and add solved left/right neighbors. Choose
the offset at least ten times the voltage classification tolerance and at
most one percent of the adjacent segment width. If these conditions cannot
both hold, classify the case as a numerical boundary stress test rather than
claiming a strict interior. Smaller offsets can be tested separately.

To obtain simultaneous VV and VW ramps, introduce a clearly named alternative
profile whose intervals overlap. For example, extend the upper VV ramp to
1.10 while retaining the VW ramp at 1.07--1.12. This changes controller data,
not the network or hinge building blocks. It is a synthetic profile variant,
not a claim about the original profile or a prescribed control setting.

## Matrix B: constraints that determine dispatch

Start with isolated limits, then select a small set of intersections. All
rows in this table are planned targets; they have not been calibrated or solved.

| Family | Target constraint | Other limits | Design change |
| --- | --- | --- | --- |
| A | Available active power | Capability, thermal, voltage slack | Current low/moderate-voltage cases |
| W | VW cap on a ramp or plateau | Availability and equipment limits slack | Current high-voltage cases; add more curve positions |
| S+ | Inverter capability with reactive injection | A and W slack | Choose S below `hypot(p_available, q_curve(v))` but above `abs(q_curve(v))` |
| S- | Inverter capability with reactive absorption | A and W slack | As above, with the absorption ramp or plateau |
| Tf | Sending-end branch rating | Device capability, A, W slack | Calibrate a transfer-limited dispatch and sending-end rating |
| Tt | Receiving-end branch rating | Other branch end and device limits slack | Calibrate the reverse voltage/rating relationship |
| V+ | Upper voltage bound | Power and thermal limits slack | High generation and an objective favoring more generation |
| V- | Lower voltage bound | Equipment limits slack | Load-dominated case with costly local generation needed to maintain voltage |
| G- | Source export bound | Device and branch limits slack | Limit source absorption of exported power |
| G+ | Source import bound | Device and branch limits slack | Make local generation more expensive, then cap imports |
| P0 | Inverter zero-output bound | Positive cap and capability slack | An objective preferring curtailment or costly local production |
| SW | Capability and VW cap geometrically tight | Availability and thermal slack | Tune their intersection, including an overlapping-ramp profile |
| TW | Shared branch rating and at least one VW cap | Other devices respond | A multiple-controller transfer-constrained case |

Keep the control law unchanged when activating equipment limits. In particular,
reducing S does not silently clip Q: the equality `q = VV(v)` still holds.
Feasibility requires `abs(VV(v)) <= S` and the attainable active power then
satisfies `p <= sqrt(S^2 - VV(v)^2)`. A stricter hardware Q bound similarly
restricts feasible voltage under the fixed law. Priority switching would be a
different controller model and needs its own formulation.

With the current series-only branch, both ends share the same current and
`abs(S01) / abs(S10) = E / v`. Equal end ratings therefore cannot independently
select which end binds at a fixed operating point. Use a suitable voltage/flow
direction or explicitly different end ratings. Do not declare two independent
thermal successes by counting the same limit twice.

Tightening a limit on a reference point only establishes geometric tightness.
It may be redundant, weakly active, or make the whole problem infeasible.
For a constraint intended to determine dispatch, check a nonzero margin from
competitors and re-solve after a small relaxation of its RHS. The resulting
dispatch/objective response supports the claimed role. Report multipliers
where meaningful; do not infer unique or nonzero multipliers at redundant
bounds or degenerate intersections.

### Concrete calibration seeds

The following seeds reuse the current load, impedance, and curves. Reconstruct
the source phasor from the proposed `(v, p, q)` using the existing reference
construction, then set the indicated limit. They define physical witnesses;
their optimal active sets still need to be verified after solving.

| Seed | Target `(v, p, q)` | Change |
| --- | --- | --- |
| S+ | `(0.96, sqrt(0.65^2 - 0.15^2), 0.15)` | Set inverter S to 0.65; availability and VW remain slack |
| S- | `(1.04, sqrt(0.65^2 - 0.15^2), -0.15)` | Set inverter S to 0.65 on the absorption ramp |
| Tf | `(1.04, 0.60, -0.15)` | Set sending-end rating to `abs(S01)` at the witness; keep the other end loose |
| Tt | `(0.96, 0.70, 0.15)` | Set receiving-end rating to `abs(S10)` at the witness; keep the other end loose |
| V+ | `(1.04, 0.70, -0.15)` | Set upper voltage to 1.04 under the current import-minimizing objective |
| V- | `(0.96, 0.50, 0.15)` | Set lower voltage to 0.96 and use the illustrative objective `pg + 2p` |
| G- | `(1.04, 0.60, -0.15)` | Set source lower P bound to the witness `pg`, retaining the current objective |

For the thermal seeds, the source voltage is higher than the inverter voltage
in Tf and lower in Tt, so the two examples also distinguish branch-end
apparent-power limits. Calibrate one limit at a time, verify competitor slack,
then perturb its rating to distinguish a dispatch-limiting constraint from an
accidentally tight one. In V-, the device cost makes lower-voltage support
costly; using the current objective unchanged would not establish the same
economic role for the lower voltage bound.

## Matrix C: multiple controllers in one study

| ID | Layout | Controller regime targets | Interaction to verify |
| --- | --- | --- | --- |
| M1 | Three-bus fork, two controllers | One injecting Q, one absorbing Q | Different local voltages under one common source |
| M2 | Three-bus chain, two controllers | Near-source deadband/availability; remote VW curtailment | Voltage gradient and different power-limiting statuses |
| M3 | Fork, three controllers | One availability-limited, one capability-limited, one VW-limited | All three limit families in the same solved case |
| M4 | Two controllers at one bus, different profiles | Different VV regions at the same voltage | Heterogeneous thresholds and aggregation of P/Q injections |
| M5 | Two controllers at one bus, identical profiles | Same VV/VW region, different availability or ratings | Shared voltage and asymmetric device limits |
| M6 | Small mesh, two or three controllers | Distinct regions, a shared thermal bottleneck | Competing injections and congestion-driven redispatch |
| M7 | Several devices at deliberate knot targets | Two simultaneous biactive pairs, remaining devices interior | Boundary degeneracy and per-device diagnostics |
| M8 | Three devices: VV only, VW only, both | Distinct enabled control blocks | Pair counts, offsets, and result attribution |

M1 (`fork_mixed_reactive`), M2 (`chain_remote_curtailment`) and M5
(`colocated_controllers`) are implemented. Other M rows remain planned.
Use M3/M6 once isolated equipment limits are verified; add M4/M7/M8 as targeted
interaction/API studies. Disabled laws and heterogeneous knot counts already
have solver-independent construction and physics tests.

Identical colocated controllers must occupy the same curve region. Different
operating regions at the same bus require different profiles or monitored
quantities. Identical colocated devices can also have nonunique active-power
allocations under an objective depending only on aggregate import. Either
accept this and compare aggregate results/feasible sets, or explicitly add a
small strictly convex device cost. Never assert one arbitrary dispatch split
as the unique correct solution.

For distinct-bus controllers, common source voltages, line flows, and balances
must be satisfied simultaneously. Do not construct each device's source voltage
independently and combine the results. One possible calibration fixes target
phasors and derives compatible loads from network injections, but must enforce
the stated load signs and ranges. Inverse construction gives a feasibility
witness, not evidence that an OPF solution chooses that witness or regime.

## Reuse the existing building blocks

Keep all power-system construction in the example module and continue returning
an ordinary `MPCCModel`. The data-driven constructor
`BalancedACOPFModel(data; x0 = nothing)` and the named-case/type convenience
wrapper are implemented. The example README documents the record schema and
the distinction between optional witnesses and coverage targets.

Represent branches, loads, sources, and controllers as small explicit records.
Each controller has its own bus, enabled laws, breakpoints, curve outputs,
availability, hardware bounds, and rating. Separate curve plateau values from
hardware Q bounds. Network assembly sums all devices connected to each bus.
Reuse the polar branch-power equations for each branch and the same hinge
construction for each enabled piecewise curve.

A scalar curve helper can turn ordered breakpoint/output pairs into a
baseline plus hinge coefficients: use the change in segment slope at each
knot, including the changes from/to the constant outer plateaus. The current
four-knot VV and two-knot VW formulas are instances of this construction.
Keep the helper inside the examples, retain the knots for deterministic pair
counts, and evaluate the direct piecewise law independently for diagnostics.
Store device powers and curve outputs on the common system per-unit base;
convert any device-rating fractions once when preparing the case data.

Compute variable and constraint index maps from the data once. Use those maps
in construction, tests, and diagnostics rather than multiplying the current
fixed slices. With four-knot VV and two-knot VW curves, the pair count is
`sum(4 * has_vv[k] + 2 * has_vw[k] for k in controllers)`; all devices carrying
both laws contribute six pairs each. Distinct device hinges simplify attribution,
even when two devices happen to share a voltage or a knot.

Validate profile order, finite coefficients, bus references, impedance, ratings,
and array sizes before building the NLP. A malformed input and a well-formed
but physically infeasible operating case need different outcomes.

## Case records and acceptance gates

Each selected case needs the following separate records:

| Record | Required information |
| --- | --- |
| Physical data | Network, sources, loads, controllers, units, objective, initial point |
| Provenance | Base case, changed parameters, generation seed if used, profile version |
| Feasible witness | AC and controller residuals; optional for deliberately infeasible cases |
| Intended coverage | Per-device regions, normalized positions/windows, target active limits, expected slack competitors, expected feasibility |
| Observed solution | Solver/version/settings, original objective, physical residuals, per-device curve values/slacks and classification |
| Audit outcome | Verified; missed target; infeasible with supporting evidence; failed solve; ambiguous near boundary |

First require finite iterates, original AC feasibility, hardware bounds, direct
curve agreement, and complementarity. Then classify the solution against the
actual curves using voltage tolerances and power slacks in the common per-unit
system. Report device-rating-normalized slacks as an additional quantity when
comparing different-sized devices. Convert squared apparent-power constraints
to magnitude margins for reporting. Use separate thresholds for tight limits, demonstrably slack
competitors, and kink proximity. The slack threshold must exceed the tightness
threshold; intermediate values are indeterminate, not forced into a category.

Regime labels must use the actual solution and actual profile. In particular,
being on the VW descending segment does not imply its cap binds; lying on its
lower plateau does not imply equality if another limit curtails further.

Core CI should check deterministic data, references, derivatives, pair/index
structure, and independent physics without requiring CCOpt. A separate solver
integration gate should enforce *achieved* coverage for a curated small set.
Broader matrix sweeps can run outside the ordinary package tests. For several
controllers, add device-order permutation and bus-relabeling checks; compare
individual dispatch only when uniqueness is justified. Check the objective and
appropriate stationarity diagnostics separately from feasibility. Passing
feasibility and coverage alone is not an optimality certificate.

## Implementation sequence

1. **Done:** repair converted-start validation and add a regression. Track the inherited
   split-API failures with focused tests and their own prerequisite fix.
2. **Done:** add target/observed coverage records to the named cases and runner.
3. **Done:** complete the missing single-controller interiors and availability crossover;
   add ramp-position strata and solved breakpoint neighbors.
4. **Done:** introduce explicit network/controller data and computed index maps while
   preserving the existing twelve named examples.
5. Add isolated capability, thermal, voltage, and source-bound cases with
   sensitivity checks that establish their role in dispatch.
6. **M1/M2/M5 done:** next build the mixed-limit and meshed multiple-controller studies.
7. Audit compatible coverage cells, add selected coactive/boundary stress cases,
   and publish only observed coverage, with infeasible/unverified cells labeled.
