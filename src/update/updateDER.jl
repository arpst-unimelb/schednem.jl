




function disable_VPP(m, sys)

    idxs_vpp = findall(x -> x == "VPP", sys.storages.categories)

    if !isempty(idxs_vpp)
        @info "Disabling VPP storage units with indices $idxs_vpp by setting their capacities to zero."
        set_parameter_value.(m[:stor_charge_cap][idxs_vpp,:], 0.0)
        set_parameter_value.(m[:stor_discharge_cap][idxs_vpp,:], 0.0)
        set_parameter_value.(m[:stor_energy_cap][idxs_vpp,:], 0.0)
    else
        @info "No VPP storage units found to disable."
    end

end