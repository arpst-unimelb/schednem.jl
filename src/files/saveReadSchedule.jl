"""
    save_schedule(schedule::SchedData, filename::String)

Saving the SchedData to a file.

"""
function save_schedule(schedule::SchedData, filename::String)

    if isfile(filename)
        @warn "File already exists and will be overwritten: $filename"
    end

    if !isdir(dirname(filename))
        mkpath(dirname(filename))
        @debug "Created directory: $(dirname(filename))"
    end
    
    # Save the schedule to an HDF5 file
    HDF5.h5open(filename, "w") do f

        attrs = HDF5.attributes(f)
        attrs["N"] = get_params(schedule)[1]
        attrs["Ngens"] = get_params(schedule)[2]
        attrs["Nstors"] = get_params(schedule)[3]
        attrs["Ngenstors"] = get_params(schedule)[4]
        attrs["Ndrs"] = get_params(schedule)[5]
        attrs["Nregions"] = get_params(schedule)[6]

        for key in string.(get_keys(schedule))
            val = get_value(schedule, Symbol(key))
            dset = HDF5.create_dataset(f, key, Int, size(val))
            HDF5.write(dset, val)
        end
    end

end

"""
    read_schedule(filename::String)

Reads an hdf5 file, and returns a SchedData object.

"""
function read_schedule(filename::String)
    # Read the schedule from an HDF5 file and return it as a dictionary
    if !isfile(filename)
        error("File not found: $filename")
    end

    sched = HDF5.h5open(filename, "r") do f
        attrs = HDF5.attributes(f)
        # Ensure backward compatibility with files that do not have Nregions attribute (i.e., created before the addition of regional dimension in the SchedData structure)
        if !("Nregions" in keys(attrs))
            sched = SchedData((HDF5.read(attrs["N"]), HDF5.read(attrs["Ngens"]), HDF5.read(attrs["Nstors"]), HDF5.read(attrs["Ngenstors"]), HDF5.read(attrs["Ndrs"]), 12))
            for key in string.(get_keys(sched))
                if key == "shortfall"
                    # For backward compatibility, if shortfall data is not present in the file, initialize it with zeros
                    set_value!(sched, Symbol(key), zeros(Int, 12, get_params(sched)[1]))
                else
                    set_value!(sched, Symbol(key), HDF5.read(f, key))
                end
            end
        else
            # New file format with Nregions attribute
            sched = SchedData((HDF5.read(attrs["N"]), HDF5.read(attrs["Ngens"]), HDF5.read(attrs["Nstors"]), HDF5.read(attrs["Ngenstors"]), HDF5.read(attrs["Ndrs"]), HDF5.read(attrs["Nregions"])))
            for key in string.(get_keys(sched))
                set_value!(sched, Symbol(key), HDF5.read(f, key))
            end
        end

        sched
    end

    return sched
end
