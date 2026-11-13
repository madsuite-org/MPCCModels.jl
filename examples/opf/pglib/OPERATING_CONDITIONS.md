# IEEE 118/300 operating-condition matrix

This study keeps the existing single-state balanced AC OPF, constant-extrapolated
VV equality, VW cap and independent hardware/network limits. It introduces no
SCOPF, temporal coupling, additional control law, curve-design variables or free
equipment. Every row is an independent optimization problem. Policy curves are
fixed within physical sequences; existing policy cards define the selected
cross-family comparisons. All profiles and placements are synthetic study inputs.

## Physical matrix

`operating_condition_specs(network=:ieee118)` and `network=:ieee300` each return
23 explicitly identified inputs. `operating_condition_case(spec)` constructs
ordinary data with the existing application/policy/fleet constructors and
`transmission_overlay`; `TransmissionOPFModel(data)` is unchanged.

| Group | Levels per network | Fixed quantities and interpretation |
| --- | --- | --- |
| Conventional reactive reserve | Retained upper interval fractions 1, .98, .95, .90, .80 | Nominal reactive-support anchor; Qmin, P limits/costs, load, plant hardware and curves fixed |
| Renewable export | Cutset rating factors 1.20, 1, .85, .70, .55 | Nominal export anchor; scale every boundary rating together, retain all other branch parameters |
| Export with voltage backstop | Rating factors 1, .85, .70 | Existing early-export-backstop card and its operating anchor; only ratings change |
| Penetration | .45, .65, .85 | Elevated surplus with existing gentle-watt-cap policy; hardware and curve ordinates scale together at fixed normalized policy and availability |
| Geography/population | Six clustered; six dispersed; twelve at original six sites | Same .65 penetration and aggregate profile mixture as the penetration anchor; placements change geography, replication changes representation size |
| Injection/reserve interaction | Upper interval fractions .98, .90 | Existing injection-service card; preserve that card's anchor Qmin, including any pre-existing application overlay |
| Absorption/availability interaction | Availability .85S, .98S | Existing absorption-service card; fixed hardware and curves; higher availability can expose the unchanged S circle |

Q-upper contraction is `Qmax = Qmin_anchor + f*(Qmax_anchor-Qmin_anchor)`.
It preserves positive Q minima and fixed intervals. It is not signed scaling
of both Q bounds. For the IEEE 118 injection card, the anchor already contains
its documented application Q contraction; this sequence preserves those anchor
lower bounds rather than claiming to restore the canonical source limits.

Penetration is distinct from population: it changes installed capacity.
Same-site replicas preserve the original rating-weighted mixture and aggregate
feasible set, apart from floating arithmetic. Clustered/dispersed placements
are topology-based, use distinct eligible buses, and are not claimed to be
voltage-sensitivity-optimal or a calibrated renewable development plan.

All four `laws=:dispatchable/:vv/:vw/:both` variants retain the same physical
inputs, costs and hardware. Removing a law changes only its operating constraint.
No coverage targets are attached to these cases, and no constructor fixes a bus
voltage or selects a complementarity sector.

## Construct and inspect an input

In the optional environment, using the package-relative example path:

```julia
using MPCCModels
example_root = joinpath(dirname(pathof(MPCCModels)), "..", "examples", "opf", "pglib")
include(joinpath(example_root, "transmission-opf.jl"))
using .TransmissionOPF

specs = operating_condition_specs(; network=:ieee300)
spec = only(filter(s -> s.id == :reserve_q90, specs))
data = operating_condition_case(spec)
model = TransmissionOPFModel(data)
# Further physical interpolation retains this same model and fixed policy.
custom = merge(spec, (id=:reserve_q88, q_upper_fraction=.88))
custom_data = operating_condition_case(custom)
```

## Reference and difficulty protocol

Run from the repository root in the optional PGLib environment:

