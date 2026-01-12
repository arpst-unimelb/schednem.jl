

function add_constraint_powerBalance(m, sys)

    # Extract system parameters
    N = m[:N]

    Nregions = length(sys.regions.names);
    Ninterfaces = length(sys.interfaces.regions_from);

    # Balance constraints
    @constraint(m, # For each region and time step
        powerBalance[r=1:Nregions, t=1:N],
            sum(m[:p_gen][g,t] for g in sys.region_gen_idxs[r]) +
            sum(m[:p_genstor_discharge][gs,t] for gs in sys.region_genstor_idxs[r]) +
            sum(m[:p_interface][l,t] * m[:connection_matrix][l,r] for l in 1:Ninterfaces) +
            sum(m[:p_stor_discharge][s,t] for s in sys.region_stor_idxs[r]) ==
            m[:dem][r,t] - m[:load_shedding][r,t] +
            sum(m[:p_stor_charge][s,t] for s in sys.region_stor_idxs[r]) +
            sum(m[:p_genstor_charge][gs,t] for gs in sys.region_genstor_idxs[r])
    )
    return m
end

#%% ========================================================================================================================
function add_constraint_techLimits(m, sys)

    # Extract system parameters
    N = m[:N]
    Ngens = length(sys.generators.names);
    Ninterfaces = length(sys.interfaces.regions_from);
    Nstors = length(sys.storages.names);
    Ngenstors = length(sys.generatorstorages.names);

    # Generator limits
    @constraint(m, genLimits[g=1:Ngens, t=1:N], m[:p_gen][g,t] <= m[:gen_cap][g,t])

    # Storage limits
    @constraint(m, storChargeLimits[s=1:Nstors, t=1:N], m[:p_stor_charge][s,t] <= m[:stor_charge_cap][s,t])
    @constraint(m, storDischargeLimits[s=1:Nstors, t=1:N], m[:p_stor_discharge][s,t] <= m[:stor_discharge_cap][s,t])
    @constraint(m, storEnergyLimitsUp[s=1:Nstors, t=1:N], m[:e_stor][s,t] <= m[:stor_energy_cap][s,t])

    # Generator-Storage limits
    @constraint(m, genstorChargeLimits[gs=1:Ngenstors, t=1:N], m[:p_genstor_charge][gs,t] <= m[:genstor_charge_cap][gs,t])
    @constraint(m, genstorDischargeLimits[gs=1:Ngenstors, t=1:N], m[:p_genstor_discharge][gs,t] <= m[:genstor_discharge_cap][gs,t])
    @constraint(m, genstorEnergyLimitsUp[gs=1:Ngenstors, t=1:N], m[:e_genstor][gs,t] <= m[:genstor_energy_cap][gs,t])

    # Interface limits
    @constraint(m, interfacesLimitsForward[l=1:Ninterfaces, t=1:N], m[:p_interface][l,t] <= m[:interface_limit_forward][l,t])
    @constraint(m, interfacesLimitsBackward[l=1:Ninterfaces, t=1:N], m[:p_interface][l,t] >= -m[:interface_limit_backward][l,t])

    return m
end

#%% ========================================================================================================================

function add_constraints_storageConservation(m, sys)

    # Extract system parameters
    N = m[:N]
    Nstors = length(sys.storages.names);
    Ngenstors = length(sys.generatorstorages.names);

    #Calculate the average efficiencies over time for storages
    stor_charge_eff = round.(sum(sys.storages.charge_efficiency, dims=2) ./ size(sys.storages.charge_efficiency, 2); digits=4)
    stor_discharge_eff = round.(sum(sys.storages.discharge_efficiency, dims=2) ./ size(sys.storages.discharge_efficiency, 2); digits=4)

    genstor_charge_eff = round.(sum(sys.generatorstorages.charge_efficiency, dims=2) ./ size(sys.generatorstorages.charge_efficiency, 2); digits=4)
    genstor_discharge_eff = round.(sum(sys.generatorstorages.discharge_efficiency, dims=2) ./ size(sys.generatorstorages.discharge_efficiency, 2); digits=4)

    if sum(stor_charge_eff .< maximum(sys.storages.charge_efficiency, dims=2)) > 0.001
        @warn "Storage charge efficiencies seem to vary over time. Using average efficiencies in conservation constraints."
    end
    if sum(stor_discharge_eff .< maximum(sys.storages.discharge_efficiency, dims=2)) > 0.001
        @warn "Storage discharge efficiencies seem to vary over time. Using average efficiencies in conservation constraints."
    end

    if sum(genstor_charge_eff .< maximum(sys.generatorstorages.charge_efficiency, dims=2)) > 0.001
        @warn "Generator-Storage charge efficiencies seem to vary over time. Using average efficiencies in conservation constraints."
    end
    if sum(genstor_discharge_eff .< maximum(sys.generatorstorages.discharge_efficiency, dims=2)) > 0.001
        @warn "Generator-Storage discharge efficiencies seem to vary over time. Using average efficiencies in conservation constraints."
    end

    # Storage conservation constraints
    @constraint(m, storConservationStart[s=1:Nstors],
        m[:e_stor][s,1] == m[:stor_initial_soc][s] + m[:p_stor_charge][s,1] * stor_charge_eff[s] -
         m[:p_stor_discharge][s,1] / stor_discharge_eff[s]
    )
    @constraint(m, storConservation[s=1:Nstors, t=2:N],
        m[:e_stor][s,t] == m[:e_stor][s,t-1] + m[:p_stor_charge][s,t] * stor_charge_eff[s] -
         m[:p_stor_discharge][s,t] / stor_discharge_eff[s]
    )
    # Generator-Storage conservation constraints (use smaller equal here to allow for spillages)
    @constraint(m, genstorConservationStart[gs=1:Ngenstors],
        m[:e_genstor][gs,1] <= m[:genstor_initial_soc][gs] + m[:p_genstor_charge][gs,1] * genstor_charge_eff[gs] -
         m[:p_genstor_discharge][gs,1] / genstor_discharge_eff[gs] + m[:genstor_inflow][gs,1]
    )
    @constraint(m, genstorConservation[gs=1:Ngenstors, t=2:N],
        m[:e_genstor][gs,t] <= m[:e_genstor][gs,t-1] + m[:p_genstor_charge][gs,t] * genstor_charge_eff[gs] -
         m[:p_genstor_discharge][gs,t] / genstor_discharge_eff[gs] + m[:genstor_inflow][gs,t]
    )

    return m
end