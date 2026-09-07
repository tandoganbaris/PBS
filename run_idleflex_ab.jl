include("main.jl")
using CSV, DataFrames, Statistics

global saveplot = false
const DIR      = raw"C:\codestuff\PBS\HeGithub"
const ITER_CAP = 3000
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
nearest_n_escorts(esc, itm, n) = begin
    keep = Set{Int}()
    for ic in itm
        order = sortperm(esc, by = ec -> abs(ec[1] - ic[1]) + abs(ec[2] - ic[2]))
        for k in order[1:min(n, length(order))]; push!(keep, k); end
    end
    [esc[k] for k in sort(collect(keep))]
end
function run_one(Lx, Ly, IOc, escs, itms, iomode, park, flex)
    escorts = Dict{String,escort}()
    for (k, c) in enumerate(escs); escorts["E$k"] = escort("E$k", c, String[], String[], 0, Dict{Int64,Vector{String}}(), Tuple{Int64,Int64}[]); end
    items = Dict{String,item}()
    for (k, c) in enumerate(itms); items["I$k"] = item("I$k", c, 0, 0, 1000.0, 1, nothing); end
    st = fill("0", Lx, Ly)
    for (key, e) in escorts; x, y = e.coords; st[x, y] = key; end
    for (key, it) in items;  x, y = it.coords; st[x, y] = key; end
    FREEROAM_GRADIENT[] = false; PARK_GATE_RADIUS[] = park
    ITEM_LOCK_ENABLED[] = false; FREEZE_ENABLED[] = false; TRACK_CONTRIB[] = false
    CANDID_FIX_MODE[] = 0; ESCORT_PROXIMITY_ORDER[] = true
    IO_ORDER_MODE[] = iomode; IDLE_FLEX[] = flex
    _, _, ms = main(st, items, escorts, IOc, 1, raw"C:\codestuff\PBS\plots";
        n=length(items), no_cores=1, mode="continue", mm="lm", iter_cap=ITER_CAP)
    IDLE_FLEX[] = true
    (ms, ESCORT_RELOCS[])
end

let df = CSV.read(joinpath(DIR, FILES[1]), DataFrame)
    rename!(df, strip.(names(df)))
    Lx, Ly, IOc, esc, itm = build(first(eachrow(df)))
    run_one(Lx, Ly, IOc, esc, itm, 2, 1, true)
end
println("warmup done\n"); flush(stdout)

detail = NamedTuple[]
for (setting, escsel, iomode, park) in (
        ("baseline", (e,i)->e, 2, 1),
        ("n=1",      (e,i)->nearest_n_escorts(e,i,1), 4, 2))
    for fname in FILES
        df = CSV.read(joinpath(DIR, fname), DataFrame); rename!(df, strip.(names(df)))
        for flex in (false, true)
            for r in eachrow(df)
                try
                    Lx, Ly, IOc, esc, itm = build(r)
                    ms, mv = run_one(Lx, Ly, IOc, escsel(esc, itm), itm, iomode, park, flex)
                    push!(detail, (setting=setting, file=fname, flex=flex, id=string(r[:id]),
                          makespan = ms < ITER_CAP ? ms : missing, moves = ms < ITER_CAP ? mv : missing))
                catch e
                    push!(detail, (setting=setting, file=fname, flex=flex, id=string(r[:id]), makespan=missing, moves=missing))
                    println("  ERR $setting $fname flex=$flex $(r[:id]): $e")
                end
            end
            println("done [$setting] $fname flex=$flex"); flush(stdout)
        end
    end
end
det = DataFrame(detail)
CSV.write(joinpath(DIR, "idleflex_ab_detail.csv"), det)

for setting in unique(det.setting), fname in unique(det.file)
    sub = det[(det.setting .== setting) .& (det.file .== fname), :]
    off = Set(sub[(.!sub.flex) .& .!ismissing.(sub.makespan), :id])
    on  = Set(sub[(sub.flex) .& .!ismissing.(sub.makespan), :id])
    common = intersect(off, on)
    println("\n=== [$setting] $fname   solved off=$(length(off))/100  on=$(length(on))/100   common=$(length(common)) ===")
    for flex in (false, true)
        s = sub[(sub.flex .== flex) .& in.(sub.id, Ref(common)), :]
        println("  flex=$flex   common-mk=$(round(mean(skipmissing(s.makespan)),digits=2))  common-moves=$(round(mean(skipmissing(s.moves)),digits=2))")
    end
end
println("\nDone.")
