include("main.jl")
using CSV, DataFrames

global saveplot = false

const SRC = raw"C:\codestuff\PBS\HeGithub\Mirzaei_vs_RL_formatted.csv"
const OUT = raw"C:\codestuff\PBS\ab_mirzaei_freeroam_results.csv"
const ITER_CAP = parse(Int, get(ENV, "ITER_CAP", "1000"))

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

df = CSV.read(SRC, DataFrame)
rename!(df, strip.(names(df)))
PROBE = get(ENV, "PROBE", "")
PROBE != "" && (df = df[1:parse(Int, PROBE), :])

function run_one(Lx, Ly, IO_coords, escort_coords, item_coords, gradient)
    escorts = Dict{String,escort}()
    for (k, c) in enumerate(escort_coords)
        escorts["E$k"] = escort("E$k", c, String[], String[], 0, Dict{Int64,Vector{String}}(), Tuple{Int64,Int64}[])
    end
    items = Dict{String,item}()
    for (k, c) in enumerate(item_coords)
        items["I$k"] = item("I$k", c, 0, 0, 1000.0, 1, nothing)
    end
    initialstate = fill("0", Lx, Ly)
    for (key, e) in escorts; x, y = e.coords; initialstate[x, y] = key; end
    for (key, it) in items;  x, y = it.coords; initialstate[x, y] = key; end

    FREEROAM_GRADIENT[] = gradient
    t0 = time()
    _, _, ms = main(initialstate, items, escorts, IO_coords, 1, raw"C:\codestuff\PBS\plots";
        n=length(items), no_cores=1, mode="continue", mm="lm", iter_cap=ITER_CAP)
    (ms, TOTAL_MOVES[], time() - t0)
end

function build(r)
    Lx_s, Ly_s = parse.(Int, split(r[Symbol("Lx x Ly")], 'x'))
    io  = parse_coords(r[:IOs])
    esc = parse_coords(r[:Escorts])
    itm = parse_coords(r[Symbol("Target Loads")])
    allc = vcat(io, esc, itm)
    Lx = max(Lx_s, maximum(c[1] for c in allc))
    Ly = max(Ly_s, maximum(c[2] for c in allc))
    IOc = length(io) == 1 ? io[1] : io
    (Lx, Ly, IOc, esc, itm)
end

# warmup both paths
let (Lx, Ly, IOc, esc, itm) = build(eachrow(df)[1])
    for g in (false, true); run_one(Lx, Ly, IOc, esc, itm, g); end
end
println("warmup done\n")

ids = String[]
ms0 = Int[]; mv0 = Int[]; cv0 = Bool[]; cpu0 = Float64[]
ms1 = Int[]; mv1 = Int[]; cv1 = Bool[]; cpu1 = Float64[]
rlmv = Union{Int,Missing}[]; rlms = Union{Int,Missing}[]; mirmv = Union{Int,Missing}[]

n = nrow(df)
for (i, r) in enumerate(eachrow(df))
    id = string(r[:id])
    Lx, Ly, IOc, esc, itm = build(r)
    a = try run_one(Lx, Ly, IOc, esc, itm, false) catch e; println("ERR $id orig: $e"); (ITER_CAP, -1, 0.0) end
    b = try run_one(Lx, Ly, IOc, esc, itm, true)  catch e; println("ERR $id grad: $e"); (ITER_CAP, -1, 0.0) end

    push!(ids, id)
    push!(ms0, a[1]); push!(mv0, a[2]); push!(cv0, a[1] < ITER_CAP); push!(cpu0, a[3])
    push!(ms1, b[1]); push!(mv1, b[2]); push!(cv1, b[1] < ITER_CAP); push!(cpu1, b[3])
    g(k) = (v = tryparse(Int, string(r[Symbol(k)])); v === nothing ? missing : v)
    push!(rlmv, g("Number of moves RL")); push!(rlms, g("Makespan RL (sm)")); push!(mirmv, g("Number of moves Mirzaei"))

    (i % 25 == 0 || i == n) && (println("[$i/$n] orig conv=$(count(cv0))  grad conv=$(count(cv1))"); flush(stdout))
end

CSV.write(OUT, DataFrame(id=ids,
    makespan_orig=ms0, moves_orig=mv0, conv_orig=cv0, cpu_orig=cpu0,
    makespan_grad=ms1, moves_grad=mv1, conv_grad=cv1, cpu_grad=cpu1,
    rl_moves=rlmv, rl_makespan=rlms, mirzaei_moves=mirmv))
println("\nwrote $OUT\n")

println("=== SUMMARY (n=$n, LM mode, cap $ITER_CAP) ===")
println("converged:   orig=$(count(cv0))/$n   grad=$(count(cv1))/$n")
both = [i for i in 1:n if cv0[i] && cv1[i]]
println("both converged: $(length(both))")
if !isempty(both)
    tm0 = sum(mv0[i] for i in both); tm1 = sum(mv1[i] for i in both)
    ts0 = sum(ms0[i] for i in both); ts1 = sum(ms1[i] for i in both)
    trl = sum(skipmissing(rlmv[i] for i in both))
    println("both-converged totals:")
    println("  moves     orig=$tm0  grad=$tm1  RL=$trl")
    println("  makespan  orig=$ts0  grad=$ts1")
    println("  moves h2h:    grad<orig:$(count(i->mv1[i]<mv0[i],both))  =:$(count(i->mv1[i]==mv0[i],both))  grad>orig:$(count(i->mv1[i]>mv0[i],both))")
    println("  makespan h2h: grad<orig:$(count(i->ms1[i]<ms0[i],both))  =:$(count(i->ms1[i]==ms0[i],both))  grad>orig:$(count(i->ms1[i]>ms0[i],both))")
end
println("converged only under orig: $(count(i->cv0[i] && !cv1[i], 1:n))")
println("converged only under grad: $(count(i->cv1[i] && !cv0[i], 1:n))")
println("total CPU: orig=$(round(sum(cpu0),digits=1))s  grad=$(round(sum(cpu1),digits=1))s")
