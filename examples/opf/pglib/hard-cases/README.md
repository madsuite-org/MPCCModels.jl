# Curated hard-case records

## Access and preservation

The eight historical TOML receipts described below are stored losslessly as
`evidence/*.toml.gz`. `evidence/index.toml` records compressed and original byte
counts and SHA-256 hashes. Resolve a receipt with
`HardCaseSearch.evidence_file("ieee300-policy-matrix.toml")` after including
`hard-search.jl` in the optional PGLib environment. Extraction is local, verifies
both hashes, and writes a content-addressed temporary cache. No download or
solver run is needed. Original receipt bytes, historical provenance and failure
records have not been edited. The TSV census/trace tables remain directly readable.

`fast-witnesses.toml` is a derived PR fixture containing 20 physical points:
three nominal IEEE 118 applications, two independent canonical IEEE 300 points,
all nine IEEE 300 policy/reserve references, and six selected operating-condition
references spanning both networks and all three observed difficulty strata. It records authoritative receipt
hashes, input hashes and Float64 bit hashes. It does not replace the full evidence.
Regenerate it with `curate-fast-fixtures.jl OUTPUT.toml`; exhaustive CI checks
byte-for-byte derivation from the full receipts.

`evidence/raw-archives.toml` indexes **all 15 complete local raw archives**, with
sizes and SHA-256 hashes, including exploratory and failed attempts. They remain
under ignored `../search-results/`. Package them together with the lossless
receipts for future distribution, without uploading or overwriting anything:

```sh
julia --project=examples/opf/pglib examples/opf/pglib/package-evidence.jl OUTPUT.tar
```

The command verifies every archive and receipt before packaging and writes a
SHA-256 sidecar. This preserves a complete transferable evidence bundle. Public
hosting remains a release task; raw-log archives are not yet downloadable from
this repository. `evidence/release-bundle.toml` identifies the verified local
26.7 MB preservation bundle and its checksum. See [test tiers](../TESTING.md) for mandatory PR checks and the
manual/weekly exhaustive gate. Historical source fingerprints belong to the
captured version; reproducing an old source-matched resume requires that version.

## Capability receipt

`ieee118-capability-082.toml` is a portable historical receipt from the first
capability search, not a requirement that future CCOpt releases keep failing.
It preserves the original numerical inputs to the starts/solver, returned
points, diagnostics, effective options and an independently checked feasible
witness. Float64 point/start bit hashes detect accidental changes to arrays.

The network is PGLib-OPF v23.07 IEEE 118 at the recorded revision and source-file
hash. Only `ibr3`'s S limit changes to 0.82 of nominal; its availability and
control curves stay fixed. Rebuild it with `HardCaseSearch.capability_case(0.82)`.
The receipt records the complete-input snapshot hash and source/environment
fingerprint from the full local search. Full snapshots and all trials remain
under the ignored `search-results/` directory; this receipt keeps representative
outcomes without duplicating the entire upstream network in Git.

The four raw rows are current/flat (iteration limit), defaults/flat (solved
status with an original-curve accuracy gap), current/neighbor (recovery), and
current/witness (recovery). The witness is a separate exact-sector NLP point;
it does not replace any of these raw results. No global optimality or full MPCC
stationarity is asserted. Tests re-evaluate the archived points rather than
requiring new solves to reproduce historical failure statuses.

From the repository root in the optional PGLib environment:

```julia
using TOML
include("examples/opf/pglib/hard-search.jl")
using .HardCaseSearch
receipt = TOML.parsefile(HardCaseSearch.evidence_file("ieee118-capability-082.toml"))
trial = receipt["trials"][1]
run_trial(capability_case(receipt["factor"]), trial["start"], trial["profile"],
    "NEW_REPLAY_DIRECTORY"; start_label = trial["start_label"],
    provenance = Dict("curated_source" => receipt["environment"]))
```

PGLib network data retain their original attribution and **CC BY 4.0** license;
see [source attribution](../data/README.md) and [upstream license](../data/LICENSE).
The normalized records and modified case are derived study instances, not new
official PGLib benchmark releases.

`ieee118-capability-sweep.tsv` retains the complete 160-row first-search table,
including failures and accuracy gaps. The full request/result/point/log/source
archive is preserved locally as
`../search-results/ieee118-capability-2026-10-24.tar.gz`; it is excluded from Git
along with the expanded output. The compact receipt above provides the committed
point-level reproduction, while the TSV records the whole experiment matrix.

## Ratio-one transition/Q-limit receipt

`ieee118-transitions-q45.toml` preserves numerical witnesses for all nine
transition/Q-limit inputs and the six raw central-case trials (zero VW offset,
Q upper limit 0.35 pu). It also retains the two neighboring Q-sensitivity
witnesses, solver profiles/options, actual starts/points, bit hashes, original
physical checks and achieved activity. Reconstruct each input with
`transition_case(; knee=record["knee"], offset=record["offset"], qmax=record["qmax"])`.
The complete 54-row census is `ieee118-transitions-sweep.tsv`.

