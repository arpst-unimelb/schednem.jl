"""
    updateGenAvailabilityFullHorizon!(m, genAv::Matrix, start_index::Int)

Updates the generator capacity parameters in the whole optimization model based on the provided generator availability (genAv) matrix.
Note that the genAv matrix should be from one specific sample (not the whole object from PRAS).
"""
function updateGenAvailabilityFullHorizon!(m, genAv::Matrix, start_index::Int; end_index::Int=0)

    # Update the generator capacity parameters in the model based on the provided genAv matrix
    N = m[:N]
    if end_index > 0
        N = end_index - start_index + 1
    end

    genAv_slice = genAv[:, start_index .+ (1:N) .- 1]

    set_parameter_value.(m[:gen_cap][:, 1:N], parameter_value.(m[:gen_cap][:, 1:N]) .* genAv_slice)

    genFailures = genAv_slice[:,2:end] - genAv_slice[:,1:end-1] # This will be -1 for generators that fail and 1 for generators that recover compared to the previous time step
    set_parameter_value.(m[:gen_fail][:, 1:N], hcat((genAv_slice[:,1] .== 0),(genFailures .== -1)))

    return m
end

"""
    updateGenAvailabilityStep!(m, start_index_model::Int, genAv::Matrix, step::Int)

Updates the generator capacity parameters in the optimization model for a specific time step based on the provided generator availability (genAv) matrix.
Note that the genAv matrix should be from one specific sample (not the whole object from PRAS).

Parameters:
- `m`: The optimization model.
- 'start_index_model': The index in the optimisation model to start updating the gen availability from.
- `genAv`: A matrix containing the generator availability values for each generator and time step.
- `step`: The specific time step within genAv to use for updating the model parameters.

"""
function updateGenAvailabilityStep!(m, genAv::Matrix, step::Int; start_index_model::Int=1)

    # Get the generator availability for the specific step
    genAv_step = genAv[:, step]
    set_parameter_value.(m[:gen_cap][:, start_index_model:end], parameter_value.(m[:gen_cap][:, start_index_model:end]) .* genAv_step)

    if m[:genOpDetails].uc || m[:genOpDetails].ramping
        genFailures_step = genAv_step - genAv[:, max(1, step - 1)] # This will be -1 for generators that fail and 1 for generators that recover compared to the previous time step
        if any(genFailures_step .== -1)
            @debug "Generator failure detected in the genAv matrix at step $step. Updating the gen_fail_before and gen_fail parameters to disable ramping constraints for the failing generators."
            # For the time steps after the failure, set gen_fail to 1 for the failing generators to disable ramping constraints in those time steps as well (assuming the generator remains failed)
            set_parameter_value.(m[:gen_fail][:, start_index_model], (genFailures_step .== -1))
        end
    end

    return m

end