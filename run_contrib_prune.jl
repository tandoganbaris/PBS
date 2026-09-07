include("main.jl")
using CSV, DataFrames, Statistics

global saveplot = false

const DIR      = raw"C:\codestuff\PBS\HeGithub"
const ITER_CAP = 3000
const FILES    = [
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

# lock: Dict{String,String} escortid -> the one item it's allowed to serve
# (nothing = no locking, pass 1/2 behavior unchanged).
function run_one(Lx, Ly, IOc, escs, itms; track=false, lock=nothing)
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
    TRACK_CONTRIB[] = track
    if track
        empty!(CONTRIB_ESCORTS)
        empty!(ESCORT_CONTRIB_ITERS)
        empty!(ESCORT_CONTRIB_EVENTS)
    end
    if lock === nothing
        ITEM_LOCK_ENABLED[] = false
    else
        empty!(ESCORT_ITEM_LOCK)
        merge!(ESCORT_ITEM_LOCK, lock)
        ITEM_LOCK_ENABLED[] = true
    end
    t0 = time()
    _, _, ms = main(st, items, escorts, IOc, 1, raw"C:\codestuff\PBS\plots";
        n=length(items), no_cores=1, mode="continue", mm="lm", iter_cap=ITER_CAP)
    TRACK_CONTRIB[]  = false
    ITEM_LOCK_ENABLED[] = false
    (ms, ESCORT_RELOCS[], time() - t0)
end

# warmup
let df = CSV.read(joinpath(DIR, FILES[1]), DataFrame)
    rename!(df, strip.(names(df)))
    Lx, Ly, IOc, esc, itm = build(first(eachrow(df)))
    run_one(Lx, Ly, IOc, esc, itm; track=true)
    contrib = reduce(union, values(CONTRIB_ESCORTS); init=Set{String}())
    escn = [c for (k,c) in enumerate(esc) if "E$k" in contrib]
    run_one(Lx, Ly, IOc, escn, itm)
    lockmap = Dict(escid => Set(x[2] for x in evs) for (escid,evs) in ESCORT_CONTRIB_EVENTS)
    run_one(Lx, Ly, IOc, escn, itm; lock=lockmap)
end
println("warmup done\n"); flush(stdout)

summary_rows = NamedTuple[]
detail_rows  = NamedTuple[]

for fname in FILES
    path = joinpath(DIR, fname)
    df = CSV.read(path, DataFrame)
    rename!(df, strip.(names(df)))
    nrows = nrow(df)

    mk1 = Float64[]; mv1 = Float64[]; nconv1 = 0
    mk2 = Float64[]; mv2 = Float64[]; nconv2 = 0
    mk3 = Float64[]; mv3 = Float64[]; nconv3 = 0
    ncontrib = Float64[]
    nerr = 0

    for r in eachrow(df)
        try
            Lx, Ly, IOc, esc, itm = build(r)
            ntot = length(esc)

            # PASS 1: full escort set, tracked (who touched what, and when)
            ms1, mv1_i, cpu1 = run_one(Lx, Ly, IOc, esc, itm; track=true)
            contrib = reduce(union, values(CONTRIB_ESCORTS); init=Set{String}())
            push!(ncontrib, length(contrib))
            if ms1 < ITER_CAP
                push!(mk1, ms1); push!(mv1, mv1_i); nconv1 += 1
            end

            # PASS 2: only escorts that ever directly moved an item in pass 1 -- unlocked
            escn = [c for (k,c) in enumerate(esc) if "E$k" in contrib]
            ms2, mv2_i, cpu2 = run_one(Lx, Ly, IOc, escn, itm)
            if ms2 < ITER_CAP
                push!(mk2, ms2); push!(mv2, mv2_i); nconv2 += 1
            end

            # PASS 3 disabled (item-lock variant found infeasible for multi-item)
            ms3, mv3_i = ITER_CAP, 0

            push!(detail_rows, (file=fname, id=string(r[:id]),
                total_escorts=ntot, contrib_escorts=length(contrib),
                makespan_pass1=ms1<ITER_CAP ? ms1 : missing, moves_pass1=ms1<ITER_CAP ? mv1_i : missing,
                makespan_pass2=ms2<ITER_CAP ? ms2 : missing, moves_pass2=ms2<ITER_CAP ? mv2_i : missing,
                makespan_pass3=ms3<ITER_CAP ? ms3 : missing, moves_pass3=ms3<ITER_CAP ? mv3_i : missing))
        catch e
            nerr += 1
            println("  ERR $fname $(r[:id]): $e")
        end
    end

    push!(summary_rows, (file=fname, nrows=nrows,
        converged_pass1=nconv1, converged_pass2=nconv2, converged_pass3=nconv3, errors=nerr,
        mean_contrib = round(mean(ncontrib), digits=2),
        mk_pass1 = nconv1>0 ? round(mean(mk1),digits=2) : missing,
        mv_pass1 = nconv1>0 ? round(mean(mv1),digits=2) : missing,
        mk_pass2 = nconv2>0 ? round(mean(mk2),digits=2) : missing,
        mv_pass2 = nconv2>0 ? round(mean(mv2),digits=2) : missing,
        mk_pass3 = nconv3>0 ? round(mean(mk3),digits=2) : missing,
        mv_pass3 = nconv3>0 ? round(mean(mv3),digits=2) : missing))

    println(">>> $fname  mean_contrib_escorts=$(round(mean(ncontrib),digits=2))")
    println("    pass1 (full)          conv=$nconv1/$nrows  mk=$(nconv1>0 ? round(mean(mk1),digits=2) : "NA")  moves=$(nconv1>0 ? round(mean(mv1),digits=2) : "NA")")
    println("    pass2 (pruned)        conv=$nconv2/$nrows  mk=$(nconv2>0 ? round(mean(mk2),digits=2) : "NA")  moves=$(nconv2>0 ? round(mean(mv2),digits=2) : "NA")")
    println("    pass3 (pruned+locked) conv=$nconv3/$nrows  mk=$(nconv3>0 ? round(mean(mk3),digits=2) : "NA")  moves=$(nconv3>0 ? round(mean(mv3),digits=2) : "NA")")
    flush(stdout)
end

CSV.write(joinpath(DIR, "contrib_prune_summary.csv"), DataFrame(summary_rows))
CSV.write(joinpath(DIR, "contrib_prune_detail.csv"), DataFrame(detail_rows))
println("\nDone. Wrote contrib_prune_summary.csv and contrib_prune_detail.csv")
