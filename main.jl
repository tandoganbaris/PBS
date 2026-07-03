using Distributed
using Random
using Statistics
include("structs.jl")
include("pbsviz.jl")
include("move.jl")

function setup_workers!(n::Int)
    # no-op: parallelism now uses Threads.@threads, no worker processes needed
end

rng = MersenneTwister(1234)

function randomintialstate(matrixsize, noescorts, items, rng)
    state = Matrix{String}(undef, matrixsize[1], matrixsize[2])

    # Pre-fill with empty strings
    for i in 1:matrixsize[1], j in 1:matrixsize[2]
        state[i, j] = ""
    end
    escorts = Dict{String, Any}()
    itemswithcoords = Dict{String, Any}()

    # Prepare item and escort labels
    item_count = matrixsize[1] * matrixsize[2] - noescorts
    item_names = [string(i) for i in 1:item_count]
    escort_names = ["E" * string(i) for i in 1:noescorts]
    all_names = vcat(item_names, escort_names)
    
    # Shuffle the labels
    shuffle!(rng, all_names)
    
    # Fill the matrix
    idx = 1
    for i in 1:matrixsize[1], j in 1:matrixsize[2]
        currid = all_names[idx] 
        state[i, j] = currid
        if currid  in escort_names
            escort = createescort(currid, (i,j), 0)
            escorts[currid] = escort
        elseif  currid in keys(items)
            item= createitem(currid, (i,j), items[currid])
            itemswithcoords[currid] =item 
        end
        idx += 1
    end
    return state, itemswithcoords, escorts
end

function atIO( item, IO)
    return item.coords == IO
end
""" 
removes items from batch when they are at IO
"""
function savemakespan_item!(makespandict,allitems, itemstopick, batch, incumbentstate, IO, time) # will need to mod for multiIO
   
    if isa(IO, Tuple)
        iox, ioy = IO
        if incumbentstate[iox, ioy] in keys(itemstopick) 
            itemid = incumbentstate[iox, ioy]
            #item = itemstopick[itemid]
            makespandict[itemid] = 1
            delete!(itemstopick, itemid)
            if haskey(batch, itemid)
                delete!(batch, itemid)
            end
        elseif incumbentstate[iox, ioy] in keys(batch)
            itemid = incumbentstate[iox, ioy]
            makespandict[itemid] = time - 0 # allitems[itemid].tes  use .tes for big batches, 0 for exact comparison
            delete!(batch, itemid)
        end
    elseif  isa(IO, Vector{Tuple{Int,Int}})
        for io in IO
            iox, ioy = io
            if incumbentstate[iox, ioy] in keys(itemstopick) 
                itemid = incumbentstate[iox, ioy]
                #item = itemstopick[itemid]
                makespandict[itemid] = 1
                delete!(itemstopick, itemid)
                if haskey(batch, itemid)
                    delete!(batch, itemid)
                end
            elseif incumbentstate[iox, ioy] in keys(batch)
                itemid = incumbentstate[iox, ioy]
                makespandict[itemid] = time - allitems[itemid].tes
                delete!(batch, itemid)
            end
        end
    else
        throw(ArgumentError("IO in wrong format: should be a Tuple{x=int,y=int} or an Array{Tuple}"))
    end   
end
"""
pushes either the most urgent of the closest items to batch
"""
function manyincloseproxy(allcoords, IO)
    prox_items = 0
    if isa(IO, Tuple)
        iox, ioy = IO
        for coord in allcoords
            distance = abs(coord[1] - iox) + abs(coord[2] - ioy)
            if distance <= length(allcoords)
                prox_items += 1
                if prox_items >1
                    return true
                end
            end
        end
    else
        for (iox, ioy) in IO   
            for coord in allcoords
                distance = abs(coord[1] - iox) + abs(coord[2] - ioy)
                if distance <= length(allcoords)
                prox_items += 1
                    if prox_items >1
                        return true
                    end
                end
            end 
        end
    end
    
   
    return false
