function get_results(m)

    # Logic to follow PRAS rounding conventions:
    # 1. If storage is discharging, round up discharging power, which means we might have to use more energy than "optimally" scheduled

    # Storage charging/discharging profiles
    p_stor_charge = round.(Int,value.(m[:p_stor_charge]))
    p_stor_discharge = round.(Int,value.(m[:p_stor_discharge]))
    e_stor = round.(Int, value.(m[:e_stor]))

    e_stor_ini = round.(Int, value.(m[:stor_initial_soc]))
    e_genstor_ini = round.(Int, value.(m[:genstor_initial_soc]))



    N = m[:N]
    Nstors = size(m[:p_stor_charge], 1)

    # Round up all the discharge values
    p_stor_discharge = ceil.(Int, value.(m[:p_stor_discharge]))
    p_stor_charge = floor.(Int, value.(m[:p_stor_charge]))
    e_stor = round.(Int, value.(m[:e_stor]))

    for i in 1:1:N
        for s in 1:1:Nstors
            if p_stor_discharge[s,i] > 0
                e_stor[s,i] = e_stor[s,i-1] - ceil(Int, p_stor_discharge[s,i] / sys.storages.discharge_efficiency[s,i])
            elseif p_stor_charge[s,i] > 0
                e_stor[s,i] = e_stor[s,i-1] + floor(Int, p_stor_charge[s,i] * sys.storages.charge_efficiency[s,i])
            end
        end
    end


    # Generator-Storage charging/discharging profiles
    p_genstor_charge = round.(Int,value.(m[:p_genstor_charge]))
    p_genstor_discharge = round.(Int,value.(m[:p_genstor_discharge]))
    e_genstor = round.(Int,value.(m[:e_genstor]))

    return (stor_charginge=p_stor_charge,
        stor_discharging=p_stor_discharge,
        stor_energy=e_stor,
        stor_initial_energy=e_stor_ini,
        genstor_charging=p_genstor_charge,
        genstor_discharging=p_genstor_discharge,
        genstor_energy=e_genstor,
        genstor_energy_initial=e_genstor_ini
    )

end