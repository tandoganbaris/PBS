using CSV
using DataFrames
using Statistics
using Plots
using Plots.PlotMeasures

# ─── Config ──────────────────────────────────────────────────────────────────

const CSV_PATH  = raw"C:\codestuff\PBS\testinstances_26\results_summary.csv"
const OUT_DIR   = raw"C:\codestuff\PBS\paperplots"

# ─── Load & aggregate ────────────────────────────────────────────────────────

df = CSV.read(CSV_PATH, DataFrame)

# Average over the 10 instances per (grid_size, n_items, n_escorts, io_position)
agg = combine(
    groupby(df, [:grid_size, :n_items, :n_escorts, :io_position]),
    :makespan      => mean => :makespan,
    :flowtime      => mean => :flowtime,
    :comp_time_sec => mean => :comp_time_sec,
)

CSV.write(joinpath(OUT_DIR, "aggregated.csv"), agg)

# ─── Helpers ─────────────────────────────────────────────────────────────────

const METRICS = [
    (:makespan,      "Makespan",          "makespan"),
    (:flowtime,      "Flow-time",   "flowtime"),
    (:comp_time_sec, "Computation time (s)",      "comptime"),
]

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
    )
end

# Computes shared y-axis limits (with padding) across several DataFrames' metric
# column, so plots that should be visually comparable (e.g. left vs. center I/O
# for the same metric) use the same vertical scale. Returns `nothing` if there's
# no finite data to scale to.
function shared_ylims(dfs, col::Symbol; pad_frac = 0.08)
    vals = Float64[]
    for d in dfs
        append!(vals, skipmissing(d[!, col]))
    end
    vals = filter(isfinite, vals)
    isempty(vals) && return nothing
    lo, hi = minimum(vals), maximum(vals)
    pad = (hi == lo) ? (hi == 0 ? 1.0 : abs(hi) * 0.1) : (hi - lo) * pad_frac
    return (lo - pad, hi + pad)
end

# Combined side-by-side plot: flowtime (left) + makespan (right), one figure.
# by_df must already be filtered to a single io_position and grouped by (xcol, seriescol).
# flow_ylims/make_ylims (if given) are applied to the respective panel so it can be
# made to share scale with the equivalent plot for a different io_position.
function combined_flow_makespan_plot(by_df, xcol, seriescol, series_values, colors,
                                      xlabel, series_label_fn, title_prefix, io, outfile;
                                      flow_ylims = nothing, make_ylims = nothing)
    p_flow = base_plot("Flow-time")
    plot!(p_flow, xlabel = xlabel, legend = false, bottom_margin = 20px, left_margin = 20px, right_margin = 20px)
    p_make = base_plot("Makespan")
    plot!(p_make, xlabel = xlabel, legend = false, bottom_margin = 20px, left_margin = 12px)

    for (i, sv) in enumerate(series_values)
        rows = sort(filter(r -> r[seriescol] == sv, by_df), xcol)
        isempty(rows) && continue
        lbl = series_label_fn(sv)
        plot!(p_flow, rows[!, xcol], rows.flowtime; label = lbl, color = colors[i], marker = :circle)
        plot!(p_make, rows[!, xcol], rows.makespan; label = lbl, color = colors[i], marker = :circle)
    end

    flow_ylims !== nothing && plot!(p_flow, ylims = flow_ylims)
    make_ylims !== nothing && plot!(p_make, ylims = make_ylims)

    # Shared legend lives in its own column so it can't steal width from either plot
    p_legend = plot(legend = :left, framestyle = :none, grid = false, showaxis = false,
                     legendfontsize = 14)
    for (i, sv) in enumerate(series_values)
        plot!(p_legend, [NaN], [NaN]; label = series_label_fn(sv), color = colors[i],
              marker = :circle, markersize = 8, linewidth = 3)
    end

    combined = plot(p_flow, p_make, p_legend,
                     # widths are fractions of total figure width for [flow, makespan, legend] —
                     # they must sum to 1.0; raise the 3rd value (and lower the other two by the
                     # same total) to make the legend column wider
                     layout = Plots.grid(1, 3, widths = [0.4, 0.4, 0.2]),
                     size = (1300, 520),
                     plot_title = "$title_prefix — I/O $io")
    savefig(combined, outfile)
end

# ─── Analysis 1: Impact of grid size ─────────────────────────────────────────
# x-axis: grid_size (10..100), one line per n_items (number of loads), averaged over escorts
# Separate plot per io_position

grid_sizes  = sort(unique(agg.grid_size))
load_values = sort(unique(agg.n_items))

# Average over n_escorts for each cut, for both io_positions, before plotting —
# so we can compute shared y-axis scales across "left" and "center" per metric.
by_grid_loads_io = Dict{String, DataFrame}()
for io in ["left", "center"]
    sub = filter(r -> r.io_position == io, agg)
    by_grid_loads_io[io] = combine(
        groupby(sub, [:grid_size, :n_items]),
        :makespan      => mean => :makespan,
        :flowtime      => mean => :flowtime,
        :comp_time_sec => mean => :comp_time_sec,
    )
end
grid_metric_ylims = Dict(metric => shared_ylims(values(by_grid_loads_io), metric) for (metric, _, _) in METRICS)

