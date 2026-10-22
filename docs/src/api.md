# API

As stated in the [Home](@ref) page, we consider the nonlinear optimization
problem in the following format:
```math
\begin{aligned}
\min \quad & f(x) \\
& \ell^c \le c(x) \le u^c,\\
& \ell^G\le G(x) \perp H(x)\ge \ell^H, \\
& \ell \leq x \leq u,
\end{aligned}
```

We implement this by wrapping an `AbstractNLPModel` in the form:
```math
\begin{aligned}
\min \quad & f(x) \\
& \ell^g \leq g(x) \leq u^g \\
& \ell \leq x \leq u,
\end{aligned}
```
along with three vectors `ind_cc1`, `ind_cc2`, and `cc_types`.
We encode the functions ``G(x)`` and ``H(x)`` via these vectors in the following way.
The vectors `ind_cc1` and `ind_cc2` correspond to indexes into the vectors ``x`` and ``g(x)``.
Which of these vectors are the target of the indexing is determined by the values in `cc_types`:

| `CCType[k]` | ``G_k(x)`` | ``H_k(x)`` | ``\ell^G_k`` | ``\ell^H_k`` |
|-------------|------------|------------|--------------|--------------|
| `VarVar`    | ``x_i``    | ``x_j``    | ``\ell_i``   | ``\ell_j``   |
| `VarCon`    | ``x_i``    | ``g_j(x)`` | ``\ell_i``   | ``\ell^g_j`` |
| `ConVar`    | ``g_i(x)`` | ``x_j``    | ``\ell^g_i`` | ``\ell_j``   |
| `ConCon`    | ``g_i(x)`` | ``g_j(x)`` | ``\ell^g_i`` | ``\ell^g_j`` |

This allows the user maximum flexibility when it comes to modelling the original MPCC.
Any constraint row used on either side of a complementarity pair must have a
finite lower bound and an upper bound of ``+\infty``. Its lower bound is used
as the corresponding complementarity lower bound, and the row is removed from
the ordinary constraint list. The constructor throws an `ArgumentError` if a
selected row does not meet these bound requirements.

For practical algorithms however, we reformulate the problem into the so called "vertical form":
```math
\begin{aligned}
\min \quad & f(x) \\
& \ell^c \le c(x) \le u^c,\\
& \ell^G\le x_1 \perp x_2\ge \ell^H, \\
& \ell_0 \leq x_0 \leq u_0,
& x_1 \leq u_1,
& x_2 \leq u_2,
\end{aligned}
```
where ``x_0`` ``x_1`` and ``x_2`` correspond to subsets of the decision variables ``x``.
This is done via the [`vertical_form`](@ref) function.

In order to develop algorithms for solving MPCCs we define the following API for the [`AbstractMPCCModel`](@ref) type:

| Function                                              | `MPCCModels.jl` function                                              | Notes                                         |
|-------------------------------------------------------|-----------------------------------------------------------------------|-----------------------------------------------|
| ``G(x)``                                              | [`comp_left`](@ref)                                                   | Raw evaluation of ``G(x)``                    |
| ``G(x)-\ell^G``                                       | [`comp_res_left`](@ref)                                               | Left hand side complementarity residual       |
| ``\nabla_x G(x)``                                     | [`jac_comp_left_structure`](@ref) and [`jac_comp_left_coord`](@ref)   | Jacobian of left hand side of complementarity |
| ``H(x)``                                              | [`comp_right`](@ref)                                                  |                                               |
| ``H(x)-\ell^H``                                       | [`comp_res_right`](@ref)                                              | Right hand side complementarity residual      |
| ``\nabla_x G(x)``                                     | [`jac_comp_right_structure`](@ref) and [`jac_comp_right_coord`](@ref) | Jacobian of left hand side of complementarity |
| ``\vert\min(G(x)-\ell^G,H(x)-\ell^H,0)\vert_\infty``    | [`comp_residual`](@ref)                                               |                                               |
| ``\vert (G(x)-\ell^G)\odot(H(x)-\ell^H)\vert_\infty`` | [`comp_residual_product`](@ref)                                       |                                               |
| ``(G(x)-\ell^G)\cdot(H(x)-\ell^H)``                    | [`comp_residual_sum`](@ref)                                           |                                               |

along with overloads for the following `NLPModels.jl` API.

| Function                  | `NLPModels.jl` function                                            | notes                                                                                                            |
|---------------------------|--------------------------------------------------------------------|------------------------------------------------------------------------------------------------------------------|
| ``f(x)``                  | [`NLPModels.obj`](@ref)                                            |                                                                                                                  |
| ``\nabla f(x)``           | [`NLPModels.grad`](@ref)                                                     |                                                                                                                  |
| ``c(x)``                  | [`NLPModels.cons`](@ref)                                                     | Note that this includes possible lifted constraints but _not_ those contained in ``G(x)`` or ``H(x)``            |
| ``\nabla c(x)``           | [`NLPModels.jac`](@ref), [`NLPModels.jac_structure`](@ref), and [`NLPModels.jac_coord`](@ref)    | Note that this includes possible lifted constraints but _not_ those contained in ``G(x)`` or ``H(x)``            |
| ``\nabla^2 L(x,\lambda)`` | [`NLPModels.hess`](@ref), [`NLPModels.hess_structure`](@ref), and [`NLPModels.hess_coord`](@ref) | Note that this is not the MPCC lagrangian but the NLP Lagrangian with no contribution from the complementarities |
