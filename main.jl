using Random
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
function createbatch!(itemstopick, incumbentstate, time, n, IO)
    batch = Dict{String, Any}()
    iox, ioy = IO
    for itemid in keys(itemstopick)
        item = itemstopick[itemid]
        for i in 1:size(incumbentstate, 1), j in 1:size(incumbentstate, 2)
            if incumbentstate[i, j] == itemid
            item.coords = (i, j)
            break
            end
        end        
    end
    distances = Dict(itemid => abs(items[itemid].coords[1] - iox) + abs(items[itemid].coords[2] - ioy) for itemid in keys(itemstopick))
    
    sorted_distances = sort(collect(distances), by = x -> x[2])
    for itemid in keys(itemstopick)
        item= itemstopick[itemid]
        if item.deadline <= time && length(keys(batch)) < n
            batch[itemid] = item
        end
    end
    while length(batch) < n && !isempty(sorted_distances)
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
function main(initialstate, items, escorts, IO)
    itemstopick = deepcopy(items)
    incumbentstate = deepcopy(initialstate)
    makespandict = Dict{String, Int64}()
    n= 3 # batch size
    r = 1 # replenishment size
    time = 0
    batch = createbatch!(itemstopick, incumbentstate, time, n, IO)
   
    while !(isempty(itemstopick)&&isempty(batch))
        savemakespan_item!(makespandict, itemstopick, batch, incumbentstate, IO, time) # deletes items from batch 
        if length(batch) <= n-r #decide on batch 
            newcandidates = createbatch!(itemstopick, incumbentstate, time, r, IO) 
            if !isempty(newcandidates)
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
        
        #save escorts for items 
        save_item_escorts!(incumbentstate, batch, escorts, IO)

        #assign escorts for items unique
        moverescortids, blockmat = item_escort_assigment!(incumbentstate, batch, escorts, IO) 
 
    
        incumbentstate = moveescorts!(time, incumbentstate, batch, escorts, moverescortids, blockmat, IO)
        save_plot(saveplot, incumbentstate, batch, escorts, IO, "$(time)_test", save_directory)
        time +=1
    end
    return incumbentstate, time
end


item_deadlines = Dict("$i" => rand() * 100 for i in 1:6)
IO= (3,1)
initialstate, items, escorts = randomintialstate((5, 5), 2, item_deadlines, rng)
save_directory = raw"C:\codestuff\PBS\plots\\"
iteration = 0
global saveplot = true # TURN OFF FOR DEBUGGING
save_plot(saveplot, initialstate, items, escorts, IO, "$(iteration)_test", save_directory)


finalstate, retrievaltimes = main(initialstate, items, escorts, IO)