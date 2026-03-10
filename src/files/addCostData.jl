"""
    addGenCostData(sys::PRAS.SystemModel, input_folder::String)

Note that DR cost data is set to be maximum of Voll_min (even if cost_red > VoLL in DER.csv) to ensure that DR is always preferred over load shedding.

"""
function addGenCostData(sys::PRAS.SystemModel, input_folder::String)

    Ngens = length(sys.generators.names);
    Ndrs = length(sys.demandresponses.names);

    # First, check if cost data already exists
    if length(keys(sys.attrs)) >= (Ngens + Ndrs)
        return sys  # Cost data already exists
    end

    generator_input_file = joinpath(input_folder, "Generator.csv")
    der_input_file = joinpath(input_folder, "DER.csv")

    # Load generator cost data
    if isfile(generator_input_file)
        gen_info = CSV.read(generator_input_file, DataFrames.DataFrame)
        for row in eachrow(gen_info)
            sys.attrs["cvar_" * string(row[:id_gen])] = string(round(Int,row[:cvar]))
        end
    else
        @warn "No generator cost data file provided. All operating cost set to zero."
        for i in 1:Ngens
            sys.attrs["cvar_" * string(i)] = "0"
        end
    end

    if Ndrs > 0 

        # Add VoLL data if not already present (with default values)
        if !haskey(sys.attrs, "VoLL_min")
            sys = addVollData(sys)  
        end

        # Load demand response cost data
        if isfile(der_input_file)
            der_info = CSV.read(der_input_file, DataFrames.DataFrame)
            for row in eachrow(der_info)
                sys.attrs["cvar_dr_" * string(row[:id_der])] = string(min(round(Int,row[:cost_red]), parse(Int, sys.attrs["VoLL_min"])))
            end
        else
            @warn "No demand response cost data file provided. All demand response costs set to VoLL_min."
            for i in 1:Ndrs
                sys.attrs["cvar_dr_" * string(i)] = sys.attrs["VoLL_min"]
            end
        end
    end

    return sys
end

#%% ========================================================================================================================
"""
    addVollData(sys::PRAS.SystemModel; voll_value::Float64=20300.0, voll_min_value::Float64=20200.0)

VoLL_min is a construct to ensure that storage is operated greedily, i.e. load shedding is shifted to later time steps as much as possible. 
This is achieved by gradually slightly reducing the load shedding cost over the optimisation horizon, which ensures that any discharge from storage is preferred over load shedding as early as possible.
"""
function addVollData(sys::PRAS.SystemModel; voll_value::Float64=20300.0, voll_min_value::Float64=20200.0)

    sys.attrs["VoLL"] = string(round(Int, voll_value))
    sys.attrs["VoLL_min"] = string(round(Int, voll_min_value))

    return sys
end