include("main.jl")
using CSV, DataFrames, Statistics

global saveplot = false
const DIR      = raw"C:\codestuff\PBS\HeGithub"
const ITER_CAP = 3000
const FILE     = "Large_scale_RL_10_61_21_61_formatted.csv"
const OUT_REACH = 5

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
nearest_n_escorts(esc, itm, n) = begin
    keep = Set{Int}()
    for ic in itm
        order = sortperm(esc, by = ec -> abs(ec[1] - ic[1]) + abs(ec[2] - ic[2]))
        for k in order[1:min(n, length(order))]; push!(keep, k); end
    end
    [esc[k] for k in sort(collect(keep))]
end
# A* deadlock precheck: can an escort get from each IO 5 cells outward, items as obstacles
function has_deadlock(Lx, Ly, IOc, itms)
    ios = isa(IOc, Tuple) ? [IOc] : collect(IOc)
    bm = zeros(Int, Lx, Ly)
    for io in ios
        iox, ioy = io; gy = ioy + OUT_REACH
        (1 <= iox <= Lx && 1 <= gy <= Ly) || return true
        extra = Set{Tuple{Int,Int}}(itms); delete!(extra, (iox, ioy)); delete!(extra, (iox, gy))
        p, _ = _escort_astar((iox, ioy), (iox, gy), bm, extra, Lx, Ly)
        isempty(p) && return true
    end
    false
end
function run_one(Lx, Ly, IOc, escs, itms)
    escorts = Dict{String,escort}()
    for (k, c) in enumerate(escs); escorts["E$k"] = escort("E$k", c, String[], String[], 0, Dict{Int64,Vector{String}}(), Tuple{Int64,Int64}[]); end
    items = Dict{String,item}()
    for (k, c) in enumerate(itms); items["I$k"] = item("I$k", c, 0, 0, 1000.0, 1, nothing); end
    st = fill("0", Lx, Ly)
    for (key, e) in escorts; x, y = e.coords; st[x, y] = key; end
    for (key, it) in items;  x, y = it.coords; st[x, y] = key; end
    FREEROAM_GRADIENT[] = false; PARK_GATE_RADIUS[] = 2; IO_ORDER_MODE[] = 4
    CANDID_FIX_MODE[] = 0; ESCORT_PROXIMITY_ORDER[] = true; IDLE_FLEX[] = true
    ITEM_LOCK_ENABLED[] = false; FREEZE_ENABLED[] = false; TRACK_CONTRIB[] = false
    t0 = time()
    _, _, ms = main(st, items, escorts, IOc, 1, raw"C:\codestuff\PBS\plots";
        n=length(items), no_cores=1, mode="continue", mm="lm", iter_cap=ITER_CAP)
    (ms, ESCORT_RELOCS[], time() - t0)
end

function go()
    df = CSV.read(joinpath(DIR, FILE), DataFrame); rename!(df, strip.(names(df)))
    let r = first(eachrow(df)); Lx,Ly,IOc,esc,itm = build(r); run_one(Lx,Ly,IOc, nearest_n_escorts(esc,itm,1), itm); end
    println("warmup done\n"); flush(stdout)

    mk = Float64[]; mv = Float64[]; cp = Float64[]; nconv = 0
    fails = NamedTuple[]
    for r in eachrow(df)
        id = string(r[:id])
        Lx, Ly, IOc, esc, itm = build(r)
        escn = nearest_n_escorts(esc, itm, 1)
        ms, moves, cpu = run_one(Lx, Ly, IOc, escn, itm)
        if ms < ITER_CAP
            push!(mk, ms); push!(mv, moves); push!(cp, cpu); nconv += 1
        else
            dl = has_deadlock(Lx, Ly, IOc, itm)
            push!(fails, (id=id, deadlock=dl))
            println("  FAIL $id   deadlock=$dl"); flush(stdout)
        end
    end
    println("\nLarge multi-IO  n=1 (idle-flex on):  solved $nconv/$(nrow(df))")
    println("  mean makespan = $(round(mean(mk),digits=2))   mean moves = $(round(mean(mv),digits=2))   mean cpu = $(round(mean(cp),digits=4))")
    println("  failures: ", fails)
    CSV.write(joinpath(DIR, "n1_large_fails.csv"), DataFrame(fails))
    println("Done.")
end
go()
