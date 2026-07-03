using CSV
using DataFrames
using Statistics
using Plots
using Plots.PlotMeasures

const CSV_PATH = raw"C:\codestuff\PBS\testinstances_26\results_summary.csv"
const OUT_DIR  = raw"C:\codestuff\PBS\pbsHeuristic\paperstuff"

df = CSV.read(CSV_PATH, DataFrame)

agg = combine(
    groupby(df, [:grid_size, :n_items, :n_escorts]),
    :makespan      => mean => :makespan,
    :flowtime      => mean => :flowtime,
    :comp_time_sec => mean => :comp_time_sec,
)

grid_sizes    = sort(unique(agg.grid_size))
item_values   = sort(unique(agg.n_items))
escort_values = sort(unique(agg.n_escorts))

METRICS = [
    (:makespan,      "Makespan (steps)",       "makespan", :viridis),
    (:flowtime,      "Flowtime (sum steps)",   "flowtime", :plasma),
    (:comp_time_sec, "Computation time (s)",   "comptime", :inferno),
]

function build_surface(agg, xvals, yvals, xcol, ycol, metric)
    Z = Matrix{Float64}(undef, length(yvals), length(xvals))
    for (j, xv) in enumerate(xvals), (i, yv) in enumerate(yvals)
        rows = filter(r -> r[xcol] == xv && r[ycol] == yv, agg)
        Z[i, j] = isempty(rows) ? NaN : mean(rows[!, metric])
    end
    return Z
end

# In Plots.jl surface, the x-axis has max at the back-left and the y-axis has
# min at the back-right (first array element = far end). To put max of BOTH
# axes at the back, keep x ascending and reverse y (so its max is index 1 = far).
function orient_axes(xvals, yvals, Z)
    xout = sort(xvals)               # ascending  → max at back-left
    yout = sort(yvals, rev=true)     # descending → max at back-right (far end)
    xperm = sortperm(xvals)
    yperm = sortperm(yvals, rev=true)
    Zout  = Z[yperm, xperm]
    return xout, yout, Zout
end

function make_surface(xvals, yvals, Z, xlabel, ylabel, zlabel, title_str, cmap, outpath)
    xp, yp, Zp = orient_axes(xvals, yvals, Z)
    p = surface(
        xp, yp, Zp;
        xlabel    = xlabel,
        ylabel    = ylabel,
        zlabel    = zlabel,
        title     = title_str,
        color     = cmap,
        camera    = (45, 30),
        linewidth = 0.5,
        size      = (800, 600),
    )
    savefig(p, outpath)
    println("Saved $(basename(outpath))")
end

# ─── Surface 1: x=grid_size, y=n_items (averaged over escorts) ───────────────

for (metric, zlabel, fname, cmap) in METRICS
    Z = build_surface(agg, grid_sizes, item_values, :grid_size, :n_items, metric)
    make_surface(
        grid_sizes, item_values, Z,
        "Grid size (N)", "Number of items", zlabel,
        "$zlabel\n(averaged over escort counts)",
        cmap, joinpath(OUT_DIR, "3d_gridsize_items_$(fname).png"),
    )
end

# ─── Surface 2: x=grid_size, y=n_escorts (averaged over items) ───────────────

for (metric, zlabel, fname, cmap) in METRICS
    Z = build_surface(agg, grid_sizes, escort_values, :grid_size, :n_escorts, metric)
    make_surface(
        grid_sizes, escort_values, Z,
        "Grid size (N)", "Number of escorts", zlabel,
        "$zlabel\n(averaged over item counts)",
        cmap, joinpath(OUT_DIR, "3d_gridsize_escorts_$(fname).png"),
    )
end

# ─── Surface 3: x=n_items, y=n_escorts (averaged over grid sizes) ────────────

for (metric, zlabel, fname, cmap) in METRICS
    Z = build_surface(agg, item_values, escort_values, :n_items, :n_escorts, metric)
    make_surface(
        item_values, escort_values, Z,
        "Number of items", "Number of escorts", zlabel,
        "$zlabel\n(averaged over grid sizes)",
        cmap, joinpath(OUT_DIR, "3d_items_escorts_$(fname).png"),
    )
end

println("\nAll 3D plots saved to $OUT_DIR")
