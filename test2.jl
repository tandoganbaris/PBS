
using Test
include("main.jl")
using CSV
using DataFrames

function parse_coords(coord_str)
    stripped = replace(coord_str, r"[\{\}]" => "")
    coords = strip.(split(stripped, ">"))
    result = []
    for c in coords
        c = replace(c, "<" => "")
        c = strip(c)
        if !isempty(c)  # Skip empty strings
            parts = split(c)
            if length(parts) == 2
                x, y = parse.(Int, parts)
                push!(result, (x+1, y+1))
            end
        end
    end
    return result
end

#@testset "CSV Rows" begin
    # Read and filter DataFrame
    df_all = CSV.read(raw"C:\codestuff\PBS\bm_4l_MIO.csv", DataFrame)
    #df_all = CSV.read(raw"C:\codestuff\PBS\bm_4l_10x10_1IO.csv", DataFrame)
    
    # Strip whitespace from column names
    rename!(df_all, strip.(names(df_all)))
    df = filter(r -> !ismissing(r[:id]) && r[:id] == "16_8_4_1", df_all)  # keep only the row with this id, skip missing IDs
    #df = filter(r -> !ismissing(r[:id]) && r[:id] == "10_12_4_42", df_all) 
 # Arrays to store heuristics
    makespan_heuristics = Float64[]
    average_dict_heuristics = Float64[]
    

    for row in eachrow(df)
        # Parse ID for folder name
        id_str = row[:id]

        # Construct a new folder path for plots
        folder_path = joinpath(raw"C:\codestuff\PBS\plots", string(id_str))
        mkpath(folder_path)  # Uncomment if you want to create the folder

        # Parse grid size, e.g. "10x10"
        size_str = row[Symbol("Lx x Ly")]
        Lx, Ly = parse.(Int, split(size_str, 'x'))

        # Parse IO, escort, and item coords
        IO_coords = parse_coords(row[:IOs])
        if length(IO_coords) == 1
            IO_coords = IO_coords[1]
        end
        escort_coords = parse_coords(row[:Escorts])
        item_coords = parse_coords(row[Symbol("Target Loads")])

        # Build escorts
        escorts = Dict{String, Any}()
        for (k, coord) in enumerate(escort_coords)
            escorts["E$k"] = escort(
                "E$k", coord, String[], String[], 0,
                Dict{Int64,Vector{String}}(),
                Tuple{Int64,Int64}[]
            )
        end

        # Build items
        items = Dict{String, Any}()
        for (k, coord) in enumerate(item_coords)
            items["I$k"] = item("I$k", coord, 0, 0, 1000.0, 1, nothing)
        end

        # Example placeholder matrix
        initialstate = fill("0", Lx, Ly)

        # Place escorts in initialstate
        for (key, esc) in escorts
            x, y = esc.coords
            initialstate[x, y] = key
        end

        # Place items in initialstate
        for (key, itm) in items
            x, y = itm.coords
            initialstate[x, y] = key
        end
      
            global saveplot = true

        
        
        finalstate, makespandict, makespan = main_savenow(
            initialstate, items, escorts,
            IO_coords,
            1,
            folder_path, n=4  # pass the new folder path and batch size to main
        )

        # 1) The makespan from your algorithm
        push!(makespan_heuristics, makespan)

        # 2) The average of the values in makespandict
        dict_values = collect(values(makespandict))
        avg_value = length(dict_values) > 0 ? sum(dict_values) : 0.0
        push!(average_dict_heuristics, avg_value)
    #end

    # Add new columns to DataFrame
    df[!, :makespan_heuristic] = makespan_heuristics
    df[!, :flowtime_heuristic] = average_dict_heuristics

    CSV.write(raw"C:\codestuff\PBS\outputtest26_6.csv", df)
end