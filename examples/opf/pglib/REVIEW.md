# PGLib review and next-case design

Review of the initial 22-case implementation, followed by controlled placement,
population and network-bound experiments on the same pinned source data.
The original 22 named configurations are retained; new study constructors are
separate from that frozen benchmark list.

## Correctness and package consistency

No discrepancy was found in the polar AC equations, transformer/charging/shunt
signs, system-base cost scaling, branch-end limits, or hinge link signs.
Independent PowerModels/Ipopt baselines, non-flat flow comparisons and derivative
checks continue to pass. The constructor follows the package design: a smooth
ADNLPModel, explicit linear rows, then ordinary `MPCCModel(nlp,r,s)` for enabled
laws. There is no new core model type or package runtime dependency. The optional
transmission implementation is Float64; generic numeric-type support is not
claimed for this example.

Two extension correctness gaps were reproduced and fixed:

1. **Two network representations could diverge.** The NLP reads normalized
   records while independent current/balance checks read `data.pm`. Editing
   loads, admittances or limits by merging only one representation could produce
   inconsistent checks or an incorrect PowerModels counterfactual. The new
   `transmission_overlay` deep-copies the authoritative per-unit dictionary and
   rebuilds records together. Constructor validation now rejects stale records.
   Original fixture bytes, hashes and source provenance remain unchanged.
2. **Targets could be individually reachable but jointly impossible.** VV and VW
   use the same voltage. The former validation checked each region against the
   bus box independently and did not intersect finite-fraction windows. Validation
   now intersects both region/window sets with the bus bounds, respecting open
   segment endpoints. Disabled laws cannot carry fraction targets.

Diagnostics now expose distances to knots, margins normalized by inverter S,
and fixed-P/fixed-Q flags for conventional generators. Fixed synchronous-
condenser P=0 boxes must not be counted as independent dispatch-bound activations.
Coverage is an activity report; original residual checks and solver status remain
separate acceptance conditions. Selected-sector refinement does not certify
full MPCC stationarity or global optimality.

## Initial 22-case coverage audit

Counts below are controller observations across solved cases, not independent
physical systems. There are 54 observations, with each law enabled in 30.

| Enabled law | Initial observations |
| --- | ---: |
| VV injection plateau | 2 |
| VV injection ramp | 12 |
| VV deadband | 4 |
| VV absorption ramp | 12 |
| VV absorption plateau | 0 |
| VV knots / deliberate left-right neighbors | 0 |
| VW upper plateau | 14 |
| VW ramp | 16 |
| VW lower plateau | 0 |
| VW knots / deliberate left-right neighbors | 0 |

Eleven of the 16 VW ramp observations are availability/VW crossovers, four have
availability tighter, and one is strictly VW-limited. Only one initial case
binds an inverter S circle. Seven hardware Q-upper observations occur when Q
is dispatchable; there is no VV-controlled hardware-Q-limited case. With the
initial VV plateaus at ±0.4 nominal S and Q boxes at ±0.5 nominal S, that last
mechanism is structurally excluded without a different hardware overlay.

Default profiles also limit which coverage is possible inside the 0.94–1.06 pu
bus voltage band:

| Profile | VV knots | Reachability limitation | VW knots | Reachability limitation |
| --- | --- | --- | --- | --- |
| ibr1 | 0.96, 0.99, 1.01, 1.04 | All regions individually reachable | 1.01, 1.04 | All regions individually reachable |
| ibr2 | 0.99, 1.02, 1.04, 1.07 | Absorption ramp stops at fraction 2/3; high plateau unreachable | 1.05, 1.08 | Ramp stops at fraction 1/3; lower plateau unreachable |
| ibr3 | 1.02, 1.05, 1.07, 1.10 | Deadband partly reachable; absorption ramp/plateau unreachable | 1.02, 1.05 | All regions individually reachable |

Reachable regions are not guaranteed optima. Coupled VV/VW targets must still
share a voltage interval. An ibr1/ibr3 ramp with the original VW values crosses
availability at fraction 0.25, explaining the concentration there. Curtailed
ramp strata 0.5/0.8 require operating conditions that make those optima, not just
new labels or more buses.

