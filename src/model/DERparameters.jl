"""
    get_DER_parameters(; case="base")

Function to get predefined DER parameters for different cases.

"""
function get_DER_parameters(; case="base")

    if case == "base"
        return Dict(
            "DSP_flexibility"=>true, # For PRASNEM and SchedNEM
                "DSP_payback_window"=>24, 
                "DSP_interest"=>-1.0, 
                "DSP_max_energy_factor"=>2.0, # This is to define the capacity of the DSP in each time step (e.g. the "storage energy capacity" of the DSP)
                "DSP_payback_before_borrowing"=>false, # Only relevant for SchedNEM
                "DSP_limit_energy_per_window"=>Dict("enabled" => true,
                    "max_energy_time_window" => 24, 
                    "max_energy_per_window_per_capacity" => 3.0, 
                    "limits_on_price_bands" => [0] 
                    ),
            "EV_charge_flexibility"=>false, # For PRASNEM and SchedNEM
                "EV_payback_window"=>24, 
                "EV_interest"=>0.0, 
                "EV_max_energy_factor"=>100.0, # This is to define the capacity of the DSP in each time step (e.g. the "storage energy capacity" of the EV)
                "EV_payback_before_borrowing"=>false, # Only relevant for SchedNEM
                "EV_limit_energy_per_window"=>Dict("enabled" => false,
                    "max_energy_time_window" => 24, 
                    "max_energy_per_window_per_capacity" => 24.0
                    ),
            "VPP_flexibility"=>true, # Only relevant for SchedNEM (if false, VPP storage units are disabled by setting their capacities to zero) 
            )
    else
        error("DER parameter case not recognised.")
    end

end