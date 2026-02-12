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
    add_constraints_demandResponse(m)

Adds basic demand response constraints to the model, including:
- Borrow and payback limits
- Conservation constraints:
    1. For each time step: There needs to be at least as much demand borrowed up, as is paid back up to that time step (i.e. no payback before borrowing)
    2. Overall: All the borrowed energy needs to be paid back (accounting for time-varying interest)
# Assumptions: 
1. No payback before borrowing
2. 

"""
function add_constraints_demandResponse(m)

    # Extract system parameters
    N = m[:N]
    Ndrs = m[:Ndrs]

    # These constraints are added as constraints (not bounds)
    
    if Ndrs == 0
        return m # If there are no demand response units, just return the model without adding any constraints
    end

    @info "Demand response constraints currently only include payback interest (i.e. how much more/less energy needs to be paid back). Time constraints not considered."

    # Demand response limits
    MOI.set(m, POI.ConstraintsInterpretation(), POI.ONLY_BOUNDS)
    @constraint(m, drsBorrowLimits[drs=1:Ndrs, t=1:N], m[:p_borrow_drs][drs,t] <= m[:drs_borrow_cap][drs,t])
    @constraint(m, drsPaybackLimits[drs=1:Ndrs, t=1:N], m[:p_payback_drs][drs,t] <= m[:drs_payback_cap][drs,t])

    # Demand response conservation constraints
    MOI.set(m, POI.ConstraintsInterpretation(), POI.ONLY_CONSTRAINTS)
    # For each time step: There needs to be at least as much demand borrowed up, as is paid back up to that time step (i.e. no payback before borrowing)
    @constraint(m, drsConservationFirstReduce[drs=1:Ndrs, T=1:N-1],
        sum(m[:p_borrow_drs][drs,t] * (m[:drs_energy_interest][drs,t] + 1.0) for t=1:T) >= sum(m[:p_payback_drs][drs,t] for t=1:T)
    )
    # Overall: All the borrowed energy needs to be paid back (accounting for time-varying interest)
    @constraint(m, drsConservationWholeTime[drs=1:Ndrs],
        sum(m[:p_borrow_drs][drs,t] * (m[:drs_energy_interest][drs,t] + 1.0) for t=1:N) <= sum(m[:p_payback_drs][drs,t] for t=1:N)
    )

    return m
end

"""
    add_constraints_demandResponse_maxEnergy(m; max_energy_per_24h=24)

"""
function add_constraints_demandResponse_maxEnergy(m)

    Ndrs = m[:Ndrs]
    N = m[:N]

    if (Ndrs > 0) && !isempty(m[:drs_limitsOnPriceBands])

        maxEnergy = m[:drs_maxEnergyPerWindowFactor]
        
        window = m[:drs_borrowEnergyTimeWindow]
        if window > N
            window = N
        end

        relevant_price_bands = m[:drs_limitsOnPriceBands]
        if 0 in relevant_price_bands
            relevant_price_bands = vcat(relevant_price_bands, m[:VoLL_min])
        end

        # Find the 
        MOI.set(m, POI.ConstraintsInterpretation(), POI.ONLY_CONSTRAINTS)
        for i in 1:Ndrs
            # Get the price for this demand response unit
            price = coefficient(m[:operating_cost_drs], m[:p_borrow_drs][i,1])
            if !iszero(price) && (price in relevant_price_bands)
                @info "Adding max energy constraints for demand response unit $i with price band $price."
                for T in window:window:N
                    @constraint(m, drsMaxEnergy[drs=i], sum(m[:p_borrow_drs][i,t] for t=T-window+1:T) <= maxEnergy * m[:drs_borrow_cap][i,1])
                end
            end
        end
    else
        @warn "No demand response units in the system or no price bands specified, so max energy constraints not added."
    end

    return m
end


#%% ========================================================================================================================
"""
    add_constraints_EnergyFixed(m, index, storage_energy_level, genstor_energy_level)

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

    # Remove the storage energy fixed constraints
    if !isnothing(constraint_by_name(m, "storEnergyFixed"))
        delete(m, :storEnergyFixed)
    end
    if !isnothing(constraint_by_name(m, "genstorEnergyFixed"))
        delete(m, :genstorEnergyFixed)
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

    m = remove_constraints_EnergyFixed(m) # Remove existing constraints if they exist

    # Extract system parameters
    N = m[:N]
    Nstors = m[:Nstors]
    Ngenstors = m[:Ngenstors]

    # These constraints are added as constraints (not bounds)
    MOI.set(m, POI.ConstraintsInterpretation(), POI.ONLY_CONSTRAINTS)

    # Storage energy level fixed constraints
    @constraint(m, storEnergyFixed[s=1:Nstors], m[:e_stor][s,index] >= storage_energy_level[s] - tolerance)
    @constraint(m, genstorEnergyFixed[gs=1:Ngenstors], m[:e_genstor][gs,index] >= genstor_energy_level[gs] - tolerance)

    return m
end