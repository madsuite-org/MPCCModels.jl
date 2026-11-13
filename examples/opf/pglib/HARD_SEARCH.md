# CCOpt hard-case search

The regression suite checks model correctness and achieved regimes. This harness
has a different purpose: retain and reproduce numerical difficulty, including
failed homotopy solves on problems with independently verified feasible points.
No raw solve is automatically polished or replaced by a witness.

## Initial family and matrix

`capability_case(factor)` uses the pinned IEEE 118 mixed VV/VW model and changes
only inverter `ibr3`'s apparent-power rating to `factor * nominal_smax`.
Availability, Q bounds, control curves, costs, generators and the network remain
fixed. Nominal S is 1.0 system pu (100 MVA) at bus 95. A factor of 0.82 therefore
means S=82 MVA while availability stays 80 MW. All powers and residuals use the
system base; physical apparent-power margins are distinct from squared-S
constraint residuals.

The default matrix has **160 raw trials**:

- Capability factors: `0.78, 0.80, 0.81, 0.82, 0.83, 0.84, 0.86, 1.0`.
- Starts: `flat`, `neighbor`, `perturbed_neighbor`, `witness`.
- Five explicit solver profiles below, with 500 iterations and 60 seconds of
  solver wall budget per run. These are MadNLP limits, not an external process
  timeout covering compilation or a stalled native-library call.

| Profile | sigma floor | sigma/mu ratio | NLP tolerance | bound push/factor |
| --- | ---: | ---: | ---: | ---: |
| defaults | 1e-8 | 1 | 1e-8 | 1e-2 |
| current | 1e-14 | 0.01 | 1e-9 | 1e-6 |
| looser_inner | 1e-14 | 0.01 | 1e-8 | 1e-6 |
| ratio_one | 1e-14 | 1 | 1e-9 | 1e-6 |
| higher_floor | 1e-8 | 0.01 | 1e-9 | 1e-6 |

All profiles disable bound relaxation. `defaults` pins the observed
CCOpt 0.1.0/MadNLP 0.10.2 defaults with explicit budgets; it does not dynamically
follow defaults in future releases. The last three vary one parameter from
`current`, so they help distinguish inner-tolerance, update-ratio and floor
sensitivity. A configuration that asks for much tighter precision than its
relaxation floor readily provides is a configuration stress test; its failure
alone does not establish intrinsic difficulty of the physical model.

The neighboring point comes from a separate nominal-factor solve. Perturbations
use a recorded MersenneTwister seed: free voltage magnitudes ±0.005 pu, angles
±0.01 rad, and inverter P/Q ±0.02 S. Box bounds are respected, then hinges are
recomputed from the perturbed voltages. The actual vectors are saved, so replay
does not depend on regenerating a random sequence. A neighboring point can be
infeasible for a reduced S limit; its initial residuals are reported.

## Run, resume and replay

Install the optional PGLib environment against this checkout as in its README.
From the repository root:

```sh
# Full default matrix; output directories are never silently overwritten.
julia --project=examples/opf/pglib examples/opf/pglib/search-hard-cases.jl \
  --out=examples/opf/pglib/search-results/ieee118-capability-study

# Smaller focused reproduction.
julia --project=examples/opf/pglib examples/opf/pglib/search-hard-cases.jl \
  --out=examples/opf/pglib/search-results/cap082 \
  --caps=0.82 --starts=flat,witness --profiles=defaults,current

# Resume the SAME plan, source and environment. Completed failures are skipped
# as completed results; unfinished attempts remain and get a new attempt folder.
julia --project=examples/opf/pglib examples/opf/pglib/search-hard-cases.jl \
  --out=examples/opf/pglib/search-results/cap082 \
  --caps=0.82 --starts=flat,witness --profiles=defaults,current --resume

# Replay one stored request under the current code/stack, into a fresh directory.
julia --project=examples/opf/pglib examples/opf/pglib/search-hard-cases.jl \
  --replay=PATH_TO_TRIAL_DIRECTORY --out=NEW_REPLAY_DIRECTORY

# Rebuild tables directly from saved records.
julia --project=examples/opf/pglib examples/opf/pglib/search-hard-cases.jl \
  --summarize=PATH_TO_SEARCH_DIRECTORY
```

