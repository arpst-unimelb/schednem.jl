"""
    add_objective(m, sys; hydro_parameters, storage_discharging_price=0.1, genData=nothing)
        
Note in objective_parameters:
    - Storage discharging price and transmission flow penalty are in AUD/MWh
    - Spillage penalty, target slack penalty and DR costs are percentages of VoLL_min

"""
function add_objective(m, sys; 
    hydro_parameters=PRASNEM.get_hydro_parameters(),
    objective_parameters=(storage_discharging_price=0.1, transmission_flow_penalty=0.1, 
            spillage_penalty=0.8, target_slack_penalty=0.8, dsp_rr_cost=0.95),
    genData=nothing)

    # Extract system parameters
    N = m[:N]
    Nregions = m[:Nregions]
    Ngens = m[:Ngens]
    Nstors = m[:Nstors]
    Ngenstors = m[:Ngenstors]
    Ndrs = m[:Ndrs]
    Ninterfaces = m[:Ninterfaces]

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
        if voll_min >= voll_max
            @warn "VoLL_min should be less than VoLL_max to ensure load shedding cost decreases over time to obtain greedy dispatch. Setting VoLL_min to 99% of VoLL_max."
            voll_min = voll_max * 0.99
        end
    else
        voll_min = voll_max * 0.99
    end
    m[:VoLL_min] = voll_min # Save VoLL_min as a parameter to be used in the objective and constraints

    if voll_min * 0.99 <= maximum(gens_cost)
        @error "VoLL_min * 0.99 should be greater than the maximum generator cost to ensure load shedding and genstor penalty are always more expensive than generation. Please update voll_min in system attributes."
    end

    
    # Extract the demand response costs from the system attributes (else zero)
    if Ndrs > 0
        drs_ids = parse.(Int, reduce(hcat, split.(sys.demandresponses.names, "_"))[1,:])
        m[:drs_rr_cost] = voll_min * objective_parameters.dsp_rr_cost
        drs_cost = fill(m[:drs_rr_cost], Ndrs) # Default DR cost is set to VoLL_min * dsp_rr_cost to ensure DR is always preferred over load shedding 
        for i in 1:Ndrs
            if haskey(sys.attrs, "cvar_dr_" * string(drs_ids[i]))
                drs_cost[i] = min(drs_cost[i], parse(Float64, sys.attrs["cvar_dr_" * string(drs_ids[i])]))
            end
        end
    end

    # Operational costs
    @expression(m, operating_cost, sum(m[:p_gen][g,t] * gens_cost[g] for g=1:Ngens, t=1:N))

    # Unit commitment costs
    if m[:genOpDetails].uc
        @expression(m, startup_cost, sum(m[:stup][g,t] * genData.start_up_cost[m[:id_gens][g]] for g=1:Ngens, t=1:N; init=zero(1)))
        @expression(m, shutdown_cost, sum(m[:shdw][g,t] * genData.shut_down_cost[m[:id_gens][g]] for g=1:Ngens, t=1:N; init=zero(1)))
        operating_cost += startup_cost + shutdown_cost
    end

    @expression(m, storage_discharging_cost, sum(m[:p_stor_discharge][s,t] * objective_parameters.storage_discharging_price for s=1:Nstors, t=1:N; init=zero(1)))
    @expression(m, genstorage_discharging_cost, sum(m[:p_genstor_discharge][gs,t] * hydro_parameters["hydro_discharging_cost"] for gs=1:Ngenstors, t=1:N; init=zero(1)))
    @expression(m, genstorage_spillage_penalty, sum(m[:genstor_spillage][gs,t] * voll_min * objective_parameters.spillage_penalty for gs=1:Ngenstors, t=1:N; init=zero(1)))
    @expression(m, genstorage_target_slack_penalty, sum(m[:genstor_target_slack][gs] * voll_min * objective_parameters.target_slack_penalty for gs=1:Ngenstors; init=zero(1)))
    
    
    @expression(m, operating_cost_drs, sum(m[:p_borrow_drs][drs,t] * drs_cost[drs] for drs=1:Ndrs, t=1:N; init=zero(1)))
    @expression(m, load_shedding_cost, sum(m[:load_shedding][r,t] * (voll_max - (voll_max - voll_min)/(N-1) * (t-1)) for r=1:Nregions, t=1:N))
    
    # Transmission flow penalty to avoid excessive usage for low cost benefit
    @expression(m, flow_penalty, sum((m[:p_interface_forward][l,t] + m[:p_interface_backward][l,t]) * objective_parameters.transmission_flow_penalty for l=1:Ninterfaces, t=1:N))

    # Objective: Minimize operating cost
    @objective(m, Min, operating_cost +
        storage_discharging_cost + genstorage_discharging_cost + 
        operating_cost_drs + load_shedding_cost +
        flow_penalty + genstorage_spillage_penalty + genstorage_target_slack_penalty)

    return m
end