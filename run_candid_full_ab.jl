include("main.jl")
using CSV, DataFrames, Statistics

global saveplot = false
const DIR      = raw"C:\codestuff\PBS\HeGithub"
const ITER_CAP = 3000
const MODES    = [0, 1, 2, 3]
const FILES    = [
    "Medium_scale_RL_6_37_13_22_formatted.csv",
    "Large_scale_RL_10_61_21_61_formatted.csv",
]

function parse_coords(s)
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
function run_one(Lx, Ly, IOc, escs, itms, mode)
    escorts = Dict{String,escort}()
    for (k, c) in enumerate(escs); escorts["E$k"] = escort("E$k", c, String[], String[], 0, Dict{Int64,Vector{String}}(), Tuple{Int64,Int64}[]); end
    items = Dict{String,item}()
    for (k, c) in enumerate(itms); items["I$k"] = item("I$k", c, 0, 0, 1000.0, 1, nothing); end
    st = fill("0", Lx, Ly)
    for (key, e) in escorts; x, y = e.coords; st[x, y] = key; end
    for (key, it) in items;  x, y = it.coords; st[x, y] = key; end
    FREEROAM_GRADIENT[] = false; PARK_GATE_RADIUS[] = 1
    ITEM_LOCK_ENABLED[] = false; FREEZE_ENABLED[] = false; TRACK_CONTRIB[] = false
    CANDID_FIX_MODE[] = mode
    empty!(MOVER_CANDID_LOG); LOG_MOVER_CANDID[] = true
    _, _, ms = main(st, items, escorts, IOc, 1, raw"C:\codestuff\PBS\plots";
        n=length(items), no_cores=1, mode="continue", mm="lm", iter_cap=ITER_CAP)
    LOG_MOVER_CANDID[] = false
    (ms, ESCORT_RELOCS[], length(MOVER_CANDID_LOG))
end

let df = CSV.read(joinpath(DIR, FILES[1]), DataFrame)
    rename!(df, strip.(names(df)))
    Lx, Ly, IOc, esc, itm = build(first(eachrow(df)))
    run_one(Lx, Ly, IOc, esc, itm, 0)
end
println("warmup done\n"); flush(stdout)

rows = NamedTuple[]
diff_rows = NamedTuple[]
for fname in FILES
    df = CSV.read(joinpath(DIR, fname), DataFrame); rename!(df, strip.(names(df)))
    nrows = nrow(df)
    for mode in MODES
        mk = Float64[]; mv = Float64[]; ev = Int[]; nconv = 0; nerr = 0
        base_by_id = Dict{String,Tuple{Any,Any}}()
        for r in eachrow(df)
            try
                Lx, Ly, IOc, esc, itm = build(r)
                ms, moves, nev = run_one(Lx, Ly, IOc, esc, itm, mode)
                push!(ev, nev)
                if ms < ITER_CAP; push!(mk, ms); push!(mv, moves); nconv += 1; end
                if mode == 0
                    base_by_id[string(r[:id])] = (ms, moves)
                end
            catch e
                nerr += 1; println("  ERR $fname mode=$mode $(r[:id]): $e")
            end
        end
        push!(rows, (file=fname, mode=mode, nrows=nrows, converged=nconv, errors=nerr,
              mean_makespan = nconv>0 ? round(mean(mk), digits=2) : missing,
              mean_moves    = nconv>0 ? round(mean(mv), digits=2) : missing,
              mean_events   = round(mean(ev), digits=1)))
        println(">>> $fname  mode=$mode  conv=$nconv/$nrows  mk=$(nconv>0 ? round(mean(mk),digits=2) : "NA")  moves=$(nconv>0 ? round(mean(mv),digits=2) : "NA")  events=$(round(mean(ev),digits=1))")
        flush(stdout)
    end
end
CSV.write(joinpath(DIR, "candid_full_ab_summary.csv"), DataFrame(rows))
println("\nDone.")