```julia
receipt = TOML.parsefile(HardCaseSearch.evidence_file("ieee118-transitions-q45.toml"))
trial = only(filter(t -> t["start_label"] == "flat", receipt["trials"]))
data = transition_case(; knee=trial["knee"], offset=trial["offset"], qmax=trial["qmax"])
run_trial(data, trial["start"], trial["profile"], "NEW_TRANSITION_REPLAY_DIRECTORY";
    start_label=trial["start_label"], provenance=Dict("curated_source" => receipt["environment"]))
```

All three devices share bus 95 and normalized profiles. Zero offset aligns the
VV deadband/absorption knee with VW onset; nonzero offsets separate the knees.
Generator 45 at bus 100 has the only changed network bound. The setup uses its
original Q limit and is retained separately. Independent selected-sector
witnesses establish numerical feasibility and achieved activity, without
certifying full MPCC stationarity. CI rechecks archived arrays; it does not
require a future solver to reproduce historical iteration limits.

Complete inputs, logs, all raw attempts, source/environment snapshots, a raw
replay and Q sensitivities are retained locally under
`../search-results/ieee118-transitions-2026-10-24/` and its sibling `.tar.gz`.
These research artifacts are excluded from Git; the receipt and TSV above are
portable committed records.

## Controlled reduction records

`ieee118-reductions.toml` preserves all 12 constructed feasible witnesses, ten
representative raw points and the separate 2,000-iteration reference. Rebuild
inputs using `reduction_case(; encoding=Symbol(row["encoding"]),
controlled=row["controlled"], plateau=Symbol(row["plateau"]))`. The witnesses
are transfers of the archived central physical point, independently checked
against each target input; they are explicitly labelled as constructions with
no new solver invocation or optimum claim.

The records include the smallest observed iteration-limit example: one
controller and five shared hinges, with a crossover inside the VW ramp, failing
from flat. Its separate-hinge counterpart passes from the identical physical
start. Other records retain the reverse contrast, where sharing resolves a
solved-status accuracy gap, and the original three-controller failure followed
by a larger-budget solved status that still violates the direct VV law.

```julia
receipt = TOML.parsefile(HardCaseSearch.evidence_file("ieee118-reductions.toml"))
trial = only(filter(t -> t["encoding"] == "shared" && t["controlled"] == 1 &&
    t["plateau"] == "crossing" && t["start_label"] == "flat", receipt["trials"]))
data = reduction_case(; encoding=Symbol(trial["encoding"]),
    controlled=trial["controlled"], plateau=Symbol(trial["plateau"]))
run_trial(data, trial["start"], trial["profile"], "NEW_REDUCTION_REPLAY_DIRECTORY";
    start_label=trial["start_label"], trace_every=trial["trace_every"])
```

`ieee118-reductions-sweep.tsv` holds all 60 raw outcomes and physical residuals.
`ieee118-reductions-traces.tsv` holds representative iteration series for the
separate/shared one-controller equal/crossing contrasts and the larger-budget
reference. Original complete logs, inputs, starts, points, witnesses, source and
environment snapshots remain in the two local ignored directories
`../search-results/ieee118-reductions-2026-10-25/` and
`../search-results/ieee118-reduction-seeds-2026-10-25/`, with sibling `.tar.gz`
archives. Source PGLib attribution and license remain unchanged.

## Application catalog records

`ieee118-applications.toml` preserves nine physically verified application
reference points, nine matched dispatchable NLP points, eight representative raw
trials and six paired local physical-parameter comparisons. Inputs rebuild with
`TransmissionOPF.application_case(Symbol(row["family"]);
level=Symbol(row["level"]))`; sensitivity rows additionally supply their recorded
physical overrides. Every point has a Float64 bit hash and original residuals.
Source/input/request/environment hashes and actual starts/solver settings are
retained. Tests evaluate the archived numerical evidence without requiring
future CCOpt versions to reproduce failures.

These are application inputs with a spread of difficulty, not reductions of one
solver pathology. The nominal/elevated/severe labels describe physical parameters.
The elevated/severe reactive-support inputs fail both tested profiles from both
starts despite verified witnesses; renewable-surplus inputs pass throughout.

```julia
receipt = TOML.parsefile(HardCaseSearch.evidence_file("ieee118-applications.toml"))
trial = only(filter(t -> t["family"] == "reactive_support" &&
    t["level"] == "severe" && t["profile"]["name"] == "ratio_one", receipt["trials"]))
data = HardCaseSearch.TransmissionOPF.application_case(:reactive_support; level=:severe)
run_trial(data, trial["start"], trial["profile"], "NEW_APPLICATION_REPLAY_DIRECTORY";
    start_label=trial["start_label"])
```

