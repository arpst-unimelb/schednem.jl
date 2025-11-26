
function addGenCostData(sys::PRAS.SystemModel, input_folder::String)

    # First, check if cost data already exists
    if "cvar_1" in keys(sys.attrs)
        return sys  # Cost data already exists
    end

    generator_input_file = joinpath(input_folder, "Generator.csv")
    der_input_file = joinpath(input_folder, "DER.csv")

    # Load generator cost data
    if !isfile(generator_input_file)
        println("WARNING: No generator cost data file provided. All operating cost set to zero.")
        Ngens = length(sys.generators.names);
        for i in 1:Ngens
            sys.attrs["cvar_" * string(i)] = "0"
        end
        return sys
    else
        # Load generator cost data from CSV
        gen_info = CSV.read(generator_input_file, DataFrame)
        for row in eachrow(gen_info)
            sys.attrs["cvar_" * string(row[:id_gen])] = string(round(Int,row[:cvar]))
        end
        return sys
    end
end

function addVollData(sys::PRAS.SystemModel; voll_value::Float64=20300.0)

    sys.attrs["VoLL"] = string(round(Int, voll_value))

    return sys
end