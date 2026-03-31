"""
    updateLineCapacity!(m, sys, start_index::Int, lineAv::Matrix)

Updates the line capacity parameters in the optimization model based on the provided line availability (lineAv) matrix.
Note that the lineAv matrix should be from one specific sample (not the whole object from PRAS).
"""
function updateLineAvailabilityFullHorizon!(m, sys, start_index::Int, lineAv::Matrix; end_index::Int=0)

    # Update the line capacity parameters in the model based on the provided lineAv matrix
    N = m[:N]
    if end_index > 0
        N = end_index - start_index + 1
    end

    # First get the capacity of the lines and multiply with availability
    lineAv_slice = lineAv[:, start_index .+ (1:N) .- 1]
    linecaps_forward = sys.lines.forward_capacity[:, start_index .+ (1:N) .- 1] .* lineAv_slice
    linecaps_backward = sys.lines.backward_capacity[:, start_index .+ (1:N) .- 1] .* lineAv_slice

    # Then assign to the interface limit parameters in the model
    for r in 1:m[:Nregions]
        set_parameter_value.(m[:interface_limit_forward][r, 1:N], sum(linecaps_forward[sys.interface_line_idxs[r], :], dims=1)[:])
        set_parameter_value.(m[:interface_limit_backward][r, 1:N], sum(linecaps_backward[sys.interface_line_idxs[r], :], dims=1)[:])
    end

    return m
end

"""
    updateLineAvailabilityStep!(m, sys, start_index_model::Int, lineAv::Matrix, step::Int)

Updates the interface limits in the model for start_index_model:N based on the line availability at a specific time step (step) from the lineAv matrix.

"""
function updateLineAvailabilityStep!(m, sys, lineAv::Matrix, step::Int; start_index_model::Int=1, end_index::Int=0)
    # Update the line capacity parameters in the model based on the provided lineAv matrix
    N = m[:N]
    if end_index > 0
        N = end_index - step + 1 - (start_index_model - 1)
    end

    # First get the capacity of the lines and multiply with availability
    lineAv_slice = lineAv[:, step]
    linecaps_forward = sys.lines.forward_capacity[:, step .+ (start_index_model:N) .- start_index_model] .* lineAv_slice
    linecaps_backward = sys.lines.backward_capacity[:, step .+ (start_index_model:N) .- start_index_model] .* lineAv_slice

    # Then assign to the interface limit parameters in the model
    for r in 1:m[:Nregions]
        set_parameter_value.(m[:interface_limit_forward][r, start_index_model:N], sum(linecaps_forward[sys.interface_line_idxs[r], :], dims=1)[:])
        set_parameter_value.(m[:interface_limit_backward][r, start_index_model:N], sum(linecaps_backward[sys.interface_line_idxs[r], :], dims=1)[:])
    end

    return m
end