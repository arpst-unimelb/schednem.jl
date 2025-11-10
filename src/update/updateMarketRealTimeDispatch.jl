function updateMarketRealTimeDispatch(sys, res)
    """
    Update storage / genstorage energy capacities with dispatch results.
    However, the charging and discharging still remains flexible for PRAS to use based on the system conditions.

    """
    
    sys.storages.energy_capacity .= res.stor_energy
    sys.generatorstorages.energy_capacity .= res.genstor_energy
    
    return sys

end