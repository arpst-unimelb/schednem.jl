
function updateMarketExpectationDispatch(sys, res; include_genstorage=true)
    """
    Dispatch: Adjust load with expected storage / genstorage dispatch. Then set the storage/genstor to fixed mode by adjusting the demand.
    """
    
    for r in 1:length(sys.regions.names)
        # Increase load by charging
        sys.regions.load[r, :] .+= sum(res.stor_charging[sys.region_stor_idxs[r], :], dims=1)[:]
        if include_genstorage
            sys.regions.load[r, :] .+= sum(res.genstor_charging[sys.region_genstor_idxs[r], :], dims=1)[:]
        end
        
        # Decrease load by discharging
        sys.regions.load[r, :] .-= sum(res.stor_discharging[sys.region_stor_idxs[r], :], dims=1)[:]
        if include_genstorage
            sys.regions.load[r, :] .-= sum(res.genstor_discharging[sys.region_genstor_idxs[r], :], dims=1)[:]
        end
    end
    # Disable storage / genstorage 
    sys.storages.discharge_capacity .= 0
    sys.storages.charge_capacity .= 0
    if include_genstorage
        sys.generatorstorages.gridinjection_capacity .= 0
        sys.generatorstorages.discharge_capacity .= 0
    end
    
    return sys
end
