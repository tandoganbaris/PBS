using Test
include("paperstuff/onestep_heuristic_raviv.jl")
using CSV
using DataFrames
using Statistics
using Printf

# Runs Raviv's greedy heuristic (Julia port, see paperstuff/onestep_heuristic_raviv.jl)
# over every one of the 5000 instances in testinstances_26/, whose per-instance
# results (from OUR heuristic) are summarized in results_summary.csv. Each CSV
# row maps 1:1 to an instance_<grid>x<grid>_I<n_items>_E<n_escorts>_<instance>.txt
# file in the same directory (verified: 5000 rows, 5000 files).
#
# results_summary.csv has no retrieval-mode column — it predates the
# continue/leave mode split added to main.jl later, so it can only have been
# generated in what is now called "continue" mode. We run Raviv's heuristic
# the same way for a fair comparison.

const INSTANCE_DIR = raw"C:\codestuff\PBS\testinstances_26"
const RESULTS_CSV   = joinpath(INSTANCE_DIR, "results_summary.csv")
const RETRIEVAL_MODE = "continue"

"""
Parses one `instance_<grid>x<grid>_I<n_items>_E<n_escorts>_<instance>.txt` file
(format: header with Grid/IO, then === ITEMS === and === ESCORTS === sections
with 1-indexed X/Y columns). Returns (Lx, Ly, O, A, E) with coordinates
converted to the 0-indexed convention onestep_heuristic_raviv.jl expects.
"""
function parse_instance_file(path)
    lines = readlines(path)

    Lx = Ly = 0
    io_x = io_y = 0
    for line in lines
        m = match(r"Grid:\s*(\d+)x(\d+)", line)
        if m !== nothing
            Lx, Ly = parse(Int, m.captures[1]), parse(Int, m.captures[2])
        end
        m2 = match(r"IO:\s*\((\d+),\s*(\d+)\)", line)
        if m2 !== nothing
            io_x, io_y = parse(Int, m2.captures[1]), parse(Int, m2.captures[2])
        end
    end
    O = Set{Loc}([(io_x - 1, io_y - 1)])

    items_start = findfirst(l -> occursin("=== ITEMS ===", l), lines)
    escorts_start = findfirst(l -> occursin("=== ESCORTS ===", l), lines)

    A = Set{Loc}()
    for line in lines[items_start+2:escorts_start-1]
        stripped = strip(line)
        isempty(stripped) && continue
        parts = split(stripped)
        x, y = parse(Int, parts[2]), parse(Int, parts[3])
        push!(A, (x - 1, y - 1))
    end

    E = Set{Loc}()
    for line in lines[escorts_start+2:end]
        stripped = strip(line)
        isempty(stripped) && continue
        parts = split(stripped)
        x, y = parse(Int, parts[2]), parse(Int, parts[3])
        push!(E, (x - 1, y - 1))
    end

    return Lx, Ly, O, A, E
end

instance_filename(grid_size, n_items, n_escorts, instance) =
    "instance_$(grid_size)x$(grid_size)_I$(n_items)_E$(n_escorts)_$(instance).txt"

