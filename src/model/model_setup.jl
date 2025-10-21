
#%% ========================================================================================================================
function model_setup(sys; N::Int=24, start_index::Int=1)

    # Get the parameters of the system model
    Nregions = length(sys.regions.names);
    Nlines = length(sys.lines.names);

    line_connection_matrix = zeros(Int, Nlines, Nregions) 
    for i in 1:length(sys.interfaces.regions_from)
        idxs = sys.interface_line_idxs[i]
        line_connection_matrix[idxs, sys.interfaces.regions_from[i]] .= -1
        line_connection_matrix[idxs, sys.interfaces.regions_to[i]] .= 1
    end

    # Create optimization model
    model = Model(HiGHS.Optimizer);
    set_silent(model);

    model[:N] = N  # Save the number of time steps as a parameter
    model[:start_index] = start_index  # Save the start index as a parameter (which time step to start from)
    model[:Nregions] = Nregions  # Save the number of regions as a parameter
    model[:line_connection_matrix] = line_connection_matrix  # Save the line connection matrix as a parameter

    return model
end

#%% ========================================================================================================================
function add_variables(model, sys)

    # Extract system parameters
    Nregions = length(sys.regions.names);
    Ngens = length(sys.generators.names);
    Nstors = length(sys.storages.names);
    Ngenstors = length(sys.generatorstorages.names);
    Nlines = length(sys.lines.names);
    N = model[:N]

    # Define decision variables
    @variable(model, p_gen[1:Ngens, 1:N] >= 0)

    @variable(model, p_stor_charge[1:Nstors, 1:N] >= 0)
    @variable(model, p_stor_discharge[1:Nstors, 1:N] >= 0)
    @variable(model, e_stor[1:Nstors, 1:N] >= 0)

    @variable(model, p_genstor_charge[1:Ngenstors, 1:N] >= 0)
    @variable(model, p_genstor_discharge[1:Ngenstors, 1:N] >= 0)
    @variable(model, e_genstor[1:Ngenstors, 1:N] >= 0)

    @variable(model, p_line[1:Nlines, 1:N])

    @variable(model, load_shedding[1:Nregions, 1:N] >= 0)

    return model
end


#%% ========================================================================================================================
function add_objective(m, sys)

    # Extract system parameters
    N = m[:N]
    Nregions = length(sys.regions.names);

    # Objective: Minimize load shedding
    @objective(m, Min, sum(m[:load_shedding][r,t] * sys.regions.load_shedding_cost[r] for r=1:Nregions, t=1:N))

    return m
end