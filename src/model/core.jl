
include("constraints.jl")
include("variables.jl")
include("objective.jl")
include("model_update.jl")
include("model_readout.jl")

#%% =======================================================================================================================
function build_operation_model(sys; optimisation_window::Int=24, move_forward::Int=24, generator_input_file::String="", optimiser::String="HiGHS")

    # First check that the optimisation window is larger than the step size
    if optimisation_window < move_forward
        error("The optimisation window must be larger than or equal to the move forward step size.")
    end

    sys = addGenCostData(sys, generator_input_file)
    sys = addVollData(sys)

    # Get the parameters of the system model
    Nregions = length(sys.regions.names);
    Ninterfaces = length(sys.interfaces.regions_from);

    connection_matrix = zeros(Int, Ninterfaces, Nregions) 
    for i in 1:length(sys.interfaces.regions_from)
        connection_matrix[i, sys.interfaces.regions_from[i]] = -1
        connection_matrix[i, sys.interfaces.regions_to[i]] = 1
    end    

    # Set up the optimization model
    if optimiser == "HiGHS"
        m = Model(() -> POI.Optimizer(HiGHS.Optimizer()));
    elseif optimiser == "Gurobi"
            m = Model(() -> POI.Optimizer(Gurobi.Optimizer()));
    else
        error("Unsupported optimiser: $optimiser. Supported options are 'HiGHS' and 'Gurobi'.")
    end
    set_silent(m);

    # Store model parameters as JuMP parameters
    m[:N] = optimisation_window  # Save the number of time steps as a parameter
    m[:move_forward] = move_forward  # Save the move forward step size as a parameter
    m[:Nregions] = Nregions  # Save the number of regions as a parameter
    m[:connection_matrix] = connection_matrix  # Save the connection matrix as a parameter

    # Add decision variables
    m = add_variables(m, sys)

    # Add objective function
    m = add_objective(m, sys)

    # Add constraints
    m = add_constraint_powerBalance(m, sys)
    m = add_constraint_techLimits(m, sys)
    m = add_constraints_storageConservation(m, sys)

    return m
end

function run_operation_model(m, sys)

    # Initialise result parameters
    full_horizon, _ = get_params(sys)
    stor_charging = zeros(Int, length(sys.storages.names), full_horizon)
    stor_discharging = zeros(Int, length(sys.storages.names), full_horizon)
    stor_energy = zeros(Int, length(sys.storages.names), full_horizon)
    genstor_charging = zeros(Int, length(sys.generatorstorages.names), full_horizon)
    genstor_discharging = zeros(Int, length(sys.generatorstorages.names), full_horizon)
    genstor_energy = zeros(Int, length(sys.generatorstorages.names), full_horizon)

    # Run the rolling horizon optimisation
    move_forward_step = m[:move_forward]
    for start_idx in 1:move_forward_step:full_horizon
        println("Optimising from time step $start_idx to $(min(start_idx + m[:N] - 1, full_horizon))")

        # Determine initial state of charge for storages and generator-storages
        if start_idx == 1
            initial_soc_stor = [0.0 for s in 1:length(sys.storages.names)]
            initial_soc_genstor = [0.0 for gs in 1:length(sys.generatorstorages.names)]
        else
            initial_soc_stor = value.(m[:e_stor])[:,move_forward_step - 1]
            initial_soc_genstor = value.(m[:e_genstor])[:,move_forward_step - 1]
        end

        # Update model parameters
        m = update_model_parameters(m, sys, start_idx, initial_soc_stor, initial_soc_genstor)

        # Optimize the model
        optimize!(m)

        # Check if the optimization was successful
        @assert is_solved_and_feasible(m) "Optimization failed at time step $start_idx"    

        # Extract results for the current optimisation window
        end_idx = min(start_idx + m[:N] - 1, full_horizon)
        time_steps = end_idx - start_idx + 1

        stor_charging[:, start_idx:end_idx] = round.(Int,value.(m[:p_stor_charge][:, 1:time_steps]))
        stor_discharging[:, start_idx:end_idx] = round.(Int,value.(m[:p_stor_discharge][:, 1:time_steps]))
        stor_energy[:, start_idx:end_idx] = round.(Int,value.(m[:e_stor][:, 1:time_steps]))

        genstor_charging[:, start_idx:end_idx] = round.(Int,value.(m[:p_genstor_charge][:, 1:time_steps]))
        genstor_discharging[:, start_idx:end_idx] = round.(Int,value.(m[:p_genstor_discharge][:, 1:time_steps]))
        genstor_energy[:, start_idx:end_idx] = round.(Int,value.(m[:e_genstor][:, 1:time_steps]))

        # Check if storage and generator-storage is operating as expected
        if sum(stor_charging[:, start_idx:end_idx] .* stor_discharging[:, start_idx:end_idx] .> 0) > 0
            println("WARNING: Some storages are charging and discharging at the same time between time steps $start_idx and $end_idx.")
        end
        if sum(genstor_charging[:, start_idx:end_idx] .* genstor_discharging[:, start_idx:end_idx] .> 0) > 0
            println("WARNING: Some generator-storages are charging and discharging at the same time between time steps $start_idx and $end_idx.")
        end

    end


    return (stor_charging=stor_charging,
        stor_discharging=stor_discharging,
        stor_energy=stor_energy,
        genstor_charging=genstor_charging,
        genstor_discharging=genstor_discharging,
        genstor_energy=genstor_energy
    )
end