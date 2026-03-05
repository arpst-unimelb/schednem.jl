include("./DERparameters.jl")
include("constraints.jl")
include("variables.jl")
include("objective.jl")

#%% =======================================================================================================================
"""
    build_operation_model(sys; optimisation_window::Int=24, move_forward::Int=24, input_folder::String="", optimiser=HiGHS.Optimizer(), include_DSP::Bool=true)



# Optional arguments:
- 'generatorOperationDetails': If true, the model includes generator operation details such as ramping limits, minimum up/down times, and start-up/shut-down costs. This can increase the realism of the model but also increases the complexity and solution time. Default is true.


# DSP parameters (only relevant if `include_DSP=true`):
    - `"max_energy_time_window" => 24 # The time window (in hours) over which the maximum energy borrow limits are applied. For example, if set to 24, the total energy borrowed over any 24 hour period cannot exceed the limit defined by `max_energy_per_window_per_capacity`.
    - `"max_energy_per_window_per_capacity" => 4 # The maximum energy that can be borrowed over the specified time window, expressed as a multiple of the unit's capacity.
    - `"limits_on_price_bands" => [0] # Select which price bands should be included in the max energy borrow limits. Empty for no limits, or [0] for reliability price band only. 


"""
function build_operation_model(sys; 
    optimisation_window::Int=48, move_forward::Int=24, 
    input_folder::String="", optimiser=HiGHS.Optimizer(),
    DER_parameters::Dict=get_DER_parameters(),
    genOpDetails=(uc=true, ramping=true, binary=false),
    hydro_discharging_price::Float64=85.0,
    storage_discharging_price::Float64=1.0,
    )

    # First check that the optimisation window is larger than the step size
    if optimisation_window < move_forward
        @error "The optimisation window must be larger than or equal to the move forward step size."
    end

    if (optimisation_window - move_forward < 24) && (genOpDetails.uc)
        @warn "The optimisation window might not be long enough to fully capture the generator operation details (e.g., minimum up/down times) with the selected move forward step size."
    end

    sys = addVollData(sys)
    sys = addGenCostData(sys, input_folder)

    # Get the parameters of the system model
    Nregions = length(sys.regions.names);
    Ninterfaces = length(sys.interfaces.regions_from);

    connection_matrix = zeros(Int, Ninterfaces, Nregions) 
    for i in 1:Ninterfaces
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
    m[:Ngens] = length(sys.generators.names)  # Save the number of generators as a parameter
    m[:genOpDetails] = genOpDetails # Save whether generator operation details are included as a parameter
    m[:Nstors] = length(sys.storages.names)  # Save the number of storages as a parameter
    m[:Ngenstors] = length(sys.generatorstorages.names)  # Save the number of generator-storages as a parameter
    m[:Ninterfaces] = Ninterfaces  # Save the number of interfaces as a parameter
    m[:connection_matrix] = connection_matrix  # Save the connection matrix as a parameter

    if genOpDetails.uc || genOpDetails.ramping
        # Add the generator ids as a parameter to the model to be used in the constraints
        m[:id_gens] = parse.(Int, first.(split.(sys.generators.names, "_")))
        # Get the generator operation data
        genData = getGenOperationData(input_folder)
        m[:rup] = genData.rup[m[:id_gens]] # Save the ramp-up limits (to use in getResults later)
    else
        genData = nothing
    end

    if DER_parameters["DSP_flexibility"] || DER_parameters["EV_charge_flexibility"]
        m[:Ndrs] = length(sys.demandresponses.names)  # Save the number of demand response units as a parameter
        m[:drs_idxs_DSP] = findall(sys.demandresponses.categories .== "DSP")
        m[:drs_idxs_EV] = findall(sys.demandresponses.categories .== "EV")
    else
        m[:Ndrs] = 0  # Set the number of demand response units to 0 if DSP is not included
    end

    # Add decision variables
    m = add_variables(m; genData)

    # Add objective function
    m = add_objective(m, sys; hydro_discharging_price=hydro_discharging_price, storage_discharging_price=storage_discharging_price, genData=genData)

    # Add constraints
    m = add_constraint_powerBalance(m, sys)
    m = add_constraint_techLimits(m; genData=genData)
    m = add_constraints_storageConservation(m)
    m = add_constraints_genstorEnergyTarget(m)

    if genOpDetails.uc || genOpDetails.ramping
        add_constraints_rampLimits!(m, genData)
        add_constraints_commitment!(m, genData)
        add_constraints_minUpDownTime!(m, genData)
    end

    # Add DER specific constraints
    if DER_parameters["DSP_flexibility"] || DER_parameters["EV_charge_flexibility"]
        m = add_constraints_demandResponse(m, DER_parameters)
        m = add_constraints_demandResponse_paybackTime(m, DER_parameters)
        m = add_constraints_demandResponse_maxEnergy(m, DER_parameters)
    end
    if !DER_parameters["VPP_flexibility"]
        m = add_constraints_disableVPP(m, sys)
    end

    # Initialise with first step
    update_model_parameters!(m, sys, 1, zeros(m[:Nstors]), zeros(m[:Ngenstors]))

    return m
