using CSV, DataFrames, Statistics, Printf
using StatsPlots, Plots

df  = CSV.read(raw"C:\codestuff\PBS\4loadstestleave.csv", DataFrame)
df2 = CSV.read(raw"C:\codestuff\PBS\4loadstestleaveP2.csv", DataFrame)
# ── Filter: only rows where ILP found a feasible solution ─────────────────────
function pos_num(v)
    ismissing(v) && return false
    isa(v, Number) && return v > 0
    n = tryparse(Float64, string(v))
    return n !== nothing && n > 0
end
df = filter(row -> pos_num(row[Symbol("ILP makespan")]) && pos_num(row[Symbol("ILP flowtime")]), df)

# ── Take the best (lowest) heuristic result per row, across df and df2 ────────
# df2 is a second heuristic run of the same instances (parallel/randomized);
# for each id, keep whichever of df/df2 scored lower on each metric.
ms_lookup = Dict(zip(df2.id, df2.makespan_heuristic))
ft_lookup = Dict(zip(df2.id, df2.flowtime_heuristic))
df.makespan_heuristic = [haskey(ms_lookup, id) ? min(v, ms_lookup[id]) : v
                          for (id, v) in zip(df.id, df.makespan_heuristic)]
df.flowtime_heuristic = [haskey(ft_lookup, id) ? min(v, ft_lookup[id]) : v
                          for (id, v) in zip(df.id, df.flowtime_heuristic)]

# ── Compute percentage gaps ───────────────────────────────────────────────────
ilp_ms  = parse.(Float64, string.(df[!, Symbol("ILP makespan")]))
ilp_ft  = parse.(Float64, string.(df[!, Symbol("ILP flowtime")]))
df.makespan_gap = (df.makespan_heuristic .- ilp_ms) ./ ilp_ms .* 100
df.flowtime_gap = (df.flowtime_heuristic .- ilp_ft) ./ ilp_ft .* 100

# ── Category: grid size (Lx x Ly), ordered by (Lx, Ly) ────────────────────────
gridkey(s) = (p = parse.(Int, split(strip(String(s)), 'x')); (p[1], p[2]))
df.grid = strip.(String.(df[!, Symbol("Lx x Ly")]))
grid_groups = sort(unique(df.grid), by = gridkey)
println("Feasible rows: $(nrow(df))  |  Grid sizes: $(grid_groups)")
println()

# ── Build summary table ───────────────────────────────────────────────────────
function gap_stats(v)
    v = filter(isfinite, v)
    isempty(v) && return (n=0, mean=NaN, min=NaN, q25=NaN, med=NaN, q75=NaN, max=NaN)
    q = quantile(v, [0.25, 0.50, 0.75])
    return (n=length(v), mean=mean(v), min=minimum(v),
            q25=q[1], med=q[2], q75=q[3], max=maximum(v))
end

metrics = [("Makespan gap %", :makespan_gap), ("Flowtime gap %", :flowtime_gap)]

# ── Plot: grouped box plots, one box per grid size per metric ─────────────────
grid_labels = string.(grid_groups)
ms_data     = [df[df.grid .== g, :makespan_gap] for g in grid_groups]
ft_data     = [df[df.grid .== g, :flowtime_gap] for g in grid_groups]

xs_ms = Float64.(1:length(grid_groups)) .- 0.2
xs_ft = Float64.(1:length(grid_groups)) .+ 0.2

p = plot(
    title  = "Heuristic vs ILP gap by grid size",
    ylabel = "Gap (%)",
    xlabel = "Grid size",
    legend = :topright,
    xticks = (1:length(grid_groups), grid_labels),
    size   = (800, 500),
    grid   = true,
    gridalpha = 0.3,
    left_margin   = 8Plots.mm,
    bottom_margin = 8Plots.mm,
    right_margin  = 5Plots.mm,
    top_margin    = 5Plots.mm,
)

for (i, (xpos, data)) in enumerate(zip(xs_ms, ms_data))
    boxplot!(p, [xpos], data,
        label      = i == 1 ? "Makespan gap" : "",
        color      = :steelblue,
        fillalpha  = 0.6,
        whisker_width = 0.3,
        bar_width  = 0.35,
        outliers   = true,
    )
end

for (i, (xpos, data)) in enumerate(zip(xs_ft, ft_data))
    boxplot!(p, [xpos], data,
        label      = i == 1 ? "Flowtime gap" : "",
        color      = :tomato,
        fillalpha  = 0.6,
        whisker_width = 0.3,
        bar_width  = 0.35,
        outliers   = true,
    )
end

display(p)
outdir = raw"C:\codestuff\PBS\paperplots"
mkpath(outdir)
savefig(joinpath(outdir, "gap_analysis_bygrid.png"))

summary_rows = NamedTuple[]
for (metric_name, col) in metrics
    println("═"^78)
    println("  $metric_name")
    println("═"^78)
    @printf("  %-10s  %5s  %7s  %7s  %7s  %7s  %7s  %7s\n",
            "Grid", "n", "Mean", "Min", "Q25", "Median", "Q75", "Max")
    println("  " * "-"^74)
    for g in grid_groups
        sub = df[df.grid .== g, col]
        s = gap_stats(sub)
        s.n == 0 && continue
        @printf("  %-10s  %5d  %7.2f  %7.2f  %7.2f  %7.2f  %7.2f  %7.2f\n",
                g, s.n, s.mean, s.min, s.q25, s.med, s.q75, s.max)
        push!(summary_rows, (metric = metric_name, grid = g, n = s.n,
                              mean = s.mean, min = s.min, q25 = s.q25, median = s.med,
                              q75 = s.q75, max = s.max))
    end
    println()

    # Overall row
    s = gap_stats(df[:, col])
    @printf("  %-10s  %5d  %7.2f  %7.2f  %7.2f  %7.2f  %7.2f  %7.2f\n",
            "ALL", s.n, s.mean, s.min, s.q25, s.med, s.q75, s.max)
    push!(summary_rows, (metric = metric_name, grid = "ALL", n = s.n,
                          mean = s.mean, min = s.min, q25 = s.q25, median = s.med,
                          q75 = s.q75, max = s.max))
    println()
end

summary_df = DataFrame(summary_rows)
CSV.write(joinpath(outdir, "gap_analysis_summary_bygrid.csv"), summary_df)
println("wrote $(joinpath(outdir, "gap_analysis_summary_bygrid.csv"))")
