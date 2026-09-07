include("main.jl")
using CSV, DataFrames, Statistics

global saveplot = false

const DIR      = raw"C:\codestuff\PBS\HeGithub"
const ITER_CAP = 3000
const NS       = 1:4
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

# Union, over all items, of that item's n nearest escorts. Escorts beyond
# that are omitted entirely.
function nearest_n_escorts(esc, itm, n)
    keep = Set{Int}()
    for ic in itm
        order = sortperm(esc, by = ec -> abs(ec[1] - ic[1]) + abs(ec[2] - ic[2]))
        for k in order[1:min(n, length(order))]
            push!(keep, k)
        end
    end
    [esc[k] for k in sort(collect(keep))]
end

# Run with escs (kept-in-grid coords) and lock every escort to its single
# nearest item (decided once, upfront, from the FULL item list). Locking is
# a no-op with 1 item.
function run_one_locked(Lx, Ly, IOc, escs, itms)
    escorts = Dict{String,escort}()
    for (k, c) in enumerate(escs)
        escorts["E$k"] = escort("E$k", c, String[], String[], 0, Dict{Int64,Vector{String}}(), Tuple{Int64,Int64}[])
    end
    items = Dict{String,item}()
    for (k, c) in enumerate(itms)
        items["I$k"] = item("I$k", c, 0, 0, 1000.0, 1, nothing)
    end

    empty!(ESCORT_ITEM_LOCK)
    for (k, c) in enumerate(escs)
        # nearest item (by Manhattan distance) among ALL loads, fixed for the whole run
        best = argmin(j -> abs(itms[j][1]-c[1]) + abs(itms[j][2]-c[2]), eachindex(itms))
        ESCORT_ITEM_LOCK["E$k"] = Set(["I$best"])
    end
    ITEM_LOCK_ENABLED[] = true

    st = fill("0", Lx, Ly)
    for (key, e) in escorts; x, y = e.coords; st[x, y] = key; end
    for (key, it) in items;  x, y = it.coords; st[x, y] = key; end
    FREEROAM_GRADIENT[] = false
    t0 = time()
    _, _, ms = main(st, items, escorts, IOc, 1, raw"C:\codestuff\PBS\plots";
        n=length(items), no_cores=1, mode="continue", mm="lm", iter_cap=ITER_CAP)
    ITEM_LOCK_ENABLED[] = false
    (ms, ESCORT_RELOCS[], time() - t0)
end

# warmup
let df = CSV.read(joinpath(DIR, FILES[1]), DataFrame)
    rename!(df, strip.(names(df)))
    Lx, Ly, IOc, esc, itm = build(first(eachrow(df)))
    run_one_locked(Lx, Ly, IOc, nearest_n_escorts(esc, itm, 2), itm)
end
println("warmup done\n"); flush(stdout)

summary_rows = NamedTuple[]

for fname in FILES
    path = joinpath(DIR, fname)
    df = CSV.read(path, DataFrame)
    rename!(df, strip.(names(df)))
    nrows = nrow(df)
    for n in NS
        mk = Float64[]; mv = Float64[]; nconv = 0; nerr = 0
        for r in eachrow(df)
            try
                Lx, Ly, IOc, esc, itm = build(r)
                escn = nearest_n_escorts(esc, itm, n)
                ms, moves, cpu = run_one_locked(Lx, Ly, IOc, escn, itm)
                if ms < ITER_CAP
                    push!(mk, ms); push!(mv, moves); nconv += 1
                end
            catch e
                nerr += 1
                println("  ERR $fname n=$n $(r[:id]): $e")
            end
        end
        push!(summary_rows, (file=fname, n=n, nrows=nrows, converged=nconv, errors=nerr,
              mean_makespan = nconv>0 ? round(mean(mk), digits=2) : missing,
              mean_moves    = nconv>0 ? round(mean(mv), digits=2) : missing))
        println(">>> $fname  n=$n (item-locked)  converged=$nconv/$nrows  mk=$(nconv>0 ? round(mean(mk),digits=2) : "NA")  moves=$(nconv>0 ? round(mean(mv),digits=2) : "NA")")
        flush(stdout)
    end
end

CSV.write(joinpath(DIR, "nearest_n_locked_summary.csv"), DataFrame(summary_rows))
println("\nDone. Wrote nearest_n_locked_summary.csv")
