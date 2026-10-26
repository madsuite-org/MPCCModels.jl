# Application operating coverage and fixed-total fleets

This extension follows the [application catalog](APPLICATIONS.md). It retains
balanced IEEE 118 AC physics and makes operating policies and plant geography
explicit. All profiles are synthetic study settings, not prescribed grid-code
values or calibrated feeder controls. Intended regimes are descriptive; no
constructor fixes voltages, chooses sectors from targets, or assumes coverage.

## Nine operating-policy inputs

`application_policy_case(policy; laws=:both, hinge_encoding=:separate)` uses the
same data-to-ADNLPModel/MPCCModel design as other examples. Its card records the
base application, operating parameters, relative profile knots/ordinates and
rationale. Original plant-specific voltage shifts are retained; all knots stay
inside original bus bounds. Profiles change policy service limits/export caps,
while hardware circles and Q boxes remain independent and unchanged from the
specified base operating point. The four policy enablement variants have
identical physical inputs.

| Policy | Base application | Physical change | Intended coverage |
| --- | --- | --- | --- |
| `absorption_service` | Renewable surplus, elevated; availability .85S | ±.25S VV service at [.95,.985,1,1.02], delayed VW [1.04,1.053] | Absorption saturation with hardware headroom |
| `injection_service` | Reactive support, severe; Q factor .3, availability .85S | VV [.12,0,0,−.25]S at [1.025,1.04,1.047,1.053] | Limited reactive participation reaches injection saturation |
| `early_export_backstop` | Export corridor, elevated; rating factor .8 | Wide VV deadband [.99,1.035], ±.25S service; VW [1,1.02] with [1,.65]S | Lower VW plateau with strict curtailment |
| `early_absorption_backstop` | Renewable surplus, elevated | VW [1.0165,1.0285], [1,.2]S; original VV | Earlier active intervention along absorption ramp |
| `middle_absorption_backstop` | Same | VW [1.0285,1.0405], [1,.2]S | Intermediate absorption position |
| `late_absorption_backstop` | Same | VW [1.0405,1.0525], [1,.2]S | Later absorption position |
| `gentle_watt_cap` | Renewable surplus, elevated | VW [1,1.04], [.82,.815]S; original VV | Export ceiling and gentle voltage backstop |
| `firm_watt_cap` | Same | VW [1,1.04], [.82,.80]S | Stronger backstop with strict availability slack |
| `steep_watt_cap` | Same | VW [1,1.04], [.82,.76]S | Strong backstop and different local equilibria |

The last three policies include an interconnection active-export ceiling below
available renewable power. Their total curtailment therefore includes that
ceiling; do not attribute all curtailed power to the voltage-dependent ramp.
The absorption-backstop policies share hardware/availability/VV and change only
the VW voltage window. All achieved fractions, plateaus and active constraints
are measured at verified points, separately from the intended descriptions.

```julia
include("examples/opf/pglib/transmission-opf.jl")
using .TransmissionOPF

data = application_policy_case(:early_export_backstop)
card = application_policy_card(:gentle_watt_cap)
```

## Population and geography

`application_fleet_case(:reactive_support; level=:elevated, count=12,
placement=:dispersed)` splits each of the six original heterogeneous profile
classes into proportional units. Counts 6/12/24 preserve each class's aggregate
S rating, P availability, hardware Q boxes and normalized VV/VW curves. Total
installed size stays **900 MVA**, availability **765 MW**. Classes are assigned
round-robin in original order, so rating-weighted profile mixture is unchanged.

- `:same_sites`: proportional units remain at their original six connection
  points. Aggregate physical feasibility is preserved; increasing unit count adds
  representation size and repeated hinges. This is the explicit count control.
- `:clustered`: distinct eligible sites are ordered by hop distance from original
  bus 44, breaking ties by original bus ID.
- `:dispersed`: starts at bus 44, then greedily maximizes minimum hop distance to
  selected sites, with original ID breaking ties.