end

function run_operation_model(m, sys; output_folder_schedule::String="", start_simulation::Int=1, end_simulation::Int=0)

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
            drs_borrowing = CSV.read(joinpath(output_folder_schedule, case_name * "_drs_borrowing.csv"), DataFrames.DataFrame; header=false)
            drs_payback = CSV.read(joinpath(output_folder_schedule, case_name * "_drs_payback.csv"), DataFrames.DataFrame; header=false)
            return (stor_charging=Matrix(stor_charging),
                stor_discharging=Matrix(stor_discharging),
                stor_energy=Matrix(stor_energy),
                genstor_charging=Matrix(genstor_charging),
                genstor_discharging=Matrix(genstor_discharging),
                genstor_energy=Matrix(genstor_energy),
                drs_borrowing=Matrix(drs_borrowing),
                drs_payback=Matrix(drs_payback)
            )
        end
    end

    # Initialise result parameters
    full_horizon, _ = get_params(sys)
    if end_simulation > 0
        full_horizon = min(full_horizon, end_simulation)
    end
    Nstors = m[:Nstors];
    Ngenstors = m[:Ngenstors];
    Ndrs = m[:Ndrs]

    stor_charging = zeros(Int, Nstors, full_horizon)
    stor_discharging = zeros(Int, Nstors, full_horizon)
    stor_energy = zeros(Int, Nstors, full_horizon)
    stor_energy_initial = zeros(Int, Nstors)
    genstor_charging = zeros(Int, Ngenstors, full_horizon)
    genstor_discharging = zeros(Int, Ngenstors, full_horizon)
    genstor_energy = zeros(Int, Ngenstors, full_horizon)
    genstor_energy_initial = zeros(Int, Ngenstors)
    drs_borrowing = zeros(Int, Ndrs, full_horizon)
    drs_payback = zeros(Int, Ndrs, full_horizon)
    p_gen = zeros(Int, m[:Ngens], full_horizon)
    p_gen_max = zeros(Int, m[:Ngens], full_horizon)
    gon = zeros(Int, m[:Ngens], full_horizon)
    stup = zeros(Int, m[:Ngens], full_horizon)
    shdw = zeros(Int, m[:Ngens], full_horizon)

    # TODO: Add updating initial energy here from sys.storages attributes when available in PRAS

    # Initial values
    initial_soc_stor = stor_energy_initial
    initial_soc_genstor = genstor_energy_initial
    p_gen_initial = []
    gon_initial = []
    stup_before = []
    shdw_before = []

    # Run the rolling horizon optimisation
    move_forward_step = m[:move_forward]
    start_idxs = start_simulation:move_forward_step:full_horizon
    for start_idx in start_idxs
        if start_idx % (round(Int,full_horizon / 10)) == 0
            println("Optimisation progress: Time step ", start_idx, " of ", full_horizon)
        end
        #println("Optimising from time step ", start_idx, " to ", min(start_idx + m[:N] - 1, full_horizon))

        # Determine initial state of charge for storages and generator-storages
        if start_idx != start_simulation
            if Nstors > 0
                initial_soc_stor = value.(m[:e_stor])[:,move_forward_step]
            end
            if Ngenstors > 0
                initial_soc_genstor = value.(m[:e_genstor])[:,move_forward_step]
            end
            if m[:genOpDetails].ramping
                # get the generation at the last time step of previous window
                p_gen_initial = value.(m[:p_gen])[:,move_forward_step]
            end
            if m[:genOpDetails].uc
                # Get the commitment status, start-up and shut-down at the last time step of previous window
                gon_initial = value.(m[:gon])[:,move_forward_step]

                stup_before = zeros(size(m[:stup_before][:,:]))
                shdw_before = zeros(size(m[:shdw_before][:,:]))
                # Shift the startup and shutdown indicators
                stup_before[:,1:move_forward_step] = value.(m[:stup_before])[:,move_forward_step+1:end] # Get the earlier time steps from the second previous optimisation
                stup_before[:,move_forward_step+1:end] = value.(m[:stup])[:,1:move_forward_step] # Get the last time steps from within the previous optimisation
                shdw_before[:,1:move_forward_step] = value.(m[:shdw_before])[:,move_forward_step+1:end]
                shdw_before[:,move_forward_step+1:end] = value.(m[:shdw])[:,1:move_forward_step]
            end
        end

        # Update model parameters
        update_model_parameters!(m, sys, start_idx, initial_soc_stor, initial_soc_genstor; 
            gon_initial=gon_initial, stup_before=stup_before, shdw_before=shdw_before, p_gen_initial=p_gen_initial)


        # Optimize the model
        optimize!(m)

        # Check if the optimization was successful
        if !is_solved_and_feasible(m)
            @warn "Optimization failed at time step $start_idx. Ending simulation and returning infeasible model."
            return m
        end

        # Extract results for full the current optimisation window
        end_idx = min(start_idx + m[:N] - 1, full_horizon)
        time_steps = end_idx - start_idx + 1

        res_window = get_results(m)

        stor_charging[:, start_idx:end_idx] = res_window.stor_charging[:, 1:time_steps]
        stor_discharging[:, start_idx:end_idx] = res_window.stor_discharging[:, 1:time_steps]
        stor_energy[:, start_idx:end_idx] = res_window.stor_energy[:, 1:time_steps]

        genstor_charging[:, start_idx:end_idx] = res_window.genstor_charging[:, 1:time_steps]
        genstor_discharging[:, start_idx:end_idx] = res_window.genstor_discharging[:, 1:time_steps]
        genstor_energy[:, start_idx:end_idx] = res_window.genstor_energy[:, 1:time_steps]

        drs_borrowing[:, start_idx:end_idx] = res_window.drs_borrowing[:, 1:time_steps]
        drs_payback[:, start_idx:end_idx] = res_window.drs_payback[:, 1:time_steps]

        p_gen[:, start_idx:end_idx] = res_window.p_gen[:, 1:time_steps]
        p_gen_max[:, start_idx:end_idx] = res_window.p_gen_max[:, 1:time_steps]
        gon[:, start_idx:end_idx] = res_window.gon[:, 1:time_steps]
        stup[:, start_idx:end_idx] = res_window.stup[:, 1:time_steps]
        shdw[:, start_idx:end_idx] = res_window.shdw[:, 1:time_steps]

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
        genstor_energy_initial=genstor_energy_initial,
        drs_borrowing=drs_borrowing,
        drs_payback=drs_payback,
        p_gen=p_gen,
        p_gen_max=p_gen_max,
        gon=gon,
        stup=stup,
        shdw=shdw
    )

    if (output_folder_schedule != "") && isdir(output_folder_schedule)
        if m[:genOpDetails].uc || m[:genOpDetails].ramping
            @warn "Generator operation details were included in the model, but the full schedule (including generator commitment and ramping) is not currently being saved. Only storage and demand response schedules are being saved. Saving full generator schedule is a planned future improvement."
        end
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
            CSV.write(joinpath(output_folder_schedule, case_name * "_drs_borrowing.csv"), Tables.table(res_schedule.drs_borrowing); writeheader=false)
            CSV.write(joinpath(output_folder_schedule, case_name * "_drs_payback.csv"), Tables.table(res_schedule.drs_payback); writeheader=false)
        end
    end

    return res_schedule
end