Initial network targets assert some V upper/lower, generator-Q upper,
generator-P lower and branch-from limits. They do not establish isolated
network-limit sensitivities. Receiving-end thermal limits do bind in IEEE 118
results, but were not explicit receiving-end target mechanisms. All initial
angle-difference limits are slack.

## Placement, population and penetration studies

Three independent experimental axes are now available in `studies.jl`:

| Study | Changes | Holds fixed | Interpretation |
| --- | --- | --- | --- |
| Three-device placement | Dispersed / clustered / colocated attachment buses | Devices, profiles, ratings, availability, costs, network | Location effect at fixed population |
| Replica population | Each device split into 1/2/4 colocated copies | Aggregate capacity, profile laws, aggregate cost, occupied buses | Formulation/count regression at essentially the same physics |
| Distinct-site fleet | 1/3/6/12 homogeneous devices on nested sites | Total S, availability, normalized profile, network | Spatial fleet growth; location changes along with count |
| Penetration | All inverter power/rating quantities multiplied by 0.5/1/2 | Three locations, knots, network demand | Installed-capacity effect at fixed population |

The three-device placements use original bus IDs (5,9,14), (9,10,14), (14,14,14)
on IEEE 14 and (20,45,95), (94,95,96), (95,95,95) on IEEE 118. Homogeneous profiles
use normalized ibr2 laws; heterogeneous profiles retain the three initial laws.
No generator is removed or automatically reclassified as an inverter.

Distinct-site fleets start at bus 14/95 and exclude the reference bus. Clusters
use increasing shortest hop distance; dispersed sites greedily maximize minimum
hop distance to previously selected sites, with bus IDs breaking ties. These
are topology-based rankings, not AC voltage-sensitivity rankings. Sites may
include zero-load buses and conventional-generator buses. All counts use one
normalized profile so population does not also change the policy mixture.

Observed VV+VW results, production-cost units as in the source data:

| Three-device study | IEEE 14 objective | IEEE 118 objective | Achieved VV regions |
| --- | ---: | ---: | --- |
| Dispersed, heterogeneous | 1621.147915 | 90402.416032 | 14: absorption/deadband/injection; 118: absorption/absorption/injection |
| Clustered, heterogeneous | 1621.824914 | 91133.065695 | Absorption/injection/injection plateau |
| Colocated, heterogeneous | 1639.942832 | 91262.274068 | Absorption/injection/injection plateau at one voltage |
| Colocated, homogeneous | 1633.725386 | 91163.277543 | All on the absorption ramp at one voltage |

Six- and twelve-controller replica cases preserve aggregate bus injections and
objectives within the tested tolerances; their pair counts are 36 and 72.
Quadratic costs scale inversely with device size, preserving aggregate cost at
equal sharing. Increasing distinct sites is a separate physical experiment and
has no invariance or monotone-cost expectation.

An IEEE 118 homogeneous cluster produces a VV knot-3 solution at device 3 while
devices 1/2 occupy absorption/deadband. It is tested as an observed knee without
fixing voltage or using targets to choose the solver sector. It still needs
neighbors before becoming a boundary-coverage family.

**Formulation caveat:** the current implementation allocates a hinge pair for
every enabled curve knot, including coincident knots at the same bus. At such a
knot the duplicate hinge definitions and zero-member conditions introduce extra
rank deficiency. Replica studies therefore increase redundant representation as
well as pair count. Keep this explicit in solver comparisons. A compact
`(bus,knot)` sharing option would be a useful future comparison; it changes MPCC
dimensions and degeneracy and should not silently replace existing benchmarks.

## Isolated network-bound sensitivities

Eight IEEE 14 studies vary one RHS, preserving every other input. Each checks
successful solves, original feasibility, explicit curve targets, a tight target
bound, a slack opposite bound, and slack competing bounds **within its family**.
Other network families can remain active. Fixed generator boxes are excluded
from dispatch isolation checks. The branch-1 thermal case has the stronger
property that every other nonfixed network limit is slack.

