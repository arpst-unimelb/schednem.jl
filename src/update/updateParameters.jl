function update_model_parameters(m, sys, start_index, initial_soc_stor=[], initial_soc_genstor=[]; end_index::Int=0)

    total_length, _ = get_params(sys)

    if total_length < start_index + m[:N] - 1
        end_index = total_length
        @warn "Last optimisation window is shorter ($N) than optimisation_window ($(m[:N]))."
    end

    # If end_index is not provided or is zero, use the full window length
    if end_index > 0
        if start_index > end_index
            error("Error: start_index should be less than end_index when updating system parameters.")
        end
        # Define the time steps for which parameters will be updated
        t = 1:(end_index - start_index + 1)
        idxs = start_index .+ t .- 1
        # Define the remaining time steps, where the parameters will be set to zero
        remaining_t = (end_index - start_index + 2):(m[:N])
    else
        t = 1:m[:N]
        idxs = start_index .+ t .- 1
        # Empty range for remaining time steps, as we are using the full window
        remaining_t = 1:0
    end

    # Extract system parameters
    Nstors = m[:Nstors]
    Ngenstors = m[:Ngenstors]
    Ndrs = m[:Ndrs]
    
    # Update the load in all regions
    set_parameter_value.(m[:dem][:,t], sys.regions.load[:, idxs])
    # If the end_index is less than the full window length, set the remaining load to zero to not have any additional unserved energy
    if end_index < start_index + m[:N] - 1
        set_parameter_value.(m[:dem][:,remaining_t], fill(0.0, size(m[:dem][:,remaining_t])))
    end

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

        # Set all the remaining times the charge/discharge capacity to zero
        set_parameter_value.(m[:stor_charge_cap][:,remaining_t], fill(0.0, size(m[:stor_charge_cap][:,remaining_t])))
        set_parameter_value.(m[:stor_discharge_cap][:,remaining_t], fill(0.0, size(m[:stor_discharge_cap][:,remaining_t])))
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

        # Set all the remaining times the charge/discharge capacity to zero
        set_parameter_value.(m[:genstor_charge_cap][:,remaining_t], fill(0.0, size(m[:genstor_charge_cap][:,remaining_t])))
        set_parameter_value.(m[:genstor_discharge_cap][:,remaining_t], fill(0.0, size(m[:genstor_discharge_cap][:,remaining_t])))
    end

    # Update demand response parameters
    if Ndrs > 0
        set_parameter_value.(m[:drs_borrow_cap][:,t], sys.demandresponses.borrow_capacity[:, idxs])
        set_parameter_value.(m[:drs_payback_cap][:,t], sys.demandresponses.payback_capacity[:, idxs])
        set_parameter_value.(m[:drs_energy_interest][:,t], sys.demandresponses.borrowed_energy_interest[:, idxs])

        # Set all the remaining times the demand response parameters to zero
        set_parameter_value.(m[:drs_borrow_cap][:,remaining_t], fill(0.0, size(m[:drs_borrow_cap][:,remaining_t])))
        set_parameter_value.(m[:drs_payback_cap][:,remaining_t], fill(0.0, size(m[:drs_payback_cap][:,remaining_t])))
        set_parameter_value.(m[:drs_energy_interest][:,remaining_t], fill(-1.0, size(m[:drs_energy_interest][:,remaining_t])))
    end

    return m
end