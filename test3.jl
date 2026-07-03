include("main.jl")
using CSV
using DataFrames
using Random

const NO_CORES = Threads.nthreads()
println("Using $NO_CORES threads.")

# ─── Instance I/O ───────────────────────────────────────────────────────────

function save_instance_text(initialstate, items, escorts_dict, IO, filepath)
    open(filepath, "w") do f
        rows, cols = size(initialstate)
        col_w = max(5, maximum(length(s) for s in initialstate) + 1)
        # Internal tuple is (row, col) = (y, x); display always as (x, y)
        io_x, io_y = IO[2], IO[1]
        println(f, "=== INSTANCE ===")
        println(f, "Grid: $(cols)x$(rows)  (x=1..$(cols), y=1..$(rows))")
        println(f, "IO: ($io_x, $io_y)")
        println(f, "Items: $(length(items))")
        println(f, "Escorts: $(length(escorts_dict))")
        println(f, "")
        println(f, "=== MATRIX ===  (x=1 left, y=1 bottom)")
        for row in rows:-1:1
            println(f, join(rpad(initialstate[row, col], col_w) for col in 1:cols))
        end
        println(f, "")
        println(f, "=== ITEMS ===")
        println(f, "ID    X    Y    Deadline")
        for (id, itm) in sort(collect(items), by=x->x[1])
            println(f, "$(rpad(id,5)) $(itm.coords[2])    $(itm.coords[1])    $(itm.deadline)")
        end
        println(f, "")
        println(f, "=== ESCORTS ===")
        println(f, "ID    X    Y")
        for (id, esc) in sort(collect(escorts_dict), by=x->x[1])
            println(f, "$(rpad(id,5)) $(esc.coords[2])    $(esc.coords[1])")
        end
    end
end

# ─── Solver with text-based solution output ──────────────────────────────────

function solve_and_save_text(initialstate, items, escorts_dict, IO, solution_path;
                              r=1, no_cores=1)
    n = length(items)  # batch capacity = all items
    allitems     = deepcopy(items)
    itemstopick  = deepcopy(items)
    incumbentstate = deepcopy(initialstate)
    makespandict_temp = Dict{String, Int64}()
    makespandict      = Dict{String, Int64}()
    timestep = 1

    if isa(IO, Tuple)
        for itm in values(allitems)
            itm.assigned_io = IO
        end
    elseif isa(IO, Vector{Any})
        IO = Vector{Tuple{Int,Int}}(IO)
    end

    batch = Dict{String, Any}()
    batch = createbatch!(batch, allitems, itemstopick, incumbentstate, timestep, n, IO)
    stalematecheck = true
    shuffletrigger = false

    states_history = Tuple{Matrix{String}, Bool, Int, Dict, Dict}[]

    while !(isempty(itemstopick) && isempty(batch))
        savemakespan_item!(makespandict_temp, allitems, itemstopick, batch, incumbentstate, IO, timestep)

        if length(batch) <= n - r
            newcandidates = createbatch!(batch, allitems, itemstopick, incumbentstate, timestep, r, IO)
            for (key, value) in newcandidates
                haskey(batch, key) || (batch[key] = value)
            end
            isempty(batch) && break
        end

        shuffletrigger && changeitems!(batch, itemstopick, timestep, IO)

        moved = PBSengine!(timestep, incumbentstate, batch, escorts_dict, IO,
                           obj="flowtime", no_cores=no_cores)
        push!(states_history,
              (deepcopy(incumbentstate), moved, timestep, deepcopy(batch), deepcopy(escorts_dict)))

        timestep += 1
        if stalematecheck
            moved ? (stalematecheck = false) : (shuffletrigger = true)
        end
        timestep > 2000 && break
    end

    timestep > 1900 && @warn "Iteration limit reached — solution may be incomplete."

    makespandict = recalculate_makespan_by_movements(states_history, makespandict_temp)
    flowtime_val = isempty(makespandict) ? 0 : sum(values(makespandict))

    #= solution file writing disabled — results go to CSV only
    rows, cols = size(initialstate)
    col_w = max(5, maximum(length(s) for s in initialstate) + 1)
    open(solution_path, "w") do f
        io_x, io_y = IO[2], IO[1]
        println(f, "=== SOLUTION ===")
        println(f, "IO: ($io_x, $io_y)")
        println(f, "Makespan: $(timestep - 1)")
        println(f, "Flowtime: $flowtime_val")
        println(f, "Per-item makespan:")
        for (id, ms) in sort(collect(makespandict), by=x->x[1])
            println(f, "  $id: $ms")
        end
        println(f, "")
        println(f, "=== STATES ===  (x=1 left, y=1 bottom)")
        for (state, moved, iter, items_state, _) in states_history
            batch_ids = join(sort(collect(keys(items_state))), ", ")
            println(f, "--- Step $iter  moved=$moved  batch=[$batch_ids] ---")
            for row in rows:-1:1
                println(f, join(rpad(state[row, col], col_w) for col in 1:cols))
            end
            println(f, "")
        end
    end
    =#

    return incumbentstate, makespandict, timestep - 1
