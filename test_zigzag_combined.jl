using Test
include("main.jl")
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

@testset "zigzag on/off comparison (single-IO + multi-IO) on FourLoads_escortflow.csv" begin
    df = CSV.read(raw"C:\codestuff\PBS\FourLoads_escortflow.csv", DataFrame)
    rename!(df, strip.(names(df)))

    if !("id" in names(df))
        df.id = [
            "$(strip(row[Symbol("Lx x Ly")]))_$(strip(string(row[Symbol("# Escorts")])))_" *
            "$(strip(string(row[Symbol("#Loads")])))_$(strip(string(row.seed)))"
            for row in eachrow(df)
        ]
    end

    function run_all(zigzag_on::Bool)
        ZIGZAG_INTERLEAVE[] = zigzag_on
        makespans = Union{Float64,Missing}[]
        flowtimes = Union{Float64,Missing}[]
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
                    raw"C:\codestuff\PBS\plots"; n=4, no_cores=1, mode=retrieval_mode
                )
                ft = length(makespandict) > 0 ? sum(values(makespandict)) : 0.0
                Float64(ms), ft
            catch e
                println("\n*** ERROR on instance: $(row[:id]) [zigzag=$zigzag_on] — skipping ***")
                showerror(stdout, e)
                println()
                missing, missing
            end

            push!(makespans, makespan)
            push!(flowtimes, flowtime)

            if idx % 250 == 0 || idx == n
                println("[zigzag=$zigzag_on] Processed $idx / $n instances")
            end
        end
        return makespans, flowtimes
    end

    off_ms, off_ft = run_all(false)
    on_ms, on_ft = run_all(true)

    df[!, :zzoff_makespan] = off_ms
    df[!, :zzoff_flowtime] = off_ft
    df[!, :zzon_makespan] = on_ms
    df[!, :zzon_flowtime] = on_ft

    out_csv = raw"C:\codestuff\PBS\4loadstest_zigzag_combined.csv"
    CSV.write(out_csv, df)
    println("\nWrote $out_csv")
end
