using Test
include("main.jl")
using CSV, DataFrames

global saveplot = true

const HEGITHUB_DIR = raw"C:\codestuff\PBS\HeGithub"
const PLOTDIR      = raw"C:\codestuff\PBS\plots_mirzaei_worst"
isdir(PLOTDIR) || mkpath(PLOTDIR)

# 10 worst Mirzaei instances by (Tandogan makespan - RL makespan)
const IDS = ["6x6_1_2_70","6x6_1_2_83","6x6_1_2_18","6x6_1_2_9","6x6_1_2_51",
             "6x6_1_2_175","6x6_1_2_31","6x6_1_2_147","6x6_1_2_62","6x6_1_2_50"]

function parse_coords(s)
    s = replace(s, r"[\{\}]" => "")
    out = Tuple{Int,Int}[]
    for c in strip.(split(s, ">"))
        c = replace(c, "<" => "")
        p = split(strip(c))
        length(p) == 2 && push!(out, (parse(Int, p[1]) + 1, parse(Int, p[2]) + 1))
    end
    out
end
rot90ccw(c, Ly) = (Ly + 1 - c[2], c[1])

df = CSV.read(joinpath(HEGITHUB_DIR, "Mirzaei_vs_RL_formatted.csv"), DataFrame)
rename!(df, strip.(names(df)))

for row in eachrow(df)
    id = string(row[:id])
    id in IDS || continue
    Lx_s, Ly_s = parse.(Int, split(row[Symbol("Lx x Ly")], 'x'))
    io  = parse_coords(row[:IOs]); esc = parse_coords(row[:Escorts]); itm = parse_coords(row[Symbol("Target Loads")])
    allc = vcat(io, esc, itm)
    Lx = max(Lx_s, maximum(c[1] for c in allc)); Ly = max(Ly_s, maximum(c[2] for c in allc))
    if any(c -> c[2] > 1, io)
        io  = [rot90ccw(c, Ly) for c in io]
        esc = [rot90ccw(c, Ly) for c in esc]
        itm = [rot90ccw(c, Ly) for c in itm]
        Lx, Ly = Ly, Lx
    end
    IO_coords = length(io) == 1 ? io[1] : io

    escorts = Dict{String,escort}()
    for (k, c) in enumerate(esc)
        escorts["E$k"] = escort("E$k", c, String[], String[], 0, Dict{Int64,Vector{String}}(), Tuple{Int64,Int64}[])
    end
    items = Dict{String,item}()
    for (k, c) in enumerate(itm)
        items["I$k"] = item("I$k", c, 0, 0, 1000.0, 1, nothing)
    end
    st = fill("0", Lx, Ly)
    for (key, e) in escorts; x, y = e.coords; st[x, y] = key; end
    for (key, it) in items;  x, y = it.coords; st[x, y] = key; end

    outdir = joinpath(PLOTDIR, id)
    isdir(outdir) || mkpath(outdir)
    println("=== $id  grid=$(Lx)x$(Ly)  IO=$io  E=$esc  I=$itm  (RL mk=$(row[Symbol("Makespan RL (sm)")]))")
    _, _, ms = main(st, items, escorts, IO_coords, id, outdir;
        n=length(items), no_cores=1, mode="continue", mm="lm", iter_cap=120)
    println("$id : iters=$ms moves=$(TOTAL_MOVES[])  -> $outdir")
end
println("Done.")
