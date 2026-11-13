# PGLib-OPF source data

These five MATPOWER files are unmodified copies from **PGLib-OPF v23.07**,
commit `dc6be4b2f85ca0e776952ec22cbd4c22396ea5a3`:

| Local file | Original path | Buses | Branches | Generators |
| --- | --- | ---: | ---: | ---: |
| `pglib_opf_case14_ieee.m` | repository root | 14 | 20 | 5 |
| `pglib_opf_case118_ieee.m` | repository root | 118 | 186 | 54 |
| `pglib_opf_case14_ieee__api.m` | `api/` | 14 | 20 | 5 |
| `pglib_opf_case118_ieee__api.m` | `api/` | 118 | 186 | 54 |
| `pglib_opf_case300_ieee.m` | repository root | 300 | 411 | 69 |

Source: [IEEE PES Power Grid Library, pinned revision](https://github.com/power-grid-lib/pglib-opf/tree/dc6be4b2f85ca0e776952ec22cbd4c22396ea5a3).
The `api` files describe heavily loaded operating conditions intended to
exercise thermal limits. Added inverter overlays are implemented in `cases.jl`;
they do not edit these files and are not official PGLib benchmark instances.

The data are licensed under **Creative Commons Attribution 4.0 International**.
The upstream [LICENSE](LICENSE) is included verbatim. Each source file retains
its attribution, original source notes and license notice, including attribution
to Richard D. Christie, University of Washington, for these IEEE test systems.
Follow the file headers and PGLib's citation guidance when publishing results.

`SHA256SUMS` records the exact imported bytes, including the upstream license.
The loader verifies each selected case's hash before parsing it. No network
access is needed to run the examples after installing Julia dependencies.
