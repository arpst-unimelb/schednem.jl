# SchedNEM

[![Build Status](https://github.com/tim-powersystems/SchedNEM.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/tim-powersystems/SchedNEM.jl/actions/workflows/CI.yml?query=branch%3Amain)
[![Coverage](https://codecov.io/gh/tim-powersystems/SchedNEM.jl/branch/main/graph/badge.svg)](https://codecov.io/gh/tim-powersystems/SchedNEM.jl)

Scheduling module for reliability studies of the NEM. Complementary to PRASNEM.jl.


The implementation for the rolling horizon optimisation is based on the JuMP tutorial by Diego Tejada, see [here](https://jump.dev/JuMP.jl/stable/tutorials/algorithms/rolling_horizon/).

Note that the default solver is HiGHS, however, we recommend using Gurobi to reduce solving time. The optimiser can be specified as optional parameter in `build_operation_model()`.

---
# Working notes

Current version:
- No DSP included (which would correspond to PRAS logic of using storage first before DSP, but not AEMO logic, which gives DSP specific prices below market cap.)
- Long-term optimisation for hydro is not included yet.



---
## Examples

```Julia
using SchedNEM
using PRAS

# First, load the PRAS file
sys = SystemModel("src/sample_data/pras_files/2025-01-07_to_2025-01-13_s2_123456789101112_regions.pras")
sys.regions.load .+= 1000 # Increase the load to see unserved energy events
# Build the economic dispatch model (add Generator.csv file to obtain the generator running costs)
m = SchedNEM.build_operation_model(sys; optimisation_window=48, move_forward=24, input_folder="./src/sample_data/nem12/")
# Run the model
res = SchedNEM.run_operation_model(m, sys)

#%% Now we can compare the adequacy of supply of the system under different storage dispatch assumptions

# Compare with expecation dispatch
# => This means storage/genstorage operation is directly added/subtracted from the load, and the units disabled in PRAS
sys_stor_fixed = deepcopy(sys)
sys_stor_fixed = SchedNEM.updateMarketExpectationDispatch(sys_stor_fixed, res)

# Compare with real-time redispatch
# => This only updates the energy-capacity to the expected state of charge of the storage/genstorage units. Therefore, storage energy levels will be lower, however it can still react to system conditions such as outages.
sys_stor_updated = deepcopy(sys)
sys_stor_updated = SchedNEM.updateMarketRealTimeDispatch(sys_stor_updated, res)

# Compare with StorageMarket Decision Dispatch
# => This only allows storage/genstorage units to charge in the timeintervals that were determined in the optimisation. The energy and discharging capacity remains unchanged.
sys_stor_decision = deepcopy(sys)
sys_stor_decision = SchedNEM.updateStorageMarketDecisionDispatch(sys_stor_decision, res)


#%%
simspecs = SequentialMonteCarlo(samples=1000)
resultspecs = (Shortfall(), );

sf_greedy, = assess(sys, simspecs, resultspecs...)
sf_market_dispatch, = assess(sys_stor_fixed, simspecs, resultspecs...)
sf_rt_market, = assess(sys_stor_updated, simspecs, resultspecs...)

#%%
println("Expected shortfall with greedy storage operation: ", NEUE(sf_greedy))
println("Expected shortfall with market dispatch storage operation: ", NEUE(sf_expectation))
println("Expected shortfall with real-time market storage operation: ", NEUE(sf_rt_market))
println("Expected shortfall with storage market decision dispatch storage operation: ", NEUE(sf_decision))

```