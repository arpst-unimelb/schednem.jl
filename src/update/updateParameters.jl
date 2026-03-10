"""


Ramping: If ramping is activated and p_gen_initial is empty, set p_gen_initial to 0.5 * the max capacity for all generators.


"""
function update_model_parameters!(m, sys, start_index, initial_soc_stor=[], initial_soc_genstor=[]; end_index::Int=0, 
    gon_initial=[], stup_before=[], shdw_before=[], p_gen_initial=[])

    total_length, _ = PRAS.get_params(sys)

    if total_length < start_index + m[:N] - 1
        end_index = total_length
        N = end_index - start_index + 1
        @warn "Last optimisation window is shorter ($N) than optimisation_window ($(m[:N]))."
    else
        N = m[:N]
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
        t = 1:N
        idxs = start_index .+ t .- 1
        # Empty range for remaining time steps, as we are using the full window
        remaining_t = 1:0
    end

    # Some parameters should always be updated for the full window length, to avoid infeasibility.
    t_full = 1:N
    idxs_full = start_index .+ t_full .- 1

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
        set_parameter_value.(m[:stor_energy_cap][:,t_full], sys.storages.energy_capacity[:, idxs_full])

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
        set_parameter_value.(m[:genstor_energy_cap][:,t_full], sys.generatorstorages.energy_capacity[:, idxs_full])
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

    # Update initial generator on/off status if unit commitment is enabled
    if m[:genOpDetails].uc
        if !isempty(gon_initial)
            set_parameter_value.(m[:gon_initial][:], gon_initial[:])
        else
            #@warn "Initial generator on/off status not provided. Setting all generators to on at the first time step."
            set_parameter_value.(m[:gon_initial][:], fill(1.0, size(m[:gon_initial][:])))
        end
        if !isempty(stup_before)
            set_parameter_value.(m[:stup_before][:,:], stup_before[:,:])
        else
            #@warn "Start-up indicator values not provided. Setting all to zero at the first time step."
            set_parameter_value.(m[:stup_before][:,:], fill(0.0, size(m[:stup_before][:,:])))
        end
        if !isempty(shdw_before)
            set_parameter_value.(m[:shdw_before][:,:], shdw_before[:,:])
        else
            #@warn "Shut-down indicator values not provided. Setting all to zero at the first time step."
            set_parameter_value.(m[:shdw_before][:,:], fill(0.0, size(m[:shdw_before][:,:])))
        end
    end

    if m[:genOpDetails].ramping
        # If ramping is activated, also update the ramping limits based on the new generator capacities and the previous time step's generation
        if !isempty(p_gen_initial)
            set_parameter_value.(m[:p_gen_initial][:], p_gen_initial[:])
        else
            #@warn "Initial generation values not provided for ramping. Setting all to half the capacity before first time step."
            set_parameter_value.(m[:p_gen_initial][:], sys.generators.capacity[:, max(idxs[1]-1, 1)] * 0.5) # Set initial generation to 50% of capacity as a default
        end
    end

    return m
end