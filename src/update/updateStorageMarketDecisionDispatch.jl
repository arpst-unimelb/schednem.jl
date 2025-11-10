function updateStorageMarketDecisionDispatch(sys, res)
    """
    Dispatch: Charging is only limited to the times when storage is expected to charge.
    """

    sys.storages.charge_capacity[findall(x -> x == 0, res.stor_charging)] .= 0
    sys.generatorstorages.gridwithdrawal_capacity[findall(x -> x == 0, res.genstor_charging)] .= 0
    
    #sys.storages.charge_capacity[findall(x -> x > 0, res.stor_discharging)] .= 0
    #sys.generatorstorages.gridwithdrawal_capacity[findall(x -> x > 0, res.genstor_discharging)] .= 0
 
    return sys
end