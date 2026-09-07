using Test
include("main.jl")
using CSV
using DataFrames

const NO_CORES = Threads.nthreads()
println("Using $NO_CORES threads for parallel execution.")
Threads.nthreads() == 1 && @warn "Running on 1 thread. Start Julia with --threads N for parallel execution."

# Helper function to parse coordinate strings like "{<1 5> <2 6>...}"
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

# ─── What this does ──────────────────────────────────────────────────────────
# 4loadstest1.csv already has heuristic_better1 / heuristic_better2 boolean
# columns from a previous run of test.jl (comparing the heuristic against the
# two baselines). For every row where either flag is true, re-solve that
# instance with saveplot=true so main()'s post-process loop actually writes
# out the per-iteration visualization PNGs — we skip re-solving (and never
# save plots for) the rows where the heuristic wasn't better.
# ──────────────────────────────────────────────────────────────────────────────

@testset "Save plots for heuristic-better rows" begin
    df = CSV.read(raw"C:\codestuff\PBS\4loadstest1.csv", DataFrame)
    rename!(df, strip.(names(df)))

    better = filter(r -> r.heuristic_better1 == true || r.heuristic_better2 == true, df)
    println("$(nrow(better)) / $(nrow(df)) rows flagged heuristic-better — saving plots for these.")

    for row in eachrow(better)
        id_str = row[:id]

        folder_path = joinpath(raw"C:\codestuff\PBS\plots_raviv", string(id_str))
        isdir(folder_path) || mkpath(folder_path)

        size_str = row[Symbol("Lx x Ly")]
        Lx, Ly = parse.(Int, split(size_str, 'x'))

        IO_coords = parse_coords(row[:IOs])
        if length(IO_coords) == 1
            IO_coords = IO_coords[1]
        end
        escort_coords = parse_coords(row[:Escorts])
        item_coords = parse_coords(row[Symbol("Target Loads")])
        retrieval_mode = lowercase(strip(string(row[Symbol("Retrieval Mode")])))

        global saveplot = true   # main()'s post-process loop will now actually save PNGs

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

        try
            main(initialstate, items, escorts, IO_coords, 1, folder_path, n=4, no_cores=NO_CORES, mode=retrieval_mode)
            println("Saved plots for instance: $id_str → $folder_path")
        catch e
            println("\n*** ERROR on instance: $id_str — skipping plot save ***")
            showerror(stdout, e)
            println()
        end
    end

    println("\nDone. Plots written under C:\\codestuff\\PBS\\plots_raviv\\<id>\\")
end
