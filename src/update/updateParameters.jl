function update_model_parameters(m, sys, start_index, initial_soc_stor=[], initial_soc_genstor=[])

    total_length, _ = get_params(sys)

    if total_length < start_index + m[:N] - 1
        N = total_length - start_index + 1
        @warn "Last optimisation window is shorter ($N) than optimisation_window ($(m[:N])). Remaining values are taken from previous window."
    else
        N = m[:N]
    end

    Nregions = m[:Nregions]
    Ngens = length(sys.generators.names);
    Nstors = length(sys.storages.names);
    Ngenstors = length(sys.generatorstorages.names);
    Ninterfaces = length(sys.interfaces.regions_from);

    t = 1:N
    
    # Update the load in all regions
    set_parameter_value.(m[:dem][:,t], sys.regions.load[:, start_index .+ t .- 1])

    # Update generator capacities
    set_parameter_value.(m[:gen_cap][:,t], sys.generators.capacity[:, start_index .+ t .- 1])

    # Update line capacities
    set_parameter_value.(m[:interface_limit_forward][:,t], sys.interfaces.limit_forward[:, start_index .+ t .- 1])
    set_parameter_value.(m[:interface_limit_backward][:,t], sys.interfaces.limit_backward[:, start_index .+ t .- 1])

    # Update storage and generator-storage capacities
    set_parameter_value.(m[:stor_charge_cap][:,t], sys.storages.charge_capacity[:, start_index .+ t .- 1])
    set_parameter_value.(m[:stor_discharge_cap][:,t], sys.storages.discharge_capacity[:, start_index .+ t .- 1])
    set_parameter_value.(m[:stor_energy_cap][:,t], sys.storages.energy_capacity[:, start_index .+ t .- 1])
    set_parameter_value.(m[:genstor_charge_cap][:,t], sys.generatorstorages.charge_capacity[:, start_index .+ t .- 1])
    set_parameter_value.(m[:genstor_discharge_cap][:,t], sys.generatorstorages.discharge_capacity[:, start_index .+ t .- 1])
    set_parameter_value.(m[:genstor_energy_cap][:,t], sys.generatorstorages.energy_capacity[:, start_index .+ t .- 1])
    set_parameter_value.(m[:genstor_inflow][:,t], sys.generatorstorages.inflow[:, start_index .+ t .- 1])

    # Update initial state of charge
    set_parameter_value.(m[:stor_initial_soc][:], initial_soc_stor[:])
    set_parameter_value.(m[:genstor_initial_soc][:], initial_soc_genstor[:])

    # Update storage efficiencies
    set_parameter_value.(m[:stor_carryover_eff][:,t], sys.storages.carryover_efficiency[:, start_index .+ t .- 1])
    set_parameter_value.(m[:stor_charge_eff][:,t], sys.storages.charge_efficiency[:, start_index .+ t .- 1])
    set_parameter_value.(m[:stor_discharge_eff_inverse][:,t], 1.0 ./ sys.storages.discharge_efficiency[:, start_index .+ t .- 1])
    set_parameter_value.(m[:genstor_carryover_eff][:,t], sys.generatorstorages.carryover_efficiency[:, start_index .+ t .- 1])
    set_parameter_value.(m[:genstor_charge_eff][:,t], sys.generatorstorages.charge_efficiency[:, start_index .+ t .- 1])
    set_parameter_value.(m[:genstor_discharge_eff_inverse][:,t], 1.0 ./ sys.generatorstorages.discharge_efficiency[:, start_index .+ t .- 1])

    return m
end