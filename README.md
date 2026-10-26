# MPCCModels

[![Build Status](https://github.com/apozharski/MPCCModels.jl/actions/workflows/CI.yml/badge.svg?branch=master)](https://github.com/apozharski/MPCCModels.jl/actions/workflows/CI.yml?query=branch%3Amaster)
[![docs-stable][docs-stable-img]][docs-stable-url]
[![docs-dev][docs-dev-img]][docs-dev-url]

[docs-stable-img]: https://img.shields.io/badge/docs-stable-blue.svg
[docs-stable-url]: https://madsuite.org/MPCCModels.jl/stable
[docs-dev-img]: https://img.shields.io/badge/docs-dev-purple.svg
[docs-dev-url]: https://madsuite.org/MPCCModels.jl/dev

A julia package built on top of [NLPModels](https://github.com/JuliaSmoothOptimizers/NLPModels.jl/) for providing the functions needed to build solvers for Mathematical Programs with Complementarity Constraints.

## Installation

To install MPCCModels, simply proceed to
```julia
pkg> add https://github.com/MadNLP/MPCCModels.jl
```

## Usage

MPCCModels takes as input an `AbstractNLPModel` from [NLPModels](https://github.com/JuliaSmoothOptimizers/NLPModels.jl/), with `ind_x1` (resp. `ind_x2`) the indices of the variables appearing in the left-hand complementarity (resp. right-hand complementarity):
```julia
using NLPModels,MPCCModels
nlp = create_your_nlp_model()
mpcc = MPCCModel(nlp, ind_x1, ind_x2)
```

**Important**: Note that currently we only support the [`API`](https://madsuite.org/MPCCModels.jl/dev/api/#API) for MPCCs in "vertical form".
In order to make sure your MPCC is in vertical form use the [`vertical_form`](https://madsuite.org/MPCCModels.jl/dev/reference/#MPCCModels.vertical_form-Tuple{AbstractMPCCModel}) function:
```julia
using NLPModels,MPCCModels
nlp = create_your_nlp_model()
mpcc = MPCCModel(nlp, ind_cc1, ind_cc1, cctypes)
vertical_mpcc = vertical_form(mpcc)
```

## Examples

The [balanced AC OPF example](examples/opf/README.md) models volt-var and
volt-watt controls using exact complementarity hinges. It includes 37 single- and
multiple-controller cases, explicit network data, feasible reference points,
and an optional CCOpt integration test that checks achieved operating regimes.

The optional [PGLib transmission suite](examples/opf/pglib/README.md) adds 22
IEEE 14/118 benchmark variants with canonical AC OPF baselines, three-inverter
VV/VW overlays, solved bound/curve coverage, and limit-sensitivity checks.
