using CSV
using DataFrames
using Statistics
using Plots
using Plots.PlotMeasures

# ─── What this does ──────────────────────────────────────────────────────────
# Focuses only on computation time (comp_time_sec from results_summary.csv,
# produced by test3.jl) and how it scales with grid size, number of loads, and
# number of escorts. Produces the same style of 2D line plots as analysis.jl
# (restricted to this one metric) plus summary statistics tables that report,
# for each factor, the mean/median/std/min/max computation time and an
# empirical scaling exponent (fit as time ~ C * x^k via a log-log regression),
# so we can quantify e.g. "doubling the grid size multiplies runtime by ~k".
# ──────────────────────────────────────────────────────────────────────────────

const CSV_PATH = raw"C:\codestuff\PBS\testinstances_26\results_summary.csv"
const OUT_DIR  = raw"C:\codestuff\PBS\paperplots"
mkpath(OUT_DIR)

df = CSV.read(CSV_PATH, DataFrame)

# Average over the 10 instances per (grid_size, n_items, n_escorts, io_position)
agg = combine(
    groupby(df, [:grid_size, :n_items, :n_escorts, :io_position]),
    :comp_time_sec => mean => :comp_time_sec,
)

const LOAD_COLORS   = [:blue, :orange, :green, :red, :purple]
const ESCORT_COLORS = palette(:tab10)[1:10]
const GRID_COLORS   = palette(:tab10)[1:10]

function base_plot(ylabel)
    plot(
        xlabel      = "",
        ylabel      = ylabel,
        legend      = :outertopright,
        framestyle  = :box,
        gridalpha   = 0.3,
        linewidth   = 2,
        markersize  = 5,
        left_margin = 10px,
        bottom_margin = 10px,
    )
end

grid_sizes    = sort(unique(agg.grid_size))
load_values   = sort(unique(agg.n_items))
escort_values = sort(unique(agg.n_escorts))

# ─── Plot 1: comp time vs grid size, one line per load count ────────────────

for io in ["left", "center"]
    sub = filter(r -> r.io_position == io, agg)
    by_grid_loads = combine(groupby(sub, [:grid_size, :n_items]),
                             :comp_time_sec => mean => :comp_time_sec)

    p = base_plot("Computation time (s)")
    plot!(p, xlabel = "Grid size (N×N)")
    for (i, nl) in enumerate(load_values)
        rows = sort(filter(r -> r.n_items == nl, by_grid_loads), :grid_size)
        isempty(rows) && continue
        plot!(p, rows.grid_size, rows.comp_time_sec; label = "$nl loads",
              color = LOAD_COLORS[i], marker = :circle)
    end
    title!(p, "Computation time vs grid size — I/O $(io)")
    savefig(p, joinpath(OUT_DIR, "comptime_gridsize_$(io).png"))
end

# ─── Plot 2: comp time vs escorts, one line per grid size ────────────────────

for io in ["left", "center"]
    sub = filter(r -> r.io_position == io, agg)
    by_escort_grid = combine(groupby(sub, [:n_escorts, :grid_size]),
                              :comp_time_sec => mean => :comp_time_sec)

    p = base_plot("Computation time (s)")
    plot!(p, xlabel = "Number of escorts")
    for (i, gs) in enumerate(grid_sizes)
        rows = sort(filter(r -> r.grid_size == gs, by_escort_grid), :n_escorts)
        isempty(rows) && continue
        plot!(p, rows.n_escorts, rows.comp_time_sec; label = "$(gs)×$(gs)",
              color = ESCORT_COLORS[i], marker = :circle)
    end
    title!(p, "Computation time vs escorts — I/O $(io)")
    savefig(p, joinpath(OUT_DIR, "comptime_escorts_$(io).png"))
end

# ─── Plot 3: comp time vs loads, one line per grid size ──────────────────────

