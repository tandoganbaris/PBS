using Test
include("main.jl")
using CSV
using DataFrames

global saveplot = false

const HEGITHUB_DIR = raw"C:\codestuff\PBS\HeGithub"

function parse_coords(coord_str)
    stripped = replace(coord_str, r"[\{\}]" => "")
    coords = strip.(split(stripped, ">"))
    result = Tuple{Int,Int}[]
    for c in coords
        c = replace(c, "<" => "")
        parts = split(strip(c))
        if length(parts) == 2
            x, y = parse.(Int, parts)
            push!(result, (x+1, y+1))
        end
    end
    return result
end

function solve_one(Lx, Ly, IO_coords, escort_coords, item_coords)
    escorts = Dict{String, escort}()
    for (k, coord) in enumerate(escort_coords)
        escorts["E$k"] = escort("E$k", coord, String[], String[], 0, Dict{Int64,Vector{String}}(), Tuple{Int64,Int64}[])
    end
    items = Dict{String, item}()
    for (k, coord) in enumerate(item_coords)
        items["I$k"] = item("I$k", coord, 0, 0, 1000.0, 1, nothing)
    end
    initialstate = fill("0", Lx, Ly)
    for (key, esc) in escorts; x, y = esc.coords; initialstate[x, y] = key; end
    for (key, itm) in items; x, y = itm.coords; initialstate[x, y] = key; end

    n = length(items)  # all items active from the start — these are one-shot retrieval instances
    t0 = time()
    _, makespandict, ms = main(initialstate, items, escorts, IO_coords, 1,
        raw"C:\codestuff\PBS\plots"; n=n, no_cores=1, mode="continue", mm="lm")
    cpu = time() - t0
    return TOTAL_MOVES[], ms, cpu
end

# ── Warm-up: JIT-compile the LM path before timing anything for real ────────
println("Warming up...")
for _ in 1:5
    solve_one(6, 6, (1, 1), [(1, 1)], [(4, 4)])
end
println("Warm-up done.\n")

for csv_name in ["Mirzaei_vs_RL_formatted.csv"]
    # Mirzaei/Zou (multi-IO) are skipped for now: LM mode doesn't converge on the
    # multi-IO movement path (confirmed via controlled A/B, see conversation) —
    # needs a separate fix before it's safe to run at scale.
    path = joinpath(HEGITHUB_DIR, csv_name)
    df = CSV.read(path, DataFrame)

    moves_out = Union{Int,Missing}[]
    makespan_out = Union{Int,Missing}[]
    cpu_out   = Union{Float64,Missing}[]

    n = nrow(df)
    for (idx, row) in enumerate(eachrow(df))
        Lx_stated, Ly_stated = parse.(Int, split(row[Symbol("Lx x Ly")], 'x'))
        io_pts = parse_coords(row[:IOs])
        escort_coords = parse_coords(row[:Escorts])
        item_coords = parse_coords(row[Symbol("Target Loads")])
        # Some source files (Mirzaei/Zou) have coordinates that reach the
        # stated Lx/Ly itself (i.e. 0-indexed inclusive of Lx), one past what
        # an LxLy-sized matrix can index — size the grid to whatever the
        # instance's own coordinates actually need.
        all_coords = vcat(io_pts, escort_coords, item_coords)
        Lx = max(Lx_stated, maximum(c[1] for c in all_coords))
        Ly = max(Ly_stated, maximum(c[2] for c in all_coords))
        IO_coords = length(io_pts) == 1 ? io_pts[1] : io_pts

        moves, makespan, cpu = try
            solve_one(Lx, Ly, IO_coords, escort_coords, item_coords)
        catch e
            println("\n*** ERROR on $(row[:id]) in $csv_name — skipping ***")
            showerror(stdout, e)
            println()
            missing, missing, missing
        end

        push!(moves_out, moves)
        push!(makespan_out, makespan)
        push!(cpu_out, cpu)

        if idx % 250 == 0 || idx == n
            println("[$csv_name] Processed $idx / $n")
        end
    end

    df[!, "Number of moves Tandogan"] = moves_out
    df[!, "Makespan Tandogan"] = makespan_out
    df[!, "CPU time(s) Tandogan"] = cpu_out
    CSV.write(path, df)
    println("Wrote $path\n")
end

println("All done.")