Other controls are `--seed`, `--repetitions`, `--max-iter`, `--max-wall` and
`--no-warmup`. Repetitions change the perturbation seed but preserve matched
starts across profiles. Use a new output directory when changing the matrix,
source, Julia or dependency environment. Run one writer per output directory.
Do not modify production source files during a search.

The driver saves a setup solve and a discarded warmup for each profile before
measured raw trials. Warmup failures are retained in their own folders and do
not abort the matrix. Times separate model construction, solver initialization,
solve-call elapsed time and the outer model/solve span. Start preparation,
witness verification, persistence and post-solve diagnostics are outside that
outer span. Cold setup/warmup times are not raw benchmark timings. Previously unvisited
restoration/failure paths can still compile on first use. These local
measurements are not performance claims for other hardware or environments.

## Witnesses and interpretation

A separate BranchNLP solve selects its sector from the nominal case's actual
hinge values and starts from that point. It never uses desired coverage labels
to select a sector, and never modifies a raw homotopy record. Every candidate
witness is checked against the *original target-capability model*, including
complex-current balances, boxes, complementarity and direct VV/VW laws. The
witness tolerance is `1e-7`, stricter than the raw physical gate `1e-5`.

Numerical feasibility is checked independently of solver termination: even a
non-successful solve can return a valid feasibility witness, with its status
retained. A failed witness search establishes no infeasibility. A verified raw
point may also be registered as a witness when the separate sector attempt did
not provide one. Unavailable neighboring/witness starts are recorded as
`unavailable_start`; the driver never silently substitutes a flat start.

Witness starts are diagnostic information about initialization. They must not
replace flat/neighbor results when evaluating robustness. A selected-sector
solution is neither a global optimum certificate nor a full MPCC stationarity
certificate. Better feasible objectives elsewhere do not by themselves disprove
local optimality of another feasible point.

Raw classifications are:

| Classification | Meaning |
| --- | --- |
| success | Successful solver status and original physical checks pass |
| solver_failure | Non-success termination, with a returned point retained |
| physical_violation | Successful status, but an original physical check fails |
| exception | Construction/solver exception, with stack trace and current iterate when available |
| diagnostic_error | A returned point could not be independently checked |
| no_solution | No returned/current point was available |
| unavailable_start | The requested start had no verified source point |

Summary findings add `known_feasible_failure` when the same case has a verified
witness, `accuracy_gap` for physical violations, and `unresolved_feasibility`
when a failed solve has no witness. Interface exceptions remain separate from
numerical failures. Physical violation is relative to the declared tolerance;
a small accuracy gap at default settings differs from a large residual after
an iteration limit. Always read the residual magnitudes and settings.

## Saved artifacts

- `plan.toml`, `environment.toml`: exact grid, budgets, tolerances, Julia/package
  versions, CPU/thread information, source hashes and Git revision.
- `environment/Project.toml`, `Manifest.toml`: the active dependency environment.
  Local develop paths may need adjustment when moved to another machine.
- `source/`: copies of model, harness and package production sources.
- `source_data/`: upstream data license and attribution notes (case snapshots
  contain the normalized study data).
- `cases/*/input.toml`: complete per-unit network and controller snapshots,
  including original PGLib provenance. Replay does not depend on reparsing a
  later upstream branch. The existing data attribution/license still applies.
- `setup/`, `warmup/`, `witnesses/`, `trials/`: distinct solver attempts, each
  containing its request, exact start, status, metrics, stdout/stderr log and
  returned/current point when available. Effective solver options and counters
  are retained, including internally selected defaults and linear solver.
