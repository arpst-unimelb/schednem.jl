function get_coefficients_storageConservation(m; rounding_digits=4)
    """
    Function to get the storage conservation coefficients from the model constraints. Not used currently, since POI is used instead.

    Note: The carryover and discharge coefficients are positive, while the charge coefficient is negative because of the normalisation of JuMP constraints.
    """

    N = m[:N]
    Nstors = length(m[:p_stor_charge][:,1])
    Ngenstors = length(m[:p_genstor_charge][:,1])

    stor_carryover_coeff = ones(Nstors, N)
    stor_charge_coeff = ones(Nstors, N)
    stor_discharge_coeff = ones(Nstors, N)

    # Get carryover eff (note the minus because of JuMP constraint normalisation)
    stor_carryover_coeff[:,1] =  normalized_coefficient.(storConservationStart, m[:e_stor])[:,1]
    stor_charge_coeff[:,1] = normalized_coefficient.(storConservationStart, m[:p_stor_charge])[:,1]
    stor_discharge_coeff[:,1] =  normalized_coefficient.(storConservationStart, m[:p_stor_discharge])[:,1]
    for t in 2:N
        stor_carryover_coeff[:,t] = normalized_coefficient.(storConservation[:,t], m[:e_stor][:,t]).data
        stor_charge_coeff[:,t] = normalized_coefficient.(storConservation[:,t], m[:p_stor_charge][:,t]).data
        stor_discharge_coeff[:,t] = normalized_coefficient.(storConservation[:,t], m[:p_stor_discharge][:,t]).data

    end

    
    genstor_carryover_coeff = ones(Ngenstors, N)
    genstor_charge_coeff = ones(Ngenstors, N)
    genstor_discharge_coeff = ones(Ngenstors, N)

    # Get carryover eff
    genstor_carryover_coeff[:,1] =  normalized_coefficient.(genstorConservationStart, m[:e_genstor])[:,1]
    genstor_charge_coeff[:,1] = normalized_coefficient.(genstorConservationStart, m[:p_genstor_charge])[:,1]
    genstor_discharge_coeff[:,1] =  normalized_coefficient.(genstorConservationStart, m[:p_genstor_discharge])[:,1]
    for t in 2:N
        genstor_carryover_coeff[:,t] = normalized_coefficient.(genstorConservation[:,t], m[:e_genstor][:,t]).data
        genstor_charge_coeff[:,t] = normalized_coefficient.(genstorConservation[:,t], m[:p_genstor_charge][:,t]).data
        genstor_discharge_coeff[:,t] = normalized_coefficient.(genstorConservation[:,t], m[:p_genstor_discharge][:,t]).data
    end

    return (stor_carryover_coeff=round.(stor_carryover_coeff, digits=rounding_digits),
            stor_charge_coeff=round.(stor_charge_coeff, digits=rounding_digits),
            stor_discharge_coeff=round.(stor_discharge_coeff, digits=rounding_digits),
            genstor_carryover_coeff=round.(genstor_carryover_coeff, digits=rounding_digits),
            genstor_charge_coeff=round.(genstor_charge_coeff, digits=rounding_digits),
            genstor_discharge_coeff=round.(genstor_discharge_coeff, digits=rounding_digits))

end
