using Test
include("main.jl")
using CSV, DataFrames

global saveplot = true

const DIR     = raw"C:\codestuff\PBS\HeGithub"
const PLOTDIR = raw"C:\codestuff\PBS\plots_scale_cap100"
isdir(PLOTDIR) || mkpath(PLOTDIR)

# the 4 instances that hit the 3000-iteration cap — first 100 iterations only
const TARGETS = [
    ("Medium_scale_RL_6_37_13_22_formatted.csv", "6x37_22_13_8"),
    ("Medium_scale_RL_6_37_13_22_formatted.csv", "6x37_22_13_94"),
    ("Large_scale_RL_10_61_21_61_formatted.csv", "10x61_61_21_64"),
    ("Large_scale_RL_10_61_21_61_formatted.csv", "10x61_61_21_89"),
]
const CAP = 100

parse_coords(s) = begin
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

const DFS = Dict{String,DataFrame}()
getdf(f) = get!(DFS, f) do
    d = CSV.read(joinpath(DIR, f), DataFrame); rename!(d, strip.(names(d))); d
end

for (fname, id) in TARGETS
    df = getdf(fname)
    row = first(filter(r -> string(r[:id]) == id, eachrow(df)))
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
    println("=== $id  grid=$(Lx)x$(Ly)  #esc=$(length(esc))  #loads=$(length(itm))  cap=$CAP ===")
    _, _, ms = main(st, items, escorts, IO_coords, id, outdir;
        n = length(items), no_cores = 1, mode = "continue", mm = "lm", iter_cap = CAP)
    println("$id : iters=$ms  escort_relocs=$(ESCORT_RELOCS[])  -> $outdir")
end
println("Done.")