- `cases/*/witness.toml`: a reference to the verified point, bound to the same
  input checksum and solution checksum. Reuse rechecks the original equations.
- `summary.toml`, `summary.tsv`: all raw attempts, including failed/unfinished
  attempts. Superseded attempts remain visible. `cases.tsv` counts the latest
  attempt for each requested trial, ordering cases by known-feasible failures
  then accuracy gaps as a triage aid, not a universal difficulty ranking.

Requests and starts are checkpointed before solver construction. Results are
written atomically. A running marker is summarized as `unfinished`; it may represent either an
active run or an interrupted process. Exceptions are captured without stopping subsequent runs;
a process termination may leave only a running marker, which resume preserves
before creating another attempt. Checksums detect changed case/start/solution
files. Replay saves its own environment and the original environment, so a
changed software stack is visible rather than claimed to reproduce identically.

Full local output is ignored by Git under `search-results/`. Curated inputs,
feasible witnesses and representative raw failures can be committed separately.
CI tests the recorder, integrity checks, replay and resume with short budgets;
it does not require an algorithm to keep failing on a particular case forever.

## Committed reproduction

The [capability-0.82 receipt](hard-cases/README.md) preserves four representative
raw trials plus an exact-sector witness as a compact TOML artifact. It includes
actual starts/points, Float64 bit hashes, effective options, source/environment
identifiers and original residuals. The tests independently re-evaluate these
points; they do not pin the behavior of future solver releases to a failure.
See its README for replaying a recorded start/profile with `run_trial`.

## First complete sweep: 2026-10-24

The first 160-trial sweep used the matrix above, Julia 1.12.6, CCOpt 0.1.0 and
MadNLP 0.10.2. Its production-source snapshot is identified in each saved
request and in the curated receipt (Git revision `eb3edf3`). Later changes
clarify unfinished-record labels and option-type metadata; they do not change
the models, starts, numerical profiles or archived outcomes.

| Capability factor | Non-success terminations | Solved-status accuracy gaps | Pass status and physical gate | Verified witness |
| --- | ---: | ---: | ---: | --- |
| 0.78 | 5 | 5 | 10 | yes |
| 0.80 | 4 | 6 | 10 | yes |
| 0.81 | 3 | 7 | 10 | yes |
| 0.82 | 6 | 4 | 10 | yes |
| 0.83 | 4 | 6 | 10 | yes |
| 0.84 | 0 | 8 | 12 | yes |
| 0.86 | 0 | 8 | 12 | yes |
| 1.00 | 0 | 8 | 12 | yes |
| Total | **22** | **52** | **86** | **8/8** |

The 22 non-success terminations comprise 15 iteration-limit stops and seven
`INFEASIBLE_PROBLEM_DETECTED` statuses, despite a separately verified feasible
witness for each input. Those local solver statuses are not mathematical
infeasibility certificates. There were no exceptions, missing starts or
unresolved-feasibility inputs in this matrix.

All five `current` failures occur from flat starts at factors 0.78–0.83.
Changing only the relaxation ratio from 0.01 to 1 recovers these five matched
trials: `ratio_one` passes all 32 of its trials. `current` and `looser_inner`
each pass 27/32. `higher_floor` has 12 non-success terminations and 20 accuracy
gaps. `defaults` terminates successfully in all 32 trials but misses the
independent `1e-5` physical gate; its maximum control-law violations range from
about `1.67e-5` to `2.09e-5` system pu. These small gaps differ materially from
the large residuals in stalled runs and must not be described as 32 catastrophic
solver failures. The results establish start/parameter sensitivity, not failure
of CCOpt under every reasonable setting.

For the committed factor-0.82 case, the current flat-start run stops at 500
iterations with direct VV/VW errors `1.73e-2`/`1.14e-2` system pu. Its exact-sector
witness has maximum original residual about `1.41e-13` and zero complementarity
minimum residual. The neighboring- and witness-start runs with current settings
return direct errors below `1.65e-9`. All raw points are retained independently.