```sh
julia --project=examples/opf/pglib examples/opf/pglib/search-operating-conditions.jl NEW_OUTPUT
# Alternatively prepare references first, then resume with the same frozen code.
julia --project=examples/opf/pglib examples/opf/pglib/search-operating-conditions.jl OTHER_OUTPUT --references-only
julia --project=examples/opf/pglib examples/opf/pglib/search-operating-conditions.jl OTHER_OUTPUT --resume
```

Each case receives a matched dispatchable NLP and a separate selected-sector
reference search. Sectors come from actual archived operating voltages,
continuation points or returned screening iterates. No desired coverage label
selects a sector. Start construction recomputes the existing curve/hinge values and clips its
initial P to existing device bounds; this adds no constraint or controller law.
Physical transfer is a start; it establishes feasibility only
when all original checks pass. A solver-produced point can establish numerical
feasibility without establishing an optimum or MPCC stationarity. Failed and
interrupted attempts remain available, and unresolved references are not called
infeasible.

The raw matrix uses the existing `current` and `ratio_one` profiles, each from
flat and independently verified reference starts. Both profiles have 500 inner
iterations and 30 native seconds; original feasibility is checked at 1e-5.
References and matched NLPs have 500 iterations/15 seconds with independent
original residual checks at 1e-7. Every request, input, start, returned point,
effective setting, source/environment fingerprint, status and solver log remains
in the raw archive. A missing reference produces an explicit unavailable start.
Raw outcomes are never replaced by refined points.

Difficulty labels describe these four attempts and this budget:

- `easy`: all four native-success/original-feasible outcomes.
- `mixed`: one to three such outcomes.
- `difficult_under_budget`: zero, with an independent feasible reference.
- `unresolved_reference`: no strict reference; report raw outcomes separately.

These labels do not rank global optimality, prove universal solver difficulty,
or demand that future CCOpt versions reproduce historical failures. Timings are
secondary observations; selection does not rank cases by runtime.

## Measured coverage and compact selection

`operating_condition_coverage` reports the existing per-controller curve regions,
fractions and margins, native bound IDs, and simultaneous case-level features:
strict VW plus generator-Q upper activity; strict VW plus thermal activity;
VV saturation plus Q-upper, voltage or thermal activity; and capability activity
alongside strict VW. Different plants may supply the different activities.
Co-occurrence is not a causal attribution or a feasibility certificate.

The curator adds achieved early/middle/late nonconstant-ramp strata (<.35,
.35–.65, >.65), strict-VW ramp strata, native bound types and near-knee distances
<=1e-4 pu. It measures these after solving; it never imposes them.

```sh
julia --project=examples/opf/pglib examples/opf/pglib/curate-operating-conditions.jl COMPLETED_OUTPUT NEW_RECEIPT.toml
```

The deterministic compact selection limits the collection to twelve verified
cases, with at most six per network. It first represents reserve/export on each
network, then observed difficulty strata and study groups, and finally adds
marginal physical coverage. Ties use case IDs. The complete candidate census and
raw sweep tables retain unselected cases and unsuccessful attempts. Complete
numerical evidence remains in the local research archive; selected references,
starts/returned points, effective settings and baseline points are retained in
a lossless portable receipt. Existing historical receipts are unchanged.

See [test tiers](TESTING.md), [evidence access](hard-cases/README.md), and the
[roadmap](ROADMAP.md) for validation and completion status.

## Recorded results — 26 October 2026

All 46 requested inputs were constructed and all 184 raw requests retained.
There are **45 strict feasible references**, **84 accepted raw outcomes**,
**97 native solver failures**, **one native-success/original-curve accuracy gap**,
and **two unavailable witness starts**. Of the native failures, 95 are on inputs
with independent strict feasible references; two are on the unresolved IEEE 300
0.80 upper-reserve input. No infeasibility claim is made for that input.

