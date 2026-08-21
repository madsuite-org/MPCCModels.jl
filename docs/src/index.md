# [MPCCModels.jl documentation](@id Home)

This package provides facilities to represent Mathematical Programs with Complementarity Constraints (MPCC) problems in Julia and a standardized API to evaluate the functions and their derivatives.
The main objective is to be able to rely on that [API](@ref) when designing specialized MPCC solvers in Julia.
It is built on the excellent tool for representing general Nonlinear Programs (NLPs) [`NLPModels.jl`](https://github.com/JuliaSmoothOptimizers/NLPModels.jl).

## Introduction

This package is built for modelling problems of the form
```math
\begin{aligned}
\min_x \quad & f(x) \\
& \ell^c \le c(x) \le u^c,\\
& \ell^G\le G(x) \perp H(x)\ge \ell^H, \\
& \ell \leq x \leq u,
\end{aligned}
```
where ``f:\mathbb{R}^n\rightarrow\mathbb{R}``,
``c:\mathbb{R}^n\rightarrow\mathbb{R}^m``,
``G:\mathbb{R}^n\rightarrow\mathbb{R}^{n_{cc}}``,
``H:\mathbb{R}^n\rightarrow\mathbb{R}^{n_{cc}}``,
and ``\ell_a \le a\perp b \ge \ell_b`` means that for each element of the vectors ``a`` and ``b``, at least one must be zero.

Optimization problems are represented by an instance/subtype of `AbstractMPCCModel`.
Such instances are composed of

- an instance of `MPCCModelMeta`, which provides information about the problem,
  including the number of variables, constraints, bounds on the variables, etc.
  This `MPCCModelMeta` wraps an `AbstractNLPModelMeta` and only updates the necessary fields by overloading the getter api in `NLPModels.jl`.
- the underlying `AbstractNLPModel` which stores the data necessary to build the MPCC.

## Important Usage Note
Note that while we support modelling MPCCs with nonlinear functions ``G(x)`` and ``H(x)``, the [API](@ref) supports only vertical form MPCCs:
```math
\begin{aligned}
\min_x \quad & f(x) \\
& \ell^c \le c(x) \le u^c,\\
& \ell^G\le x_1 \perp x_2\ge \ell^H, \\
& \ell_0 \leq x_0 \leq u_0,
\end{aligned}
```
where ``x_0`` ``x_1`` and ``x_2`` correspond to subsets of the decision variables ``x``.
In order to ensure your MPCC is in vertical form use the [`vertical_form`](@ref) function.
The function adds two slack variables ``s = (s_1, s_2)`` to reformulate the complementarity
constraints appearing in the MPCC as:
```math
\begin{aligned}
\min_{x,s} \quad & f(x) \\
& \ell^c \le c(x) \le u^c,\\
& G(x) - s_1 = 0 \\
& H(x) - s_2 = 0 \\
& \ell^G\le s_1 \perp s_2 \ge \ell^H, \\
& \ell \leq x \leq u,
\end{aligned}
```



## Install

Install `MPCCModels.jl` with the following command.
```julia
pkg> add MPCCModels
```

This will enable the use of the API and the tools described here, and it allows the creation of a manually written model.


## License

This content is released under the [MIT](https://opensource.org/license/mit) License.

## Contents

```@contents
```
