# PGLib transmission OPF roadmap

## Focused operating-condition matrix (2026-10-26)

Retain the existing single-state balanced AC OPF, fixed VV equality/VW cap and
independent hardware/network limits. No SCOPF, temporal coupling, new control
laws, free equipment or curve-design variables are introduced.

- [x] Add IEEE 118/300 one-sided Q-upper reserve and fixed-policy export sequences.
- [x] Add selected penetration, fixed-total placement and population controls.
- [x] Independently validate references and measure combined VV/VW/network activity.
- [x] Benchmark identical flat/reference starts under current/ratio_one settings;
      preserve unresolved references, raw failures and all inputs/options.
- [x] Curate a small coverage/diversity collection with measured easy, mixed and
      difficult outcomes; retain the full candidate census and original archives.
- [x] Add physics/invariant/derivative/evidence tests, portable documentation and
      CI coverage at the existing fast versus exhaustive tiers.

Recorded outcome: **46 inputs, 45 strict references, 184 requests**. The raw
matrix has 84 accepted outcomes, 97 native failures, one solved-status physical
accuracy gap and two unavailable witness starts. The full case spectrum is
14 easy / 16 mixed / 15 difficult under budget / one unresolved reference.
The unresolved input is IEEE 300 `reserve_q80`; it is not certified infeasible.

The deterministic twelve-case collection has six per network and spans five
easy, two mixed and five difficult cases. It covers all 43 physical features
observed across the full matrix, including early/middle/late strict VW ramps,
VV saturation/native-limit combinations, export-cutset activity and S-circle
saturation. Strict VW plus S activity at different plants and active angle bounds
remain gaps; no operating laws or voltages were changed to manufacture them.

Validation: 2,050 core assertions; 6,855 operating-model assertions on Julia 1.10
and 1.12; 172 fast checks on both; 1,083 operating-evidence/selection/resume checks;
38 archive-integrity checks; 2,648 legacy expansion and 2,254 policy checks.
The compact receipt, full census and sweep regenerate byte for byte. All 1,647
original experiment files remain unchanged in the verified raw archive. The
updated 26.7 MB local preservation bundle contains fifteen raw archives and
eight lossless receipts. Documenter builds offline and local links pass across
19 pages. Remote GitHub CI remains pending; no PR or release is opened here.

See the [operating-condition guide](OPERATING_CONDITIONS.md),
[complete census](hard-cases/operating-conditions-census.tsv) and
[raw sweep](hard-cases/operating-conditions-sweep.tsv) for physical parameters,
measured activity, native statuses and qualification boundaries.

## PR readiness and preservation (2026-10-25)

- [x] Correct VV plateau labels using terminal Q polarity; zero-Q, one-sided,
  reversed-polarity and feasible-zero-point regressions cover the report.
- [x] Label validated prepared points neutrally and preserve solver/physical/
  unknown origins separately in records, trial provenance and summaries.
- [x] Publish repository guides inside Documenter with local relative links;
  use a package-relative include and remove the personal-branch guide URL.
- [x] Replace 8.98 MB of expanded receipts with 2.65 MB of lossless gzip evidence;
  preserve original receipt hashes, every failure and every feasible witness.
  Keep a derived 14-point fixture for PR physics checks and check its derivation
  in exhaustive CI. Census and trace tables remain readable.
- [x] Index all 14 full raw archives by size/SHA-256 and provide a verified,
  non-uploading distribution-bundle command. Local raw artifacts remain intact.
- [x] Tier CI: package/model/compact-witness/reporting checks on PRs;
  complete solver/archive suites manual and weekly; research sweeps explicit.
- [ ] Publish the verified raw evidence bundle as a versioned release artifact
  when preparing the contribution. No PR or release is opened by this cleanup.
- [ ] Run the manual OPF integration workflow on GitHub before requesting review;
  local timing is evidence about this machine, not a cold Linux CI measurement.

See [test tiers](TESTING.md) and [evidence access](hard-cases/README.md).

Validation for this cleanup: the core package passes 2,050 assertions; the fast
transmission gate checks 14 points and passes 140 assertions on Julia 1.12.
The fast tier also passes on Julia 1.10, with final reporting regressions checked
separately. All eleven exhaustive PGLib scripts and the 151-assertion solved
37-case gate pass locally. Integrity tests verify all seven expanded receipt
hashes and byte-for-byte compact-fixture regeneration. The 19.2 MB preservation
bundle round-trips every receipt and all fourteen raw archives, and regenerates
byte for byte. Documenter builds offline with external link checks disabled, and rendered
local files/fragments pass in flat and CI-style pretty-URL layouts. Workflow YAML
and tier wiring are checked locally; remote GitHub execution remains pending.
The tracked tree is about 4.2 MB versus 10.3 MB before cleanup; Git history is
retained. Cached local tier timings are recorded in the testing guide.

## Aim and acceptance rules

Keep the 37 small synthetic cases as precise unit/regime regressions. Add a
separate, optional transmission benchmark family using PGLib-OPF v23.07, pinned
to commit `dc6be4b2f85ca0e776952ec22cbd4c22396ea5a3`. Preserve original files,
licenses and attribution; express modifications in named, reproducible overlays.
No power-system or solver dependency is added to the MPCCModels runtime.

A correctness/regime regression is accepted after a successful solve, independent
physical feasibility checks, and achieved coverage checks. Hard-case search has a
separate retention rule: preserve all requested runs, including solver failures,
exceptions and interrupted attempts. A verified numerical witness establishes
feasibility independently of the failing solver; an unresolved witness search
does not establish infeasibility. A feasible constructed witness
is useful for debugging but does not establish an optimum or a solved regime.
Report local solutions and selected-sector refinement honestly; do not claim
global optimality or full MPCC stationarity from feasibility alone.

## Current application-driven roadmap

The deliverable is a set of parameterized OPF families motivated by operating
applications, containing ordinary and deliberately stressed instances. CCOpt
difficulty is measured within these families. Explaining or minimizing a solver
failure is optional supporting work, not a gate for adding cases or larger
networks. Existing search traces, witnesses and reduction experiments remain
useful infrastructure and an explicitly labelled formulation/degeneracy family.

