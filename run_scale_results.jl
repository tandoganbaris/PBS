include("main.jl")
using CSV, DataFrames

global saveplot = false

const DIR       = raw"C:\codestuff\PBS\HeGithub"
const ITER_CAP  = 3000
const OUT_REACH = 5          # each IO must be able to reach this many cells outward (into the grid)
const FILES     = [
    "Medium_scale_Yalcin_vs_IP_vs_RL_6_37_1_22_formatted.csv",
    "Large_scale_Yalcin_vs_RL_10_61_1_61_formatted.csv",
    "Medium_scale_RL_6_37_13_22_formatted.csv",
    "Large_scale_RL_10_61_21_61_formatted.csv",
]

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

function build(r)
    Lx_s, Ly_s = parse.(Int, split(r[Symbol("Lx x Ly")], 'x'))
    io  = parse_coords(r[:IOs]); esc = parse_coords(r[:Escorts]); itm = parse_coords(r[Symbol("Target Loads")])
    allc = vcat(io, esc, itm)
    Lx = max(Lx_s, maximum(c[1] for c in allc)); Ly = max(Ly_s, maximum(c[2] for c in allc))
    if any(c -> c[2] > 1, io)
        io  = [rot90ccw(c, Ly) for c in io]
        esc = [rot90ccw(c, Ly) for c in esc]
        itm = [rot90ccw(c, Ly) for c in itm]
        Lx, Ly = Ly, Lx
    end
    (Lx, Ly, length(io) == 1 ? io[1] : io, esc, itm)
end

# For every IO, A* from the IO to the cell OUT_REACH positions straight outward
# (+y, into the grid, since after rotation all IOs sit on the y=1 edge), treating
# the target loads as obstacles. If any IO cannot reach that cell on the initial
# layout, the instance is excluded.
function io_reach_ok(Lx, Ly, IOc, itms)
    ios = isa(IOc, Tuple) ? [IOc] : collect(IOc)
    blockmat = zeros(Int, Lx, Ly)
    for io in ios
        iox, ioy = io
        gy = ioy + OUT_REACH
        (1 <= iox <= Lx && 1 <= gy <= Ly) || return false          # grid too shallow here
        extra = Set{Tuple{Int,Int}}(itms)
        delete!(extra, (iox, ioy)); delete!(extra, (iox, gy))
        path, _ = _escort_astar((iox, ioy), (iox, gy), blockmat, extra, Lx, Ly)
        isempty(path) && return false
    end
    return true
end

function run_one(Lx, Ly, IOc, escs, itms)
    escorts = Dict{String,escort}()
    for (k, c) in enumerate(escs)
        escorts["E$k"] = escort("E$k", c, String[], String[], 0, Dict{Int64,Vector{String}}(), Tuple{Int64,Int64}[])
    end
    items = Dict{String,item}()
    for (k, c) in enumerate(itms)
        items["I$k"] = item("I$k", c, 0, 0, 1000.0, 1, nothing)
    end
    st = fill("0", Lx, Ly)
    for (key, e) in escorts; x, y = e.coords; st[x, y] = key; end
    for (key, it) in items;  x, y = it.coords; st[x, y] = key; end
    FREEROAM_GRADIENT[] = false
    t0 = time()
    _, _, ms = main(st, items, escorts, IOc, 1, raw"C:\codestuff\PBS\plots";
        n=length(items), no_cores=1, mode="continue", mm="lm", iter_cap=ITER_CAP)
    (ms, ESCORT_RELOCS[], time() - t0)
end

# warmup / JIT
let df = CSV.read(joinpath(DIR, FILES[1]), DataFrame)
    rename!(df, strip.(names(df)))
    Lx, Ly, IOc, esc, itm = build(first(eachrow(df)))
    io_reach_ok(Lx, Ly, IOc, itm)
    run_one(Lx, Ly, IOc, esc, itm)
end
println("warmup done\n"); flush(stdout)

for fname in FILES
    path = joinpath(DIR, fname)
    isfile(path * ".bak") || cp(path, path * ".bak")
    df = CSV.read(path, DataFrame)
    rename!(df, strip.(names(df)))
    n = nrow(df)
    mv  = Vector{Any}(missing, n)
    cpv = Vector{Any}(missing, n)
    mkv = Vector{Any}(missing, n)
    nerr = 0; nexcl = 0
    println(">>> $fname  ($n instances)"); flush(stdout)
    for (i, r) in enumerate(eachrow(df))
        try
            Lx, Ly, IOc, esc, itm = build(r)
            if !io_reach_ok(Lx, Ly, IOc, itm)
                mv[i] = "excluded"; cpv[i] = "excluded"; mkv[i] = "excluded"
                nexcl += 1
                continue
            end
            ms, moves, cpu = run_one(Lx, Ly, IOc, esc, itm)
            if ms < ITER_CAP
                mv[i]  = moves
                cpv[i] = round(cpu, digits = 6)
                mkv[i] = ms
            end
        catch e
            nerr += 1
            println("  ERR $(r[:id]): $e")
        end
        (i % 20 == 0 || i == n) && (println("  [$i/$n]"); flush(stdout))
    end
    df[!, "Number of moves Tandogan"] = mv
    df[!, "CPU time(s) Tandogan"]     = cpv
    df[!, "Makespan Tandogan"]        = mkv
    tmp = path * ".tmp"
    CSV.write(tmp, df)
    wrote_ok = false
    try
        cp(tmp, path; force = true)   # overwrite in place (rename fails on Windows if target exists/locked)
        rm(tmp; force = true)
        wrote_ok = true
    catch e
        @warn "could not overwrite $path ($e) -- close it if open, result kept at $tmp"
    end
    conv = count(x -> x isa Number, mkv)
    wrote_ok || println("  (NOT overwritten -- see $tmp)")
    println("  wrote $path   converged $conv/$n   excluded $nexcl   errors $nerr\n"); flush(stdout)
end
println("Done.")
