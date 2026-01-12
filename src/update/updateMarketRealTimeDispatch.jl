function updateMarketRealTimeDispatch(sys, res; include_genstorage=true)
    """
    Update storage / genstorage energy capacities with dispatch results.
    However, the charging and discharging still remains flexible for PRAS to use based on the system conditions.

    """
    
    sys.storages.energy_capacity .= res.stor_energy[:,:]
    if include_genstorage
        sys.generatorstorages.energy_capacity .= res.genstor_energy[:,:]
    end
    
    return sys

end