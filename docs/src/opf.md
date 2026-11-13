# Balanced AC OPF with inverter controls

The module in `examples/opf/balanced-ac-opf.jl` returns an ordinary
[`MPCCModel`](@ref), with `ADNLPModels` supplying the smooth NLP. It supports
connected balanced networks and multiple VV/VW controllers. These example
building blocks live outside the package's runtime API.

## Network and controls

Branches have series impedance ``z=r+\mathrm{j}x``, without shunts, taps or phase
shifts. For bus phasors ``V_i=v_i e^{\mathrm{j}\theta_i}``, their end powers are

```math
S_{ij}=V_i\overline{(V_i-V_j)/z},\qquad
S_{ji}=V_j\overline{(V_j-V_i)/z}.
```

Every bus balances load, all attached device injections, source power if
attached, and branch powers. One source voltage and angle are fixed; bounded
source P/Q can represent import or export. Branches have separate apparent-power
ratings at their ends. Each device has availability, hardware Q bounds and
``p_k^2+q_k^2\le S_k^2``. The objective is

```math
\min\; c_g p_g + \sum_k \left(c_k p_k+\tfrac12 d_k p_k^2\right).
```

Named cases use source cost one and device costs zero. All powers and curve
outputs share a three-phase system per-unit base; voltage uses its corresponding
positive-sequence base, and angles are radians. Fixtures are synthetic and do
not prescribe grid-code settings.

VV fixes ``q_k=F^{VV}_k(v_k)``; VW caps ``p_k\le F^{VW}_k(v_k)`` alongside
availability. Hardware limits apply simultaneously, with no implicit clipping
or priority policy. Disabling VV leaves bounded free Q; disabling VW removes
that cap. Default VV points are `(0.94, 0.3)`, `(0.98, 0)`, `(1.02, 0)`, and
`(1.06, -0.3)`; default VW points are `(1.07, 1.0)`, `(1.12, 0.2)`.
Both curves interpolate linearly and extrapolate constantly. The hardware Q
box `[-0.4, 0.4]` is separate from the `[-0.3, 0.3]` curve plateaus.

## Hinge blocks