`ieee118-application-catalog.tsv` records the nine measured reference operating
points. `ieee118-applications-sweep.tsv` retains every raw combined-policy trial,
including failures. Complete artifacts and sibling `.tar.gz` archives remain in
local ignored `../search-results/ieee118-applications-2026-10-25/` and
`../search-results/ieee118-application-sensitivities-2026-10-25/`.
The [application guide](../APPLICATIONS.md) defines scope, parameters, intended
versus observed effects, paired comparisons and remaining coverage gaps. Original
PGLib attribution and license remain unchanged.

## Operating coverage and fleet records

`ieee118-expansions.toml` contains 18 case specifications, 39 verified reference
points, 18 dispatchable NLP points and 18 representative raw trials from the
coverage/fleet studies. `ieee118-expansions-sweep.tsv` retains all 54 raw outcomes;
`ieee118-expansions-coverage.tsv` records every verified reference's regions and
fractions. Compact per-point coverage is sufficient for comparison; complete
controller margins, requests, points and solver outputs remain in the archives.

Coverage cases rebuild with `application_policy_case(Symbol(spec["policy"]))`.
Fleet cases rebuild with `application_fleet_case(Symbol(spec["family"]);
level=Symbol(spec["level"]),count=spec["count"],placement=Symbol(spec["placement"]))`.
Pass `laws=:dispatchable` for their matched counterfactuals. The original
application receipt's hash identifies the operating-point source.

Each case's `primary_reference` indexes its `references` list. A `solver_point`
reference records an observed sector solve (or verified raw point); a
`physical_transfer` records construction and original feasibility, with no
solver-success claim. They preserve different feasible regimes and do not assert
full-MPCC stationarity. Tests reconstruct inputs and independently check all
stored points, hardware/mixture invariants and the newly reached curve regions.
Historical failure statuses are preserved without requiring future solvers to
repeat them.

```julia
receipt = TOML.parsefile(HardCaseSearch.evidence_file("ieee118-expansions.toml"))
trial = only(filter(t -> t["case_key"] == "policy-injection_service-both" &&
    t["start_label"] == "flat", receipt["trials"]))
data = HardCaseSearch.TransmissionOPF.application_policy_case(:injection_service)
run_trial(data, trial["start"], trial["profile"], "NEW_EXPANSION_REPLAY_DIRECTORY";
    start_label=trial["start_label"])
```

Full local artifacts and sibling archives are under ignored
`../search-results/ieee118-coverage-2026-10-25/` and
`../search-results/ieee118-fleets-2026-10-25/`. The
[extension guide](../EXPANSIONS.md) defines physical scope, policies, geography,
reference construction and measured outcomes. PGLib attribution/license are
retained; these are synthetic study overlays, not new official PGLib releases.

## IEEE 300 application records

`ieee300-applications.toml` preserves the independently checked canonical
MadNLP/PowerModels points, all 32 executed CCOpt starts/returned vectors, four
unavailable starts, seven strict controlled references, nine matched dispatchable
outcomes and four selected-sector physical sensitivity points. Both failed
baselines and unresolved inputs remain explicit. Float64 bit hashes and complete
input snapshot hashes guard the stored points and factory reconstruction.
`ieee300-applications-sweep.tsv` contains every requested trial. See the
[IEEE 300 guide](../IEEE300.md) for exact placements, physical coverage and scope.

The 36-request cohort has 11 successes, 20 solver failures, one solved-status
original-VV accuracy gap and four unavailable starts. Sixteen solver failures
are on inputs with strict numerical feasibility witnesses. The four actual
failures on elevated/severe reactive inputs remain unresolved; their baselines
also fail. Neither a local infeasibility status nor a failed witness search
certifies the full problem infeasible. Future CCOpt releases need not retain
any of these failures; tests re-evaluate the archived numerical evidence.

Raw solves use current/ratio_one, flat/verified-reference primal starts, 500
iterations and 60 seconds. The complete source fingerprint is from commit
`42a641d`; the source tree, environment, full inputs, all failed reference attempts
and solver logs are archived locally. A later catalog metadata change leaves
all reconstructed physical input hashes unchanged. Resume before that change
preserves all 312 raw/baseline/reference/input files byte for byte.

Complete local archives under ignored `examples/opf/pglib/search-results/`:

| Archive | SHA-256 |
| --- | --- |
| `ieee300-applications-2026-10-25.tar.gz` | `1d423d3b080d7a842013145c4a6db61f979cec3a74e7fe6f27194a5a7cbaa951` |
| `ieee300-canonical-validation-2026-10-25.tar.gz` | `0f369a59cb9b0a2c70980eb25b0000250415fff6f814e6d317fe018e8c55e504` |
| `ieee300-limit-sensitivities-2026-10-25.tar.gz` | `914102276fcd95db8e80a6c72eb15f8b974bdc34c42683b222d396a09bbdeeea` |
| `ieee300-exploratory-2026-10-25.tar.gz` | `8ee29436d5054e76e59d455d7a02b48f181868c612f25dbb7d6584470e474749` |

