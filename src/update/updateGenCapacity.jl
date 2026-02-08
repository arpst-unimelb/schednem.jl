"""
    updateGenCapacity(m, sys, start_index::Int, genAv::Matrix)

Updates the generator capacity parameters in the optimization model based on the provided generator availability (genAv) matrix.
Note that the genAv matrix should be from one specific sample (not the whole object from PRAS).
"""
function updateGenCapacity(m, sys, start_index::Int, genAv::Matrix)

    # Update the generator capacity parameters in the model based on the provided genAv matrix
    N = m[:N]

    gencaps = sys.generators.capacity[:, start_index .+ (1:N) .- 1]
    genAv_slice = genAv[:, start_index .+ (1:N) .- 1]

    set_parameter_value.(m[:gen_cap][:, 1:N], gencaps .* genAv_slice)

    return m
end