end
function createbatch!(batch, allitems, itemstopick, incumbentstate, time, r, IO)
    newbatch = Dict{String, Any}()

    for idx in CartesianIndices(incumbentstate) # can we remove this???
        if incumbentstate[idx] in keys(itemstopick)
            item = itemstopick[incumbentstate[idx]]
            item.coords = Tuple(idx)
        end
    end

    if isa(IO, Tuple)
        iox, ioy = IO
        distances = Dict(itemid => abs(itemstopick[itemid].coords[1] - iox) + abs(itemstopick[itemid].coords[2] - ioy) for itemid in keys(itemstopick))
    elseif isa(IO, Vector{Tuple{Int,Int}})
        distances = Dict(itemid => abs(itemstopick[itemid].coords[2] - 1) for itemid in keys(itemstopick))
    else
        throw(ArgumentError("IO in wrong format: should be a Tuple{x=int,y=int} or an Array{Tuple}"))
    end
    sorted_distances = sort(collect(distances), by = x -> x[2]) 
    ebatch_coords = [item.coords for item in values(batch)]
    allcoords = vcat([item.coords for item in values(newbatch)], ebatch_coords)
    for itemid in keys(itemstopick)
        item= itemstopick[itemid]
        coords = item.coords
        l_allcoords= deepcopy(allcoords)
        push!(l_allcoords, coords)
        if item.deadline <= time && length(keys(newbatch)) < r &&
            ((manyincloseproxy(l_allcoords,IO)==false) || path_to_io_exists_if(incumbentstate, l_allcoords, IO))
            allitems[itemid].tes = time
            newbatch[itemid] = item
            push!(allcoords, coords)
            if haskey(itemstopick, itemid)
                delete!(itemstopick, itemid)
            end
            deleteat!(sorted_distances, 1)
        end
    end
    while length(newbatch) < r && !isempty(sorted_distances)
        itemid = sorted_distances[1][1]
        if !haskey(itemstopick, itemid)
            deleteat!(sorted_distances, 1)
            continue
        end
        item = itemstopick[itemid]
        coords = item.coords
        l_allcoords= deepcopy(allcoords)
        push!(l_allcoords, coords)
        if (manyincloseproxy(l_allcoords,IO)==false) || path_to_io_exists_if(incumbentstate, l_allcoords, IO)
            allitems[itemid].tes = time
            newbatch[itemid] = item
            push!(allcoords, coords)
            if haskey(itemstopick, itemid)
                delete!(itemstopick, itemid)
            end
        end
        deleteat!(sorted_distances, 1)
    end
    return newbatch
end
function changeitems!(batch, itemstopick,time,IO)
    noitems = length(keys(batch))
    closetoIO = []
    if isa(IO, Tuple)
        iox, ioy = IO
        for (itemid, item) in batch
            distance = abs(item.coords[1] - iox) + abs(item.coords[2] - ioy)
            if distance <= 1
                push!(closetoIO, itemid)
            end
        end
    elseif isa(IO, Array{Tuple})
        for io in IO
            iox, ioy = io
            for (itemid, item) in batch
                distance = abs(item.coords[1] - iox) + abs(item.coords[2] - ioy)
                if distance <= 1
                    push!(closetoIO, itemid)
                end
            end
        end
    else
        throw(ArgumentError("IO in wrong format: should be a Tuple{x=int,y=int} or an Array{Tuple}"))
    end
    for itemid in closetoIO
        if haskey(batch, itemid)
            item = batch[itemid]
            item.tes = 0 
            delete!(batch, itemid)
            itemstopick[itemid] = item
        end
    end
    # Randomly select items from itemstopick to add to the batch
    num_to_add = length(closetoIO)
    item_ids = collect(keys(itemstopick))
    shuffle!(rng, item_ids)
    for i in 1:min(num_to_add, length(item_ids))
        itemid = item_ids[i]
        item = itemstopick[itemid]
        itemstopick[itemid].tes = time
        batch[itemid] = item
        delete!(itemstopick, itemid)
    end
end

