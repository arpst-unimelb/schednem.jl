"""
    get_results(m::JuMP.Model; conservative_rounding=false)

Function to extract the results from the solution of the optimization model and return them in a mutable struct.

"""
function get_results(m; conservative_rounding=false)

    N = m[:N]
    Ngens = m[:Ngens]
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

    gon = ones(Int, Ngens, N)
    stup = zeros(Int, Ngens, N)
    shdw = zeros(Int, Ngens, N)

    # Generator details
    p_gen = round.(Int, value.(m[:p_gen]))
    p_gen_max = round.(Int, value.(m[:gen_cap]))

    # If ramping activated, update the p_gen_max to always to the previous time step's generation + ramping limit
    # --- This is conservative! But if storages are also turned off, this should work to identify critical times if ramping limits are a problem. If only used for PRAS input, this does not work.
    if m[:genOpDetails].ramping
        p_gen_max[:,1] = round.(Int, min.(value.(m[:p_gen_initial][:]) .+ m[:rup], p_gen_max[:,1])) 
        p_gen_max[:,2:end] = round.(Int, min.(p_gen[:, 1:end-1] .+ m[:rup], p_gen_max[:,2:end]))
    end

    if m[:genOpDetails].uc
        gon = round.(Int, value.(m[:gon]))
        stup = round.(Int, value.(m[:stup]))
        shdw = round.(Int, value.(m[:shdw]))
    end
    
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
        drs_payback=p_payback_drs,
        p_gen = p_gen,
        p_gen_max = p_gen_max,
        gon = gon,
        stup = stup,
        shdw = shdw
    )

end