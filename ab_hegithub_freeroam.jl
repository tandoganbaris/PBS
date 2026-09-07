include("main.jl")
using CSV, DataFrames

global saveplot = false

const DIR = raw"C:\codestuff\PBS\HeGithub"
const OUT = raw"C:\codestuff\PBS\ab_hegithub_freeroam_results.csv"
const ITER_CAP = parse(Int, get(ENV, "ITER_CAP", "1000"))
const FILES = ["Gue", "Yalcin", "Zou", "Mirzaei"]

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

function run_one(Lx, Ly, IOc, escs, itms, gradient)
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
    FREEROAM_GRADIENT[] = gradient
    t0 = time()
    _, _, ms = main(st, items, escorts, IOc, 1, raw"C:\codestuff\PBS\plots";
        n=length(items), no_cores=1, mode="continue", mm="lm", iter_cap=ITER_CAP)
    (ms, TOTAL_MOVES[], time() - t0)
end

function build(r)
    Lx_s, Ly_s = parse.(Int, split(r[Symbol("Lx x Ly")], 'x'))
    io  = parse_coords(r[:IOs]); esc = parse_coords(r[:Escorts]); itm = parse_coords(r[Symbol("Target Loads")])
    allc = vcat(io, esc, itm)
    Lx = max(Lx_s, maximum(c[1] for c in allc)); Ly = max(Ly_s, maximum(c[2] for c in allc))
    (Lx, Ly, length(io) == 1 ? io[1] : io, esc, itm, length(io), length(esc), length(itm))
end

refcol(df, name) = begin
    for c in ("Number of moves $name",)
        c in names(df) && return c
    end
    ""
end

# warmup
let df = CSV.read(joinpath(DIR, "Gue_vs_RL_formatted.csv"), DataFrame)
    rename!(df, strip.(names(df)))
    Lx, Ly, IOc, esc, itm, _, _, _ = build(eachrow(df)[1])
    for g in (false, true); run_one(Lx, Ly, IOc, esc, itm, g); end
end
println("warmup done\n"); flush(stdout)

allrows = DataFrame(set=String[], id=String[], nio=Int[], nesc=Int[], nload=Int[],
    ms_orig=Int[], mv_orig=Int[], cv_orig=Bool[], cpu_orig=Float64[],
    ms_grad=Int[], mv_grad=Int[], cv_grad=Bool[], cpu_grad=Float64[],
    rl_moves=Union{Int,Missing}[], rl_ms=Union{Int,Missing}[], ref_moves=Union{Int,Missing}[])

for fname in FILES
    df = CSV.read(joinpath(DIR, "$(fname)_vs_RL_formatted.csv"), DataFrame)
    rename!(df, strip.(names(df)))
    rc = refcol(df, fname)
    n = nrow(df)
    println(">>> $fname  ($n instances)"); flush(stdout)
    for (i, r) in enumerate(eachrow(df))
        id = string(r[:id])
        Lx, Ly, IOc, esc, itm, nio, nesc, nload = build(r)
        a = try run_one(Lx, Ly, IOc, esc, itm, false) catch e; println("ERR $fname/$id orig: $e"); (ITER_CAP, -1, 0.0) end
        b = try run_one(Lx, Ly, IOc, esc, itm, true)  catch e; println("ERR $fname/$id grad: $e"); (ITER_CAP, -1, 0.0) end
        gi(k) = k == "" ? missing : (v = tryparse(Int, string(r[Symbol(k)])); v === nothing ? missing : v)
        push!(allrows, (fname, id, nio, nesc, nload,
            a[1], a[2], a[1] < ITER_CAP, a[3],
            b[1], b[2], b[1] < ITER_CAP, b[3],
            gi("Number of moves RL"), gi("Makespan RL (sm)"), gi(rc)))
        (i % 200 == 0 || i == n) && (println("  [$i/$n]"); flush(stdout))
    end
end

CSV.write(OUT, allrows)
println("\nwrote $OUT\n")

function report(sub, label)
    n = nrow(sub); n == 0 && return
    co = count(sub.cv_orig); cg = count(sub.cv_grad)
    both = sub[sub.cv_orig .& sub.cv_grad, :]
    println("── $label  (n=$n)")
    println("   converged:  orig=$co   grad=$cg   (only orig: $(count(sub.cv_orig .& .!sub.cv_grad)), only grad: $(count(sub.cv_grad .& .!sub.cv_orig)))")
    if nrow(both) > 0
        mo, mg = sum(both.mv_orig), sum(both.mv_grad)
        so, sg = sum(both.ms_orig), sum(both.ms_grad)
        rl = sum(skipmissing(both.rl_moves))
        println("   both-conv ($(nrow(both))): moves orig=$mo grad=$mg RL=$rl | makespan orig=$so grad=$sg")
        println("      moves h2h  grad</=/> orig: $(count(both.mv_grad .< both.mv_orig))/$(count(both.mv_grad .== both.mv_orig))/$(count(both.mv_grad .> both.mv_orig))")
    end
    println("   CPU: orig=$(round(sum(sub.cpu_orig),digits=1))s grad=$(round(sum(sub.cpu_grad),digits=1))s")
end

println("========== PER SET ==========")
for f in FILES; report(allrows[allrows.set .== f, :], f); end
println("\n========== $(("Yalcin","Zou")) BY (#IO,#ESC) ==========")
for f in ("Yalcin", "Zou"), ne in 1:3
    report(allrows[(allrows.set .== f) .& (allrows.nesc .== ne), :], "$f  nesc=$ne")
end
println("\n========== OVERALL ==========")
report(allrows, "ALL")
