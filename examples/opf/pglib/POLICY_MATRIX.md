# IEEE 300 operating-policy matrix

This extension fills the first IEEE 300 cohort's missing strict VW curtailment,
VV saturation and VW lower-plateau coverage, and introduces a controlled study
of one-sided conventional reactive reserve. It reuses the optional transmission
model, validated source data and [application building blocks](APPLICATIONS.md).
The original IEEE 118 policies and archived input identities are unchanged.

These are synthetic steady-state policies for aggregate inverter plants. No
setting is a prescribed grid-code value or a calibrated utility interconnection
policy. Topology, losses, shunts, taps and native AC limits remain present. No
inverter priority/clipping policy or dynamic response is modeled.

## Physical inputs and matched comparisons

| Study | Inputs | Anchor | Single study axis |
| --- | --- | --- | --- |
| Strict VW | `gentle_watt_cap`, `firm_watt_cap`, `steep_watt_cap` | Elevated renewable surplus, availability .9S | Same normalized cap at the lower knot (.82S); terminal cap .815/.80/.76S |
| Absorption service | `absorption_service` | Elevated renewable surplus, availability .85S | Q service ±.25S; absorption plateau starts at 1.02 pu before site shifts; delayed VW backstop |
| Injection service | `injection_service` | Nominal reactive support with original conventional Q intervals | Q service ±.25S; injection plateau ends at 1.025 pu before site shifts |
| Earlier export intervention | `early_export_backstop` | Nominal export corridor | Broad VV deadband and VW cap decreasing from 1S to .65S over 1.00–1.02 pu before site shifts |
| One-sided Q upper reserve | `mild`, `moderate`, `strong` | Nominal reactive support | Retain .98/.95/.90 of each original Q-interval width while fixing its lower bound |

All voltage knots retain the original six heterogeneous site shifts and lie
within the original connection-bus voltage bands. Hardware S ratings, plant Q
boxes, availability and conventional P limits/costs match across the four law
variants of each input. The three strict VW cases additionally share every
physical input and the complete VV law; only VW terminal values change.
Different service policies intentionally change the operating law and, where
stated, availability. They are not a comparison that holds those policies fixed.

Reserve inputs keep load, plant hardware, both control laws, conventional P
limits/costs and every network limit unchanged. For retained fraction f,

`Qmax_new = Qmin_original + f*(Qmax_original - Qmin_original)`.

Every Q lower bound stays fixed. These Q boxes are nested as f decreases,
including the source generators with positive Q minima (IDs 5,44,45). The factor
scales interval width, not signed Qmax or Mvar capacity. Fixed Q intervals stay
fixed. No signed scaling toward zero occurs. `factor=1` restores the original
physical Q limits exactly. Other fractions in (0,1] are available explicitly.

```julia
include("examples/opf/pglib/transmission-opf.jl")
using .TransmissionOPF

specs = application_expansion_specs(:policy_matrix; network=:ieee300)
data = application_policy_case(:gentle_watt_cap; network=:ieee300)
reserve = application_reserve_case(:moderate)
custom = application_reserve_case(:moderate; factor=.97)
model = TransmissionOPFModel(reserve)
# Identical hardware/availability/network for a matched policy comparison:
vw_only = application_policy_case(:gentle_watt_cap; network=:ieee300, laws=:vw)
```

## Regime and feasibility qualification

`application_policy_coverage(data,x)` extends the legacy application report with
strict VW activity, joint availability/VW activity, strict S-circle activity and
strict plateau IDs. Legacy `application_coverage` returns its existing schema.

Strict VW requires a tight cap, P below availability, a slack S circle and
positive P. A tight cap at availability is reported separately. Strict plateau
positions require voltage to lie beyond the terminal knot by more than the
voltage tolerance. VV injection/absorption additionally requires a positive/
negative terminal Q beyond the power tolerance; a zero-Q plateau counts as
neither, and either side of a custom curve may have either polarity.
Power margins are system-base pu; voltage separation is
voltage pu. Defaults are 1e-5 for each. These are activity classifications, not
feasibility or unique-cause certificates. Native network limits may also bind.