The exploratory archive preserves an interrupted preliminary run during which
a reporting-only edit occurred. It is excluded from the characterized cohort;
the formal run was restarted on frozen committed production code. The canonical
validation archive also retains the exact imported source and its licensing.

Manual utilities in this directory regenerate independent canonical receipts
(`validate-ieee300.jl`), isolate S-circle/cutset-rating responses from strict
references (`study-ieee300-limits.jl`), and build the portable receipt from
completed searches (`curate-ieee300.jl`). Their commands and the admission gates
are documented in the study guide. They do not overwrite raw attempts.

## IEEE 300 policy matrix records

`ieee300-policy-matrix.toml` retains nine independently validated policy/reserve
references, all 36 raw CCOpt starts and returned points, nine matched dispatchable
baseline records, physical coverage, effective solver settings and source/input/
Float64-point hashes. `ieee300-policy-matrix-sweep.tsv` lists every raw trial.
The [study guide](../POLICY_MATRIX.md) defines the hardware, policies, one-sided
Q-upper formula, numerical gates and reproducible commands.

All nine references are selected-sector local NLP points with maximum original
residual 1.73e-11. The reference generator used actual archived operating
voltages; every candidate passed its first operating reference attempt. No desired
regime selected a sector or fixed a voltage. Four plants per cap-gain input are
strictly VW-limited, two absorption and four injection plateaus are reached, and
the early backstop reaches two VW lower plateaus. Every reserve case retains
all original Q lower bounds, including positive source Q minima.

The benchmark receives these references before its raw trials. It rechecks
complete input identity, point hashes and original feasibility, then copies the
receipt into the captured run. Both solver profiles use the same reference point
for each input. All 32 raw failures reach 500 iterations on known-feasible inputs;
four raw trials pass, and all nine dispatchable runs pass. The cap-gain variants
share the same physical dispatchable baseline. No raw solve is polished or
replaced. Tests validate historical numerical evidence without requiring future
CCOpt releases to retain the same failures.

The recorded production source is commit `732d0dd`. Resume preserves all **318
matrix files** byte for byte, and the portable receipt and sweep table regenerate
byte for byte from completed records. Complete local archives are retained under
ignored `examples/opf/pglib/search-results/`:

| Archive | SHA-256 |
| --- | --- |
| `ieee300-policy-references-2026-10-25.tar.gz` | `1f81e43b59614ab20dac264b54494382cd1288d0d86646f4d936d0dcd3b1780b` |
| `ieee300-policy-matrix-2026-10-25.tar.gz` | `4646aee659c03d66e0684e9fbd58d6c8e358bc0592bbb713a543f81b101472a6` |

The archives include complete source/environment copies, the source application
receipt, every reference and baseline attempt, raw starts/results and solver
logs. The new studies retain the unresolved status of the two original signed-Q
stress inputs; the one-sided reserve sequence is a separate feasible family.
Local sector references establish numerical feasibility, not global optimality
or full-MPCC stationarity. Publishing the complete archives remains follow-up work.

## IEEE 118/300 operating-condition records

`operating-conditions.toml` retains twelve cases selected from the 46-input matrix:
six per network, five easy, two mixed and five difficult under the recorded budget.
It includes every selected feasible reference, all 48 raw starts/returned points,
twelve matched dispatchable records and deduplicated effective option dictionaries
identified by SHA-256. The complete 46-case numerical census and all 184 requested
outcomes remain in the readable census/sweep TSVs beside this guide. The single
unresolved reference and its unavailable starts are retained, not called infeasible.

The twelve selected points cover all 43 features observed in the full study.
Early/middle/late strict VW ramps, mixed controller regions, VV saturation plus
native limits, export-boundary activity and S-circle saturation are represented.
Strict VW plus S activity at different plants remains a recorded coverage gap.
See the [operating-condition guide](../OPERATING_CONDITIONS.md) for physical axes,
selection rules, the result table and qualification limits.

`operating-conditions-2026-10-26.tar.gz` preserves 1,647 original experiment files
unchanged, plus the read-only curation/preservation scripts and a per-file SHA-256
manifest. Its 6,936,206 bytes have SHA-256
`b893495635e84c87a958e05c018ebbc349a7cd286e080a30804aeff21216f687`.
The updated complete `pr-evidence-2026-10-26.tar` preservation bundle contains
all fifteen raw archives and eight lossless receipts. Both bundles remain local;
checksums and the non-overwriting packaging utility are committed. The older
25 October cleanup bundle remains preserved separately.
