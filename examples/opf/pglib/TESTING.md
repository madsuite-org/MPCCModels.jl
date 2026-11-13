# OPF test tiers and evidence

OPF factories, case cards, diagnostics and search tools are optional example
APIs; MPCCModels does not export them. The runtime dependency list is unchanged.
The separate example environments declare their solver and power-system dependencies.

| Tier | Trigger | Checks |
| --- | --- | --- |
| Package | Every PR/push to master | Existing `Pkg.test()` matrix on Julia 1.10, 1.12 and prerelease; all 37 small OPF definitions and core API regressions |
| Transmission PR | Every PR/push to master | `test-model.jl`: import/physics/sparse derivatives/input validation; `test-fast.jl`: 14 archived original-feasible points, all nine policy activities and reporting/provenance regressions; no optimizer invocation |
| OPF integration | Manual **OPF integration** workflow or weekly default-branch schedule | All 37 small solved regimes; independent PowerModels canonical solves; all ten original PGLib suites; operating-matrix invariants, derivatives and archived evidence; complete receipt checks and compact-fixture derivation |
| Research search | Explicit local command | Multi-start, multi-setting CCOpt sweeps, raw traces and reference searches; complete attempts retained, never a required PR gate |

The PR job still installs the optional environment, including the solver packages
used by the research tools. Its test path invokes no optimizer. Exhaustive tests
include bounded recorder smoke solves and fresh canonical/regime solves, but do
not rerun the full 500-iteration difficulty matrices. Historical failure evidence
is checked numerically; future solver versions need not repeat old failures.
Weekly runs begin after the workflow reaches the repository default branch.
The existing **CI** workflow also has a manual `full_opf` boolean input that
requests this same integration tier on the selected ref. This permits branch
validation through the existing workflow entry point; the new standalone
workflow becomes directly dispatchable after it reaches the default branch.

From the repository root, after developing this checkout in the optional project:

```sh
julia --project=examples/opf/pglib examples/opf/pglib/test-model.jl
julia --project=examples/opf/pglib examples/opf/pglib/test-fast.jl
julia --project=examples/opf/pglib examples/opf/pglib/test-evidence.jl
```

The [evidence guide](hard-cases/README.md#access-and-preservation) explains the
lossless receipt archive, compact derived witness fixture and complete raw-log
bundle. Nothing in these checks asserts global optimality or MPCC stationarity.

## Local validation after tiering (2026-10-25)

With cached dependencies on the development machine (Julia 1.12.6), separate
processes for `test-model.jl` and `test-fast.jl` took **27.42 s + 36.12 s**.
The complete eleven-script PGLib integration tier took **538.37 s**; the separate
37-case solved gate took **23.10 s**. These include Julia process startup and
compilation in each process, and exclude dependency installation. They are local
observations, not cold Linux CI measurements or a runtime guarantee. The small
follow-up provenance round-trip assertions are included in the fast-tier timing.

## Operating-condition extension (2026-10-26)

The single-state IEEE 118/300 matrix adds `test-operating-model.jl` and
`test-operating-evidence.jl` to the exhaustive tier. The former checks independent
physical axes, same-site population equivalence and sparse directional
derivatives. The latter checks deterministic compact selection, all retained
reference/raw/baseline points, complete census dimensions, and recorder resume
integrity. No CI job reruns the 46-input research matrix. The fast tier includes
a bounded selection of its archived feasible references alongside the historical
14-point fixture.

The extended fixture has twenty points (fourteen historical plus six operating
references) and passes 172 assertions on Julia 1.10/1.12. Cached Julia 1.12
measurements for this extension: fast checks 48.51 seconds, operating-model
invariants/derivatives 40.38 seconds, and operating-evidence/resume checks 82.98
seconds. They exclude dependency installation and are not cold Linux CI timings.
Core tests pass 2,050 assertions; the affected legacy expansion/policy suites
pass 2,648/2,254 respectively. Receipt, census and sweep regeneration is checked
locally byte for byte against the retained raw archive; CI needs no private
archive to check the committed twelve-case numerical evidence.