1. **Specify applications.** Define physical interpretation, plant locations and
   ratings, synthetic controller policies, operating parameters and intended
   interactions. The first IEEE 118 families cover high renewable output/light
   demand, limited reactive support, and constrained renewable export. These are
   balanced positive-sequence transmission/aggregate-plant study proxies, not
   calibrated distribution feeders or mandatory grid-code parameter sets.
2. **Build tunable graded instances.** Supply nominal/elevated/severe operating
   points with independent parameter overrides and matched dispatchable/VV/VW/both
   variants on identical network/hardware/availability. Physical severity labels
   do not predict solver difficulty. Use heterogeneous multi-controller plants;
   retain compatible subsets of VV/VW regimes, bounds, ramps and knees.
3. **Validate and characterize.** Require correct equations/derivatives,
   provenance and independent original physical checks. Claim feasibility only
   with a verified numerical witness. Record achieved curve regions, fractions,
   curtailment and network/device margins separately from intended mechanisms.
   CCOpt success or a full optimality certificate is not required to admit a
   feasible challenge case. Retain unresolved cases without calling them infeasible.
4. **Select challenges within applications.** Sweep load, renewable output,
   reactive headroom, export capacity, placement and population over documented
   ranges. Preserve easy-through-hard instances rather than only failures. Use
   fixed solver/start budgets, multiple starts and original-curve checks to
   distinguish passes, accuracy gaps, iteration/runtime limits and exceptions.
5. **Expand coverage and scale.** Add missing plateaus, ramp strata, knees and
   multi-plant interactions based on achieved coverage. Extend network size and
   plant population independently, including RTS 24/IEEE 300 once import and
   validation are ready. This work does not depend on diagnosing existing failures.

### First implementation milestone

- [x] Add three application cards and parameterized IEEE 118 constructors, each
      with three physical operating levels and heterogeneous plants.
- [x] Add matched policy variants, input/derivative tests and application metadata.
- [x] Run the first nine both-law inputs with multiple starts/settings, matched
      dispatchable baselines, separate witnesses and complete failure retention.
- [x] Report achieved activity/curve coverage, measured difficulty and gaps;
      curate physically verified records and keep unsuccessful searches intact.
- [ ] Extend application-specific plateau/ramp coverage and population/placement
      variations, then larger networks, using the same building blocks.

The original import, canonical validation and 22-case solved registry are retained.
Their completed development and the historical search/reduction results below
remain evidence; current priorities are the application families above.

## Matrix design

| Axis | Levels and acceptance evidence |
| --- | --- |
| Network | 14/118 first; original and congested `api`; later 24/300 |
| Laws | Dispatchable P/Q, VV, VW, VV+VW with matched hardware/costs |
| Placement | Dispersed, clustered, same-bus heterogeneous profiles |
| Population | Few devices, increasing count, increasing penetration |
| Operating point | Nominal, light load/high availability, stressed load |
| VV | Low plateau, injection ramp, deadband, absorption ramp, high plateau |
| VW | Upper plateau, ramp, lower plateau; availability tighter/equal/looser |
| Position | Interior fractions near 0.2/0.5/0.8, knees, left/right neighbors |
| Limits | Availability, VW, S circle, Q box, bus V, generator P/Q, each branch end, angle difference |

Use a compatible subset, not a Cartesian product. A controller has one voltage,
so VV and VW regions cannot be assigned independently when profiles overlap.
Identical profiles at the same bus imply identical curve regions. Different
availability or costs can change limiting constraints without changing region.

## Making the cases meaningful

- Check every requested region intersects the bus voltage interval before solving.
  The original synthetic VW threshold 1.07 is unreachable in IEEE 14's 1.06
  upper voltage bound. Use documented synthetic transmission profiles inside
  the existing band; do not silently relax the network's bounds.
- Choose ramp slopes and device ratings together. Ensure capability and Q boxes
  can accommodate intended VV values, or deliberately designate their conflict.
  Preserve VW as an upper bound: voltage on its ramp does not imply it binds.
- Explore load/availability/profile offsets with deterministic parameter grids;
  select scenarios by achieved regimes, then freeze their inputs and explicit
  target windows. Never select a complementarity sector using desired targets.
- Record per-controller region, normalized ramp position, breakpoint distance,
  margins to availability/VW/S/Q bounds; report all bus, generator and branch
  margins. Check all original equations, bounds, both hinge members and direct
  curves independently of solver stopping tests.
- Define tight/slack tolerances in physical units and normalize reporting by
  device or branch rating where useful. Squared S residuals are not S margins.
  Boundary neighbors must be separated from classifier/feasibility tolerances.
- Require targeted limits tight and named competitors strictly slack. A duplicate
  plateau/Q bound is a degeneracy study, not two distinct mechanisms. Check
  sensitivity to small RHS changes before claiming a limit drives dispatch.
- For multi-controller cases require simultaneous contrasting regions, e.g.
  injection/deadband/absorption plus availability-limited and VW-limited devices.
  Keep all controllers coupled through one consistent network solution.
- Keep a baseline with the same added devices but dispatchable P/Q. Also retain
  the unmodified PGLib baseline to validate import; these baselines differ.
- Report infeasible combinations and solver failures separately from accepted
  benchmarks. Avoid narrow solved voltage targets unless reproducible across
  supported solvers; report aggregate quantities when dispatch is nonunique.

## Progress

- [x] Agree the staged network/control/activation matrix.
- [x] Pin PGLib v23.07 provenance and define acceptance criteria.
- [x] Import original 14/118 and congested variants with license and hashes.
- [x] Implement and test canonical transmission NLP and hinged MPCC overlay.
- [x] Cross-check the baseline against PowerModels.
- [x] Freeze first solved multi-controller overlays and independent targets.
- [x] Add optional solver/coverage tests and runnable documentation.
- [x] Add sensitivity-backed isolated inverter VW and capability-limit studies.
- [x] Add isolated voltage/thermal/generator/angle-limit perturbation studies
      on IEEE 14, with within-family isolation and explicit competitor checks.
