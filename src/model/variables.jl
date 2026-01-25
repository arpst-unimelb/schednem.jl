#%% ========================================================================================================================
function add_variables(model, sys)

    # Extract system parameters
    Nregions = length(sys.regions.names);
    Ngens = length(sys.generators.names);
    Nstors = length(sys.storages.names);
    Ngenstors = length(sys.generatorstorages.names);
    Ninterfaces = length(sys.interfaces.regions_from);
    N = model[:N]

    # Define decision variables
    @variable(model, p_gen[1:Ngens, 1:N] >= 0)

    @variable(model, p_stor_charge[1:Nstors, 1:N] >= 0)
    @variable(model, p_stor_discharge[1:Nstors, 1:N] >= 0)
    @variable(model, e_stor[1:Nstors, 1:N] >= 0)

    @variable(model, p_genstor_charge[1:Ngenstors, 1:N] >= 0)
    @variable(model, p_genstor_discharge[1:Ngenstors, 1:N] >= 0)
    @variable(model, e_genstor[1:Ngenstors, 1:N] >= 0)

    @variable(model, p_interface_forward[1:Ninterfaces, 1:N] >= 0)
    @variable(model, p_interface_backward[1:Ninterfaces, 1:N] >= 0)

    @variable(model, load_shedding[1:Nregions, 1:N] >= 0)

    # And define all the parameters that will be updated (so the model doesn't need to be rebuilt)
    @variables(model, begin
        dem[1:Nregions, 1:N] in Parameter(0.0)

        gen_cap[1:Ngens, 1:N] in Parameter(0.0)
        
        stor_charge_cap[1:Nstors, 1:N] in Parameter(0.0)
        stor_discharge_cap[1:Nstors, 1:N] in Parameter(0.0)
        stor_energy_cap[1:Nstors, 1:N] in Parameter(0.0)
        stor_initial_soc[1:Nstors] in Parameter(0.0)
        stor_carryover_eff[1:Nstors, 1:N] in Parameter(1.0)
        stor_charge_eff[1:Nstors, 1:N] in Parameter(1.0)
        stor_discharge_eff_inverse[1:Nstors, 1:N] in Parameter(1.0)

        genstor_charge_cap[1:Ngenstors, 1:N] in Parameter(0.0)
        genstor_discharge_cap[1:Ngenstors, 1:N] in Parameter(0.0)
        genstor_energy_cap[1:Ngenstors, 1:N] in Parameter(0.0)
        genstor_inflow[1:Ngenstors, 1:N] in Parameter(0.0)
        genstor_initial_soc[1:Ngenstors] in Parameter(0.0)
        genstor_carryover_eff[1:Ngenstors, 1:N] in Parameter(1.0)
        genstor_charge_eff[1:Ngenstors, 1:N] in Parameter(1.0)
        genstor_discharge_eff_inverse[1:Ngenstors, 1:N] in Parameter(1.0)

        interface_limit_forward[1:Ninterfaces, 1:N] in Parameter(0.0)
        interface_limit_backward[1:Ninterfaces, 1:N] in Parameter(0.0)
    end)

    return model
end