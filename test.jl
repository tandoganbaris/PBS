using Test
include("main.jl")
using CSV
using DataFrames

const NO_CORES = Threads.nthreads()  # set via julia --threads N or JULIA_NUM_THREADS=N
println("Using $NO_CORES threads for parallel execution.")
Threads.nthreads() == 1 && @warn "Running on 1 thread. Start Julia with --threads N for parallel execution."
const REPS_PER_ROW = NO_CORES > 1 ? 5 : 1

# Helper function to parse coordinate strings like "{<1 5> <2 6>...}"
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
    df =  CSV.read(raw"C:\codestuff\PBS\bm_4l_10x10_1IO.csv", DataFrame)
     #CSV.read(raw"C:\codestuff\PBS\bm_4l_MIO.csv", DataFrame)
   #df = filter(r -> !ismissing(r[:id]) && r[:id] == "10_8_4_1", df)
    rename!(df, strip.(names(df)))

    # Arrays to store heuristics
    makespan_heuristics = Float64[]
    average_dict_heuristics = Float64[]
    

    for row in eachrow(df)
        # Parse ID for folder name
        id_str = row[:id]

        # Construct a new folder path for plots
        folder_path = joinpath(raw"C:\codestuff\PBS\plots", string(id_str))
        isdir(folder_path) || mkpath(folder_path)  # Uncomment if you want to create the folder

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

        global saveplot = false

        best_makespan = nothing
        best_makespandict = nothing

        for rep in 1:REPS_PER_ROW
            # Build escorts fresh each rep: main() mutates this dict in place,
            # so reusing it across reps would carry over state from the previous run.
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

            _, makespandict, makespan = try
                main(
                    initialstate, items, escorts,
                    IO_coords,
                    1,
                    folder_path, n=4, no_cores=NO_CORES
                )
            catch e
                println("\n*** ERROR on instance: $id_str (rep $rep) ***")
                rethrow(e)
            end

            if best_makespan === nothing || makespan < best_makespan
                best_makespan = makespan
                best_makespandict = makespandict
            end
        end

        # 1) The best makespan from your algorithm across reps
        push!(makespan_heuristics, best_makespan)

        # 2) The average of the values in makespandict for the best rep
        dict_values = collect(values(best_makespandict))
        avg_value = length(dict_values) > 0 ? sum(dict_values) : 0.0
        push!(average_dict_heuristics, avg_value)
    end

    # Add new columns to DataFrame
    df[!, :makespan_heuristic] = makespan_heuristics
    df[!, :flowtime_heuristic] = average_dict_heuristics

    # Write updated CSV
    CSV.write(raw"C:\codestuff\PBS\outputtestn4.csv", df)
end