@testset "Raviv heuristic on results_summary.csv instances" begin
    df = CSV.read(RESULTS_CSV, DataFrame)
    out_csv = joinpath(INSTANCE_DIR, "summary_raviv.csv")

    # ── Checkpoint: reuse Raviv results already computed in a prior run ─────────
    instance_key(row) = (row.grid_size, row.n_items, row.n_escorts, row.instance)
    previous = Dict{Tuple,Any}()
    if isfile(out_csv)
        prior_df = CSV.read(out_csv, DataFrame)
        for row in eachrow(prior_df)
            !ismissing(row.raviv_makespan) || continue
            previous[instance_key(row)] = (row.raviv_makespan, row.raviv_flowtime,
                                            row.raviv_movements, row.raviv_cpu_time)
        end
        println("Found $(length(previous)) already-solved instances in $out_csv — skipping those.")
    end

    raviv_makespan  = Union{Int,Missing}[]
    raviv_flowtime  = Union{Int,Missing}[]
    raviv_movements = Union{Int,Missing}[]
    raviv_cpu_time  = Union{Float64,Missing}[]

    n = nrow(df)
    n_reused = 0
    for (idx, row) in enumerate(eachrow(df))
        cached = get(previous, instance_key(row), nothing)
        makespan, flow_time, movements, cpu = if cached !== nothing
            n_reused += 1
            cached
        else
            path = joinpath(INSTANCE_DIR,
                instance_filename(row.grid_size, row.n_items, row.n_escorts, row.instance))
            try
                Lx, Ly, O, A, E = parse_instance_file(path)
                step_cap = max(1, (Lx + Ly) * max(1, length(A)) * 20 ÷ max(1, length(E)))
                t0 = time()
                ms, ft, mv, _ = solve_greedy(Lx, Ly, O, A, E;
                    max_steps = step_cap, acyclic = false, retrieval_mode = RETRIEVAL_MODE)
                ms, ft, mv, time() - t0
            catch e
                println("\n*** ERROR on $path — skipping ***")
                showerror(stdout, e)
                println()
                missing, missing, missing, missing
            end
        end

        push!(raviv_makespan, makespan)
        push!(raviv_flowtime, flow_time)
        push!(raviv_movements, movements)
        push!(raviv_cpu_time, cpu)

        if idx % 250 == 0 || idx == n
            println("Processed $idx / $n instances ($n_reused reused)")
        end
    end

    df[!, :raviv_makespan]  = raviv_makespan
    df[!, :raviv_flowtime]  = raviv_flowtime
    df[!, :raviv_movements] = raviv_movements
    df[!, :raviv_cpu_time]  = raviv_cpu_time

    CSV.write(out_csv, df)
    println("\nWrote $out_csv")

    # ── Compare existing (our) heuristic results against Raviv's ────────────────
    valid = filter(r -> !ismissing(r.raviv_makespan), df)
    println("\nValid comparisons: $(nrow(valid)) / $n")

    valid.ms_diff = valid.raviv_makespan .- valid.makespan   # >0 means Raviv worse (higher makespan)
    valid.ft_diff = valid.raviv_flowtime .- valid.flowtime
    valid.mine_wins_ms = valid.makespan .< valid.raviv_makespan
    valid.ties_ms       = valid.makespan .== valid.raviv_makespan
    valid.mine_wins_ft = valid.flowtime .< valid.raviv_flowtime
    valid.ties_ft       = valid.flowtime .== valid.raviv_flowtime

    println("\n" * "═"^90)
    println("  Mine vs Raviv — by grid size and IO position")
    println("═"^90)
    summary_rows = NamedTuple[]
    for io in sort(unique(valid.io_position))
        for gs in sort(unique(valid.grid_size))
            sub = valid[(valid.io_position .== io) .& (valid.grid_size .== gs), :]
            isempty(sub) && continue
            mean_mine_ms  = mean(sub.makespan)
            mean_raviv_ms = mean(sub.raviv_makespan)
            mean_mine_ft  = mean(sub.flowtime)
            mean_raviv_ft = mean(sub.raviv_flowtime)
            win_ms = 100 * count(sub.mine_wins_ms) / nrow(sub)
            win_ft = 100 * count(sub.mine_wins_ft) / nrow(sub)
            @printf("  io=%-7s grid=%-4d n=%-4d  makespan mine=%7.1f raviv=%7.1f (mine wins %5.1f%%)  flowtime mine=%7.1f raviv=%7.1f (mine wins %5.1f%%)\n",
                    io, gs, nrow(sub), mean_mine_ms, mean_raviv_ms, win_ms, mean_mine_ft, mean_raviv_ft, win_ft)
            push!(summary_rows, (io_position = io, grid_size = gs, n = nrow(sub),
                                  mine_mean_makespan = mean_mine_ms, raviv_mean_makespan = mean_raviv_ms,
                                  mine_wins_makespan_pct = win_ms,
                                  mine_mean_flowtime = mean_mine_ft, raviv_mean_flowtime = mean_raviv_ft,
                                  mine_wins_flowtime_pct = win_ft))
        end
    end
    println()

    overall_win_ms = 100 * count(valid.mine_wins_ms) / nrow(valid)
    overall_win_ft = 100 * count(valid.mine_wins_ft) / nrow(valid)
    println("Overall: mine makespan mean=$(mean(valid.makespan))  raviv makespan mean=$(mean(valid.raviv_makespan))  mine wins $(round(overall_win_ms, digits=1))%")
    println("Overall: mine flowtime mean=$(mean(valid.flowtime))  raviv flowtime mean=$(mean(valid.raviv_flowtime))  mine wins $(round(overall_win_ft, digits=1))%")

    comparison_df = DataFrame(summary_rows)
    comp_csv = joinpath(INSTANCE_DIR, "summary_raviv_comparison.csv")
    CSV.write(comp_csv, comparison_df)
    println("\nWrote $comp_csv")
end