- [x] Develop matched three-device dispersed/clustered/colocated placement studies.
- [x] Develop fixed-total replica populations and growing distinct-site fleets.
- [x] Separate population, placement/profile and penetration experiments.
- [ ] Freeze plateau, ramp-stratum and knee-neighbor coverage in transmission cases.
- [ ] Develop heterogeneous distinct-site fleets with constant profile mixture.
- [ ] Compare shared `(bus,knot)` hinges with explicitly redundant formulations.
- [ ] Add the first IEEE 118 isolated network-limit sensitivity families.
- [ ] Add RTS 24/IEEE 300 after the coverage gaps are addressed.

## Initial implementation and validation

- Four unmodified, hash-verified source files retain upstream license and
  attribution. PowerModels parses them without its network repair pass; units
  are converted explicitly. Power-system and solver packages remain confined
  to the optional `examples/opf/pglib` environment.
- The canonical builder preserves the full pi/transformer network, costs,
  conventional generator boxes, bus bounds and branch-end/angle limits. All
  voltage magnitudes are optimized; only one reference angle is fixed.
- The first suite has 22 cases: four canonical baselines, four matched law
  variants on each network and two isolated IEEE 14 inverter-limit studies.
  Every overlay has three controllers; both-law overlays have 18 hinge pairs.
- The IEEE 14 mixed case simultaneously exercises VV absorption, deadband and
  injection. The congested IEEE 118 case exercises two injection ramps and a
  plateau. IEEE 118 thermal limits remain active with controllers; the IEEE 14
  API overlays relieve the two thermal limits active in its canonical baseline.
  These outcomes are explicit coverage assertions, not assumed from case names.
- Strict IEEE 14 VW curtailment occurs near the middle of a gentle ramp with
  availability and capability slack. A separate case activates the S circle
  with availability and VW slack. Small independent relaxations increase device
  dispatch and reduce cost. Broader network-limit sensitivities remain open.
- An exploratory IEEE 118 capability overlay failed homotopy termination and
  original-curve checks. It is excluded from accepted scenarios. Solver success
  and physical/coverage tolerances were not weakened to include it.
- Optional CI runs model checks, independent PowerModels/Ipopt baselines, and
  solved activity/sensitivity gates on Julia 1.12. Remote CI is pending a PR or
  workflow dispatch; local validation is recorded below.

## Local validation record

- Julia **1.10.12 and 1.12.6**: optional model tests **554 assertions**,
  independent PowerModels/Ipopt baseline comparison **16 assertions**, and
  solved activity/matched controls/limit perturbations **235 assertions**.
  All **22 accepted cases** solve from the documented flat-voltage starts and
  meet original residual and explicit coverage gates on both Julia versions.
- Julia 1.12.6: complete package suite **2050 assertions** passes. No core
  package code or dependencies changed in this transmission expansion.
- Baseline objectives (our local solves; PowerModels/Ipopt agrees within the
  tested tolerances) are 2178.080428 for IEEE 14, 97213.607396 for IEEE 118,
  5999.363314 for IEEE 14 API and 249614.524493 for IEEE 118 API. These are
  agreement checks between local solves, not global-optimum certificates.
- Validation environment: ADNLPModels 0.8.15, CCOpt 0.1.0, MadNLP 0.10.2,
  PowerModels 0.21.7, Ipopt.jl 1.16.0 and JuMP 1.32.1. Compatible versions are
  specified in the optional Project; the local manifests are not committed.
- Documenter builds successfully with the transmission overview. External link
  checking was disabled for the offline build; the committed configuration
  retains it. Pinned data hashes, local Markdown links, JuliaFormatter and
  `git diff --check` pass. CI definitions are added; remote results are pending.

## Sources

