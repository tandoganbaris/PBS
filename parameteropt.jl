using Test
include("main.jl")
using CSV
using DataFrames
using Statistics

# ─── Config — tweak these to trade off runtime vs. confidence ────────────────
const ALPHAS = [0.0, 0.1, 0.3, 0.5, 0.7, 0.9, 1.0]  # candidate GRASP_ITEM_ALPHA values to try
const NUM_INSTANCES = 100    # how many rows of the CSV to use (nothing = all rows)
const REPS_PER_INSTANCE = 10 # GRASP replicate reps per instance per alpha (only matters if no_cores>1)
const NO_CORES = Threads.nthreads()  # set via julia --threads N or JULIA_NUM_THREADS=N

println("Using $NO_CORES threads.")
Threads.nthreads() == 1 && @warn "Running on 1 thread — GRASP_ITEM_ALPHA has no effect at no_cores=1 (only the randomized _r! functions use it, and those only run when no_cores>1). Start Julia with --threads N."

function parse_coords(coord_str)
    stripped = replace(coord_str, r"[\{\}]" => "")
    coords = strip.(split(stripped, ">"))
    result = Tuple{Int,Int}[]
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

df = CSV.read(raw"C:\codestuff\PBS\bm_4l_10x10_1IO.csv", DataFrame)
rename!(df, strip.(names(df)))
if NUM_INSTANCES !== nothing
    df = df[1:min(NUM_INSTANCES, nrow(df)), :]
end
println("Testing $(nrow(df)) instance(s) x $(length(ALPHAS)) alpha value(s) x $REPS_PER_INSTANCE rep(s) each.")

global saveplot = false

# Per-alpha aggregate results
results = DataFrame(alpha = Float64[], avg_makespan = Float64[], avg_flowtime = Float64[],
                     median_makespan = Float64[], n_failed = Int[])

for α in ALPHAS
    GRASP_ITEM_ALPHA[] = α
    println("\n=== alpha = $α ===")

    makespans = Float64[]
    flowtimes = Float64[]
    n_failed = 0

    for row in eachrow(df)
        id_str = row[:id]
        size_str = row[Symbol("Lx x Ly")]
        Lx, Ly = parse.(Int, split(size_str, 'x'))

        IO_coords = parse_coords(row[:IOs])
        if length(IO_coords) == 1
            IO_coords = IO_coords[1]
        end
        escort_coords = parse_coords(row[:Escorts])
        item_coords = parse_coords(row[Symbol("Target Loads")])

        best_makespan = nothing
        best_flowtime = nothing

        for rep in 1:REPS_PER_INSTANCE
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

            makespan, flowtime = try
                _, makespandict, makespan = main(
                    initialstate, items, escorts,
                    IO_coords, 1, folder_path, n=4, no_cores=NO_CORES
                )
                flowtime = length(makespandict) > 0 ? sum(values(makespandict)) : 0.0
                Float64(makespan), Float64(flowtime)
            catch e
                println("  *** ERROR on instance $id_str (alpha=$α, rep=$rep): $e — skipping rep ***")
                nothing, nothing
            end

            if makespan === nothing
                continue
            end
            if best_makespan === nothing || makespan < best_makespan
                best_makespan = makespan
                best_flowtime = flowtime
            end
        end

        if best_makespan === nothing
            n_failed += 1
        else
            push!(makespans, best_makespan)
            push!(flowtimes, best_flowtime)
        end
    end

    avg_makespan = isempty(makespans) ? Inf : mean(makespans)
    avg_flowtime = isempty(flowtimes) ? Inf : mean(flowtimes)
    med_makespan = isempty(makespans) ? Inf : median(makespans)
    println("alpha=$α  avg_makespan=$avg_makespan  avg_flowtime=$avg_flowtime  median_makespan=$med_makespan  failed=$n_failed/$(nrow(df))")

    push!(results, (α, avg_makespan, avg_flowtime, med_makespan, n_failed))
end

sort!(results, :avg_makespan)
println("\n=== Results (sorted by avg_makespan, best first) ===")
println(results)

CSV.write(raw"C:\codestuff\PBS\parameteropt_grasp_item_alpha_results.csv", results)
println("\nBest alpha by avg_makespan: ", results.alpha[1])
println("Wrote full results to parameteropt_grasp_item_alpha_results.csv")
