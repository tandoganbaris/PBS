using CSV, DataFrames, Plots

df = CSV.read(raw"C:\codestuff\PBS\4loadstestleave.csv", DataFrame)
df2 = CSV.read(raw"C:\codestuff\PBS\4loadstestleaveP2.csv", DataFrame)

# ── Filter: only rows where ILP found a feasible solution ─────────────────────
function pos_num(v)
    ismissing(v) && return false
    isa(v, Number) && return v > 0
    n = tryparse(Float64, string(v))
    return n !== nothing && n > 0
end
df = filter(row -> pos_num(row[Symbol("ILP makespan")]) && pos_num(row[Symbol("ILP flowtime")]), df)

df.ilp_makespan = parse.(Float64, string.(df[!, Symbol("ILP makespan")]))
df.ilp_flowtime = parse.(Float64, string.(df[!, Symbol("ILP flowtime")]))
df.raviv_makespan = parse.(Float64, string.(df[!, Symbol("Heuristic UB makespan")]))

println("Feasible rows: $(nrow(df))")
println()

outdir = raw"C:\codestuff\PBS\paperplots"
mkpath(outdir)

"""
Sorts by the ILP (ground-truth) objective ascending, breaking ties by the
heuristic objective ascending, then plots both absolute objective values
against the resulting instance ordering so the gap is visible bar-by-bar.
"""
function plot_absolute_gap(df, ilp_col::Symbol, heuristic_col::Symbol, label::String, filename::String;
                            extra_col::Union{Symbol,Nothing}=nothing, extra_label::String="",
                            randomized_df=nothing, randomized_col::Union{Symbol,Nothing}=nothing,
                            randomized_label::String="Heuristic Flow-Time Randomized",
                            csv_filename::Union{String,Nothing}=nothing)
    sorted = sort(df, [ilp_col, heuristic_col])
    n = nrow(sorted)
    xs = 1:n

    # Look up the randomized-heuristic series by id, aligned to df's sort order —
    # missing ids (not present in the randomized run) become NaN, which Plots skips.
    randomized_vals = nothing
    if randomized_df !== nothing
        lookup = Dict(zip(randomized_df.id, randomized_df[!, randomized_col]))
        randomized_vals = [get(lookup, id, NaN) for id in sorted.id]
    end

    if csv_filename !== nothing
        out_cols = [:id, ilp_col, heuristic_col]
        extra_col !== nothing && push!(out_cols, extra_col)
        csv_df = DataFrame(instance = collect(xs))
        for c in out_cols
            csv_df[!, c] = sorted[!, c]
        end
        randomized_vals !== nothing && (csv_df[!, :randomized_heuristic] = randomized_vals)
        CSV.write(joinpath(outdir, csv_filename), csv_df)
    end

    p = plot(
        title  = "$label: heuristic vs ILP (sorted by ILP $label)",
        xlabel = "Instance (sorted by increasing ILP $label)",
        ylabel = "$label (absolute value)",
        legend = :topleft,
        legendfontsize = 12,
        size   = (1000, 500),
        grid   = true,
        gridalpha = 0.3,
        left_margin   = 12Plots.mm,
        bottom_margin = 10Plots.mm,
        right_margin  = 5Plots.mm,
        top_margin    = 5Plots.mm,
    )

    plot!(p, xs, sorted[!, ilp_col], label = "ILP $label", color = :steelblue, linewidth = 2)
    plot!(p, xs, sorted[!, heuristic_col], label = "Heuristic $label", color = :red3, linewidth = 1.5, alpha = 0.85)
    if extra_col !== nothing
        plot!(p, xs, sorted[!, extra_col], label = extra_label, color = :seagreen, linewidth = 1.5, alpha = 0.85)
    end
    if randomized_vals !== nothing
        plot!(p, xs, randomized_vals, label = randomized_label, color = :orange2, linewidth = 1.5, alpha = 0.85)
    end

    display(p)
    savefig(p, joinpath(outdir, filename))
    return p
end

plot_absolute_gap(df, :ilp_makespan, :makespan_heuristic, "Makespan", "gap_analysis_absolute_makespan.png";
                   extra_col = :raviv_makespan, extra_label = "Raviv_heuristic",
                   randomized_df = df2, randomized_col = :makespan_heuristic,
                   csv_filename = "gap_analysis_absolute_makespan.csv")
plot_absolute_gap(df, :ilp_flowtime, :flowtime_heuristic, "Flow-time", "gap_analysis_absolute_flowtime.png";
                   randomized_df = df2, randomized_col = :flowtime_heuristic,
                   csv_filename = "gap_analysis_absolute_flowtime.csv")