A complete resume reused all 160 results; SHA-256 comparisons confirmed all
800 raw-attempt files were byte-identical. Full local artifacts are in
`search-results/ieee118-capability-2026-10-24`. The compact committed receipt
retains the key reproduction if local search output is later removed.

Validation: **105 harness/curated-record assertions** pass on Julia 1.10.12 and
1.12.6. The existing **578 PGLib model assertions** pass on Julia 1.12.6, and
Documenter builds with external link checks disabled locally. The archived
0.82 flat/current request was replayed under the finalized recorder and again
stopped at 500 iterations with the same returned-point residuals. Full resume
left all 800 raw-attempt files unchanged. CI runs the short recorder/witness
tests; the 160-trial search remains an explicit research run.

The complete [160-row matrix](hard-cases/ieee118-capability-sweep.tsv) is also
committed. A compressed local archive retains every request, raw point, solver
log, witness, environment and captured source file at
`search-results/ieee118-capability-2026-10-24.tar.gz`.

## Ratio-one simultaneous transitions and generator-Q limit

`transition_case(; knee=1.02, offset=0.0, qmax=0.35)` puts the three original
IEEE 118 inverters at bus 95. Ratings, availability, hardware Q boxes and costs
are unchanged. Each device has VV knots `knee + [-.06,-.02,0,.02]` with Q/S
`[.4,0,0,-.4]`, and VW knots `knee + offset + [0,.015]` with P/S `[.8,.2]`.
Thus zero offset coincides with the VV deadband/absorption knee, the start of
VW curtailment and availability. VW remains an upper bound. All knots stay in
the original voltage band. Separate hinges deliberately preserve six biactive
pairs at the common knee; shared-knot encoding is a future matched comparison.

Only original generator 45 at bus 100 has a network limit changed: its Q upper
bound decreases from 1.55 pu to 0.20/0.35/0.50 pu (20/35/50 MVAr on the
100-MVA base). Its lower bound stays −0.5 pu. No voltage is fixed to a knee and
no generator output is fixed to its bound. Tightness must emerge from a solve.

```sh
julia --project=examples/opf/pglib examples/opf/pglib/search-hard-cases.jl \
  --transitions --out=examples/opf/pglib/search-results/ieee118-transitions-2026-10-24 \
  --offsets=-.0001,0,.0001 --qmaxes=.2,.35,.5 \
  --seeds=20261024,20261025,20261026 --max-iter=500 --max-wall=60
# Repeat the same command with --resume to recheck the plan and retain completed attempts.
julia --project=examples/opf/pglib examples/opf/pglib/search-hard-cases.jl \
  --transitions --summarize=examples/opf/pglib/search-results/ieee118-transitions-2026-10-24
```

The 54 raw trials use `ratio_one` throughout: nine inputs, with flat, verified
relaxed-Q neighboring-case, verified same-case witness, and three seeded
perturbations of the neighboring point. The three deterministic starts run once
per input. All actual vectors are saved. Model construction and independent
checks retain the existing recording/replay protocol and resource limits.
Separately retained setup solves warm the solver before the raw matrix; reported
outer times still include per-trial construction/checking.

For each offset, a separate relaxed-Q homotopy point selects a sector by its
hinge signs, even if homotopy failed. A separate exact-sector solve must pass all
original feasibility checks at `1e-7` before becoming a neighboring start. Each
tightened-Q input receives a separately retained sector witness. These witness
solves neither modify a raw result nor establish MPCC optimality/stationarity.
An unavailable witness remains explicitly unavailable, and a failed witness
search never establishes infeasibility. Raw verified points can establish
numerical feasibility independently of termination status.

`summary.toml` retains every attempt and identifies superseded attempts without
deleting them. It reports raw and witness activity separately: distances to the
VV knee and VW onset, number of controllers simultaneously within `1e-6` pu of
both, generator 45 Q and upper margin, and tightness at `1e-6` system-base pu.
Activity alone is insufficient: the original feasibility flag and all six
residual fields remain separate. At nonzero offsets the VV and VW knees are
intentionally distinct; do not label them simultaneously active because they
are nearby. `summary.tsv` is a compact status census. Replay individual raw
requests using the existing `--replay=TRIAL --out=NEW_DIR` command.

