using Test
include("main.jl")   # original, unmodified move.jl
using CSV
using DataFrames

global saveplot = false

function parse_coords(coord_str)
    stripped = replace(coord_str, r"[\{\}]" => "")
    coords = strip.(split(stripped, ">"))
    result = Tuple{Int,Int}[]
    for c in coords
        c = replace(c, "<" => "")
        parts = split(strip(c))
        if length(parts) == 2
            x, y = parse.(Int, parts)
            push!(result, (x+1, y+1))
        end
    end
    return result
end

@testset "batch-size (n=2) control on FourLoads_escortflow.csv" begin
    df = CSV.read(raw"C:\codestuff\PBS\FourLoads_escortflow.csv", DataFrame)
    rename!(df, strip.(names(df)))

    if !("id" in names(df))
        df.id = [
            "$(strip(row[Symbol("Lx x Ly")]))_$(strip(string(row[Symbol("# Escorts")])))_" *
            "$(strip(string(row[Symbol("#Loads")])))_$(strip(string(row.seed)))"
            for row in eachrow(df)
        ]
    end

    n2_makespan = Union{Float64,Missing}[]
    n2_flowtime = Union{Float64,Missing}[]

    n = nrow(df)
    for (idx, row) in enumerate(eachrow(df))
        size_str = row[Symbol("Lx x Ly")]
        Lx, Ly = parse.(Int, split(size_str, 'x'))

        IO_coords = parse_coords(row[:IOs])
        if length(IO_coords) == 1
            IO_coords = IO_coords[1]
        end
        escort_coords = parse_coords(row[:Escorts])
        item_coords = parse_coords(row[Symbol("Target Loads")])
        retrieval_mode = lowercase(strip(string(row[Symbol("Retrieval Mode")])))

        escorts = Dict{String, escort}()
        for (k, coord) in enumerate(escort_coords)
            escorts["E$k"] = escort("E$k", coord, String[], String[], 0, Dict{Int64,Vector{String}}(), Tuple{Int64,Int64}[])
        end
        items = Dict{String, item}()
        for (k, coord) in enumerate(item_coords)
            items["I$k"] = item("I$k", coord, 0, 0, 1000.0, 1, nothing)
        end

        initialstate = fill("0", Lx, Ly)
        for (key, esc) in escorts
            x, y = esc.coords
            initialstate[x, y] = key
        end
        for (key, itm) in items
            x, y = itm.coords
            initialstate[x, y] = key
        end

        makespan, flowtime = try
            _, makespandict, ms = main(
                initialstate, items, escorts, IO_coords, 1,
                raw"C:\codestuff\PBS\plots"; n=2, no_cores=1, mode=retrieval_mode
            )
            ft = length(makespandict) > 0 ? sum(values(makespandict)) : 0.0
            Float64(ms), ft
        catch e
            println("\n*** ERROR on instance: $(row[:id]) — skipping ***")
            showerror(stdout, e)
            println()
            missing, missing
        end

        push!(n2_makespan, makespan)
        push!(n2_flowtime, flowtime)

        if idx % 250 == 0 || idx == n
            println("Processed $idx / $n instances")
        end
    end

    df[!, :n2_makespan] = n2_makespan
    df[!, :n2_flowtime] = n2_flowtime

    out_csv = raw"C:\codestuff\PBS\4loadstestleave_batchsize2.csv"
    CSV.write(out_csv, df)
    println("\nWrote $out_csv")
end
