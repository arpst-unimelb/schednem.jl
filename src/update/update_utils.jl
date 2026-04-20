"""
  updateParameters_gon_feasible!(m)

This function is to make sure that gon_initial fits to the preceeding stup/shdw status before to avoid infeasibility in the first time step.
This function is especially important if UC is linearised.

Underlying logic for each generator with commitment constraints:
    1. If there was a shut-down before, this has priority - set gon_initial to 0 (off)
    2. Else, if there was a start-up before (but not failed), we set gon_initial to 1 (on)
    3. Else, if there was a failure before, we set gon_initial to 0 (off) and also assume that there was a shut-down to enforce minimum down time
    3. Additionally, always keep only the last indicator (if there are multiple)

"""
function updateParameters_gon_feasible!(m)

    N = m[:N]

    # Get the indices of generators that have commitment constraints
    idxs_rel = findall((m[:up_time] .> 0.0) .|| (m[:down_time] .> 0.0)) 

    if !isempty(idxs_rel)
        for g in idxs_rel

            t_stup = N-m[:down_time][g]+1:N
            t_shdw = N-m[:up_time][g]+1:N

            # Check if at least one shut-down in the relevant time
            if sum(parameter_value.(m[:shdw_before][g,t_shdw])) >= 1.0
                @debug "Generator $g has a shut-down before - Updating initial status to off to avoid infeasibility due to ramping limits in the first time step."
                
                # Set initial status to off
                set_parameter_value.(m[:gon_initial][g], 0.0)

                # Set all relevant start-up indicators to zero
                set_parameter_value.(m[:stup_before][g,t_stup], 0.0) 
                
                # And set only the last shdw indicator to 1 (if there are multiple)
                shdw_idx = findall(parameter_value.(m[:shdw_before][g,t_shdw]) .> 0.0)
                if length(shdw_idx) > 1
                    @debug "Generator $g has multiple shut-down indicators before. Setting all to zero except the last one to avoid infeasibility due to ramping limits in the first time step."
                    set_parameter_value.(m[:shdw_before][g,t_shdw], 0.0)
                    set_parameter_value.(m[:shdw_before][g,t_shdw][shdw_idx[end]], 1.0)
                end
            
            elseif sum(parameter_value.(m[:stup_before][g,t_stup]) .- parameter_value.(m[:gen_fail_before][g,t_stup])) >= 1.0 # Has a start-up before (but not failed), set gon_initial to 1
                @debug "Generator $g has a start-up before - Updating initial status to on to avoid infeasibility due to ramping limits in the first time step."
                
                # Set initial status to on
                set_parameter_value.(m[:gon_initial][g], 1.0)

                # Set all shut-down indicators to zero
                set_parameter_value.(m[:shdw_before][g,end-m[:down_time][g]+1:end], 0.0) # And set all the preceeding shutdown indicators to zero (this is a conservative implementation)
                
                # And set only the last stup indicator to 1 (if there are multiple)
                stup_idx = findall(parameter_value.(m[:stup_before][g,end-m[:up_time][g]+1:end]) .> 0.0)
                if length(stup_idx) > 1
                    @debug "Generator $g has multiple start-up indicators before. Setting all to zero except the last one to avoid infeasibility due to ramping limits in the first time step."
                    set_parameter_value.(m[:stup_before][g,end-m[:up_time][g]+1:end], 0.0)
                    set_parameter_value.(m[:stup_before][g,end-m[:up_time][g]+1:end][stup_idx[end]], 1.0)
                end
            elseif sum(parameter_value.(m[:gen_fail_before][g,t_stup])) >= 1.0 # If there is a failure before, set gon_initial to 0 (off)
                @debug "Generator $g has a failure before - Updating initial status to off to avoid infeasibility due to ramping limits in the first time step."
                
                # Set initial status to off
                set_parameter_value.(m[:gon_initial][g], 0.0)

                # Set all relevant start-up indicators to zero
                set_parameter_value.(m[:stup_before][g,t_stup], 0.0) 
                
                # And set only the last gen_fail indicator to 1 (if there are multiple), and also set it for shutdown (min down time)
                fail_idx = findall(parameter_value.(m[:gen_fail_before][g,t_stup]) .> 0.0)
                if length(fail_idx) > 1
                    @debug "Generator $g has multiple failure indicators before. Setting all to zero except the last one to avoid infeasibility due to ramping limits in the first time step."
                    set_parameter_value.(m[:gen_fail_before][g,t_stup], 0.0)
                    set_parameter_value.(m[:gen_fail_before][g,t_stup][fail_idx[end]], 1.0) 
                end

                # Also set the corresponding shutdown indicator to 1 to enforce minimum down time
                set_parameter_value.(m[:shdw_before][g,t_shdw], 0.0)
                set_parameter_value.(m[:shdw_before][g,t_stup][fail_idx[end]], 1.0) # Need to use t_stup, since fail_idx is refering to the indices of t_stup
            else
                @debug "Generator $g has no start-up or shut-down before - Keeping initial status as is."
            end
        end
    end
    return m
end

# ================================================================================================
# ================================================================================================
"""
    updateParameters_p_gen_feasible!(m)

This function is to make sure that the initial generation values fit to the gon_initial status to avoid infeasibility in the first time step due to ramping limits.
This function is especially important if UC is linearised, since then gon_initial can be non-binary and may not fit to the initial generation values, which can lead to infeasibility due to ramping limits in the first time step.

Underlying logic for each generator with commitment constraints:
    1. If gon_initial is off, set initial generation to zero
    2. Else, if gon_initial is on: max(p_gen_initial, gen_min_limit)
"""
function updateParameters_p_gen_feasible!(m)

    # If unit commitment is also activated, but not binary (i.e. linearised), we need to make sure that the initial generation fits to the gon status, otherwise we may have infeasibility in the first time step due to ramping limits.
    if m[:genOpDetails].uc
        
        # Set initial generation to zero for all generators that are off
        idxs_off = findall(parameter_value.(m[:gon_initial][:]) .== 0.0)
        set_parameter_value.(m[:p_gen_initial][idxs_off], 0.0)

        idxs_on = findall(parameter_value.(m[:gon_initial][:]) .== 1.0)
        # Iterate through the generators that have minimum gen limits
        for (g,t) in eachindex(m[:genMinLimits][idxs_on, :])
            if (t == 1) # If gen has min limit in first time step and is on before
                # Set initial generation to be at least the minimum stable generation for that generator
                gen_min_limit = abs(normalized_coefficient.(m[:genMinLimits][g,1], m[:gon][g,1]))
                gen_initial = parameter_value(m[:p_gen_initial][g])
                if gen_initial < gen_min_limit
                    @debug "Generator $g has a minimum stable generation of $gen_min_limit MW, but the initial generation is set to $gen_initial MW. Updating initial generation to the minimum stable generation to avoid infeasibility due to ramping limits in the first time step."
                    set_parameter_value.(m[:p_gen_initial][g], max.(gen_initial, gen_min_limit))
                end
            end
        end
    end
    
    return m
end
