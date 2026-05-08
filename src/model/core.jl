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
    DER_parameters::Dict=PRASNEM.get_DER_parameters(),
    genOpDetails=(uc=true, ramping=true, binary=false),
    hydro_parameters=PRASNEM.get_hydro_parameters(),
    objective_parameters=(storage_discharging_price=0.1, transmission_flow_penalty=0.1, 
            spillage_penalty=0.8, target_slack_penalty=0.8, dsp_rr_cost=0.95),
    )

    # First check that the optimisation window is larger than the step size
    if optimisation_window < move_forward
        @error "The optimisation window must be larger than or equal to the move forward step size."
    end

    if (optimisation_window < 24 || move_forward < 24) && (genOpDetails.uc)
        @warn "The optimisation window and/or move forward step size might not be long enough to fully capture the generator operation details (e.g., minimum up/down times)."
    end

    addVollData!(sys)
    addGenCostData!(sys, input_folder)

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
        m[:up_time] = round.(Int, genData.up_time[m[:id_gens]])
        m[:down_time] = round.(Int, genData.down_time[m[:id_gens]])
    else
        genData = nothing
    end

    if DER_parameters["DSP_flexibility"] || DER_parameters["EV_charge_flexibility"]
        m[:Ndrs] = length(sys.demandresponses.names)  # Save the number of demand response units as a parameter
        m[:drs_idxs_DSP] = findall(sys.demandresponses.categories .== "DSP")
        m[:drs_idxs_EV] = findall(sys.demandresponses.categories .== "EV")
        m[:drs_rr_cost] = 0.0 # Initialize the demand response cost parameter, will be updated in add_objective based on system attributes
        m[:drs_max_energy_time_window] = DER_parameters["DSP_limit_energy_per_window"]["max_energy_time_window"]
    else
        m[:Ndrs] = 0  # Set the number of demand response units to 0 if DSP is not included
    end

    # Add decision variables
    m = add_variables(m; genData)

    # Add objective function
    m = add_objective(m, sys; hydro_parameters=hydro_parameters, objective_parameters=objective_parameters, genData=genData)

    # Add constraints
    m = add_constraint_powerBalance(m, sys)
    m = add_constraint_techLimits(m; genData=genData)
    m = add_constraints_storageConservation(m)
    m = add_constraints_hydro_finalSOC(m, sys; hydro_parameters=hydro_parameters)

    if genOpDetails.uc || genOpDetails.ramping
        add_constraints_rampLimits!(m, genData)
        add_constraints_commitment!(m, genData)
        add_constraints_minUpDownTime!(m, genData)
    end

    # Add DER specific constraints
    if DER_parameters["DSP_flexibility"] || DER_parameters["EV_charge_flexibility"]
        m = add_constraints_demandResponse(m, DER_parameters)
        #m = add_constraints_demandResponse_paybackTime(m, DER_parameters) # Currently not used as maxEnergy constraint is added
        m = add_constraints_demandResponse_maxEnergy(m, DER_parameters)
    end
    if !DER_parameters["VPP_flexibility"]
        m = add_constraints_disableVPP(m, sys)
    end

		MOI.set(m, POI.ConstraintsInterpretation(), POI.BOUNDS_AND_CONSTRAINTS)

    # Initialise with first step
    update_model_parameters!(m, sys, 1)

    return m
