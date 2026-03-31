"""
    reoptimise(df_expectation, sys, res_input, genAvSamples, lineAvSamples;
        default_horizon::Int=4, min_time_after_event::Int=4,
        optimisation_window::Int=48, move_forward::Int=24, 
        optimiser_name="HiGHS", input_folder::String="",
        DER_parameters=PRASNEM.get_DER_parameters(), 
        genOpDetails=(uc=true, ramping=true, binary=false),
        max_extend_simulations::Int=10,
        imperfect_foresight=true)

Important points:
- Sys should be with the full max capacity of all components (i.e. before any derating).


Parameters:
- 'df_expectation': The DataFrame with the critical events and their details (e.g. from PRASNEM.get_all_event_details).
- 'sys': The PRAS system object containing the system data and parameters.
- 'res_input': The originial schedule from SchedNEM.
- 'genAvSamples'/ 'lineAvSamples': PRAS output matrices (e.g. genAv.available) containing the generator and line availability for each sample and time step.
- 'default_horizon' / 'min_time_after_event': Parameters to determine the simulation windows (and also to determine the minimum time after the last load shedding).
- 'optimisation_window' / 'move_forward': Parameters for the optimisation model (e.g. how many time steps to include in the optimisation and how many time steps to max move forward for each new optimisation).
- 'optimiser_name': The optimiser to use for the re-optimisation (e.g. "HiGHS" or "Gurobi").
- 'input_folder': The folder where the input files for the model are located (e.g. Generator.csv).
- 'DER_parameters' / 'genOpDetails': Parameters for the DERs and generator operation to use in the model (e.g. whether to include unit commitment or ramping constraints).
- 'max_extend_simulations': The maximum number of times to extend the simulation window if load shedding is still happening at the end of the window.
- imperfect_foresight: Boolean indicating whether to use imperfect foresight or perfect foresight within each optimisation window.


"""
function reoptimise(df_expectation, sys, res_input, genAvSamples, lineAvSamples; 
    default_horizon::Int=4, min_time_after_event::Int=4,
    optimisation_window::Int=48, move_forward::Int=24,
    optimiser_name="HiGHS", input_folder::String="",
    DER_parameters=PRASNEM.get_DER_parameters(), 
    genOpDetails=(uc=true, ramping=true, binary=false),
    max_extend_simulations::Int=10,
    imperfect_foresight=true)

    @info "Reoptimising all events with a horizon of > $default_horizon hours to assess system response."

    if optimiser_name == "HiGHS"
        optimiser = HiGHS.Optimizer()
    elseif optimiser_name == "Gurobi"
        optimiser = Gurobi.Optimizer()
    else
        error("Optimiser $(optimiser_name) not recognised. Please select either 'HiGHS' or 'Gurobi'.")
    end

    # Add an ID column for easier references
    df_expectation.id = 1:DataFrames.nrow(df_expectation)
    N = length(sys.timestamps)
    Nregions = length(sys.regions.names)
    Nsamples = size(genAvSamples, 3)

    # Initialise the output
    # TODO: Make this a sparse object (e.g. via SparseArrayKit) to save memory!
    load_shedding_output = zeros(Int, Nregions, N, Nsamples);

    # Initialise a counter for the total amount of (extended) simulations (for reporting at the end)
    total_number_of_simulations = 0
    total_number_of_extended_simulations = 0

    # Calculate all the timestamps where an outage or repair was happening in the samples
    statechange_times = PRASNEM.calculate_state_change_times(genAvSamples; lineAvSamples=lineAvSamples)

    # Calculate all the simulation times
    all_simulation_times = get_all_simulation_windows(df_expectation, N, Nsamples, statechange_times; 
        default_horizon=default_horizon, min_time_after_event=min_time_after_event)

    # Print the distribution of the simulation lengths to check if the default horizon is appropriate
    sim_length = [sum(all_simulation_times[i].sim_time; init=0) for i in 1:Nsamples]
    @debug "Distribution of re-simulation time per sample:" *
        "\n  Min: $(minimum(sim_length)), Max: $(maximum(sim_length)), Mean: $(sum(sim_length)/Nsamples) - out of $N timesteps with $Nsamples samples."
    
    @info "Running the re-optimisation with $(imperfect_foresight ? "imperfect" : "perfect") foresight now for $Nsamples samples..."

    # Build the model once for the horizon and then update the parameters for each event
    m = build_operation_model(sys; optimisation_window=optimisation_window, move_forward=move_forward,
        input_folder=input_folder, optimiser=optimiser, DER_parameters=DER_parameters, genOpDetails=genOpDetails)
    
    for sample in 1:Nsamples
        if sample % 10 == 0
            println("     $sample/$Nsamples")
        end

        # Run the re-optimisation for this sample for all the simulation windows and save the load shedding results
        for j in 1:length(all_simulation_times[sample].start_idxs)
            start_idx = all_simulation_times[sample].start_idxs[j]
            end_idx = all_simulation_times[sample].end_idxs[j]

            flag_merged_with_next = false
            total_number_of_simulations += 1

            if imperfect_foresight
                temp = run_reoptimisation_imperfect_foresight(m, res_input, sys, start_idx, end_idx, genAvSamples[:,:,sample], lineAvSamples[:,:,sample], statechange_times[sample])
            else
                temp = run_reoptimisation_perfect_foresight(m, res_input, sys, start_idx, end_idx, genAvSamples[:,:,sample], lineAvSamples[:,:,sample])
            end

            # If model was infeasible, return the model to check the infeasibility
            if typeof(temp) <: JuMP.Model
                println("Model infeasible for sample $sample and simulation window $start_idx - $end_idx")
                return temp
            end
            
            # Now check if load shedding is still happening at the end of the simulation window
            if sum(temp[:, end-min_time_after_event+1:end]) == 0 || (end_idx >= N)
                # Save the load shedding results if no load shedding at the end or at end of the timeseries
                load_shedding_output[:, start_idx:end_idx, sample] = temp
            else
                # Calculate the start of the next simulation window
                next_start = j < length(all_simulation_times[sample].start_idxs) ? all_simulation_times[sample].start_idxs[j+1] : N+1

                # Iteratively extend the simulation window until no load shedding is happening at the end of the window or until the next event is reached
                for k in 1:max_extend_simulations

                    
                    println("        Extending the simulation window for sample $(sample) by $(k * min_time_after_event) hours to check if load shedding continues. Start idx: $start_idx, new end index:  $end_idx -> $(end_idx + k * min_time_after_event). Next event starts at $next_start.")
                    @debug "Extending the simulation window for sample $(sample) by $(k * min_time_after_event) hours to check if load shedding at the end can be avoided. Start idx: $start_idx, new end index: $end_idx -> $(end_idx + k * min_time_after_event). Next event starts at $next_start."
                    
                    # Calculate the new end index by extending the current end index by the min_time_after_event
                    end_idx_extended = min(end_idx + k * min_time_after_event, N)
                    
                    if end_idx_extended >= next_start
                        if j < length(all_simulation_times[sample].start_idxs) # If there still is a next event, update the next event to include the current horizon
                            @debug "Extended end index $(end_idx_extended) exceeds the next event start index $(next_start). Updating the next event to start at $(start_idx) to combine the two events."
                            # If the extended end index exceeds the next start, update the next window
                            all_simulation_times[sample].start_idxs[j+1] = start_idx
                            flag_merged_with_next = true
                            println("        Extended end index $(end_idx_extended) exceeds the next event start index $(next_start). Merging the current simulation window with the next event by updating the next event to start at $(start_idx).")
                            break # Break the current loop since the next event will now include the current window
                        end
                    end


                    # Update the counter for the total amount of extended simulations
                    total_number_of_extended_simulations += 1 

                    # Then re-run the re-optimisation with the extended end index
                    if imperfect_foresight
                        temp = run_reoptimisation_imperfect_foresight(m, res_input, sys, start_idx, end_idx_extended, genAvSamples[:,:,sample], lineAvSamples[:,:,sample], statechange_times[sample])
                    else
                        temp = run_reoptimisation_perfect_foresight(m, res_input, sys, start_idx, end_idx_extended, genAvSamples[:,:,sample], lineAvSamples[:,:,sample])
                    end
                    
                    if typeof(temp) <: JuMP.Model 
                        println("Model infeasible for sample $sample and simulation window $start_idx - $end_idx_extended")
                        return temp
                    end

                    # Check if load shedding is still happening at the end of the extended simulation window
                    if sum(temp[:, end-min_time_after_event+1:end]) == 0 || (end_idx_extended == N)
                        # Save the load shedding results if no load shedding at the end or at end of the timeseries
                        load_shedding_output[:, start_idx:end_idx_extended, sample] = temp
                        println("      Done. New window ended at $(end_idx_extended).")
                        break
                    end
                end # End of loop to extend the simulation window

                if (sum(temp[:, end-min_time_after_event+1:end]) > 0) && (!flag_merged_with_next) # If we extended and didnt merge with the next sample
                    @warn "Even after extending the simulation window up to $(end_idx_extended), load shedding is still occurring at the end of the window ($(end_idx_extended)) for sample $(sample). Consider increasing the 'max_extend_simulations'-parameter or checking the model formulation."
                end
            
            end # End of check for load shedding at the end of the simulation window
        
        end # End of loop through simulation windows for this sample
    
    end # End of loop through samples

    @info "Re-optimisation completed.\n     Total number of simulations: $(total_number_of_simulations)\n     + extended simulations: $(total_number_of_extended_simulations)."
   
    return load_shedding_output
end
