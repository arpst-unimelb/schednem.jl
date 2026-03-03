module SchedNEM

    using JuMP
    import CSV
    import DataFrames
    import HiGHS
    import ParametricOptInterface as POI
    using PRAS
    import Tables
    import Plots

    
    include("utils.jl")
    include("parser/core.jl")
    include("model/core.jl")
    include("update/core.jl")
    include("analysis/core.jl")

end
