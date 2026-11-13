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
pkg> add MPCCModels
```

## Usage

MPCCModels takes as input an `AbstractNLPModel` from [NLPModels](https://github.com/JuliaSmoothOptimizers/NLPModels.jl/), with `ind_x1` (resp. `ind_x2`) the indices of the variables or constraint appearing in the left-hand complementarity (resp. right-hand complementarity), depending on `cc_types`:
```julia
using NLPModels,MPCCModels
nlp = create_your_nlp_model()
mpcc = MPCCModel(nlp, ind_x1, ind_x2, cc_types)
```