- [PGLib-OPF](https://github.com/power-grid-lib/pglib-opf/tree/dc6be4b2f85ca0e776952ec22cbd4c22396ea5a3)
- [Canonical formulation](https://github.com/power-grid-lib/pglib-opf/blob/dc6be4b2f85ca0e776952ec22cbd4c22396ea5a3/MODEL.tex)
- [Baseline results](https://github.com/power-grid-lib/pglib-opf/blob/dc6be4b2f85ca0e776952ec22cbd4c22396ea5a3/BASELINE.md)
- [Original synthetic case matrix](../CASE_DESIGN.md)

## Review and study expansion

The [implementation review](REVIEW.md) records the initial solved coverage census,
structurally unreachable regions, corrected overlay/target validation gaps,
placement/population experiments and recommended next named cases. The new study
constructors and runner are separate from the initial 22-case registry.

- Network overlays rebuild NLP records and independent-check data from one
  copied authoritative dictionary. Stale records are rejected. VV/VW target
  validation now intersects both laws and fraction windows at the shared voltage.
- Diagnostics distinguish fixed generator boxes from economic bound activity
  and expose normalized inverter margins and nearest-knot distances.
- IEEE 14/118 studies compare three-device placement and profile homogeneity;
  3/6/12 replica populations at fixed aggregate size; 1/3/6/12 controllers on
  nested distinct bus sets; and independent 0.5/1/2 penetration levels.
- IEEE 118 homogeneous clustering adds an observed VV knee. It still needs
  left/right neighbors. Redundant coincident hinges remain explicitly identified
  as a formulation characteristic, especially in replica/knee experiments.
- Eight IEEE 14 network studies perturb one RHS in both directions and at half
  step, assert target and competing bound activity, and compare dispatchable
  policies on the same modified network. Isolating one family does not imply
  every other network family is slack; the branch-1 thermal case additionally
  checks this stronger property.
- The branch-6 receiving-end study combines network-driven curtailment below a
  slack VW cap at one device with strict VW curtailment at another device.
- Remaining highest priorities are in-band absorption/lower-watt plateaus, ramp
  strata away from availability crossovers, knees with neighbors, hardware-Q/VV
  intersections and IEEE 118 location-sensitive thermal/controller interactions.

Validation of the review expansion: Julia 1.10.12/1.12.6 pass **578 model** and
**376 study** assertions. Julia 1.12.6 also passes the existing **235 solved-case**
and **16 independent baseline** assertions after the changes. Documentation
builds with offline external-link checking disabled. The expanded optional CI
gate is committed; remote execution is pending.

## Hard-case search: IEEE 118 capability intersection

The immediate objective is to identify reproducible CCOpt difficulties. Keep
failures and configuration-sensitive cases rather than filtering the search to
examples the solver already handles. Preserve the original 22-case regression
suite as a model-correctness check.

- [x] Reproduce the IEEE 118 device-3 S=0.82 case: the current flat-start
  homotopy reaches its iteration limit; a separately selected exact-sector
  solve yields a numerically feasible point. Default-like and exact-start
  settings give different outcomes, so this is a parameter/start-sensitive
  candidate, not a universal CCOpt failure.
- [x] Sweep S ratings around the capability/VW/availability intersection while
  holding availability, control profiles, network and costs fixed.
- [x] Compare flat, neighboring-case, seeded perturbed and verified-witness
  starts; save their actual vectors and source provenance.
- [x] Compare explicit default-like/current settings and individual changes
  to inner tolerance, relaxation ratio and relaxation floor.
- [x] Checkpoint raw requests before solving and preserve their results
  independently of witness/refinement work; retain exceptions, returned/current
  iterates and original physical checks.
- [x] Save full input snapshots, package/source fingerprints, effective solver
  options, budgets, timings, checksums and replayable request records.
- [x] Verify and preserve feasible witnesses separately from homotopy results.
- [x] Warm up before timed trials, retain warmups separately, support safe
  resume/replay, and summarize known-feasible failures versus accuracy gaps,
  unresolved feasibility and interface errors.
- [x] Run a first complete matrix, curate the 0.82 reproduction and add tests
  that verify the recorder without requiring a particular solver failure.

The BMOPFTools comparison at `faf3d455381e15b651808c489237c0dd921d7cf7`
([experiment notes](https://github.com/frederikgeth/BMOPFTools.jl/blob/faf3d455381e15b651808c489237c0dd921d7cf7/scripts/README.md))
informs this design: active controls, solver/formulation controls, original-curve
checks, sensitivity to inner tolerances, and timing after compilation. Product
residuals alone do not measure the physical error of a steep droop curve. API
exceptions and smooth-formulation overflow remain separate failure categories.

### First search results and next steps

The [harness instructions and results](HARD_SEARCH.md) describe the complete
160-trial run: 22 non-success terminations on known-feasible inputs, 52
solved-status accuracy gaps and 86 runs passing both status and original physical
checks. All eight capability variants have independently verified witnesses.
The [committed 0.82 receipt](hard-cases/README.md) preserves a witness plus
failed, accuracy-limited and recovered raw runs, with actual start/point vectors
and bit hashes. The complete search is retained locally under `search-results/`.

The five current-profile failures occur only from flat starts at factors
0.78–0.83; a matched change of relaxation ratio recovers all five. Seven of the
22 non-success trials report local infeasibility despite verified witnesses.
This is evidence of configuration/initialization sensitivity, not a claim of
universal algorithm failure. Small default-profile physical errors are recorded
separately from stalled, large-residual results.

- [ ] Refine the current-profile flat-start transition between 0.83 and 0.84.
- [ ] Repeat with several explicit perturbation seeds and fixed resource budgets.
- [ ] Minimize network/controller complexity while preserving a reproducible
  failure and an independently verified witness.
- [ ] Add simultaneous-knee/colocated and stressed-PV families to the same
  failure-retaining protocol; compare redundant and shared-knot encodings.
- [ ] Assess feasible-point objective/stationarity evidence separately from
  termination and feasibility, without treating a better point as proof against
  local optimality or a selected-sector solution as a full MPCC certificate.

### Ratio-one simultaneous-transition and generator-Q search

The next search fixes `ratio_one` (which passed the first capability matrix)
and combines three colocated controllers with simultaneous VV deadband/absorption
and VW onset transitions. Separate nearby VW offsets from exactly coincident
knees. Tighten one original conventional-generator Q upper bound without changing
its P bounds, costs or other network data. Preserve separate case snapshots and
all raw starts/results; never infer infeasibility from unsuccessful homotopy.

- [x] Select feasible in-band knees and a local generator-Q limit; document
      actual binding margins and knee distances at numerical witnesses.
- [x] Sweep Q upper limits and VW offsets with flat, neighboring, independently
      perturbed and witness starts under fixed `ratio_one` budgets.
- [x] Retain exact-sector witnesses separately and verify all original physical
      equations, curve laws, boxes and complementarity before registering them.
- [x] Curate reproducible difficult trials, matched recoveries and witnesses;
      report achieved activity separately from requested activity.
- [x] Test case invariants, activity reporting and persistence; document results
      and the next reduction/shared-hinge experiments.

Validation: **105 harness/curated-record assertions** pass on Julia 1.10.12 and
1.12.6. The existing **578 PGLib model assertions** pass on Julia 1.12.6, and
Documenter builds with external link checks disabled locally. The archived
0.82 flat/current request was replayed under the finalized recorder and again
stopped at 500 iterations with the same returned-point residuals. Full resume
left all 800 raw-attempt files unchanged. CI runs the short recorder/witness
tests; the 160-trial search remains an explicit research run.

The completed ratio-one matrix has **54 known-feasible iteration-limit exits**:
all three Q limits × all three VW offsets × six starts. None passes the original
physical gate. All nine separately verified witnesses bind generator 45's Q upper
limit; all three zero-offset witnesses put all three controllers at simultaneous
VV/VW knees. Maximum witness residual is below `2.5e-11`. Nearby Q perturbations
confirm local dispatch/cost influence. The relaxed-Q setup and both separated
knee neighbors also fail, so neither Q tightness nor exact VV/VW coincidence
alone explains the difficulty. See [protocol/results](HARD_SEARCH.md) and
[portable records](hard-cases/README.md#ratio-one-transitionq-limit-receipt).

Historical reduction plan (supporting formulation study; not a gate for application expansion):

- [ ] Compare one, two and three active controllers while retaining the other
      devices as matched dispatchable injections; distinguish controller count
      from total injected power and device hardware.
- [ ] Compare separate hinges with shared `(bus,knot)` hinges on identical
      physics, starts and budgets; report dimensions and redundant constraints.
- [ ] Separate availability from the upper VW plateau and move its crossover
      into the ramp; distinguish coincident physical bounds from shared knots.
- [ ] Split same-bus devices across nearby buses while keeping profiles and
      aggregate ratings fixed; preserve the knee/Q activity evidence.
- [ ] Check selected-sector objective/stationarity diagnostics and report which
      failure persists as a supporting formulation study.

Validation: **419 recorder/archived-point assertions** pass on Julia 1.10.12
and 1.12.6, and the existing **578 transmission-model assertions** pass on
1.12.6. Documenter builds locally with external link checks disabled. A full
resume preserves all **270 raw-attempt files** byte for byte. Remote CI remains
pending. The complete local archive is
`search-results/ieee118-transitions-2026-10-24.tar.gz` (SHA-256
`56d834e6c5e6a12737aa7665a11f77fa662b2800d8eff7f7fcd5f334b35b7d41`).

## Controlled reduction of the ratio-one failures

Use the zero-offset, Q-upper=0.35 pu input as the reference. First run the
12-variant matrix: separate/shared exact `(bus,knot)` hinges × 1/2/3 controlled
devices × upper VW plateau equal to availability / crossover inside the ramp.
All three inverter hardware records, costs and network data stay fixed. Disabled
policies leave their devices dispatchable; only the encoding comparison preserves
the complete physical feasible set. Use identical physical flat and witness
starts across encodings. Preserve constructed feasible witnesses separately from
solver results and report that they do not establish optima of reduced cases.

- [x] Add shared-hinge encoding, physical-point transfer and equivalence tests.
- [x] Add the policy-count/plateau matrix, snapshots and explicit activity reports.
- [x] Add read-only, flushed iteration traces of barrier/relaxation parameters,
      primal/dual residuals and independently evaluated physical errors.
- [x] Run 24 flat/witness trials at 500 iterations and a separate 2000-iteration
      reference; preserve every request, failure, point and witness.
- [x] Repeat informative paired contrasts with three matched perturbation seeds.
- [x] Curate the smallest observed failure and matched recoveries, validate on
      both supported Julia versions, and identify the next reduction.

### Reduction results and next priorities

The full 12-variant × five-start matrix gives **41 physical passes, 10 accuracy
gaps and 9 iteration-limit exits**. All inputs have explicit constructed numerical
witnesses, with their provenance separated from solver runs. The three matched
perturbations were extended to every variant after flat/witness results showed
encoding/start interactions in both directions. Starts match in every physical
variable across variants and encodings for each of the five labels/seeds.

- Separate equal-plateau cases: one/two controllers give accuracy gaps on all
  five starts; three controllers reach 500 iterations on all five.
- Separate ramp-crossing cases pass on all 15 starts. Shared equal-plateau
  one/two-controller cases pass on all ten starts; the three-controller case
  fails from flat and passes the other four.
- Every shared ramp-crossing input has one iteration-limit exit and four passes.
  The one/three-controller failures are flat; the two-controller failure starts
  from a verified feasible witness. Sharing is not uniformly easier.
- The smallest iteration-limit example uses one controller, five shared pairs,
  360 variables and 804 ordinary constraints. Its separate-hinge counterpart
  passes from the same physical flat start. It is initialization-sensitive:
  witness and all three perturbed starts pass.
- The 2,000-iteration original reference terminates with a solved status at
  iteration 1,145 but still misses the physical gate (VV error `2.29e-4` pu).
  This is a budget-sensitive exit followed by an accuracy gap, not evidence of
  permanent nontermination. Traces retain both solver and original residuals.

The [results/protocol](HARD_SEARCH.md#completed-reduction-results-2026-10-25)
and [portable records](hard-cases/README.md#controlled-reduction-records) retain
all 60 outcomes, twelve witnesses, ten representative raw trials, the extended
reference and representative convergence series. Long runs remain manual; CI
checks encoding equivalence, derivatives, witness/point integrity, tracing and
resume/replay without requiring future solvers to keep failing.

Optional diagnostic follow-ups (superseded as the main development agenda):

- [ ] Reduce the network/dispatchable-device complexity of the five-pair case
      while preserving a reproducible flat-start failure and verified witness.
- [ ] Compare physical-accuracy requirements with inner tolerance and actual
      mu/sigma at termination; retain accuracy gaps independently of solver status.
- [ ] Examine selected-sector objective and stationarity evidence separately
      from feasibility when assessing optimality claims for solved examples.
- [ ] Test nearby bus placements after the minimal failure and matched encoding
      recovery; larger-network/application development proceeds independently.

Validation: **585 reduction/curated-record assertions** pass on Julia 1.10.12
and 1.12.6. Existing **419 hard-search**, **578 transmission-model** and **235
solved-case** assertions pass on Julia 1.12.6. Documenter builds locally with
external link checking disabled. Full resume preserves all **366 raw/reference
files** byte for byte. Remote CI is pending.

The smallest shared one-controller flat request replays with identical returned
point and original residuals, again reaching 500 iterations. Complete local
archives are `search-results/ieee118-reductions-2026-10-25.tar.gz` (SHA-256
`d1e68a14d76c1c02a1afae24e26a8d6c46a0169d12e57ea9d4f65e7b448f7387`)
and `search-results/ieee118-reduction-seeds-2026-10-25.tar.gz` (SHA-256
`0ba001433684b3cf24ac2d175ddd608558ad1226f1f166b206a4dfe1237c4e0b`).

## First application catalog: implementation and results

The current deliverable is documented in [APPLICATIONS.md](APPLICATIONS.md).
Three IEEE 118 families each have nominal/elevated/severe physical operating
points, heterogeneous plants at distinct buses and independently overridable
parameters. Matched dispatchable/VV/VW/both constructors retain identical
hardware, availability and network inputs. Nine reference points and nine
matched dispatchable NLP points pass original physical checks. The combined-law
matrix has **26 physical passes and 10 iteration-limit exits** across 36 raw
trials (two profiles × flat/witness starts). All failed inputs have verified
feasible references; the elevated/severe reactive-support inputs challenge both
profiles from both starts. Severity labels remain independent of solver outcomes.

Measured application coverage includes absorption, injection, deadbands, a knee,
VW upper plateaus/ramp positions, capability circles, conventional Q limits,
voltage bounds and both thermal ends. Full renewable availability activates all
six inverter S circles. Reactive support derating produces 14/25/40 tight
conventional Q upper limits at the selected references. The export family has
0/92.584/394.860 MW reference curtailment, with one then both boundary circuits
binding. These are measured reference points, not global/full-MPCC optima.

Six paired exact-sector local comparisons vary one physical parameter at a time
from the severe references. Availability/S 1.00→.99 removes the small capability-
related curtailment while lowering available production; Q-range factor .20→.30
reduces curtailment 354.549→257.464 MW; corridor factor .70→.80 reduces curtailment
394.860→359.044 MW. Settings, sectors and physical starts match within each pair.
They support application interpretation, not solver debugging or global
sensitivity certificates. Raw homotopy results remain unmodified.

The [portable application records](hard-cases/README.md#application-catalog-records)
include all nine witnesses/counterfactuals, eight raw examples, all six local
comparisons, the nine-row coverage catalog and the complete 36-row outcome table.
Complete raw snapshots, requests, starts, points and solver/environment records
remain in the local ignored search directories.

### Next application-development priorities

- [x] Add physically specified operating/profile variants covering both VV outer
      plateaus, the VW lower plateau and ramp strata away from availability
      crossovers. Record unreachable or unachieved regimes without relabelling them.
- [x] Extend heterogeneous fleet count and placement studies on the application
      inputs, independently varying installed capacity, population and geography.
- [ ] Characterize the already available VV-only and VW-only matched variants;
      keep operating effects and measured difficulty separate.
- [ ] Add pinned RTS 24/IEEE 300 data and independent canonical validation, then
      map application cards to those networks. Solver diagnosis is not a gate.
- [ ] Keep the earlier coincident-knee/redundancy cases as an explicit stress
      family alongside the application families, with their provenance intact.

Validation: **1,320 application/model/archived-record assertions** pass on Julia
1.10.12 and 1.12.6. Existing **419 hard-search**, **585 reduction** and **578
transmission-model** assertions pass on Julia 1.12.6. Documenter builds locally
with external link checks disabled. Resume preserves all **235 raw,
counterfactual and witness files** byte for byte. Remote CI remains pending.

The elevated reactive-support ratio_one/flat failure replays at 500 iterations
with identical returned vector and original residuals. Complete local archives:
`search-results/ieee118-applications-2026-10-25.tar.gz` (SHA-256
`fc6e7fc25db7b14d169756652b8fe2b2b3f9b323b16b305aad46953ddfea24ff`)
and `search-results/ieee118-application-sensitivities-2026-10-25.tar.gz` (SHA-256
`da22d3ed8d8e6456755296a552ebd0b36daae4bb268e71bdb223454681a0ace3`).

## Coverage and fleet expansion milestone

Implement nine additional IEEE 118 operating/policy inputs to address the
application catalog's missing VV plateaus, VW lower plateau and ramp-position
coverage. Profiles are explicit synthetic operating policies inside original bus
voltage bands; target descriptions never fix voltages or select sectors. Verify
what both raw points and reference witnesses actually achieve, retain missed
coverage and failures, and do not label intended regimes as solved outcomes.

Add 6/12/24-unit variants of the heterogeneous reactive-support application with
constant aggregate hardware, availability and rating-weighted profile mixture.
Separate same-connection-point replicas (an exact aggregate-physics control) from
clustered/dispersed distinct-site fleets. More distinct sites intentionally change
geography; they are not an isolated controller-count experiment.

- [x] Add policy/operating cards and reusable coverage-variant constructors.
- [x] Add fleet construction, deterministic site selection and source-point transfer.
- [x] Test policy/hardware matching, population invariants, source purity and sparse derivatives.
- [x] Run the nine coverage inputs with current/ratio_one and flat/reference starts.
- [x] Characterize the fleet matrix with ratio_one and flat/reference starts,
      preserving dispatchable baselines, feasible witnesses and every raw outcome.
- [x] Curate measured coverage, difficulty, reference points and remaining gaps;
      update documentation and application priorities. IEEE 300 remains the next
      network expansion, independently of solver diagnosis.

### Coverage and fleet expansion: measured completion

The [extension guide](EXPANSIONS.md) defines nine additional operating-policy
inputs and nine 6/12/24-unit fleet inputs, with the original application registry
unchanged. Verified references now reach both VV outer plateaus, a strict VW
lower plateau, VV absorption fractions near .2/.5/.8 and strict VW ramps across
roughly .25–.79 with availability slack. All settings are explicit synthetic
operating policies within original voltage bands; measured coverage is separate
from targets and the reference points need not be full-MPCC/global optima.

The coverage cohort has **29 physical passes and seven 500-iteration exits**
across 36 raw current/ratio_one flat/reference trials. The injection-service
input challenges both profiles from both starts despite feasible references.
The fleet cohort has **seven physical passes and eleven iteration-limit exits**
across 18 ratio_one flat/reference trials. All 18 dispatchable counterfactuals
pass, all 18 inputs have checked feasible references, and the portable dataset
retains 39 verified references, including five explicitly constructed transfers.

Fleets preserve 900 MVA installed size, 765 MW availability and each original
profile class's rating-weighted hardware/curve mixture. Same-site replicas give
an exact aggregate-physics control; all 6/12/24 variants fail from both starts.
Distinct-site sets are nested and topology-based. Clustered 6/12-unit inputs
fail both starts while 24 units pass both; dispersed 12/24 pass both, with only
the dispersed six-unit flat start failing. Population/geography are coupled for
distinct-site growth, so these outcomes do not establish a pure count benefit.

The [portable expansion records](hard-cases/README.md#operating-coverage-and-fleet-records)
retain constructors/specs, input/source hashes, reference kinds/points, all 54 raw
outcomes, 18 baselines and representative actual starts/results. Complete raw and
reference attempts, including unverified reference solves, remain archived locally.

Next application milestones:

- [x] Import/pin IEEE 300 and independently validate its canonical AC OPF,
      then supply network-specific placements/ratings for the existing families.
- [ ] Characterize matched VV-only/VW-only policies using the existing factories;
      keep physical effects, measured activity and difficulty as separate outputs.
- [ ] Add sequences of steady-state operating points varying load/availability
      and reactive/export headroom, with measured transitions between curve parts.
- [ ] Extend distinct-site fleet geography beyond topology rules when an explicit
      electrical-sensitivity siting study is justified by the application.

### IEEE 300 application milestone

- [x] Import IEEE 300 from the same pinned PGLib revision, preserving source bytes,
      attribution and checksums; keep the 22 legacy overlays unchanged.
- [x] Independently validate canonical AC OPF against PowerModels/Ipopt, including
      objective, original limits, complex-current balance and nonflat derivatives.
- [x] Extend all three application families with explicit IEEE 300 placements,
      ratings and a topology-defined export cutset; preserve IEEE 118 inputs.
- [x] Run the nine family/operating inputs with current/ratio_one and flat/reference
      starts, matched dispatchable baselines and separately verified witnesses.
- [x] Curate original residuals, curve/limit activity, unresolved coverage and raw
      CCOpt failures; test portable records and document the next physical studies.

Difficulty is measured, not required to increase with network size or severity.
Feasible references qualify failures without asserting full-MPCC stationarity or
global optimality. Long solver matrices remain manual research experiments.

Validation: **2,648 expansion/model/archived-record assertions** pass on Julia
1.10.12 and 1.12.6. Existing **1,320 application** and **578 transmission-model**
assertions pass on Julia 1.12.6. Documenter builds locally with external link
checking disabled; remote CI remains pending. Long search matrices are manual,
while CI validates physical invariants and archived evidence without requiring
future solver releases to retain the same failures.

Resume preserves all **540 raw/baseline/sector-reference files** byte for byte.
The injection-service ratio_one/flat failure replays at 500 iterations with
identical returned point and original residuals. Complete local archives are
`search-results/ieee118-coverage-2026-10-25.tar.gz` (SHA-256
`8ca51806b0b0c83faa068126fcbc7c1be44f91fd2065e094863059e30817be37`)
and `search-results/ieee118-fleets-2026-10-25.tar.gz` (SHA-256
`f98c1b13c75d4a210b95a50a6328adc8f99e49411f53fadb73823d6fecfcb164`).

### IEEE 300: measured completion

The [IEEE 300 guide](IEEE300.md) documents the pinned 300/411/69 source,
738-variable / 1,833-constraint canonical AC OPF and independent PowerModels/Ipopt
agreement at approximately 565,219.990890. All three application families now
accept network-specific placements/ratings through `network=:ieee300`. The nine
operating inputs retain matched dispatchable/VV/VW/both-policy construction;
IEEE 118 snapshots and the 22-case legacy registry remain unchanged.

The 36-request matrix executes 32 CCOpt solves and records four unavailable
reference starts: **11 passes, 20 solver failures and one original-VV accuracy
gap**. **16 solver failures have independently checked feasible references**;
four belong to unresolved inputs. Seven controlled inputs have strict references
(maximum original residual 1.63e-8). Seven dispatchable baselines pass; elevated
and severe reactive baselines also fail. Those two operating inputs remain
unresolved and are not counted as established feasible CCOpt challenges.

Nominal reactive support and elevated export fail both profiles from both starts.
Elevated/severe surplus challenge ratio_one from both starts. Coverage includes
all three finite VV parts, knot positions, VW upper plateau/ramp, binding VW
caps coincident with availability, strict inverter-circle limitation, and native
P/Q, voltage and thermal limits. No strict VW limitation, VV
outer plateau, VW lower plateau or native angle limit is reached in this cohort.
Plant Q boxes intentionally lie outside the entire VV range. The two strongest
reactive scenarios have no claimed achieved coverage.

Four additional checked local sensitivity points isolate S-circle oversizing
and cutset-rating relief with identical starts/settings/hinge masks within each
pair. Oversizing releases three S circles but reaches joint availability/VW caps and
reduces curtailment by only 3.02 MW; export rating relief reduces it by 261.32 MW.
These are selected-sector local responses, not global sensitivity certificates.

Next IEEE 300 case-design matrix, in priority order:

| Study axis | Proposed physical cases | Admission / comparison |
| --- | --- | --- |
| Reactive operating frontier | Load 1/1.025/1.05 and signed Q interval factors 1/.95/.9/.85/.8, with other plant inputs held fixed within each sweep | Check dispatchable and controlled references; retain unresolved candidates separately; do not infer infeasibility from local statuses |
| Conventional reactive reserve | Derate selected positive Q upper bounds at fixed Q lower bounds, then release only those upper bounds | Source generators 5/44/45 have positive Q minima; signed interval scaling is not a nested one-sided reserve study |
| VV/VW policy coverage | Lower-amplitude reactive saturation services and earlier active-power backstops, followed by matched VV-only/VW-only/both policies | Measure strict plateau/ramp positions and VW-limited dispatch with slack availability; preserve hardware and availability within each policy comparison |
| Fleet geography/population | 6/12/24 units at constant aggregate hardware/availability/profile mixture; same-site and distinct-site controls | Require voltage-class/interface eligibility for distinct sites, avoiding automatic GW placements at small low-voltage radial attachments; geography changes are not pure count changes |
| Operating sequences | Load/availability/reserve trajectories through verified curve and native-limit transitions | Compare flat and checked neighboring/reference starts; report physical transitions separately from raw CCOpt difficulty |

The high-priority difficulty benchmarks are already available. Resolving every
stress input or explaining a solver failure is not required before implementing
these physically motivated extensions. Publishing complete portable archives and
running remote CI remain follow-up work; the committed receipts support local
validation without the long searches.

Validation: **1,146 IEEE 300 assertions** pass on Julia 1.10.12 and 1.12.6,
including all archived raw points, strict references, independent canonical
points, sparse nonflat derivatives, case/policy invariants, isolated-limit
recipes and recorder resume integrity. The five-network independent canonical
suite passes **20 assertions**; existing **578 model**, **235 solved-case**,
**419 hard-search**, **1,320 application** and **2,648 expansion** assertions pass
on Julia 1.12.6. Documenter builds locally with external link checking disabled.
Remote CI and publication of the full local archives remain pending.

## IEEE 300 operating-policy matrix

Build from the seven verified IEEE 300 operating inputs. Keep matched hardware,
availability and network records across dispatchable/VV-only/VW-only/both-law
variants, and retain the IEEE 118 definitions and archived snapshot identities.
Intended regimes never select a witness sector or fix a bus voltage.

| Axis | Initial inputs | Physical interpretation / required measured evidence |
| --- | --- | --- |
| Strict VW | Gentle/firm/steep caps on elevated surplus | Interconnection export ceilings with different voltage gains; require P below availability and slack S circle at a binding VW cap |
| VV saturation | Injection service on nominal reactive support; absorption service on elevated surplus | Bounded reactive participation with explicit setpoints; require strict outer-plateau positions at checked feasible references |
| VW lower plateau | Early backstop on a verified export input | Earlier voltage-based export intervention; distinguish plateau position from independent cap limitation |
| Q-upper reserve | Three one-sided contractions of nominal reactive Q intervals | Hold every Q lower bound, P bound/cost, plant and network input fixed; interpolate only Q upper bounds toward original lower bounds, including positive-Q-minimum units |

- [x] Implement network-aware policy cards, one-sided reserve recipes and strict
      limit classification without changing legacy reports by default.
- [x] Validate authoritative overlays, policy matching, source identity, derivative
      products and recorder behavior; freeze candidate definitions in a commit.
- [x] Validate independent numerical references and achieved regimes; retain
      unsuccessful candidates and reference attempts explicitly.
- [x] Freeze the accepted matrix and run both CCOpt profiles from flat/checked
      reference starts, with matched dispatchable baselines and raw failures intact.
- [x] Curate portable numerical evidence, measured physical/solver matrices,
      remaining gaps and the next application cases; update CI, docs and roadmap.

A missing reference is unresolved feasibility, and a tight VW cap coincident with
availability is not strict VW curtailment. No full-MPCC stationarity or global
optimality is asserted by selected-sector local references. Explaining CCOpt
failures is not a prerequisite for admitting physically meaningful feasible cases.

### IEEE 300 policy matrix: measured completion

The [policy matrix](POLICY_MATRIX.md) adds six network-specific operating policies
and three one-sided Q-upper reserve inputs. All nine have independently checked
references (maximum original residual **1.73e-11**) before benchmarking. The
three cap gains strictly limit four plants each, with strict ramp positions
around **.21–.78**. The saturation services reach two absorption and four injection
plateaus; the early export backstop reaches two VW lower plateaus, one with
strict cap limitation. These fill the intended coverage gaps without fixed
voltages, forced target sectors, redundant hardware Q bounds or changed legacy
IEEE 118 inputs.

Reserve fractions .98/.95/.90 retain that fraction of each original Q-interval
width at the nominal reactive operating point. Every original Q lower bound,
plant, cost, P limit, load and native network limit remains fixed. Q-upper bound
counts are **35/35/37**, with lower-voltage counts **1/2/4**. The two older coupled
signed-Q stress cases retain their unresolved status; this sequence is a
separate feasible application family.

All **36 raw CCOpt trials execute**. **Four pass and 32 reach 500 iterations**;
all 32 failures have prevalidated references. All nine matched dispatchable runs
pass (the three cap gains share one physical dispatchable baseline). Steep VW,
both saturation services, mild reserve and strong reserve fail both profiles
from both starts. Other inputs recover in different single profile/start
combinations, so neither gain nor reserve severity orders measured difficulty.
The production source remains frozen at `732d0dd` throughout reference
validation and benchmarking; no solver-engine changes are introduced.

Portable numerical records retain every raw start/returned point, reference,
baseline, original residual and actual solver option. The recorder verifies
prepared references before any raw solve and preserves their provenance.
Resume retains all **318 matrix files** byte for byte; receipt regeneration is
byte-identical. Full local archives, including source/environment snapshots and
solver logs, are indexed in the [record guide](hard-cases/README.md#ieee-300-policy-matrix-records).

Validation: **2,199 policy-matrix assertions** pass on Julia 1.10.12 and 1.12.6,
including all recorded points, regime classifications, one-sided interval
nesting, law/hardware matching, sparse nonflat derivatives, tampered-reference
rejection and prepared-reference resume. Existing **2,648 expansion** and
**1,146 IEEE 300** assertions pass on Julia 1.12.6. Documenter builds locally
with external link checking disabled. CI now runs the new suite; remote CI and
publication of complete archives remain pending.

Next physically motivated additions:

| Study | Controlled comparison | Qualification |
| --- | --- | --- |
| Matched law variants | VV-only/VW-only/both on representative cap, saturation and reserve inputs with identical hardware/operating envelopes | Transfer and independently recheck feasible physical points; distinguish transfers from solver-produced references |
| Interior ramp/backstop policies | Vary intervention windows to add strict VW mid-ramp interiors beyond the quarter/late positions already covered | Measure achieved positions and competing margins; keep unchanged inputs explicit |
| IEEE 300 fleets | Fixed-total 6/12/24-unit heterogeneous same-site replicas and geographically distinct plants | Admit connection sites by voltage class/interface capacity; retain exact aggregate-physics controls and checked references |
| Operating trajectories | Separate load, availability and one-sided Q-upper changes around the verified reserve sequence | Preserve feasibility/transition evidence and raw flat/neighbor/reference outcomes; do not infer infeasibility from local solver failures |

These studies grow the physically interpretable benchmark families. Diagnosing
why CCOpt fails is optional and does not gate the next case additions.
