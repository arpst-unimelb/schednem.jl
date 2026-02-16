"""
    add_constraint_powerBalance(m, sys)

Note: The PRAS system is needed as input to assign the units to the appropriate regions (for generation, storage, and interfaces).

"""
function add_constraint_powerBalance(m, sys)

    # Extract system parameters
    N = m[:N]
    Nregions = m[:Nregions]
    Ninterfaces = m[:Ninterfaces]
    
    # These constraints are added as constraints (not bounds)
    MOI.set(m, POI.ConstraintsInterpretation(), POI.ONLY_CONSTRAINTS)

    # Balance constraints (add init=zero(1) to the sums to avoid errors when there are no units of a certain type in a region)
    @constraint(m, # For each region and time step
        powerBalance[r=1:Nregions, t=1:N],
            sum(m[:p_gen][g,t] for g in sys.region_gen_idxs[r]) +
            sum(m[:p_genstor_discharge][gs,t] for gs in sys.region_genstor_idxs[r]; init = zero(1)) +
            sum(m[:p_stor_discharge][s,t] for s in sys.region_stor_idxs[r]; init = zero(1)) +
            sum(m[:p_borrow_drs][drs,t] for drs in sys.region_dr_idxs[r] if (m[:Ndrs] > 0); init = zero(1)) +
            sum((m[:p_interface_forward][l,t] - m[:p_interface_backward][l,t]) * m[:connection_matrix][l,r] for l in 1:Ninterfaces) ==
            m[:dem][r,t] - m[:load_shedding][r,t] +
            sum(m[:p_payback_drs][drs,t] for drs in sys.region_dr_idxs[r] if (m[:Ndrs] > 0); init = zero(1)) +
            sum(m[:p_stor_charge][s,t] for s in sys.region_stor_idxs[r]; init = zero(1)) +
            sum(m[:p_genstor_charge][gs,t] for gs in sys.region_genstor_idxs[r]; init = zero(1))
    )
    return m
end

#%% ========================================================================================================================
function add_constraint_techLimits(m)

    # Extract system parameters
    N = m[:N]
    Ngens = m[:Ngens]
    Ninterfaces = m[:Ninterfaces]
    Nstors = m[:Nstors]
    Ngenstors = m[:Ngenstors]

    # These constraints are added as constraints (not bounds)
    MOI.set(m, POI.ConstraintsInterpretation(), POI.ONLY_BOUNDS)

    # Generator limits
    @constraint(m, genLimits[g=1:Ngens, t=1:N], m[:p_gen][g,t] <= m[:gen_cap][g,t])

    if Nstors > 0
        # Storage limits
        @constraint(m, storChargeLimits[s=1:Nstors, t=1:N], m[:p_stor_charge][s,t] <= m[:stor_charge_cap][s,t])
        @constraint(m, storDischargeLimits[s=1:Nstors, t=1:N], m[:p_stor_discharge][s,t] <= m[:stor_discharge_cap][s,t])
        @constraint(m, storEnergyLimitsUp[s=1:Nstors, t=1:N], m[:e_stor][s,t] <= m[:stor_energy_cap][s,t])
    end

    if Ngenstors > 0
        # Generator-Storage limits
        @constraint(m, genstorChargeLimits[gs=1:Ngenstors, t=1:N], m[:p_genstor_charge][gs,t] <= m[:genstor_charge_cap][gs,t])
        @constraint(m, genstorDischargeLimits[gs=1:Ngenstors, t=1:N], m[:p_genstor_discharge][gs,t] <= m[:genstor_discharge_cap][gs,t])
        @constraint(m, genstorEnergyLimitsUp[gs=1:Ngenstors, t=1:N], m[:e_genstor][gs,t] <= m[:genstor_energy_cap][gs,t])
    end

    # Interface limits
    @constraint(m, interfacesLimitsForward[l=1:Ninterfaces, t=1:N], m[:p_interface_forward][l,t] <= m[:interface_limit_forward][l,t])
    @constraint(m, interfacesLimitsBackward[l=1:Ninterfaces, t=1:N], m[:p_interface_backward][l,t] <= m[:interface_limit_backward][l,t])

    return m
end

#%% ========================================================================================================================