Distinct-site sets are nested for increasing counts, exclude the reference bus,
and retain valid original voltage bands for all profiles. They may include
conventional-generator and zero-load buses. These are topology-based study
placements, not voltage-sensitivity rankings or calibrated development plans.
More distinct sites intentionally changes geography; it is not a pure count
experiment. Compare placements at fixed count and use same-site replicas as the
aggregate-physics control.

| Units | Separate hinge pairs | Variables | Ordinary constraints |
| --- | --- | --- | --- |
| 6 | 36 | 428 | 848 |
| 12 | 72 | 512 | 902 |
| 24 | 144 | 680 | 1010 |

`application_fleet_start(target, source, x)` copies network variables and splits
plant P/Q by profile class, then constructs exact target hinges. At the same
sites the original physical reference remains feasible up to numerical tolerance.
For relocated plants the transfer is only a start and generally violates balance
or laws; it is never called a witness without rechecking the full original model.

## Recorded protocol

```sh
julia --project=examples/opf/pglib examples/opf/pglib/test-expansions.jl
julia --project=examples/opf/pglib examples/opf/pglib/search-expansions.jl \
  --kind=coverage --out=examples/opf/pglib/search-results/ieee118-coverage-2026-10-25
julia --project=examples/opf/pglib examples/opf/pglib/search-expansions.jl \
  --kind=fleet --profiles=ratio_one \
  --out=examples/opf/pglib/search-results/ieee118-fleets-2026-10-25
```

The coverage batch records **36 raw trials**: nine inputs × current/ratio_one ×
flat/reference starts. The fleet batch records **18 raw trials**: nine inputs ×
ratio_one × flat/reference starts. Each batch also retains nine matched
ordinary-NLP dispatchable counterfactuals, warmups and reference attempts.
Raw budgets are 500 iterations/60 seconds, inner tolerance `1e-9`, and original
physical acceptance `1e-5`; references must verify at `1e-7`. Identical arguments
with `--resume` preserve completed attempts; `--summarize=DIR` rebuilds reports.
The long matrices remain manual research runs; CI checks constructors,
equivalence/invariants, derivatives and archived numerical evidence.

Every input receives a transferred start from the committed original application
reference. Its source, complete target input and actual vector are recorded.
The transfer is explicitly a non-solver record. When it independently satisfies
the target model it can establish feasibility; otherwise it remains only a start.
Separate operating-reference NLPs select sectors by the transferred voltage's
hinge signs. Returned-iterate reference NLPs use signs from actual raw iterates.
No intended-region label chooses a sector. All attempts, failures and verified
reference coverages are reported; no raw result is polished or replaced.

A verified physical transfer is retained even if a subsequent NLP solve fails.
Otherwise a verified operating/returned reference or raw point supplies the
reference start. Records distinguish constructed points from solver results.
Selected-sector/local references establish numerical feasibility and measured
activity, not full MPCC stationarity or a global optimum. Raw optimizers may
reach different regions from the operating reference; retain both rather than
claiming one canonical activity pattern.

## Measured coverage and difficulty (2026-10-25)

All **18 inputs** have independently checked feasible references, and all
18 matched dispatchable NLP counterfactuals pass original checks. The two
recorded cohorts contain **54 raw trials: 36 physical passes and 18 iteration-
limit exits**, with no exceptions, unavailable starts or solved-status physical
accuracy gaps. Feasibility verification remains independent of solver status.

| Coverage policy | Physical passes / 500-iteration exits (four starts/settings) |
| --- | --- |
| Absorption service | 4 / 0 |
| Injection service | 0 / 4 |
| Early export backstop | 2 / 2 |
| Early absorption backstop | 3 / 1 |
| Middle absorption backstop | 4 / 0 |
| Late absorption backstop | 4 / 0 |
| Gentle / firm / steep watt caps | 4 / 0 each |

The coverage cohort has 29 passes and seven exits. At verified operating or
returned-iterate references it adds:

- VV absorption plateau at five plants, plus an absorption endpoint in the
  operating reference. The raw solutions also reach absorption saturation.
- VV injection plateau at three plants under limited reactive-service
  participation. All four raw injection-service trials reach 500 iterations
  despite independently feasible references.
- A strict VW lower plateau at one plant in the early export backstop reference,
  with P below availability and the cap at .65S. Raw endpoints need not retain
  that regime; the different reference modes are preserved explicitly.
- Absorption-ramp fractions near **0.2, 0.5 and 0.8** across the staggered
  backstops. The old application-point transfer and selected operating sector
  can reach different fractions from the returned-iterate reference; the table
  of all verified points retains those distinctions.
- Strictly binding VW ramps with availability slack and fractions spanning
  roughly **0.25–0.79**, including interior low/middle/high strata. These differ
  from the availability crossovers dominating the first catalog.

The portable dataset contains **39 verified references** across 18 cases,
including five independently verified physical transfers. The remaining points
are solver-derived selected-sector references. They are feasible operating/local
reference points, not global or full-MPCC optimality certificates. Some separate
reference attempts do not verify; those attempts remain in the full archives.

| Placement | 6 units: passes / exits | 12 units | 24 units |
| --- | --- | --- | --- |
| Same six connection points | 0 / 2 | 0 / 2 | 0 / 2 |
| Clustered distinct sites | 0 / 2 | 0 / 2 | 2 / 0 |
| Dispersed distinct sites | 1 / 1 | 2 / 0 | 2 / 0 |

The fleet cohort has seven passes and eleven exits. Within dispersed fleets, only the six-unit
flat start fails; its reference start passes. All 6/12/24 same-site cases have
verified constructed references with identical aggregate physical feasibility.
Changing distinct-site count changes placement and capacity per connection, so
the clustered recovery at 24 units does not establish a pure controller-count
benefit. The cohorts shared the host with each other and validation work; wall
times are observational, not a calibrated runtime ranking. All failures above
are iteration limits rather than wall-time exits.

The [portable expansion records](hard-cases/README.md#operating-coverage-and-fleet-records)
retain case specifications, reference kinds, points, checksums, baselines,
representative raw starts/results, the full 54-row census and measured fractional
coverage. Missing/next coverage work is application-specific placement and
operating transitions, matched VV-only/VW-only characterization and wider
networks. IEEE 300 remains the next network import/validation milestone; reducing
or diagnosing a solver failure is not a prerequisite.

Validation: **2,648 expansion/model/archived-record assertions** pass on Julia
1.10.12 and 1.12.6; existing 1,320 application and 578 transmission-model
assertions pass on Julia 1.12.6. Documenter builds locally with external link
checks disabled. Resume preserves all **540 raw, baseline and sector-reference
files** byte for byte. The injection-service ratio_one/flat request replays to
500 iterations with an identical returned vector and original residuals.

Complete local archives, excluded from Git:

- `search-results/ieee118-coverage-2026-10-25.tar.gz`, SHA-256
  `8ca51806b0b0c83faa068126fcbc7c1be44f91fd2065e094863059e30817be37`.
- `search-results/ieee118-fleets-2026-10-25.tar.gz`, SHA-256
  `f98c1b13c75d4a210b95a50a6328adc8f99e49411f53fadb73823d6fecfcb164`.

## IEEE 300 policy and reserve extension

The [IEEE 300 policy matrix](POLICY_MATRIX.md) uses the same constructors and
recorder with network-specific policy cards and verified operating anchors.
`application_policy_case(...; network=:ieee300)` selects its six policies;
`application_reserve_case(:mild/:moderate/:strong)` changes only conventional Q
upper bounds. `application_expansion_specs(:policy_matrix; network=:ieee300)`
combines these nine inputs. IEEE 118 defaults, policy definitions and archived
inputs retain their identities. IEEE 300 fleet geography is intentionally not
inherited from the IEEE 118 placement rules.