Across the full census, 14 cases pass all four attempts, 16 have mixed outcomes,
15 have zero accepted outcomes despite a feasible reference, and one remains
unresolved. The compact selection retains **five easy, two mixed and five
budget-difficult cases**, six per network, and covers **all 43 observed physical
features** under the documented feature vocabulary. Its maximum original
reference residual is 5.45e-12 pu. All references are numerical
feasibility witnesses, without global-optimality or full-MPCC stationarity claims.

| Retained input | Variables / pairs | Raw passes / 4 | Strict VW plants | VV injection / absorption plateaus | S circles | Native Q-upper / thermal ends |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `ieee118-absorption_a85` | 428 / 36 | 4 | 0 | 0 / 5 | 0 | 11 / 1 |
| `ieee118-absorption_a98` | 428 / 36 | 4 | 0 | 0 / 5 | 6 | 11 / 1 |
| `ieee118-export_r55` | 386 / 18 | 4 | 0 | 0 / 0 | 0 | 17 / 2 |
| `ieee118-injection_q90` | 428 / 36 | 0 | 3 | 3 / 0 | 0 | 38 / 3 |
| `ieee118-penetration_p85` | 428 / 36 | 4 | 6 | 0 / 0 | 0 | 7 / 1 |
| `ieee118-reserve_q80` | 428 / 36 | 1 | 0 | 0 / 0 | 0 | 20 / 1 |
| `ieee300-absorption_a85` | 822 / 36 | 0 | 0 | 0 / 2 | 0 | 32 / 5 |
| `ieee300-absorption_a98` | 822 / 36 | 0 | 0 | 0 / 2 | 2 | 32 / 5 |
| `ieee300-backstop_r100` | 780 / 18 | 0 | 1 | 0 / 0 | 0 | 33 / 4 |
| `ieee300-export_r100` | 780 / 18 | 2 | 0 | 0 / 0 | 0 | 35 / 5 |
| `ieee300-placement_6_dispersed` | 822 / 36 | 4 | 3 | 0 / 0 | 0 | 33 / 6 |
| `ieee300-reserve_q90` | 822 / 36 | 0 | 0 | 0 / 0 | 0 | 37 / 2 |

The IEEE 118 export boundary is slack at the looser ratings and becomes active
at factor .55. In IEEE 300 it is active throughout the sampled standard export
sequence. Backstop cases co-activate strict VW and native Q/thermal limits.
The IEEE 118 injection/reserve interaction also co-activates VV injection
saturation, strict VW and native limits. Both high-availability absorption
references activate S circles while retaining VV saturation.

The IEEE 300 dispersed six-plant case passes four of four raw attempts. The
clustered six-plant case and the original-site six/twelve-plant controls pass
zero. Geography and population comparisons are separate; same-site replication
preserves aggregate physical feasibility and does not establish that population
causes the observed difficulty. The two .85/.98 availability pairs provide
matched saturation/capability comparisons on both networks.

Strict VW ramp coverage includes early, middle and late strata, with heterogeneous
controller regions and near-knee points. **Simultaneous strict VW and S-circle
activity at different plants was not reached**, and native angle bounds remain
inactive. Full observed-feature coverage is not coverage of every possible or
intended combination. Those gaps are retained explicitly without changing the
operating laws or forcing voltages.

The [complete census](hard-cases/operating-conditions-census.tsv) records all 46
inputs; the [raw sweep](hard-cases/operating-conditions-sweep.tsv) records all 184
requests. Read `operating-conditions.toml` through the verified lossless receipt
resolver described in [evidence access](hard-cases/README.md). The 6.94 MB complete
raw archive preserves captured production source at `2bf9115`, environments,
all inputs/starts/returned points, reference attempts, baseline attempts and logs.
Its file manifest round-trips, with 1,647 original files unchanged. Complete raw
archives remain local; the selected point-level receipt and tables are committed.

A subsequent constructor fix makes explicit policy `profile_shift` overrides
apply consistently to both curves; all matrix shifts are zero, so every recorded
physical input hash and historical receipt remains unchanged.
