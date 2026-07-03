using CSV, DataFrames, Statistics, Printf
using StatsPlots, Plots

df = CSV.read(raw"C:\codestuff\PBS\outputtestn4.csv", DataFrame)

# ── Filter: only rows where ILP found a feasible solution ─────────────────────
function pos_num(v)
    ismissing(v) && return false
    isa(v, Number) && return v > 0
    n = tryparse(Float64, string(v))
    return n !== nothing && n > 0
end
df = filter(row -> pos_num(row[Symbol("ILP makespan")]) && pos_num(row[Symbol("ILP flowtime")]), df)

# ── Compute percentage gaps ───────────────────────────────────────────────────
ilp_ms  = parse.(Float64, string.(df[!, Symbol("ILP makespan")]))
ilp_ft  = parse.(Float64, string.(df[!, Symbol("ILP flowtime")]))
df.makespan_gap = (df.makespan_heuristic .- ilp_ms) ./ ilp_ms .* 100
df.flowtime_gap = (df.flowtime_heuristic .- ilp_ft) ./ ilp_ft .* 100

escorts_col = df[!, Symbol("# Escorts")]
println("Feasible rows: $(nrow(df))  |  Escort counts: $(sort(unique(escorts_col)))")
println()

# ── Build summary table ───────────────────────────────────────────────────────
function gap_stats(v)
    v = filter(isfinite, v)
    isempty(v) && return (n=0, mean=NaN, min=NaN, q25=NaN, med=NaN, q75=NaN, max=NaN)
    q = quantile(v, [0.25, 0.50, 0.75])
    return (n=length(v), mean=mean(v), min=minimum(v),
            q25=q[1], med=q[2], q75=q[3], max=maximum(v))
end

escort_groups = sort(unique(df[!, Symbol("# Escorts")]))
metrics = [("Makespan gap %", :makespan_gap), ("Flowtime gap %", :flowtime_gap)]

# ── Plot: grouped box plots, one box per escort count per metric ───────────────
esc_labels  = string.(escort_groups)
ms_data     = [df[df[!, Symbol("# Escorts")] .== e, :makespan_gap] for e in escort_groups]
ft_data     = [df[df[!, Symbol("# Escorts")] .== e, :flowtime_gap] for e in escort_groups]

# Build x-positions with a small offset so makespan and flowtime boxes sit side-by-side
xs_ms = Float64.(1:length(escort_groups)) .- 0.2
xs_ft = Float64.(1:length(escort_groups)) .+ 0.2

p = plot(
    title  = "Heuristic vs ILP gap by escort count (10x10, 4 loads, 1 IO)",
    ylabel = "Gap (%)",
    xlabel = "Number of escorts",
    legend = :topright,
    xticks = (1:length(escort_groups), esc_labels),
    size   = (800, 500),
    grid   = true,
    gridalpha = 0.3,
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
savefig(joinpath(outdir, "gap_analysis.png"))

for (metric_name, col) in metrics
    println("═"^78)
    println("  $metric_name")
    println("═"^78)
    @printf("  %-10s  %5s  %7s  %7s  %7s  %7s  %7s  %7s\n",
            "Escorts", "n", "Mean", "Min", "Q25", "Median", "Q75", "Max")
    println("  " * "-"^74)
    for esc in escort_groups
        sub = df[df[!, Symbol("# Escorts")] .== esc, col]
        s = gap_stats(sub)
        s.n == 0 && continue
        @printf("  %-10d  %5d  %7.1f  %7.1f  %7.1f  %7.1f  %7.1f  %7.1f\n",
                esc, s.n, s.mean, s.min, s.q25, s.med, s.q75, s.max)
    end
    println()

    # Overall row
    s = gap_stats(df[:, col])
    @printf("  %-10s  %5d  %7.1f  %7.1f  %7.1f  %7.1f  %7.1f  %7.1f\n",
            "ALL", s.n, s.mean, s.min, s.q25, s.med, s.q75, s.max)
    println()
end