end
#%% =======================================================================================================================
"""
    run_operation_model(m, sys; output_file::String="", start_simulation::Int=1, end_simulation::Int=0)

Runs the operation model with rolling horizon optimisation, updating the data from the PRAS system sys, and returns the resulting schedule as a SchedData object.

"""
function run_operation_model(m, sys; output_file::String="", start_simulation::Int=1, end_simulation::Int=0, include_reserve_run::Bool=true)

    if start_simulation > 1
        @warn "Starting simulation from time step $start_simulation. Note that the result includes earlier timesteps, however with random values. Make sure to only use the relevant time steps in the analysis or create a new system model from a later timestep."
    end

    # Check if schedule files already exist
    if "case" in keys(sys.attrs) && output_file != ""
        case_name = sys.attrs["case"]
        #output_file= joinpath(output_folder_schedule, case_name * ".h5")
        if ispath(output_file)
            @info "Loading schedule from existing files in: " * output_file
            return read_schedule(output_file)
        end
    end

    # Initialise result parameters
    full_horizon, _ = PRAS.get_params(sys)
    if end_simulation > 0
        full_horizon = min(full_horizon, end_simulation)
    end

    @info "Running operation model with rolling horizon optimisation..."
    println("        Optimisation window: ", m[:N], " | Move forward step: ", m[:move_forward], "")
    println("        Timesteps: ", start_simulation, " to ", full_horizon)
    println("        Ramping: ", m[:genOpDetails].ramping, " | UC: ", m[:genOpDetails].uc, " | Binary: ", m[:genOpDetails].binary)
    println("        Reserve run: ", include_reserve_run)

    # Initialise an empty SchedData object to store the results
    res = SchedData(sys; N=full_horizon) 

    # Create a copy of the system model with reserves if include_reserve_run is true, and add reserves to the system model.
    if include_reserve_run
        sys_with_reserves = deepcopy(sys)
        SchedNEM.addReserve!(sys_with_reserves)
    end

    # TODO: Add updating initial energy here from sys.storages attributes when available in PRAS

    # Initial values
    Nstors = m[:Nstors];
    Ngenstors = m[:Ngenstors];
    initial_soc_stor = []
    initial_soc_genstor = []
    p_gen_initial = []
    gon_initial = []
    stup_before = []
    shdw_before = []
    res_window = nothing

    # Run the rolling horizon optimisation
    move_forward_step = m[:move_forward]
    start_idxs = start_simulation:move_forward_step:full_horizon
    for start_idx in start_idxs
        if start_idx % (round(Int,full_horizon / 10)) == 0
            println("Optimisation progress: Time step ", start_idx, " of ", full_horizon)
        end
        #println("Optimising from time step ", start_idx, " to ", min(start_idx + m[:N] - 1, full_horizon))

        # Determine initial state of charge for storages and generator-storages
        if start_idx > start_simulation # Not for fist time-step
            if Nstors > 0
                initial_soc_stor = res_window.stor_energy[:,move_forward_step]
            end
            if Ngenstors > 0
                initial_soc_genstor = res_window.genstor_energy[:,move_forward_step]
            end
            if m[:genOpDetails].ramping
                # get the generation at the last time step of previous window
                p_gen_initial = res_window.p_gen[:,move_forward_step]
            end
            if m[:genOpDetails].uc
                # Get the commitment status, start-up and shut-down at the last time step of previous window
                gon_initial = res_window.gon[:,move_forward_step]

                stup_before = zeros(size(m[:stup_before][:,:]))
                shdw_before = zeros(size(m[:shdw_before][:,:]))
                # Shift the startup and shutdown indicators
                stup_before[:,1:move_forward_step] = value.(m[:stup_before])[:,move_forward_step+1:end] # Get the earlier time steps from the second previous optimisation
                stup_before[:,move_forward_step+1:end] = res_window.stup[:,1:move_forward_step] # Get the last time steps from within the previous optimisation
                shdw_before[:,1:move_forward_step] = value.(m[:shdw_before])[:,move_forward_step+1:end]
                shdw_before[:,move_forward_step+1:end] = res_window.shdw[:,1:move_forward_step]
            end
        end

        if include_reserve_run
            # Reset the lower bounds for generator commitment
            set_lower_bound.(m[:gon], 0.0)

            # Update model parameters with reserves
            update_model_parameters!(m, sys_with_reserves, start_idx; 
                initial_soc_stor=initial_soc_stor, initial_soc_genstor=initial_soc_genstor, 
                gon_initial=gon_initial, stup_before=stup_before, shdw_before=shdw_before, p_gen_initial=p_gen_initial)

            # Optimize the model with reserves
            optimize!(m)

            if is_solved_and_feasible(m)
                # Extract generator commitments for the current optimisation window with reserves
                gons = value.(m[:gon])
                # Set the generator commitment decisions as lower bounds for the next optimisation without reserves to ensure that the reserve constraints are binding and the same commitment decisions are made in the next optimisation without reserves
                set_lower_bound.(m[:gon], gons) 
            else
                @warn "Optimization failed for window $start_idx-$(start_idx+m[:N]-1) for reserve run. Removing reserve constraints for this window."
                return m
            end
        end

        # Update model parameters
        update_model_parameters!(m, sys, start_idx; initial_soc_stor=initial_soc_stor, initial_soc_genstor=initial_soc_genstor, 
            gon_initial=gon_initial, stup_before=stup_before, shdw_before=shdw_before, p_gen_initial=p_gen_initial)

        # Optimize the model
        optimize!(m)

        # Check if the optimization was successful
        if !is_solved_and_feasible(m)

            # Try to relax the model by removing the reserve constraints if they were included, and re-optimize
            if include_reserve_run
                @warn "Optimization failed at time step $start_idx. Removing reserve constraints and re-optimizing."
                set_lower_bound.(m[:gon], 0.0) # Remove the lower bound on generator commitment to allow the model to find a feasible solution without reserve constraints
                optimize!(m)
            end

            # If shill not feasible, return the model with the infeasibility status for analysis
            if !is_solved_and_feasible(m)
                @warn "Optimization failed at time step $start_idx. Ending simulation and returning infeasible model."
                return m
            end
        end

        # Extract results for full the current optimisation window
        end_idx = min(start_idx + m[:N] - 1, full_horizon)
        time_steps = end_idx - start_idx + 1

        if sum(value.(m[:load_shedding])) > 0
            @warn "Load shedding is occurring in simulation $start_idx-$end_idx: $(round(sum(value.(m[:load_shedding])), digits=2)) MWh."
        end

        if sum(value.(m[:genstor_spillage])) > 0
            @warn "Hydro spillage is occurring in simulation $start_idx-$end_idx: $(round(sum(value.(m[:genstor_spillage])), digits=2)) MWh."
        end

        res_window = get_results(m)

        update_SchedData!(res, start_idx:end_idx, res_window, 1:time_steps)

        # Check if storage and generator-storage is operating as expected
        if sum(res.stor_charging[:, start_idx:end_idx] .* res.stor_discharging[:, start_idx:end_idx] .> 0) > 0
            @warn "Some storages are charging and discharging at the same time between time steps $start_idx and $end_idx."
        end
        if sum(res.genstor_charging[:, start_idx:end_idx] .* res.genstor_discharging[:, start_idx:end_idx] .> 0) > 0
            @warn "Some generator-storages are charging and discharging at the same time between time steps $start_idx and $end_idx."
        end

    end

    if (output_file != "")
        @info "Saving schedule to file: " * output_file
        save_schedule(res, output_file)
    end

    return res
end