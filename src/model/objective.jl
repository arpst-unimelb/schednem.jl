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
        println("WARNING: No generator cost data found in system attributes. All operating cost set to zero.")
    end

    @expression(m, operating_cost, sum(m[:p_gen][g,t] * gens_cost[g] for g=1:Ngens, t=1:N))
    @expression(m, load_shedding_cost, sum(m[:load_shedding][r,t] * parse(Float64, sys.attrs["VoLL"]) for r=1:Nregions, t=1:N))
    @expression(m, storage_discharging_cost, sum(m[:p_stor_discharge][s,t] * 2 for s=1:length(sys.storages.names), t=1:N))
    @expression(m, genstorage_discharging_cost, sum(m[:p_genstor_discharge][gs,t] * 1 for gs=1:length(sys.generatorstorages.names), t=1:N))

    # Objective: Minimize operating cost
    @objective(m, Min, operating_cost + load_shedding_cost + storage_discharging_cost + genstorage_discharging_cost)

    return m
end