The formulation is ported from
[BMOPFTools.jl PR #383](https://github.com/frederikgeth/BMOPFTools.jl/pull/383)
at commit `faf3d455381e15b651808c489237c0dd921d7cf7`. At each curve knot:

```math
r_h-s_h-v_k=-\kappa_h,\qquad 0\le r_h\perp s_h\ge0.
```

Hence ``r_h=\max(v_k-\kappa_h,0)``. A curve is its first output plus weighted
hinges, with the change in segment slope as each weight. Any finite ordered
knot/value arrays are supported. All knots are retained, even zero slope
changes, for stable indices. Four-knot VV and two-knot VW give six pairs per
device carrying both laws; disabled laws contribute no pairs.

The NLP contains linear hinge/control links, smooth AC balances and equipment
limits. `MPCCModel` receives the pairs separately. Neither `max` evaluations
nor product equalities enter the underlying NLP. Colocated devices have their
own pair indices and aggregate through their common bus balance.

## Build and inspect

Prepare the optional example environment from the repository root:

```sh
julia --project=examples/opf -e 'using Pkg; Pkg.develop(path=pwd()); Pkg.instantiate()'
```

```@example balanced_opf
using MPCCModels, NLPModels
include(joinpath(dirname(pathof(MPCCModels)), "..", "examples", "opf", "balanced-ac-opf.jl"))
using .BalancedACOPF

data = balanced_ac_opf_case(:chain_remote_curtailment)
layout = opf_layout(data)
mpcc = BalancedACOPFModel(data)
x = balanced_ac_opf_reference(data)
(get_nvar(mpcc), get_ncon(mpcc), get_ncc(mpcc))
```

The near-source device is availability-limited in the VV deadband; the remote
device is VW-limited on the VV absorption plateau:

```@example balanced_opf
(p = round.(x[layout.p]; digits = 3), q = round.(x[layout.q]; digits = 3))
```

```@example balanced_opf
@assert maximum(values(opf_residuals(mpcc, x, data))) < 1e-10
opf_coverage(data, x).targets_met
```

`BalancedACOPFModel(Float32; case = :deadband)` remains available. The original
twelve two-bus cases keep their 18-variable, 15-constraint, six-pair ordering.
Use `opf_layout(data)` for indices in new cases. `x0` overrides the flat start;
starting values are checked after numeric conversion.

## Data and modifications

`opf_bus`, `opf_branch`, `opf_controller`, and `opf_curve` construct records.
A model needs `name`, `buses`, `branches`, `controllers`, and `source`. Source
fields are `bus`, `voltage`, `pmin`, `pmax`, `qmin`, `qmax`, and `cost`.
Bus indices are array positions and controller IDs are unique. The network
must be connected with at least one enabled law. Source voltage must satisfy
its fixed-voltage bus bounds. Negative P loads are rejected; negative Q loads
are capacitive. Parallel branches and meshes are supported.

Custom data need neither a reference nor targets. `reference` contains per-bus
voltage/angle and per-device P/Q. `targets` match controller IDs and specify
`vv_region`, `vw_region`, `voltage_window`, `tight`, and `slack`. Without targets,
the coverage result is `missing`, not a vacuous success.

For example, construct a lower-capability variant using the same blocks:

```@example balanced_opf
devices = [merge(data.controllers[1], (smax = 0.65,)), data.controllers[2]]
variant = (name = :custom_capability, buses = data.buses, branches = data.branches,
    source = data.source, controllers = devices, targets = nothing)
limited_model = BalancedACOPFModel(variant)
get_ncc(limited_model)
```

This builds a new problem; it does not establish that its optimum is on the
capability circle. The old witness/targets are not carried over. Rating changes
can alter feasibility, dispatch and curve regimes. Calibrate and verify the
new targets before adding a named case. Treat data as immutable after building
the model and rebuild after edits.

## Implemented case matrix

There are 34 single-controller cases: twelve original interiors/knots,
three missing joint regimes/crossover, seven extra ramp positions and twelve
left/right knot neighbors. The missing regimes are now covered by:

| Case | Reference voltage | Interpretation |
| --- | ---: | --- |
| `saturated_var_flat_watt` | 1.065 | VV saturated; VW upper plateau |
| `early_watt_ramp` | 1.07625 | VW descending; availability tighter |
| `availability_watt_crossover` | 1.0825 | Both active-power caps tight |

Ramp cases sample 20/50/80% positions. Each knot has neighbors at plus/minus
`1e-4` voltage. Knot classification uses a `1e-6` voltage neighborhood; solver
iterates need not be exactly biactive.

| Two-controller case | Interaction |
| --- | --- |
| `fork_mixed_reactive` | VV injection/absorption ramps at different buses |
| `chain_remote_curtailment` | Near-source availability and remote VW curtailment |
| `colocated_controllers` | Shared voltage/profile and different availability |

The multiple-controller loads are calibrated jointly from complex branch
injections under one source, with nonnegative P/Q loads. They do not combine
independently constructed sources. References are feasibility witnesses,
not optimality certificates.

```@example balanced_opf
all(balanced_ac_opf_cases()) do name
    d = balanced_ac_opf_case(name)
    model = BalancedACOPFModel(d)
    point = balanced_ac_opf_reference(d)
    maximum(values(opf_residuals(model, point, d))) < 1e-10 &&
        opf_coverage(d, point).targets_met === true
end
```

## Validate actual solutions

```sh
julia --project=examples/opf examples/opf/solve.jl all
julia --project=examples/opf examples/opf/test-solves.jl
```

The runner checks solver status, original residuals below `1e-5`, and achieved
coverage. It classifies the **solution**, checking per-device regions, voltage
windows, tight limits and slack competitors. It reports segment fractions and
network margins. Being on a descending VW segment does not imply the cap binds.
Margins use physical per-unit magnitudes, not squared apparent-power slacks.

The current dispatches are availability- or VW-limited. Binding capability,
thermal, voltage and source-bound families remain in `examples/opf/CASE_DESIGN.md`
and the roadmap. Acceptable-level solver status is preserved when returned.
The tight solver/relaxation tolerances and small initialization bound push are
illustrative settings for these per-unit examples. Original curve checks remain
necessary: a product error of order ``\epsilon`` can allow an individual hinge
error of order ``\sqrt{\epsilon}`` at a knot. Neither feasibility nor coverage
is a global optimality certificate.

`Pkg.test()` checks independent phasor physics and derivatives, Float32/Float64
references, arbitrary curves, disabled laws, device permutation, bus relabeling,
source-bus controllers and the split NLP API. A separate CI job runs the solved
coverage targets with CCOpt.

When a successful homotopy point misses the physical or coverage checks, the
runner can polish the branch selected from that iterate using `CCOpt.BranchNLP`.
It preserves the original and final statuses, residuals and coverage. No
reference or target selects the branch. This selected-sector solve is not a
full MPCC stationarity or global-optimality test. Set `polish = false` when
calling `solve_opf_case` to inspect the unrefined homotopy result against the
same gates.

## PGLib transmission extension

A separate optional environment in `examples/opf/pglib` develops larger balanced
transmission cases from pinned PGLib-OPF v23.07 IEEE 14/118 networks and their
congested variants. It preserves conventional generators, polynomial costs,
shunts, line charging, fixed transformer taps/phase shifts, voltage and
branch-end limits, and angle-difference limits. The reference voltage magnitude
is optimized. It adds no dependencies to the package runtime.

The initial 22-case suite contains four canonical baselines, all four matched
dispatchable/VV/VW/both variants on each network, and IEEE 14 scenarios with
strict VW curtailment or an isolated binding inverter capability circle. Three
controllers share each physical network. Explicit targets check simultaneous
curve regions, finite-segment fractions and tight/slack limits; network targets
check selected bus, generator and branch-end bounds. Small limit relaxations
verify dispatch and production-cost responses in the two isolated inverter-limit
studies. Coverage of all transmission plateaus, knees and network-limit
sensitivities remains future work in `examples/opf/pglib/ROADMAP.md`.

```sh
julia --project=examples/opf/pglib examples/opf/pglib/solve.jl ieee118 both
julia --project=examples/opf/pglib examples/opf/pglib/solve.jl ieee14 both watt_limited
```

Install that environment against this checkout using `Pkg.develop(path=pwd())`
and `Pkg.instantiate()` as described in its README. `test-model.jl` checks
physics/derivatives; `validate-baselines.jl` compares with independent
PowerModels/Ipopt solves; `test-solves.jl` checks original feasibility, achieved
activity, matched hardware and limit perturbations. These are local numerical
checks and do not certify global optimality or full MPCC stationarity. Data
provenance, attribution, licenses and checksums are retained in the example.

## Searching for solver difficulty

The optional `examples/opf/pglib/search-hard-cases.jl` runner complements the
regression suite with failure-retaining experiments. It sweeps IEEE 118
capability limits, initial points and explicit solver profiles. Each raw CCOpt
attempt preserves its status, point, options, original physical errors and
reproducible input/start snapshots; failed runs are not automatically polished.
Separate exact-sector solves provide independently checked numerical feasibility
witnesses. Solver failure without a witness remains unresolved feasibility, not
a mathematical infeasibility certificate.

```sh
julia --project=examples/opf/pglib examples/opf/pglib/search-hard-cases.jl \
  --caps=0.82 --starts=flat,witness --profiles=defaults,current \
  --out=examples/opf/pglib/search-results/cap082
```

The harness documentation, artifact schema and resume/replay instructions are
in [Hard Search guide](generated/opf/pglib/HARD_SEARCH.md). A committed capability-0.82 receipt
retains representative raw failures/recoveries and a feasible witness. CI
rechecks that witness and the recorder, without requiring future solver versions
to keep failing. Full search outputs remain separate from the accepted regime
regressions and are ignored by Git.

A second search uses `--transitions` to hold the relaxation ratio at one while
combining three colocated IEEE 118 VV/VW controllers, knee offsets and a tightened
generator-Q upper bound. It records achieved knee distances and Q margins for
raw points and separate witnesses, and sweeps several deterministic perturbation
seeds. See the optional example's `HARD_SEARCH.md` for the full matrix and replay
commands. These difficulty searches retain the package's original hinge encoding.

The controlled reduction runner `examples/opf/pglib/search-reductions.jl` compares
separate and shared exact `(bus,knot)` hinges, controller counts, and availability/
VW intersections. Shared encoding preserves physical constraints while reducing
complementarity pairs; controller-policy changes retain hardware but alter the
physical feasible set. Physical-point transfer gives matched starts across
representations. Read-only iteration traces retain both solver residuals and
independent original-curve errors, with constructed witnesses labelled separately
from solver results.

## Application-driven transmission families

The optional application catalog adds `application_case`, `application_card`,
`application_parameters`, `application_cases` and `application_coverage`.
The first IEEE 118 families represent high renewable output with lighter demand,
limited conventional reactive support, and renewable export through a constrained
corridor. They use heterogeneous multi-plant controls, nominal/elevated/severe
operating points, parameter overrides and matched dispatchable/VV/VW/both laws.
The physical labels do not predict solver difficulty. PGLib topology and source
files are retained; explicit load, capability and corridor overlays are recorded.

```julia
using MPCCModels
include(joinpath(dirname(pathof(MPCCModels)), "..", "examples", "opf", "pglib", "transmission-opf.jl"))
using .TransmissionOPF

data = application_case(:reactive_support; level=:severe)
model = TransmissionOPFModel(data)
```

The same constructors accept `network=:ieee300`. This adds a pinned 300-bus,
411-branch, 69-generator canonical AC OPF independently checked against
PowerModels/Ipopt, plus nine operating inputs with network-specific plant
placements and ratings. The canonical model has 738 variables and 1,833
constraints. The IEEE 118 defaults and original 22 solved overlays retain their
definitions. See the [IEEE 300 study guide](generated/opf/pglib/IEEE300.md)
for the physical matrix, coverage and raw CCOpt results. Select `--network=ieee300`
in `search-applications.jl` to run this matrix with the existing failure-retaining
recorder and independently checked references.

These are synthetic balanced steady-state transmission/aggregate-plant proxies,
with a documented scope rather than prescribed inverter settings or calibrated
feeders. The optional `search-applications.jl` runner retains raw outcomes,
matched dispatchable baselines, verified numerical witnesses and measured curve/
bound coverage. A feasible challenge case can enter the catalog even when CCOpt
fails; failed witness searches remain unresolved. Application definitions,
physical parameter tables and the measurement protocol are documented in
[Applications guide](generated/opf/pglib/APPLICATIONS.md).

The application extension adds `application_policy_card`,
`application_policy_case`, `application_fleet_case` and `application_fleet_start`.
Nine synthetic policy variants target reactive saturation, active-power backstops
and interior ramp coverage. Fixed-total 6/12/24-unit fleets preserve each original
profile class's aggregate hardware/availability. Same-site proportional replicas
provide an aggregate-physics control; clustered/dispersed distinct-site fleets
intentionally vary geography. The optional `search-expansions.jl` runner records
raw trials, matched dispatchable baselines and explicitly labelled physical
transfers versus solver-derived references. Definitions, measured outcomes and
scope are documented in [Expansions guide](generated/opf/pglib/EXPANSIONS.md).

The IEEE 300 operating-policy extension adds network-aware
`application_policy_case` inputs and `application_reserve_case` for one-sided
conventional Q-upper contractions. Lower Q bounds remain fixed, including
positive mandatory-Q minima. `application_policy_coverage` separates strict VW
activity from joint availability/VW activity and checks strict plateau positions;
the original coverage report schema is unchanged. References are validated at
`1e-7` before both CCOpt profiles run from flat/reference starts. See
[Policy Matrix guide](generated/opf/pglib/POLICY_MATRIX.md) for the nine-input physical matrix,
measured regimes, numerical evidence and reproducible commands.