"""
    recalculate_makespan_by_movements(states_history, makespandict_temp)

Recalculates makespan based only on iterations where movement occurred.
For each item picked at iteration T, counts how many true movements occurred up to T.
"""
function recalculate_makespan_by_movements(states_history, makespandict_temp)
    # Build a mapping of iteration -> movement state
    movement_history = Dict{Int, Bool}()
    for (state, moved, iter, items_state, escorts_state) in states_history
        movement_history[iter] = moved
    end
    
    # For each item in makespandict_temp, recalculate based on actual movements
    recalculated_makespan = Dict{String, Int64}()
    
    for (itemid, pickup_iter) in makespandict_temp
        # Count actual time steps (movements) up to pickup_iter
        actual_time = 0
        for iter in sort(collect(keys(movement_history)))
            if iter > pickup_iter
                break
            end
            if movement_history[iter]
                actual_time += 1
            end
        end
        recalculated_makespan[itemid] = actual_time
    end
    
    return recalculated_makespan
end


function main(initialstate, items, escorts, IO, testid, save_directory; n=4, r=1, no_cores=1)
    setup_workers!(no_cores)   # spawns workers + loads code on them if not done yet
    allitems = deepcopy(items)
    itemstopick = deepcopy(items)
    local incumbentstate = deepcopy(initialstate)
    makespandict_temp = Dict{String, Int64}()  # Temporary, for tracking item pickup iterations
    makespandict = Dict{String, Int64}()  # Final, will be computed based on actual movements
    time = 1
    if isa(IO, Tuple)
        for item in values(allitems)
            item.assigned_io = IO
        end
    elseif isa(IO, Vector{Any})
        IO = Vector{Tuple{Int,Int}}(IO)
    end
    batch = Dict{String, Any}()
    local batch = createbatch!(batch, allitems,itemstopick, incumbentstate, time, n, IO)
    stalematecheck = true 
    shuffletrigger= false
  
    # Array to store states with movement info: (state, moved, iteration, items_state, escorts_state)
    states_history = Tuple{Matrix{String}, Bool, Int, Dict, Dict}[]
    
    while !(isempty(itemstopick)&&isempty(batch))
        savemakespan_item!(makespandict_temp, allitems, itemstopick, batch, incumbentstate, IO, time) # deletes items from batch 
        if length(batch) <= n-r #decide on batch 
            newcandidates = createbatch!(batch,allitems,itemstopick, incumbentstate, time, r, IO) 
            if !isempty(keys(newcandidates))
                for (key, value) in newcandidates
                    if !haskey(batch, key)
                        batch[key] = value
                    end
                end
            end
            if isempty(batch)
                break
            end
        end 
        if shuffletrigger
            changeitems!(batch,itemstopick, time,  IO)
        end
        
        #assign escorts for items unique
        moved = PBSengine!(time, incumbentstate, batch, escorts, IO, obj="flowtime", no_cores=no_cores)
        #moved = PBSengine!(time, incumbentstate, batch, escorts, IO, obj="makespan")
        
        # Store state with movement info and current items/escorts state
        push!(states_history, (deepcopy(incumbentstate), moved, time, deepcopy(batch), deepcopy(escorts)))
        
        time +=1
        if stalematecheck
            if !moved
                shuffletrigger = true
            else
                stalematecheck = false
            end
        end
        if time >1000 
            break
        end
    end
    
    # Post-process: save all plots
    for (state, moved, iter, items_state, escorts_state) in states_history
        save_plot(saveplot, state, items_state, escorts_state, IO, "$(testid)_$(iter)_test", save_directory)
    end
    if time >900
        println("Warning: reached iteration limit without completing all items. Check for potential issues.")
    end
    # Post-process: calculate makespan based only on actual movements
    makespandict = recalculate_makespan_by_movements(states_history, makespandict_temp)
    
    return incumbentstate, makespandict, time-1
