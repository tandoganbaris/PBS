using Test
include("main.jl")
using CSV
using DataFrames

const NO_CORES = Threads.nthreads()  # set via julia --threads N or JULIA_NUM_THREADS=N
println("Using $NO_CORES threads for parallel execution.")
Threads.nthreads() == 1 && @warn "Running on 1 thread. Start Julia with --threads N for parallel execution."

# Parses Python-style "[[x,y],[x,y],...]" coordinate lists. Instances were generated
# 0-indexed for Python, so +1 on both axes to match Julia's 1-indexed grid.
function parse_coord_list(s)
    result = Tuple{Int,Int}[]
    for m in eachmatch(r"\[\s*(\d+)\s*,\s*(\d+)\s*\]", s)
        x = parse(Int, m.captures[1])
        y = parse(Int, m.captures[2])
        push!(result, (x + 1, y + 1))
    end
    return result
end

df = CSV.read(raw"C:\codestuff\PBS\generalization_manifest_17to35.csv", DataFrame)
rename!(df, strip.(names(df)))

bt_makespan = Union{Float64,Missing}[]
bt_flowtime = Union{Float64,Missing}[]

for row in eachrow(df)
    id_str = row[:instance_id]

    Lx, Ly = row[:lx], row[:ly]

    IO_coords = parse_coord_list(row[:outputs_optimal])
    if length(IO_coords) == 1
        IO_coords = IO_coords[1]
    end
    escort_coords = parse_coord_list(row[:escorts_optimal])
    item_coords = parse_coord_list(row[:loads_optimal])

    escorts = Dict{String, escort}()
    for (k, coord) in enumerate(escort_coords)
        escorts["E$k"] = escort(
            "E$k", coord, String[], String[], 0,
            Dict{Int64,Vector{String}}(),
            Tuple{Int64,Int64}[]
        )
    end

    items = Dict{String, item}()
    for (k, coord) in enumerate(item_coords)
        items["I$k"] = item("I$k", coord, 0, 0, 1000.0, 1, nothing)
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

    folder_path = joinpath(raw"C:\codestuff\PBS\plots", string(id_str))
    isdir(folder_path) || mkpath(folder_path)

    global saveplot = false

    makespan_val, flowtime_val = try
        _, makespandict, makespan = main(
            initialstate, items, escorts,
            IO_coords,
            1,
            folder_path, n=4, no_cores=NO_CORES
        )
        flowtime = length(makespandict) > 0 ? sum(values(makespandict)) : 0.0
        Float64(makespan), Float64(flowtime)
    catch e
        println("\n*** ERROR on instance: $id_str — skipping ***")
        showerror(stdout, e)
        println()
        missing, missing
    end

    push!(bt_makespan, makespan_val)
    push!(bt_flowtime, flowtime_val)
end

df[!, :bt_makespan] = bt_makespan
df[!, :bt_flowtime] = bt_flowtime

CSV.write(raw"C:\codestuff\PBS\generalization_eval_17to35_hot_rev2p1.csv", df)
println("Done. Wrote ", nrow(df), " rows to generalization_eval_17to35_hot_rev2p1.csv")
