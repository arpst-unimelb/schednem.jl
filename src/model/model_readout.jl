function get_results(m; conservative_rounding=false)

    if conservative_rounding
        # Storage charging/discharging profiles
        p_stor_charge = ceil.(Int,value.(m[:p_stor_charge]))
        p_stor_discharge = floor.(Int,value.(m[:p_stor_discharge]))
        e_stor = floor.(Int, value.(m[:e_stor]))
        e_stor_ini = floor.(Int, value.(m[:stor_initial_soc]))

        # Generator-Storage charging/discharging profiles
        p_genstor_charge = ceil.(Int,value.(m[:p_genstor_charge]))
        p_genstor_discharge = floor.(Int,value.(m[:p_genstor_discharge]))
        e_genstor = floor.(Int,value.(m[:e_genstor]))
        e_genstor_ini = floor.(Int, value.(m[:genstor_initial_soc]))

    else
        # Storage charging/discharging profiles
        p_stor_charge = round.(Int,value.(m[:p_stor_charge]))
        p_stor_discharge = round.(Int,value.(m[:p_stor_discharge]))
        e_stor = round.(Int, value.(m[:e_stor]))
        e_stor_ini = round.(Int, value.(m[:stor_initial_soc]))

        # Generator-Storage charging/discharging profiles
        p_genstor_charge = round.(Int,value.(m[:p_genstor_charge]))
        p_genstor_discharge = round.(Int,value.(m[:p_genstor_discharge]))
        e_genstor = round.(Int,value.(m[:e_genstor]))
        e_genstor_ini = round.(Int, value.(m[:genstor_initial_soc]))
    end

    return (stor_charging=p_stor_charge,
        stor_discharging=p_stor_discharge,
        stor_energy=e_stor,
        stor_energy_initial=e_stor_ini,
        genstor_charging=p_genstor_charge,
        genstor_discharging=p_genstor_discharge,
        genstor_energy=e_genstor,
        genstor_energy_initial=e_genstor_ini
    )

end