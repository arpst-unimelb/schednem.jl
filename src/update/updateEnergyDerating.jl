function updateEnergyDerating(sys; derating_mapping = Dict(1.5 => 0.5, 3.5 => 0.75, 7.5 => 0.9))
    """
    This function is derating short-term energy storage capacities based on a provided mapping (or AEMO mapping by default).
    The derating_mapping is a Dict where keys are energy storage duration thresholds (in hours) and values are the derating factors (between 0 and 1).

    """
    
    lower_bound_hours  = 0.0
    for (derating_hours, derating_factor) in sort(derating_mapping)
        println("<",derating_hours, " hours energy storage derated to ", derating_factor * 100, "% capacity.")
        for s in 1:length(sys.storages.names)
            ecap = maximum(sys.storages.energy_capacity[s, :])
            pcap = maximum(sys.storages.discharge_capacity[s, :])  # Assuming capacity is constant over time
            energy_hours = ecap / pcap
            if energy_hours > lower_bound_hours && energy_hours <= derating_hours
                sys.storages.energy_capacity[s, :] .= round.(Int, ecap * derating_factor)
            end
        end
        lower_bound_hours = derating_hours
    end

    return sys
end