end
function main_savenow(initialstate, items, escorts, IO, testid, save_directory; n=4, r=1, no_cores=1)
    setup_workers!(no_cores)
    allitems = deepcopy(items)
    itemstopick = deepcopy(items)
    local incumbentstate = deepcopy(initialstate)
    makespandict_temp = Dict{String, Int64}()
    makespandict = Dict{String, Int64}()
    time = 1
    if isa(IO, Tuple)
        for item in values(allitems)
            item.assigned_io = IO
        end
    elseif isa(IO, Vector{Any})
        IO = Vector{Tuple{Int,Int}}(IO)
    end
    batch = Dict{String, Any}()
    local batch = createbatch!(batch, allitems, itemstopick, incumbentstate, time, n, IO)
    stalematecheck = true
    shuffletrigger = false

    states_history = Tuple{Matrix{String}, Bool, Int, Dict, Dict}[]

    while !(isempty(itemstopick) && isempty(batch))
        savemakespan_item!(makespandict_temp, allitems, itemstopick, batch, incumbentstate, IO, time)
        if length(batch) <= n - r
            newcandidates = createbatch!(batch, allitems, itemstopick, incumbentstate, time, r, IO)
            if !isempty(keys(newcandidates))
                for (key, value) in newcandidates
                    if !haskey(batch, key)
                        batch[key] = value
                    end
                end
            end
            if isempty(batch)
                break
            end
        end
        if shuffletrigger
            changeitems!(batch, itemstopick, time, IO)
        end

        moved = PBSengine!(time, incumbentstate, batch, escorts, IO, obj="flowtime", no_cores=no_cores)

        push!(states_history, (deepcopy(incumbentstate), moved, time, deepcopy(batch), deepcopy(escorts)))

        # Save immediately after each iteration
        save_plot(saveplot, incumbentstate, batch, escorts, IO, "$(testid)_$(time)_test", save_directory)

        time += 1
        if stalematecheck
            if !moved
                shuffletrigger = true
            else
                stalematecheck = false
            end
        end
        if time > 1000
            break
        end
    end

    makespandict = recalculate_makespan_by_movements(states_history, makespandict_temp)

    return incumbentstate, makespandict, time - 1
end
function checksync_main(matrix, escorts, items)
    for eid in keys(escorts)
        ex, ey = escorts[eid].coords
        if matrix[ex, ey] != eid
            println("CSM Escort $eid is not in the right place")
        end
    end
    for iid in keys(items)
        ix, iy = items[iid].coords
        if matrix[ix, iy] != iid
            println("CSM Item $iid is not in the right place")
        end
    end
end
function checkmatchange_main(matrix1, matrix2)
    for idx in CartesianIndices(matrix1)
        if matrix1[idx] != matrix2[idx]
            return true # change happened
        end
    end
    return false
end

#=
global makespan_sum = 0
global average_time_sum = 0
num_iterations = 100
timerstart = time()
for i in 1:num_iterations
    if i ==263
        global saveplot = true
    else
        global saveplot = true
    end
    item_deadlines = Dict("$i" => Float64(1000 - i * 10) for i in 1:20) 
    #item_deadlines = Dict("$i" => Float64(20 + (i - 1) * 10) for i in 1:10)
    IO= (1,1)
    initialstate, items, escorts = randomintialstate((10, 10), 4, item_deadlines, rng)
    save_directory = raw"C:\codestuff\PBS\plots\\"
    save_plot(saveplot, initialstate, items, escorts, IO, "$(0)_test", save_directory)
    finalstate, makespandict, makespan = main(initialstate, items, escorts, IO, i, save_directory)
    sumtime = 0
    max_time = makespan
    if isempty(makespandict)
        println("Empty makespandict in iteration $i")
        print_matrix(finalstate)
        println(initialstate)
        println("Items: ", items)
        println("Escorts: ", escorts)
        continue
    end
    for itemid in keys(makespandict)
        sumtime += makespandict[itemid] 
    end
    average_time = sumtime / length(keys(makespandict))
    #println("Average time: ", average_time, "       Total makespan: ", max_time)
    global makespan_sum += max_time
    global average_time_sum += average_time
end
timerstop = time()

average_makespan = makespan_sum / num_iterations
average_of_average_time = average_time_sum / num_iterations
println("Time elapsed: ", timerstop - timerstart)
println("Average of makespan: ", average_makespan)
println("Avg of Avg times: ", average_of_average_time)
=#

