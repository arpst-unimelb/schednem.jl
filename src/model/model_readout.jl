function readout_model_results(m)

    # Storage charging/discharging profiles
    p_stor_charge = value.(m[:p_stor_charge])
    p_stor_discharge = value.(m[:p_stor_discharge])
    e_stor = value.(m[:e_stor])

    # Generator-Storage charging/discharging profiles
    p_genstor_charge = value.(m[:p_genstor_charge])
    p_genstor_discharge = value.(m[:p_genstor_discharge])
    e_genstor = value.(m[:e_genstor])
    return (p_stor_charge=p_stor_charge,p_stor_discharge=p_stor_discharge,
        e_stor=e_stor,
        p_genstor_charge=p_genstor_charge,
        p_genstor_discharge=p_genstor_discharge,
        e_genstor=e_genstor
    )

end