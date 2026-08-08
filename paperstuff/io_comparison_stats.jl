include("../main.jl")
using CSV
using DataFrames
using Statistics
using Random

# ─── What this does ──────────────────────────────────────────────────────────
# Regenerates the exact same instances used in test3.jl's run_experiments()
# (same grid sizes, load counts, escort counts, 10 instances each, same seed
# formula) — but instead of splitting instances 5/5 between IO=left and
# IO=center, EVERY instance is solved TWICE: once with IO on the left (1,1)
# and once with IO in the center (grid_n÷2, 1). This gives a properly paired
# comparison (same random layout, only the IO position differs) instead of
# comparing averages across two different sets of random instances.
# ──────────────────────────────────────────────────────────────────────────────

const NO_CORES = Threads.nthreads()
println("Using $NO_CORES threads.")
Threads.nthreads() == 1 && @warn "Running on 1 thread. Start Julia with --threads N for parallel execution."

const OUT_DIR = raw"C:\codestuff\PBS\paperplots"
mkpath(OUT_DIR)

global saveplot = false   # never call save_plot in main's post-process loop

# ─── Solve one instance with one IO, from a pristine deep copy ───────────────

function solve_instance(initialstate, items, escorts, IO; no_cores=1)
    n  = length(items)   # batch capacity = all loads at once, matching test3.jl
    st = deepcopy(initialstate)
    it = deepcopy(items)
    es = deepcopy(escorts)
    _, makespandict, makespan = main(st, it, es, IO, 1, ""; n=n, r=1, no_cores=no_cores)
    flowtime = isempty(makespandict) ? 0 : sum(values(makespandict))
    return makespan, flowtime
end

# ─── Warm-up: run a couple of small instances so JIT is done before timing ──

println("Warming up...")
for w in 1:3
    rng_w = MersenneTwister(w)
    wd    = Dict("$i" => 1.0 for i in 1:2)
    ws, wi, we = randomintialstate((10, 10), 2, wd, rng_w)
    solve_instance(ws, wi, we, (1, 1); no_cores=NO_CORES)
end
println("Warm-up done.\n")

# ─── Same instance grid as test3.jl ──────────────────────────────────────────

items_range   = 2:2:10
escorts_range = 2:2:20
grid_range    = 10:10:100

total = length(items_range) * length(escorts_range) * length(grid_range) * 10
done  = 0

raw_path = joinpath(OUT_DIR, "io_paired_comparison_raw.csv")

# ─── Checkpoint: resume from already-completed instances ────────────────────

completed = Set{Tuple{Int,Int,Int,Int}}()  # (grid_n, n_items, n_escorts, inst_num)
if isfile(raw_path)
    existing = CSV.read(raw_path, DataFrame)
    for row in eachrow(existing)
        push!(completed, (row.grid_size, row.n_items, row.n_escorts, row.instance))
    end
    println("Resuming — $(length(completed)) instances already done.\n")
else
    header_df = DataFrame(
        grid_size        = Int[],
        n_items           = Int[],
        n_escorts         = Int[],
        instance          = Int[],
        makespan_left     = Int[],
        flowtime_left     = Int[],
        makespan_center   = Int[],
        flowtime_center   = Int[],
        pct_makespan      = Float64[],
        pct_flowtime      = Float64[],
    )
    CSV.write(raw_path, header_df)
end

for n_items in items_range, n_escorts in escorts_range, grid_n in grid_range
    for inst_num in 1:10
        global done += 1

        (grid_n, n_items, n_escorts, inst_num) in completed && continue

        # Same seed formula as test3.jl → identical random layout per instance
        seed     = n_items * 1_000_000 + n_escorts * 10_000 + grid_n * 100 + inst_num
        rng_inst = MersenneTwister(seed)

        item_deadlines = Dict("$i" => 1.0 for i in 1:n_items)
        initialstate, items, escorts =
            randomintialstate((grid_n, grid_n), n_escorts, item_deadlines, rng_inst)

        IO_left   = (1, 1)
        IO_center = (div(grid_n, 2), 1)

        makespan_left,   flowtime_left   = solve_instance(initialstate, items, escorts, IO_left;   no_cores=NO_CORES)
        makespan_center, flowtime_center = solve_instance(initialstate, items, escorts, IO_center; no_cores=NO_CORES)

        pct_makespan = (makespan_left - makespan_center) / makespan_left * 100
        pct_flowtime = (flowtime_left - flowtime_center) / flowtime_left * 100

        row_df = DataFrame(
            grid_size        = [grid_n],
            n_items           = [n_items],
            n_escorts         = [n_escorts],
            instance          = [inst_num],
            makespan_left     = [makespan_left],
            flowtime_left     = [flowtime_left],
            makespan_center   = [makespan_center],
            flowtime_center   = [flowtime_center],
            pct_makespan      = [round(pct_makespan, digits=4)],
            pct_flowtime      = [round(pct_flowtime, digits=4)],
        )
        CSV.write(raw_path, row_df; append=true)

        println("[$done/$total] $(grid_n)x$(grid_n)_I$(n_items)_E$(n_escorts)_$(inst_num)  " *
                "left(ms=$makespan_left,ft=$flowtime_left)  center(ms=$makespan_center,ft=$flowtime_center)  " *
                "pct_ms=$(round(pct_makespan,digits=1))%  pct_ft=$(round(pct_flowtime,digits=1))%")
    end
end

println("\nAll instances done. Raw paired results → $raw_path")

# ─── Stats helper ────────────────────────────────────────────────────────────

paired = CSV.read(raw_path, DataFrame)

function stats_row(group_col, group_val, vals_makespan, vals_flowtime)
    return (
        group           = string(group_col),
        value           = group_val,
        n               = length(vals_makespan),
        makespan_avg    = mean(vals_makespan),
        makespan_worst  = minimum(vals_makespan),
        makespan_best   = maximum(vals_makespan),
        makespan_q25    = quantile(vals_makespan, 0.25),
        makespan_median = quantile(vals_makespan, 0.50),
        makespan_q75    = quantile(vals_makespan, 0.75),
        flowtime_avg    = mean(vals_flowtime),
        flowtime_worst  = minimum(vals_flowtime),
        flowtime_best   = maximum(vals_flowtime),
        flowtime_q25    = quantile(vals_flowtime, 0.25),
        flowtime_median = quantile(vals_flowtime, 0.50),
        flowtime_q75    = quantile(vals_flowtime, 0.75),
    )
end

function grouped_stats(paired, group_col::Symbol)
    rows = NamedTuple[]
    for gv in sort(unique(paired[!, group_col]))
        sub = filter(r -> r[group_col] == gv, paired)
        push!(rows, stats_row(group_col, gv, sub.pct_makespan, sub.pct_flowtime))
    end
    return DataFrame(rows)
end

CSV.write(joinpath(OUT_DIR, "io_paired_comparison_by_loads.csv"),    grouped_stats(paired, :n_items))
CSV.write(joinpath(OUT_DIR, "io_paired_comparison_by_escorts.csv"),  grouped_stats(paired, :n_escorts))
CSV.write(joinpath(OUT_DIR, "io_paired_comparison_by_gridsize.csv"), grouped_stats(paired, :grid_size))

overall = DataFrame([stats_row(:overall, "all", paired.pct_makespan, paired.pct_flowtime)])
CSV.write(joinpath(OUT_DIR, "io_paired_comparison_overall.csv"), overall)

println("Wrote io_paired_comparison_by_loads.csv, _by_escorts.csv, _by_gridsize.csv, _overall.csv")
println("\nDone. All outputs in: $OUT_DIR")
