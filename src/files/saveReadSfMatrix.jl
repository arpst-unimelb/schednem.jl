"""
    saveSfMatrix(SfMatrix, filename)
Functions to save and read SfMatrix in a sparse format (only non-zero entries are saved).
First entry contains the dimensions of the matrix, followed by the indices and values of the non-zero entries.

"""
function saveSfMatrix(SfMatrix, filename)
    coords = findall(SfMatrix .> 0)                # linear indices
    cart = Tuple.(CartesianIndices(SfMatrix)[coords])      # vector of (i,j,k)
    dims = size(SfMatrix)
    I = [c[1] for c in cart]; J = [c[2] for c in cart]; K = [c[3] for c in cart]
    V = SfMatrix[coords]

    I = vcat(dims[1], I) # Add an entry for the dimensions of the matrix
    J = vcat(dims[2], J)
    K = vcat(dims[3], K)
    V = vcat(0, V) # Add a dummy value for the dimensions entry

    DataFrames.DataFrame(I=I, J=J, K=K, V=V) |> CSV.write(filename)
end
"""
    readSfMatrix(filename)

Reads a sparse SfMatrix from a CSV file and reconstructs the full matrix. The CSV file should have columns I, J, K, V where I, J, K are the indices and V is the value.
"""
function readSfMatrix(filename)
    df = CSV.read(filename, DataFrames.DataFrame)
    I = df.I; J = df.J; K = df.K; V = df.V
    dims = (maximum(I), maximum(J), maximum(K))
    SfMatrixOut = zeros(Float64, dims)
    for idx in eachindex(I)
        SfMatrixOut[I[idx], J[idx], K[idx]] = V[idx]
    end
    return SfMatrixOut
end