# SchedNEM

[![Build Status](https://github.com/tim-powersystems/SchedNEM.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/tim-powersystems/SchedNEM.jl/actions/workflows/CI.yml?query=branch%3Amain)

Scheduling module for reliability studies of the NEM. Complementary to PRASNEM.jl.

The implementation for the rolling horizon optimisation is based on the JuMP tutorial by Diego Tejada, see [here](https://jump.dev/JuMP.jl/stable/tutorials/algorithms/rolling_horizon/).

Note that the default solver is HiGHS, however, we recommend using Gurobi to reduce solving time. The optimiser can be specified as optional parameter in `build_operation_model()`.

## Detailed documentation to follow