for io in ["left", "center"]
    sub = filter(r -> r.io_position == io, agg)
    by_loads_grid = combine(groupby(sub, [:n_items, :grid_size]),
                             :comp_time_sec => mean => :comp_time_sec)

    p = base_plot("Computation time (s)")
    plot!(p, xlabel = "Number of loads")
    for (i, gs) in enumerate(grid_sizes)
        rows = sort(filter(r -> r.grid_size == gs, by_loads_grid), :n_items)
        isempty(rows) && continue
        plot!(p, rows.n_items, rows.comp_time_sec; label = "$(gs)×$(gs)",
              color = GRID_COLORS[i], marker = :circle)
    end
    title!(p, "Computation time vs loads — I/O $(io)")
    savefig(p, joinpath(OUT_DIR, "comptime_loads_$(io).png"))
end

println("Computation-time plots done.")

# ─── Statistics tables ────────────────────────────────────────────────────────
# Uses the raw (unaveraged) per-instance rows, pooled across the other two
# factors and both io_positions, so std/min/max reflect real spread.

function stats_table(df, group_col::Symbol)
    g = combine(groupby(df, group_col),
        :comp_time_sec => mean   => :mean,
        :comp_time_sec => std    => :std,
        :comp_time_sec => minimum => :min,
        :comp_time_sec => median => :median,
        :comp_time_sec => maximum => :max,
        nrow                     => :n,
    )
    sort!(g, group_col)
    # scale factor = how many times larger the mean is vs the previous row
    g.scale_factor = [i == 1 ? missing : g.mean[i] / g.mean[i-1] for i in 1:nrow(g)]
    return g
end

t_grid    = stats_table(df, :grid_size)
t_loads   = stats_table(df, :n_items)
t_escorts = stats_table(df, :n_escorts)

CSV.write(joinpath(OUT_DIR, "comptime_stats_by_gridsize.csv"), t_grid)
CSV.write(joinpath(OUT_DIR, "comptime_stats_by_loads.csv"), t_loads)
CSV.write(joinpath(OUT_DIR, "comptime_stats_by_escorts.csv"), t_escorts)
println("Wrote comptime_stats_by_gridsize.csv, _by_loads.csv, _by_escorts.csv")

# ─── Empirical scaling exponent: fit time ≈ C * x^k via log-log regression ──
# k is the slope of log(mean_time) vs log(x). k≈1 → linear, k≈2 → quadratic, etc.

function fit_power_law(xvals, yvals)
    lx = log.(xvals)
    ly = log.(yvals)
    X  = hcat(ones(length(lx)), lx)
    coeffs = X \ ly              # least squares: [intercept, slope]
    ŷ  = X * coeffs
    ss_res = sum((ly .- ŷ).^2)
    ss_tot = sum((ly .- mean(ly)).^2)
    r2 = ss_tot == 0 ? 1.0 : 1 - ss_res / ss_tot
    return coeffs[2], r2         # (exponent k, R²)
end

k_grid,    r2_grid    = fit_power_law(t_grid.grid_size,   t_grid.mean)
k_loads,   r2_loads   = fit_power_law(t_loads.n_items,    t_loads.mean)
k_escorts, r2_escorts = fit_power_law(t_escorts.n_escorts, t_escorts.mean)

scaling = DataFrame(
    factor   = ["grid_size", "n_items (loads)", "n_escorts"],
    exponent = [k_grid, k_loads, k_escorts],
    r_squared = [r2_grid, r2_loads, r2_escorts],
    interpretation = [
        "time ~ grid_size^$(round(k_grid, digits=2))",
        "time ~ loads^$(round(k_loads, digits=2))",
        "time ~ escorts^$(round(k_escorts, digits=2))",
    ],
)
CSV.write(joinpath(OUT_DIR, "comptime_scaling_exponents.csv"), scaling)
println("Wrote comptime_scaling_exponents.csv")
println(scaling)

println("\nAll outputs in: $OUT_DIR")
