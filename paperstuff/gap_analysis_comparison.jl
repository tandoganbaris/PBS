using CSV, DataFrames, Statistics, Printf
using StatsPlots, Plots

# ── Head-to-head: our heuristic vs. Raviv's heuristic, both vs. ILP makespan ──
# df  = 4loadstestleaveP2.csv — our parallel/randomized heuristic run
# df2 = 4loadstestleave.csv   — our deterministic heuristic run
# "Heuristic UB makespan" — Raviv's heuristic, identical between the two files
#   (verified in gap_analysis_ravivUB.jl), so either file's value is authoritative.
# With USE_P2 = true, our result per instance = best (lowest) makespan across
# the two runs. With USE_P2 = false, the P2 (parallel) run is skipped entirely
# and only the original deterministic "leave" file (df2) is used.

const USE_P2 = false  # set true to also read/merge the P2 (parallel) run

df2 = CSV.read(raw"C:\codestuff\PBS\4loadstestleave.csv", DataFrame)

function pos_num(v)
    ismissing(v) && return false
    isa(v, Number) && return v > 0
    n = tryparse(Float64, string(v))
    return n !== nothing && n > 0
end
df2 = filter(row -> pos_num(row[Symbol("ILP makespan")]), df2)

ilp_lookup   = Dict(zip(df2.id, df2[!, Symbol("ILP makespan")]))
raviv_lookup = Dict(zip(df2.id, df2[!, Symbol("Heuristic UB makespan")]))
esc_lookup   = Dict(zip(df2.id, df2[!, Symbol("# Escorts")]))

if USE_P2
    df = CSV.read(raw"C:\codestuff\PBS\4loadstestleaveP2.csv", DataFrame)
    df = filter(row -> pos_num(row[Symbol("ILP makespan")]), df)

    ids = intersect(df.id, df2.id)
    mine1_lookup = Dict(zip(df.id,  df.makespan_heuristic))
    mine2_lookup = Dict(zip(df2.id, df2.makespan_heuristic))
    mine_lookup  = Dict(id => min(mine1_lookup[id], mine2_lookup[id]) for id in ids)
else
    ids = df2.id
    mine_lookup = Dict(zip(df2.id, df2.makespan_heuristic))
end

combined = DataFrame(
    id           = collect(ids),
    ilp_makespan = [parse(Float64, string(ilp_lookup[id])) for id in ids],
    mine         = [mine_lookup[id] for id in ids],
    raviv        = [parse(Float64, string(raviv_lookup[id])) for id in ids],
    escorts      = [esc_lookup[id] for id in ids],
)

combined.mine_gap  = (combined.mine  .- combined.ilp_makespan) ./ combined.ilp_makespan .* 100
combined.raviv_gap = (combined.raviv .- combined.ilp_makespan) ./ combined.ilp_makespan .* 100
combined.mine_wins = combined.mine .< combined.raviv
combined.ties       = combined.mine .== combined.raviv

escort_groups = sort(unique(combined.escorts))
println("Feasible/matched rows: $(nrow(combined))  |  Escort counts: $(escort_groups)")
println()

# ── Comparison table ────────────────────────────────────────────────────────────
function gap_stats(v)
    v = filter(isfinite, v)
    isempty(v) && return (n=0, mean=NaN, med=NaN)
    return (n=length(v), mean=mean(v), med=median(v))
end

println("═"^100)
@printf("  %-8s  %5s  %14s  %14s  %14s  %14s  %10s  %8s\n",
        "Escorts", "n", "Mine mean %", "Mine med %", "Raviv mean %", "Raviv med %", "Mine wins", "Ties")
println("  " * "-"^96)

rows = NamedTuple[]
for esc in escort_groups
    sub = combined[combined.escorts .== esc, :]
    sm = gap_stats(sub.mine_gap)
    sr = gap_stats(sub.raviv_gap)
    win_pct = 100 * count(sub.mine_wins) / nrow(sub)
    tie_pct = 100 * count(sub.ties) / nrow(sub)
    @printf("  %-8d  %5d  %14.1f  %14.1f  %14.1f  %14.1f  %9.1f%%  %7.1f%%\n",
            esc, sm.n, sm.mean, sm.med, sr.mean, sr.med, win_pct, tie_pct)
    push!(rows, (escorts = string(esc), n = sm.n,
                  mine_mean_gap = sm.mean, mine_median_gap = sm.med,
                  raviv_mean_gap = sr.mean, raviv_median_gap = sr.med,
                  mine_wins_pct = win_pct, ties_pct = tie_pct))
end
println()

sm = gap_stats(combined.mine_gap)
sr = gap_stats(combined.raviv_gap)
win_pct = 100 * count(combined.mine_wins) / nrow(combined)
tie_pct = 100 * count(combined.ties) / nrow(combined)
@printf("  %-8s  %5d  %14.1f  %14.1f  %14.1f  %14.1f  %9.1f%%  %7.1f%%\n",
        "ALL", sm.n, sm.mean, sm.med, sr.mean, sr.med, win_pct, tie_pct)
push!(rows, (escorts = "ALL", n = sm.n,
              mine_mean_gap = sm.mean, mine_median_gap = sm.med,
              raviv_mean_gap = sr.mean, raviv_median_gap = sr.med,
              mine_wins_pct = win_pct, ties_pct = tie_pct))
println()

outdir = raw"C:\codestuff\PBS\paperplots"
mkpath(outdir)
comparison_df = DataFrame(rows)
CSV.write(joinpath(outdir, "gap_analysis_comparison_summary.csv"), comparison_df)
CSV.write(joinpath(outdir, "gap_analysis_comparison_rows.csv"), combined)

# ── Plot: grouped box plots, mine vs Raviv per escort count ────────────────────
esc_labels = string.(escort_groups)
mine_data  = [combined[combined.escorts .== e, :mine_gap]  for e in escort_groups]
raviv_data = [combined[combined.escorts .== e, :raviv_gap] for e in escort_groups]

xs_mine  = Float64.(1:length(escort_groups)) .- 0.2
xs_raviv = Float64.(1:length(escort_groups)) .+ 0.2

p = plot(
    title  = "Our heuristic vs Raviv heuristic — gap to ILP makespan",
    ylabel = "Gap (%)",
    xlabel = "Number of escorts",
    legend = :topright,
    xticks = (1:length(escort_groups), esc_labels),
    size   = (800, 500),
    grid   = true,
    gridalpha = 0.3,
    left_margin   = 8Plots.mm,
    bottom_margin = 8Plots.mm,
    right_margin  = 5Plots.mm,
    top_margin    = 5Plots.mm,
)

for (i, (xpos, data)) in enumerate(zip(xs_mine, mine_data))
    boxplot!(p, [xpos], data,
        label      = i == 1 ? "Mine" : "",
        color      = :steelblue,
        fillalpha  = 0.6,
        whisker_width = 0.3,
        bar_width  = 0.35,
        outliers   = true,
    )
end

for (i, (xpos, data)) in enumerate(zip(xs_raviv, raviv_data))
    boxplot!(p, [xpos], data,
        label      = i == 1 ? "Raviv" : "",
        color      = :darkorange,
        fillalpha  = 0.6,
        whisker_width = 0.3,
        bar_width  = 0.35,
        outliers   = true,
    )
end

display(p)
savefig(joinpath(outdir, "gap_analysis_comparison.png"))
