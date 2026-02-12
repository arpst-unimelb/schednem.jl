function get_results(m; conservative_rounding=false)

    N = m[:N]
    Nstors = m[:Nstors]
    Ngenstors = m[:Ngenstors]
    Ndrs = m[:Ndrs]

    p_stor_charge = zeros(Int, Nstors, N)
    p_stor_discharge = zeros(Int, Nstors, N)
    e_stor = zeros(Int, Nstors, N)
    e_stor_ini = zeros(Int, Nstors)
    p_genstor_charge = zeros(Int, Ngenstors, N)
    p_genstor_discharge = zeros(Int, Ngenstors, N)
    e_genstor = zeros(Int, Ngenstors, N)
    e_genstor_ini = zeros(Int, Ngenstors)

    p_borrow_drs = zeros(Int, Ndrs, N)
    p_payback_drs = zeros(Int, Ndrs, N)

    if Nstors > 0
            # Storage charging/discharging profiles
        p_stor_charge = round.(Int,value.(m[:p_stor_charge]))
        p_stor_discharge = round.(Int,value.(m[:p_stor_discharge]))
        e_stor = round.(Int, value.(m[:e_stor]))
        e_stor_ini = round.(Int, value.(m[:stor_initial_soc]))
    end

    if Ngenstors > 0
        # Generator-Storage charging/discharging profiles
        p_genstor_charge = round.(Int,value.(m[:p_genstor_charge]))
        p_genstor_discharge = round.(Int,value.(m[:p_genstor_discharge]))
        e_genstor = round.(Int,value.(m[:e_genstor]))
        e_genstor_ini = round.(Int, value.(m[:genstor_initial_soc]))
    end

    if Ndrs > 0
        # Demand response borrowing/payback profiles
        p_borrow_drs = round.(Int,value.(m[:p_borrow_drs]))
        p_payback_drs = round.(Int,value.(m[:p_payback_drs]))
    end


    return (stor_charging=p_stor_charge,
        stor_discharging=p_stor_discharge,
        stor_energy=e_stor,
        stor_energy_initial=e_stor_ini,
        genstor_charging=p_genstor_charge,
        genstor_discharging=p_genstor_discharge,
        genstor_energy=e_genstor,
        genstor_energy_initial=e_genstor_ini,
        drs_borrowing=p_borrow_drs,
        drs_payback=p_payback_drs
    )

end