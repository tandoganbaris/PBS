include("main.jl")
using CSV, DataFrames

global saveplot = false

const SRC = raw"C:\codestuff\PBS\FourLoads_escortflow.csv"
const OUT = raw"C:\codestuff\PBS\ab_raviv_freeroam_results.csv"
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
if !("id" in names(df))
    df.id = [ "$(strip(r[Symbol("Lx x Ly")]))_$(strip(string(r[Symbol("# Escorts")])))_$(strip(string(r[Symbol("#Loads")])))_$(strip(string(r.seed)))" for r in eachrow(df) ]
end
PROBE = get(ENV, "PROBE", "")
if PROBE != ""
    df = df[1:parse(Int, PROBE), :]
end

function run_one(Lx, Ly, IO_coords, escort_coords, item_coords, mode, gradient)
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
        n=4, no_cores=1, mode=mode, mm="lm", iter_cap=ITER_CAP)
    (ms, TOTAL_MOVES[], time() - t0)
end

# warmup / JIT both paths
let r = eachrow(df)[1]
    Lx, Ly = parse.(Int, split(r[Symbol("Lx x Ly")], 'x'))
    io = parse_coords(r[:IOs]); io = length(io) == 1 ? io[1] : io
    for g in (false, true)
        run_one(Lx, Ly, io, parse_coords(r[:Escorts]), parse_coords(r[Symbol("Target Loads")]),
                lowercase(strip(string(r[Symbol("Retrieval Mode")]))), g)
    end
end
println("warmup done\n")

ids   = String[]
ms0   = Int[];  mv0 = Int[];  cv0 = Bool[];  cpu0 = Float64[]
ms1   = Int[];  mv1 = Int[];  cv1 = Bool[];  cpu1 = Float64[]
ilpms = Union{Int,Missing}[];  ilpmv = Union{Int,Missing}[]

n = nrow(df)
for (i, r) in enumerate(eachrow(df))
    id = string(r[:id])
    Lx, Ly = parse.(Int, split(r[Symbol("Lx x Ly")], 'x'))
    io = parse_coords(r[:IOs]); io = length(io) == 1 ? io[1] : io
    esc = parse_coords(r[:Escorts])
    itm = parse_coords(r[Symbol("Target Loads")])
    mode = lowercase(strip(string(r[Symbol("Retrieval Mode")])))

    a = try run_one(Lx, Ly, io, esc, itm, mode, false) catch e; println("ERR $id orig: $e"); (ITER_CAP, -1, 0.0) end
    b = try run_one(Lx, Ly, io, esc, itm, mode, true)  catch e; println("ERR $id grad: $e"); (ITER_CAP, -1, 0.0) end

    push!(ids, id)
    push!(ms0, a[1]); push!(mv0, a[2]); push!(cv0, a[1] < ITER_CAP); push!(cpu0, a[3])
    push!(ms1, b[1]); push!(mv1, b[2]); push!(cv1, b[1] < ITER_CAP); push!(cpu1, b[3])
    push!(ilpms, tryparse(Int, string(r[Symbol("ILP makespan")])) === nothing ? missing : parse(Int, string(r[Symbol("ILP makespan")])))
    push!(ilpmv, tryparse(Int, string(r[Symbol("#load movements")])) === nothing ? missing : parse(Int, string(r[Symbol("#load movements")])))

    if i % 100 == 0 || i == n
        println("[$i/$n] orig conv=$(count(cv0))  grad conv=$(count(cv1))")
        flush(stdout)
    end
end

res = DataFrame(id=ids,
    makespan_orig=ms0, moves_orig=mv0, conv_orig=cv0,
    makespan_grad=ms1, moves_grad=mv1, conv_grad=cv1,
    cpu_orig=cpu0, cpu_grad=cpu1,
    ilp_makespan=ilpms, ilp_load_movements=ilpmv)
CSV.write(OUT, res)
println("\nwrote $OUT\n")

both = [i for i in 1:n if cv0[i] && cv1[i]]
println("=== SUMMARY (n=$n) ===")
println("converged:            orig=$(count(cv0))   grad=$(count(cv1))")
println("both converged:       $(length(both))")
if !isempty(both)
    tot_mv0 = sum(mv0[i] for i in both); tot_mv1 = sum(mv1[i] for i in both)
    tot_ms0 = sum(ms0[i] for i in both); tot_ms1 = sum(ms1[i] for i in both)
    println("on both-converged instances:")
    println("  total moves:    orig=$tot_mv0   grad=$tot_mv1   (grad/orig = $(round(tot_mv1/tot_mv0, digits=4)))")
    println("  total makespan: orig=$tot_ms0   grad=$tot_ms1   (grad/orig = $(round(tot_ms1/tot_ms0, digits=4)))")
    mv_better = count(i -> mv1[i] < mv0[i], both)
    mv_worse  = count(i -> mv1[i] > mv0[i], both)
    mv_eq     = count(i -> mv1[i] == mv0[i], both)
    println("  moves head-to-head:    grad<orig:$mv_better  grad=orig:$mv_eq  grad>orig:$mv_worse")
    ms_better = count(i -> ms1[i] < ms0[i], both)
    ms_worse  = count(i -> ms1[i] > ms0[i], both)
    ms_eq     = count(i -> ms1[i] == ms0[i], both)
    println("  makespan head-to-head: grad<orig:$ms_better  grad=orig:$ms_eq  grad>orig:$ms_worse")
end
only0 = count(i -> cv0[i] && !cv1[i], 1:n)
only1 = count(i -> cv1[i] && !cv0[i], 1:n)
println("converged only under orig: $only0")
println("converged only under grad: $only1")
println("total CPU:  orig=$(round(sum(cpu0),digits=1))s   grad=$(round(sum(cpu1),digits=1))s")
println("mean CPU/solve:  orig=$(round(1000*sum(cpu0)/n,digits=1))ms   grad=$(round(1000*sum(cpu1)/n,digits=1))ms")
conv_i = [i for i in 1:n if cv0[i]]; cap_i = [i for i in 1:n if !cv0[i]]
isempty(conv_i) || println("mean CPU orig, converged:  $(round(1000*sum(cpu0[i] for i in conv_i)/length(conv_i),digits=1))ms  (n=$(length(conv_i)))")
isempty(cap_i)  || println("mean CPU orig, hit cap:    $(round(1000*sum(cpu0[i] for i in cap_i)/length(cap_i),digits=1))ms  (n=$(length(cap_i)))")
