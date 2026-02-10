function update_model_parameters(m, sys, start_index, initial_soc_stor=[], initial_soc_genstor=[])

    total_length, _ = get_params(sys)

    if total_length < start_index + m[:N] - 1
        N = total_length - start_index + 1
        @warn "Last optimisation window is shorter ($N) than optimisation_window ($(m[:N])). Remaining values are taken from previous window."
    else
        N = m[:N]
    end

    # Extract system parameters
    Nstors = m[:Nstors]
    Ngenstors = m[:Ngenstors]
    Ndrs = m[:Ndrs]

    # Define the time steps for which parameters will be updated
    t = 1:N
    idxs = start_index .+ t .- 1
    
    # Update the load in all regions
    set_parameter_value.(m[:dem][:,t], sys.regions.load[:, idxs])

    # Update generator capacities
    set_parameter_value.(m[:gen_cap][:,t], sys.generators.capacity[:, idxs])

    # Update line capacities
    set_parameter_value.(m[:interface_limit_forward][:,t], sys.interfaces.limit_forward[:, idxs])
    set_parameter_value.(m[:interface_limit_backward][:,t], sys.interfaces.limit_backward[:, idxs])

    # Update storage parameters
    if Nstors > 0
        set_parameter_value.(m[:stor_charge_cap][:,t], sys.storages.charge_capacity[:, idxs])
        set_parameter_value.(m[:stor_discharge_cap][:,t], sys.storages.discharge_capacity[:, idxs])
        set_parameter_value.(m[:stor_energy_cap][:,t], sys.storages.energy_capacity[:, idxs])

        # Storage efficiencies
        set_parameter_value.(m[:stor_carryover_eff][:,t], sys.storages.carryover_efficiency[:, idxs])
        set_parameter_value.(m[:stor_charge_eff][:,t], sys.storages.charge_efficiency[:, idxs])
        set_parameter_value.(m[:stor_discharge_eff_inverse][:,t], 1.0 ./ sys.storages.discharge_efficiency[:, idxs])

        # Update initial state of charge
        set_parameter_value.(m[:stor_initial_soc][:], initial_soc_stor[:])
    end

    # Update generator-storage parameters
    if Ngenstors > 0
        set_parameter_value.(m[:genstor_charge_cap][:,t], sys.generatorstorages.charge_capacity[:, idxs])
        set_parameter_value.(m[:genstor_discharge_cap][:,t], sys.generatorstorages.discharge_capacity[:, idxs])
        set_parameter_value.(m[:genstor_energy_cap][:,t], sys.generatorstorages.energy_capacity[:, idxs])
        set_parameter_value.(m[:genstor_inflow][:,t], sys.generatorstorages.inflow[:, idxs])

        # Genstor efficiencies
        set_parameter_value.(m[:genstor_carryover_eff][:,t], sys.generatorstorages.carryover_efficiency[:, idxs])
        set_parameter_value.(m[:genstor_charge_eff][:,t], sys.generatorstorages.charge_efficiency[:, idxs])
        set_parameter_value.(m[:genstor_discharge_eff_inverse][:,t], 1.0 ./ sys.generatorstorages.discharge_efficiency[:, idxs])

        # Update initial state of charge
        set_parameter_value.(m[:genstor_initial_soc][:], initial_soc_genstor[:])
    end

    # Update demand response parameters
    if Ndrs > 0
        set_parameter_value.(m[:drs_borrow_cap][:,t], sys.demandresponses.borrow_capacity[:, idxs])
        set_parameter_value.(m[:drs_payback_cap][:,t], sys.demandresponses.payback_capacity[:, idxs])
    end

    return m
end