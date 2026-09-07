include("main.jl")
using CSV, DataFrames

global saveplot = true

const DIR     = raw"C:\codestuff\PBS\HeGithub"
const PLOTDIR = raw"C:\codestuff\PBS\plots_candid_top10_prox"
isdir(PLOTDIR) || mkpath(PLOTDIR)

# 10 Large multi-IO instances with the most mover-phase candid events
const FNAME = "Large_scale_RL_10_61_21_61_formatted.csv"
const IDS = ["10x61_61_21_27","10x61_61_21_47","10x61_61_21_100","10x61_61_21_72",
             "10x61_61_21_52","10x61_61_21_79","10x61_61_21_97","10x61_61_21_9",
             "10x61_61_21_88","10x61_61_21_21"]
const CAP = 3000

parse_coords(s) = begin
    s = replace(s, r"[\{\}]" => "")
    out = Tuple{Int,Int}[]
    for c in strip.(split(s, ">"))
        c = replace(c, "<" => ""); p = split(strip(c))
        length(p) == 2 && push!(out, (parse(Int, p[1]) + 1, parse(Int, p[2]) + 1))
    end
    out
end
rot90ccw(c, Ly) = (Ly + 1 - c[2], c[1])

df = CSV.read(joinpath(DIR, FNAME), DataFrame); rename!(df, strip.(names(df)))

for id in IDS
    row = first(filter(r -> string(r[:id]) == id, eachrow(df)))
    Lx_s, Ly_s = parse.(Int, split(row[Symbol("Lx x Ly")], 'x'))
    io  = parse_coords(row[:IOs]); esc = parse_coords(row[:Escorts]); itm = parse_coords(row[Symbol("Target Loads")])
    allc = vcat(io, esc, itm)
    Lx = max(Lx_s, maximum(c[1] for c in allc)); Ly = max(Ly_s, maximum(c[2] for c in allc))
    if any(c -> c[2] > 1, io)
        io  = [rot90ccw(c, Ly) for c in io]; esc = [rot90ccw(c, Ly) for c in esc]; itm = [rot90ccw(c, Ly) for c in itm]
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

    FREEROAM_GRADIENT[] = false
    PARK_GATE_RADIUS[]  = 1
    CANDID_FIX_MODE[]   = 0
    outdir = joinpath(PLOTDIR, id)
    isdir(outdir) || mkpath(outdir)
    println("=== $id  grid=$(Lx)x$(Ly)  #esc=$(length(esc))  #loads=$(length(itm)) ===")
    _, _, ms = main(st, items, escorts, IO_coords, id, outdir;
        n = length(items), no_cores = 1, mode = "continue", mm = "lm", iter_cap = CAP)
    println("$id : iters=$ms  escort_relocs=$(ESCORT_RELOCS[])  -> $outdir")
end
println("Done.")
