include("main.jl")
using CSV
using DataFrames
using Random
using Statistics

const NO_CORES = Threads.nthreads()
println("Using $NO_CORES threads.")

# ─── Instance I/O ───────────────────────────────────────────────────────────

function save_instance_text(initialstate, items, escorts_dict, IO, filepath)
    open(filepath, "w") do f
        rows, cols = size(initialstate)
        col_w = max(5, maximum(length(s) for s in initialstate) + 1)
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

# ─── Solver (same loop as test3.jl's solve_and_save_text) ────────────────────

# Iteration cap: 10 x sum of the target loads' initial distances to the I/O.
iter_cap_for(items, IO) = 10 * sum(io_distance(itm.coords, IO) for itm in values(items); init=0)

function solve_and_save_text(initialstate, items, escorts_dict, IO, solution_path;
                              r=1, no_cores=1)
    n = length(items)  # batch capacity = all items
    cap = iter_cap_for(items, IO)
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

    batch = Dict{String, item}()
    batch = createbatch!(batch, allitems, itemstopick, incumbentstate, timestep, n, IO)
    stalematecheck = true
    shuffletrigger = false

    states_history = Tuple{Matrix{String}, Bool, Int, Dict{String,item}, Dict{String,escort}}[]

    # Stall rollback + reach-escort guard (same scheme as main() in main.jl)
    leave_grace = Dict{String, Int}()
    set_reach_guard!(nothing)
    set_force_freeroam!(false)
    stall_count = 0
    noalign_count = 0
    rollback_point = nothing
    rolled_back_to = Set{Int}()
    picks_at_guard = 0
    n_rollbacks = 0

    while !(isempty(itemstopick) && isempty(batch))
        pre_step = STALL_WINDOW[] > 0 ? stall_snapshot(incumbentstate, batch, escorts_dict, itemstopick, allitems, makespandict_temp,
                                                       leave_grace, timestep, length(states_history), stalematecheck, shuffletrigger) : nothing
        savemakespan_item!(makespandict_temp, allitems, itemstopick, batch, incumbentstate, IO, timestep)
        if reach_guard_io() !== nothing && length(makespandict_temp) > picks_at_guard
            set_reach_guard!(nothing)
        end

        if length(batch) <= n - r
            newcandidates = createbatch!(batch, allitems, itemstopick, incumbentstate, timestep, r, IO)
            for (key, value) in newcandidates
                haskey(batch, key) || (batch[key] = value)
            end
            isempty(batch) && break
        end

        shuffletrigger && changeitems!(batch, itemstopick, timestep, IO)

        loadpos = Dict(k => v.coords for (k, v) in batch)
        moved = PBSengine!(timestep, incumbentstate, batch, escorts_dict, IO,
                           obj="flowtime", no_cores=no_cores)
        if target_load_moved(batch, loadpos)
            rollback_point = pre_step
            stall_count = 0
        else
            stall_count += 1
        end
        noalign_count = (last_n_movers() == 0 && !target_load_moved(batch, loadpos)) ? noalign_count + 1 : 0
        if STALL_WINDOW[] > 0 && noalign_count >= STALL_WINDOW[]
            set_force_freeroam!(true)
        end
        push!(states_history,
              (deepcopy(incumbentstate), moved, timestep, deepcopy(batch), deepcopy(escorts_dict)))

        timestep += 1
        if stalematecheck
            moved ? (stalematecheck = false) : (shuffletrigger = true)
        end
        if STALL_WINDOW[] > 0 && stall_count >= STALL_WINDOW[] && rollback_point !== nothing && !(rollback_point[8] in rolled_back_to)
            push!(rolled_back_to, rollback_point[8])
            timestep, stalematecheck, shuffletrigger = stall_restore!(rollback_point, incumbentstate, batch, escorts_dict, itemstopick,
                                                                       allitems, makespandict_temp, leave_grace, states_history)
            set_reach_guard!(IO)
            if IO isa Tuple && all_loads_urgent(batch, timestep, IO, size(incumbentstate))
                reset_urgency!(batch, timestep, IO)
            end
            picks_at_guard = length(makespandict_temp)
            rollback_point = nothing
            stall_count = 0
            noalign_count = 0
            set_force_freeroam!(false)
            n_rollbacks += 1
            continue
        end
        timestep > cap && break
    end
    set_reach_guard!(nothing)
    set_force_freeroam!(false)

    timestep > 0.9 * cap && @warn "Iteration limit reached — solution may be incomplete."

    makespandict = recalculate_makespan_by_movements(states_history, makespandict_temp)
    flowtime_val = isempty(makespandict) ? 0 : sum(values(makespandict))

    return incumbentstate, makespandict, timestep - 1
