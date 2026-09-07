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
    PARK_GATE_RADIUS[]  = 1
    ITEM_LOCK_ENABLED[] = false
    FREEZE_ENABLED[]    = false
    TRACK_CONTRIB[]     = false
    empty!(MOVER_CANDID_LOG)
    LOG_MOVER_CANDID[]  = true
    _, _, ms = main(st, items, escorts, IOc, 1, raw"C:\codestuff\PBS\plots";
        n=length(items), no_cores=1, mode="continue", mm="lm", iter_cap=ITER_CAP)
    LOG_MOVER_CANDID[] = false
    (ms, ESCORT_RELOCS[], copy(MOVER_CANDID_LOG))
end

let df = CSV.read(joinpath(DIR, FILES[1]), DataFrame)
    rename!(df, strip.(names(df)))
    Lx, Ly, IOc, esc, itm = build(first(eachrow(df)))
    run_one(Lx, Ly, IOc, esc, itm)
end
println("warmup done\n"); flush(stdout)

event_rows = NamedTuple[]
inst_summary = NamedTuple[]

for fname in FILES
    path = joinpath(DIR, fname)
    df = CSV.read(path, DataFrame)
    rename!(df, strip.(names(df)))
    nrows = nrow(df)
    total_events = 0
    insts_with_events = 0
    for r in eachrow(df)
        try
            Lx, Ly, IOc, esc, itm = build(r)
            ms, moves, evlog = run_one(Lx, Ly, IOc, esc, itm)
            n_ev = length(evlog)
            n_stop = count(e -> e.branch == "stop_at_cand", evlog)
            n_push = count(e -> e.branch == "push_past_cand", evlog)
            total_events += n_ev
            n_ev > 0 && (insts_with_events += 1)
            push!(inst_summary, (file=fname, id=string(r[:id]), makespan=(ms<ITER_CAP ? ms : missing),
                  n_events=n_ev, n_stop_at_cand=n_stop, n_push_past_cand=n_push))
            for e in evlog
                push!(event_rows, merge((file=fname, id=string(r[:id])), e))
            end
        catch e
            println("  ERR $fname $(r[:id]): $e")
        end
    end
    println(">>> $fname  instances_with_events=$insts_with_events/$nrows  total_events=$total_events")
    flush(stdout)
end

CSV.write(joinpath(DIR, "candid_survey_instances.csv"), DataFrame(inst_summary))
CSV.write(joinpath(DIR, "candid_survey_events.csv"), DataFrame(event_rows))
println("\nDone. Wrote candid_survey_instances.csv and candid_survey_events.csv")
