
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
        parts = split(strip(c))
        if length(parts) == 2
            x, y = parse.(Int, parts)
            push!(result, (x+1, y+1)) # because we use julia
        end
    end
    return result
end

@testset "CSV Rows" begin
    # Read and filter DataFrame
    df_all = CSV.read(raw"C:\codestuff\PBS\bm_4l_10x10_1IO.csv", DataFrame)
    df = filter(r -> r[:id] == "10_12_4_42", df_all)  # keep only the row with this id

    makespan_heuristics = Float64[]
    average_dict_heuristics = Float64[]

    for row in eachrow(df)
        # Parse ID for folder name
        id_str = row[:id]

        # Construct path for plots
        folder_path = joinpath(raw"C:\codestuff\PBS\plots", string(id_str))
        # mkpath(folder_path)  # create folder if needed

        # Parse grid size
        size_str = row[Symbol("Lx x Ly")]
        Lx, Ly = parse.(Int, split(size_str, 'x'))

        IO_coords = parse_coords(row[:IOs])
        escort_coords = parse_coords(row[:Escorts])
        item_coords = parse_coords(row[Symbol("Target Loads")])

        escorts = Dict{String, Any}()
        for (k, coord) in enumerate(escort_coords)
            escorts["E$k"] = escort(
                "E$k", coord, String[], String[], 0,
                Dict{Int64,Vector{String}}(),
                Tuple{Int64,Int64}[]
            )
        end

        items = Dict{String, Any}()
        for (k, coord) in enumerate(item_coords)
            items["I$k"] = item("I$k", coord, 0, 0, 1000.0, 1)
        end

        initialstate = fill("0", Lx, Ly)

        for (key, esc) in escorts
            x, y = esc.coords
            initialstate[x, y] = key
        end

        for (key, itm) in items
            x, y = itm.coords
            initialstate[x, y] = key
        end

        global saveplot = true  # turn on plot saving for debugging
        finalstate, makespandict, makespan = main(
            initialstate, items, escorts, IO_coords[1], 1, folder_path
        )

        push!(makespan_heuristics, makespan)

        dict_values = collect(values(makespandict))
        avg_value = length(dict_values) > 0 ? sum(dict_values) : 0.0
        push!(average_dict_heuristics, avg_value)
    end

    df[!, :makespan_heuristic] = makespan_heuristics
    df[!, :flowtime_heuristic] = average_dict_heuristics

    CSV.write(raw"C:\codestuff\PBS\outputtest.csv", df)
end