using Test
include("main.jl")
using CSV
using DataFrames

global saveplot = true

const HEGITHUB_DIR = raw"C:\codestuff\PBS\HeGithub"
const PLOTDIR      = raw"C:\codestuff\PBS\plots_zou10"
isdir(PLOTDIR) || mkpath(PLOTDIR)

# 10 nesc=1 instances that stall (hit the iteration cap) after the #2/#3 fixes
const IDS = ["6x6_1_2_3","6x6_1_2_7","6x6_1_2_8","6x6_1_2_9","6x6_1_2_11",
             "6x6_1_2_12","6x6_1_2_18","6x6_1_2_19","6x6_1_2_23","6x6_1_2_27"]

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

df = CSV.read(joinpath(HEGITHUB_DIR, "Zou_vs_RL_formatted.csv"), DataFrame)
rename!(df, strip.(names(df)))

for row in eachrow(df)
    id = string(row[:id])
    id in IDS || continue
    Lx_stated, Ly_stated = parse.(Int, split(row[Symbol("Lx x Ly")], 'x'))
    io_pts        = parse_coords(row[:IOs])
    escort_coords = parse_coords(row[:Escorts])
    item_coords   = parse_coords(row[Symbol("Target Loads")])
    all_coords = vcat(io_pts, escort_coords, item_coords)
    Lx = max(Lx_stated, maximum(c[1] for c in all_coords))
    Ly = max(Ly_stated, maximum(c[2] for c in all_coords))
    IO_coords = length(io_pts) == 1 ? io_pts[1] : io_pts

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
    for (key, itm) in items;   x, y = itm.coords; initialstate[x, y] = key; end

    outdir = joinpath(PLOTDIR, id)
    isdir(outdir) || mkpath(outdir)

    println("=== $id  grid=$(Lx)x$(Ly)  IOs=$io_pts  E=$escort_coords  I=$item_coords")
    _, _, ms = main(initialstate, items, escorts, IO_coords, id, outdir;
        n=length(items), no_cores=1, mode="continue", mm="lm", iter_cap=200)
    println("$id : iterations=$ms  moves=$(TOTAL_MOVES[])  (plots -> $outdir)")
end

println("Done.")
