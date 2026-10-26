# Application-driven balanced OPF families

These families study steady-state economic dispatch with voltage-responsive
aggregate inverter plants in the pinned PGLib IEEE 118 and IEEE 300 transmission networks.
Local VV/VW functions have an established PV voltage-regulation application;
see the [NREL/Hawaiian Electric simulation and field pilot report](https://research-hub.nlr.gov/en/publications/advanced-inverter-voltage-controls-simulation-and-field-pilot-fin/).
The inputs here are synthetic balanced transmission proxies: neither calibrated
feeders nor prescribed grid-code settings. They do not represent dynamic
stability, inverter priority logic, regulator switching or time-series energy
production. Conventional generation retains PGLib costs and P boxes.

## Physical case definitions

`application_case(family; network=:ieee118, level=:nominal, laws=:both, parameters=(;),
hinge_encoding=:separate)` creates an ordinary ADNLPModel-compatible data record.
`TransmissionOPFModel(data)` returns the existing ADNLPModel or MPCCModel.
`application_card(family)` describes the motivation, sites, rating template,
intended interactions and applicable knobs. `application_cases()` lists the
initial nine operating points, separately from the original 22 solved cases.
Pass `network=:ieee300` to the case, card, parameters or catalog functions for
the larger network. The [IEEE 300 guide](IEEE300.md) defines its placements,
ratings, canonical validation and measured characterization. Tables below
describe the original IEEE 118 placements; the operating parameter table applies
to both networks.

The system base is 100 MVA. Plant ratings below are system-base pu before the
penetration multiplier. Availability means `P_available/S`; all plant Q boxes
are ±0.5S. Plant active production costs are zero; conventional costs supply the
economic dispatch objective. Curtailment is availability minus dispatched P.

| Family | Physical interpretation | Sites (original bus IDs) | Rating template |
| --- | --- | --- | --- |
| `renewable_surplus` | Increasing renewable output with lighter demand and reduced inverter reactive headroom | 20,45,53,70,95,110 | 1.6,2.0,2.4,1.8,2.2,2.0 |
| `reactive_support` | Available conventional Q operating ranges shrink while load and inverter active availability increase | 44,45,46,94,95,96 | 1.6,2.0,2.4,1.8,2.2,2.0 |
| `export_corridor` | Three plants export from buses 20–22 through the two boundary circuits | 20,21,22 | 2.4,2.2,2.4 |

Sites are explicit study placements, not sensitivity-ranked or utility-calibrated
locations. Nominal/elevated/severe describe physical operating parameters, not
predictions of solver performance. Several parameters change together in these
named scenarios; use individual overrides for isolated sensitivities.

| Family | Level | Load P/Q factor | Plant S multiplier | P availability/S | Conventional Q factor | Corridor rating factor |
| --- | --- | --- | --- | --- | --- | --- |
| renewable surplus | nominal | 1.00 | .35 | .75 | 1 | 1 |
| renewable surplus | elevated | .85 | .65 | .90 | 1 | 1 |
| renewable surplus | severe | .65 | 1.00 | 1.00 | 1 | 1 |
| reactive support | nominal | 1.00 | .50 | .60 | 1 | 1 |
| reactive support | elevated | 1.05 | .75 | .85 | .5 | 1 |
| reactive support | severe | 1.10 | 1.00 | .95 | .2 | 1 |
| export corridor | nominal | 1.00 | .35 | .75 | 1 | 1 |
| export corridor | elevated | .95 | .70 | .90 | 1 | 1 |
| export corridor | severe | .90 | 1.00 | .98 | 1 | .7 |

Q factors multiply both original conventional Q bounds toward zero. All
conventional P bounds/costs, topology, taps, charging, shunts, bus bounds and
angle limits remain unchanged. The corridor is the exact cutset of buses
20,21,22: original branches **25** (19–20) and **29** (22–23), each originally
1.78 pu. Only those two ratings are scaled in the export family. All other
original thermal limits remain present in every family, so other constraints
may also bind. Files are unchanged; complete overlays/parameters are saved.

Each plant has a distinct profile shift from
`[-.006,+.006,0,-.003,+.003,-.004]` in site order (first three for export).
VV has Q/S `[.4,0,0,-.4]` at voltage knots `[.95,.99,1.01,1.05]` for renewable/
export, and `[.95,1.025,1.04,1.053]` for reactive support. VW has P/S `[1,.2]`
at `[1.022,1.052]`. Shifts apply to both curves. All default knots lie inside
original bus voltage bounds. A `profile_shift` override must keep them there.
VV is an equality and VW an upper bound; S circles and hardware boxes are
independent constraints. These curves do not implement a separate priority or
clipping policy. The reactive-support profiles represent a higher voltage
support setpoint than the other two families.

```julia
include("examples/opf/pglib/transmission-opf.jl")
using .TransmissionOPF

surplus = application_case(:renewable_surplus; level=:severe)
reactive = application_case(:reactive_support; level=:elevated,
    parameters=(q_support=.35,))
export_case = application_case(:export_corridor; level=:severe)
relaxed_export = application_case(:export_corridor; level=:severe,
    parameters=(export_rating=.8,))
dispatchable = application_case(:export_corridor; level=:severe, laws=:dispatchable)
```

The four matched policies `:dispatchable/:vv/:vw/:both` share the exact hardware,
availability, costs and network data. Only enabled laws differ. Knobs listed in
each card can be overridden independently. Population/placement builders remain
available for further studies; the initial catalog uses distinct sites and
heterogeneous profiles rather than a redundant same-bus fleet.

## Validation and characterization protocol

```sh
julia --project=examples/opf/pglib examples/opf/pglib/test-applications.jl
julia --project=examples/opf/pglib examples/opf/pglib/search-applications.jl \
  --out=examples/opf/pglib/search-results/ieee118-applications-2026-10-25
# Resume with the identical arguments plus --resume; or rebuild reports:
julia --project=examples/opf/pglib examples/opf/pglib/search-applications.jl \
  --summarize=examples/opf/pglib/search-results/ieee118-applications-2026-10-25
```

The default records **36 raw both-law trials** (nine inputs × flat/witness ×
current/ratio_one), plus **nine matched dispatchable NLP counterfactuals**.
Budgets are 500 iterations and 60 seconds, inner tolerance `1e-9`, with original
physical acceptance at `1e-5` and strict witness verification at `1e-7`.
A one-iteration warmup per profile is retained separately. Optional explicit seeds
add perturbed witness starts; trace recording is available but off by default.
Flat results are saved before witness construction and never replaced.

A witness is an original-feasible raw point or a separately labelled exact-sector
solve selected by observed hinge signs from an actual returned iterate. When
necessary, a previously verified operating point in the same application family
provides a separately recorded neighboring start/sector. No desired regime or
bound target chooses a sector. A failed witness search remains unresolved
feasibility. These numerical witnesses do not establish full MPCC stationarity
or a global optimum. Witness-start raw trials remain independent recorded runs.

`application_coverage(data,x)` reports measured curve regions/fractions and
knot distances, P availability/injection/curtailment in MW, Q signs, VW/capability
activity, conventional P/Q limits, voltage bounds, both thermal ends and angles.
Fixed conventional boxes are excluded from activity counts. Intended effects
are card metadata, not constructor assertions. Use physical checks before
accepting a point's coverage. Curtailment with slack device caps is only a
candidate network/control interaction; a binding margin alone does not assign
causality or establish an economic sensitivity.

`summary.toml` separates per-input witness coverage, counterfactual results and
all raw outcomes. `summary.tsv` retains status, original residuals and curtailment
for every attempt, with superseded attempts labelled. Input snapshots, starts,
points, solver options, provenance and source/environment hashes follow the
[hard-search recorder](HARD_SEARCH.md). Constructor, matched-input, sparse
Jacobian/Hessian, snapshot and failure-retention tests run independently of
whether CCOpt happens to find a hard input on a future release.

## First measured catalog (2026-10-25)

All nine inputs have verified numerical witnesses at `1e-7`; all nine matched
dispatchable NLP counterfactuals pass original physical checks. The 36 raw
combined-policy trials give **26 physical passes and 10 iteration-limit exits**,
with no accuracy-gap classifications, exceptions or unavailable starts.
The table describes the protocol's selected feasible reference points; they
are not guaranteed global or full-MPCC optima and need not have unique activity.

| Family | Level | Reference curtailment (MW) | Observed reference mechanisms | Raw passes / iteration limits |
| --- | --- | --- | --- | --- |
| Renewable surplus | nominal | ≈0 | Six absorption ramps; availability/VW crossovers | 4 / 0 |
| Renewable surplus | elevated | ≈0 | Six absorption ramps; one original thermal end tight | 4 / 0 |
| Renewable surplus | severe | 0.528 | All six inverter S circles tight; an absorption knee | 4 / 0 |
| Reactive support | nominal | ≈0 | Two injecting plants, deadbands; 14 conventional Q upper limits tight | 3 / 1 |
| Reactive support | elevated | ≈0 | Three injecting plants; 25 conventional Q upper limits tight | 0 / 4 |
| Reactive support | severe | 354.549 | Injection/deadband/absorption/knee mixture; 40 Q upper limits and thermal limits tight | 0 / 4 |
| Export corridor | nominal | ≈0 | Three absorption ramps; boundary ratings slack | 4 / 0 |
| Export corridor | elevated | 92.584 | Injection/deadband/absorption across three plants; branch 25 boundary tight | 4 / 0 |
| Export corridor | severe | 394.860 | Both boundary circuits tight; curtailment with slack VW caps | 3 / 1 |

Physical severity is deliberately separate from measured difficulty: every
renewable-surplus trial passes, while elevated/severe reactive-support cases
challenge both solver profiles from flat and verified-witness starts. The
nominal reactive case and severe export case fail only for ratio_one/flat in
this run. Every failed input has a verified feasible point. The original PGLib
network contains other active limits; these are coupled applications, not
claims that a single limit alone explains every outcome.

The export dispatchable counterfactuals also curtail about 87.112 MW (elevated)
and 392.107 MW (severe), compared with 92.584/394.860 MW for the selected
controlled references. Those are local numerical comparisons with matched
hardware/network, not global optimality gaps.

### One-parameter physical comparisons

Six separately recorded exact-sector NLP solves compare each severe reference
with one changed physical parameter. A common source witness selects the sector;
reference and modified solves use identical physical starts, sector masks and
settings. All six points pass original checks at `1e-7`. These are local
selected-sector comparisons, not additional raw CCOpt homotopy trials.

| Physical change | Reference curtailment (MW) | Modified curtailment (MW) | Interpretation of measured response |
| --- | --- | --- | --- |
| Renewable availability/S 1.00 → .99 | 0.528 | ≈0 | Restores reactive headroom by reducing availability by 12 MW; actual injection decreases and conventional cost rises |
| Conventional Q-range factor .20 → .30 | 354.549 | 257.464 | Additional conventional reactive support reduces local curtailment and cost |
| Export boundary rating factor .70 → .80 | 394.860 | 359.044 | Additional corridor capacity increases local renewable dispatch and reduces cost |

The catalog covers injection/absorption ramp interiors, deadbands, a VV knee,
VW upper plateaus/ramp positions, inverter capability circles, conventional
P/Q bounds, voltage bounds and thermal limits. The selected application
witnesses do **not** yet cover both VV outer plateaus, the VW lower plateau,
or systematic ramp-fraction strata. Those are explicit next application-design
targets; they do not block retaining these meaningful easy and challenging
instances. VV-only/VW-only constructors are validated as matched inputs; the
first recorded characterization concentrates on combined and dispatchable laws.

Portable points, metadata and numerical checks are in
[the application receipt](hard-cases/README.md#application-catalog-records).
`ieee118-application-catalog.tsv` holds the nine physical reference rows;
`ieee118-applications-sweep.tsv` holds all 36 raw outcomes. Complete raw inputs,
starts, points, counterfactuals, witnesses and source/environment snapshots are
retained locally under `search-results/ieee118-applications-2026-10-25/`.
Paired local comparisons are retained separately under
`search-results/ieee118-application-sensitivities-2026-10-25/`.

Validation: **1,320 application/model/archived-record assertions** pass on Julia
1.10.12 and 1.12.6; existing 419 hard-search, 585 reduction and 578 transmission-
model assertions pass on Julia 1.12.6. Documenter builds locally with external
link checking disabled. Resume preserves all **235 raw/counterfactual/witness
files** byte for byte. Replaying reactive-support/elevated/ratio_one/flat again
reaches 500 iterations with an identical returned vector and physical residuals.

Complete local archives, excluded from Git:

- `search-results/ieee118-applications-2026-10-25.tar.gz`, SHA-256
  `fc6e7fc25db7b14d169756652b8fe2b2b3f9b323b16b305aad46953ddfea24ff`.
- `search-results/ieee118-application-sensitivities-2026-10-25.tar.gz`, SHA-256
  `da22d3ed8d8e6456755296a552ebd0b36daae4bb268e71bdb223454681a0ace3`.
