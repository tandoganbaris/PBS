using Test
include("paperstuff/onestep_heuristic_raviv.jl")
using CSV
using DataFrames

# Runs Raviv's greedy heuristic (Julia port of OneStepHeuristic_v2.py's
# SolveGreedy, see paperstuff/onestep_heuristic_raviv.jl) over every instance
# in the same "leave" benchmark CSV that test.jl uses, and writes the results
# out. This is a standalone comparison run — it doesn't touch our own PBS
# heuristic in main.jl/move.jl at all.

# Parses coordinate strings like "{<1 5> <2 6>...}" WITHOUT the +1 offset
# test.jl uses — onestep_heuristic_raviv.jl mirrors the Python source and
# keeps coordinates 0-indexed (x in 0:Lx-1, y in 0:Ly-1).
function parse_coords_0idx(coord_str)
    stripped = replace(coord_str, r"[\{\}]" => "")
    coords = strip.(split(stripped, ">"))
    result = Loc[]
    for c in coords
        c = replace(c, "<" => "")
        parts = split(strip(c))
        if length(parts) == 2
            x, y = parse.(Int, parts)
            push!(result, (x, y))
        end
    end
    return result
end

@testset "Raviv heuristic on leave-mode CSV rows" begin
    df = CSV.read(raw"C:\codestuff\PBS\FourLoads_escortflow.csv", DataFrame)
    rename!(df, strip.(names(df)))

    if !("id" in names(df))
        df.id = [
            "$(strip(row[Symbol("Lx x Ly")]))_$(strip(string(row[Symbol("# Escorts")])))_" *
            "$(strip(string(row[Symbol("#Loads")])))_$(strip(string(row.seed)))"
            for row in eachrow(df)
        ]
    end

    raviv_makespan  = Union{Int,Missing}[]
    raviv_flowtime  = Union{Int,Missing}[]
    raviv_movements = Union{Int,Missing}[]
    raviv_cpu_time  = Union{Float64,Missing}[]

    n = nrow(df)
    for (idx, row) in enumerate(eachrow(df))
        id_str = row[:id]

        size_str = row[Symbol("Lx x Ly")]
        Lx, Ly = parse.(Int, split(size_str, 'x'))

        O = Set{Loc}(parse_coords_0idx(row[:IOs]))
        E = Set{Loc}(parse_coords_0idx(row[:Escorts]))
        A = Set{Loc}(parse_coords_0idx(row[Symbol("Target Loads")]))
        retrieval_mode = lowercase(strip(string(row[Symbol("Retrieval Mode")])))

        step_cap = max(1, (Lx + Ly) * max(1, length(A)) * 20 ÷ max(1, length(E)))

        makespan, flow_time, movements, cpu = try
            t0 = time()
            ms, ft, mv, _ = solve_greedy(Lx, Ly, O, A, E;
                max_steps = step_cap, acyclic = false, retrieval_mode = retrieval_mode)
            ms, ft, mv, time() - t0
        catch e
            println("\n*** ERROR on instance: $id_str — skipping ***")
            showerror(stdout, e)
            println()
            missing, missing, missing, missing
        end

        push!(raviv_makespan, makespan)
        push!(raviv_flowtime, flow_time)
        push!(raviv_movements, movements)
        push!(raviv_cpu_time, cpu)

        if idx % 50 == 0 || idx == n
            println("Processed $idx / $n instances")
        end
    end

    df[!, :raviv_julia_makespan]  = raviv_makespan
    df[!, :raviv_julia_flowtime]  = raviv_flowtime
    df[!, :raviv_julia_movements] = raviv_movements
    df[!, :raviv_julia_cpu_time]  = raviv_cpu_time

    CSV.write(raw"C:\codestuff\PBS\4loadstestleave_ravivJulia.csv", df)
    println("\nWrote C:\\codestuff\\PBS\\4loadstestleave_ravivJulia.csv")
end
