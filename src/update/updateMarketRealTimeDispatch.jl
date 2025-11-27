function updateMarketRealTimeDispatch(sys, res; include_genstorage=true)
    """
    Update storage / genstorage energy capacities with dispatch results.
    However, the charging and discharging still remains flexible for PRAS to use based on the system conditions.

    """
    
    sys.storages.energy_capacity .= hcat(res.stor_energy[:,1],res.stor_energy[:,1:end-1])
    if include_genstorage
        sys.generatorstorages.energy_capacity .= hcat(res.genstor_energy[:,1],res.genstor_energy[:,1:end-1])
    end
    
    return sys

end