These cases intentionally combine several degeneracies: common voltage and law
profiles across devices, repeated hinge knots, and equality of the upper VW
plateau with availability. The matched relaxed-Q setup tests whether Q tightness
is necessary for a failure. Additional ablations should split device count,
shared versus separate knots, and availability/VW coincidence before attributing
slow convergence to one mechanism. A failed witness-start homotopy is useful
robustness evidence; it still does not diagnose the algorithmic cause.

### Completed 54-trial result (2026-10-24)

All **54 raw `ratio_one` trials reach 500 iterations** and fail the original
`1e-5` physical gate. Every input has a separate exact-sector witness with maximum
original residual below **2.5e-11**; all nine witness-start homotopies also stall.
No raw result was replaced by a witness. There are no exceptions, unavailable
starts, wall-time exits or unresolved-feasibility cases in this matrix.

| VW offset (pu) | Witness voltage (pu) | Achieved VV position | Known-feasible failures |
| --- | --- | --- | --- |
| −0.0001 | 1.0199 | Deadband, just below absorption knee | 18 / 18 |
| 0 | 1.0200 | Deadband/absorption knee, simultaneous with VW | 18 / 18 |
| +0.0001 | 1.0201 | Absorption ramp, fraction 0.005 | 18 / 18 |

All witnesses lie at VW onset, with availability and VW tight and capability
slack. At zero offset, all three controllers meet both knee-distance checks.
All nine generator-Q margins are positive and below `4.38e-8` pu, well within
the `1e-6` activity threshold. Raw points have VV errors from `4.93e-4` to
`2.06e-2` system-base pu; small AC balance errors do not make those points feasible.
The ±`1e-4` offsets are 100 times the knee classifier tolerance: the separated
neighbors are not counted as simultaneous knees.

Three relaxed-Q setup homotopies also hit 500 iterations; their separate sector
solves succeed. Thus Q tightness is present in these combined cases, but is not
necessary for their observed difficulty. The nearby offsets also stall, so the
failure is not confined to exact VV/VW knot coincidence. Shared profiles and
same-bus redundancy remain present in every input and require matched ablations.

For the central zero-offset case, separate sector solves at Q upper bounds
0.349, 0.350 and 0.351 pu give local objectives 91215.165706737,
91215.160139752 and 91215.154608201, respectively. Each Q bound is tight and
all original residuals are below `1e-7`. This supports local influence of the
limit on dispatch/cost; these selected-sector values are not global sensitivity
certificates or full MPCC stationarity checks.

