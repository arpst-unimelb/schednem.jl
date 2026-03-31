"""
    addReserve!(sys; reserves=[890, 705, 600, 168, 251])

Reserve requirements per regions. Default values are based on the 2024 ISP initial reserve requirements for adequacy, with are:
QLD: 890 MW, NSW: 705 MW, VIC: 600 MW, TAS: 168 MW, SA: 251 MW
The reserve requirements are added to the load in each region.

"""
function addReserve!(sys; load_requirements_area=[890, 705, 600, 168, 251])
    #Region	Initial regional reserve requirements (MW)
    #NSW	705
    #QLD	890
    #SA	    251
    #TAS	168
    #VIC	600

    area_region_map = PRASNEM.get_region_area_map("ISP24"; rev=true)

    reserve_requirements_region = zeros(length(sys.regions.names))
    for (area, regions) in area_region_map
        max_load = [maximum(sys.regions.load[r, :]) for r in regions]
        reserve_requirements_region[regions] = load_requirements_area[area] * max_load ./ sum(max_load)
    end

    @debug "Reserve requirements per region (MW): $(round.(Int, reserve_requirements_region)). Adding to system load."

    for r in 1:length(sys.regions.names)
        sys_temp.regions.load[r, :] .+= round(Int, reserve_requirements_region[r])
    end

    return sys
end