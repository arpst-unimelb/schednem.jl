#%% ========================================================================================================================
function add_objective(m, sys)

    # Extract system parameters
    N = m[:N]
    Nregions = length(sys.regions.names);
    Ngens = length(sys.generators.names);

    # Extract the generator costs from the system attributes (else zero)
    gen_ids = parse.(Int, reduce(hcat, split.(sys.generators.names, "_"))[1,:])
    gens_cost = zeros(Float64, Ngens)
    for i in 1:Ngens
        if haskey(sys.attrs, "cvar_" * string(gen_ids[i]))
            gens_cost[i] = parse(Float64, sys.attrs["cvar_" * string(gen_ids[i])])
        end
    end
    if sum(gens_cost) == 0.0
        @warn "No generator cost data found in system attributes. All operating cost set to zero."
    end

    # Extract VoLL from system attributes
    # Goal: Storage operation should be greedy, i.e. any discharge should be preferred over load shedding as early as possible
    # - This is achieved by gradually slightly reducing the load shedding cost over the optimisation horizon
    if haskey(sys.attrs, "VoLL_max")
        voll_max = parse(Float64, sys.attrs["VoLL_max"])
    else
        voll_max = parse(Float64, sys.attrs["VoLL"])
    end
    
    if haskey(sys.attrs, "VoLL_min")
        voll_min = parse(Float64, sys.attrs["VoLL_min"])
    else
        voll_min = voll_max * 0.99
    end

    @expression(m, operating_cost, sum(m[:p_gen][g,t] * gens_cost[g] for g=1:Ngens, t=1:N))
    @expression(m, load_shedding_cost, sum(m[:load_shedding][r,t] * (voll_max - (voll_max - voll_min)/(N-1) * (t-1)) for r=1:Nregions, t=1:N))
    @expression(m, storage_discharging_cost, sum(m[:p_stor_discharge][s,t] * 1 for s=1:length(sys.storages.names), t=1:N))
    @expression(m, genstorage_discharging_cost, sum(m[:p_genstor_discharge][gs,t] * 2 for gs=1:length(sys.generatorstorages.names), t=1:N))
    @expression(m, flow_penalty, sum((m[:p_interface_forward][l,t] + m[:p_interface_backward][l,t]) * 1.0 for l=1:length(sys.interfaces.regions_from), t=1:N))

    # Objective: Minimize operating cost
    @objective(m, Min, operating_cost + load_shedding_cost + storage_discharging_cost + genstorage_discharging_cost + flow_penalty)

    return m
end