for io in ["left", "center"]
    by_grid_loads = by_grid_loads_io[io]

    for (metric, ylabel, fname) in METRICS
        p = base_plot(ylabel)
        plot!(p, xlabel = "Grid size (N×N)")
        for (i, nl) in enumerate(load_values)
            rows = sort(filter(r -> r.n_items == nl, by_grid_loads), :grid_size)
            isempty(rows) && continue
            plot!(p, rows.grid_size, rows[!, metric];
                  label     = "$nl loads",
                  color     = LOAD_COLORS[i],
                  marker    = :circle,
            )
        end
        grid_metric_ylims[metric] !== nothing && plot!(p, ylims = grid_metric_ylims[metric])
        title!(p, "$(titlecase(fname)) vs grid size — I/O $(io)")
        savefig(p, joinpath(OUT_DIR, "gridsize_$(fname)_$(io).png"))
    end

    # Save aggregated table for this cut
    CSV.write(joinpath(OUT_DIR, "gridsize_$(io).csv"), by_grid_loads)

    combined_flow_makespan_plot(
        by_grid_loads, :grid_size, :n_items, load_values, LOAD_COLORS,
        "Grid size (N×N)", nl -> "$nl loads", "Flow-time vs Makespan by grid size", io,
        joinpath(OUT_DIR, "gridsize_combined_$(io).png");
        flow_ylims = grid_metric_ylims[:flowtime], make_ylims = grid_metric_ylims[:makespan],
    )
end

println("Grid-size plots done.")

# ─── Analysis 2: Impact of number of escorts ─────────────────────────────────
# x-axis: n_escorts (2..20), one line per grid_size, averaged over n_items
# Separate plot per io_position

escort_values = sort(unique(agg.n_escorts))

by_escort_grid_io = Dict{String, DataFrame}()
for io in ["left", "center"]
    sub = filter(r -> r.io_position == io, agg)
    by_escort_grid_io[io] = combine(
        groupby(sub, [:n_escorts, :grid_size]),
        :makespan      => mean => :makespan,
        :flowtime      => mean => :flowtime,
        :comp_time_sec => mean => :comp_time_sec,
    )
end
escort_metric_ylims = Dict(metric => shared_ylims(values(by_escort_grid_io), metric) for (metric, _, _) in METRICS)

for io in ["left", "center"]
    by_escort_grid = by_escort_grid_io[io]

    for (metric, ylabel, fname) in METRICS
        p = base_plot(ylabel)
        plot!(p, xlabel = "Number of escorts")
        for (i, gs) in enumerate(grid_sizes)
            rows = sort(filter(r -> r.grid_size == gs, by_escort_grid), :n_escorts)
            isempty(rows) && continue
            plot!(p, rows.n_escorts, rows[!, metric];
                  label  = "$(gs)×$(gs)",
                  color  = ESCORT_COLORS[i],
                  marker = :circle,
            )
        end
        escort_metric_ylims[metric] !== nothing && plot!(p, ylims = escort_metric_ylims[metric])
        title!(p, "$(titlecase(fname)) vs escorts — I/O $(io)")
        savefig(p, joinpath(OUT_DIR, "escorts_$(fname)_$(io).png"))
    end

    CSV.write(joinpath(OUT_DIR, "escorts_$(io).csv"), by_escort_grid)

    combined_flow_makespan_plot(
        by_escort_grid, :n_escorts, :grid_size, grid_sizes, ESCORT_COLORS,
        "Number of escorts", gs -> "$(gs)×$(gs)", "Flow-time vs Makespan by escorts", io,
        joinpath(OUT_DIR, "escorts_combined_$(io).png");
        flow_ylims = escort_metric_ylims[:flowtime], make_ylims = escort_metric_ylims[:makespan],
    )
end

println("Escort plots done.")

# ─── Analysis 3: Impact of number of loads ───────────────────────────────────
# x-axis: n_items (number of loads, 2..10), one line per grid_size, averaged over escorts
# Separate plot per io_position

by_loads_grid_io = Dict{String, DataFrame}()
for io in ["left", "center"]
    sub = filter(r -> r.io_position == io, agg)
    by_loads_grid_io[io] = combine(
        groupby(sub, [:n_items, :grid_size]),
        :makespan      => mean => :makespan,
        :flowtime      => mean => :flowtime,
        :comp_time_sec => mean => :comp_time_sec,
    )
end
loads_metric_ylims = Dict(metric => shared_ylims(values(by_loads_grid_io), metric) for (metric, _, _) in METRICS)

for io in ["left", "center"]
    by_loads_grid = by_loads_grid_io[io]

    for (metric, ylabel, fname) in METRICS
        p = base_plot(ylabel)
        plot!(p, xlabel = "Number of loads")
        for (i, gs) in enumerate(grid_sizes)
            rows = sort(filter(r -> r.grid_size == gs, by_loads_grid), :n_items)
            isempty(rows) && continue
            plot!(p, rows.n_items, rows[!, metric];
                  label  = "$(gs)×$(gs)",
                  color  = GRID_COLORS[i],
                  marker = :circle,
            )
        end
        loads_metric_ylims[metric] !== nothing && plot!(p, ylims = loads_metric_ylims[metric])
        title!(p, "$(titlecase(fname)) vs loads — I/O $(io)")
        savefig(p, joinpath(OUT_DIR, "loads_$(fname)_$(io).png"))
    end

    CSV.write(joinpath(OUT_DIR, "loads_$(io).csv"), by_loads_grid)

    combined_flow_makespan_plot(
        by_loads_grid, :n_items, :grid_size, grid_sizes, GRID_COLORS,
        "Number of loads", gs -> "$(gs)×$(gs)", "Flow-time vs Makespan by loads", io,
        joinpath(OUT_DIR, "loads_combined_$(io).png");
        flow_ylims = loads_metric_ylims[:flowtime], make_ylims = loads_metric_ylims[:makespan],
    )
end

println("Load plots done.")
println("\nAll outputs in: $OUT_DIR")
