include("main.jl")
using CSV, DataFrames, Statistics

global saveplot = false

const DIR       = raw"C:\codestuff\PBS\HeGithub"
const ITER_CAP  = 3000
const OUT_REACH = 5
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

function io_reach_ok(Lx, Ly, IOc, itms)
    ios = isa(IOc, Tuple) ? [IOc] : collect(IOc)
    blockmat = zeros(Int, Lx, Ly)
    for io in ios
        iox, ioy = io
        gy = ioy + OUT_REACH
        (1 <= iox <= Lx && 1 <= gy <= Ly) || return false
        extra = Set{Tuple{Int,Int}}(itms)
        delete!(extra, (iox, ioy)); delete!(extra, (iox, gy))
        path, _ = _escort_astar((iox, ioy), (iox, gy), blockmat, extra, Lx, Ly)
        isempty(path) && return false
    end
    return true
end

# returns (makespan, flowtime, moves, cpu)
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
    _, md, ms = main(st, items, escorts, IOc, 1, raw"C:\codestuff\PBS\plots";
        n=length(items), no_cores=1, mode="continue", mm="lm", iter_cap=ITER_CAP)
    ft = isempty(md) ? 0 : sum(values(md))
    (ms, ft, ESCORT_RELOCS[], time() - t0)
end

let df = CSV.read(joinpath(DIR, FILES[1]), DataFrame)
    rename!(df, strip.(names(df)))
    Lx, Ly, IOc, esc, itm = build(first(eachrow(df)))
    io_reach_ok(Lx, Ly, IOc, itm)
    run_one(Lx, Ly, IOc, esc, itm)
end
println("warmup done\n"); flush(stdout)

for fname in FILES
    path = joinpath(DIR, fname)
    isfile(path * ".bak_preFT_tandogan") || cp(path, path * ".bak_preFT_tandogan")
    df = CSV.read(path, DataFrame)
    rename!(df, strip.(names(df)))
    n = nrow(df)
    mv  = Vector{Any}(missing, n)
    cpv = Vector{Any}(missing, n)
    mkv = Vector{Any}(missing, n)
    ftv = Vector{Any}(missing, n)
    nerr = 0; nexcl = 0
    println(">>> $fname  ($n instances)"); flush(stdout)
    for (i, r) in enumerate(eachrow(df))
        try
            Lx, Ly, IOc, esc, itm = build(r)
            if !io_reach_ok(Lx, Ly, IOc, itm)
                mv[i] = "excluded"; cpv[i] = "excluded"; mkv[i] = "excluded"; ftv[i] = "excluded"
                nexcl += 1
                continue
            end
            ms, ft, moves, cpu = run_one(Lx, Ly, IOc, esc, itm)
            if ms < ITER_CAP
                mv[i]  = moves
                cpv[i] = round(cpu, digits = 6)
                mkv[i] = ms
                ftv[i] = ft
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
    df[!, "Flowtime Tandogan"]        = ftv
    # place Flowtime Tandogan immediately after Makespan Tandogan
    order = String[]
    for c in names(df)
        c == "Flowtime Tandogan" && continue
        push!(order, c)
        c == "Makespan Tandogan" && push!(order, "Flowtime Tandogan")
    end
    select!(df, order)
    tmp = path * ".tmp"
    CSV.write(tmp, df)
    wrote_ok = false
    try
        cp(tmp, path; force = true)
        rm(tmp; force = true)
        wrote_ok = true
    catch e
        @warn "could not overwrite $path ($e) -- result kept at $tmp"
    end
    conv = count(x -> x isa Number, mkv)
    mk_ok = Float64[x for x in mkv if x isa Number]
    ft_ok = Float64[x for x in ftv if x isa Number]
    wrote_ok || println("  (NOT overwritten -- see $tmp)")
    println("  wrote $path   converged $conv/$n   excluded $nexcl   errors $nerr")
    if !isempty(ft_ok)
        println("  mean Makespan Tandogan = $(round(mean(mk_ok), digits=2))    mean Flowtime Tandogan = $(round(mean(ft_ok), digits=2))")
    end
    println(); flush(stdout)
end
println("Done.")