The [portable receipt and census](hard-cases/README.md#ratio-one-transitionq-limit-receipt)
retain all nine main witnesses, both additional Q-sensitivity witnesses and all
six central-case raw trials. The TSV includes all 54 statuses, original residuals,
raw activity and witness activity. Full snapshots, actual vectors, logs and
source/environment records remain under `search-results/`. A replay of the
central flat-start request again hits 500 iterations with identical residuals.

Resume rechecks the finalized plan/source/environment and preserves all **270**
raw-attempt files byte for byte. The local full archive is
`search-results/ieee118-transitions-2026-10-24.tar.gz`, SHA-256
`56d834e6c5e6a12737aa7665a11f77fa662b2800d8eff7f7fcd5f334b35b7d41`.
The recorder and archived points pass **419 assertions** on Julia 1.10.12 and
1.12.6. The long search remains manual; CI rechecks model/recorder behavior and
stored numerical evidence without asserting continued solver failure.

## Controlled reduction matrix

`reduction_case(; encoding=:separate, controlled=3, plateau=:equal)` starts from
`transition_case()` (zero offset, generator-45 Q upper limit 0.35 pu).

- `encoding=:separate/:shared` changes only the hinge representation. Shared
  encoding allocates one pair per **exact** `(bus,knot)` key and reuses it across
  devices and laws. It keeps every law row and physical constraint. The central
  three-device case shrinks from 18 to 5 pairs. At one controlled device it
  shrinks from 6 to 5 because VV and VW already share a knot within that device.
- `controlled=1/2/3` retains both laws on the first original device IDs. The
  remaining devices stay at bus 95 with unchanged hardware, availability and
  costs, but dispatchable P/Q. Changing this count changes the physical feasible
  set; total installed hardware and the conventional network remain fixed.
- `plateau=:equal/:crossing` keeps availability at .8S and VW knots unchanged.
  The upper VW ordinate is .8S or .9S, respectively, with the lower ordinate
  fixed at .2S. In the crossing variant availability intersects the VW ramp at
  fraction 1/7, voltage `1.022142857...`; it no longer duplicates the upper
  plateau. The voltage knees remain coincident with the VV absorption knee.

`transmission_start(target, source, x)` checks ordered physical record IDs and
attachment buses, copies V/angle/generator P/Q/inverter P/Q, then constructs exact
hinges for the target representation. It does not map relaxed hinge iterates or
multipliers. Flat and witness physical starts match across all 12 variants;
seeded starts come from one perturbed physical reference and match as well.

Every case receives a **constructed, independently verified numerical witness**
from the committed central physical point. These transfers preserve its binding
Q limit and knee voltage, and must pass all original checks at `1e-7`. They are
stored as explicit witness records with source/input/point checksums, rather than
being labelled new solver runs or optima of the reduced problems. In crossing
variants the VW knee is geometrically coincident but its cap is slack at this
witness; activity reporting distinguishes the knot from a binding cap.

```sh
julia --project=examples/opf/pglib examples/opf/pglib/search-reductions.jl \
  --out=examples/opf/pglib/search-results/ieee118-reductions-2026-10-25
# The default runs 24 flat/witness trials plus a separate 2000-iteration reference.
```

Each raw request enables a read-only MadNLP/CCOpt intermediate callback. It
flushes `trace.tsv` every ten iterations and records a final sample: iteration,
phase, elapsed time, barrier mu, relaxation sigma range, reported primal/dual/
complementarity residuals, objective and all six independent original residuals.
The observer returns true and never changes iterates or solver settings; its
model evaluations add to evaluation counters and runtime. A separate traced
warmup pays compilation costs before the matrix. Trace errors are retained,
trace checksums are checked on read, and replay restores the sampling interval.
Restoration/robust phases are labelled separately when callbacks are invoked.

The reference uses the original separate/three-device/equal-plateau input and
flat start, with 2000 iterations and 180 seconds instead of 500 and 60. It is
stored under `references/`, outside the 24-trial matrix. These finite budgets
measure observed progress; an iteration limit does not establish permanent
algorithmic stagnation. Matched perturbation batches use explicit seeds and
separate output plans. Resume never overwrites complete raw attempts.

To add only seeded paired starts, without repeating flat/witness runs or the
larger-budget reference:

```sh
julia --project=examples/opf/pglib examples/opf/pglib/search-reductions.jl \
  --out=examples/opf/pglib/search-results/ieee118-reduction-seeds-2026-10-25 \
  --starts=perturbed_witness --seeds=20261025,20261026,20261027 --no-reference
```

A seeded physical point is generated once from the central three-policy input,
then transferred into each variant with exact target hinges. It may violate
network balance or policies initially; it is an explicitly perturbed start, not
an additional feasible witness. Availability, hardware and physical-variable
order match, so each seed has identical V/angle/generator/inverter P/Q across
both encodings and all policy-count/plateau variants.

### Completed reduction results (2026-10-25)

The complete matrix has **60 raw trials**: flat, the common verified witness,
and three matched perturbations for each of 12 variants. Results are **41
physical passes, 10 solved-status accuracy gaps and 9 iteration-limit exits**.
Every input has a separately stored constructed feasible witness. There are no
exceptions, trace errors, missing starts or unresolved-feasibility cases.

Each entry below gives **physical passes / accuracy gaps / iteration limits**
among the five starts. Physical passes require both successful status and all
original residuals at `1e-5`.

| Controlled devices | VW plateau | Separate hinges | Shared hinges |
| --- | --- | --- | --- |
| 1 | Equal to availability | 0 / 5 / 0 | 5 / 0 / 0 |
| 1 | Crossover in ramp | 5 / 0 / 0 | 4 / 0 / 1 |
| 2 | Equal to availability | 0 / 5 / 0 | 5 / 0 / 0 |
| 2 | Crossover in ramp | 5 / 0 / 0 | 4 / 0 / 1 |
| 3 | Equal to availability | 0 / 0 / 5 | 4 / 0 / 1 |
| 3 | Crossover in ramp | 5 / 0 / 0 | 4 / 0 / 1 |

The separate equal-plateau cases with one/two controllers terminate successfully
but leave VV errors around `1.08e-4`/`1.62e-4` pu. The trace records small product-
based solver residuals alongside much larger minimum-hinge and direct-curve
errors. For example, the one-controller flat case stops with mu/sigma near
`9.09e-11`, reported primal residual `9.08e-11`, minimum-hinge violation
`6.74e-6` and VV error `1.08e-4`. Those measures must not be interchanged.

Sharing recovers these accuracy-gap cases and four starts of the original
three-controller case, but is **not a universal improvement**. The smallest
recorded iteration-limit example has **one controller, five shared pairs, 360
variables and 804 ordinary constraints**, with availability crossing the VW ramp.
Its flat start reaches 500 iterations, with VV error `9.06e-3` and VW violation
`4.11e-2` pu. The physically identical separate-hinge case passes from the same
physical start in 385 iterations; the shared case passes from its witness and
all three perturbations. The shared two-controller crossing case instead fails
from the witness; shared three-controller cases fail from flat. These are
encoding/start interactions, not evidence of monotonically increasing difficulty
with controller count or redundant pairs.

The original separate/three-controller/equal-plateau reference reaches
`SOLVE_SUCCEEDED` at **1,145 iterations** under the 2,000-iteration budget. It
still fails the physical gate: VV error `2.29e-4` pu and minimum-hinge violation
`9.53e-6`. Thus the original 500-iteration exits are budget-sensitive, while
termination alone still does not establish the direct laws. The reference is
retained separately and excluded from the 60-trial census.

The [curated reduction receipt](hard-cases/README.md#controlled-reduction-records)
contains all 12 constructed witnesses, ten representative raw trials and the
larger-budget reference, with actual starts/points, profiles, checksums and
original diagnostics. The census retains all 60 outcomes; the trace TSV retains
five representative convergence series. Physical starts match exactly across
encodings and variants for each start label/seed. No failed raw result is
polished or replaced by these witnesses.

Validation: **585 reduction/curated-record assertions** pass on Julia 1.10.12
and 1.12.6, alongside the existing 419 hard-search, 578 model and 235 solved-case
assertions on Julia 1.12.6. Resume preserves all **366 raw/reference files** byte
for byte, and the five physical start-label/seed combinations match exactly
across every variant. Replaying the smallest shared one-controller flat failure
reproduces the 500-iteration status, identical returned vector and identical
original residuals. The observer records no errors in either search batch.

Complete local archives (excluded from Git):

- `search-results/ieee118-reductions-2026-10-25.tar.gz`, SHA-256
  `d1e68a14d76c1c02a1afae24e26a8d6c46a0169d12e57ea9d4f65e7b448f7387`.
- `search-results/ieee118-reduction-seeds-2026-10-25.tar.gz`, SHA-256
  `0ba001433684b3cf24ac2d175ddd608558ad1226f1f166b206a4dfe1237c4e0b`.
