using CSV, DataFrames, Statistics, Printf
using StatsPlots, Plots

# ── Gap analysis for the OTHER author's heuristic (Raviv), read from the
# "Heuristic UB makespan" column. This baseline is independent of our own
# heuristic runs — df (P2, parallel/randomized) and df2 (deterministic) are
# just two re-runs of the same instances, so "Heuristic UB makespan" is
# identical between them for a given id (verified: 1500/1500 ids match).
# With USE_P2 = true we read both, sanity-check that assumption, and fall
# back to whichever file has the value if one is ever missing. With
# USE_P2 = false, the P2 (parallel) run is skipped entirely and only the
# original deterministic "leave" file (df2) is used.

const USE_P2 = false  # set true to also read/merge the P2 (parallel) run

df2 = CSV.read(raw"C:\codestuff\PBS\4loadstestleave.csv", DataFrame)    # deterministic heuristic run

function pos_num(v)
    ismissing(v) && return false
    isa(v, Number) && return v > 0
    n = tryparse(Float64, string(v))
    return n !== nothing && n > 0
end
df2 = filter(row -> pos_num(row[Symbol("ILP makespan")]), df2)

if USE_P2
    df = CSV.read(raw"C:\codestuff\PBS\4loadstestleaveP2.csv", DataFrame)  # parallel heuristic run
    df = filter(row -> pos_num(row[Symbol("ILP makespan")]), df)

    # ── Sanity-check: Heuristic UB makespan should agree between the two runs ──
    ub1 = Dict(zip(df.id,  df[!,  Symbol("Heuristic UB makespan")]))
    ub2 = Dict(zip(df2.id, df2[!, Symbol("Heuristic UB makespan")]))
    common = intersect(keys(ub1), keys(ub2))
    mismatches = [id for id in common if ub1[id] != ub2[id]]
    if !isempty(mismatches)
        println("WARNING: Heuristic UB makespan disagrees between the two CSVs for $(length(mismatches)) ids — using the P2 (parallel) file's value for those.")
    end

    # ── Build one row per instance: prefer df, fall back to df2 ───────────────
    ids = union(df.id, df2.id)
    ilp_lookup = merge(Dict(zip(df2.id, df2[!, Symbol("ILP makespan")])), Dict(zip(df.id, df[!, Symbol("ILP makespan")])))
    ub_lookup  = merge(ub2, ub1)  # df (P2) wins on conflicts, per the warning above
    esc_lookup = merge(Dict(zip(df2.id, df2[!, Symbol("# Escorts")])), Dict(zip(df.id, df[!, Symbol("# Escorts")])))
else
    ids = df2.id
    ilp_lookup = Dict(zip(df2.id, df2[!, Symbol("ILP makespan")]))
    ub_lookup  = Dict(zip(df2.id, df2[!, Symbol("Heuristic UB makespan")]))
    esc_lookup = Dict(zip(df2.id, df2[!, Symbol("# Escorts")]))
end

combined = DataFrame(
    id       = collect(ids),
    ilp_makespan = [parse(Float64, string(ilp_lookup[id])) for id in ids],
    raviv_ub     = [parse(Float64, string(ub_lookup[id])) for id in ids],
    escorts      = [esc_lookup[id] for id in ids],
)

combined.raviv_gap = (combined.raviv_ub .- combined.ilp_makespan) ./ combined.ilp_makespan .* 100

escort_groups = sort(unique(combined.escorts))
println("Feasible rows: $(nrow(combined))  |  Escort counts: $(escort_groups)")
println()

# ── Summary table ──────────────────────────────────────────────────────────────
function gap_stats(v)
    v = filter(isfinite, v)
    isempty(v) && return (n=0, mean=NaN, min=NaN, q25=NaN, med=NaN, q75=NaN, max=NaN)
    q = quantile(v, [0.25, 0.50, 0.75])
    return (n=length(v), mean=mean(v), min=minimum(v),
            q25=q[1], med=q[2], q75=q[3], max=maximum(v))
end

println("═"^78)
println("  Raviv heuristic (Heuristic UB makespan) gap %")
println("═"^78)
@printf("  %-10s  %5s  %7s  %7s  %7s  %7s  %7s  %7s\n",
        "Escorts", "n", "Mean", "Min", "Q25", "Median", "Q75", "Max")
println("  " * "-"^74)

summary_rows = NamedTuple[]
for esc in escort_groups
    sub = combined[combined.escorts .== esc, :raviv_gap]
    s = gap_stats(sub)
    s.n == 0 && continue
    @printf("  %-10d  %5d  %7.1f  %7.1f  %7.1f  %7.1f  %7.1f  %7.1f\n",
            esc, s.n, s.mean, s.min, s.q25, s.med, s.q75, s.max)
    push!(summary_rows, (metric = "Raviv makespan gap %", escorts = string(esc), n = s.n,
                          mean = s.mean, min = s.min, q25 = s.q25, median = s.med,
                          q75 = s.q75, max = s.max))
end
println()

s = gap_stats(combined.raviv_gap)
@printf("  %-10s  %5d  %7.1f  %7.1f  %7.1f  %7.1f  %7.1f  %7.1f\n",
        "ALL", s.n, s.mean, s.min, s.q25, s.med, s.q75, s.max)
push!(summary_rows, (metric = "Raviv makespan gap %", escorts = "ALL", n = s.n,
                      mean = s.mean, min = s.min, q25 = s.q25, median = s.med,
                      q75 = s.q75, max = s.max))
println()

outdir = raw"C:\codestuff\PBS\paperplots"
mkpath(outdir)

summary_df = DataFrame(summary_rows)
CSV.write(joinpath(outdir, "gap_analysis_ravivUB_summary.csv"), summary_df)
CSV.write(joinpath(outdir, "gap_analysis_ravivUB_rows.csv"), combined)

# ── Plot: box plot of Raviv gap by escort count ────────────────────────────────
esc_labels = string.(escort_groups)
data       = [combined[combined.escorts .== e, :raviv_gap] for e in escort_groups]

p = plot(
    title  = "Raviv heuristic vs ILP makespan gap by escort count",
    ylabel = "Gap (%)",
    xlabel = "Number of escorts",
    legend = false,
    xticks = (1:length(escort_groups), esc_labels),
    size   = (800, 500),
    grid   = true,
    gridalpha = 0.3,
    left_margin   = 8Plots.mm,
    bottom_margin = 8Plots.mm,
    right_margin  = 5Plots.mm,
    top_margin    = 5Plots.mm,
)

for (i, (xpos, d)) in enumerate(zip(1:length(escort_groups), data))
    boxplot!(p, [xpos], d,
        color = :darkorange,
        fillalpha = 0.6,
        whisker_width = 0.3,
        bar_width = 0.5,
        outliers = true,
    )
end

display(p)
savefig(joinpath(outdir, "gap_analysis_ravivUB.png"))
