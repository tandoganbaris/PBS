using Random
using Statistics
include("structs.jl")
include("pbsviz.jl")
include("move.jl")

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
function savemakespan_item!(makespandict, items, batch, incumbentstate, IO, time) # will need to mod for multiIO
    iox, ioy = IO
    if incumbentstate[iox, ioy] in keys(items) 
        itemid = incumbentstate[iox, ioy]
        #item = items[itemid]
        makespandict[itemid] = time
        delete!(items, itemid)
        if haskey(batch, itemid)
            delete!(batch, itemid)
        end
    elseif incumbentstate[iox, ioy] in keys(batch)
        itemid = incumbentstate[iox, ioy]
        makespandict[itemid] = time
        delete!(batch, itemid)
    end
    #=
    for itemid in keys(batch)
        item = batch[itemid]
        if atIO(item, IO)
            makespandict[itemid] = time
        end
        delete!(batch, itemid)
    end
    =#
   
end
"""
pushes either the most urgent of the closest items to batch
"""
function createbatch!(itemstopick, incumbentstate, time, r, IO)
    batch = Dict{String, Any}()
    iox, ioy = IO

    for idx in CartesianIndices(incumbentstate)
        if incumbentstate[idx] in keys(itemstopick)
            item = itemstopick[incumbentstate[idx]]
            item.coords = Tuple(idx)
        end
    end
    
    distances = Dict(itemid => abs(itemstopick[itemid].coords[1] - iox) + abs(itemstopick[itemid].coords[2] - ioy) for itemid in keys(itemstopick))
    
    sorted_distances = sort(collect(distances), by = x -> x[2])
    for itemid in keys(itemstopick)
        item= itemstopick[itemid]
        if item.deadline <= time && length(keys(batch)) < r
            batch[itemid] = item
            if haskey(itemstopick, itemid)
                delete!(itemstopick, itemid)
            end
            deleteat!(sorted_distances, 1)
        end
    end
    while length(batch) < r && !isempty(sorted_distances)
        itemid = sorted_distances[1][1]
        item = itemstopick[itemid]
        batch[itemid] = item
        if haskey(itemstopick, itemid)
            delete!(itemstopick, itemid)
        end
        deleteat!(sorted_distances, 1)
    end
    return batch
end
function main(initialstate, items, escorts, IO, save_directory)
    itemstopick = deepcopy(items)
    local incumbentstate = deepcopy(initialstate)
    makespandict = Dict{String, Int64}()
    n= 7 # batch size
    r = 1 # replenishment size
    time = 0
    local batch = createbatch!(itemstopick, incumbentstate, time, n, IO)
   
    while !(isempty(itemstopick)&&isempty(batch))
        savemakespan_item!(makespandict, itemstopick, batch, incumbentstate, IO, time) # deletes items from batch 
        if length(batch) <= n-r #decide on batch 
            newcandidates = createbatch!(itemstopick, incumbentstate, time, r, IO) 
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
        if time == 24
            #print("break")
        end
        #assign escorts for items unique
        moverescortids, blockmat = item_escort_assigment!(incumbentstate, batch, escorts, time, IO) 
 
    
        moveescorts!(time, incumbentstate, batch, escorts, moverescortids, blockmat, IO)
        #checksync_main(incumbentstate, escorts, batch)
        save_plot(saveplot, incumbentstate, batch, escorts, IO, "$(time)_test", save_directory)
        time +=1
        if time >1000
            break
        end
    end
    return incumbentstate, makespandict
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
global makespan_sum = 0
global average_time_sum = 0
num_iterations = 10
for i in 1:num_iterations
    if i ==2
        global saveplot = false
    else
        global saveplot = false
    end
    #item_deadlines = Dict("$i" => Float64(1000 - i * 10) for i in 1:10) 
    item_deadlines = Dict("$i" => Float64(20 + (i - 1) * 10) for i in 1:10)
    IO= (1,1)
    initialstate, items, escorts = randomintialstate((10, 10), 4, item_deadlines, rng)
    save_directory = raw"C:\codestuff\PBS\plots\\"
    save_plot(saveplot, initialstate, items, escorts, IO, "$(0)_test", save_directory)
    finalstate, makespandict = main(initialstate, items, escorts, IO, save_directory)
    sumtime = 0
    max_time = 0
    for itemid in keys(makespandict)
        sumtime += makespandict[itemid]
        if makespandict[itemid] > max_time
            max_time = makespandict[itemid]
        end
    end
    average_time = sumtime / length(keys(makespandict))
    #println("Average time: ", average_time, "       Total makespan: ", max_time)
    global makespan_sum += max_time
    global average_time_sum += average_time
end
average_makespan = makespan_sum / num_iterations
average_of_average_time = average_time_sum / num_iterations

println("Average of makespan: ", average_makespan)
println("Avg of Avg times: ", average_of_average_time)