end

function solve_one(initialstate, items, escorts_dict, IO)
    try
        cap = iter_cap_for(items, IO)
        _, makespandict, ms = solve_and_save_text(deepcopy(initialstate), deepcopy(items), deepcopy(escorts_dict), IO, "";
                                                    r=1, no_cores=1)
        flowtime = isempty(makespandict) ? 0 : sum(values(makespandict))
        return (ok=true, makespan=ms, flowtime=flowtime, capped=(ms >= cap), err="")
    catch e
        return (ok=false, makespan=missing, flowtime=missing, capped=false, err=sprint(showerror, e))
    end
end

# ─── Experiment runner ───────────────────────────────────────────────────────
#
# Paired IO-left vs IO-center comparison, escorts fixed at 2 (the row of the
# improvement-% table we're refilling). Same 500 (n_items x grid_n x
# inst_num) instances as test3.jl / the earlier test4_sept28.jl, but now each
# instance's item/escort layout is solved TWICE -- once with IO at (1,1),
# once with IO at (grid_n÷2,1) -- so the improvement from moving the IO to
# the center can be measured per instance instead of comparing two
# unrelated random layouts.

function run_experiments()
    base_dir = raw"C:\Users\baris\PBSproject\testinstances_sept28"
    mkpath(base_dir)

    global saveplot = false

    println("Warming up (5 instances)...")
    for w in 1:5
        rng_w = MersenneTwister(w)
        wd    = Dict(("$i" => 1.0) for i in 1:2)
        ws, wi, we = randomintialstate((10, 10), 2, wd, rng_w)
        solve_and_save_text(ws, wi, we, (1, 1), tempname(); r=1, no_cores=1)
    end
    println("Warm-up done.\n")

    items_range = 2:2:10
    n_escorts   = 2
    grid_range  = 10:10:100

    total = length(items_range) * length(grid_range) * 10   # = 500

    results_path = joinpath(base_dir, "results_paired_rollback.csv")

    tasks = Tuple{Int,Int,Int}[]  # (n_items, grid_n, inst_num)
    for n_items in items_range, grid_n in grid_range, inst_num in 1:10
        push!(tasks, (n_items, grid_n, inst_num))
    end
    println("Running $(length(tasks)) / $total paired instances (left + center each) on $(Threads.nthreads()) thread(s).\n")

    io_lock = ReentrantLock()
    done = Threads.Atomic{Int}(0)
    rows = Vector{Any}(undef, length(tasks))

    Threads.@threads for ti in eachindex(tasks)
        n_items, grid_n, inst_num = tasks[ti]

        # Same layout (items/escorts positions) used for BOTH IO placements —
        # only the seed's own terms determine the layout, no inst_num-based
        # IO branching like the original test3.jl.
        seed     = n_items * 1_000_000 + n_escorts * 10_000 + grid_n * 100 + inst_num
        rng_inst = MersenneTwister(seed)
        item_deadlines = Dict(("$i" => 1.0) for i in 1:n_items)
        initialstate, items, escorts_dict =
            randomintialstate((grid_n, grid_n), n_escorts, item_deadlines, rng_inst)

        tag = "$(grid_n)x$(grid_n)_I$(n_items)_E$(n_escorts)_$(inst_num)"
        save_instance_text(initialstate, items, escorts_dict, (1, 1),
                            joinpath(base_dir, "instance_$(tag).txt"))

        IO_left   = (1, 1)
        IO_center = (div(grid_n, 2), 1)

        t0 = time()
        r_left   = solve_one(initialstate, items, escorts_dict, IO_left)
        r_center = solve_one(initialstate, items, escorts_dict, IO_center)
        comp_time = time() - t0

        rows[ti] = (grid_size=grid_n, n_items=n_items, n_escorts=n_escorts, instance=inst_num,
                    left_ok=r_left.ok, left_makespan=r_left.makespan, left_flowtime=r_left.flowtime,
                    left_capped=r_left.capped, left_err=r_left.err,
                    center_ok=r_center.ok, center_makespan=r_center.makespan, center_flowtime=r_center.flowtime,
                    center_capped=r_center.capped, center_err=r_center.err,
                    comp_time_sec=round(comp_time, digits=4))

        n_done = Threads.atomic_add!(done, 1) + 1
        lock(io_lock) do
            lstat = r_left.ok   ? "L(ms=$(r_left.makespan)$(r_left.capped ? " CAP" : ""))"   : "L(FAIL)"
            cstat = r_center.ok ? "C(ms=$(r_center.makespan)$(r_center.capped ? " CAP" : ""))" : "C(FAIL)"
            println("[$n_done/$total] $tag  $lstat  $cstat  t=$(round(comp_time, digits=2))s")
        end
    end

    df = DataFrame(rows)
    CSV.write(results_path, df)
    println("\nAll done. Paired results → $results_path")
    return df