function add_constraints_storageConservation(m)

    # Extract system parameters
    N = m[:N]
    Nstors = m[:Nstors]
    Ngenstors = m[:Ngenstors]

    # These constraints are added as constraints (not bounds)
    MOI.set(m, POI.ConstraintsInterpretation(), POI.ONLY_CONSTRAINTS)
    if Nstors > 0
        # Storage conservation constraints
        @constraint(m, storConservationStart[s=1:Nstors],
            m[:e_stor][s,1] == m[:stor_initial_soc][s] * m[:stor_carryover_eff][s,1] + m[:p_stor_charge][s,1] * m[:stor_charge_eff][s,1] -
             m[:p_stor_discharge][s,1] * m[:stor_discharge_eff_inverse][s,1]
        )
        @constraint(m, storConservation[s=1:Nstors, t=2:N],
            m[:e_stor][s,t] == m[:e_stor][s,t-1] * m[:stor_carryover_eff][s,t] + m[:p_stor_charge][s,t] * m[:stor_charge_eff][s,t] -
             m[:p_stor_discharge][s,t] * m[:stor_discharge_eff_inverse][s,t]
        )
    end
    
    if Ngenstors > 0
        # Generator-Storage conservation constraints (use inequality here to allow for spillages!)
        @constraint(m, genstorConservationStart[gs=1:Ngenstors],
            m[:e_genstor][gs,1] <= m[:genstor_initial_soc][gs] * m[:genstor_carryover_eff][gs,1] + m[:p_genstor_charge][gs,1] * m[:genstor_charge_eff][gs,1] -
            m[:p_genstor_discharge][gs,1] * m[:genstor_discharge_eff_inverse][gs,1] + m[:genstor_inflow][gs,1]
        )
        @constraint(m, genstorConservation[gs=1:Ngenstors, t=2:N],
            m[:e_genstor][gs,t] <= m[:e_genstor][gs,t-1] * m[:genstor_carryover_eff][gs,t] + m[:p_genstor_charge][gs,t] * m[:genstor_charge_eff][gs,t] -
            m[:p_genstor_discharge][gs,t] * m[:genstor_discharge_eff_inverse][gs,t] + m[:genstor_inflow][gs,t]
        )
    end

    return m
end

#%% ========================================================================================================================
"""
    add_constraints_demandResponse(m, DER_params)

Adds basic demand response constraints to the model, including:
- Borrow and payback limits
- Conservation constraints:
    1. For each time step: There needs to be at least as much demand borrowed up, as is paid back up to that time step (i.e. no payback before borrowing)
    2. Overall: All the borrowed energy needs to be paid back (accounting for time-varying interest)
# Assumptions: 
1. No payback before borrowing
2. 

"""
function add_constraints_demandResponse(m, DER_params)

    # Extract system parameters
    N = m[:N]
    Ndrs = m[:Ndrs]
    drs_idxs_DSP = m[:drs_idxs_DSP]
    drs_idxs_EV = m[:drs_idxs_EV]

    # These constraints are added as constraints (not bounds)
    
    if Ndrs == 0
        return m # If there are no demand response units, just return the model without adding any constraints
    end

    # Demand response capacity limits
    MOI.set(m, POI.ConstraintsInterpretation(), POI.ONLY_BOUNDS)
    @constraint(m, drsBorrowLimits[drs=1:Ndrs, t=1:N], m[:p_borrow_drs][drs,t] <= m[:drs_borrow_cap][drs,t])
    @constraint(m, drsPaybackLimits[drs=1:Ndrs, t=1:N], m[:p_payback_drs][drs,t] <= m[:drs_payback_cap][drs,t])

    # Add limit if payback before borrowing is not allowed
    if !DER_params["DSP_payback_before_borrowing"]
        @constraint(m, drsPaybackBeforeBorrowingDSP[drs=drs_idxs_DSP, t=1:N], m[:e_drs][drs,t] >= 0.0)
    end
    if !DER_params["EV_payback_before_borrowing"]
        @constraint(m, drsPaybackBeforeBorrowingEV[drs=drs_idxs_EV, t=1:N], m[:e_drs][drs,t] >= 0.0)
    end

    # Demand response conservation constraints
    MOI.set(m, POI.ConstraintsInterpretation(), POI.ONLY_CONSTRAINTS)
    @constraint(m, drsConservationStart[drs=1:Ndrs],
        m[:e_drs][drs,1] == m[:p_borrow_drs][drs,1] * (1.0 + m[:drs_energy_interest][drs,1]) - m[:p_payback_drs][drs,1]
    )
    @constraint(m, drsConservation[drs=1:Ndrs, t=2:N],
        m[:e_drs][drs,t] == m[:e_drs][drs,t-1] + m[:p_borrow_drs][drs,t] * (1.0 + m[:drs_energy_interest][drs,t]) - m[:p_payback_drs][drs,t]
    )

    # Finally, add a constraint to ensure that all borrowed energy is paid back by the end of the time horizon (accounting for interest)
    @constraint(m, drsPaybackComplete[drs=1:Ndrs], m[:e_drs][drs,N] == 0)

    return m
