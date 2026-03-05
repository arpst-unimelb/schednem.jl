"""
    updateLineCapacity!(m, sys, start_index::Int, lineAv::Matrix)

Updates the line capacity parameters in the optimization model based on the provided line availability (lineAv) matrix.
Note that the lineAv matrix should be from one specific sample (not the whole object from PRAS).
"""
function updateLineCapacity!(m, sys, start_index::Int, lineAv::Matrix)

    # Update the line capacity parameters in the model based on the provided lineAv matrix
    N = m[:N]

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