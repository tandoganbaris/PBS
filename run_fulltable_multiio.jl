include("main.jl")
using CSV, DataFrames, Statistics

global saveplot = false
const DIR      = raw"C:\codestuff\PBS\HeGithub"
const ITER_CAP = 3000
const FILES    = [
    "Medium_scale_RL_6_37_13_22_formatted.csv",
    "Large_scale_RL_10_61_21_61_formatted.csv",
]

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
function run_one(Lx, Ly, IOc, escs, itms; iomode=2, park=1, track=false)
    escorts = Dict{String,escort}()
    for (k, c) in enumerate(escs); escorts["E$k"] = escort("E$k", c, String[], String[], 0, Dict{Int64,Vector{String}}(), Tuple{Int64,Int64}[]); end
    items = Dict{String,item}()
    for (k, c) in enumerate(itms); items["I$k"] = item("I$k", c, 0, 0, 1000.0, 1, nothing); end
    st = fill("0", Lx, Ly)
    for (key, e) in escorts; x, y = e.coords; st[x, y] = key; end
    for (key, it) in items;  x, y = it.coords; st[x, y] = key; end
    FREEROAM_GRADIENT[] = false
    ITEM_LOCK_ENABLED[] = false; FREEZE_ENABLED[] = false
    CANDID_FIX_MODE[] = 0; ESCORT_PROXIMITY_ORDER[] = true; IDLE_FLEX[] = true
    IO_ORDER_MODE[] = iomode; PARK_GATE_RADIUS[] = park
    TRACK_CONTRIB[] = track
    track && (empty!(CONTRIB_ESCORTS))
    _, _, ms = main(st, items, escorts, IOc, 1, raw"C:\codestuff\PBS\plots";
        n=length(items), no_cores=1, mode="continue", mm="lm", iter_cap=ITER_CAP)
    TRACK_CONTRIB[] = false
    (ms, ESCORT_RELOCS[])
end

let df = CSV.read(joinpath(DIR, FILES[1]), DataFrame)
    rename!(df, strip.(names(df)))
    Lx, Ly, IOc, esc, itm = build(first(eachrow(df)))
    run_one(Lx, Ly, IOc, esc, itm)
end
println("warmup done\n"); flush(stdout)

detail = NamedTuple[]
for fname in FILES
    df = CSV.read(joinpath(DIR, fname), DataFrame); rename!(df, strip.(names(df)))
    for r in eachrow(df)
        id = string(r[:id])
        Lx, Ly, IOc, esc, itm = build(r)
        # This paper (full, mode 2, park 1)
        ms, mv = run_one(Lx, Ly, IOc, esc, itm; iomode=2, park=1)
        push!(detail, (file=fname, id=id, col="thispaper", makespan=ms<ITER_CAP ? ms : missing, moves=ms<ITER_CAP ? mv : missing))
        # n = 1..4  (n=1: mode 4 park 2; n>=2: mode 2 park 2)
        for n in 1:4
            escn = nearest_n_escorts(esc, itm, n)
            iom = n == 1 ? 4 : 2
            ms, mv = run_one(Lx, Ly, IOc, escn, itm; iomode=iom, park=2)
            push!(detail, (file=fname, id=id, col="n$n", makespan=ms<ITER_CAP ? ms : missing, moves=ms<ITER_CAP ? mv : missing))
        end
        # Postprocess: pass1 tracked (full), then pass2 pruned to contributors
        ms1, _ = run_one(Lx, Ly, IOc, esc, itm; iomode=2, park=1, track=true)
        contrib = reduce(union, values(CONTRIB_ESCORTS); init=Set{String}())
        escn = [c for (k,c) in enumerate(esc) if "E$k" in contrib]
        ms2, mv2 = run_one(Lx, Ly, IOc, escn, itm; iomode=2, park=1)
        push!(detail, (file=fname, id=id, col="postproc", makespan=ms2<ITER_CAP ? ms2 : missing, moves=ms2<ITER_CAP ? mv2 : missing))
    end
    println("done $fname"); flush(stdout)
end
det = DataFrame(detail)
CSV.write(joinpath(DIR, "fulltable_multiio_detail.csv"), det)

for fname in FILES
    println("\n=== $fname ===")
    for col in ["thispaper","n1","n2","n3","n4","postproc"]
        s = det[(det.file .== fname) .& (det.col .== col), :]
        mk = collect(skipmissing(s.makespan)); mv = collect(skipmissing(s.moves))
        println("  $(rpad(col,10))  solved $(length(mk))/$(nrow(s))   mk=$(round(mean(mk),digits=2))  moves=$(round(mean(mv),digits=2))")
    end
end
println("\nDone.")