end

# ─── Experiment runner ───────────────────────────────────────────────────────

function run_experiments()
    base_dir = raw"C:\codestuff\PBS\testinstances_26"
    mkpath(base_dir)

    global saveplot = false   # never call save_plot in main's post-process loop

    # ── Warm-up: run 5 small instances so JIT is done before timed experiments ──
    println("Warming up (5 instances)...")
    for w in 1:5
        rng_w = MersenneTwister(w)
        wd    = Dict("$i" => 1.0 for i in 1:2)
        ws, wi, we = randomintialstate((10, 10), 2, wd, rng_w)
        solve_and_save_text(ws, wi, we, (1, 1), tempname(); r=1, no_cores=NO_CORES)
    end
    println("Warm-up done.\n")

    items_range   = 2:2:10
    escorts_range = 2:2:20
    grid_range    = 10:10:100

    total = length(items_range) * length(escorts_range) * length(grid_range) * 10
    done  = 0

    results_path = joinpath(base_dir, "results_summary.csv")

    # ── Checkpoint: load already-completed instances ──────────────────────────
    completed = Set{Tuple{Int,Int,Int,Int}}()  # (grid_n, n_items, n_escorts, inst_num)
    if isfile(results_path)
        existing = CSV.read(results_path, DataFrame)
        for row in eachrow(existing)
            push!(completed, (row.grid_size, row.n_items, row.n_escorts, row.instance))
        end
        println("Resuming — $(length(completed)) instances already done.\n")
    else
        # Write header row so we can append cleanly later
        header_df = DataFrame(
            grid_size     = Int[],
            n_items       = Int[],
            n_escorts     = Int[],
            instance      = Int[],
            io_position   = String[],
            makespan      = Int[],
            flowtime      = Int[],
            comp_time_sec = Float64[],
        )
        CSV.write(results_path, header_df)
    end

    for n_items in items_range, n_escorts in escorts_range, grid_n in grid_range
        for inst_num in 1:10
            done += 1

            (grid_n, n_items, n_escorts, inst_num) in completed && continue

            # IO position (display x,y — both on bottom row y=1):
            #   left   → display (1, 1)        = internal (row=1, col=1)
            #   center → display (grid_n÷2, 1) = internal (row=1, col=grid_n÷2)
            IO        = inst_num <= 5 ? (1, 1) : (div(grid_n, 2), 1)
            io_label  = inst_num <= 5 ? "left" : "center"

            # Reproducible RNG per instance
            seed     = n_items * 1_000_000 + n_escorts * 10_000 + grid_n * 100 + inst_num
            rng_inst = MersenneTwister(seed)

            # All items available from time 1 (deadline = 1.0)
            item_deadlines = Dict("$i" => 1.0 for i in 1:n_items)

            initialstate, items, escorts_dict =
                randomintialstate((grid_n, grid_n), n_escorts, item_deadlines, rng_inst)

            tag       = "$(grid_n)x$(grid_n)_I$(n_items)_E$(n_escorts)_$(inst_num)"
            inst_path = joinpath(base_dir, "instance_$(tag).txt")
            save_instance_text(initialstate, items, escorts_dict, IO, inst_path)

            t0 = time()
            _, makespandict, makespan = solve_and_save_text(
                initialstate, items, escorts_dict, IO, "";
                r=1, no_cores=NO_CORES
            )
            comp_time = time() - t0

            flowtime = isempty(makespandict) ? 0 : sum(values(makespandict))

            # Append this row immediately so it survives an interrupt
            row_df = DataFrame(
                grid_size     = [grid_n],
                n_items       = [n_items],
                n_escorts     = [n_escorts],
                instance      = [inst_num],
                io_position   = [io_label],
                makespan      = [makespan],
                flowtime      = [flowtime],
                comp_time_sec = [round(comp_time, digits=4)],
            )
            CSV.write(results_path, row_df; append=true)

            println("[$done/$total] $tag  io=$io_label  makespan=$makespan  " *
                    "flowtime=$flowtime  t=$(round(comp_time, digits=2))s")
        end
    end

    println("\nAll done. Results → $results_path")
    return CSV.read(results_path, DataFrame)
end

results = run_experiments()
