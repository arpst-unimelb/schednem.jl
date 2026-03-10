"""
    save_schedule(schedule::SchedData, filename::String)

Saving the SchedData to a file.

"""
function save_schedule(schedule::SchedData, filename::String)
    
    # Save the schedule to an HDF5 file
    HDF5.h5open(filename, "w") do f

        attrs = HDF5.attributes(f)
        attrs["N"] = get_params(schedule)[1]
        attrs["Ngens"] = get_params(schedule)[2]
        attrs["Nstors"] = get_params(schedule)[3]
        attrs["Ngenstors"] = get_params(schedule)[4]
        attrs["Ndrs"] = get_params(schedule)[5]

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
        sched = SchedData((HDF5.read(attrs["N"]), HDF5.read(attrs["Ngens"]), HDF5.read(attrs["Nstors"]), HDF5.read(attrs["Ngenstors"]), HDF5.read(attrs["Ndrs"])))

        for key in string.(get_keys(sched))
            set_value!(sched, Symbol(key), HDF5.read(f, key))
        end
        
        sched
    end

    return sched
end
