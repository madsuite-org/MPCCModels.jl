# IEEE 300 application families

The optional transmission example now imports the unmodified IEEE 300 case from
[PGLib v23.07 at the pinned revision](https://github.com/power-grid-lib/pglib-opf/blob/dc6be4b2f85ca0e776952ec22cbd4c22396ea5a3/pglib_opf_case300_ieee.m).
Its SHA-256 is recorded in `data/SHA256SUMS`; the imported Git blob matches upstream
`92d03963ed36dd4072915b1cdfabf5a7273b02cc`. Source attribution and CC BY 4.0 licensing
are retained. These application overlays are synthetic studies, not official
PGLib instances or prescribed inverter/grid-code settings.

## Canonical AC OPF

The source contains 300 buses, 411 branches and 69 generators, with 23,525.85 MW
and 7,787.97 Mvar aggregate demand on a 100-MVA base. Bus IDs are nonconsecutive,
including transformer-side and low-voltage IDs up to 9533. All source IDs map
explicitly to model positions. Taps, phase shifts, shunts, line charging, both
branch-end thermal limits, angle bounds, voltage bounds and conventional P/Q
boxes/costs are retained. Only the reference angle is fixed.

The canonical model is an ordinary ADNLPModel with 738 variables and 1,833
constraints. Independent PowerModels/Ipopt and our MadNLP solve agree at an
objective of approximately **565,219.990890** (local solutions, no global
certificate). The PowerModels point is also evaluated in our formulation and
by independent complex-current balance. Run:

```sh
julia --project=examples/opf/pglib examples/opf/pglib/validate-baselines.jl
julia --project=examples/opf/pglib examples/opf/pglib/test-ieee300.jl
```

## Physical study matrix

The [application parameter table](APPLICATIONS.md#physical-case-definitions)
applies on both IEEE 118 and IEEE 300: three application families, each at
nominal/elevated/severe operating levels. Network-specific connection points
and rating templates distinguish IEEE 300. These are explicit topology/load
placements, not sensitivity rankings. The six-plant full rating is 6,600 MVA,
roughly 28% of original demand in MW; the three-plant export template is
3,800 MVA, roughly 16%. These rounded rating templates are about 5.5 times the
IEEE 118 templates, retaining similar installed-capacity/original-demand ratios.
Installed size is subsequently multiplied by each level's penetration.
No assumption of equal achievable output or comparable difficulty across grids
follows from these rating choices.

| Family | Original connection bus IDs | Rating template, system-base pu | Placement rationale |
| --- | --- | --- | --- |
| `renewable_surplus` | 5,59,125,170,200,243 | 9,11,13,10,12,11 | Distributed load-area connections across the transmission network |
| `reactive_support` | 118,120,121,140,171,178 | 9,11,13,10,12,11 | Reactive-demand buses, including bus 118's 650-Mvar load and a 118/120/121 support cluster |
| `export_corridor` | 25,26,27 | 13,12,13 | Connected pocket 25/26/27/320, including bus 320's radial attachment; only its two boundary ratings scale |

The surplus connections are 115 kV except bus 243 (66 kV); the reactive sites
are 115 kV except bus 140 (230 kV). The export pocket is 115 kV, with original
boundary branches **63** (20–27, 148 MVA) and **66** (23–25, 677 MVA). Its
original demand is 144.4 MW / 21.4 Mvar. Severe export ratings become 103.6 and
473.9 MVA. The installed/available plant capacities deliberately exceed this
export interface: these are aggregate development-pressure studies, not claims
of validated hosting capacity or individually calibrated plant connections.

VV is a continuous piecewise linear Q equality; VW is an active-power cap.
Independent hardware circles/boxes remain present. Heterogeneous voltage shifts
and normalized profiles match the original family definitions. All control knots
lie in the original connection-bus voltage bands. Conventional Q reductions scale
both original Q bounds toward zero. Curtailment is available minus dispatched P.
No inverter priority/clipping policy or dynamic behavior is modeled.

The source has positive Q lower bounds at generator IDs **5**, **44** and **45**
(buses 76,242,243). Consequently `q_support` scaling moves these operating
intervals toward zero as well as narrowing them; it is not a nested one-sided
reserve reduction. A study that isolates Q upper headroom must hold Q lower
bounds fixed. The reported family parameters retain their exact signed-interval
definition on both networks.

```julia
include("examples/opf/pglib/transmission-opf.jl")
using .TransmissionOPF
card = application_card(:export_corridor; network=:ieee300)
data = application_case(:export_corridor; network=:ieee300, level=:severe)
model = TransmissionOPFModel(data)
# The same physical inputs support matched policies:
vw_only = application_case(:export_corridor; network=:ieee300,
                           level=:severe, laws=:vw)
```

The constructor defaults to IEEE 118. Its nine inputs and all archived IEEE 118
snapshot hashes remain unchanged, as does the original 22-case solved registry.
`application_cases(network=:ieee300)` lists nine physical operating inputs;
choose `laws=:dispatchable/:vv/:vw/:both` separately. Its case descriptors include
the network, while the IEEE 118 descriptor shape is retained. IEEE 300 intentionally does
not inherit the older overlays' solved-region targets.

## Characterization protocol

```sh
julia --project=examples/opf/pglib examples/opf/pglib/search-applications.jl \
  --network=ieee300 --out=examples/opf/pglib/search-results/ieee300-applications \
  --profiles=current,ratio_one --max-iter=500 --max-wall=60
```

The plan records the selected network and complete source/environment hashes.
Each input has a matched dispatchable NLP. Raw flat/profile trials run first;
separate exact-sector reference attempts choose sectors from actual iterates,
with checked neighboring operating points available as fallback. Witness starts
are independently feasible for the original MPCC at 1e-7. Raw solver status and
six original residuals are retained; physical passes use 1e-5. Failed reference
attempts and unavailable starts remain recorded. No reference replaces a raw
failure or certifies full-MPCC stationarity/global optimality.

Coverage reports distinguish curve regions/fractions, inverter capability and
availability, conventional P/Q boxes, bus-voltage limits and individual branch
ends. Coverage is meaningful only alongside original feasibility. A curtailed
plant with slack device caps is a candidate network/control interaction, not a
causal attribution. Increasing physical severity or network size need not increase
solver difficulty.

IEEE 118 and IEEE 300 differ in geography, native limits and placements as well
as size; this comparison does not isolate network size as the cause of any
solver difference. Same-plant hardware/policy counterfactuals within each input
provide the controlled comparisons.

## Measured physical coverage and CCOpt difficulty

The recorded matrix used Julia 1.12.6, CCOpt 0.1.0 and MadNLP 0.10.2, with
500 iterations / 60 seconds per solve. Current and ratio_one differ only in the
relaxation/barrier ratio (.01 versus 1); both use the recorded tolerances and
bound initialization. Starts are primal flat or checked reference points, not
full primal-dual warm starts. The source/plan and complete effective settings
are retained. Historical solver failures are evidence, not requirements on future
solver versions.

There were **36 requested trials: 32 actual solves and four unavailable reference
starts**. Outcomes were **11 passes, 20 solver failures and one original-VV accuracy
gap**. Of the solver failures, **16 have checked feasible witnesses** and four
belong to unresolved inputs. Seven controlled inputs have strict references
(maximum original residual **1.63e-8**, gate 1e-7). Seven matched dispatchable NLPs
pass; the elevated and severe reactive baselines also fail. Those two inputs are
unresolved feasibility studies, not established feasible CCOpt challenges or
proven infeasible problems. Local infeasibility statuses are not certificates.

In the table, **S** means solved and original-feasible at 1e-5, **L** means the
500-iteration limit, **I** is local infeasibility detection, **A** means solved
status with an original-law accuracy gap, and **—** means no verified start.
Numbers are iterations. C/R are current/ratio_one; F/W are flat/reference.

| Family / level | C/F | R/F | C/W | R/W |
| --- | ---: | ---: | ---: | ---: |
| renewable surplus / nominal | L/500 | S/355 | S/97 | S/281 |
| renewable surplus / elevated | S/405 | L/500 | S/196 | L/500 |
| renewable surplus / severe | S/317 | L/500 | S/390 | L/500 |
| reactive support / nominal | L/500 | L/500 | L/500 | L/500 |
| reactive support / elevated | L/500 | L/500 | — | — |
| reactive support / severe | L/500 | I/376 | — | — |
| export corridor / nominal | L/500 | L/500 | S/192 | S/143 |
| export corridor / elevated | L/500 | L/500 | L/500 | L/500 |
| export corridor / severe | S/94 | L/500 | S/100 | A/179 |

The accuracy gap is severe export / ratio_one / reference: solved status at
179 iterations, but direct VV error **1.04451e-5** exceeds the 1e-5 gate. Its
AC balance and lifted constraints are near 6e-13. The raw point is retained
without replacing it with a reference or loosening the gate.

The nominal reactive-support and elevated export inputs fail all four raw
profile/start combinations despite verified references. Elevated and severe
surplus fail ratio_one from both starts. Severe export passes current from
both starts while the milder elevated export fails both profiles: the physical
severity labels do not order solver difficulty.

Physical coverage below uses only strict references. I/D/A denote VV injection
ramp/deadband/absorption ramp; K2/K3 are reported knot positions. U/R/K1 denote
VW upper plateau/ramp/first knot. Native V and Q counts are lower/upper; P counts
and all individual IDs/margins remain in the portable receipt. Thermal counts
are branch ends, so a branch may contribute twice. Counts exclude fixed
conventional P/Q boxes.

| Family / level | VV parts | VW parts | S circles | VW caps | Curtailment MW | V lo/hi | Gen Q lo/hi | Thermal ends |
| --- | --- | --- | ---: | ---: | ---: | --- | --- | ---: |
| renewable surplus / nominal | 1I, 1D, 4A | 4U, 2R | 0 | 0 | 0.00 | 2/25 | 4/37 | 3 |
| renewable surplus / elevated | 1K3, 1I, 4A | 4U, 2R | 0 | 2 | 489.84 | 2/19 | 3/35 | 5 |
| renewable surplus / severe | 1K3, 1I, 4A | 6U | 3 | 0 | 1523.21 | 1/16 | 4/28 | 6 |
| reactive support / nominal | 1K2, 4I, 1D | 4U, 2R | 0 | 0 | 248.66 | 1/29 | 4/33 | 3 |
| reactive support / elevated | unresolved | — | — | — | — | — | — | — |
| reactive support / severe | unresolved | — | — | — | — | — | — | — |
| export corridor / nominal | 1K2, 2A | 1U, 2R | 0 | 0 | 293.42 | 3/27 | 3/35 | 5 |
| export corridor / elevated | 1I, 1D, 1A | 2U, 1K1 | 0 | 0 | 1435.83 | 3/25 | 4/34 | 4 |
| export corridor / severe | 2I, 1A | 3U | 0 | 0 | 3016.23 | 2/24 | 4/29 | 5 |

All seven references activate native voltage, conventional P/Q and thermal
limits. Severe export activates the **to ends of both boundary branches 63 and
66**; its dispatchable baseline already curtails 3,004.72 MW, versus 3,016.23 MW
at the controlled reference. Native export headroom is therefore a major part
of this instance, rather than an assumption that all curtailment is VW-driven.
The two tight VW caps in elevated surplus coincide with availability crossovers.
No strict VW limitation with slack availability is established by this cohort.
These are comparisons of reported local points, not global objective gaps.

Coverage gaps remain: neither VV outer plateau nor the VW lower plateau is
reached in this cohort, strict VW limitation is missing, and no native angle limit activates. Plant Q boxes are
outside the entire VV range by design (±.5S versus ±.4S), so their inactivity is
structural. The next policies should study explicit reactive-service saturation
and earlier active-power backstops, rather than adding redundant bounds just to
mark another activation.

## Isolated physical responses

Two pairs of selected-sector local NLP solves use identical starts, solver
settings and hinge masks within each pair. They test one physical change each;
they are separate from the 32 raw CCOpt solves. All four returned points satisfy
the original corresponding inputs at 1e-7. The response is local to the recorded
sector and is not a global sensitivity or proof about the full MPCC optimum.

| Severe family | Single change | Reference curtailment MW | Modified MW | Observed response |
| --- | --- | ---: | ---: | --- |
| Surplus | Increase only S-circle ratings by 10%; retain availability, Q boxes and both laws | 1,523.21 | 1,520.19 | Three binding S circles release; availability and upper-plateau VW caps become jointly active at those plants |
| Export | Restore only the two cutset ratings from .7 to 1.0 of original | 3,016.23 | 2,754.91 | More active export, while both boundary to-end limits remain active |

The surplus objective decreases by 110.94 and the export objective by 5,166.00
at these local points. The three newly tight VW caps in the oversized case also coincide with
availability; they are not evidence of independent VW curtailment. Oversizing
alone therefore supplies little extra active production under the unchanged controls/network; the export interface change
has a much larger dispatch response. The strongest reactive inputs lack a
verified reference, so they are excluded from this paired sensitivity cohort.

## Reproduce and extend the records

The portable [receipt](hard-cases/README.md#ieee-300-application-records) includes the two
canonical points, all 32 actual raw returned points and starts, four unavailable
starts, nine dispatchable outcomes, seven strict controlled references, four
local sensitivity points, coverage, hashes and effective solver settings. The
[sweep table](hard-cases/ieee300-applications-sweep.tsv) includes every requested
trial. Tests reconstruct the physical inputs and re-evaluate archived evidence;
they do not require CCOpt to retain historical failures.

```sh
# Choose fresh directories for each new experiment.
julia --project=examples/opf/pglib examples/opf/pglib/hard-cases/validate-ieee300.jl CANONICAL_DIR
julia --project=examples/opf/pglib examples/opf/pglib/hard-cases/study-ieee300-limits.jl SEARCH_DIR SENSITIVITY_DIR renewable_surplus
julia --project=examples/opf/pglib examples/opf/pglib/hard-cases/study-ieee300-limits.jl SEARCH_DIR SENSITIVITY_DIR export_corridor
julia --project=examples/opf/pglib examples/opf/pglib/hard-cases/curate-ieee300.jl SEARCH_DIR CANONICAL_DIR OUTPUT.toml SENSITIVITY_DIR
```

The recorded production source is commit `42a641d`, with exact source hashes and
copies in each archive. A subsequent catalog-only change includes `network` in
IEEE 300 case descriptors; constructors reproduce the recorded input hashes.
Resume before the catalog metadata change preserves all **312 raw/baseline/reference/input
files** byte for byte. New searches use the current source and a new directory.
See [archive details](hard-cases/README.md#ieee-300-application-records) for local
archive checksums and the retained interrupted exploratory run.

The subsequent [policy matrix](POLICY_MATRIX.md) implements strict VW caps,
reactive saturation, an early backstop and feasible one-sided Q-upper reserve
studies. Fixed-total fleets with voltage-class/interface eligibility and further
operating sequences remain priorities. These address
physical coverage gaps while retaining the difficult feasible inputs already
found; algorithm diagnosis is not a prerequisite for growing the catalog.

Validation: **1,146 IEEE 300 assertions** pass on Julia 1.10.12 and 1.12.6.
The original application/expansion and transmission regression checks pass;
the five-network canonical cross-check passes. Documenter builds locally with
external link checking disabled. Remote CI has not yet been run.
