function updateMarketRealTimeDispatch(sys, res; include_genstorage=true)
    """
    Update storage / genstorage energy capacities with dispatch results.
    However, the charging and discharging still remains flexible for PRAS to use based on the system conditions.

    """
    
    # Get the total number of time steps
    N = length(res.stor_energy[1,:])

    # Use a threshold to determine if storage is charging/discharging/idling (is irrelevant for integer results, but just to be safe)
    threshold = 0.01

    # Now update storage energy capacity for each time step
    for t in 1:1:N
        
        # If storage is charging or idling:
        # Energy capacity at each step must be the same as from the simulation 
        # (=> The energy in PRAS is the energy after the step, but applied at the beginning)
        sys.storages.energy_capacity[:,t] .= res.stor_energy[:,t]

        # When discharging: Energy capacity should be taken from the previous (!) timestep - so that the energy is still available for discharge in PRAS in this timestep
        idxs_discharging = findall(res.stor_discharging[:,t] .> threshold)
        if !isempty(idxs_discharging)
            if t == 1
                @warn "Storage discharging in first timestep, using initial energy capacity. - Not implemented properly yet."
                sys.storages.energy_capacity[idxs_discharging,t] .= res.stor_energy_initial[idxs_discharging]
            else
                sys.storages.energy_capacity[idxs_discharging,t] .= res.stor_energy[idxs_discharging,t-1]
            end
        end

        # Now do the same for generator-storages
        if include_genstorage

            # Update energy capacity for genstor when charging or idling
            sys.generatorstorages.energy_capacity[:,t] .= res.genstor_energy[:,t]

            # Check if genstorage is discharging, then use the previous timestep energy capacity
            idxs_discharging = findall(res.genstor_discharging[:,t] .> threshold)
            if !isempty(idxs_discharging)
                if t == 1
                    @warn "Generator-Storage discharging in first timestep, using initial energy capacity. - Not implemented properly yet."
                    sys.generatorstorages.energy_capacity[idxs_discharging,t] .= res.genstor_energy_initial[idxs_discharging]
                else
                    sys.generatorstorages.energy_capacity[idxs_discharging,t] .= res.genstor_energy[idxs_discharging,t-1]
                end
            end
            
        end

    end

    
    return sys

end