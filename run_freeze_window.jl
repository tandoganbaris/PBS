include("main.jl")
using CSV, DataFrames, Statistics

global saveplot = false

const DIR      = raw"C:\codestuff\PBS\HeGithub"
const ITER_CAP = 3000
const KS       = [0, 1, 2, 3, 5]
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

function run_one(Lx, Ly, IOc, escs, itms; track=false, freeze=false)
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
    TRACK_CONTRIB[]  = track
    FREEZE_ENABLED[] = freeze
    track && empty!(ESCORT_CONTRIB_ITERS)
    t0 = time()
    _, _, ms = main(st, items, escorts, IOc, 1, raw"C:\codestuff\PBS\plots";
        n=length(items), no_cores=1, mode="continue", mm="lm", iter_cap=ITER_CAP)
    TRACK_CONTRIB[]  = false
    FREEZE_ENABLED[] = false
    (ms, ESCORT_RELOCS[], time() - t0)
end

function build_windows!(k)
    empty!(ESCORT_ACTIVE_WINDOWS)
    for (escid, iters) in ESCORT_CONTRIB_ITERS
        ESCORT_ACTIVE_WINDOWS[escid] = [(t - k, t + k) for t in iters]
    end
end

# warmup
let df = CSV.read(joinpath(DIR, FILES[1]), DataFrame)
    rename!(df, strip.(names(df)))
    Lx, Ly, IOc, esc, itm = build(first(eachrow(df)))
    run_one(Lx, Ly, IOc, esc, itm; track=true)
    build_windows!(2)
    run_one(Lx, Ly, IOc, esc, itm; freeze=true)
end
println("warmup done\n"); flush(stdout)

summary_rows = NamedTuple[]

for fname in FILES
    path = joinpath(DIR, fname)
    df = CSV.read(path, DataFrame)
    rename!(df, strip.(names(df)))
    nrows = nrow(df)

    # Cache pass-1 (discovery) results per instance so we don't re-run it for every K.
    cache = Vector{Any}(undef, nrows)
    for (i, r) in enumerate(eachrow(df))
        try
            Lx, Ly, IOc, esc, itm = build(r)
            ms1, mv1, cpu1 = run_one(Lx, Ly, IOc, esc, itm; track=true)
            contrib_iters = deepcopy(ESCORT_CONTRIB_ITERS)
            cache[i] = (Lx=Lx, Ly=Ly, IOc=IOc, esc=esc, itm=itm,
                        ms1=ms1, mv1=mv1, contrib_iters=contrib_iters)
        catch e
            cache[i] = nothing
            println("  ERR pass1 $fname $(r[:id]): $e")
        end
    end
    nconv1 = count(c -> c !== nothing && c.ms1 < ITER_CAP, cache)
    mk1 = mean([c.ms1 for c in cache if c !== nothing && c.ms1 < ITER_CAP])
    mv1 = mean([c.mv1 for c in cache if c !== nothing && c.ms1 < ITER_CAP])
    println(">>> $fname  pass1 (full, unfrozen)  conv=$nconv1/$nrows  mk=$(round(mk1,digits=2))  moves=$(round(mv1,digits=2))")
    flush(stdout)

    for k in KS
        mk = Float64[]; mv = Float64[]; nconv = 0
        for c in cache
            c === nothing && continue
            empty!(ESCORT_CONTRIB_ITERS)
            merge!(ESCORT_CONTRIB_ITERS, c.contrib_iters)
            build_windows!(k)
            ms, moves, cpu = run_one(c.Lx, c.Ly, c.IOc, c.esc, c.itm; freeze=true)
            if ms < ITER_CAP
                push!(mk, ms); push!(mv, moves); nconv += 1
            end
        end
        push!(summary_rows, (file=fname, k=k, nrows=nrows,
            converged=nconv,
            mk = nconv>0 ? round(mean(mk),digits=2) : missing,
            mv = nconv>0 ? round(mean(mv),digits=2) : missing))
        println("    k=$k (freeze window +-$k)  conv=$nconv/$nrows  mk=$(nconv>0 ? round(mean(mk),digits=2) : "NA")  moves=$(nconv>0 ? round(mean(mv),digits=2) : "NA")")
        flush(stdout)
    end
end

CSV.write(joinpath(DIR, "freeze_window_summary.csv"), DataFrame(summary_rows))
println("\nDone. Wrote freeze_window_summary.csv")
