![Logo](logo-full.svg)
---
| **Documentation** | **Build Status** | **Coverage** | **DOI** |
|:-----------------:|:----------------:|:----------------:|:----------------:|
| [![doc](https://img.shields.io/badge/docs-dev-blue.svg)](https://madnlp.github.io/MadNLP.jl/dev) | [![build](https://github.com/MadNLP/MadNLP.jl/workflows/build/badge.svg?branch=dev%2Fgithub_actions)](https://github.com/MadNLP/MadNLP.jl/actions?query=workflow%3Abuild) | [![codecov](https://codecov.io/gh/MadNLP/MadNLP.jl/branch/master/graph/badge.svg?token=MBxH2AAu8Z)](https://codecov.io/gh/MadNLP/MadNLP.jl) | [![DOI](https://zenodo.org/badge/DOI/10.5281/zenodo.5825776.svg)](https://doi.org/10.5281/zenodo.5825776) |

MadNLP is a [nonlinear programming](https://en.wikipedia.org/wiki/Nonlinear_programming) (NLP) solver, purely implemented in [Julia](https://julialang.org/). MadNLP implements a filter line-search algorithm, as that used in [Ipopt](https://github.com/coin-or/Ipopt). MadNLP seeks to streamline the development of modeling and algorithmic paradigms in order to exploit structures and to make efficient use of high-performance computers.

## Installation
```julia
pkg> add MadNLP
```
Optionally, various extension packages can be installed together:
```julia
pkg> add MadNLPHSL, MadNLPPardiso, MadNLPMumps, MadNLPGPU, MadNLPGraph, MadNLPKrylov
```
These packages are stored in the `lib` subdirectory within the main MadNLP repository. Some extension packages may require additional dependencies or specific hardware. For the instructions for the build procedure, see the following links: [MadNLPHSL](https://github.com/MadNLP/MadNLP.jl/tree/master/lib/MadNLPHSL), [MadNLPPardiso](https://github.com/MadNLP/MadNLP.jl/tree/master/lib/MadNLPHSL), [MadNLPGPU](https://github.com/MadNLP/MadNLP.jl/tree/master/lib/MadNLPGPU).


## Usage
### Interfaces
MadNLP is interfaced with modeling packages:
- [JuMP](https://github.com/jump-dev/JuMP.jl)
- [Plasmo](https://github.com/zavalab/Plasmo.jl)
- [NLPModels](https://github.com/JuliaSmoothOptimizers/NLPModels.jl).
Users can pass various options to MadNLP also through the modeling packages. The interface-specific syntaxes are shown below. To see the list of MadNLP solver options, check the [OPTIONS.md](https://github.com/MadNLP/MadNLP/blob/master/OPTIONS.md) file.

#### JuMP interface
```julia
using MadNLP, JuMP

model = Model(()->MadNLP.Optimizer(print_level=MadNLP.INFO, max_iter=100))
@variable(model, x, start = 0.0)
@variable(model, y, start = 0.0)
@NLobjective(model, Min, (1 - x)^2 + 100 * (y - x^2)^2)

optimize!(model)

```

#### NLPModels interface
```julia
using MadNLP, CUTEst
model = CUTEstModel("PRIMALC1")
madnlp(model, print_level=MadNLP.WARN, max_wall_time=3600)
```

#### Plasmo interface (requires extension `MadNLPGraph`)
```julia
using MadNLP, MadNLPGraph, Plasmo

graph = OptiGraph()
@optinode(graph,n1)
@optinode(graph,n2)
@variable(n1,0 <= x <= 2)
@variable(n1,0 <= y <= 3)
@constraint(n1,x+y <= 4)
@objective(n1,Min,x)
@variable(n2,x)
@NLnodeconstraint(n2,exp(x) >= 2)
@linkconstraint(graph,n1[:x] == n2[:x])

MadNLP.optimize!(graph; print_level=MadNLP.DEBUG, max_iter=100)

```

### Linear Solvers
MadNLP is interfaced with non-Julia sparse/dense linear solvers:
- [Umfpack](https://people.engr.tamu.edu/davis/suitesparse.html)
- [MKL-Pardiso](https://software.intel.com/content/www/us/en/develop/documentation/mkl-developer-reference-fortran/top/sparse-solver-routines/intel-mkl-pardiso-parallel-direct-sparse-solver-interface.html)
- [MKL-Lapack](https://software.intel.com/content/www/us/en/develop/documentation/mkl-developer-reference-fortran/top/lapack-routines.html)
- [HSL solvers](http://www.hsl.rl.ac.uk/ipopt/) (requires extension)
- [Pardiso](https://www.pardiso-project.org/) (requires extension)
- [Mumps](http://mumps.enseeiht.fr/)  (requires extension)
- [cuSOLVER](https://docs.nvidia.com/cuda/cusolver/index.html) (requires extension)

Each linear solver in MadNLP is a Julia type, and the `linear_solver` option should be specified by the actual type. Note that the linear solvers are always exported to `Main`.

#### Built-in Solvers: Umfpack, PardisoMKL, LapackCPU
```julia
using MadNLP, JuMP
# ...
model = Model(()->MadNLP.Optimizer(linear_solver=UmfpackSolver)) # default
model = Model(()->MadNLP.Optimizer(linear_solver=LapackCPUSolver))
```

#### HSL (requires extension `MadNLPHSL`)
```julia
using MadNLP, MadNLPHSL, JuMP
# ...
model = Model(()->MadNLP.Optimizer(linear_solver=Ma27Solver))
model = Model(()->MadNLP.Optimizer(linear_solver=Ma57Solver))
model = Model(()->MadNLP.Optimizer(linear_solver=Ma77Solver))
model = Model(()->MadNLP.Optimizer(linear_solver=Ma86Solver))
model = Model(()->MadNLP.Optimizer(linear_solver=Ma97Solver))
```

#### Mumps (requires extension `MadNLPMumps`)
```julia
using MadNLP, MadNLPMumps, JuMP
# ...
model = Model(()->MadNLP.Optimizer(linear_solver=MumpsSolver))
```

#### Pardiso (requires extension `MadNLPPardiso`)
```julia
using MadNLP, MadNLPPardiso, JuMP
# ...
model = Model(()->MadNLP.Optimizer(linear_solver=PardisoSolver))
model = Model(()->MadNLP.Optimizer(linear_solver=PardisoMKLSolver))
```

#### LapackGPU (requires extension `MadNLPGPU`)
```julia
using MadNLP, MadNLPGPU, JuMP
# ...
model = Model(()->MadNLP.Optimizer(linear_solver=LapackGPUSolver))
```


#### Schur and Schwarz (requires extension `MadNLPGraph`)
```julia
using MadNLP, MadNLPGraph, JuMP
# ...
model = Model(()->MadNLP.Optimizer(linear_solver=MadNLPSchwarz))
model = Model(()->MadNLP.Optimizer(linear_solver=MadNLPSchur))
```
The solvers in `MadNLPGraph` (`Schur` and `Schwarz`) use multi-thread parallelism; thus, Julia session should be started with `-t` flag.
```sh
julia -t 16 # to use 16 threads
```

## Citing MadNLP.jl
If you use MadNLP.jl in your research, we would greatly appreciate your citing it.
```bibtex
@article{shin2020graph,
  title={Graph-Based Modeling and Decomposition of Energy Infrastructures},
  author={Shin, Sungho and Coffrin, Carleton and Sundar, Kaarthik and Zavala, Victor M},
  journal={arXiv preprint arXiv:2010.02404},
  year={2020}
}
```

## Bug reports and support
Please report issues and feature requests via the [Github issue tracker](https://github.com/MadNLP/MadNLP.jl/issues).
