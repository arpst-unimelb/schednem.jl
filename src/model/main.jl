
include("model_setup.jl")

m = model_setup(sys; N=24, start_index=1) # 24 time steps, starting from index 1
m = add_variables(m, sys)
m = add_constraint_powerBalance(m, sys)
m = add_constraint_techLimits(m, sys)
m = add_constraints_storageConservation(m, sys)