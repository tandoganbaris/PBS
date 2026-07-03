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
    (:makespan,      "Makespan (steps)",          "makespan"),
    (:flowtime,      "Flowtime (sum of steps)",   "flowtime"),
    (:comp_time_sec, "Computation time (s)",      "comptime"),
]

const ITEM_COLORS  = [:blue, :orange, :green, :red, :purple]
const ESCORT_COLORS = palette(:tab10)[1:10]

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

# ─── Analysis 1: Impact of grid size ─────────────────────────────────────────
# x-axis: grid_size (10..100), one line per n_items, averaged over escorts
# Separate plot per io_position

grid_sizes  = sort(unique(agg.grid_size))
item_values = sort(unique(agg.n_items))

for io in ["left", "center"]
    sub = filter(r -> r.io_position == io, agg)
    # Average over n_escorts for this cut
    by_grid_items = combine(
        groupby(sub, [:grid_size, :n_items]),
        :makespan      => mean => :makespan,
        :flowtime      => mean => :flowtime,
        :comp_time_sec => mean => :comp_time_sec,
    )

    for (metric, ylabel, fname) in METRICS
        p = base_plot(ylabel)
        plot!(p, xlabel = "Grid size (N×N)")
        for (i, ni) in enumerate(item_values)
            rows = sort(filter(r -> r.n_items == ni, by_grid_items), :grid_size)
            isempty(rows) && continue
            plot!(p, rows.grid_size, rows[!, metric];
                  label     = "$ni items",
                  color     = ITEM_COLORS[i],
                  marker    = :circle,
            )
        end
        title!(p, "$(titlecase(fname)) vs grid size — IO $(io)")
        savefig(p, joinpath(OUT_DIR, "gridsize_$(fname)_$(io).png"))
    end

    # Save aggregated table for this cut
    CSV.write(joinpath(OUT_DIR, "gridsize_$(io).csv"), by_grid_items)
end

println("Grid-size plots done.")

# ─── Analysis 2: Impact of number of escorts ─────────────────────────────────
# x-axis: n_escorts (2..20), one line per grid_size, averaged over n_items
# Separate plot per io_position

escort_values = sort(unique(agg.n_escorts))

for io in ["left", "center"]
    sub = filter(r -> r.io_position == io, agg)
    by_escort_grid = combine(
        groupby(sub, [:n_escorts, :grid_size]),
        :makespan      => mean => :makespan,
        :flowtime      => mean => :flowtime,
        :comp_time_sec => mean => :comp_time_sec,
    )

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
        title!(p, "$(titlecase(fname)) vs escorts — IO $(io)")
        savefig(p, joinpath(OUT_DIR, "escorts_$(fname)_$(io).png"))
    end

    CSV.write(joinpath(OUT_DIR, "escorts_$(io).csv"), by_escort_grid)
end

println("Escort plots done.")
println("\nAll outputs in: $OUT_DIR")
