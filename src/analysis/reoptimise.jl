
"""

Model to re-optimise USE events, to see if the USE changes if storage would be allowed to react.

# Arguments
- `df_expectation`: DataFrame containing the expected system state at the time of the USE event.

- 'tolerance_storage_energy_fixed`: A non-negative scalar specifying the tolerance for fixing the energy levels. The constraints will ensure that the energy levels are greater than or equal to the specified levels minus this tolerance. This is to account for rounding issues in the results from the initial optimisation.

"""
function reoptimise_all_samples(df_expectation, sys, res, genAvSamples; 
    default_horizon::Int=24, min_time_after_event::Int=5, 
    optimiser=HiGHS.Optimizer(), input_folder::String="",
    tolerance_storage_energy_fixed::Float64=1.0)

    # Add an ID column for easier reference
    df_expectation.id = 1:nrow(df_expectation)

    # Initialise the results
    sum_reoptimised = df_expectation.sum
    length_reoptimised = df_expectation.length
    maximum_reoptimised = df_expectation.maximum
    start_reoptimised = df_expectation.start_index
    end_reoptimised = df_expectation.end_index

    # For now just iterate through all events
    # TODO: Filter for events here first to avoid calculating all events
    # TODO: Add DER operation here as well
    # TODO: Find a way to not rebuild the model for each event?
    for event in eachrow(df_expectation)

        # For determining the horizon: Need to check when next event was happening in this sample
        idxs_relevant = findall((df_expectation.sample .== event.sample) .& (df_expectation.start_index .> event.start_index))

        # Find the appropriate horizon
        end_time_max = minimum(vcat(df_expectation[idxs_relevant, :start_index], [8760]))
        horizon = min(max(default_horizon, event.length + min_time_after_event), end_time_max - event.start_index) # Select a horizon that is at least as long as the event, but not too long to avoid overlapping with the next event
        if horizon < event.length
            error("Warning: Horizon selected (", horizon, " hours) is shorter than the event duration (", event.length, " hours). Consider increasing the default horizon or checking the timing of events in this sample.")
        end

        # Create the model for the event
        m_event = build_operation_model(sys; optimisation_window=horizon, move_forward=horizon, input_folder=input_folder, optimiser=optimiser)

        # Update the model parameters to reflect the event conditions (e.g., generator outages, initial state of charge of storage)
        initial_soc_stor = res.stor_energy[:, event.start_index - 1] # Initial state of charge of storage at the start of the event
        initial_soc_genstor = res.genstor_energy[:, event.start_index - 1] # Initial state of charge of genstorage at the start of the event
        m_event = update_model_parameters(m_event, sys, event.start_index, initial_soc_stor, initial_soc_genstor)
        m_event = updateGenCapacity(m_event, sys, event.start_index, genAvSamples.available[:,:,event.sample]) # Update the generation capacity in the model to reflect the outages in the event

        fixing_index = event.start_index + horizon - 1
        final_soc_stor = res.stor_energy[:, fixing_index] # Final state of charge of storage at the end of the event
        final_soc_genstor = res.genstor_energy[:, fixing_index] # Final state of charge of genstorage at the end of the event
        m_event_fixed = add_constraints_EnergyFixed(m_event, horizon, final_soc_stor, final_soc_genstor; tolerance=tolerance_storage_energy_fixed) # Tolerance because of the rounding

        # Optimize the model
        optimize!(m_event_fixed)
        @assert is_solved_and_feasible(m_event_fixed) "Re-optimisation failed for event ID $(event.id) at time step $(event.start_index)."

        # Update the results in the DataFrame
        shedding = value.(m_event_fixed[:load_shedding])[event.region, :]
        sum_reoptimised[event.id] = round(Int,sum(shedding))
        length_reoptimised[event.id] = sum(shedding .> 0)
        maximum_reoptimised[event.id] = round(Int,maximum(shedding))
        if sum(shedding) > 0
            start_reoptimised[event.id] = event.start_index + findfirst(shedding .> 0) - 1 # Find the first time step where shedding is happening and add it to the start index of the event
            end_reoptimised[event.id] = event.start_index + findlast(shedding .> 0) - 1 # Find the last time step where shedding is happening and add it to the start index of the event
        else
            start_reoptimised[event.id] = event.start_index
            end_reoptimised[event.id] = event.start_index
        end
    end

    df_expectation.sum_reoptimised = sum_reoptimised
    df_expectation.length_reoptimised = length_reoptimised
    df_expectation.maximum_reoptimised = maximum_reoptimised
    df_expectation.start_reoptimised = start_reoptimised
    df_expectation.end_reoptimised = end_reoptimised
    
    return df_expectation
end