end

df = run_experiments()

# ─── Improvement stats (center vs. left), matching the paper table's columns ─

function pct_stats(v)
    v = collect(skipmissing(v))
    isempty(v) && return (n=0, avg=NaN, worst=NaN, best=NaN, q25=NaN, med=NaN, q75=NaN)
    return (n=length(v), avg=mean(v), worst=minimum(v), best=maximum(v),
            q25=quantile(v, 0.25), med=median(v), q75=quantile(v, 0.75))
end

both_ok = df.left_ok .& df.center_ok
sub = df[both_ok, :]
n_fail = count(!, both_ok)

makespan_improve = (sub.left_makespan .- sub.center_makespan) ./ sub.left_makespan .* 100
flowtime_improve = (sub.left_flowtime .- sub.center_flowtime) ./ sub.left_flowtime .* 100

ms_stats = pct_stats(makespan_improve)
ft_stats = pct_stats(flowtime_improve)

println("\n=== Escorts = 2 — center vs. left IO, improvement (%) ===")
println("(positive = center IO better than left IO for that instance)")
println("N (both sides completed) = $(ms_stats.n) / $(nrow(df))")
println("Failed pairs (crash on at least one side): $n_fail")
println()
println("Makespan improvement:  avg=$(round(ms_stats.avg,digits=1))  worst=$(round(ms_stats.worst,digits=1))  best=$(round(ms_stats.best,digits=1))  Q25=$(round(ms_stats.q25,digits=1))  median=$(round(ms_stats.med,digits=1))  Q75=$(round(ms_stats.q75,digits=1))")
println("Flowtime improvement:  avg=$(round(ft_stats.avg,digits=1))  worst=$(round(ft_stats.worst,digits=1))  best=$(round(ft_stats.best,digits=1))  Q25=$(round(ft_stats.q25,digits=1))  median=$(round(ft_stats.med,digits=1))  Q75=$(round(ft_stats.q75,digits=1))")

if n_fail > 0
    println("\nFailure detail:")
    for row in eachrow(df[.!both_ok, :])
        side = !row.left_ok ? "left" : "center"
        msg  = !row.left_ok ? row.left_err : row.center_err
        println("  $(row.grid_size)x$(row.grid_size)_I$(row.n_items)_E$(row.n_escorts)_$(row.instance)  side=$side  $(first(split(msg, '\n')))")
    end
end