| Study | Base bound | Step | Base cost | Cost decrease from one relaxation step |
| --- | --- | --- | ---: | ---: |
| V upper, bus 1 | 1.06 pu | 0.0001 pu | 1621.147915 | 0.007268 |
| V lower, bus 3 | 1.005 pu | 0.0001 pu | 1621.149880 | 0.000371 |
| Generator 1 P upper | 1.8 system pu | 0.001 system pu | 1973.653576 | 1.437203 |
| Generator 2 Q upper | 0.3 system pu | 0.001 system pu | 1621.147915 | 0.000823 |
| Branch 1 thermal, from end | 1.2 system pu | 0.001 system pu | 2095.442541 | 1.721744 |
| Branch 6 thermal, to end | 0.33 system pu | 0.0002 system pu | 1640.873625 | 1.211588 |
| Branch 1 angle upper | 0.075 rad | 0.0001 rad | 1752.029551 | 3.104154 |
| Branch 6 angle lower | -0.06 rad | 0.0001 rad | 1621.209657 | 0.013869 |

Both tightening and relaxation are tested, and the monotone cost response must
persist at half step. Matched dispatchable-P/Q counterfactuals retain the same
modified network and hardware. These are local value responses, not NLP duals or
global derivatives. In particular the lower-angle case has asymmetric one-sided
responses; do not report one constant marginal price for it.

The receiving-end thermal case simultaneously curtails device 2 below its VW
cap and availability while device 3 is strictly VW-limited near ramp fraction
0.37. The step was reduced to 0.0002 to keep the perturbations away from device
2's availability bound and nearby VV knee. This is a coupled thermal/control
study, with only one thermal end binding, not a claim that no other constraint
family is active.

## Recommended next named cases

| Priority | Proposed family | Scientific target and acceptance requirement |
| --- | --- | --- |
| 1 | In-band VV absorption plateau and VW lower plateau | New explicit profiles with all desired knots inside the existing voltage box; strict curve regions, positive knot distance and named slack competitors |
| 1 | IEEE 118 knee and left/right neighbors | Start from the homogeneous cluster knee; select deterministic load/availability/profile perturbations that actually land on opposite sides, at distances comfortably above classification/feasibility tolerances |
| 1 | Strict VW ramp 0.2/0.5/0.8 | Change availability/profile ratio as needed so ramp position and limiting cap are separate axes; avoid counting the fraction-0.25 crossover repeatedly |
| 2 | IEEE 118 location-sensitive thermal/VW interaction | Use lines 106/156/163 identified by placement studies; target receiving/from ends separately, compare matched policies and two perturbation sizes |
| 2 | VV ramp meeting a hardware Q bound | Put a Q limit inside the VV range; verify feasibility, response and competitor slack. The model enforces both constraints and does not clip the law |
| 2 | Heterogeneous distinct-site fleets | Counts 3/6/12 with constant total size and constant aggregate profile mixture, alongside the homogeneous and replica controls |
| 3 | RTS 24 / IEEE 300 | Add after regime and limit breadth improves; increase network size separately from controller count and penetration |

Keep acceptance tiers explicit: the initial 22 cases have frozen data targets;
replica/placement/knee/sensitivity regression tests assert their own outcomes;
distinct-site and penetration sweeps establish solved feasibility and report
activity but do not yet declare a complete regime-coverage target matrix.

## Reproduce

```sh
julia --project=examples/opf/pglib examples/opf/pglib/test-model.jl
julia --project=examples/opf/pglib examples/opf/pglib/test-solves.jl
julia --project=examples/opf/pglib examples/opf/pglib/validate-baselines.jl
julia --project=examples/opf/pglib examples/opf/pglib/test-studies.jl
julia --project=examples/opf/pglib examples/opf/pglib/run-studies.jl
```

All results are local numerical experiments. Failed aggressively tightened
angle/thermal trials were excluded instead of being called physical
infeasibility certificates or accepted by weakening gates.

## Validation record for this review

- Julia 1.10.12 and 1.12.6: **578 model assertions** and **376 study assertions**
  pass. Study assertions cover replicas, placement/profile contrasts, growing
  fleets, original feasibility, target activity, competitor slack, both RHS
  perturbation directions, half-step responses and matched counterfactuals.
- Julia 1.12.6: the existing **235 solved-case assertions** and **16 independent
  baseline assertions** pass after the changes.
- Documenter builds successfully, with external link checks disabled locally
  for the offline build; the committed configuration retains them. No core
  package implementation or dependency changed.
- The CI job now includes `test-studies.jl`. These are local results; remote
  CI execution remains pending.