References come from independently solved local sector NLPs. The initial sector
uses the actual voltage of a verified archived application point. If required,
continuation from a verified neighboring input and a separate recorded CCOpt
screening iterate supply further observed sectors. Intended regimes never fix
voltages or choose sectors. Every candidate, failed reference and screening
attempt is retained; numerical feasibility is checked against all six original
residual measures at 1e-7. References do not establish global optimality or
full-MPCC stationarity.

All nine candidate definitions obtain verified references with original residuals
below 2e-11. The cap variants each strictly limit four plants, absorption service
reaches two strict absorption plateaus, injection service reaches four injection
plateaus, and the early export backstop reaches two strict VW lower plateaus.
All three reserve inputs have verified references. Classification is measured
from returned points; it is not encoded as a constructor target.

## Reproduce reference validation and benchmarking

```sh
# Choose fresh directories; raw attempts are never overwritten.
julia --project=examples/opf/pglib examples/opf/pglib/hard-cases/validate-policy-matrix.jl REFERENCE_DIR
julia --project=examples/opf/pglib examples/opf/pglib/search-expansions.jl \
  --network=ieee300 --kind=policy_matrix --out=SEARCH_DIR \
  --references=REFERENCE_DIR/references.toml --max-iter=500 --max-wall=60
julia --project=examples/opf/pglib examples/opf/pglib/hard-cases/curate-policy-matrix.jl \
  SEARCH_DIR REFERENCE_DIR OUTPUT.toml
```

The reference receipt is copied into the benchmark archive and hash-checked in
the resume plan. Every supplied point must match the complete input snapshot and
pass original feasibility again before any raw solve. Its source trial and
fingerprint remain in the numerical evidence. The frozen matrix runs both
`current` and `ratio_one` from flat and prevalidated reference primal starts,
plus a matched dispatchable NLP per input. The raw CCOpt outcomes are never
polished or replaced by reference solves. This protocol keeps reference
validation separate from the difficulty benchmark.

New runs label an accepted supplied point `prevalidated_reference`, with its
original solver, physical-transfer or unknown origin retained separately in the
prepared record, trial provenance and summary. Validation establishes numerical
feasibility and does not establish that a solver produced the supplied point.
Historical receipts keep their original labels and source fingerprints.

## Verified physical coverage

All entries below use the independently checked operating references, not failed
raw iterates. Counts use the reported power/voltage tolerances. Thermal activity
counts branch ends. Fixed conventional P/Q boxes are excluded from native-limit
counts. The complete receipt retains all IDs, margins and curve fractions.

| Input | Strict VW | VV injection plateau | VV absorption plateau | VW lower plateau | Curtailment MW | Native V lo/hi | Native Q lo/hi | Thermal ends |
| --- | ---: | ---: | ---: | ---: | ---: | --- | --- | ---: |
| `policy-gentle_watt_cap` | 4 | 0 | 0 | 0 | 719.83 | 3/21 | 3/35 | 5 |
| `policy-firm_watt_cap` | 4 | 0 | 0 | 0 | 726.82 | 2/20 | 3/35 | 5 |
| `policy-steep_watt_cap` | 4 | 0 | 0 | 0 | 734.87 | 2/20 | 3/35 | 4 |
| `policy-absorption_service` | 0 | 0 | 2 | 0 | 445.31 | 2/25 | 5/32 | 5 |
| `policy-injection_service` | 0 | 4 | 0 | 0 | 0.00 | 5/25 | 6/32 | 2 |
| `policy-early_export_backstop` | 1 | 0 | 0 | 2 | 439.24 | 4/25 | 5/33 | 4 |
| `reserve-mild` | 0 | 0 | 0 | 0 | 243.77 | 1/27 | 3/35 | 3 |
| `reserve-moderate` | 0 | 0 | 0 | 0 | 235.39 | 2/28 | 3/35 | 2 |
| `reserve-strong` | 0 | 0 | 0 | 0 | 315.07 | 4/25 | 3/37 | 2 |

The cap-gain references strictly bind four VW caps each. Strict ramp positions
span approximately **.21–.78**, including quarter-ramp and late-ramp positions.
Some strictly binding caps are on the upper plateau; they are interconnection
export ceilings below availability. The early-backstop case reaches its lower
plateau at two plants, but only one is independently VW-limited under the stated
margin test. Plateau position and binding limitation remain separate outputs.

