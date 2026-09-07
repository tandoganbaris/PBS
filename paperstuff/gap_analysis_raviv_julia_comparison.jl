using CSV, DataFrames, Statistics, Printf
using StatsPlots, Plots

# ── Head-to-head: our heuristic vs. the Julia port of Raviv's greedy heuristic ──
# df  = 4loadstestleave.csv           — our deterministic heuristic run
# df2 = 4loadstestleaveP2.csv         — our parallel/randomized heuristic run
# df3 = 4loadstestleave_ravivJulia.csv — raviv_test.jl's run of onestep_heuristic_raviv.jl
#       over the exact same instances (raviv_julia_makespan/flowtime/movements),
#       verified to match the CSV's own "Heuristic UB makespan"/"movements"
#       columns exactly (1500/1500) — see raviv_test.jl.
# "Mine" per instance = best (lowest) result across the two of our own runs,
# same as gap_analysis_comparison.jl. Now includes flowtime too, since
# raviv_test.jl produced a flowtime figure that wasn't in the original CSVs.

df  = CSV.read(raw"C:\codestuff\PBS\4loadstestleave.csv", DataFrame)
df2 = CSV.read(raw"C:\codestuff\PBS\4loadstestleaveP2.csv", DataFrame)
df3 = CSV.read(raw"C:\codestuff\PBS\4loadstestleave_ravivJulia.csv", DataFrame)

function pos_num(v)
    ismissing(v) && return false
    isa(v, Number) && return v > 0
    n = tryparse(Float64, string(v))
    return n !== nothing && n > 0
end
df  = filter(row -> pos_num(row[Symbol("ILP makespan")]) && pos_num(row[Symbol("ILP flowtime")]), df)
df2 = filter(row -> pos_num(row[Symbol("ILP makespan")]) && pos_num(row[Symbol("ILP flowtime")]), df2)
df3 = filter(row -> pos_num(row[Symbol("ILP makespan")]) && pos_num(row[Symbol("ILP flowtime")]), df3)

ids = intersect(df.id, df2.id, df3.id)

ilp_ms_lookup = Dict(zip(df.id, df[!, Symbol("ILP makespan")]))
ilp_ft_lookup = Dict(zip(df.id, df[!, Symbol("ILP flowtime")]))
esc_lookup    = Dict(zip(df.id, df[!, Symbol("# Escorts")]))

mine_ms1 = Dict(zip(df.id,  df.makespan_heuristic))
mine_ms2 = Dict(zip(df2.id, df2.makespan_heuristic))
mine_ft1 = Dict(zip(df.id,  df.flowtime_heuristic))
mine_ft2 = Dict(zip(df2.id, df2.flowtime_heuristic))

raviv_ms_lookup = Dict(zip(df3.id, df3.raviv_julia_makespan))
raviv_ft_lookup = Dict(zip(df3.id, df3.raviv_julia_flowtime))

combined = DataFrame(
    id           = ids,
    ilp_makespan = [parse(Float64, string(ilp_ms_lookup[id])) for id in ids],
    ilp_flowtime = [parse(Float64, string(ilp_ft_lookup[id])) for id in ids],
    mine_makespan  = [min(mine_ms1[id], mine_ms2[id]) for id in ids],
    mine_flowtime  = [min(mine_ft1[id], mine_ft2[id]) for id in ids],
    raviv_makespan = [Float64(raviv_ms_lookup[id]) for id in ids],
    raviv_flowtime = [Float64(raviv_ft_lookup[id]) for id in ids],
    escorts        = [esc_lookup[id] for id in ids],
)

combined.mine_ms_gap  = (combined.mine_makespan  .- combined.ilp_makespan) ./ combined.ilp_makespan .* 100
combined.raviv_ms_gap = (combined.raviv_makespan .- combined.ilp_makespan) ./ combined.ilp_makespan .* 100
combined.mine_ft_gap  = (combined.mine_flowtime  .- combined.ilp_flowtime) ./ combined.ilp_flowtime .* 100
combined.raviv_ft_gap = (combined.raviv_flowtime .- combined.ilp_flowtime) ./ combined.ilp_flowtime .* 100

combined.mine_wins_ms = combined.mine_makespan .< combined.raviv_makespan
combined.ties_ms      = combined.mine_makespan .== combined.raviv_makespan
combined.mine_wins_ft = combined.mine_flowtime .< combined.raviv_flowtime
combined.ties_ft      = combined.mine_flowtime .== combined.raviv_flowtime

escort_groups = sort(unique(combined.escorts))
println("Matched rows: $(nrow(combined))  |  Escort counts: $(escort_groups)")
println()

function gap_stats(v)
    v = filter(isfinite, v)
    isempty(v) && return (n=0, mean=NaN, med=NaN)
    return (n=length(v), mean=mean(v), med=median(v))
end

