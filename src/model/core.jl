
include("constraints.jl")
include("variables.jl")
include("objective.jl")
include("model_update.jl")
include("model_readout.jl")

#%% =======================================================================================================================
function build_operation_model(sys; optimisation_window::Int=24, move_forward::Int=24, input_folder::String="", optimiser=HiGHS.Optimizer())

    # First check that the optimisation window is larger than the step size
    if optimisation_window < move_forward
        @error "The optimisation window must be larger than or equal to the move forward step size."
    end

    sys = addGenCostData(sys, input_folder)
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
    m = Model(() -> POI.Optimizer(optimiser));
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

function run_operation_model(m, sys; output_folder_schedule::String="")

    # Check if schedule files already exist
    if "case" in keys(sys.attrs) && output_folder_schedule != ""
        case_name = sys.attrs["case"]
        output_filepath_test = joinpath(output_folder_schedule, case_name * "_stor_charging.csv")
        if ispath(output_filepath_test)
            @info "Loading schedule from existing files in: " * output_folder_schedule
            stor_charging = CSV.read(joinpath(output_folder_schedule, case_name * "_stor_charging.csv"), DataFrames.DataFrame; header=false)
            stor_discharging = CSV.read(joinpath(output_folder_schedule, case_name * "_stor_discharging.csv"), DataFrames.DataFrame; header=false)
            stor_energy = CSV.read(joinpath(output_folder_schedule, case_name * "_stor_energy.csv"), DataFrames.DataFrame; header=false)
            stor_energy_initial = CSV.read(joinpath(output_folder_schedule, case_name * "_stor_energy_initial.csv"), DataFrames.DataFrame; header=false)
            genstor_charging = CSV.read(joinpath(output_folder_schedule, case_name * "_genstor_charging.csv"), DataFrames.DataFrame; header=false)
            genstor_discharging = CSV.read(joinpath(output_folder_schedule, case_name * "_genstor_discharging.csv"), DataFrames.DataFrame; header=false)
            genstor_energy = CSV.read(joinpath(output_folder_schedule, case_name * "_genstor_energy.csv"), DataFrames.DataFrame; header=false)
            genstor_energy_initial = CSV.read(joinpath(output_folder_schedule, case_name * "_genstor_energy_initial.csv"), DataFrames.DataFrame; header=false)
            return (stor_charging=Matrix(stor_charging),
                stor_discharging=Matrix(stor_discharging),
                stor_energy=Matrix(stor_energy),
                genstor_charging=Matrix(genstor_charging),
                genstor_discharging=Matrix(genstor_discharging),
                genstor_energy=Matrix(genstor_energy)
            )
        end
    end

    # Initialise result parameters
    full_horizon, _ = get_params(sys)
    Nstors = length(sys.storages.names);
    Ngenstors = length(sys.generatorstorages.names);

    stor_charging = zeros(Int, Nstors, full_horizon)
    stor_discharging = zeros(Int, Nstors, full_horizon)
    stor_energy = zeros(Int, Nstors, full_horizon)
    stor_energy_initial = zeros(Int, Nstors)
    genstor_charging = zeros(Int, Ngenstors, full_horizon)
    genstor_discharging = zeros(Int, Ngenstors, full_horizon)
    genstor_energy = zeros(Int, Ngenstors, full_horizon)
    genstor_energy_initial = zeros(Int, Ngenstors)

    # TODO: Add updating initial energy here from sys.storages attributes when available in PRAS

    # Run the rolling horizon optimisation
    move_forward_step = m[:move_forward]
    start_idxs = 1:move_forward_step:full_horizon
    for start_idx in start_idxs
        if start_idx % (round(Int,full_horizon / 10)) == 0
            println("Optimisation progress: Time step $start_idx of $full_horizon")
        end
        println("Optimising from time step $start_idx to $(min(start_idx + m[:N] - 1, full_horizon))")

        # Determine initial state of charge for storages and generator-storages
        if start_idx == 1
            initial_soc_stor = stor_energy_initial
            initial_soc_genstor = genstor_energy_initial
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

        res_window = get_results(m)

        stor_charging[:, start_idx:end_idx] = res_window.stor_charging[:, 1:time_steps]
        stor_discharging[:, start_idx:end_idx] = res_window.stor_discharging[:, 1:time_steps]
        stor_energy[:, start_idx:end_idx] = res_window.stor_energy[:, 1:time_steps]

        genstor_charging[:, start_idx:end_idx] = res_window.genstor_charging[:, 1:time_steps]
        genstor_discharging[:, start_idx:end_idx] = res_window.genstor_discharging[:, 1:time_steps]
        genstor_energy[:, start_idx:end_idx] = res_window.genstor_energy[:, 1:time_steps]

        # Check if storage and generator-storage is operating as expected
        if sum(stor_charging[:, start_idx:end_idx] .* stor_discharging[:, start_idx:end_idx] .> 0) > 0
            @warn "Some storages are charging and discharging at the same time between time steps $start_idx and $end_idx."
        end
        if sum(genstor_charging[:, start_idx:end_idx] .* genstor_discharging[:, start_idx:end_idx] .> 0) > 0
            @warn "Some generator-storages are charging and discharging at the same time between time steps $start_idx and $end_idx."
        end

    end

    res_schedule = (stor_charging=stor_charging,
        stor_discharging=stor_discharging,
        stor_energy=stor_energy,
        stor_energy_initial=stor_energy_initial,
        genstor_charging=genstor_charging,
        genstor_discharging=genstor_discharging,
        genstor_energy=genstor_energy,
        genstor_energy_initial=genstor_energy_initial
    )

    if (output_folder_schedule != "") && isdir(output_folder_schedule)
        if !("case" in keys(sys.attrs))
            @warn "'case' attribute not found in system attributes. Couldn't save schedule."
        else
            case_name = sys.attrs["case"]
            CSV.write(joinpath(output_folder_schedule, case_name * "_stor_charging.csv"), Tables.table(res_schedule.stor_charging); writeheader=false)
            CSV.write(joinpath(output_folder_schedule, case_name * "_stor_discharging.csv"), Tables.table(res_schedule.stor_discharging); writeheader=false)
            CSV.write(joinpath(output_folder_schedule, case_name * "_stor_energy.csv"), Tables.table(res_schedule.stor_energy); writeheader=false)
            CSV.write(joinpath(output_folder_schedule, case_name * "_stor_energy_initial.csv"), Tables.table(res_schedule.stor_energy_initial'); writeheader=false)
            CSV.write(joinpath(output_folder_schedule, case_name * "_genstor_charging.csv"), Tables.table(res_schedule.genstor_charging); writeheader=false)
            CSV.write(joinpath(output_folder_schedule, case_name * "_genstor_discharging.csv"), Tables.table(res_schedule.genstor_discharging); writeheader=false)
            CSV.write(joinpath(output_folder_schedule, case_name * "_genstor_energy.csv"), Tables.table(res_schedule.genstor_energy); writeheader=false)
            CSV.write(joinpath(output_folder_schedule, case_name * "_genstor_energy_initial.csv"), Tables.table(res_schedule.genstor_energy_initial'); writeheader=false)
        end
    end

    return res_schedule
end