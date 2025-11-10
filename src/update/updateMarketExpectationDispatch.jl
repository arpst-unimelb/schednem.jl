
function updateMarketExpectationDispatch(sys, res)
    """
    Dispatch: Adjust load with expected storage / genstorage dispatch. Then set the storage/genstor to fixed mode (no discharge).
    """
    
    for r in 1:length(sys.regions.names)
        # Increase load by charging
        sys.regions.load[r, :] .+= sum(res.stor_charging[sys.region_stor_idxs[r], :], dims=1)[:]
        sys.regions.load[r, :] .+= sum(res.genstor_charging[sys.region_genstor_idxs[r], :], dims=1)[:]
        
        # Decrease load by discharging
        sys.regions.load[r, :] .-= sum(res.stor_discharging[sys.region_stor_idxs[r], :], dims=1)[:]
        sys.regions.load[r, :] .-= sum(res.genstor_discharging[sys.region_genstor_idxs[r], :], dims=1)[:]
    end
    # Disable storage / genstorage 
    sys.storages.discharge_capacity .= 0
    sys.storages.charge_capacity .= 0
    sys.generatorstorages.gridinjection_capacity .= 0
    sys.generatorstorages.discharge_capacity .= 0
    
    return sys

end



