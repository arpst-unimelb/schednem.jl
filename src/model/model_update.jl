function update_model_parameters(m, sys, start_index, initial_soc_stor::Vector{Float64}=Float64[], initial_soc_genstor::Vector{Float64}=Float64[])

    total_length, _ = get_params(sys)

    if total_length < start_index + m[:N] - 1
        N = total_length - start_index + 1
        println("Last optimisation window is shorter ($N) than optimisation_window ($(m[:N])). Remaining values are taken from previous window.")
    else
        N = m[:N]
    end

    Nregions = m[:Nregions]
    Ngens = length(sys.generators.names);
    Nstors = length(sys.storages.names);
    Ngenstors = length(sys.generatorstorages.names);
    Ninterfaces = length(sys.interfaces.regions_from);

    for t in 1:N
        for r in 1:Nregions
            set_parameter_value(m[:dem][r,t], sys.regions.load[r, start_index + t - 1])
        end
        for g in 1:Ngens
            set_parameter_value(m[:gen_cap][g,t], sys.generators.capacity[g, start_index + t - 1])
        end
        for s in 1:Nstors
            set_parameter_value(m[:stor_charge_cap][s,t], sys.storages.charge_capacity[s, start_index + t - 1])
            set_parameter_value(m[:stor_discharge_cap][s,t], sys.storages.discharge_capacity[s, start_index + t - 1])
            set_parameter_value(m[:stor_energy_cap][s,t], sys.storages.energy_capacity[s, start_index + t - 1])
        end
        for gs in 1:Ngenstors
            set_parameter_value(m[:genstor_charge_cap][gs,t], sys.generatorstorages.charge_capacity[gs, start_index + t - 1])
            set_parameter_value(m[:genstor_discharge_cap][gs,t], sys.generatorstorages.discharge_capacity[gs, start_index + t - 1])
            set_parameter_value(m[:genstor_energy_cap][gs,t], sys.generatorstorages.energy_capacity[gs, start_index + t - 1])
            set_parameter_value(m[:genstor_inflow][gs,t], sys.generatorstorages.inflow[gs, start_index + t - 1])
        end
        for l in 1:Ninterfaces
            set_parameter_value(m[:interface_limit_forward][l,t], sys.interfaces.limit_forward[l, start_index + t - 1])
            set_parameter_value(m[:interface_limit_backward][l,t], sys.interfaces.limit_backward[l, start_index + t - 1])
        end
    end

    for s in 1:Nstors
        set_parameter_value(m[:stor_initial_soc][s], initial_soc_stor[s])
    end
    for gs in 1:Ngenstors
        set_parameter_value(m[:genstor_initial_soc][gs], initial_soc_genstor[gs])
    end

    return m
end