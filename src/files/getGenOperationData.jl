"""
    getGenOperationData(input_folder::String)

Note: Start up time and shut down time are not considered in the current model.

"""
function getGenOperationData(input_folder::String; MinsInTimestep::Int = 60)

    data = CSV.read(joinpath(input_folder, "Generator.csv"), DataFrames.DataFrame)

    if (sum(data.start_up_time) + sum(data.shut_down_time)) > 0
        @warn "Start-up time and shut-down time are not currently considered in the model. Some parameters seem to be non-zero in the input data, but will not be included in the model."
    end

    # Now create arrays for each of the relevant parameters, indexed by generator ID (with missing IDs filled with zeros)
    maxid = maximum(data.id_gen)

    pmin_by_id = fill(0.0, maxid)
    pmin_by_id[data.id_gen] = data.pmin

    pmax_by_id = fill(0.0, maxid)
    pmax_by_id[data.id_gen] = data.pmax

    rup_by_id = fill(9999.9 * MinsInTimestep, maxid)
    rup_by_id[data.id_gen] = data.rup * MinsInTimestep

    rdw_by_id = fill(9999.9 * MinsInTimestep, maxid)
    rdw_by_id[data.id_gen] = data.rdw * MinsInTimestep

    down_time_by_id = fill(0.0, maxid)
    down_time_by_id[data.id_gen] = [(data.down_time[i] > 0) ? data.down_time[i] : data.up_time[i] for i in 1:length(data.id_gen)] # If down_time is not provided, use up_time as a proxy

    up_time_by_id = fill(0.0, maxid)
    up_time_by_id[data.id_gen] = data.up_time

    start_up_cost_by_id = fill(0.0, maxid)
    start_up_cost_by_id[data.id_gen] = data.start_up_cost

    shut_down_cost_by_id = fill(0.0, maxid)
    shut_down_cost_by_id[data.id_gen] = data.shut_down_cost

    return (id = 1:maxid, pmin = pmin_by_id, pmax = pmax_by_id,
        rup = rup_by_id, rdw = rdw_by_id, 
        down_time = down_time_by_id, up_time = up_time_by_id,
        start_up_cost = start_up_cost_by_id, shut_down_cost = shut_down_cost_by_id)
end