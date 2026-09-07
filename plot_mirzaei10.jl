using Test
include("main.jl")
using CSV
using DataFrames

global saveplot = true

const HEGITHUB_DIR = raw"C:\codestuff\PBS\HeGithub"
const PLOTDIR      = raw"C:\codestuff\PBS\plots_mirzaei10"
isdir(PLOTDIR) || mkpath(PLOTDIR)

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

df = CSV.read(joinpath(HEGITHUB_DIR, "Mirzaei_vs_RL_formatted.csv"), DataFrame)

for row in eachrow(df)[1:10]
    id = row[:id]
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

    outdir = joinpath(PLOTDIR, string(id))
    isdir(outdir) || mkpath(outdir)

    _, _, ms = main(initialstate, items, escorts, IO_coords, id, outdir;
        n=length(items), no_cores=1, mode="continue", mm="lm", iter_cap=200)
    println("$id : iterations=$ms  moves=$(TOTAL_MOVES[])  (plots -> $outdir)")
end

println("Done.")
