

function add_constraint_powerBalance(m, sys)

    # Extract system parameters
    N = m[:N]

    Nregions = length(sys.regions.names);
    Nlines = length(sys.lines.names);

    # Balance constraints
    @constraint(m, # For each region and time step
        powerBalance[r=1:Nregions, t=1:N],
            sum(m[:p_gen][g,t] for g in sys.region_gen_idxs[r]) +
            sum(m[:p_genstor_discharge][gs,t] for gs in sys.region_genstor_idxs[r]) +
            sum(m[:p_line][l,t] * m[:line_connection_matrix][l,r] for l in 1:Nlines) +
            sum(m[:p_stor_discharge][s,t] for s in sys.region_stor_idxs[r]) ==
            sys.regions.load[r,t] - m[:load_shedding][r,t] +
            sum(m[:p_stor_charge][s,t] for s in sys.region_stor_idxs[r]) +
            sum(m[:p_genstor_charge][gs,t] for gs in sys.region_genstor_idxs[r])
    )

    return m
end

#%% ========================================================================================================================
function add_constraint_techLimits(m, sys)

    # Extract system parameters
    N = m[:N]
    start_idx = m[:start_index]
    t_idxs = start_idx:(start_idx + N - 1)
    Ngens = length(sys.generators.names);

    # Generator limits
    @constraint(m, genLimits[g=1:Ngens, t=1:N], m[:p_gen][g,t] <= sys.generators.capacity[g,t_idxs[t]])

    # Storage limits
    @constraint(m, storChargeLimits[s=1:length(sys.storages.names), t=1:N], m[:p_stor_charge][s,t] <= sys.storages.charge_capacity[s,t_idxs[t]])
    @constraint(m, storDischargeLimits[s=1:length(sys.storages.names), t=1:N], m[:p_stor_discharge][s,t] <= sys.storages.discharge_capacity[s,t_idxs[t]])
    @constraint(m, storEnergyLimits[s=1:length(sys.storages.names), t=1:N], m[:e_stor][s,t] <= sys.storages.energy_capacity[s,t_idxs[t]])

    # Generator-Storage limits
    @constraint(m, genstorChargeLimits[gs=1:length(sys.generatorstorages.names), t=1:N], m[:p_genstor_charge][gs,t] <= sys.generatorstorages.gridwithdrawal_capacity[gs,t_idxs[t]])
    @constraint(m, genstorDischargeLimits[gs=1:length(sys.generatorstorages.names), t=1:N], m[:p_genstor_discharge][gs,t] <= sys.generatorstorages.gridinjection_capacity[gs,t_idxs[t]])

    # Line limits
    @constraint(m, lineLimitsForward[l=1:length(sys.lines.names), t=1:N], m[:p_line][l,t] <= sys.lines.forward_capacity[l,t_idxs[t]])
    @constraint(m, lineLimitsBackward[l=1:length(sys.lines.names), t=1:N], m[:p_line][l,t] >= -sys.lines.backward_capacity[l,t_idxs[t]])

    return m
end

#%% ========================================================================================================================

function add_constraints_storageConservation(m, sys)

    # Extract system parameters
    N = m[:N]
    start_idx = m[:start_index]
    t_idxs = start_idx:(start_idx + N - 1)
    Nstors = length(sys.storages.names);
    Ngenstors = length(sys.generatorstorages.names);

    # Storage conservation constraints
    @constraint(m, storConservation[s=1:Nstors, t=2:N],
        m[:e_stor][s,t] == m[:e_stor][s,t-1] + m[:p_stor_charge][s,t-1] * sys.storages.charge_efficiency[s,t_idxs[t]-1] -
         m[:p_stor_discharge][s,t-1] / sys.storages.discharge_efficiency[s,t_idxs[t]-1]
    )
    # Generator-Storage conservation constraints (use smaller equal here to allow for spillages)
    @constraint(m, genstorConservation[gs=1:Ngenstors, t=2:N],
        m[:e_genstor][gs,t] <= m[:e_genstor][gs,t-1] +
        m[:p_genstor_charge][gs,t-1] * sys.generatorstorages.charge_efficiency[gs,t_idxs[t]-1] -
         m[:p_genstor_discharge][gs,t-1] / sys.generatorstorages.discharge_efficiency[gs,t_idxs[t]-1] + sys.generatorstorages.inflow[gs,t_idxs[t]-1]
    )

    return m
end