function print_and_collect_table(title, gap_col_mine, gap_col_raviv, wins_col, ties_col, metric_label)
    println("═"^100)
    println("  $title")
    println("═"^100)
    @printf("  %-8s  %5s  %14s  %14s  %14s  %14s  %10s  %8s\n",
            "Escorts", "n", "Mine mean %", "Mine med %", "Raviv mean %", "Raviv med %", "Mine wins", "Ties")
    println("  " * "-"^96)

    rows = NamedTuple[]
    for esc in escort_groups
        sub = combined[combined.escorts .== esc, :]
        sm = gap_stats(sub[!, gap_col_mine])
        sr = gap_stats(sub[!, gap_col_raviv])
        win_pct = 100 * count(sub[!, wins_col]) / nrow(sub)
        tie_pct = 100 * count(sub[!, ties_col]) / nrow(sub)
        @printf("  %-8d  %5d  %14.1f  %14.1f  %14.1f  %14.1f  %9.1f%%  %7.1f%%\n",
                esc, sm.n, sm.mean, sm.med, sr.mean, sr.med, win_pct, tie_pct)
        push!(rows, (metric = metric_label, escorts = string(esc), n = sm.n,
                      mine_mean_gap = sm.mean, mine_median_gap = sm.med,
                      raviv_mean_gap = sr.mean, raviv_median_gap = sr.med,
                      mine_wins_pct = win_pct, ties_pct = tie_pct))
    end
    println()

    sm = gap_stats(combined[!, gap_col_mine])
    sr = gap_stats(combined[!, gap_col_raviv])
    win_pct = 100 * count(combined[!, wins_col]) / nrow(combined)
    tie_pct = 100 * count(combined[!, ties_col]) / nrow(combined)
    @printf("  %-8s  %5d  %14.1f  %14.1f  %14.1f  %14.1f  %9.1f%%  %7.1f%%\n",
            "ALL", sm.n, sm.mean, sm.med, sr.mean, sr.med, win_pct, tie_pct)
    push!(rows, (metric = metric_label, escorts = "ALL", n = sm.n,
                  mine_mean_gap = sm.mean, mine_median_gap = sm.med,
                  raviv_mean_gap = sr.mean, raviv_median_gap = sr.med,
                  mine_wins_pct = win_pct, ties_pct = tie_pct))
    println()
    return rows
end

ms_rows = print_and_collect_table("Makespan gap to ILP — Mine vs Raviv (Julia)",
                                   :mine_ms_gap, :raviv_ms_gap, :mine_wins_ms, :ties_ms, "Makespan gap %")
ft_rows = print_and_collect_table("Flowtime gap to ILP — Mine vs Raviv (Julia)",
                                   :mine_ft_gap, :raviv_ft_gap, :mine_wins_ft, :ties_ft, "Flowtime gap %")

outdir = raw"C:\codestuff\PBS\paperplots"
mkpath(outdir)

comparison_df = DataFrame(vcat(ms_rows, ft_rows))
CSV.write(joinpath(outdir, "gap_analysis_raviv_julia_comparison_summary.csv"), comparison_df)
CSV.write(joinpath(outdir, "gap_analysis_raviv_julia_comparison_rows.csv"), combined)

# ── Plots: grouped box plots, mine vs Raviv(Julia) per escort count ────────────
function comparison_boxplot(gap_col_mine, gap_col_raviv, title, filename)
    esc_labels = string.(escort_groups)
    mine_data  = [combined[combined.escorts .== e, gap_col_mine]  for e in escort_groups]
    raviv_data = [combined[combined.escorts .== e, gap_col_raviv] for e in escort_groups]

    xs_mine  = Float64.(1:length(escort_groups)) .- 0.2
    xs_raviv = Float64.(1:length(escort_groups)) .+ 0.2

    p = plot(
        title  = title,
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
            label = i == 1 ? "Mine" : "", color = :steelblue, fillalpha = 0.6,
            whisker_width = 0.3, bar_width = 0.35, outliers = true)
    end
    for (i, (xpos, data)) in enumerate(zip(xs_raviv, raviv_data))
        boxplot!(p, [xpos], data,
            label = i == 1 ? "Raviv (Julia)" : "", color = :darkorange, fillalpha = 0.6,
            whisker_width = 0.3, bar_width = 0.35, outliers = true)
    end

    display(p)
    savefig(joinpath(outdir, filename))
end

comparison_boxplot(:mine_ms_gap, :raviv_ms_gap,
    "Our heuristic vs Raviv (Julia) — gap to ILP makespan", "gap_analysis_raviv_julia_comparison_makespan.png")
comparison_boxplot(:mine_ft_gap, :raviv_ft_gap,
    "Our heuristic vs Raviv (Julia) — gap to ILP flowtime", "gap_analysis_raviv_julia_comparison_flowtime.png")
