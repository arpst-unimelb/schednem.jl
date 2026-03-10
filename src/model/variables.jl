#%% ========================================================================================================================
function add_variables(model; genData=nothing)

    # Extract system parameters
    Nregions = model[:Nregions]
    Ngens = model[:Ngens]
    Nstors = model[:Nstors]
    Ngenstors = model[:Ngenstors]
    Ndrs = model[:Ndrs]
    Ninterfaces = model[:Ninterfaces]
    N = model[:N]

    # Define decision variables
    @variable(model, p_gen[1:Ngens, 1:N] >= 0)

    if Nstors > 0
        @variable(model, p_stor_charge[1:Nstors, 1:N] >= 0)
        @variable(model, p_stor_discharge[1:Nstors, 1:N] >= 0)
        @variable(model, e_stor[1:Nstors, 1:N] >= 0)
    end

    if Ngenstors > 0
        @variable(model, p_genstor_charge[1:Ngenstors, 1:N] >= 0)
        @variable(model, p_genstor_discharge[1:Ngenstors, 1:N] >= 0)
        @variable(model, e_genstor[1:Ngenstors, 1:N] >= 0)

        # Add slack variable to have genstor target as soft constraint (to avoid infeasibility if target is not achievable)
        @variable(model, genstor_energy_target_slack[1:Ngenstors] >= 0)
        
        # Add genstor spillage variable to allow for excess inflow to be spilled (to avoid infeasibility if inflow exceeds discharge capacity)
        @variable(model, genstor_spillage[1:Ngenstors, 1:N] >= 0)
    end

    if Ndrs > 0
        @variable(model, p_borrow_drs[1:Ndrs, 1:N] >= 0)
        @variable(model, p_payback_drs[1:Ndrs, 1:N] >= 0)
        @variable(model, e_drs[1:Ndrs, 1:N]) 
    end

    @variable(model, p_interface_forward[1:Ninterfaces, 1:N] >= 0)
    @variable(model, p_interface_backward[1:Ninterfaces, 1:N] >= 0)

    @variable(model, load_shedding[1:Nregions, 1:N] >= 0)

    if model[:genOpDetails].uc
        if model[:genOpDetails].binary
             # Generator status variables (binary)
            @variable(model, gon[1:Ngens, t=1:N], Bin) # Generator on/off status variable 
            @variable(model, stup[1:Ngens, t=1:N], Bin) # Start-up indicator variable
            @variable(model, shdw[1:Ngens, t=1:N], Bin) # Shut-down indicator variable
        else
            # Generator status variables (relaxed to continuous between 0 and 1 for now, but can be changed to binary if needed)
            @variable(model, 0.0 <= gon[1:Ngens, t=1:N] <= 1.0) # Generator on/off status variable 
            @variable(model, 0.0 <= stup[1:Ngens, t=1:N] <= 1.0) # Start-up indicator variable
            @variable(model, 0.0 <= shdw[1:Ngens, t=1:N] <= 1.0) # Shut-down indicator variable
        end
    end

    # ====================================================================================================
    # And define all the parameters that will be updated (so the model doesn't need to be rebuilt)
    @variables(model, begin
        dem[1:Nregions, 1:N] in Parameter(0.0)
        gen_cap[1:Ngens, 1:N] in Parameter(0.0)
        interface_limit_forward[1:Ninterfaces, 1:N] in Parameter(0.0)
        interface_limit_backward[1:Ninterfaces, 1:N] in Parameter(0.0)
    end)

    if Nstors > 0
        @variables(model, begin
            stor_charge_cap[1:Nstors, 1:N] in Parameter(0.0)
            stor_discharge_cap[1:Nstors, 1:N] in Parameter(0.0)
            stor_energy_cap[1:Nstors, 1:N] in Parameter(0.0)
            stor_initial_soc[1:Nstors] in Parameter(0.0)
            stor_carryover_eff[1:Nstors, 1:N] in Parameter(1.0)
            stor_charge_eff[1:Nstors, 1:N] in Parameter(1.0)
            stor_discharge_eff_inverse[1:Nstors, 1:N] in Parameter(1.0)
        end)
    end

    if Ngenstors > 0
        @variables(model, begin
            genstor_charge_cap[1:Ngenstors, 1:N] in Parameter(0.0)
            genstor_discharge_cap[1:Ngenstors, 1:N] in Parameter(0.0)
            genstor_energy_cap[1:Ngenstors, 1:N] in Parameter(0.0)
            genstor_inflow[1:Ngenstors, 1:N] in Parameter(0.0)
            genstor_initial_soc[1:Ngenstors] in Parameter(0.0)
            genstor_carryover_eff[1:Ngenstors, 1:N] in Parameter(1.0)
            genstor_charge_eff[1:Ngenstors, 1:N] in Parameter(1.0)
            genstor_discharge_eff_inverse[1:Ngenstors, 1:N] in Parameter(1.0)
            genstor_energy_target[1:Ngenstors] in Parameter(0.0)
        end)
    end

    if Ndrs > 0
        @variables(model, begin
            drs_borrow_cap[1:Ndrs, 1:N] in Parameter(0.0)
            drs_payback_cap[1:Ndrs, 1:N] in Parameter(0.0)
            drs_energy_cap[1:Ndrs, 1:N] in Parameter(0.0)
            drs_energy_interest[1:Ndrs, 1:N] in Parameter(-1.0) # Note that interest is the growth (positive) or shrinkage (negative) of the borrowed energy, i.e. the payback needs to be more than the borrowed energy if interest is positive, and can be less if interest is negative.
        end)
    end

    if model[:genOpDetails].uc
        @variables(model, begin
            gon_initial[1:Ngens] in Parameter(1.0) # Set initial value to on for all generators
            stup_before[1:Ngens, 1:N] in Parameter(0.0) # Initial setup: No start-up before so that shutdown can happen in first time-step if needed
            shdw_before[1:Ngens, 1:N] in Parameter(0.0)
        end)
    end

    if model[:genOpDetails].ramping
        @variables(model, begin
            p_gen_initial[1:Ngens] in Parameter.(genData.pmin[model[:id_gens]])
        end)
    end

    return model
end