Across the reserve sequence, native Q upper-bound counts are **35,35,37**, and
lower-voltage counts are **1,2,4**. All original Q minima remain fixed. Curtailment
need not vary monotonically with the reserve factor: the table reports distinct
local sector solutions and reactive/active redispatch, not global optima.

S circles remain slack in these references. They complement the strict capability
activity already present in the original IEEE 300 surplus cohort. Plant Q boxes
are wider than the entire prescribed VV range, so their inactivity is structural.
No native angle limit activates. Remaining coverage priorities include strict
VW mid-ramp interiors, further reserve/operating trajectories and geographically
eligible multi-plant fleets.

## Recorded CCOpt difficulty

The benchmark used Julia 1.12.6, CCOpt 0.1.0 and MadNLP 0.10.2
on the frozen production source at commit `732d0dd`. Current and ratio_one use
the same initialization and stopping settings apart from the relaxation/barrier
ratio (.01 versus 1). Every raw solve has a 500-iteration / 60-second budget.
Starts are primal flat or independently prevalidated points, not full primal-dual
warm starts. No reference is chosen from a formal benchmark outcome.

**Four of 36 raw trials pass; 32 reach the 500-iteration limit. All 32 failures
are on known-feasible inputs.** There are no unavailable starts, exceptions or
solved-status accuracy gaps in this cohort. All nine matched dispatchable NLP
runs pass; the three cap-gain inputs share a physical dispatchable baseline.
All nine reference NLPs pass separately, with maximum original residual 1.73e-11.

S/L mean original-feasible solved status / iteration limit; numbers are iterations.
C/R are current/ratio_one and F/W are flat/reference.

| Input | C/F | R/F | C/W | R/W |
| --- | ---: | ---: | ---: | ---: |
| `policy-gentle_watt_cap` | L/500 | L/500 | S/447 | L/500 |
| `policy-firm_watt_cap` | S/305 | L/500 | L/500 | L/500 |
| `policy-steep_watt_cap` | L/500 | L/500 | L/500 | L/500 |
| `policy-absorption_service` | L/500 | L/500 | L/500 | L/500 |
| `policy-injection_service` | L/500 | L/500 | L/500 | L/500 |
| `policy-early_export_backstop` | L/500 | S/327 | L/500 | L/500 |
| `reserve-mild` | L/500 | L/500 | L/500 | L/500 |
| `reserve-moderate` | L/500 | L/500 | S/207 | L/500 |
| `reserve-strong` | L/500 | L/500 | L/500 | L/500 |

Steep VW, both saturation services, mild reserve and strong reserve fail all
four profile/start combinations. Gentle VW recovers only from its reference
under current; firm VW passes only from flat under current; the early backstop
passes only from flat under ratio_one; moderate reserve passes only from its
reference under current. Gain and reserve severity do not order difficulty,
and feasible starts do not guarantee recovery. These observations apply to the
recorded settings/budgets, not all solver configurations or future releases.

The [portable receipt](hard-cases/README.md#ieee-300-policy-matrix-records) retains all 36 raw
starts/returned vectors, nine independent reference records, nine matched
baseline records, exact options, source/input/point hashes and measured coverage.
The [sweep table](hard-cases/ieee300-policy-matrix-sweep.tsv) lists every raw trial.
Tests reconstruct inputs and check numerical evidence; they never require a
future CCOpt version to retain the historical failures.

Resume on the same source/environment preserves all **318 input, raw, baseline,
reference-receipt and captured-source files** byte for byte. Full archives and
their checksums are documented in the [record guide](hard-cases/README.md#ieee-300-policy-matrix-records).

Validation: **2,199 policy-matrix assertions** pass on Julia 1.10.12 and 1.12.6.
The existing 2,648 expansion assertions and 1,146 IEEE 300 assertions pass on
Julia 1.12.6. Checks cover original residuals, point hashes, strict versus joint
limits, achieved plateaus/ramp spread, bound nesting, law matching, sparse
derivatives, invalid prepared references and resume. Documenter builds locally
with external link checks disabled; remote CI remains pending.

The two original coupled signed-Q stress inputs retain their unresolved status.
The new one-sided reserve sequence is a separate verified family at the nominal
reactive operating point. Next studies are matched law variants, strict VW
mid-ramp policies, voltage-class/interface-eligible fleets and steady-state
operating trajectories through the verified reserve range.
