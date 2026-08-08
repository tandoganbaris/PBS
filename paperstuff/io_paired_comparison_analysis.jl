using CSV
using DataFrames
using Statistics

# ─── What this does ──────────────────────────────────────────────────────────
# Reads the raw paired left-vs-center results (io_paired_comparison_raw.csv,
# produced by io_comparison_stats.jl) and removes rows that indicate an engine
# failure rather than a real result, before recomputing the grouped stats.
#
# A row is dropped if any of the following holds:
#   1. pct_makespan or pct_flowtime is non-finite (NaN/Inf/-Inf) — this happens
#      when flowtime_left or flowtime_center is 0 (nothing was delivered),
#      making the percentage undefined.
#   2. pct_makespan or pct_flowtime is worse than -500% (more than 5x worse) —
#      values this extreme come from a run producing an implausibly tiny
#      flowtime/makespan, not a genuine measurement.
#   3. makespan_left or makespan_center equals 1000 — main.jl hard-caps a run
#      at 1000 iterations and breaks out unfinished (`if time > 1000 break`),
#      so a run landing exactly on 1000 didn't actually complete and its
#      recorded flowtime/makespan understate the true value. This is the root
#      cause of both symptoms above, so it's filtered directly rather than
#      relying only on the two symptoms catching every case.
# ──────────────────────────────────────────────────────────────────────────────

const OUT_DIR = raw"C:\codestuff\PBS\paperplots"
const RAW_PATH = joinpath(OUT_DIR, "io_paired_comparison_raw.csv")
const ITERATION_CAP = 1000
const WORST_PCT_ALLOWED = -500.0   # more negative than this = dropped

df = CSV.read(RAW_PATH, DataFrame)
n_total = nrow(df)

nonfinite_mask = .!isfinite.(df.pct_makespan) .| .!isfinite.(df.pct_flowtime)
extreme_mask   = isfinite.(df.pct_makespan) .& (df.pct_makespan .< WORST_PCT_ALLOWED) .|
                 isfinite.(df.pct_flowtime) .& (df.pct_flowtime .< WORST_PCT_ALLOWED)
capped_mask    = (df.makespan_left .== ITERATION_CAP) .| (df.makespan_center .== ITERATION_CAP)

bad_mask  = nonfinite_mask .| extreme_mask .| capped_mask
good_mask = .!bad_mask

println("Total rows:              $n_total")
println("Non-finite pct (NaN/Inf): $(count(nonfinite_mask))")
println("Worse than -500%:         $(count(extreme_mask))")
println("Hit iteration cap ($ITERATION_CAP):  $(count(capped_mask))")
println("Dropped overall:          $(count(bad_mask))")
println("Kept:                     $(count(good_mask))")

dropped = df[bad_mask, :]
CSV.write(joinpath(OUT_DIR, "io_paired_comparison_dropped.csv"), dropped)

clean = df[good_mask, :]
CSV.write(joinpath(OUT_DIR, "io_paired_comparison_clean.csv"), clean)
println("\nWrote io_paired_comparison_clean.csv ($(nrow(clean)) rows) and _dropped.csv ($(nrow(dropped)) rows)")

# ─── Stats helper (same shape as io_comparison_stats.jl) ────────────────────

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

function grouped_stats(data, group_col::Symbol)
    rows = NamedTuple[]
    for gv in sort(unique(data[!, group_col]))
        sub = filter(r -> r[group_col] == gv, data)
        push!(rows, stats_row(group_col, gv, sub.pct_makespan, sub.pct_flowtime))
    end
    return DataFrame(rows)
end

CSV.write(joinpath(OUT_DIR, "io_paired_comparison_by_loads_clean.csv"),    grouped_stats(clean, :n_items))
CSV.write(joinpath(OUT_DIR, "io_paired_comparison_by_escorts_clean.csv"),  grouped_stats(clean, :n_escorts))
CSV.write(joinpath(OUT_DIR, "io_paired_comparison_by_gridsize_clean.csv"), grouped_stats(clean, :grid_size))

overall = DataFrame([stats_row(:overall, "all", clean.pct_makespan, clean.pct_flowtime)])
CSV.write(joinpath(OUT_DIR, "io_paired_comparison_overall_clean.csv"), overall)

println("Wrote by_loads_clean.csv, by_escorts_clean.csv, by_gridsize_clean.csv, overall_clean.csv")
println("\nDone. All outputs in: $OUT_DIR")
