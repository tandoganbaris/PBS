include("main.jl")
using CSV, DataFrames

global saveplot = false

const DIR      = raw"C:\codestuff\PBS\HeGithub"
const ITER_CAP = 1000
const FILES    = ["Gue", "Mirzaei", "Yalcin", "Zou"]

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

# 90 deg CCW rotation so an IO stuck at higher y lands on the y=1 edge the heuristic
# is built for. Only applied when the instance actually has such an IO.
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
    (ms, TOTAL_MOVES[], time() - t0)
end

# warmup / JIT
let df = CSV.read(joinpath(DIR, "Gue_vs_RL_formatted.csv"), DataFrame)
    rename!(df, strip.(names(df)))
    Lx, Ly, IOc, esc, itm = build(first(eachrow(df)))
    run_one(Lx, Ly, IOc, esc, itm)
end
println("warmup done\n"); flush(stdout)

for fname in FILES
    path = joinpath(DIR, "$(fname)_vs_RL_formatted.csv")
    isfile(path * ".bak") || cp(path, path * ".bak")
    df = CSV.read(path, DataFrame)
    rename!(df, strip.(names(df)))
    n = nrow(df)
    mv  = Vector{Union{Int,Missing}}(missing, n)
    cpv = Vector{Union{Float64,Missing}}(missing, n)
    mkv = Vector{Union{Int,Missing}}(missing, n)
    nerr = 0
    println(">>> $fname  ($n instances)"); flush(stdout)
    for (i, r) in enumerate(eachrow(df))
        try
            Lx, Ly, IOc, esc, itm = build(r)
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
        (i % 500 == 0 || i == n) && (println("  [$i/$n]"); flush(stdout))
    end
    df[!, "Number of moves Tandogan"] = mv
    df[!, "CPU time(s) Tandogan"]     = cpv
    df[!, "Makespan Tandogan"]        = mkv
    tmp = path * ".tmp"
    CSV.write(tmp, df)
    wrote_ok = false
    try
        Base.Filesystem.rename(tmp, path)   # atomic; fails if target is locked (e.g. open in Excel)
        wrote_ok = true
    catch e
        @warn "could not overwrite $path ($e) -- result kept at $tmp ; close it in Excel then run:  mv \"$tmp\" \"$path\""
    end
    conv = count(!ismissing, mkv)
    wrote_ok || println("  (NOT overwritten -- see $tmp)")
    println("  wrote $path   converged $conv/$n   errors $nerr\n"); flush(stdout)
end
println("Done.")
