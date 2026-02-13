# A collection of analysis and plotting functions for visualizing the results of the optimization model.

"""
    plot_timeseries_results(m, sys; region::Int=1)

Function to plot the time series results of the optimization model for a specific region.

TODO: Add imports/exports
TODO: Add option for plotting an aggregate of multiple regions

"""
function plot_timeseries_results(m, sys; region::Int=1)

    dem = value.(m[:dem][region, :])

    all_gens_in_region = sys.region_gen_idxs[region]
    idx_pv = findall(n -> n in ["RoofPV", "LargePV"], sys.generators.categories[all_gens_in_region])
    idx_w = findall(n -> n in ["Wind"], sys.generators.categories[all_gens_in_region])
    ixd_gas = findall(n -> n in ["CCGT", "OCGT"], sys.generators.categories[all_gens_in_region])
    idx_other = setdiff(all_gens_in_region, vcat(idx_pv, idx_w, ixd_gas))

    gen_pv = sum(value.(m[:p_gen][idx_pv, :]), dims=1)[:]
    gen_w = sum(value.(m[:p_gen][idx_w, :]), dims=1)[:]
    gen_gas = sum(value.(m[:p_gen][ixd_gas, :]), dims=1)[:]
    gen_other = sum(value.(m[:p_gen][idx_other, :]), dims=1)[:]

    if m[:Nstors] > 0
    stor_discharge = sum(value.(m[:p_stor_discharge][sys.region_stor_idxs[region], :]), dims=1)[:]
        stor_charge = sum(value.(m[:p_stor_charge][sys.region_stor_idxs[region], :]), dims=1)[:]
    else
        stor_discharge = zeros(m[:N])
        stor_charge = zeros(m[:N])
    end

    if m[:Ngenstors] > 0
        genstor_discharge = sum(value.(m[:p_genstor_discharge][sys.region_genstor_idxs[region], :]), dims=1)[:]
        genstor_charge = sum(value.(m[:p_genstor_charge][sys.region_genstor_idxs[region], :]), dims=1)[:]
    else
        genstor_discharge = zeros(m[:N])
        genstor_charge = zeros(m[:N])
    end

    if m[:Ndrs] > 0
        idxs_dsp = intersect(findall(n -> n == "DSP", sys.demandresponses.categories), sys.region_dr_idxs[region])
        idxs_ev = intersect(findall(n -> n == "EV", sys.demandresponses.categories), sys.region_dr_idxs[region])
        drs_dsp_borrow = sum(value.(m[:p_borrow_drs][idxs_dsp, :]), dims=1)[:]
        drs_ev_borrow = sum(value.(m[:p_borrow_drs][idxs_ev, :]), dims=1)[:]
        drs_dsp_payback = sum(value.(m[:p_payback_drs][idxs_dsp, :]), dims=1)[:]
        drs_ev_payback = sum(value.(m[:p_payback_drs][idxs_ev, :]), dims=1)[:]
    else
        drs_dsp_borrow = zeros(m[:N])
        drs_ev_borrow = zeros(m[:N])
        drs_dsp_payback = zeros(m[:N])
        drs_ev_payback = zeros(m[:N])
    end

    shed = value.(m[:load_shedding][region, :])

    t = 1:length(dem)
    gen_stack = hcat(gen_other, gen_gas, gen_w, gen_pv, genstor_discharge, stor_discharge, shed, drs_dsp_borrow, drs_ev_borrow)
    charge_stack = hcat(-genstor_charge, -stor_charge, -drs_dsp_payback, -drs_ev_payback)

    comp_labels = ["Coal" "Gas" "Wind" "Solar PV" "Hydro" "Battery" "Load shedding" "DSP" "EV (shifting)"]
    comp_labels[findall(x -> x == 0.0, sum(gen_stack, dims=1)[:])] .= ""

    plt = Plots.areaplot(t, gen_stack ./ 1e3, color=[:black :grey 8 5 10 11 :red :orange :blue], fillalpha = 0.8, labels = comp_labels, lw=0, palette=:Spectral_11)
    Plots.areaplot!(plt, t, charge_stack ./ 1e3, color=[10 11 :orange :blue], fillalpha = 0.8, labels=["" ""], lw=0, palette=:Spectral_11)
    Plots.plot!(plt, t, dem  ./ 1e3; label = "", lw = 1, lc = :black, ls=:dash)
    Plots.plot!(plt, t, (dem .- drs_dsp_borrow .- drs_ev_borrow) ./ 1e3; label = "Net Demand", lw = 2, lc = :black)
    #Plots.areaplot!(plt, t, gen_pv ./ 1e3; label = "Solar PV", lw = 2, lc = :yellow)

    Plots.xlabel!("Hour")
    Plots.ylabel!("Power [GW]")
    Plots.title!("Region: $region | ENS: $(round(sum(shed))) MWh")

    return plt

end
