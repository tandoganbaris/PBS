include("main.jl")
using CSV, DataFrames, Statistics

global saveplot = false
const DIR      = raw"C:\codestuff\PBS\HeGithub"
const ITER_CAP = 3000
const FILE     = "Large_scale_RL_10_61_21_61_formatted.csv"

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
function build(r)
    Lx_s, Ly_s = parse.(Int, split(r[Symbol("Lx x Ly")], 'x'))
    io  = parse_coords(r[:IOs]); esc = parse_coords(r[:Escorts]); itm = parse_coords(r[Symbol("Target Loads")])
    allc = vcat(io, esc, itm)
    Lx = max(Lx_s, maximum(c[1] for c in allc)); Ly = max(Ly_s, maximum(c[2] for c in allc))
    if any(c -> c[2] > 1, io)
        io  = [rot90ccw(c, Ly) for c in io]; esc = [rot90ccw(c, Ly) for c in esc]; itm = [rot90ccw(c, Ly) for c in itm]
        Lx, Ly = Ly, Lx
    end
    (Lx, Ly, length(io) == 1 ? io[1] : io, esc, itm)
end
function nearest_n_escorts(esc, itm, n)
    keep = Set{Int}()
    for ic in itm
        order = sortperm(esc, by = ec -> abs(ec[1] - ic[1]) + abs(ec[2] - ic[2]))
        for k in order[1:min(n, length(order))]; push!(keep, k); end
    end
    [esc[k] for k in sort(collect(keep))]
end
function run_one(Lx, Ly, IOc, escs, itms; idleflex)
    escorts = Dict{String,escort}()
    for (k, c) in enumerate(escs); escorts["E$k"] = escort("E$k", c, String[], String[], 0, Dict{Int64,Vector{String}}(), Tuple{Int64,Int64}[]); end
    items = Dict{String,item}()
    for (k, c) in enumerate(itms); items["I$k"] = item("I$k", c, 0, 0, 1000.0, 1, nothing); end
    st = fill("0", Lx, Ly)
    for (key, e) in escorts; x, y = e.coords; st[x, y] = key; end
    for (key, it) in items;  x, y = it.coords; st[x, y] = key; end
    FREEROAM_GRADIENT[] = false
    PARK_GATE_RADIUS[]  = 2
    ITEM_LOCK_ENABLED[] = false
    FREEZE_ENABLED[]    = false
    TRACK_CONTRIB[]     = false
    IDLE_FLEX[]         = idleflex
    _, md, ms = main(st, items, escorts, IOc, 1, raw"C:\codestuff\PBS\plots";
        n=length(items), no_cores=1, mode="continue", mm="lm", iter_cap=ITER_CAP)
    (ms, ESCORT_RELOCS[], isempty(md) ? 0 : sum(values(md)))
end

const ONLY = Set(["10x61_61_21_" * s for s in ["38","50","52","89","91","99"]])
df = CSV.read(joinpath(DIR, FILE), DataFrame); rename!(df, strip.(names(df)))
df = df[in.(string.(df[:, :id]), Ref(ONLY)), :]
let r = first(eachrow(df)); Lx,Ly,IOc,esc,itm = build(r); run_one(Lx,Ly,IOc, nearest_n_escorts(esc,itm,4), itm; idleflex=true); end
println("warmup done  (checking $(nrow(df)) instances)\n"); flush(stdout)

for idleflex in (true, false)
    mk = Float64[]; ft = Float64[]; fails = String[]
    for r in eachrow(df)
        Lx, Ly, IOc, esc, itm = build(r)
        escn = nearest_n_escorts(esc, itm, 4)
        ms, mv, f = run_one(Lx, Ly, IOc, escn, itm; idleflex=idleflex)
        if ms < ITER_CAP
            push!(mk, ms); push!(ft, f)
            println("    $(r[:id])  makespan=$ms  flowtime=$f")
        else
            push!(fails, string(r[:id]))
            println("    $(r[:id])  FAIL (iter cap)")
        end
    end
    println(">>> k=4  Large multi-IO   IDLE_FLEX=$idleflex")
    println("    converged $(length(mk))/$(nrow(df))   failures: $fails")
    flush(stdout)
end
println("\nDone.")