end

"""
    add_constraints_demandResponse_paybackTime(m, DER_params)

"""
function add_constraints_demandResponse_paybackTime(m, DER_params)

    # Extract system parameters
    N = m[:N]

    # First for DSP
    if DER_params["DSP_flexibility"] && (DER_params["DSP_payback_window"] > 0) && (DER_params["DSP_payback_window"] < N) && (DER_params["DSP_interest"] > -1.0)
        drs_idxs_DSP = m[:drs_idxs_DSP]
        window = DER_params["DSP_payback_window"]
        @info "Adding demand response payback time constraints for DSP units with payback window of $(window) hours."
        MOI.set(m, POI.ConstraintsInterpretation(), POI.ONLY_CONSTRAINTS)
        @constraint(m, drsPaybackTimeDSP[drs=drs_idxs_DSP, t=window:N], sum(m[:p_payback_drs][drs,tau] for tau=t-window+1:t) >= m[:p_borrow_drs][drs,t-window+1] * (1.0 + m[:drs_energy_interest][drs,t-window+1]))
    end

    if DER_params["EV_charge_flexibility"] && (DER_params["EV_payback_window"] > 0) && (DER_params["EV_payback_window"] < N) && (DER_params["EV_interest"] > -1.0)
        drs_idxs_EV = m[:drs_idxs_EV]
        window = DER_params["EV_payback_window"]
        @info "Adding demand response payback time constraints for EV units with payback window of $(window) hours."
        MOI.set(m, POI.ConstraintsInterpretation(), POI.ONLY_CONSTRAINTS)
        @constraint(m, drsPaybackTimeEV[drs=drs_idxs_EV, t=window:N], sum(m[:p_payback_drs][drs,tau] for tau=t-window+1:t) >= m[:p_borrow_drs][drs,t-window+1] * (1.0 + m[:drs_energy_interest][drs,t-window+1]))
    end

    return m
end


"""
    add_constraints_demandResponse_maxEnergy(m, DER_params)


- Limiting the energy that can be borrowed over a certain time window (e.g. 24 hours) to be no more than a certain factor of the total borrowing capacity in that window. 
- This is to reflect AEMO practices to limit the energy per day that can be borrowed through DSP.

"""
function add_constraints_demandResponse_maxEnergy(m, DER_params)

    Ndrs = m[:Ndrs]
    N = m[:N]

    if (Ndrs > 0)

        idxs_DSP = m[:drs_idxs_DSP]
        idxs_EV = m[:drs_idxs_EV]

        if !isempty(idxs_DSP) && DER_params["DSP_limit_energy_per_window"]["enabled"]
            maxEnergyFac = DER_params["DSP_limit_energy_per_window"]["max_energy_per_window_per_capacity"]
            window = DER_params["DSP_limit_energy_per_window"]["max_energy_time_window"]
            if window > N
                window = N
            end

            relevant_price_bands = DER_params["DSP_limit_energy_per_window"]["limits_on_price_bands"]
            if 0 in relevant_price_bands
                relevant_price_bands = vcat(relevant_price_bands, m[:VoLL_min])
            end

            # Find the list of relevant demand response units that should be added
            idxs_DSP_drs = []
            prices_drs = []
            for i in idxs_DSP
                # Get the price for this demand response unit
                price = coefficient(m[:operating_cost_drs], m[:p_borrow_drs][i,1])
                if !iszero(price) && (price in relevant_price_bands)
                    push!(idxs_DSP_drs, i)
                    push!(prices_drs, price)
                end
            end

            @info "Adding max energy constraints for DSP units $idxs_DSP_drs with price bands $prices_drs."
            MOI.set(m, POI.ConstraintsInterpretation(), POI.ONLY_CONSTRAINTS)
            @constraint(m, drsMaxEnergyDSP[i=idxs_DSP_drs, T=collect(window:window:N)], sum(m[:p_borrow_drs][i,t] for t=T-window+1:T)  <= maxEnergyFac / window * sum(m[:drs_borrow_cap][i,t] for t=T-window+1:T))
        end

        if !isempty(idxs_EV) && DER_params["EV_limit_energy_per_window"]["enabled"]
            maxEnergyFac = DER_params["EV_limit_energy_per_window"]["max_energy_per_window_per_capacity"]
            window = DER_params["EV_limit_energy_per_window"]["max_energy_time_window"]
            if window > N
                window = N
            end

            @info "Adding max energy constraints for EV units $idxs_EV."
            MOI.set(m, POI.ConstraintsInterpretation(), POI.ONLY_CONSTRAINTS)
            @constraint(m, drsMaxEnergyEV[i=idxs_EV, T=collect(window:window:N)], sum(m[:p_borrow_drs][i,t] for t=T-window+1:T) <= maxEnergyFac / window * sum(m[:drs_borrow_cap][i,t] for t=T-window+1:T))
        end

    else
        @warn "No demand response units in the system or no price bands specified, so max energy constraints not added."
    end

    return m
