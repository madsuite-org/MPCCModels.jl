# Balanced AC OPF with volt-var and volt-watt controls

This example builds an ordinary vertical-form `MPCCModel` from explicit bus,
series-branch, source, and controller records. It supports several controllers
on one bus or on different buses, arbitrary continuous piecewise-linear curves,
and independently enabled VV/VW laws. `ADNLPModels` supplies the smooth NLP.
Neither the examples nor CCOpt add dependencies to the package runtime.

The nonnegative hinge formulation is ported from
[BMOPFTools.jl PR #383](https://github.com/frederikgeth/BMOPFTools.jl/pull/383),
specifically `_complementarity_curve_expr!` at
[`faf3d455381e15b651808c489237c0dd921d7cf7`](https://github.com/frederikgeth/BMOPFTools.jl/blob/faf3d455381e15b651808c489237c0dd921d7cf7/ext/BMOPFOpfExt/ibr.jl#L357).

## Run

Prepare the example environment from the repository root:

```sh
julia --project=examples/opf -e 'using Pkg; Pkg.develop(path=pwd()); Pkg.instantiate()'
julia --project=examples/opf examples/opf/solve.jl curtailment
julia --project=examples/opf examples/opf/solve.jl fork_mixed_reactive
julia --project=examples/opf examples/opf/solve.jl all
julia --project=examples/opf examples/opf/test-solves.jl
```

The optional integration test solves all 37 named cases. It requires successful
or acceptable-level solver termination, all original feasibility residuals below
`1e-5` per unit, and **achieved** coverage of every controller's intended regime,
voltage window, tight limits, and slack competitors. It does not establish
global optimality. The same gate runs in a separate CI job; ordinary package
tests remain solver-independent.

`solve.jl` prints the original objective, solver status, residuals, and individual
controller reports. Its tight tolerances and small per-unit initialization bound
push are example settings, not general recommendations. Nonnegative hinge bounds
are kept unrelaxed. Direct physical curve checks remain necessary at knots,
where a small product can still allow larger errors in its individual factors.

If a successful homotopy point misses these checks, the runner conditionally
polishes a branch NLP using `CCOpt.BranchNLP`. The branch is chosen from the
returned hinge values, never from a reference or target. Both solver statuses,
the original homotopy residuals/coverage, and the final checks are preserved.
This is a solve on a selected smooth sector, not a full MPCC stationarity or
global-optimality certificate. `solve_opf_case(name; polish = false)` disables
this refinement while retaining the same acceptance gates.

## Inspect the model

```julia
using MPCCModels, NLPModels
include("examples/opf/balanced-ac-opf.jl")
using .BalancedACOPF

data = balanced_ac_opf_case(:chain_remote_curtailment)
layout = opf_layout(data)
mpcc = BalancedACOPFModel(data)
x = balanced_ac_opf_reference(data)
@show get_nvar(mpcc), get_ncon(mpcc), get_ncc(mpcc) # (34, 28, 12)
@show x[layout.p], x[layout.q]                     # approximately [0.8, 0.68], [0, -0.3]
@show opf_residuals(mpcc, x, data)
@show opf_coverage(data, x).targets_met             # true
```

The convenience constructor `BalancedACOPFModel(Float32; case = :deadband)`
is retained. The original twelve two-bus cases still have 18 variables,
15 constraints, six pairs, and their original variable/constraint ordering.
The default is a flat voltage start; `x0` supplies another start. Values are
checked for finiteness **after** conversion to the model's numeric type.

## Building blocks and data contract

- `opf_curve(knots, values)` validates an ordered, finite continuous curve with
  constant extrapolation. One hinge is retained per knot, including zero slope
  changes, so indices depend on structure rather than coefficient values.
- `opf_bus(T; pload, qload, vmin, vmax, angle_max)` defines a bus. Positive load
  consumes power; negative Q load is capacitive. The shipped fixtures have
  nonnegative P and Q loads.
- `opf_branch(from, to, r, x, T; rate_from, rate_to)` defines a series branch
  with separate apparent-power limits at its ends. Parallel branches and meshes
  are supported; shunts, taps and phase shifts are absent.
- `opf_controller(id, bus, T; vv, vw, p_available, smax, qmin, qmax, cost,
  quadratic_cost)` defines a device. Either curve can be `nothing`. A device
  without VV has bounded free Q; one without VW has only its other P limits.
- `opf_layout(data)` validates the network and computes all indices. Source
  voltage and angle have index zero because they are fixed. Use these maps in
  new cases instead of hard-coded slices.

A data record contains `name`, `buses`, `branches`, `controllers`, and `source`.
Bus numbers index `buses`; controller IDs must be unique. Source fields are
`bus`, `voltage`, `pmin`, `pmax`, `qmin`, `qmax`, and `cost`. Its positive fixed
voltage and zero angle must satisfy its bus bounds. The network must be
connected and at least one control law enabled. Malformed data are rejected.

Optional `reference` fields are `voltage`/`angle` vectors per bus and `p`/`q`
vectors per controller. Source P/Q are reconstructed from balance. Optional
`targets` contain one record per controller ID with `vv_region`, `vw_region`,
`voltage_window`, `tight`, and `slack`. Missing targets yield
`targets_met = missing`, rather than certifying coverage vacuously.

All powers and curve outputs use a common three-phase system per-unit base;
voltage uses the corresponding positive-sequence base, and angles are radians.
Convert device-rating fractions before building curves. Treat data as immutable
after construction and rebuild after edits. Changing physical data invalidates
the old reference and coverage assumptions.

The objective is `source.cost * pg + sum(c.cost*p[c] + c.quadratic_cost*p[c]^2/2)`.
This allows future cases to make local production costly or distinguish
otherwise symmetric dispatch allocations.

## Physical controls

VV **sets Q**; VW **caps P**, alongside availability and the capability circle.
Default VV points are `(0.94, 0.3)`, `(0.98, 0)`, `(1.02, 0)`, `(1.06, -0.3)`.
Default VW points are `(1.07, 1.0)`, `(1.12, 0.2)`. The default hardware Q box
is `[-0.4, 0.4]`, separate from the `[-0.3, 0.3]` curve plateaus. This removes
the original duplicate plateau bounds without changing the exact controlled
feasible set. There is no implicit clipping, dynamics, or priority switching.

Every knot uses `r - s - v = -knot`, `0 <= r ⟂ s >= 0`. Changes in segment
slopes give the coefficients in `baseline + sum(weight*r)`. The underlying NLP
has linear hinge/control links and smooth nonlinear AC balances and equipment
limits. It contains neither nonsmooth curve evaluations nor product equalities.

## Coverage matrix implemented so far

| Group | Count | Coverage |
| --- | ---: | --- |
| Original interiors and exact knots | 12 | Five VV regions, three VW regions, all six knots |
| Missing joint regimes/crossover | 3 | `saturated_var_flat_watt`, `early_watt_ramp`, `availability_watt_crossover` |
| Additional ramp positions | 7 | VV injection/absorption at 20/80%; VW at 20/50/80% |
| Knot neighbors | 12 | Every knot minus/plus `1e-4` per-unit voltage |
| Multiple-controller studies | 3 | Fork, chain, and colocated controllers |

Availability 0.8 crosses the default VW cap at voltage 1.0825. Thus the early
VW ramp is distinct: the descending curve need not determine P.

| Multiple-controller case | Reference voltages | Reference P/Q and target |
| --- | --- | --- |
| `fork_mixed_reactive` | 0.96, 1.04 | P = 0.8 each; Q = +0.15/-0.15 on opposite VV ramps |
| `chain_remote_curtailment` | 1.00, 1.09 | Near: P = 0.8, Q = 0; remote: P = 0.68, Q = -0.3 with VW binding |
| `colocated_controllers` | Shared 1.04 | P = 0.3/0.8 and Q = -0.15 each, both availability-limited |

All fixtures are synthetic. The two-bus source voltage is calibrated to its
target. Multiple-controller loads are calibrated jointly from complex network
injections under one common source. Witnesses establish feasibility; the
integration gate independently checks what the solver actually achieves.

`opf_coverage` reports `below`, `segment_1`, ..., `above`, or `knot_1`, ... for
each law, with fractional positions on finite segments. Its defaults are a
`1e-6` voltage neighborhood for knots, `1e-5` for tight power limits, and `1e-4`
for demonstrably slack competitors. Branch margins are apparent-power
magnitudes, not squared slacks. Tight Q boxes are geometric observations,
not evidence of independent capability competition.

## Tests and next cases

`julia --project -e 'using Pkg; Pkg.test()'` checks Float32/Float64 references,
independent phasor physics, losses, generic curves, disabled laws, source-bus
controllers, permutation/relabeling, malformed inputs, and finite differences
of the gradient, Jacobian and Lagrangian Hessian. Split NLP evaluations are
checked against full ones. Coverage tests reject feasible missed-target points.

The [roadmap](ROADMAP.md) and [case-design matrix](CASE_DESIGN.md) track remaining
equipment-limited cases, heterogeneous profiles, coactive limits, and larger
studies. The shipped dispatches are availability- or VW-limited; isolated
binding capability, thermal, voltage and source-limit studies remain planned.

## PGLib transmission cases

The optional [PGLib suite](pglib/README.md) adds IEEE 14/118 and their congested
variants, full transmission equipment, matched dispatchable/VV/VW/both overlays,
three controllers per study, and solved activity/sensitivity checks. Its
[roadmap](pglib/ROADMAP.md) tracks the larger case and bound-activation matrix.
