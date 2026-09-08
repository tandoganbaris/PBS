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
function run_one(Lx, Ly, IOc, escs, itms; iomode=2, park=1, track=false, idleflex=false)
    escorts = Dict{String,escort}()
    for (k, c) in enumerate(escs); escorts["E$k"] = escort("E$k", c, String[], String[], 0, Dict{Int64,Vector{String}}(), Tuple{Int64,Int64}[]); end
    items = Dict{String,item}()
    for (k, c) in enumerate(itms); items["I$k"] = item("I$k", c, 0, 0, 1000.0, 1, nothing); end
    st = fill("0", Lx, Ly)
    for (key, e) in escorts; x, y = e.coords; st[x, y] = key; end
    for (key, it) in items;  x, y = it.coords; st[x, y] = key; end
    FREEROAM_GRADIENT[] = false
    ITEM_LOCK_ENABLED[] = false; FREEZE_ENABLED[] = false
    CANDID_FIX_MODE[] = 0; ESCORT_PROXIMITY_ORDER[] = true; IDLE_FLEX[] = idleflex
    IO_ORDER_MODE[] = iomode; PARK_GATE_RADIUS[] = park
    TRACK_CONTRIB[] = track
    track && (empty!(CONTRIB_ESCORTS))
    _, md, ms = main(st, items, escorts, IOc, 1, raw"C:\codestuff\PBS\plots";
        n=length(items), no_cores=1, mode="continue", mm="lm", iter_cap=ITER_CAP)
    TRACK_CONTRIB[] = false
    ft = isempty(md) ? 0 : sum(values(md))
    (ms, ESCORT_RELOCS[], ft)
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
    for (i, r) in enumerate(eachrow(df))
        id = string(r[:id])
        Lx, Ly, IOc, esc, itm = build(r)
        ms, mv, ft = run_one(Lx, Ly, IOc, esc, itm; iomode=2, park=1)
        push!(detail, (file=fname, id=id, col="thispaper", makespan=ms<ITER_CAP ? ms : missing,
                       moves=ms<ITER_CAP ? mv : missing, flowtime=ms<ITER_CAP ? ft : missing))
        for n in 1:4
            escn = nearest_n_escorts(esc, itm, n)
            iom = n == 1 ? 4 : 2
            ms, mv, ft = run_one(Lx, Ly, IOc, escn, itm; iomode=iom, park=2, idleflex=(n == 1))
            push!(detail, (file=fname, id=id, col="n$n", makespan=ms<ITER_CAP ? ms : missing,
                           moves=ms<ITER_CAP ? mv : missing, flowtime=ms<ITER_CAP ? ft : missing))
        end
        ms1, _, _ = run_one(Lx, Ly, IOc, esc, itm; iomode=2, park=1, track=true)
        contrib = reduce(union, values(CONTRIB_ESCORTS); init=Set{String}())
        escn = [c for (k, c) in enumerate(esc) if "E$k" in contrib]
        ms2, mv2, ft2 = run_one(Lx, Ly, IOc, escn, itm; iomode=2, park=1)
        push!(detail, (file=fname, id=id, col="postproc", makespan=ms2<ITER_CAP ? ms2 : missing,
                       moves=ms2<ITER_CAP ? mv2 : missing, flowtime=ms2<ITER_CAP ? ft2 : missing))
        i % 20 == 0 && (println("  $fname [$i]"); flush(stdout))
    end
    println("done $fname"); flush(stdout)
end
det = DataFrame(detail)
CSV.write(joinpath(DIR, "fulltable_flowtime_detail.csv"), det)

COLS = ["thispaper", "n1", "n2", "n3", "n4", "postproc"]
for fname in FILES
    println("\n=== $fname ===")
    # per-column solved + raw means
    for col in COLS
        s = det[(det.file .== fname) .& (det.col .== col), :]
        mk = collect(skipmissing(s.makespan)); ft = collect(skipmissing(s.flowtime))
        println("  $(rpad(col,10)) solved $(length(mk))/$(nrow(s))  mk=$(round(mean(mk),digits=2))  flowtime=$(round(mean(ft),digits=2))")
    end
    # common converged set across all Tandogan columns
    ids = unique(det[det.file .== fname, :id])
    conv(id, col) = begin
        row = det[(det.file .== fname) .& (det.id .== id) .& (det.col .== col), :]
        nrow(row) == 1 && !ismissing(row.flowtime[1])
    end
    common = [id for id in ids if all(col -> conv(id, col), COLS)]
    rl = CSV.read(joinpath(DIR, fname), DataFrame); rename!(rl, strip.(names(rl)))
    rlft = Dict(string(row.id) => row["Flowtime RL"] for row in eachrow(rl))
    println("  --- common converged set: $(length(common))/$(length(ids)) instances ---")
    rlvals = Float64[]
    for id in common
        v = get(rlft, id, missing)
        (v isa Number) && push!(rlvals, float(v))
    end
    println("  $(rpad("RL",12)) flowtime = $(round(mean(rlvals),digits=2))   (n=$(length(rlvals)))")
    for col in COLS
        vals = Float64[]
        for id in common
            row = det[(det.file .== fname) .& (det.id .== id) .& (det.col .== col), :]
            push!(vals, float(row.flowtime[1]))
        end
        println("  $(rpad(col,12)) flowtime = $(round(mean(vals),digits=2))")
    end
end
println("\nDone.")