end


#%% ========================================================================================================================
"""
    add_constraints_genstorEnergyTarget(m, index, storage_energy_level, genstor_energy_level)

"""
function add_constraints_genstorEnergyTarget(m)

    # Extract system parameters
    N = m[:N]
    Ngenstors = m[:Ngenstors]

    # These constraints are added as constraints (not bounds)
    MOI.set(m, POI.ConstraintsInterpretation(), POI.ONLY_CONSTRAINTS)

    # Generator-Storage energy target constraint (use inequality here to allow for infeasibility and penalize with slack variable)
    @constraint(m, genstorEnergyTarget[gs=1:Ngenstors],
        m[:e_genstor][gs,N] >= m[:genstor_energy_target][gs] - m[:genstor_energy_target_slack][gs]
    )

    return m
end


#%% ========================================================================================================================
"""
    remove_constraints_EnergyFixed(m)

Removes the constraints that fix storage energy levels at a certain time step.
"""
function remove_constraints_EnergyFixed(m)

    # Extract system parameters
    Nstors = m[:Nstors]
    Ngenstors = m[:Ngenstors]

    # These constraints are added as bounds
    MOI.set(m, POI.ConstraintsInterpretation(), POI.BOUNDS_AND_CONSTRAINTS)

    if Nstors > 0
        set_lower_bound.(m[:e_stor], 0.0)
        set_lower_bound.(m[:e_stor][:,index], 0.0)
    end
    for gs in 1:Ngenstors
        set_lower_bound.(m[:e_genstor][gs,:], 0.0)
    end

    return m
end


"""
    add_constraints_EnergyFixed(m, index, storage_energy_level, genstor_energy_level)

# Inputs
- `m`: The optimization model to which the constraints will be added.
- `index`: The time step index after which the storage energy levels are to be fixed. (energy is always at the end of the time step)
- `storage_energy_level`: A vector of length Nstors specifying the fixed energy level for each storage after the specified time step index.
- `genstor_energy_level`: A vector of length Ngenstors specifying the fixed energy level for each generator-storage after the specified time step index.
- `tolerance`: A non-negative scalar specifying the tolerance for fixing the energy levels. The constraints will ensure that the energy levels are greater than or equal to the specified levels minus this tolerance.

# Description




"""
function add_constraints_EnergyFixed(m, index, storage_energy_level, genstor_energy_level; tolerance=0.0)

    # Extract system parameters
    Nstors = m[:Nstors]
    Ngenstors = m[:Ngenstors]

    # These constraints are added as bounds
    MOI.set(m, POI.ConstraintsInterpretation(), POI.ONLY_BOUNDS)

    # Storage energy level fixed constraints
    if Nstors > 0
        set_lower_bound.(m[:e_stor], 0.0) # First set all the lower bounds to zero to avoid errors when adding the constraints
        set_lower_bound.(m[:e_stor][:,index], storage_energy_level[:] .- tolerance)
    end
    for gs in 1:Ngenstors
        set_lower_bound.(m[:e_genstor][gs,:], 0.0) # First set all the lower bounds to zero to avoid errors when adding the constraints
        set_lower_bound(m[:e_genstor][gs,index], genstor_energy_level[gs] - tolerance)
    end

    return m
end


#%% ========================================================================================================================
"""
    add_constraints_disableVPP(m, sys)

If VPP should not be flexible, this function is fixing its state of charge to zero for all time steps.
This is added as a constraint to still allow for updateParameters to run smoothly.

"""
function add_constraints_disableVPP(m, sys)

    # Extract system parameters
    N = m[:N]
    Nstors = m[:Nstors]
    idxs_vpp = findall(x -> x == "VPP", sys.storages.categories)

    if !isempty(idxs_vpp)

        # These constraints are added as bounds
        MOI.set(m, POI.ConstraintsInterpretation(), POI.ONLY_BOUNDS)
        fix(m[:e_stor][idxs_vpp,:], 0.0)
    end

    return m
end
