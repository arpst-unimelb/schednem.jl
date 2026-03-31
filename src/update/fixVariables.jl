"""
    fixVariablesBeforeT(m, t::Int)

Fixes all decision variables in the optimization model `m` that correspond to time steps before `t` to their current values. 
This is useful for rolling horizon optimization where we want to fix the decisions for past time steps and only optimize for future time steps.

"""
function fixVariablesBeforeT!(m, t::Int)

    all_times_before_t = string.(collect(1:t-1)) .* "]" # This creates an array of strings like ["1]", "2]", ..., "t-1]"]

    v_to_fix = []
    # Iterate through all variables
    for v in all_variables(m)
        if is_parameter(v) || is_fixed(v)
            continue # Skip POI parameters and already fixed variables. Also skip e_drs variables because their bounds are invoked by DER parameters.
        end

        # Because we split the variable names by "," and the time index is always at the end of the name followed by "]", we can check if the last part of the split name is in the list of times before t to decide whether to fix the variable or not.
        if split(name(v), ",")[end] in all_times_before_t
            push!(v_to_fix, v)
        end
    end

    values_temp = value.(v_to_fix) # Need to save the values - else will throw error
    fix.(v_to_fix, values_temp; force=true) # Fix the variables to their current values

    return m
end


"""
    unfixAllVariables(m)

Unfix all variables that have been fixed before and add their original bounds again.

"""
function unfixAllVariables!(m)

    # Reset all fixed values to be free again (but non-negative)
    for v in all_variables(m)
        if is_parameter(v)
            continue # Skip POI parameters and binary variables
        end

        if is_fixed(v)
            if has_upper_bound(v) && !(name(v)[1:3] == "gon" || name(v)[1:4] in ["stup", "shdw"])
                error("Variable $(name(v)) is fixed and has an upper bound, which is not expected. Please check the variable definitions.")
            end

            # Unfix the variable 
            unfix(v)

            # TODO: If VPP is disabled, fix the VPP storage variables to 0.0.

            if is_binary(v) || (name(v)[1:5] == "e_drs")
                continue
            end

            # Set lower bound to 0
            set_lower_bound(v, 0.0)

            # For the generator on/off status and start-up/shut-down variables, we need to set the upper bound back to 1.0 after unfixing
            if (name(v)[1:3] == "gon" || name(v)[1:4] in ["stup", "shdw"])
                set_upper_bound(v, 1.0)
            end
        end
    end

    return m
end