using Statistics
using DataStructures
"""
assigns escorts to items based on the initial sorting (in the function) and the positions in the matrix
"""
function PBSengine!(iteration, incumbentstate, batch, escorts, IO;obj="makespan")
     #assign escorts for items unique
    if obj == "makespan"
        if isa(IO, Tuple)
            moved_any = false
            moverescortids, blockmat = item_escort_assigment!(incumbentstate, batch, escorts, iteration, IO) 
            moved_any = moveescorts!(iteration, incumbentstate, batch, escorts, moverescortids, blockmat, IO)
            return moved_any
        elseif isa(IO, Vector{Tuple{Int,Int}})
            (io_blockmats, global_blockmat, global_escort_items, item_to_ios) = item_escort_IO_assigment!(incumbentstate, batch, escorts, iteration, IO) 
            moved_any = moveescorts_flow_multi_io!(iteration, incumbentstate, batch, escorts, 
                           io_blockmats, global_blockmat, global_escort_items,IO, item_to_ios)
            return moved_any
        else
            throw(ArgumentError("IO in wrong format: should be a Tuple{x=int,y=int} or an Vector{Tuple{Int,Int}}"))
        end
    elseif obj == "flowtime"
        if isa(IO, Tuple)
            moved_any = false
            moverescortids, blockmat = item_escort_assigment!(incumbentstate, batch, escorts, iteration, IO) 
            moved_any = moveescorts_flow!(iteration, incumbentstate, batch, escorts, moverescortids, blockmat, IO)
            return moved_any
        elseif isa(IO, Vector{Tuple{Int,Int}})
               (io_blockmats, global_blockmat, global_escort_items, item_to_ios) = item_escort_IO_assigment!(incumbentstate, batch, escorts, iteration, IO) 
            moved_any = moveescorts_flow_multi_io!(iteration, incumbentstate, batch, escorts, 
                           io_blockmats, global_blockmat, global_escort_items,IO, item_to_ios)
            return moved_any
            # Handle the case where IO is an array of tuples
        else
            throw(ArgumentError("IO in wrong format: should be a Tuple{x=int,y=int} or an Vector{Tuple{Int,Int}}"))
        end
    end   
end

function item_IO_assignment(item, IO)
    if isa(IO, Tuple)
        item.assigned_io = IO
    elseif isa(IO, Vector{Tuple{Int,Int}})
        item.assigned_io = IO
    else
        throw(ArgumentError("IO in wrong format: should be a Tuple{x=int,y=int} or an Vector{Tuple{Int,Int}}"))
    end
end


function item_escort_IO_assigment!(matrix, items, escorts, iteration, IO)
    # Handle multi-IO case: create separate assignments for each IO
    if isa(IO, Vector{Tuple{Int,Int}})
        io_assignments = Dict()  # Will store: IO => (escortstomovefirst, blockmat, itemescortdict)
        
        resetescorts!(escorts, iteration)  # Reset escorts once for all IOs
        
        # Pre-process: determine which IOs are relevant for each item
        item_to_ios = Dict{String, Vector{Tuple}}()  # item_id => [primary_io, secondary_io (if any)]
        
        for item_id in keys(items)
            item_x, item_y = items[item_id].coords
            
            # Calculate distances to all IOs
            io_distances = [(io, euclidean_distance((item_x, item_y), io)) for io in IO]
            sort!(io_distances, by = x -> x[2])  # Sort by distance
            
            # Keep at most 2 closest IOs, with x-coordinate filtering
            relevant_ios = []
            for (i, (io, dist)) in enumerate(io_distances[1:min(2, length(io_distances))])
                io_x, io_y = io
                should_consider = true
                
                # X-coordinate alignment check
                if i == 1
                    # Always consider the closest IO
                    push!(relevant_ios, io)
                else
                    # For secondary IO, check x-coordinate alignment
                    primary_io_x, _ = io_distances[1][1]
                    
                    # Don't consider secondary IO if item is not between/beyond the IOs
                    if (item_x < min(primary_io_x, io_x)) || (item_x > max(primary_io_x, io_x))
                        # Item is on one side, only one IO is relevant
                        if item_x < min(primary_io_x, io_x)
                            # Item is to the left, keep the leftmost IO (already primary)
                            should_consider = false
                        elseif item_x > max(primary_io_x, io_x)
                            # Item is to the right, replace primary with rightmost if primary is not rightmost
                            if primary_io_x > io_x
                                should_consider = false
                            else
                                # Primary is leftmost, secondary is rightmost - keep both logic
                                push!(relevant_ios, io)
                                should_consider = false
                            end
                        end
                    else
                        # Item is between or near both IOs
                        x_gap = abs(primary_io_x - io_x)
                        x_to_primary = abs(item_x - primary_io_x)
                        x_to_secondary = abs(item_x - io_x)
                        
                        # Check if we already have a secondary IO; if current candidate is closer, replace it
                        if length(relevant_ios) > 1
                            existing_io = relevant_ios[2]
                            existing_io_x, _ = existing_io
                            
                            # If current candidate is closer to item than existing secondary, replace it
                            if x_to_secondary < abs(item_x - existing_io_x)
                                # Replace the secondary IO with the closer one
                                relevant_ios[2] = io
                            end
                            should_consider = false  # Don't push again, we either replaced or skipped
                        else
                            # No secondary IO yet, decide if we should add this one
                            if x_to_secondary < x_gap *0.3
                                should_consider = true
                            else
                                # Large gap: only consider if secondary is significantly closer
                                should_consider = x_to_secondary < x_to_primary
                            end
                        end
                    end
                    
                    if should_consider
                        push!(relevant_ios, io)
                    end
                end
            end
            
            if !isempty(relevant_ios)
                item_to_ios[item_id] = relevant_ios
            end
        end
        
        for io in IO
            # Only process items relevant to this IO
            relevant_items = [item_id for item_id in keys(items) if haskey(item_to_ios, item_id) && io in item_to_ios[item_id]]
            
            if isempty(relevant_items)
                # No relevant items for this IO, skip
                io_assignments[io] = ([0 for _ in 1:size(matrix, 1), _ in 1:size(matrix, 2)], Dict())
                continue
            end
            
            io_x, io_y = io
            sorted_keys = sort_keys_by_distance_and_sum(items, io, relevant_items)
            
            # For each IO, create independent escort availability
            availableescorts = deepcopy(collect(keys(escorts)))
            itemescortdict = Dict{String, Tuple{Vector{String}, Vector{String}}}()
            blockmat = [0 for _ in 1:size(matrix, 1), _ in 1:size(matrix, 2)]
            escort_items_dict = Dict{String, Tuple{Vector{String}, Vector{String}}}()  # Save assignments per IO
            
            updateitemescorts!(itemescortdict, items, sorted_keys, escorts, availableescorts, blockmat, iteration, io)
            
            # Assignment loop for this specific IO - use stable iteration
            remaining_keys = deepcopy(sorted_keys)
            for key in deepcopy(sorted_keys)
                item = items[key]
                escortsx = itemescortdict[key][1]
                escortsy = itemescortdict[key][2]
                x , y = items[key].coords    
                filter!(x -> x != key, remaining_keys) # remove this item from remaining
                
                if (length(escortsx) == 0 && length(escortsy) == 0)
                    item.direction = 0 # not move               
                    continue
                end
                
                escortid = 0  # Track the escort assigned
                
                if length(escortsx) == 0 && length(escortsy) > 0
                    item.direction = 2 # move in y
                    escortid = find_nearest_escort_multi_io(key, items, remaining_keys, matrix, io, blockmat, 2, escorts, escortsx, escortsy, iteration, IO, item_to_ios)
                    if escortid == 0
                        itemescortdict[key] = (itemescortdict[key][1], Vector{String}())
                        continue
                    else
                        updateblockmat!(blockmat, item, escorts[escortid])
                        filter!(x -> x != escortid, availableescorts)
                        updateitemescortslight!(itemescortdict, items, remaining_keys, escorts, availableescorts, blockmat, iteration, io)
                    end
                
                elseif length(escortsy) == 0 && length(escortsx) > 0
                    item.direction = 1
                    escortid = find_nearest_escort_multi_io(key, items, remaining_keys, matrix, io, blockmat, 1, escorts, escortsx, escortsy, iteration, IO, item_to_ios)
                    if escortid == 0
                        itemescortdict[key] = (Vector{String}(), itemescortdict[key][2])
                        continue
                    else
                        updateblockmat!(blockmat, item, escorts[escortid])
                        filter!(x -> x != escortid, availableescorts)
                        updateitemescortslight!(itemescortdict, items, remaining_keys, escorts, availableescorts, blockmat, iteration, io)
                    end
                
                elseif length(escortsx) > 0 && length(escortsy) > 0 # prefer x direction
                    preferred_dir = length(escortsx) > length(escortsy) ? 1 : 2
                    secondary_dir = preferred_dir == 1 ? 2 : 1
                    item.direction = preferred_dir
                    escortid = find_nearest_escort_multi_io(key, items, remaining_keys, matrix, io, blockmat, preferred_dir, escorts, escortsx, escortsy, iteration, IO, item_to_ios)
                    if escortid == 0
                        escortid = find_nearest_escort_multi_io(key, items, remaining_keys, matrix, io, blockmat, secondary_dir, escorts, escortsx, escortsy, iteration, IO, item_to_ios)
                        if escortid == 0
                            continue
                        else
                            item.direction = secondary_dir
                            updateblockmat!(blockmat, item, escorts[escortid])
                            filter!(x -> x != escortid, availableescorts)
                            updateitemescortslight!(itemescortdict, items, remaining_keys, escorts, availableescorts, blockmat, iteration, io)
                        end
                    else
                        updateblockmat!(blockmat, item, escorts[escortid])
                        filter!(x -> x != escortid, availableescorts)
                        updateitemescortslight!(itemescortdict, items, remaining_keys, escorts, availableescorts, blockmat, iteration, io)
                    end
                end
                
                # Final assignment if escortid is not 0 - save to escort_items_dict instead of modifying escorts directly
                if escortid != 0
                    if item.direction == 2
                        # Save itemsy assignment for this IO
                        if !haskey(escort_items_dict, escortid)
                            escort_items_dict[escortid] = (Vector{String}(), Vector{String}())
                        end
                        escort_items_dict[escortid] = (escort_items_dict[escortid][1], [key])
                    elseif item.direction == 1
                        # Save itemsx assignment for this IO
                        if !haskey(escort_items_dict, escortid)
                            escort_items_dict[escortid] = (Vector{String}(), Vector{String}())
                        end
                        escort_items_dict[escortid] = ([key], escort_items_dict[escortid][2])
                    end
                end

                # Clean up itemescortdict for items no longer being processed
                for rm_key in setdiff(collect(keys(itemescortdict)), remaining_keys)
                    delete!(itemescortdict, rm_key)
                end
                if all((length(itemescortdict[key][1]) + length(itemescortdict[key][2])) == 0 for key in keys(itemescortdict))
                    break
                end
            end
            
            # Store this IO's assignments: blockmat and escort-item mappings
            io_assignments[io] = (blockmat, escort_items_dict)
        end
        
        # Prepare global structures for the next phase of assignment
        # Merge blockmats and build global blockmat
        global_blockmat = [0 for _ in 1:size(matrix, 1), _ in 1:size(matrix, 2)]
        io_blockmats = Dict()
        # Structure: escort_id => [(io, itemsx, itemsy), ...] to preserve which IO each assignment is for
        global_escort_items = Dict{String, Vector{Tuple{Tuple, Vector{String}, Vector{String}}}}()
        
        for io in IO
            if haskey(io_assignments, io)
                blockmat, escort_items_dict = io_assignments[io]
                io_blockmats[io] = blockmat
                
                # Merge into global blockmat (1 if assigned in any IO)
                for i in 1:size(global_blockmat, 1), j in 1:size(global_blockmat, 2)
                    if blockmat[i, j] == 1
                        global_blockmat[i, j] = 1
                    end
                end
                
                # Merge escort assignments globally, preserving the IO information
                for (escort_id, (itemsx, itemsy)) in escort_items_dict
                    if !haskey(global_escort_items, escort_id)
                        global_escort_items[escort_id] = []
                    end
                    # Store: (io, itemsx, itemsy) so we know which IO these items belong to
                    push!(global_escort_items[escort_id], (io, itemsx, itemsy))
                end
            end
        end
        
        # Return all data needed for intelligent multi-IO assignment:
        # - io_blockmats: individual blockmat for each IO (for IO-specific decisions)
        # - global_blockmat: merged blockmat across all IOs (for global conflict detection)
        # - global_escort_items: which escorts are already assigned, to what items, and for which IO
        # - item_to_ios: which IOs each item can use (for fallback logic)
        return (io_blockmats, global_blockmat, global_escort_items, item_to_ios)

    else
        throw(ArgumentError("IO in wrong format: should be a Tuple{x=int,y=int} or an Vector{Tuple{Int,Int}}"))
    end
end

function item_escort_assigment!(matrix, items, escorts, iteration, IO) 
    #save_item_escorts!(matrix, items, escorts, IO)
    io_x, io_y = IO
    sorted_keys = sort_keys_by_distance_and_sum(items, IO)
    escortstomovefirst= []
    # sort the items by the increasing number of total escorts
    resetescorts!(escorts, iteration)
    availableescorts = deepcopy(collect(keys(escorts)))
    itemescortdict = Dict{String, Tuple{Vector{String}, Vector{String}}}() # save number of escorts that can serve item
    blockmat = [0 for _ in 1:size(matrix, 1), _ in 1:size(matrix, 2)]
    updateitemescorts!(itemescortdict, items, sorted_keys, escorts, availableescorts, blockmat, iteration, IO)
      
    for key in deepcopy(sorted_keys)
        item = items[key]
        escortsx = itemescortdict[key][1]
        escortsy = itemescortdict[key][2]
        x , y = items[key].coords    
        sorted_keys = filter(x -> x != key, sorted_keys) # remove this item as now we will decide its future
        if length(escortsx) == 0 && length(escortsy) == 0
            item.direction = 0 # not move               
            continue
        end
        if length(escortsx) == 0 && length(escortsy) > 0
            item.direction = 2 # move in y
            escortid = find_nearest_escort(key, items, sorted_keys, matrix, IO, blockmat,2,escorts, escortsx, escortsy,iteration) # is 0 if no escort is available (path blocked)
            if escortid == 0
                #println("No escort found for item ", key)
                itemescortdict[key] = (itemescortdict[key][1], Vector{String}())
                continue
                
            else
                updateblockmat!( blockmat, item, escorts[escortid])
                filter!(x -> x != escortid, availableescorts)
                updateitemescortslight!(itemescortdict, items, sorted_keys, escorts, availableescorts, blockmat,iteration, IO)
            end
        
        elseif length(escortsy) == 0 && length(escortsx) > 0
            item.direction = 1
            escortid = find_nearest_escort(key, items, sorted_keys, matrix, IO, blockmat,1,escorts, escortsx, escortsy, iteration) 
            if escortid == 0
                #println("No escort found for item ", key)
                itemescortdict[key] = (Vector{String}(), itemescortdict[key][2])
                continue
            else
                updateblockmat!( blockmat, item, escorts[escortid])
                filter!(x -> x != escortid, availableescorts)
                updateitemescortslight!(itemescortdict, items, sorted_keys, escorts, availableescorts, blockmat, iteration,IO)
            end
        
        elseif length(escortsx)>0 && length(escortsy) > 0 # prefer x direction
            preferred_dir = length(escortsx) > length(escortsy) ? 1 : 2
            secondary_dir = preferred_dir == 1 ? 2 : 1
            item.direction = preferred_dir
            escortid = find_nearest_escort(key, items, sorted_keys, matrix, IO, blockmat, preferred_dir, escorts,escortsx, escortsy, iteration)
            if escortid == 0
                escortid = find_nearest_escort(key, items, sorted_keys, matrix, IO, blockmat, secondary_dir, escorts, escortsx, escortsy,iteration)
                if escortid == 0
                    continue
                else
                    item.direction = secondary_dir
                    updateblockmat!(blockmat, item, escorts[escortid])
                    filter!(x -> x != escortid, availableescorts)
                    updateitemescortslight!(itemescortdict, items, sorted_keys, escorts, availableescorts, blockmat,iteration, IO)
                end
            else
                updateblockmat!(blockmat, item, escorts[escortid])
                filter!(x -> x != escortid, availableescorts)
                updateitemescortslight!(itemescortdict, items, sorted_keys, escorts, availableescorts, blockmat, iteration, IO)
            end
        end
        #Final assignment if escortid is not 0
        push!(escortstomovefirst, escortid)
        if item.direction == 2
            escorts[escortid].itemsy = [key]
        elseif item.direction == 1
            escorts[escortid].itemsx = [key]
        end

        # Remove the key from sorted_keys for the next iteration and re sort according to number of escorts
        
        sorted_keys = sort_keys_by_distance_and_sum(items, IO)
        for key in setdiff(collect(keys(itemescortdict)), sorted_keys)
            delete!(itemescortdict, key)
        end
        if all((length(itemescortdict[key][1]) + length(itemescortdict[key][2])) == 0 for key in keys(itemescortdict))
            break
        end
    end
    #print_matrix(matrix, blockmat)
    return escortstomovefirst, blockmat

end
function updateitemescorts!(itemescortdict, items, sorted_keys,  escorts, availableescorts, blockmat, iteration,  IO)
    io_x, io_y = IO
    for key in sorted_keys
        item = items[key]
        item.direction = 0
        escortsx = Vector{String}()
        escortsy = Vector{String}()
        x , y = items[key].coords
        for escort_id in availableescorts
            ex, ey = escorts[escort_id].coords
            if ey == y && x != io_x 
                if allowedOrder(ex, io_x,x) && # escort is on the right side and item has to move right
                    noblock(blockmat, x, y, ex, ey) &&
                    !(haskey(escorts[escort_id].banset, iteration) && key in escorts[escort_id].banset[iteration])
                    push!(escortsx, escort_id)
                end
            elseif ex == x && ey < y && # escort is on the right side and item has to move right
                noblock(blockmat, x, y, ex, ey) &&
                !(haskey(escorts[escort_id].banset, iteration) && key in escorts[escort_id].banset[iteration])# escort is below the item and the x coord is the save_item_escorts
                push!(escortsy, escort_id)
            end
        end
        itemescortdict[key] = (escortsx, escortsy)
        items[key].escortssum = length(escortsx) + length(escortsy)
    end
end
function updateitemescortslight!(itemescortdict, items, sorted_keys,  escorts, availableescorts, blockmat, iteration,  IO)
    io_x, io_y = IO
    # Remove keys from itemescortdict that are not in sorted_keys
    for key in sorted_keys
        item = items[key]
        escortsx = itemescortdict[key][1]
        escortsy = itemescortdict[key][2]
        x , y = items[key].coords
        for escort_id in escortsx
            ex, ey = escorts[escort_id].coords
            if !(ey == y && allowedOrder(ex, io_x,x) && # escort is on the right side and item has to move right
                noblock(blockmat, x, y, ex, ey) && escort_id in availableescorts) || (haskey(escorts[escort_id].banset, iteration) && key in escorts[escort_id].banset[iteration])
                filter!(x -> x != escort_id, escortsx)
            end
        end
        for escort_id in escortsy
            ex, ey = escorts[escort_id].coords
            if !(ex == x && ey < y && 
                noblock(blockmat, x, y, ex, ey) && escort_id in availableescorts) || (haskey(escorts[escort_id].banset, iteration) && key in escorts[escort_id].banset[iteration])# escort is below the item and the x coord is the save_item_escorts
                filter!(x -> x != escort_id, escortsy)
            end
        end
        itemescortdict[key] = (escortsx, escortsy)
        items[key].escortssum = length(escortsx) + length(escortsy)
    end
end
function noblock(blockmat, x, y, ex, ey)
    if x == ex
        ystart = min(y, ey)
        yend = max(y, ey)
        for y in ystart:yend
            if blockmat[x, y] == 1
                return false
            end
        end
    elseif y == ey
        xstart = min(x, ex)
        xend = max(x, ex)
        for x in xstart:xend
            if blockmat[x, y] == 1
                return false
            end
        end
    end
    return true
end
function euclidean_distance(coords1, coords2)
    return sqrt((coords1[1] - coords2[1])^2 + (coords1[2] - coords2[2])^2)
end
"""
sorting function. currently by decreasing distance and then increasing number of escorts. (furthest away item is first)
"""
function sort_keys_by_distance_and_sum(items, IO, relevant_items=nothing)
    if relevant_items === nothing
        keys_to_sort = collect(keys(items))
    else
        keys_to_sort = intersect(relevant_items, collect(keys(items)))
    end
    sorted_keys = sort(keys_to_sort, by = x -> (
        -euclidean_distance(items[x].coords, IO),  # Negative Euclidean distance for decreasing order
        items[x].escortssum  # Sum of lengths for increasing order
    ))
    return sorted_keys
end
function sort_keys_by_distance(items, IO, increasing) 
    if increasing
        sorted_keys = sort(collect(keys(items)), by = x -> (
        euclidean_distance(items[x].coords, IO))) # Negative Euclidean distance for decreasing order
    else
        sorted_keys = sort(collect(keys(items)), by = x -> (
            -euclidean_distance(items[x].coords, IO))) 
    end
    
    return sorted_keys
end
function sort_urgkeys_by_distance_toescort(items, urgkeys, esccoords,increasing) 
    if increasing
        sorted_keys = sort(collect(urgkeys), by = x -> (
        euclidean_distance(items[x].coords, esccoords))) # Negative Euclidean distance for decreasing order
    else
        sorted_keys = sort(collect(urgkeys), by = x -> (
            -euclidean_distance(items[x].coords, esccoords))) 
    end
    
    return sorted_keys
end
function sort_keys_by_urgency_distance(items, IO, iteration, increasing)
    # Identify urgent customers
    urgentcustomers = filter(
        c_id -> floor(Int, iteration + (abs(IO[1] - items[c_id].coords[1]) + items[c_id].coords[2]) * 1.5)
                >= items[c_id].deadline,
        keys(items)
    )
    normalcustomers = isempty(urgentcustomers) ? keys(items) : setdiff(keys(items), urgentcustomers)
    
    
    if  !isempty(urgentcustomers)# Sort urgent customers by (deadline - iteration - distance), ascending
        urgent_sorted = sort(collect(urgentcustomers), by = c_id ->
            items[c_id].deadline - (
                iteration + euclidean_distance(items[c_id].coords, IO)
            )
        )
    end
    # Sort normal customers by distance, ascending or descending
    if increasing
        normal_sorted = sort(collect(normalcustomers), by = c_id -> euclidean_distance(items[c_id].coords, IO))
    else
        normal_sorted = sort(collect(normalcustomers), by = c_id -> -euclidean_distance(items[c_id].coords, IO))
    end

    return vcat(urgent_sorted, normal_sorted)
end

"""
updateblockmat! updates the blockmat with the block between item and escort after assignment
"""
function updateblockmat!( blockmat, item, escort) # ban the block between item and escort
    itemx, itemy = item.coords
    escortx, escorty = escort.coords
    if  itemx == escortx
        ystart = min(itemy, escorty)
        yend = max(itemy, escorty)
        for y in ystart:yend
            blockmat[itemx, y] = 1
        end
    elseif itemy == escorty
        xstart = min(itemx, escortx)
        xend = max(itemx, escortx)
        for x in xstart:xend
            blockmat[x, itemy] = 1
        end
    end
end
"""
updateblockmat_e! updates the blockmat with the block between escort curr and escort fin coords
"""
function updateblockmat_e!( blockmat, escortx, escorty, finx, finy; val = 1) # ban the block between item and escort
    if escortx == finx # direction Y 
        ystart = min(escorty, finy)
        yend = max(escorty, finy)
        for y in ystart:yend
            blockmat[escortx, y] = val
        end           
    elseif escorty == finy # direction X
        xstart = min(escortx, finx)
        xend = max(escortx, finx)
        for x in xstart:xend
            blockmat[x, escorty] = val
        end
    end
end
function updateurgmats_e!(urgmats, escortx, escorty, finx, finy; val = 1)
    for urgid in keys(urgmats)
        if escortx == finx # direction Y 
            ystart = min(escorty, finy)
            yend = max(escorty, finy)
            for y in ystart:yend
                urgmats[urgid][escortx, y] = val
            end           
        elseif escorty == finy # direction X
            xstart = min(escortx, finx)
            xend = max(escortx, finx)
            for x in xstart:xend
                urgmats[urgid][x, escorty] = val
            end
        end
    end
end
"""
Given everything it finds the nearest escort to item. checks the path, if another item can be servd it serves it too.

"""
#=
# Multi-IO Find Nearest Escort Function - Logic Explanation

An escort should NOT be assigned to an item if:

1. **The escort is "too far out"**: The escort lies beyond another IO (from current IO perspective) that has unassigned items needing to move in the same direction
   - Example: `item1, io1, io2, escort, item2`
   - item1 moves toward io1, item2 moves toward io2
   - Escort is beyond io2 - should serve item2 for io2, not item1 for io1

2. **Multiple items same direction**: There are other unassigned items that also need to move in the same direction toward the same IO
   - Example: `item1, io1, item2, io2, escort`
   - Both items move right toward their respective IOs
   - Escort should wait to serve both (or the one further out first to maintain furthest-first principle)


# Algorithm Steps


# Step 2: Check escort distance vs other IOs
For each candidate escort:
- Calculate distance from escort to current_io
- For each other IO in `all_ios`:
  - Check if that IO has unassigned items needing same direction
  - If escort is FURTHER from current_io than that other IO is, SKIP escort
  - Reasoning: Escort should serve the IO it's closer to

# Step 3: Detect multi-item opportunity (doubleserve)
- Check path between item and escort
- Identify other items on this path that could be served together
- Mark them for batch assignment

# Step 4: Validate path and return
- Ensure path is not blocked
- Return escort ID if valid, 0 otherwise

# Key Variables

- `escort_dist_to_current_io`: Distance from escort to current IO
- `other_io_dist_to_current_io`: Distance from another IO to current IO
- `competing_items`: Items that also move in same direction to same IO

=#

function find_nearest_escort_multi_io(itemid::String,items::Dict,remaining_keys::Vector, matrix::Matrix, current_io::Tuple, blockmat::Matrix, direction::Int,
    escorts::Dict,relevantescx::Vector,relevantescy::Vector,    iteration::Int,    all_ios::Vector{Tuple{Int,Int}},    item_to_ios::Dict
)
    itemx, itemy = items[itemid].coords
    nearest_id = 0
    min_dist = Inf
    iox, ioy = current_io
    doubleserve = []

    # Helper: check if escort would better serve another unassigned item
    function escort_better_for_other_item(escort_x, escort_y, direction) #TODO Monday
        # Calculate distance from current item to escort (only relevant coordinate)
        if direction == 1
            item_dist_to_escort = abs(escort_x - itemx)  # x-distance for x-movement
        else  # direction == 2
            item_dist_to_escort = abs(escort_y - itemy)  # y-distance for y-movement
        end
        
        # Check if an unassigned item closer to escort targets a different IO
        for candidate_key in remaining_keys
            if !haskey(item_to_ios, candidate_key)
                continue
            end
            
            candidate_x, candidate_y = items[candidate_key].coords
            
            # Calculate distance from candidate to escort (only relevant coordinate)
            if direction == 1
                candidate_dist_to_escort = abs(escort_x - candidate_x)
                # Is candidate CLOSER to escort than current item?
                if candidate_dist_to_escort < item_dist_to_escort && candidate_x == escort_x
                    candidate_ios = item_to_ios[candidate_key]
                    
                    # Check each IO the candidate targets
                    for candidate_io in candidate_ios
                        if candidate_io == current_io
                            continue
                        end
                        
                        # Case 1: itemx < current_io[1] < candidate_io[1] < candidate_x < escort_x
                        # Case 2: escort_x < candidate_x < candidate_io[1] < current_io[1] < itemx (mirrored)
                        if (itemx < current_io[1] < candidate_io[1] < candidate_x < escort_x ) ||
                            (escort_x < candidate_x < candidate_io[1] < current_io[1] < itemx)
                            return true
                        end
                       
                    end
                end
            elseif direction == 2
                
                candidate_dist_to_escort = abs(escort_y - candidate_y)
                # Is candidate CLOSER to escort than current item?
                if candidate_dist_to_escort < item_dist_to_escort && candidate_y == escort_y
                    candidate_ios = item_to_ios[candidate_key]
                    
                    # Check each IO the candidate targets
                    for candidate_io in candidate_ios
                        if candidate_io == current_io
                            continue
                        end
                        
                        # Not allowed cases (y-direction)
                        # Case 1: itemy < current_io[2] < candidate_io[2] < candidate_y < escort_y
                        # Case 2: escort_y < candidate_y < candidate_io[2] < current_io[2] < itemy (mirrored)
                        if (itemy < current_io[2] < candidate_io[2] < candidate_y < escort_y) ||
                            (escort_y < candidate_y < candidate_io[2] < current_io[2] < itemy)
                            return true
                        end
                        
                    end
                end
            end
        end
        return false
    end


    # Direction 1: x-direction movement
    if direction == 1
        
        for e_id in relevantescx
            escort_x, escort_y = escorts[e_id].coords
            
            # Ban check
            if haskey(escorts[e_id].banset, iteration) && itemid ∈ escorts[e_id].banset[iteration]
                continue
            end
            
            # Basic sanity checks
            if escort_y != itemy || (iox < itemx && escort_x > itemx) || (iox > itemx && escort_x < itemx)
                continue
            end
            
            # MULTI-IO CONSTRAINT: Check if escort would better serve another unassigned item
            if escort_better_for_other_item(escort_x, escort_y, 1)
                continue
            end
            
            # Check blockmat between itemx and escort_x at y = itemy
            xstart = min(itemx, escort_x)
            xend = max(itemx, escort_x)
            path_blocked = false
            
            for xx in xstart:xend
                if blockmat[xx, itemy] == 1
                    path_blocked = true
                    break
                elseif matrix[xx, itemy] ∈ remaining_keys
                    if haskey(escorts[e_id].banset, iteration) && matrix[xx, itemy] ∈ escorts[e_id].banset[iteration]
                        path_blocked = true
                    elseif !allowedOrder(escort_x, iox, xx, itemx)
                        path_blocked = true
                    else
                        push!(doubleserve, matrix[xx, itemy])
                    end
                end
            end
            
            if path_blocked
                continue
            end
            
            dist = abs(escort_x - itemx)
            if dist < min_dist
                min_dist = dist
                nearest_id = e_id
            end
        end
        
    elseif direction == 2  # y-direction movement
        
        for e_id in relevantescy
            escort_x, escort_y = escorts[e_id].coords
            
            # Ban check
            if haskey(escorts[e_id].banset, iteration) && itemid ∈ escorts[e_id].banset[iteration]
                continue
            end
            
            # Basic sanity checks
            if escort_x != itemx || escort_y > itemy
                continue
            end
            
            # MULTI-IO CONSTRAINT: Check if escort would better serve another unassigned item
            if escort_better_for_other_item(escort_x, escort_y, 2)
                continue
            end
        
            # Check blockmat between itemy and escort_y at x = itemx
            ystart = min(itemy, escort_y)
            yend = max(itemy, escort_y)
            path_blocked = false
            
            for yy in ystart:yend
                if blockmat[itemx, yy] == 1
                    path_blocked = true
                    break
                elseif matrix[itemx, yy] ∈ remaining_keys
                    if haskey(escorts[e_id].banset, iteration) && matrix[itemx, yy] ∈ escorts[e_id].banset[iteration]
                        path_blocked = true
                    elseif !allowedOrder(escort_y, ioy, yy, itemy)
                        path_blocked = true
                    else
                        push!(doubleserve, matrix[itemx, yy])
                    end
                end
            end
            
            if path_blocked
                continue
            end
            
            dist = abs(escort_y - itemy)
            if dist < min_dist
                min_dist = dist
                nearest_id = e_id
            end
        end
    end
    

  
    if nearest_id != 0 #TODO should we check for all ios this block? 
        escort_x, escort_y = escorts[nearest_id].coords
        if ((abs(iox - escort_x) + abs(ioy - escort_y)) <= length(keys(items))+1) # escort in close proximity to IO, therefore its move will be controlled
            futurecoords = generatefuturecoords_multi_io(items, escorts, direction, nearest_id, itemid, matrix, item_to_ios, current_io)
            samecoords =[]
            if direction == 2
                samecoords = filter(x -> x[1] == itemx &&  x[2] >= min(itemy, escort_y) && x[2] <= max(itemy, escort_y), futurecoords)
            elseif direction ==1
                samecoords = filter(x -> x[2] == itemy &&  x[1] >= min(itemx, escort_x) && x[1] <= max(itemx, escort_x), futurecoords)
            end
            if !isempty(samecoords)
                minDist = minimum([abs(iox - coord[1]) + abs(ioy - coord[2]) for coord in samecoords])
                if minDist <= length(keys(items))+1 && # item far out from IO
                    !path_to_io_exists_if(matrix, futurecoords, current_io)   # check with A* if this movement would cause some stupid block
                    items[itemid].direction = 0
                    return 0
                end        
            end
        end
    
        for key in doubleserve # we are lucky to serve two items 
            filter!(x -> x != key, remaining_keys)
            items[key].direction = direction
            # If path is blocked, revert assignment:
            if direction == 1
                push!(escorts[nearest_id].itemsx, key)
            elseif direction == 2
                push!(escorts[nearest_id].itemsy, key)
            end
        end
    end


    return nearest_id
end

function find_nearest_escort(itemid, items, sorted_keys, matrix, IO, blockmat, direction,escorts, relevantescx, relevantescy, iteration)
    itemx, itemy = items[itemid].coords
    nearest_id = 0
    min_dist = Inf
    iox, ioy = IO
    doubleserve = []

    if direction == 1 # x_
        for e_id in relevantescx
            escort_x, escort_y = escorts[e_id].coords 
            if haskey(escorts[e_id].banset, iteration) && itemid ∈ escorts[e_id].banset[iteration]
                continue
            end
            if escort_y != itemy || (iox < itemx && escort_x > itemx) || (iox > itemx && escort_x < itemx)
                println("saved escort$e_id: ($escort_x, $escort_y) wrong,notsameY item $(itemid) ($itemx, $itemy)")
               # print_matrix(matrix)
                continue
            end
            # Check blockmat between itemx and escort_x at y = itemy
            xstart = min(itemx, escort_x)
            xend   = max(itemx, escort_x)
            path_blocked = false
            for xx in xstart:xend
                # blockmat entry is a tuple, skip if first value is 1
                if blockmat[xx, itemy] == 1 # either already serving or another item on the path
                    path_blocked = true
                    break
                elseif matrix[xx, itemy] ∈ sorted_keys # we serve double item, delete from sorted_keys
                    if haskey(escorts[e_id].banset, iteration) && matrix[xx, itemy] ∈ escorts[e_id].banset[iteration]
                        path_blocked = true
                    elseif !allowedOrder(escort_x, iox, xx, itemx) 
                        path_blocked = true
                    else
                        push!(doubleserve, matrix[xx, itemy])
                    end
                end
            end
            if path_blocked
                continue
            end
            dist = abs(escort_x - itemx)
            if dist < min_dist
                min_dist = dist
                nearest_id = e_id
            end
        end
    elseif direction == 2 # y
        for e_id in relevantescy
            escort_x, escort_y = escorts[e_id].coords
            if haskey(escorts[e_id].banset, iteration) && itemid ∈ escorts[e_id].banset[iteration]
                continue
            end
            if escort_x != itemx || escort_y > itemy
                println("saved escort$e_id: ($escort_x, $escort_y) wrong,notsameX item $(itemid) ($itemx, $itemy)")
                #print_matrix(matrix)
                continue
            end

            # Check blockmat between itemy and escort_y at x = itemx
            ystart = min(itemy, escort_y)
            yend   = max(itemy, escort_y)
            path_blocked = false
            for yy in ystart:yend
                # blockmat entry is a tuple, skip if first value is 1
                if blockmat[itemx, yy] == 1 #
                    path_blocked = true
                    break
                elseif matrix[itemx, yy] ∈ sorted_keys # we serve double item, delete from sorted_keys
                    if haskey(escorts[e_id].banset, iteration) && matrix[itemx, yy] ∈ escorts[e_id].banset[iteration]
                        path_blocked = true
                    elseif !allowedOrder(escort_y, ioy, yy, itemy)
                        println("IO_y in the path of y movement, should not happen, check error")
                        println(e_id, " ", item.id)
                        print_matrix(matrix)
                    else
                        push!(doubleserve, matrix[itemx, yy])
                    end
                end
            end
            if path_blocked
                continue
            end            
            dist = abs(escort_y - itemy)
            if dist < min_dist
                min_dist = dist
                nearest_id = e_id
            end
        end
    end
    if nearest_id != 0
        escort_x, escort_y = escorts[nearest_id].coords
        if ((abs(IO[1] - escort_x) + abs(IO[2] - escort_y)) <= length(keys(items))+1) # escort in close proximity to IO, therefore its move will be controlled
            futurecoords = generatefuturecoords(items, escorts,direction, nearest_id, itemid, matrix, IO)
            samecoords =[]
            if direction == 2
                samecoords = filter(x -> x[1] == itemx &&  x[2] >= min(itemy, escort_y) && x[2] <= max(itemy, escort_y), futurecoords)
            elseif direction ==1
                samecoords = filter(x -> x[2] == itemy &&  x[1] >= min(itemx, escort_x) && x[1] <= max(itemx, escort_x), futurecoords)
            end
            if !isempty(samecoords)
                minDist = minimum([abs(IO[1] - coord[1]) + abs(IO[2] - coord[2]) for coord in samecoords])
                if minDist <= length(keys(items))+1 && # item far out from IO
                    !path_to_io_exists_if(matrix, futurecoords, IO)   # check with A* if this movement would cause some stupid block
                    items[itemid].direction = 0
                    return 0
                end        
            end
        end
    
        for key in doubleserve # we are lucky to serve two items 
            filter!(x -> x != key, sorted_keys)
            items[key].direction = direction
            # If path is blocked, revert assignment:
            if direction == 1
                push!(escorts[nearest_id].itemsx, key)
            elseif direction == 2
                push!(escorts[nearest_id].itemsy, key)
            end
        end
    end
       
    
    return nearest_id
end
function path_to_io_exists(matrix, items, IO)
    rows, cols = size(matrix)
    x_max, y_max = IO[1] + length(keys(items)), IO[2] 
    # Mark future positions
    future_blocked = zeros(Int, rows, cols)
    for identifier in keys(items)
        x, y = items[identifier].coords
        dir = items[identifier].direction
        futurecoords = (x,y)
        if dir == 1
            if IO[1] > x && x < rows
                futurecoords = (x + 1, y)
            elseif IO[1] < x && x > 1
                futurecoords = (x - 1, y)
            end
        elseif dir == 2
            if y > 1
                futurecoords = (x, y - 1)
            end
        else
            futurecoords = (x, y)
        end
        if futurecoords != IO
            future_blocked[futurecoords[1], futurecoords[2]] = 1
        end
    end

    # Start from the furthest position
    while future_blocked[x_max, y_max] == 1
        if x_max < cols
            x_max += 1
        elseif y_max < rows
            y_max += 1
        end
    end
   
    startcoords = (x_max, y_max)

    # A* search setup
    visited = zeros(Int, rows, cols)
    dist = fill(Inf, rows, cols)
    open_set = BinaryMinHeap{Tuple{Float64, Int, Int}}()  # Store (priority, x, y)

    # Manhattan heuristic
    h(x, y) = abs(x - startcoords[1]) + abs(y - startcoords[2])
    #h(nx, ny) = 0
    dist[IO[1], IO[2]] = 0
    # Enqueue start with priority = cost + heuristic
    priority = dist[IO[1], IO[2]] + h(IO[1], IO[2])
    push!(open_set, (priority, IO[1], IO[2]))  # Wrap everything in a tuple

    # A* loop
    while !isempty(open_set)
        (priority, cx, cy) = pop!(open_set)  # Extract priority and coordinates
    
        if visited[cx, cy] == 1
            continue
        end
        visited[cx, cy] = 1
    
        if (cx, cy) == startcoords 
            return true
        end
        
    
        # Explore neighbors
        for (nx, ny) in [(cx+1, cy), (cx-1, cy), (cx, cy+1), (cx, cy-1)]
            if 1 ≤ nx ≤ rows && 1 ≤ ny ≤ cols && future_blocked[nx, ny] != 1
                cost_here = dist[cx, cy] + 1
        
                if cost_here < dist[nx, ny]
                    if (nx, ny) == startcoords
                        return true
                    end
                    dist[nx, ny] = cost_here
                    priority = cost_here + h(nx, ny)
    
                    push!(open_set, (priority, nx, ny))  # Min-Heap allows duplicate priorities
                  
                end
            end
        end
    end
    #println("No path found to start coordinates: ", startcoords)
    #print_matrix(future_blocked, visited)
    return false
end
function path_to_io_exists_if(matrix, itemscoords, IO)
    rows, cols = size(matrix)
    dir = IO[1]>size(matrix,1)/2 ? -1 : 1 # if io is on the left we have sink right, else on the left
    x_max= dir == 1 ? min(size(matrix,1),(IO[1] + length(itemscoords))) : max(1, IO[1] - length(itemscoords)); y_max =  IO[2] 
    # Mark future positions
    future_blocked = zeros(Int, rows, cols)
    for pair in itemscoords
        x, y = pair
        if pair != IO
            future_blocked[x, y] = 1
        end
    end

    while future_blocked[x_max, y_max] == 1
        if x_max < rows
            if x_max > 1
                x_max += dir
            else
                dir = dir * -1
                x_max += dir
            end
        elseif y_max < cols
            y_max += 1
        elseif x_max == rows && y_max == cols
            y_max = Int(cols/2)
            x_max = Int(rows/2)
        end
    end
   
    startcoords = (x_max, y_max)

    # A* search setup
    visited = zeros(Int, rows, cols)
    dist = fill(Inf, rows, cols)
    open_set = BinaryMinHeap{Tuple{Float64, Int, Int}}()  # Store (priority, x, y)

    # Manhattan heuristic
    h(x, y) = abs(x - startcoords[1]) + abs(y - startcoords[2])
    #h(nx, ny) = 0
    dist[IO[1], IO[2]] = 0
    # Enqueue start with priority = cost + heuristic
    priority = dist[IO[1], IO[2]] + h(IO[1], IO[2])
    push!(open_set, (priority, IO[1], IO[2]))  # Wrap everything in a tuple

    # A* loop
    while !isempty(open_set)
        (priority, cx, cy) = pop!(open_set)  # Extract priority and coordinates
    
        if visited[cx, cy] == 1
            continue
        end
        visited[cx, cy] = 1
    
        if (cx, cy) == startcoords 
            return true
        end
        
    
        # Explore neighbors
        for (nx, ny) in [(cx+1, cy), (cx-1, cy), (cx, cy+1), (cx, cy-1)]
            if (nx, ny) == startcoords && future_blocked[nx, ny] == 1
                println("issue with wrong dest writing")
                return true
            end 
            if 1 ≤ nx ≤ rows && 1 ≤ ny ≤ cols && future_blocked[nx, ny] != 1
                cost_here = dist[cx, cy] + 1
        
                if cost_here < dist[nx, ny]
                    if (nx, ny) == startcoords
                        return true
                    end
                    dist[nx, ny] = cost_here
                    priority = cost_here + h(nx, ny)
    
                    push!(open_set, (priority, nx, ny))  # Min-Heap allows duplicate priorities
                  
                end
            end
        end
    end
    #println("No path found to start coordinates: ", startcoords)
    #print_matrix(future_blocked, visited)
    return false
end
function outwards_astar(matrix, IO, blockmat, escorts, items)
    rows, cols = size(matrix)
    allkeys = vcat(keys(escorts), keys(items))
    itemcoords = [(items[key].coords[1], items[key].coords[2]) for key in keys(items)]
    escortcoords = [(escorts[key].coords[1], escorts[key].coords[2]) for key in keys(escorts)]
    allcoords = vcat(itemcoords, escortcoords)
    x_max, y_max = 1, 1

    # Mark future positions
    future_blocked = deepcopy(blockmat)
    for pair in allcoords
        x, y = pair
        if pair != IO
            future_blocked[x, y] = 1
        end
        x_max = max(x_max, x)
        y_max = max(y_max, y)
    end
    while blockmat[x_max,y_max] ==1 || matrix[x_max,y_max] in allkeys
        if x_max < cols
            x_max += 1
        elseif y_max < rows
            y_max += 1
        end
    end

    startcoords = (x_max, y_max)

    # A* search setup
    visited = zeros(Int, rows, cols)
    dist = fill(Inf, rows, cols)
    open_set = BinaryMinHeap{Tuple{Float64, Int, Int}}()  # Store (priority, x, y)

    # Manhattan heuristic
    h(x, y) = abs(x - startcoords[1]) + abs(y - startcoords[2])

    dist[IO[1], IO[2]] = 0
    priority = dist[IO[1], IO[2]] + h(IO[1], IO[2])
    push!(open_set, (priority, IO[1], IO[2]))

    found_path = false

    # A* loop
    while !isempty(open_set)
        (priority, cx, cy) = pop!(open_set)

        if visited[cx, cy] == 1
            continue
        end
        visited[cx, cy] = 1

        if (cx, cy) == startcoords
            found_path = true
            break
        end

        # Explore neighbors
        for (nx, ny) in [(cx+1, cy), (cx-1, cy), (cx, cy+1), (cx, cy-1)]
            if (nx, ny) == startcoords && future_blocked[nx, ny] == 1
                println("issue with wrong dest writing")
                found_path = true
                break
            end
            if 1 ≤ nx ≤ rows && 1 ≤ ny ≤ cols && future_blocked[nx, ny] != 1
                cost_here = dist[cx, cy] + 1
                if cost_here < dist[nx, ny]
                    dist[nx, ny] = cost_here
                    priority = cost_here + h(nx, ny)
                    push!(open_set, (priority, nx, ny))
                end
            end
        end
        if found_path
            break
        end
    end

    # Return whether we found a path and the entire distance matrix
    return (found_path, dist)
end
function outwards_astar_with_dirchange(matrix, IO, blockmat, escortid, escorts, items; distval = 0.0)
    if isa(IO, Tuple)
        iox, ioy = IO
        rows, cols = size(matrix)
        allkeys = vcat(keys(escorts), keys(items))
        itemcoords = [(items[key].coords[1], items[key].coords[2]) for key in keys(items)]
        escortcoords = [(escorts[key].coords[1], escorts[key].coords[2]) for key in keys(escorts) if key != escortid]
        allcoords =itemcoords# vcat(itemcoords, escortcoords)
        x_max, y_max = escorts[escortid].coords
    
        # Mark future positions
        future_blocked = deepcopy(blockmat)
        for pair in allcoords
            x, y = pair
            if pair != IO
                future_blocked[x, y] = 1
            end
        end
     
    
        startcoords = (x_max, y_max)
    
        # Directions: 1 = none/initial, 2 = horizontal, 3 = vertical
        dist = fill(Inf, rows, cols, 3)
        visited = fill(false, rows, cols, 3)
    
        # If x1 == x2 => movement must be vertical (3), else horizontal (2)
        function dir_type(x1, y1, x2, y2)
            return (x1 == x2) ? 3 : 2
        end
    
        open_set = BinaryMinHeap{Tuple{Float64, Int, Int, Int}}()
    
        # Manhattan heuristic
        h(x, y) = 0.2* (abs(x - startcoords[1]) + abs(y - startcoords[2]))
    
        # Initialize at IO with direction = 1 (none/initial)
        dist[IO[1], IO[2], 1] = 0
        init_priority = dist[IO[1], IO[2], 1] + h(IO[1], IO[2])
        push!(open_set, (init_priority, IO[1], IO[2], 1))
    
        found_path = false
    
        # A* loop
        while !isempty(open_set)
            (priority, cx, cy, cdir) = pop!(open_set)
    
            if visited[cx, cy, cdir]
                continue
            end
            visited[cx, cy, cdir] = true
    
            for (nx, ny) in [(cx+1, cy), (cx-1, cy), (cx, cy+1), (cx, cy-1)]
                if 1 ≤ nx ≤ rows && 1 ≤ ny ≤ cols && future_blocked[nx, ny] != 1
                    ndir = dir_type(cx, cy, nx, ny)
                    # +1 for moving a step, plus +1 more if changing direction (excluding first step)
                    extra_cost = (cdir == 1 || cdir == ndir) ? 0 : 1  # Reduce penalty to 0.5
                    cost_here = dist[cx, cy, cdir] +  extra_cost + distval
                    if cost_here < dist[nx, ny, ndir]
                        dist[nx, ny, ndir] = cost_here
                        new_priority = cost_here + h(nx, ny)
                        push!(open_set, (new_priority, nx, ny, ndir))
                    end
                end
            end
            if (cx, cy) == startcoords
                # Ensure all slots between IOx and escx at coordinate escy are explored
                x_step = sign(cx - iox)  # Determine direction of iteration
                all_x_explored = true
                if x_step !=0
                    for x in iox:x_step:cx
                        if !visited[x, cy, cdir] && future_blocked[x, cy] != 1
                            ndir = dir_type(cx, cy, x, cy)
                            extra_cost = (cdir == 1 || cdir == ndir) ? 0 : 1
                            cost_here = dist[cx, cy, cdir] + extra_cost
                
                            if cost_here < dist[x, cy, ndir]
                                dist[x, cy, ndir] = cost_here
                                new_priority = cost_here + h(x, cy)
                                push!(open_set, (new_priority, x, cy, ndir))
                                visited[x, cy, cdir] = true  # ✅ Mark as visited
                            end
                        end
                    end
                    all_x_explored = all(visited[x, cy, cdir] || future_blocked[x, cy] == 1 for x in iox:x_step:cx)
                end
    
            
                # Ensure all slots between IOy and escy at coordinate escx are explored
                y_step = sign(cy - ioy)  # Determine direction of iteration
                all_y_explored = true
                if y_step != 0 
                    for y in ioy:y_step:cy
                        if !visited[cx, y, cdir] && future_blocked[cx, y] != 1
                            ndir = dir_type(cx, cy, cx, y)
                            extra_cost = (cdir == 1 || cdir == ndir) ? 0 : 1
                            cost_here = dist[cx, cy, cdir] + extra_cost
                
                            if cost_here < dist[cx, y, ndir]
                                dist[cx, y, ndir] = cost_here
                                new_priority = cost_here + h(cx, y)
                                push!(open_set, (new_priority, cx, y, ndir))
                                visited[cx, y, cdir] = true  # ✅ Mark as visited
                            end
                        end
                    end
                    all_y_explored = all(visited[cx, y, cdir] || future_blocked[cx, y] == 1 for y in ioy:y_step:cy)
                end
            
                
            
                if all_x_explored && all_y_explored  # ✅ Only mark found if the full range is covered
                    found_path = true
                    break
                end
            end
        end
    
        # Convert dist into a 2D cost by taking the minimum cost ignoring direction
        min_cost = fill(Inf, rows, cols)
        for x in 1:rows
            for y in 1:cols
                if distval == 0.0
                    min_cost[x, y] = floor(minimum(dist[x, y, 1:3]))
                else
                    min_cost[x, y] = minimum(dist[x, y, 1:3])
                end
            end
        end
    
        return found_path, min_cost
    elseif isa(IO, Vector{Tuple{Int,Int}})
        combined_astar_matrices = zeros(Float64, rows, cols, num_io)
        for i in 1:num_io
            io = IO[i]
            worked, asternmat = outwards_astar_with_dirchange(matrix, IO, blockmat, escortid, escorts, items, distval=0.01)
            if worked
                combined_astar_matrices[:, :, i] = asternmat
            end
        end
        
        rows, cols, _ = size(combined_astar_matrices)
        min_cost = fill(Inf, rows, cols)

        for x in 1:rows
            for y in 1:cols
                # Gather non-zero values across all IO layers
                vals = [combined_astar_matrices[x, y, i] for i in 1:num_io if combined_astar_matrices[x, y, i] != 0.0]
                # Take the minimum if any non-zero values exist, otherwise leave 0
                if !isempty(vals)
                    min_cost[x, y] = minimum(vals)
                end
            end
        end

        return true, min_cost
    end
    

end
function save_item_escorts!(matrix, items, escorts, IO) #saves all escorts for all items.
    io_x , io_y = IO
    for key in keys(items)
        items[key].escortsx = Vector{String}()
        items[key].escortsy = Vector{String}()
        items[key].direction = 0 
        x , y = items[key].coords
        x_dir = io_x > x ? 1 : -1 
        x_dir = io_x == x ? 0 : x_dir
        for escort_id in keys(escorts)
            ex, ey = escorts[escort_id].coords
            #if (matrix[ex, ey] != escort_id) # if escort is already serving the item
            #    println("Escort coords saved wrong!: $escort_id saved at $ex, $ey")
            #    print_matrix(matrix)
            #end
            if ey == y && x != io_x 
                if allowedOrder(ex, io_x,x) # escort is on the right side and item has to move right
                    push!(items[key].escortsx, escort_id)
                end
            elseif ex == x && ey < y  # escort is below the item and the x coord is the save_item_escorts
                push!(items[key].escortsy, escort_id)
            end
        end  
    end
end

"""moves one escort to the final coordinates, modifying the incumbent matrix and the positions of items and escorts"""
function move_escort!(matrix, items, escorts, escortid, escort_finalcoords)
    xgoal, ygoal = escort_finalcoords 
    xcurr, ycurr = escorts[escortid].coords
    direction = 0
    if xgoal == xcurr && ygoal == ycurr
        return 0
    elseif xgoal == xcurr
        if ygoal> ycurr
            direction = 2 # move escort up, block down
        elseif ygoal < ycurr
            direction = -2 # move escort down, block up
        end
    elseif ygoal == ycurr
        if xgoal > xcurr
            direction = 1 # move escort right , block to left
        elseif xgoal < xcurr
            direction = -1  # move escort left , block to right
        end
    end

    #Depending on the direction, move the block, update the coordinates of the items and escorts if they exist in the block
    if direction == 1
        for x in xcurr+1:xgoal
            cand_id = matrix[x, ycurr]
            if haskey(items, cand_id)
                items[cand_id].coords = (x-1, ycurr) # update item's coordinates
            elseif haskey(escorts, cand_id)
                escorts[cand_id].coords = (x-1, ycurr) # update escort's coordinates
            end
            matrix[x-1, ycurr] = cand_id # move block to left
            matrix[x, ycurr] = ""
        end
    elseif direction == -1
        for x in xcurr-1:-1:xgoal
            cand_id = matrix[x, ycurr]
            if haskey(items, cand_id)
                items[cand_id].coords = (x+1, ycurr) # update item's coordinates
            elseif haskey(escorts, cand_id)
                escorts[cand_id].coords = (x+1, ycurr) # update escort's coordinates
            end
            matrix[x+1, ycurr] = cand_id # move block to right
            matrix[x, ycurr] = ""
        end
    elseif direction == 2
        for y in ycurr+1:ygoal
            cand_id = matrix[xcurr, y]
            if haskey(items, cand_id)
                items[cand_id].coords = (xcurr, y-1) # update item's coordinates
            elseif haskey(escorts, cand_id)
                escorts[cand_id].coords = (xcurr, y-1) # update escort's coordinates
            end
            matrix[xcurr, y-1] = cand_id # move block down
            matrix[xcurr, y] = ""
        end
    elseif direction == -2
        for y in ycurr-1:-1:ygoal
            cand_id = matrix[xcurr, y]
            if haskey(items, cand_id)
                items[cand_id].coords = (xcurr, y+1) # update item's coordinates
            elseif haskey(escorts, cand_id)
                escorts[cand_id].coords = (xcurr, y+1) # update escort's coordinates
            end
            matrix[xcurr, y+1] = cand_id # move block up
            matrix[xcurr, y] = ""
        end
    end
    matrix[xgoal, ygoal] = escortid # update matrix
    escorts[escortid].coords = (xgoal, ygoal) # update escort's coordinates
    #print_matrix(matrix)
    return 1
end


"""
moves all escorts, starting with the mover escorts
"""
function moveescorts!(iteration, matrix, items, escorts, moverescortids, blockmat, IO)
# MOVERS FIRST

    iox, ioy = IO
    #if iteration == 5
    #    println("here")
    #end
    serveditems = []
    checkpathformovers = false
    esccoords = [(escorts[key].coords[1], escorts[key].coords[2]) for key in moverescortids]
    closeescorts = findall([abs(IO[1] - coord[1]) + abs(IO[2] - coord[2]) <= (length(keys(items))) for coord in esccoords])
    if !isempty(closeescorts)
        checkpathformovers = true
    end
    for escortid in moverescortids
        itemsx = escorts[escortid].itemsx
        itemsy = escorts[escortid].itemsy
        if !isempty(itemsx)
            direction = 1
            itemid = itemsx[1]
        elseif !isempty(itemsy)
            direction = 2
            itemid = itemsy[1]
        else
            println("No item found, check item escort assignment")
            continue
        end
        if itemid in Iterators.flatten(values(escorts[escortid].banset)) || 
            futurecoords_closetoIO(items,  itemid, escorts, escortid, direction, IO) 
            checkpathformovers = true
        end
        item = items[itemid]
        if (item.direction != direction) 
            println("Item direction and escort direction do not match")
        end

        itemx, itemy = item.coords
        escortx, escorty = escorts[escortid].coords
        # Here onwards until the move_escort! function, we find the nearest item where this escort could be useful in next time step
        candid,candx,candy = find_nearest_item_toitem(matrix, items, itemid, blockmat, IO, direction)
        gapx, gapy = abs(candx - iox), abs(candy - ioy)
        if direction == 1
            if candid == 0 || candx == itemx
                escort_finalcoords = (itemx, escorty)
            else 
                
                if items[candid].direction == 1 ||  gapx < gapy # moving in x
                    if iox > min(itemx, candx) 
                        escort_finalcoords = (max(1, candx+1), itemy) # IO on the right
                    else iox < min(itemx, candx)
                        escort_finalcoords = (max(1, candx-1), itemy) # IO on the left
                    end
                elseif items[candid].direction == 2 || gapy <= gapx # moving in y
                    escort_finalcoords = (candx, itemy)
                end
            end
        elseif direction == 2
            if candid == 0 || candy == itemy
                escort_finalcoords = (escortx, itemy)
            else 
                if items[candid].direction == 1 ||  gapx < gapy# moving in x
                    escort_finalcoords = (itemx, candy) 
                elseif items[candid].direction == 2 || gapy <= gapx# moving in y
                    escort_finalcoords = (itemx, max(1, candy-1))
                end
            end
        end
        if escort_finalcoords != ( escortx, escorty) # TODO add path tho io exists if in range
            if checkpathformovers
                itemscoords = generatefuturecoords_fincoord(items,  escorts, direction, escortid, escort_finalcoords, matrix, IO) 
                samecoords = direction == 2 ? 
                filter(x -> x[1] == itemx && x[2] >= min(itemy, escorty) && x[2] <= max(itemy, escorty), itemscoords) :
                filter(x -> x[2] == itemy && x[1] >= min(itemx, escortx) && x[1] <= max(itemx, escortx), itemscoords) # as moving this item might move another item closer to depot
                minDist = minimum([abs(IO[1] - coord[1]) + abs(IO[2] - coord[2]) for coord in samecoords])
                if minDist  > length(keys(items))+1 || # item far out from IO
                    path_to_io_exists_if(matrix, itemscoords, IO)   # check with A* if this movement would cause some stupid block
                    
                    push!(escorts[escortid].tabu, (escortx,escorty))
                    moved_any += move_escort!(matrix, items, escorts, escortid, escort_finalcoords)
                    updateblockmat_e!(blockmat, escortx, escorty, escort_finalcoords[1], escort_finalcoords[2])
                    escorts[escortid].lastmoved = iteration
    
                else# else we ban it for next iteration to simplify computation on assignment! 
                    if !haskey(escorts[escortid].banset, iteration+1)
                        escorts[escortid].banset[iteration+1] = [itemid]
                    else
                        push!(escorts[escortid].banset[iteration+1],itemid)
                    end
                    filter!(x -> x != escortid, moverescortids)
                    updateblockmat_e!(blockmat, escortx, escorty, escort_finalcoords[1], escort_finalcoords[2], val=0) # unblock the path 

                end
            else
                push!(escorts[escortid].tabu, (escortx,escorty))
                moved_any += move_escort!(matrix, items, escorts, escortid, escort_finalcoords)
                updateblockmat_e!(blockmat, escortx, escorty, escort_finalcoords[1], escort_finalcoords[2])
                escorts[escortid].lastmoved = iteration
            end

           
        end
    end
    
    # First, filter the customers:
    urgentcustomers = filter(customer_id ->  floor(Int,iteration+ (abs(iox -items[customer_id].coords[1]) + items[customer_id].coords[2]) * 1.5) >= items[customer_id].deadline,keys(items))
    
    
    
    # URGENCY POLICY UNDER CONSTRUCTION, will need to go into the find nearest item to escort function i guess due to complexity
    
   
    
    # NON MOVERS (nonassigned in earlier stage)
    nonmovers = setdiff(keys(escorts), moverescortids)
    # Sort non-movers according to the number of empty spaces in front of them in the y direction
    nonmovers = sort(collect(nonmovers), by = escortid -> begin
                esc_x, esc_y = escorts[escortid].coords
                empty_spaces = 0
                for y in esc_y-1:-1:1
                    if blockmat[esc_x, y] == 1 || matrix[esc_x, y] in keys(items) || matrix[esc_x, y] in keys(escorts)
                        break
                    end
                    empty_spaces += 1
                end
                distance_to_IO = -euclidean_distance((esc_x, esc_y), IO)  # negative for descending
                    return (distance_to_IO, empty_spaces)
                end, rev=false) 

    usedescorts =[]
    #Direct serve
    for escortid in nonmovers
        esc_x , esc_y = escorts[escortid].coords
        if blockmat[esc_x, esc_y] == 1
            continue
        end
        moved, escort_finalcoords = directserve_makespan!(iteration, matrix, items, escorts, escortid, urgentcustomers, blockmat, IO)
        if moved && escort_finalcoords != (esc_x,esc_y)
            push!(escorts[escortid].tabu, (esc_x,esc_y))
            push!(usedescorts,escortid)
            moved_any += move_escort!(matrix, items, escorts, escortid, escort_finalcoords)
            updateblockmat_e!(blockmat, esc_x, esc_y, escort_finalcoords[1], escort_finalcoords[2])
            escorts[escortid].lastmoved = iteration
        end
    end
    # Remove used escorts from nonmovers
    nonmovers = setdiff(nonmovers, usedescorts)
    #3-4 step serve
    usedescorts =[]
    if !isempty(urgentcustomers)
        urgentmatrixes = urgmats(items, escorts, blockmat, matrix, urgentcustomers, IO)
        for escortid in nonmovers
            esc_x , esc_y = escorts[escortid].coords
            if blockmat[esc_x, esc_y] == 1
                continue
            end
            moved, escort_finalcoords = urgserve!(iteration, matrix, items, escorts, escortid, urgentmatrixes, IO)
            if moved && escort_finalcoords != (esc_x,esc_y)
                push!(escorts[escortid].tabu, (esc_x,esc_y))
                push!(usedescorts,escortid)
                moved_any += move_escort!(matrix, items, escorts, escortid, escort_finalcoords)
                updateblockmat_e!(blockmat, esc_x, esc_y, escort_finalcoords[1], escort_finalcoords[2])
                updateurgmats_e!(urgentmatrixes, esc_x, esc_y, escort_finalcoords[1], escort_finalcoords[2])
                escorts[escortid].lastmoved = iteration
            end
        end
    end
    nonmovers = setdiff(nonmovers, usedescorts)
    for escortid in nonmovers
        esc_x , esc_y = escorts[escortid].coords
        if blockmat[esc_x, esc_y] == 1
            continue
        end
        moved, escort_finalcoords = freeroam!(iteration, matrix, items, escorts, escortid, blockmat, IO)
        if moved && escort_finalcoords != (esc_x,esc_y)
            push!(escorts[escortid].tabu, (esc_x,esc_y))
            moved_any += move_escort!(matrix, items, escorts, escortid, escort_finalcoords)
            updateblockmat_e!(blockmat, esc_x, esc_y, escort_finalcoords[1], escort_finalcoords[2])
            escorts[escortid].lastmoved = iteration
        end
    end
    #checksync(matrix, escorts, items)
    #print_matrix(matrix, blockmat)
    return (moved_any>0)
end
function moveescorts_flow!(iteration, matrix, items, escorts, moverescortids, blockmat, IO)
    # MOVERS FIRST
   
    iox, ioy = IO
    moved_any = 0
    serveditems = []
    checkpathformovers = false
    esccoords = [(escorts[key].coords[1], escorts[key].coords[2]) for key in moverescortids]
    closeescorts = findall([abs(IO[1] - coord[1]) + abs(IO[2] - coord[2]) <= (length(keys(items))) for coord in esccoords])
    if !isempty(closeescorts)
        checkpathformovers = true
    end
    for escortid in moverescortids
        itemsx = escorts[escortid].itemsx
        itemsy = escorts[escortid].itemsy
        if !isempty(itemsx)
            direction = 1
            itemid = itemsx[1]
        elseif !isempty(itemsy)
            direction = 2
            itemid = itemsy[1]
        else
            println("No item found, check item escort assignment")
            continue
        end
        if itemid in Iterators.flatten(values(escorts[escortid].banset)) || 
            futurecoords_closetoIO(items,  itemid, escorts, escortid, direction, IO) 
            checkpathformovers = true
        end
        item = items[itemid]
        if (item.direction != direction) 
            println("Item direction and escort direction do not match")
        end

        itemx, itemy = item.coords
        escortx, escorty = escorts[escortid].coords
        # Here onwards until the move_escort! function, we find the nearest item where this escort could be useful in next time step
        candid,candx,candy = find_nearest_item_toitem(matrix, items, itemid, blockmat, IO, direction)
        gapx, gapy = abs(candx - iox), abs(candy - ioy)
        if direction == 1
            if candid == 0 || candx == itemx
                escort_finalcoords = (itemx, escorty)
            else 
                
                if items[candid].direction == 1 ||  gapx < gapy # moving in x
                    if iox > min(itemx, candx) 
                        escort_finalcoords = (max(1, candx+1), itemy) # IO on the right
                    else iox < min(itemx, candx)
                        escort_finalcoords = (max(1, candx-1), itemy) # IO on the left
                    end
                elseif items[candid].direction == 2 || gapy <= gapx # moving in y
                    escort_finalcoords = (candx, itemy)
                end
            end
        elseif direction == 2
            if candid == 0 || candy == itemy
                escort_finalcoords = (escortx, itemy)
            else 
                if items[candid].direction == 1 ||  gapx < gapy# moving in x
                    escort_finalcoords = (itemx, candy) 
                elseif items[candid].direction == 2 || gapy <= gapx# moving in y
                    escort_finalcoords = (itemx, max(1, candy-1))
                end
            end
        end
        if escort_finalcoords != ( escortx, escorty) # TODO add path tho io exists if in range
            if checkpathformovers
                itemscoords = generatefuturecoords_fincoord(items,  escorts, direction, escortid, escort_finalcoords, matrix, IO) 
                samecoords = direction == 2 ? 
                filter(x -> x[1] == itemx && x[2] >= min(itemy, escorty) && x[2] <= max(itemy, escorty), itemscoords) :
                filter(x -> x[2] == itemy && x[1] >= min(itemx, escortx) && x[1] <= max(itemx, escortx), itemscoords) # as moving this item might move another item closer to depot
                minDist = minimum([abs(IO[1] - coord[1]) + abs(IO[2] - coord[2]) for coord in samecoords])
                if minDist  > length(keys(items))+1 || # item far out from IO
                    path_to_io_exists_if(matrix, itemscoords, IO)   # check with A* if this movement would cause some stupid block
                    
                    push!(escorts[escortid].tabu, (escortx,escorty))
                    moved_any += move_escort!(matrix, items, escorts, escortid, escort_finalcoords)
                    updateblockmat_e!(blockmat, escortx, escorty, escort_finalcoords[1], escort_finalcoords[2])
                    escorts[escortid].lastmoved = iteration
    
                else# else we ban it for next iteration to simplify computation on assignment! 
                    if !haskey(escorts[escortid].banset, iteration+1)
                        escorts[escortid].banset[iteration+1] = [itemid]
                    else
                        push!(escorts[escortid].banset[iteration+1],itemid)
                    end
                    filter!(x -> x != escortid, moverescortids)
                    updateblockmat_e!(blockmat, escortx, escorty, escort_finalcoords[1], escort_finalcoords[2], val=0) # unblock the path 

                end
            else
                push!(escorts[escortid].tabu, (escortx,escorty))
                moved_any += move_escort!(matrix, items, escorts, escortid, escort_finalcoords)
                updateblockmat_e!(blockmat, escortx, escorty, escort_finalcoords[1], escort_finalcoords[2])
                escorts[escortid].lastmoved = iteration
            end

           
        end
    end
        
    diagonal_size = sqrt(size(matrix, 1)^2 + size(matrix, 2)^2)
    # First, filter the customers:
    urgentcustomers = filter(customer_id -> begin
        item = items[customer_id]
        floor(Int, iteration + (abs(iox - item.coords[1]) + item.coords[2]) * 1.5) >= item.deadline ||
        (iteration - item.tes) + (abs(item.coords[1] - iox) + abs(item.coords[2] - ioy)) > diagonal_size
    end, keys(items))
    
    
    # URGENCY POLICY UNDER CONSTRUCTION, will need to go into the find nearest item to escort function i guess due to complexity
    
    
    
    # NON MOVERS (nonassigned in earlier stage)
    nonmovers = setdiff(keys(escorts), moverescortids)
    # Sort non-movers according to the number of empty spaces in front of them in the y direction
    nonmovers = sort(collect(nonmovers), by = escortid -> begin
            esc_x, esc_y = escorts[escortid].coords
            empty_spaces = 0
            for y in esc_y-1:-1:1
                if blockmat[esc_x, y] == 1 || matrix[esc_x, y] in keys(items) || matrix[esc_x, y] in keys(escorts)
                    break
                end
                empty_spaces += 1
            end
            distance_to_IO = -euclidean_distance((esc_x, esc_y), IO)  # negative for descending
                return (distance_to_IO, empty_spaces)
            end, rev=false)

    
    
    usedescorts =[]
    #Direct serve
    for escortid in nonmovers
        esc_x , esc_y = escorts[escortid].coords
        if blockmat[esc_x, esc_y] == 1
            continue
        end
        moved, escort_finalcoords = directserve_flow!(iteration, matrix, items, escorts, escortid, urgentcustomers, blockmat, IO)
        if moved && escort_finalcoords != (esc_x,esc_y)
            push!(escorts[escortid].tabu, (esc_x,esc_y))
            push!(usedescorts,escortid)
            moved_any +=move_escort!(matrix, items, escorts, escortid, escort_finalcoords)
            updateblockmat_e!(blockmat, esc_x, esc_y, escort_finalcoords[1], escort_finalcoords[2])
            escorts[escortid].lastmoved = iteration
        end
    end
    # Remove used escorts from nonmovers
    nonmovers = setdiff(nonmovers, usedescorts)
    #3-4 step serve
    usedescorts =[]
    if !isempty(urgentcustomers)
        urgentmatrixes = urgmats(items, escorts, blockmat, matrix, urgentcustomers, IO)
        for escortid in nonmovers
            esc_x , esc_y = escorts[escortid].coords
            if blockmat[esc_x, esc_y] == 1
                continue
            end
            moved, escort_finalcoords = urgserve!(iteration, matrix, items, escorts, escortid, urgentmatrixes, IO)
            if moved && escort_finalcoords != (esc_x,esc_y)
                push!(escorts[escortid].tabu, (esc_x,esc_y))
                push!(usedescorts,escortid)
                moved_any +=move_escort!(matrix, items, escorts, escortid, escort_finalcoords)
                updateblockmat_e!(blockmat, esc_x, esc_y, escort_finalcoords[1], escort_finalcoords[2])
                updateurgmats_e!(urgentmatrixes, esc_x, esc_y, escort_finalcoords[1], escort_finalcoords[2])
                escorts[escortid].lastmoved = iteration
            end
        end
    end
    nonmovers = setdiff(nonmovers, usedescorts)
    smart = zeros(Int, length(nonmovers))
    if length(nonmovers) > length(keys(items))
        gap = length(nonmovers) - length(keys(items))
        for i in 1:gap
            smart[i] = 1
        end
    end
    for (index,escortid) in enumerate(nonmovers)
        esc_x , esc_y = escorts[escortid].coords
        if blockmat[esc_x, esc_y] == 1
            continue
        end
        if smart[index] ==1 
            moved, escort_finalcoords = freeroam_dumb!(iteration, matrix, items, escorts, escortid, blockmat, IO)
        else
            moved, escort_finalcoords = freeroam!(iteration, matrix, items, escorts, escortid, blockmat, IO)
        end
        if moved && escort_finalcoords != (esc_x,esc_y)
            push!(escorts[escortid].tabu, (esc_x,esc_y))
            moved_any += move_escort!(matrix, items, escorts, escortid, escort_finalcoords)
            updateblockmat_e!(blockmat, esc_x, esc_y, escort_finalcoords[1], escort_finalcoords[2])
            escorts[escortid].lastmoved = iteration
        end
    end

    #checksync(matrix, escorts, items)
    print_matrix(matrix, blockmat)
    return (moved_any>0)
    #return matrix
end

"""
Multi-IO version of moveescorts_flow!
Uses global_escort_items structure instead of individual escort.itemsx/itemsy
Processes mover escorts using IO-specific information and blockmats
"""
function moveescorts_flow_multi_io!(iteration, matrix, items, escorts, io_blockmats, global_blockmat, 
                                     global_escort_items, all_ios, item_to_ios)
    # MOVERS FIRST - Process using global_escort_items structure
    # global_escort_items[escort_id] = [(io, itemsx, itemsy), ...]
    moverescortids = collect(keys(global_escort_items))
    moved_any = 0
    serveditems = []
    checkpathformovers = false
    
    for escortid in moverescortids
        if !haskey(global_escort_items, escortid)
            continue
        end
        
        assignments = global_escort_items[escortid]  # List of (io, itemsx, itemsy) tuples
        
        # Process each IO assignment for this escort
        for (target_io, itemsx, itemsy) in assignments
            # Determine which item and direction to serve
            itemid = ""
            direction = 0
            
            if !isempty(itemsx)
                direction = 1
                itemid = itemsx[1]
            elseif !isempty(itemsy)
                direction = 2
                itemid = itemsy[1]
            else
                continue  # No items for this assignment
            end
            
            if !haskey(items, itemid)
                continue
            end
            
            item = items[itemid]
            if item.direction != direction
                println("Item direction and escort direction do not match for multi-IO")
                continue
            end
            
            itemx, itemy = item.coords
            escortx, escorty = escorts[escortid].coords
            iox, ioy = target_io  # Use the specific target IO for this assignment
            
            # Check if escort is close to its target IO
            if abs(iox - escortx) + abs(ioy - escorty) <= length(keys(items)) + 1
                checkpathformovers = true
            end
            
            # Find nearest item to serve next (using target IO for this escort)
            candid, candx, candy = find_nearest_item_toitem(matrix, items, itemid, global_blockmat, target_io, direction)
            gapx, gapy = abs(candx - iox), abs(candy - ioy)
            
            escort_finalcoords = (escortx, escorty)  # Default: no movement
            
            if direction == 1  # x-movement
                if candid == 0 || candx == itemx
                    escort_finalcoords = (itemx, escorty)
                else
                    if items[candid].direction == 1 || gapx < gapy  # moving in x
                        if iox > min(itemx, candx)
                            escort_finalcoords = (max(1, candx + 1), itemy)  # IO on the right
                        elseif iox < min(itemx, candx)
                            escort_finalcoords = (max(1, candx - 1), itemy)  # IO on the left
                        end
                    elseif items[candid].direction == 2 || gapy <= gapx  # moving in y
                        escort_finalcoords = (candx, itemy)
                    end
                end
                
            elseif direction == 2  # y-movement
                if candid == 0 || candy == itemy
                    escort_finalcoords = (escortx, itemy)
                else
                    if items[candid].direction == 1 || gapx < gapy  # moving in x
                        escort_finalcoords = (itemx, candy)
                    elseif items[candid].direction == 2 || gapy <= gapx  # moving in y
                        escort_finalcoords = (itemx, max(1, candy - 1))
                    end
                end
            end
            
            # Validate movement
            if escort_finalcoords != (escortx, escorty)
                if checkpathformovers
                    # Use IO-specific blockmat for this assignment
                    
                    itemscoords = generatefuturecoords_fincoord(items, escorts, direction, escortid, escort_finalcoords, matrix, target_io)
                    samecoords = direction == 2 ?
                        filter(x -> x[1] == itemx && x[2] >= min(itemy, escorty) && x[2] <= max(itemy, escorty), itemscoords) :
                        filter(x -> x[2] == itemy && x[1] >= min(itemx, escortx) && x[1] <= max(itemx, escortx), itemscoords)
                    
                    if !isempty(samecoords)
                        minDist = minimum([abs(iox - coord[1]) + abs(ioy - coord[2]) for coord in samecoords])
                        
                        if minDist > length(keys(items)) + 1 || path_to_io_exists_if(matrix, itemscoords, target_io)
                            # Safe to move
                            push!(escorts[escortid].tabu, (escortx, escorty))
                            moved_any += move_escort!(matrix, items, escorts, escortid, escort_finalcoords)
                            updateblockmat_e!(global_blockmat, escortx, escorty, escort_finalcoords[1], escort_finalcoords[2])
                            escorts[escortid].lastmoved = iteration
                        else
                            # Ban this escort from moving this item next iteration
                            if !haskey(escorts[escortid].banset, iteration + 1)
                                escorts[escortid].banset[iteration + 1] = [itemid]
                            else
                                push!(escorts[escortid].banset[iteration + 1], itemid)
                            end
                            updateblockmat_e!(global_blockmat, escortx, escorty, escort_finalcoords[1], escort_finalcoords[2], val=0)
                        end
                    end
                else
                    # No path check needed, move directly
                    push!(escorts[escortid].tabu, (escortx, escorty))
                    moved_any += move_escort!(matrix, items, escorts, escortid, escort_finalcoords)
                    
                    updateblockmat_e!(global_blockmat, escortx, escorty, escort_finalcoords[1], escort_finalcoords[2])
                    escorts[escortid].lastmoved = iteration
                end
            end
        end
    end
    
# ── NON-MOVERS ──────────────────────────────────────────────────────────
    diagonal_size = sqrt(size(matrix, 1)^2 + size(matrix, 2)^2)

    # Urgency: each item is checked against its own assigned IO (closest one if multiple)
    urgentcustomers = filter(customer_id -> begin
        item = items[customer_id]
        assigned = get(item_to_ios, customer_id, all_ios)
        iox, ioy = argmin(io -> abs(io[1] - item.coords[1]) + abs(io[2] - item.coords[2]), assigned)
        floor(Int, iteration + (abs(iox - item.coords[1]) + item.coords[2]) * 1.5) >= item.deadline ||
        (iteration - item.tes) + (abs(item.coords[1] - iox) + abs(item.coords[2] - ioy)) > diagonal_size
    end, keys(items))

    nonmovers = setdiff(keys(escorts), moverescortids)

    # Sort: escorts farther from all IOs go first (they need to reposition more urgently),
    # break ties by empty space ahead in y
    nonmovers = sort(collect(nonmovers), by = escortid -> begin
        esc_x, esc_y = escorts[escortid].coords
        empty_spaces = 0
        for y in esc_y-1:-1:1
            if global_blockmat[esc_x, y] == 1 || matrix[esc_x, y] in keys(items) || matrix[esc_x, y] in keys(escorts)
                break
            end
            empty_spaces += 1
        end
        dist_to_nearest_io = minimum(io -> abs(io[1] - esc_x) + abs(io[2] - esc_y), all_ios)
        return (-dist_to_nearest_io, empty_spaces)
    end, rev=false)

    usedescorts = []
    for escortid in nonmovers
        esc_x, esc_y = escorts[escortid].coords
        if global_blockmat[esc_x, esc_y] == 1
            continue
        end
        moved, escort_finalcoords = directserve_flow_multi_io!(iteration, matrix, items, escorts,
                                                                escortid, urgentcustomers,
                                                                global_blockmat, item_to_ios, all_ios)
                            
        if moved && escort_finalcoords != (esc_x, esc_y)
            #println("iter $iteration: moved $escortid from ($esc_x, $esc_y) to $escort_finalcoords")
            push!(escorts[escortid].tabu, (esc_x, esc_y))
            push!(usedescorts, escortid)
            moved_any += move_escort!(matrix, items, escorts, escortid, escort_finalcoords)
            updateblockmat_e!(global_blockmat, esc_x, esc_y, escort_finalcoords[1], escort_finalcoords[2])
            escorts[escortid].lastmoved = iteration
        end
    end
    nonmovers = setdiff(nonmovers, usedescorts)
    usedescorts = []
    if !isempty(urgentcustomers)
        # Build urgmats using each item's own assigned IO, not a single global IO
        urgentmatrixes = urgmats_multi_io(items, escorts, global_blockmat, matrix, 
                                           urgentcustomers, item_to_ios, all_ios)
        for escortid in nonmovers
            esc_x, esc_y = escorts[escortid].coords
            if global_blockmat[esc_x, esc_y] == 1
                continue
            end
            moved, escort_finalcoords = urgserve_multi_io!(iteration, matrix, items, escorts, 
                                                            escortid, urgentmatrixes, 
                                                            item_to_ios, all_ios)
            if moved && escort_finalcoords != (esc_x, esc_y)
                #println("iter $iteration: moved $escortid from ($esc_x, $esc_y) to ($escort_finalcoords)")
                push!(escorts[escortid].tabu, (esc_x, esc_y))
                push!(usedescorts, escortid)
                moved_any += move_escort!(matrix, items, escorts, escortid, escort_finalcoords)
                updateblockmat_e!(global_blockmat, esc_x, esc_y, escort_finalcoords[1], escort_finalcoords[2])
                updateurgmats_e!(urgentmatrixes, esc_x, esc_y, escort_finalcoords[1], escort_finalcoords[2])
                escorts[escortid].lastmoved = iteration
            end
        end
    end
    nonmovers = setdiff(nonmovers, usedescorts)

  # ── BALANCING + FREEROAM ─────────────────────────────────────────────────
    # Count escorts "belonging" to each IO: nearest IO wins
    io_escort_counts = Dict(io => 0 for io in all_ios)
    io_escort_members = Dict(io => [] for io in all_ios)
    for escortid in nonmovers
        esc_x, esc_y = escorts[escortid].coords
        nearest_io = argmin(io -> abs(io[1] - esc_x) + abs(io[2] - esc_y), all_ios)
        io_escort_counts[nearest_io] += 1
        push!(io_escort_members[nearest_io], escortid)
    end

    # How many escorts should each IO ideally have
    target_per_io = length(nonmovers) / length(all_ios)

    # Build a list of (escortid, target_io) for each nonmover:
    # - escorts in overpopulated zones get assigned to the nearest underpopulated IO
    # - all others stay in their current zone
    escort_target_ios = Dict{eltype(nonmovers), Any}()

    # Sort IOs: overpopulated ones "donate" escorts to underpopulated ones
    sorted_ios_by_excess = sort(all_ios, by = io -> -io_escort_counts[io])  # most populated first
    
    # Build a transfer list: (escortid, destination_io)
    # For each overpopulated IO, take the escorts farthest from it (most "transferable")
    # and assign them to the most underpopulated IO
    for escortid in nonmovers
        esc_x, esc_y = escorts[escortid].coords
        nearest_io = argmin(io -> abs(io[1] - esc_x) + abs(io[2] - esc_y), all_ios)
        escort_target_ios[escortid] = nearest_io  # default: stay in own zone
    end

    # Transfer excess escorts from overpopulated IOs to underpopulated IOs
    for io in sorted_ios_by_excess
        remaining_excess = io_escort_counts[io] - ceil(Int, target_per_io)
        if remaining_excess <= 0; continue; end

        # Only consider escorts still assigned to this IO (not already transferred away)
        not_yet_transferred = filter(eid -> escort_target_ios[eid] == io, io_escort_members[io])

        # Sort by closeness to target — but target may change per escort, so sort by
        # distance to the centroid of all underpopulated IOs as a proxy
        underpopulated = filter(io2 -> io_escort_counts[io2] < floor(Int, target_per_io), all_ios)
        if isempty(underpopulated); continue; end
        centroid_x = mean(io2[1] for io2 in underpopulated)
        centroid_y = mean(io2[2] for io2 in underpopulated)
        transferable = sort(not_yet_transferred,
            by = eid -> abs(centroid_x - escorts[eid].coords[1]) + abs(centroid_y - escorts[eid].coords[2]))

        for eid in transferable
            if remaining_excess <= 0; break; end
            # Recompute the most underpopulated IO for each individual escort transfer
            target_io = argmin(io2 -> io_escort_counts[io2], all_ios)
            if io_escort_counts[target_io] >= ceil(Int, target_per_io); break; end

            escort_target_ios[eid] = target_io
            io_escort_counts[io] -= 1
            io_escort_counts[target_io] += 1
            remaining_excess -= 1
        end
    end

    # Count items per IO zone (to decide smart vs dumb within each zone)
    io_item_counts = Dict(io => count(
        id -> argmin(pio -> abs(pio[1] - items[id].coords[1]) + abs(pio[2] - items[id].coords[2]), all_ios) == io,
        keys(items)) for io in all_ios)

    # Freeroam: each escort uses its assigned target_io as the IO argument
    for escortid in nonmovers
        esc_x, esc_y = escorts[escortid].coords
        if global_blockmat[esc_x, esc_y] == 1; continue; end

        target_io = escort_target_ios[escortid]
        escorts_in_zone = io_escort_counts[target_io]
        items_in_zone   = io_item_counts[target_io]

        # Use dumb if this zone has more escorts than items (escort is "excess" there)
        if escorts_in_zone > items_in_zone
            moved, escort_finalcoords = freeroam_dumb!(iteration, matrix, items, escorts,
                                                        escortid, global_blockmat, target_io)
        else
            moved, escort_finalcoords = freeroam!(iteration, matrix, items, escorts,
                                                   escortid, global_blockmat, target_io)
        end

        if moved && escort_finalcoords != (esc_x, esc_y)
            push!(escorts[escortid].tabu, (esc_x, esc_y))
            moved_any += move_escort!(matrix, items, escorts, escortid, escort_finalcoords)
            updateblockmat_e!(global_blockmat, esc_x, esc_y, escort_finalcoords[1], escort_finalcoords[2])
            escorts[escortid].lastmoved = iteration
        end
    end

    
    return (moved_any > 0)
end


function find_nearest_item_toitem(matrix, items, itemid, blockmat, IO, direction)
    item = items[itemid]
    itemx, itemy = item.coords
    nearestitemx = size(matrix, 1)+1
    nearestitemy = size(matrix, 2)+1
    nearestitemid = 0
    for item_id in keys(items)
        if item_id == itemid
            continue
        end
        otheritem = items[item_id]
        otherx, othery = otheritem.coords
        if direction == 1
       
            if otherx == itemx
                if otheritem.direction == 1 || # moving together
                    (otheritem.direction ==2 && abs(othery - IO[2]) <= 1) # moving to the front of this item makes no sense
                    continue
                else
                    return item_id, otherx, othery# great candidate 
                end
            elseif (IO[1] < itemx && otherx > itemx) || (IO[1] > itemx && otherx < itemx) # depends on io
                xstart = min(itemx, otherx)
                xend = max(itemx, otherx)
                path_blocked = false
                for x in xstart:xend
                    if blockmat[x, itemy] == 1 || matrix[x, itemy] == item_id
                        path_blocked = true
                        break
                    end
                end
                if !path_blocked && 
                    ((IO[1] < itemx && otherx > itemx && otherx < nearestitemx) || # order: IO, item, other
                     (IO[1] > itemx && otherx < itemx && otherx > nearestitemx)) # order: other, item, IO
                    nearestitemid = item_id
                    nearestitemx = otherx
                end
            end
        elseif direction == 2
            if othery == itemy
                if otheritem.direction == 2 || # moving together
                    (otheritem.direction ==1 && abs(otherx - IO[1]) <= 1) ||  # moving to the front of this item makes no sense
                    (otherx - IO[1]) == 0  || # other item at depot
                    !(IO[1] < itemx && otherx > itemx) || (IO[1] > itemx && otherx < itemx) # this item doesn help other item
                    continue
                else
                    return item_id, otherx, othery # great candidate 
                end
            elseif othery > itemy
                ystart = min(itemy, othery)
                yend = max(itemy, othery)
                path_blocked = false
                for y in ystart:yend
                    if blockmat[itemx, y] == 1 || matrix[itemx, y] == item_id
                        path_blocked = true
                        break
                    end
                end
                if !path_blocked && othery < nearestitemy
                    nearestitemid = item_id
                    nearestitemy = othery
                end
            end
        end
    end
    return nearestitemid, nearestitemx, nearestitemy
end
"""
in the effort to moveescorts! bit misleading name as if no item is found we try to come near to IO as this will allow us to move better in next time step
"""
function find_nearest_item_toescort!(iteration, matrix, items, escorts, escortid, urgmats, blockmat, IO)
    #if ((iteration == 2 || iteration ==3 ) && escortid == "E1")
     #   println("here")
    #end
    strategy = IO[1] == 1 ? 1 : IO[1] == size(matrix, 1) ? 3 : 2 # 1: left, 2: middle, 3: right
    allkeys = setdiff(union(keys(escorts), keys(items)), [escortid])
    thisescort = escorts[escortid]
    esc_x, esc_y = thisescort.coords
    avgesc_x = length(keys(escorts)) > 1 ? mean([escorts[esc].coords[1] for esc in keys(escorts) if esc != escortid]) : esc_x
    if strategy ==2 && avgesc_x<IO[1]
        strategy = 3 # if most escorts are on the left we prefer staying as right as possible while moving left
    elseif strategy ==2 && avgesc_x>IO[1]
        strategy = 1# if most escorts are on the right we prefer staying as left as possible while moving right
    end
    moveitnow = false
    if escorts[escortid].lastmoved <= iteration-2 
        moveitnow = true
    end
    # Get coordinates of escorts that have not moved this iteration and are not this escort
    other_escorts_coords = [(escorts[esc].coords[1], escorts[esc].coords[2]) for esc in keys(escorts) if esc != escortid]
   
    distx, disty = size(matrix, 1)+1, size(matrix, 2)+1
    closestx , closesty = 0 , 0 
    finx , finy = esc_x, esc_y 
    sortedkeys = sort_keys_by_distance(items, IO, true) # sort by distance to IO
    # CAN WE SERVE A CUSTOMER IN NEXT ITERATION? 
    for itemid in sortedkeys # try serve item in next iteration 
        itemx, itemy = items[itemid].coords
        if ((IO[1] < itemx && esc_x < itemx) ||  # check if we can move escort to item path on X
            (IO[1] > itemx && esc_x > itemx)) && itemx != esc_x
            ygap = abs(esc_y - itemy)
            path_blocked = false ; skipItem = false
            for (ox, oy) in other_escorts_coords # if there exists an escort ready to serve this item we dont block it
                if oy == itemy
                    if (IO[1] > itemx && esc_x > itemx) &&  # item going right we want to avoid itemx-ox-escx
                        (itemx < esc_x && ox < esc_x && itemx < ox) # esc_x < ox && itemx <ox || itemx < esc_x && ox < esc_x && itemx < ox # If going left, check if there's an escort further left
                        skipItem = true
                        break
                    elseif (IO[1] < itemx && esc_x < itemx) &&  # item goes left. we want to avoid escx-ox-itemx
                        (itemx > esc_x && ox > esc_x && itemx> ox )# esc_x > ox && itemx >ox || itemx> esc_x && ox > esc_x && itemx > ox  # If going right, check if there's an escort further right
                        skipItem = true
                        break
                    end
                end
            end
            if skipItem
                continue
            end
            if ygap <= disty && ygap > 0 # if gap is 0 we could have served, there must be a reason we didnt
                ymin = min(esc_y, itemy)
                ymax = max(esc_y, itemy)

               
                for y in ymin:ymax
                    if blockmat[esc_x, y] == 1 || matrix[esc_x, y] in keys(items)
                        path_blocked = true
                        break
                    end
                end
                if IO[1] > min(itemx, esc_x) && IO[1] < max(itemx, esc_x) # can serve but effects badly 
                    for x in min(esc_x, IO[1]):max(esc_x, IO[1])
                        if matrix[x, itemy] in keys(items) 
                            path_blocked = true
                            break
                        end
                    end
                end
            else 
                continue
            end
            if !path_blocked || (ygap == 0 && ((esc_x < itemx && IO[1] < itemx) || (esc_x > itemx && IO[1] > itemx)))
                itemscoords = generatefuturecoords(items, escorts, 1, escortid, itemid, matrix, IO)
                sameycoords = filter(x -> x[2] == itemy && x[1] >= min(itemx, esc_x) && x[1] <= max(itemx, esc_x), itemscoords) # as moving this item might move another item closer to depot
                minDist = minimum([abs(IO[1] - coord[1]) + abs(IO[2] - coord[2]) for coord in sameycoords])
                if minDist  > length(keys(items))+1 || # item far out from IO
                    path_to_io_exists_if(matrix, itemscoords, IO)   # check with A* if this movement would cause some stupid block
                    disty = ygap 
                    closesty = itemid
                else# else we ban it for next iteration to simplify computation on assignment! 
                    if !haskey(thisescort.banset, iteration+1)
                        thisescort.banset[iteration+1] = [itemid]
                    else
                        push!(thisescort.banset[iteration+1],itemid)
                    end
                end
            end
        end
        if esc_y < itemy # check if we can move escort to item path on Y 
            xgap = abs(esc_x - itemx)
            path_blocked = false ; skipItem = false
            for (ox, oy) in other_escorts_coords
                if ox == itemx && oy < itemy
                    skipItem = true
                    break
                end
            end
            if skipItem
                continue
            end
            if xgap <= distx && xgap > 0
                xmin = min(esc_x, itemx)
                xmax = max(esc_x, itemx)
                for x in xmin:xmax
                    if blockmat[x, esc_y] == 1 || matrix[x, esc_y] in keys(items)
                        path_blocked = true
                        break
                    end
                end
            else
                continue
            end
            if !path_blocked || xgap==0 # if gap is 0 we could have served, there must be a reason we didnt 
                itemscoords = generatefuturecoords(items, escorts,2, escortid, itemid, matrix, IO)
                samexcoords = filter(x -> x[1] == itemx && x[2] >= min(itemy, esc_y) && x[2] <= max(itemy, esc_y), itemscoords) # as moving this item might move another item closer to depot
                minDist = minimum([abs(IO[1] - coord[1]) + abs(IO[2] - coord[2]) for coord in samexcoords])
                if  minDist > length(keys(items))+1 ||
                    path_to_io_exists_if(matrix, itemscoords, IO) # check with A* if this movement would cause some stupid block
                    distx = xgap
                    closestx = itemid
                else 
                    if !haskey(thisescort.banset, iteration+1)
                        thisescort.banset[iteration+1] = [itemid]
                    else
                        push!(thisescort.banset[iteration+1],itemid)
                    end
                end
            end
        end
    end
    # If we could serve an item we move to there
    if distx < disty  && closestx !=0 # go in front of item in Y direction
        if haskey(urgmats, closestx)
            delete!(urgmats, closestx)
        end
        candx , candy = items[closestx].coords
        return (candx, esc_y)
    end
    if distx >= disty && closesty !=0 # go in path of item in X direction
        if haskey(urgmats, closesty)
            delete!(urgmats, closesty)
        end
        candx , candy = items[closesty].coords
        return (esc_x, candy)
    end
    # MUST WE SERVE A CUSTOMER SOON?
    if !isempty(keys(urgmats))
        urgentassignmentdict = Dict{String, Tuple{Int, Int, Int}}() # itemid, steps, x, y
        for urgitem in keys(urgmats)
            urgmat= urgmats[urgitem]
            urgx,urgy = items[urgitem].coords
            skip_urgitem = false
            for escid in keys(escorts)
                if escid == escortid
                    continue
                end
                otherescx, otherescy = escorts[escid].coords
                if urgmat[otherescx, otherescy] == 2
                    skip_urgitem = true
                    break
                end
            end
            if skip_urgitem
                continue
            end                 
            foundy = false; foundx = false; completedy = false; completedx = false; distance = Inf; dir = urgx > IO[1] ? -1 : 1
            candidy = 0; xin = deepcopy(esc_x); yin = deepcopy(esc_y); candidx = 0; gapy = Inf ; gapx = Inf
            if urgmat[esc_x, esc_y] == 2
                #println("Escort is 2 steps away from urgent item, should have served in previous step")
                continue 
            end
            while !completedy 
                if ( esc_x < urgx && IO[1] < urgx) ||
                    (esc_x > urgx && IO[1] > urgx)
                    completedy = true
                    break
                end
                if  (esc_y>=urgy)
                    for y in esc_y-1:-1:1
                        if urgmat[xin, y] == 2
                            candidy = y
                            gapy = abs(esc_y-y )
                            foundy = true
                            break
                        elseif urgmat[xin, y] == 1
                            foundy = false
                        end
                    end
                    if foundy || ( xin + dir < 1 ||
                        xin + dir > size(matrix, 1) ||
                            (dir == -1 && xin + dir <= urgx) ||
                            (dir == 1 && xin + dir > urgx))
                        completedy = true  # we cannot move anymore, if we havent found a 2 we cannot move
                    else
                        xin += dir
                    end
                elseif (esc_y < urgy-1) 
                    for y in esc_y+1:urgy-1
                        if urgmat[xin, y] == 2
                            candidy = y
                            gapy = abs(esc_y-y )
                            foundy = true
                            break
                        elseif urgmat[xin, y] == 1
                            foundy = false
                        end
                    end
                    if foundy || ( xin + dir < 1 ||
                        xin + dir > size(matrix, 1) ||
                            (dir == -1 && xin + dir <= urgx) ||
                            (dir == 1 && xin + dir > urgx))
                        completedy = true  # we cannot move anymore, if we havent found a 2 we cannot move
                    else
                        xin += dir
                    end
        
                else
                    completedy = true
                end
                
            end
            while !completedx
                if esc_y<=urgy
                    completedx = true
                    break
                end
                if esc_x>=urgx
                    if dir == -1 # escort on the right side or urg: IO-urg-esc
                        for x in esc_x-1:-1:IO[1]
                            if urgmat[x, esc_y] == 2
                                candidx = x
                                gapx = abs(esc_x - x)
                                foundx = true
                                break
                            elseif urgmat[x, esc_y] == 1
                                foundx = false
                                break
                            end
                        end
                    else # escort on the right side of urg : urg-esc-IO or urg-IO-esc
                        for x in esc_x-1:-1:urgx
                            if urgmat[x, esc_y] == 2
                                candidx = x
                                gapx = abs(esc_x - x)
                                foundx = true
                                break
                            elseif urgmat[x, esc_y] == 1
                                foundx = false
                                break
                            end
                        end
                    end
                    if foundx || yin -1 <= urgy
                        completedx = true # we cannot move anymore, if we havent found a 2 we cannot move
                    else
                        yin -= 1
                    end
                elseif esc_x<urgx-1
                    if dir ==1# escort left of item, item left of IO
                        for x in esc_x+1:IO[1]
                            if urgmat[x, esc_y] == 2
                                candidx = x
                                gapx = abs(esc_x - x)
                                foundx = true
                                break
                            elseif urgmat[x, esc_y] == 1
                                foundx = false
                            end
                        end
                    else # escort left of item, item right of IO
                        for x in esc_x+1:urgx-1
                            if urgmat[x, esc_y] == 2
                                candidx = x
                                gapx = abs(esc_x - x)
                                foundx = true
                                break
                            elseif urgmat[x, esc_y] == 1
                                foundx = false
                            end
                        end
                        for x in esc_x-1:-1:1
                            if urgmat[x, esc_y] == 2
                                gapotherx = abs(esc_x - x)
                                if gapotherx < gapx
                                    gapx = gapotherx
                                    candidx = x
                                end                                
                                foundx = true
                                break
                            elseif urgmat[x, esc_y] == 1
                                foundx = false
                            end
                        end
                    end
                    if foundx || yin -1 <= urgy
                        completedx = true # we cannot move anymore, if we havent found a 2 we cannot move
                    else
                        yin -= 1
                    end
                else
                    completedx = true
                end
            end
            if foundy && foundx
                onx = xin == esc_x ? 1 : 0
                ony = yin == esc_y ? 1 : 0
                if onx + ony == 2 # 3 step both fine
                    if gapx < gapy
                        candidx = esc_x 
                    else 
                        candidy = esc_y
                    end
                elseif onx == 1  # 3 step go down with escort
                    candidy = esc_y; distance = gapx
                elseif ony == 1 # 3 step go left in with escort (if escort right out of item)
                    candidx = esc_x;  distance = gapy
                else # 4 step 
                    gapx = gapx + 5*(abs(esc_y - yin))
                    gapy = gapy + 5*(abs(esc_x- xin))
                    if gapx < gapy
                        candidy = yin; candidx = esc_x ; distance = gapx
                    else
                        candidx = xin ; candidy = esc_y ; distance = gapy
                    end
                end
            elseif foundy
                onx = xin == esc_x ? 1 : 0
                if onx ==1 
                    candidx = esc_x ; distance = gapy
                else # 4 Step
                    gapy = gapy + 5*(abs(esc_x- xin))
                    candidx = xin ; candidy = esc_y ; distance = gapy
                end
            elseif foundx 
                ony = yin == esc_y ? 1 : 0
                if ony ==1 
                    candidy = yin; distance = gapx
                else # 4 Step
                    gapx = gapx + 5*(abs(esc_y - yin))
                    candidy = yin; candidx = esc_x;  distance = gapx # go down 
                end
            end
            # we check how many steps to get to a 2 in the matrix from the position and how far
            if distance != Inf && candidx != 0 && candidy!=0 && !(matrix[candidx, candidy] in keys(escorts))
                urgentassignmentdict[urgitem] =(distance , candidx,candidy) 
            end
        end

        if !isempty(urgentassignmentdict)
            min_distance = Inf
            min_key = ""
            min_tuple = ()
            for (key, value) in urgentassignmentdict
                if value[1] < min_distance
                    newx, newy = value[2], value[3]
                    skipthis = false
                    if esc_x == newx
                        ystart, yend = min(esc_y, newy), max(esc_y, newy)
                        for y in ystart:yend
                            if matrix[esc_x, y] in allkeys
                                skipthis = true
                                break
                            end
                        end
                    elseif esc_y == newy
                        xstart, xend = min(esc_x, newx), max(esc_x, newx)
                        for x in xstart:xend
                            if matrix[x, esc_y] in allkeys
                                skipthis = true
                                break
                            end
                        end
                    end
                    if skipthis
                        continue
                    elseif !((newx, newy) in escorts[escortid].tabu)
                        min_distance = value[1]
                        min_key = key
                        min_tuple = value
                    end
                end
            end 
            
            if  !isempty(min_tuple)
                delete!(urgmats, min_key)
                otheritems = setdiff(keys(urgentassignmentdict), [min_key])
                if !haskey(thisescort.banset, iteration+1)
                    thisescort.banset[iteration+1] = Vector{String}(collect(otheritems))
                else
                    append!(thisescort.banset[iteration+1], otheritems)
                end
                #println("$iteration :$escortid-> $min_key movement decided by urgency policy")
                return (min_tuple[2], min_tuple[3]) # we also need some sort of commitment. using the banset I assume TODO 
            end
        end 
    end
    # FREE ROAM; GO SOMEWHERE ELSE/FREE IF POSSIBLE
    if closestx ==0  && closesty == 0 # Most complex part of this entire algorithm, even if A*fromIO said no dont do it now we do it if we are blocked anyways
        worked, asternmat = outwards_astar_with_dirchange(matrix, IO, blockmat,escortid,escorts,items)
        if esc_x == IO[1] && esc_y == IO[2]
            return (esc_x, esc_y) # best place it could be 
        elseif esc_x == IO[1] # down, outwards, 
            maxmove_y = checkasternmat(blockmat, matrix, -2, escortid, strategy, escorts, items,IO, asternmat)
            if (maxmove_y == esc_y) || matrix[esc_x, maxmove_y ] in keys(escorts) || (esc_x, maxmove_y) in thisescort.tabu #cannot move down enough , move out of the way right or left 
                avg_x = mean([items[item].coords[1] for item in keys(items)]) # where are the items ? 
                diresc= avg_x <= IO[1] ? 1 : -1 # if items are left we go right, vice versa
                for _ in 1:2 # Try both directions if the first choice fails
                    if diresc == 1 || IO[1] ==1 # chose right
                        maxmove = size(matrix, 1)
                        maxmove = checkmatrixforblock!(blockmat, matrix, diresc, escortid, strategy, iteration, escorts, items, IO)
                        if (maxmove > esc_x && !(matrix[maxmove, esc_y] in keys(escorts)))&& !((maxmove, esc_y) in thisescort.tabu) # can move right
                            return (maxmove, esc_y)
                        end
                    elseif diresc == -1 || IO[1] == size(matrix,1)# chose left
                        maxmove = 1
                        maxmove = checkmatrixforblock!(blockmat, matrix, diresc, escortid, strategy, iteration, escorts, items,IO)
                        if (maxmove < esc_x && !(matrix[maxmove, esc_y] in keys(escorts)))&& !((maxmove, esc_y) in thisescort.tabu) # can move left
                            return (maxmove, esc_y)
                        end
                    end
                    diresc = -diresc # Switch direction
                end 
                if moveitnow # side is also blocked. so now we couldnt move down or sideways
                    minup = checkmatrixforblock!(blockmat, matrix, 2, escortid, strategy, iteration, escorts, items,IO)
                    if minup > esc_y
                        return (esc_x, minup)
                    end
                end

            else
                return (esc_x, maxmove_y)
            end
        elseif esc_y == IO[2] # go in X direction towards IO , if blocked go up, if must move go outwards 
            if esc_x < IO[1] # io on the right
                maxmove_x = checkasternmat( blockmat, matrix, 1, escortid, strategy, escorts, items,IO, asternmat)
                if maxmove_x == esc_x || matrix[maxmove_x, esc_y] in keys(escorts) || (maxmove_x, esc_y) in thisescort.tabu 
                    minup = asternmat[esc_x,esc_y+1] != Inf ? checkasternmat(blockmat, matrix, 2, escortid, strategy, escorts, items,IO, asternmat) :
                        checkmatrixforblock!(blockmat, matrix, 2, escortid, strategy, iteration, escorts, items,IO)
                    if minup > esc_y
                        return (esc_x, minup)
                    elseif moveitnow 
                        maxmove_x = checkasternmat( blockmat, matrix, -1, escortid, strategy, escorts, items,IO, asternmat)
                        if maxmove_x == esc_x || matrix[maxmove_x, esc_y] in keys(escorts) || (maxmove_x, esc_y) in thisescort.tabu 
                            return (maxmove_x, esc_y)
                        end
                    end
                end                
            else # io on the left
                maxmove_x = maxmove_x = checkasternmat( blockmat, matrix, -1, escortid, strategy, escorts, items,IO, asternmat)
                if maxmove_x == esc_x || matrix[maxmove_x, esc_y] in keys(escorts) || (maxmove_x, esc_y) in thisescort.tabu 
                    minup = asternmat[esc_x,esc_y+1] != Inf ? checkasternmat(blockmat, matrix, 2, escortid, strategy, escorts, items,IO, asternmat) :
                        checkmatrixforblock!(blockmat, matrix, 2, escortid, strategy, iteration, escorts, items,IO)
                    if minup > esc_y
                        return (esc_x, minup)
                    elseif moveitnow 
                        maxmove_x = checkasternmat( blockmat, matrix, 1, escortid, strategy, escorts, items,IO, asternmat)
                        if maxmove_x == esc_x || matrix[maxmove_x, esc_y] in keys(escorts) || (maxmove_x, esc_y) in thisescort.tabu 
                            return (maxmove_x, esc_y)
                        end
                    end
                end     
            end  
            return (maxmove_x, esc_y)
        else # not at IO coords # down, inwards, upwards, outwards
            avg_x = mean([items[item].coords[1] for item in keys(items)])
            dirx= avg_x <= IO[1] ? 1 : -1 # try go to the opposite direction of the items to be able to serve them
            iodir = dirx
            maxmove_y = checkasternmat(blockmat, matrix, -2, escortid, strategy, escorts, items,IO, asternmat)#checkmatrixforblock!(blockmat, matrix, 1, -2, escortid, strategy, iteration, escorts, items,IO)
            if (maxmove_y == esc_y) || matrix[esc_x, maxmove_y ] in keys(escorts) || (esc_x, maxmove_y) in thisescort.tabu# cannot move down enough , move out of the way right or left 
                for _ in 1:2 
                    if dirx == 1 # chose right
                        maxmove = iodir == dirx ?  # if asternmat can be used we use it
                                checkasternmat( blockmat, matrix, dirx, escortid, strategy, escorts, items,IO, asternmat) :
                                checkmatrixforblock!(blockmat, matrix, dirx, escortid, strategy, iteration, escorts, items,IO)
                        if maxmove > esc_x && !(matrix[maxmove, esc_y] in keys(escorts)) && !((maxmove, esc_y) in thisescort.tabu) # can move right
                            return (maxmove, esc_y)
                        end
                    elseif dirx == -1 # chose left
                        maxmove = iodir == dirx ? 
                                checkasternmat( blockmat, matrix, dirx, escortid, strategy, escorts, items,IO, asternmat) :
                                checkmatrixforblock!(blockmat, matrix, dirx, escortid, strategy, iteration, escorts, items,IO)
                        if (maxmove < esc_x && !(matrix[maxmove, esc_y] in keys(escorts))) && !((maxmove, esc_y) in thisescort.tabu) # can move left
                            return (maxmove, esc_y)
                        end
                    end
                    dirx = -dirx
                end
            else # can go down
                return (esc_x, maxmove_y)
            end
            if moveitnow # must move so we try up
                minup = checkmatrixforblock!(blockmat, matrix, 2, escortid, strategy, iteration, escorts, items,IO)
                if minup > esc_y
                    return (esc_x, minup)
                end
            end
            
        end
    end
    return (finx, finy) # cannot move
end
function find_nearest_item_toescort_flow!(iteration, matrix, items, escorts, escortid, urgmats, blockmat, IO)
    strategy = IO[1] == 1 ? 1 : IO[1] == size(matrix, 1) ? 3 : 2 # 1: left, 2: middle, 3: right
    allkeys = setdiff(union(keys(escorts), keys(items)), [escortid])
    thisescort = escorts[escortid]
    esc_x, esc_y = thisescort.coords
    avgesc_x = length(keys(escorts)) > 1 ? mean([escorts[esc].coords[1] for esc in keys(escorts) if esc != escortid]) : esc_x
    if strategy ==2 && avgesc_x<IO[1]
        strategy = 3 # if most escorts are on the left we prefer staying as right as possible while moving left
    elseif strategy ==2 && avgesc_x>IO[1]
        strategy = 1# if most escorts are on the right we prefer staying as left as possible while moving right
    end
    moveitnow = false
    if escorts[escortid].lastmoved <= iteration-2 
        moveitnow = true
    end
    # Get coordinates of escorts that have not moved this iteration and are not this escort
    other_escorts_coords = [(escorts[esc].coords[1], escorts[esc].coords[2]) for esc in keys(escorts) if esc != escortid]
   
    distx, disty = size(matrix, 1)+1, size(matrix, 2)+1
    closestx , closesty = 0 , 0 
    finx , finy = esc_x, esc_y 
    sortedkeys = sort_keys_by_distance(items, IO, true) # sort by distance to IO

    # Sort urgent customers by their urgency and distance to IO
    sorted_urgkeys = sort_urgkeys_by_distance_toescort(items, keys(urgmats),(esc_x, esc_y), true)

    # CAN WE SERVE AN URGENT CUSTOMER DIRECTLY IN NEXT ITERATION? 
    for itemid in sorted_urgkeys # try serve item in next iteration 
        itemx, itemy = items[itemid].coords
        if ((IO[1] < itemx && esc_x < itemx) ||  # check if we can move escort to item path on X
            (IO[1] > itemx && esc_x > itemx)) && itemx != esc_x
            ygap = abs(esc_y - itemy)
            path_blocked = false ; skipItem = false
            for (ox, oy) in other_escorts_coords # if there exists an escort ready to serve this item we dont block it
                if oy == itemy
                    if (IO[1] > itemx && esc_x > itemx) &&  # item going right we want to avoid itemx-ox-escx
                        (itemx < esc_x && ox < esc_x && itemx < ox) # esc_x < ox && itemx <ox || itemx < esc_x && ox < esc_x && itemx < ox # If going left, check if there's an escort further left
                        skipItem = true
                        break
                    elseif (IO[1] < itemx && esc_x < itemx) &&  # item goes left. we want to avoid escx-ox-itemx
                        (itemx > esc_x && ox > esc_x && itemx> ox )# esc_x > ox && itemx >ox || itemx> esc_x && ox > esc_x && itemx > ox  # If going right, check if there's an escort further right
                        skipItem = true
                        break
                    end
                end
            end
            if skipItem
                continue
            end
            if ygap <= disty && ygap > 0 # if gap is 0 we could have served, there must be a reason we didnt
                ymin = min(esc_y, itemy)
                ymax = max(esc_y, itemy)

               
                for y in ymin:ymax
                    if blockmat[esc_x, y] == 1 || matrix[esc_x, y] in keys(items)
                        path_blocked = true
                        break
                    end
                end
                if IO[1] > min(itemx, esc_x) && IO[1] < max(itemx, esc_x) # can serve but effects badly 
                    for x in min(esc_x, IO[1]):max(esc_x, IO[1])
                        if matrix[x, itemy] in keys(items) 
                            path_blocked = true
                            break
                        end
                    end
                end
            else 
                continue
            end
            if !path_blocked || (ygap == 0 && ((esc_x < itemx && IO[1] < itemx) || (esc_x > itemx && IO[1] > itemx)))
                itemscoords = generatefuturecoords(items, escorts, 1, escortid, itemid, matrix, IO)
                sameycoords = filter(x -> x[2] == itemy && x[1] >= min(itemx, esc_x) && x[1] <= max(itemx, esc_x), itemscoords) # as moving this item might move another item closer to depot
                minDist = minimum([abs(IO[1] - coord[1]) + abs(IO[2] - coord[2]) for coord in sameycoords])
                if minDist  > length(keys(items))+1 || # item far out from IO
                    path_to_io_exists_if(matrix, itemscoords, IO)   # check with A* if this movement would cause some stupid block
                    disty = ygap 
                    closesty = itemid
                else# else we ban it for next iteration to simplify computation on assignment! 
                    if !haskey(thisescort.banset, iteration+1)
                        thisescort.banset[iteration+1] = [itemid]
                    else
                        push!(thisescort.banset[iteration+1],itemid)
                    end
                end
            end
        end
        if esc_y < itemy # check if we can move escort to item path on Y 
            xgap = abs(esc_x - itemx)
            path_blocked = false ; skipItem = false
            for (ox, oy) in other_escorts_coords
                if ox == itemx && oy < itemy
                    skipItem = true
                    break
                end
            end
            if skipItem
                continue
            end
            if xgap <= distx && xgap > 0
                xmin = min(esc_x, itemx)
                xmax = max(esc_x, itemx)
                for x in xmin:xmax
                    if blockmat[x, esc_y] == 1 || matrix[x, esc_y] in keys(items)
                        path_blocked = true
                        break
                    end
                end
            else
                continue
            end
            if !path_blocked || xgap==0 # if gap is 0 we could have served, there must be a reason we didnt 
                itemscoords = generatefuturecoords(items, escorts,2, escortid, itemid, matrix, IO)
                samexcoords = filter(x -> x[1] == itemx && x[2] >= min(itemy, esc_y) && x[2] <= max(itemy, esc_y), itemscoords) # as moving this item might move another item closer to depot
                minDist = minimum([abs(IO[1] - coord[1]) + abs(IO[2] - coord[2]) for coord in samexcoords])
                if  minDist > length(keys(items))+1 ||
                    path_to_io_exists_if(matrix, itemscoords, IO) # check with A* if this movement would cause some stupid block
                    distx = xgap
                    closestx = itemid
                else 
                    if !haskey(thisescort.banset, iteration+1)
                        thisescort.banset[iteration+1] = [itemid]
                    else
                        push!(thisescort.banset[iteration+1],itemid)
                    end
                end
            end
        end
    end
    # If we could serve an item we move to there
    if distx < disty  && closestx !=0 # go in front of item in Y direction
        if haskey(urgmats, closestx)
            delete!(urgmats, closestx)
        end
        candx , candy = items[closestx].coords
        return (candx, esc_y)
    end
    if distx >= disty && closesty !=0 # go in path of item in X direction
        if haskey(urgmats, closesty)
            delete!(urgmats, closesty)
        end
        candx , candy = items[closesty].coords
        return (esc_x, candy)
    end
    # CAN WE SERVE ANOTHER CUSTOMER IN NEXT ITERATION? 
    for itemid in setdiff(sortedkeys, keys(urgmats)) # try serve item in next iteration 
        itemx, itemy = items[itemid].coords
        if ((IO[1] < itemx && esc_x < itemx) ||  # check if we can move escort to item path on X
            (IO[1] > itemx && esc_x > itemx)) && itemx != esc_x
            ygap = abs(esc_y - itemy)
            path_blocked = false ; skipItem = false
            for (ox, oy) in other_escorts_coords # if there exists an escort ready to serve this item we dont block it
                if oy == itemy
                    if (IO[1] > itemx && esc_x > itemx) &&  # item going right we want to avoid itemx-ox-escx
                        (itemx < esc_x && ox < esc_x && itemx < ox) # esc_x < ox && itemx <ox || itemx < esc_x && ox < esc_x && itemx < ox # If going left, check if there's an escort further left
                        skipItem = true
                        break
                    elseif (IO[1] < itemx && esc_x < itemx) &&  # item goes left. we want to avoid escx-ox-itemx
                        (itemx > esc_x && ox > esc_x && itemx> ox )# esc_x > ox && itemx >ox || itemx> esc_x && ox > esc_x && itemx > ox  # If going right, check if there's an escort further right
                        skipItem = true
                        break
                    end
                end
            end
            if skipItem
                continue
            end
            if ygap <= disty && ygap > 0 # if gap is 0 we could have served, there must be a reason we didnt
                ymin = min(esc_y, itemy)
                ymax = max(esc_y, itemy)

               
                for y in ymin:ymax
                    if blockmat[esc_x, y] == 1 || matrix[esc_x, y] in keys(items)
                        path_blocked = true
                        break
                    end
                end
                if IO[1] > min(itemx, esc_x) && IO[1] < max(itemx, esc_x) # can serve but effects badly 
                    for x in min(esc_x, IO[1]):max(esc_x, IO[1])
                        if matrix[x, itemy] in keys(items) 
                            path_blocked = true
                            break
                        end
                    end
                end
            else 
                continue
            end
            if !path_blocked || (ygap == 0 && ((esc_x < itemx && IO[1] < itemx) || (esc_x > itemx && IO[1] > itemx)))
                itemscoords = generatefuturecoords(items, escorts, 1, escortid, itemid, matrix, IO)
                sameycoords = filter(x -> x[2] == itemy && x[1] >= min(itemx, esc_x) && x[1] <= max(itemx, esc_x), itemscoords) # as moving this item might move another item closer to depot
                minDist = minimum([abs(IO[1] - coord[1]) + abs(IO[2] - coord[2]) for coord in sameycoords])
                if minDist  > length(keys(items))+1 || # item far out from IO
                    path_to_io_exists_if(matrix, itemscoords, IO)   # check with A* if this movement would cause some stupid block
                    disty = ygap 
                    closesty = itemid
                else# else we ban it for next iteration to simplify computation on assignment! 
                    if !haskey(thisescort.banset, iteration+1)
                        thisescort.banset[iteration+1] = [itemid]
                    else
                        push!(thisescort.banset[iteration+1],itemid)
                    end
                end
            end
        end
        if esc_y < itemy # check if we can move escort to item path on Y 
            xgap = abs(esc_x - itemx)
            path_blocked = false ; skipItem = false
            for (ox, oy) in other_escorts_coords
                if ox == itemx && oy < itemy
                    skipItem = true
                    break
                end
            end
            if skipItem
                continue
            end
            if xgap <= distx && xgap > 0
                xmin = min(esc_x, itemx)
                xmax = max(esc_x, itemx)
                for x in xmin:xmax
                    if blockmat[x, esc_y] == 1 || matrix[x, esc_y] in keys(items)
                        path_blocked = true
                        break
                    end
                end
            else
                continue
            end
            if !path_blocked || xgap==0 # if gap is 0 we could have served, there must be a reason we didnt 
                itemscoords = generatefuturecoords(items, escorts,2, escortid, itemid, matrix, IO)
                samexcoords = filter(x -> x[1] == itemx && x[2] >= min(itemy, esc_y) && x[2] <= max(itemy, esc_y), itemscoords) # as moving this item might move another item closer to depot
                minDist = minimum([abs(IO[1] - coord[1]) + abs(IO[2] - coord[2]) for coord in samexcoords])
                if  minDist > length(keys(items))+1 ||
                    path_to_io_exists_if(matrix, itemscoords, IO) # check with A* if this movement would cause some stupid block
                    distx = xgap
                    closestx = itemid
                else 
                    if !haskey(thisescort.banset, iteration+1)
                        thisescort.banset[iteration+1] = [itemid]
                    else
                        push!(thisescort.banset[iteration+1],itemid)
                    end
                end
            end
        end
    end
    # If we could serve an item we move to there
    if distx < disty  && closestx !=0 # go in front of item in Y direction
        if haskey(urgmats, closestx)
            delete!(urgmats, closestx)
        end
        candx , candy = items[closestx].coords
        return (candx, esc_y)
    end
    if distx >= disty && closesty !=0 # go in path of item in X direction
        if haskey(urgmats, closesty)
            delete!(urgmats, closesty)
        end
        candx , candy = items[closesty].coords
        return (esc_x, candy)
    end
    # MUST WE SERVE A CUSTOMER SOON? 3-4 Steps 
    if !isempty(keys(urgmats))
        urgentassignmentdict = Dict{String, Tuple{Int, Int, Int}}() # itemid, steps, x, y
        for urgitem in keys(urgmats)
            urgmat= urgmats[urgitem]
            urgx,urgy = items[urgitem].coords
            skip_urgitem = false
            for escid in keys(escorts)
                if escid == escortid
                    continue
                end
                otherescx, otherescy = escorts[escid].coords
                if urgmat[otherescx, otherescy] == 2
                    skip_urgitem = true
                    break
                end
            end
            if skip_urgitem
                continue
            end                 
            foundy = false; foundx = false; completedy = false; completedx = false; distance = Inf; dir = urgx > IO[1] ? -1 : 1
            candidy = 0; xin = deepcopy(esc_x); yin = deepcopy(esc_y); candidx = 0; gapy = Inf ; gapx = Inf
            if urgmat[esc_x, esc_y] == 2
                #println("Escort is 2 steps away from urgent item, should have served in previous step")
                continue 
            end
            while !completedy 
                if ( esc_x < urgx && IO[1] < urgx) ||
                    (esc_x > urgx && IO[1] > urgx)
                    completedy = true
                    break
                end
                if  (esc_y>=urgy)
                    for y in esc_y-1:-1:1
                        if urgmat[xin, y] == 2
                            candidy = y
                            gapy = abs(esc_y-y )
                            foundy = true
                            break
                        elseif urgmat[xin, y] == 1
                            foundy = false
                        end
                    end
                    if foundy || ( xin + dir < 1 ||
                        xin + dir > size(matrix, 1) ||
                            (dir == -1 && xin + dir <= urgx) ||
                            (dir == 1 && xin + dir > urgx))
                        completedy = true  # we cannot move anymore, if we havent found a 2 we cannot move
                    else
                        xin += dir
                    end
                elseif (esc_y < urgy-1) 
                    for y in esc_y+1:urgy-1
                        if urgmat[xin, y] == 2
                            candidy = y
                            gapy = abs(esc_y-y )
                            foundy = true
                            break
                        elseif urgmat[xin, y] == 1
                            foundy = false
                        end
                    end
                    if foundy || ( xin + dir < 1 ||
                        xin + dir > size(matrix, 1) ||
                            (dir == -1 && xin + dir <= urgx) ||
                            (dir == 1 && xin + dir > urgx))
                        completedy = true  # we cannot move anymore, if we havent found a 2 we cannot move
                    else
                        xin += dir
                    end
        
                else
                    completedy = true
                end
                
            end
            while !completedx
                if esc_y<=urgy
                    completedx = true
                    break
                end
                if esc_x>=urgx
                    if dir == -1 # escort on the right side or urg: IO-urg-esc
                        for x in esc_x-1:-1:IO[1]
                            if urgmat[x, esc_y] == 2
                                candidx = x
                                gapx = abs(esc_x - x)
                                foundx = true
                                break
                            elseif urgmat[x, esc_y] == 1
                                foundx = false
                                break
                            end
                        end
                    else # escort on the right side of urg : urg-esc-IO or urg-IO-esc
                        for x in esc_x-1:-1:urgx
                            if urgmat[x, esc_y] == 2
                                candidx = x
                                gapx = abs(esc_x - x)
                                foundx = true
                                break
                            elseif urgmat[x, esc_y] == 1
                                foundx = false
                                break
                            end
                        end
                    end
                    if foundx || yin -1 <= urgy
                        completedx = true # we cannot move anymore, if we havent found a 2 we cannot move
                    else
                        yin -= 1
                    end
                elseif esc_x<urgx-1
                    if dir ==1# escort left of item, item left of IO
                        for x in esc_x+1:IO[1]
                            if urgmat[x, esc_y] == 2
                                candidx = x
                                gapx = abs(esc_x - x)
                                foundx = true
                                break
                            elseif urgmat[x, esc_y] == 1
                                foundx = false
                            end
                        end
                    else # escort left of item, item right of IO
                        for x in esc_x+1:urgx-1
                            if urgmat[x, esc_y] == 2
                                candidx = x
                                gapx = abs(esc_x - x)
                                foundx = true
                                break
                            elseif urgmat[x, esc_y] == 1
                                foundx = false
                            end
                        end
                        for x in esc_x-1:-1:1
                            if urgmat[x, esc_y] == 2
                                gapotherx = abs(esc_x - x)
                                if gapotherx < gapx
                                    gapx = gapotherx
                                    candidx = x
                                end                                
                                foundx = true
                                break
                            elseif urgmat[x, esc_y] == 1
                                foundx = false
                            end
                        end
                    end
                    if foundx || yin -1 <= urgy
                        completedx = true # we cannot move anymore, if we havent found a 2 we cannot move
                    else
                        yin -= 1
                    end
                else
                    completedx = true
                end
            end
            if foundy && foundx
                onx = xin == esc_x ? 1 : 0
                ony = yin == esc_y ? 1 : 0
                if onx + ony == 2 # 3 step both fine
                    if gapx < gapy
                        candidx = esc_x 
                    else 
                        candidy = esc_y
                    end
                elseif onx == 1  # 3 step go down with escort
                    candidy = esc_y; distance = gapx
                elseif ony == 1 # 3 step go left in with escort (if escort right out of item)
                    candidx = esc_x;  distance = gapy
                else # 4 step 
                    gapx = gapx + 5*(abs(esc_y - yin))
                    gapy = gapy + 5*(abs(esc_x- xin))
                    if gapx < gapy
                        candidy = yin; candidx = esc_x ; distance = gapx
                    else
                        candidx = xin ; candidy = esc_y ; distance = gapy
                    end
                end
            elseif foundy
                onx = xin == esc_x ? 1 : 0
                if onx ==1 
                    candidx = esc_x ; distance = gapy
                else # 4 Step
                    gapy = gapy + 5*(abs(esc_x- xin))
                    candidx = xin ; candidy = esc_y ; distance = gapy
                end
            elseif foundx 
                ony = yin == esc_y ? 1 : 0
                if ony ==1 
                    candidy = yin; distance = gapx
                else # 4 Step
                    gapx = gapx + 5*(abs(esc_y - yin))
                    candidy = yin; candidx = esc_x;  distance = gapx # go down 
                end
            end
            # we check how many steps to get to a 2 in the matrix from the position and how far
            if distance != Inf && candidx != 0 && candidy!=0 && !(matrix[candidx, candidy] in keys(escorts))
                urgentassignmentdict[urgitem] =(distance , candidx,candidy) 
            end
        end

        if !isempty(urgentassignmentdict)
            min_distance = Inf
            min_key = ""
            min_tuple = ()
            for (key, value) in urgentassignmentdict
                if value[1] < min_distance
                    newx, newy = value[2], value[3]
                    skipthis = false
                    if esc_x == newx
                        ystart, yend = min(esc_y, newy), max(esc_y, newy)
                        for y in ystart:yend
                            if matrix[esc_x, y] in allkeys
                                skipthis = true
                                break
                            end
                        end
                    elseif esc_y == newy
                        xstart, xend = min(esc_x, newx), max(esc_x, newx)
                        for x in xstart:xend
                            if matrix[x, esc_y] in allkeys
                                skipthis = true
                                break
                            end
                        end
                    end
                    if skipthis
                        continue
                    elseif !((newx, newy) in escorts[escortid].tabu)
                        min_distance = value[1]
                        min_key = key
                        min_tuple = value
                    end
                end
            end 
            
            if  !isempty(min_tuple)
                delete!(urgmats, min_key)
                otheritems = setdiff(keys(urgentassignmentdict), [min_key])
                if !haskey(thisescort.banset, iteration+1)
                    thisescort.banset[iteration+1] = Vector{String}(collect(otheritems))
                else
                    append!(thisescort.banset[iteration+1], otheritems)
                end
                #println("$iteration :$escortid-> $min_key movement decided by urgency policy")
                return (min_tuple[2], min_tuple[3]) # we also need some sort of commitment. using the banset I assume TODO 
            end
        end 
    end
    # FREE ROAM; GO SOMEWHERE ELSE/FREE IF POSSIBLE
    if closestx ==0  && closesty == 0 # Most complex part of this entire algorithm, even if A*fromIO said no dont do it now we do it if we are blocked anyways
        worked, asternmat = outwards_astar_with_dirchange(matrix, IO, blockmat,escortid,escorts,items)
        if esc_x == IO[1] && esc_y == IO[2]
            return (esc_x, esc_y) # best place it could be 
        elseif esc_x == IO[1] # down, outwards, 
            maxmove_y = checkasternmat(blockmat, matrix, -2, escortid, strategy, escorts, items,IO, asternmat)
            if (maxmove_y == esc_y) || matrix[esc_x, maxmove_y ] in keys(escorts) || (esc_x, maxmove_y) in thisescort.tabu #cannot move down enough , move out of the way right or left 
                avg_x = mean([items[item].coords[1] for item in keys(items)]) # where are the items ? 
                diresc= avg_x <= IO[1] ? 1 : -1 # if items are left we go right, vice versa
                for _ in 1:2 # Try both directions if the first choice fails
                    if diresc == 1 || IO[1] ==1 # chose right
                        maxmove = size(matrix, 1)
                        maxmove = checkmatrixforblock!(blockmat, matrix, diresc, escortid, strategy, iteration, escorts, items, IO)
                        if (maxmove > esc_x && !(matrix[maxmove, esc_y] in keys(escorts)))&& !((maxmove, esc_y) in thisescort.tabu) # can move right
                            return (maxmove, esc_y)
                        end
                    elseif diresc == -1 || IO[1] == size(matrix,1)# chose left
                        maxmove = 1
                        maxmove = checkmatrixforblock!(blockmat, matrix, diresc, escortid, strategy, iteration, escorts, items,IO)
                        if (maxmove < esc_x && !(matrix[maxmove, esc_y] in keys(escorts)))&& !((maxmove, esc_y) in thisescort.tabu) # can move left
                            return (maxmove, esc_y)
                        end
                    end
                    diresc = -diresc # Switch direction
                end 
                if moveitnow # side is also blocked. so now we couldnt move down or sideways
                    minup = checkmatrixforblock!(blockmat, matrix, 2, escortid, strategy, iteration, escorts, items,IO)
                    if minup > esc_y
                        return (esc_x, minup)
                    end
                end

            else
                return (esc_x, maxmove_y)
            end
        elseif esc_y == IO[2] # go in X direction towards IO , if blocked go up, if must move go outwards 
            if esc_x < IO[1] # io on the right
                maxmove_x = checkasternmat( blockmat, matrix, 1, escortid, strategy, escorts, items,IO, asternmat)
                if maxmove_x == esc_x || matrix[maxmove_x, esc_y] in keys(escorts) || (maxmove_x, esc_y) in thisescort.tabu 
                    minup = asternmat[esc_x,esc_y+1] != Inf ? checkasternmat(blockmat, matrix, 2, escortid, strategy, escorts, items,IO, asternmat) :
                        checkmatrixforblock!(blockmat, matrix, 2, escortid, strategy, iteration, escorts, items,IO)
                    if minup > esc_y
                        return (esc_x, minup)
                    elseif moveitnow 
                        maxmove_x = checkasternmat( blockmat, matrix, -1, escortid, strategy, escorts, items,IO, asternmat)
                        if maxmove_x == esc_x || matrix[maxmove_x, esc_y] in keys(escorts) || (maxmove_x, esc_y) in thisescort.tabu 
                            return (maxmove_x, esc_y)
                        end
                    end
                end                
            else # io on the left
                maxmove_x = maxmove_x = checkasternmat( blockmat, matrix, -1, escortid, strategy, escorts, items,IO, asternmat)
                if maxmove_x == esc_x || matrix[maxmove_x, esc_y] in keys(escorts) || (maxmove_x, esc_y) in thisescort.tabu 
                    minup = asternmat[esc_x,esc_y+1] != Inf ? checkasternmat(blockmat, matrix, 2, escortid, strategy, escorts, items,IO, asternmat) :
                        checkmatrixforblock!(blockmat, matrix, 2, escortid, strategy, iteration, escorts, items,IO)
                    if minup > esc_y
                        return (esc_x, minup)
                    elseif moveitnow 
                        maxmove_x = checkasternmat( blockmat, matrix, 1, escortid, strategy, escorts, items,IO, asternmat)
                        if maxmove_x == esc_x || matrix[maxmove_x, esc_y] in keys(escorts) || (maxmove_x, esc_y) in thisescort.tabu 
                            return (maxmove_x, esc_y)
                        end
                    end
                end     
            end  
            return (maxmove_x, esc_y)
        else # not at IO coords # down, inwards, upwards, outwards
            avg_x = mean([items[item].coords[1] for item in keys(items)])
            dirx= avg_x <= IO[1] ? 1 : -1 # try go to the opposite direction of the items to be able to serve them
            iodir = dirx
            maxmove_y = checkasternmat(blockmat, matrix, -2, escortid, strategy, escorts, items,IO, asternmat)#checkmatrixforblock!(blockmat, matrix, 1, -2, escortid, strategy, iteration, escorts, items,IO)
            if (maxmove_y == esc_y) || matrix[esc_x, maxmove_y ] in keys(escorts) || (esc_x, maxmove_y) in thisescort.tabu# cannot move down enough , move out of the way right or left 
                for _ in 1:2 
                    if dirx == 1 # chose right
                        maxmove = iodir == dirx ?  # if asternmat can be used we use it
                                checkasternmat( blockmat, matrix, dirx, escortid, strategy, escorts, items,IO, asternmat) :
                                checkmatrixforblock!(blockmat, matrix, dirx, escortid, strategy, iteration, escorts, items,IO)
                        if maxmove > esc_x && !(matrix[maxmove, esc_y] in keys(escorts)) && !((maxmove, esc_y) in thisescort.tabu) # can move right
                            return (maxmove, esc_y)
                        end
                    elseif dirx == -1 # chose left
                        maxmove = iodir == dirx ? 
                                checkasternmat( blockmat, matrix, dirx, escortid, strategy, escorts, items,IO, asternmat) :
                                checkmatrixforblock!(blockmat, matrix, dirx, escortid, strategy, iteration, escorts, items,IO)
                        if (maxmove < esc_x && !(matrix[maxmove, esc_y] in keys(escorts))) && !((maxmove, esc_y) in thisescort.tabu) # can move left
                            return (maxmove, esc_y)
                        end
                    end
                    dirx = -dirx
                end
            else # can go down
                return (esc_x, maxmove_y)
            end
            if moveitnow # must move so we try up
                minup = checkmatrixforblock!(blockmat, matrix, 2, escortid, strategy, iteration, escorts, items,IO)
                if minup > esc_y
                    return (esc_x, minup)
                end
            end
            
        end
    end
    return (finx, finy) # cannot move
end
function directserve_makespan!(iteration, matrix, items, escorts, escortid, urgcusts, blockmat, IO)
    thisescort = escorts[escortid]
    esc_x, esc_y = thisescort.coords

    # Get coordinates of escorts that have not moved this iteration and are not this escort
    other_escorts_coords = [(escorts[esc].coords[1], escorts[esc].coords[2]) for esc in keys(escorts) if esc != escortid]
   
    distx, disty = size(matrix, 1)+1, size(matrix, 2)+1
    closestx , closesty = 0 , 0 
    sortedkeys = sort_keys_by_distance(items, IO, true) # sort by distance to IO

    # Sort urgent customers by their urgency and distance to IO
   

    # CAN WE SERVE AN URGENT CUSTOMER DIRECTLY IN NEXT ITERATION? 
  
    # CAN WE SERVE ANOTHER CUSTOMER IN NEXT ITERATION? 
    for itemid in sortedkeys # try serve item in next iteration 
        itemx, itemy = items[itemid].coords
        if ((IO[1] < itemx && esc_x < itemx) ||  # check if we can move escort to item path on X
            (IO[1] > itemx && esc_x > itemx)) && itemx != esc_x
            ygap = abs(esc_y - itemy)
            path_blocked = false ; skipItem = false
            for (ox, oy) in other_escorts_coords # if there exists an escort ready to serve this item we dont block it
                if oy == itemy
                    if (IO[1] > itemx && esc_x > itemx) &&  # item going right we want to avoid itemx-ox-escx
                        (itemx < esc_x && ox < esc_x && itemx < ox) # esc_x < ox && itemx <ox || itemx < esc_x && ox < esc_x && itemx < ox # If going left, check if there's an escort further left
                        skipItem = true
                        break
                    elseif (IO[1] < itemx && esc_x < itemx) &&  # item goes left. we want to avoid escx-ox-itemx
                        (itemx > esc_x && ox > esc_x && itemx> ox )# esc_x > ox && itemx >ox || itemx> esc_x && ox > esc_x && itemx > ox  # If going right, check if there's an escort further right
                        skipItem = true
                        break
                    end
                end
            end
            if skipItem
                continue
            end
            if ygap <= disty && ygap > 0 # if gap is 0 we could have served, there must be a reason we didnt
                ymin = min(esc_y, itemy)
                ymax = max(esc_y, itemy)

               
                for y in ymin:ymax
                    if blockmat[esc_x, y] == 1 || matrix[esc_x, y] in keys(items)
                        path_blocked = true
                        break
                    end
                end
                if IO[1] > min(itemx, esc_x) && IO[1] < max(itemx, esc_x) # can serve but effects badly 
                    for x in min(esc_x, IO[1]):max(esc_x, IO[1])
                        if matrix[x, itemy] in keys(items) 
                            path_blocked = true
                            break
                        end
                    end
                end
            else 
                continue
            end
            if !path_blocked || (ygap == 0 && ((esc_x < itemx && IO[1] < itemx) || (esc_x > itemx && IO[1] > itemx)))
                itemscoords = generatefuturecoords(items, escorts, 1, escortid, itemid, matrix, IO)
                sameycoords = filter(x -> x[2] == itemy && x[1] >= min(itemx, esc_x) && x[1] <= max(itemx, esc_x), itemscoords) # as moving this item might move another item closer to depot
                minDist = minimum([abs(IO[1] - coord[1]) + abs(IO[2] - coord[2]) for coord in sameycoords])
                if minDist  > length(keys(items))+1 || # item far out from IO
                    path_to_io_exists_if(matrix, itemscoords, IO)   # check with A* if this movement would cause some stupid block
                    disty = ygap 
                    closesty = itemid
                else# else we ban it for next iteration to simplify computation on assignment! 
                    if !haskey(thisescort.banset, iteration+1)
                        thisescort.banset[iteration+1] = [itemid]
                    else
                        push!(thisescort.banset[iteration+1],itemid)
                    end
                end
            end
        end
        if esc_y < itemy # check if we can move escort to item path on Y 
            xgap = abs(esc_x - itemx)
            path_blocked = false ; skipItem = false
            for (ox, oy) in other_escorts_coords
                if ox == itemx && oy < itemy
                    skipItem = true
                    break
                end
            end
            if skipItem
                continue
            end
            if xgap <= distx && xgap > 0
                xmin = min(esc_x, itemx)
                xmax = max(esc_x, itemx)
                for x in xmin:xmax
                    if blockmat[x, esc_y] == 1 || matrix[x, esc_y] in keys(items)
                        path_blocked = true
                        break
                    end
                end
            else
                continue
            end
            if !path_blocked || xgap==0 # if gap is 0 we could have served, there must be a reason we didnt 
                itemscoords = generatefuturecoords(items, escorts,2, escortid, itemid, matrix, IO)
                samexcoords = filter(x -> x[1] == itemx && x[2] >= min(itemy, esc_y) && x[2] <= max(itemy, esc_y), itemscoords) # as moving this item might move another item closer to depot
                minDist = minimum([abs(IO[1] - coord[1]) + abs(IO[2] - coord[2]) for coord in samexcoords])
                if  minDist > length(keys(items))+1 ||
                    path_to_io_exists_if(matrix, itemscoords, IO) # check with A* if this movement would cause some stupid block
                    distx = xgap
                    closestx = itemid
                else 
                    if !haskey(thisescort.banset, iteration+1)
                        thisescort.banset[iteration+1] = [itemid]
                    else
                        push!(thisescort.banset[iteration+1],itemid)
                    end
                end
            end
        end
    end
    # If we could serve an item we move to there
    if distx < disty  && closestx !=0 # go in front of item in Y direction
        if closestx in urgcusts 
            filter!(id -> id != closestx, urgcusts)
        end
        candx , candy = items[closestx].coords
        return true, (candx, esc_y)
    end
    if distx >= disty && closesty !=0 # go in path of item in X direction
        if closesty in urgcusts 
            filter!(id -> id != closesty, urgcusts)
        end
        candx , candy = items[closesty].coords
        return true, (esc_x, candy)
    end
    return false , (esc_x, esc_y)
end
function directserve_flow!(iteration, matrix, items, escorts, escortid, urgcusts, blockmat, IO)
    thisescort = escorts[escortid]
    esc_x, esc_y = thisescort.coords
    
    allkeys = setdiff(union(keys(escorts), keys(items)), [escortid])
    # Get coordinates of escorts that have not moved this iteration and are not this escort
    other_escorts_coords = [(escorts[esc].coords[1], escorts[esc].coords[2]) for esc in keys(escorts) if esc != escortid]
   
    distx, disty = size(matrix, 1)+1, size(matrix, 2)+1
    closestx , closesty = 0 , 0 
    sortedkeys = sort_keys_by_distance(items, IO, true) # sort by distance to IO

    # Sort urgent customers by their urgency and distance to IO
    sorted_urgkeys = sort_urgkeys_by_distance_toescort(items, urgcusts,(esc_x, esc_y), true)

    # CAN WE SERVE AN URGENT CUSTOMER DIRECTLY IN NEXT ITERATION? 
    for itemid in sorted_urgkeys # try serve item in next iteration 
        itemx, itemy = items[itemid].coords
        if ((IO[1] < itemx && esc_x < itemx) ||  # check if we can move escort to item path on X
            (IO[1] > itemx && esc_x > itemx)) && itemx != esc_x
            ygap = abs(esc_y - itemy)
            path_blocked = false ; skipItem = false
            for (ox, oy) in other_escorts_coords # if there exists an escort ready to serve this item we dont block it
                if oy == itemy
                    if (IO[1] > itemx && esc_x > itemx) &&  # item going right we want to avoid itemx-ox-escx
                        (itemx < esc_x && ox < esc_x && itemx < ox) # esc_x < ox && itemx <ox || itemx < esc_x && ox < esc_x && itemx < ox # If going left, check if there's an escort further left
                        skipItem = true
                        break
                    elseif (IO[1] < itemx && esc_x < itemx) &&  # item goes left. we want to avoid escx-ox-itemx
                        (itemx > esc_x && ox > esc_x && itemx> ox )# esc_x > ox && itemx >ox || itemx> esc_x && ox > esc_x && itemx > ox  # If going right, check if there's an escort further right
                        skipItem = true
                        break
                    end
                end
            end
            if skipItem
                continue
            end
            if ygap <= disty && ygap > 0 # if gap is 0 we could have served, there must be a reason we didnt
                ymin = min(esc_y, itemy)
                ymax = max(esc_y, itemy)

               
                for y in ymin:ymax
                    if blockmat[esc_x, y] == 1 || matrix[esc_x, y] in allkeys
                        path_blocked = true
                        break
                    end
                end
                if IO[1] > min(itemx, esc_x) && IO[1] < max(itemx, esc_x) # can serve but effects badly 
                    for x in min(esc_x, IO[1]):max(esc_x, IO[1])
                        if matrix[x, itemy] in allkeys 
                            path_blocked = true
                            break
                        end
                    end
                end
            else 
                continue
            end
            if !path_blocked || (ygap == 0 && ((esc_x < itemx && IO[1] < itemx) || (esc_x > itemx && IO[1] > itemx)))
                itemscoords = generatefuturecoords(items, escorts, 1, escortid, itemid, matrix, IO)
                sameycoords = filter(x -> x[2] == itemy && x[1] >= min(itemx, esc_x) && x[1] <= max(itemx, esc_x), itemscoords) # as moving this item might move another item closer to depot
                minDist = minimum([abs(IO[1] - coord[1]) + abs(IO[2] - coord[2]) for coord in sameycoords])
                if minDist  > length(keys(items))+1 || # item far out from IO
                    path_to_io_exists_if(matrix, itemscoords, IO)   # check with A* if this movement would cause some stupid block
                    disty = ygap 
                    closesty = itemid
                else# else we ban it for next iteration to simplify computation on assignment! 
                    if !haskey(thisescort.banset, iteration+1)
                        thisescort.banset[iteration+1] = [itemid]
                    else
                        push!(thisescort.banset[iteration+1],itemid)
                    end
                end
            end
        end
        if esc_y < itemy # check if we can move escort to item path on Y 
            xgap = abs(esc_x - itemx)
            path_blocked = false ; skipItem = false
            for (ox, oy) in other_escorts_coords
                if ox == itemx && oy < itemy
                    skipItem = true
                    break
                end
            end
            if skipItem
                continue
            end
            if xgap <= distx && xgap > 0
                xmin = min(esc_x, itemx)
                xmax = max(esc_x, itemx)
                for x in xmin:xmax
                    if blockmat[x, esc_y] == 1 || matrix[x, esc_y] in allkeys
                        path_blocked = true
                        break
                    end
                end
            else
                continue
            end
            if !path_blocked || xgap==0 # if gap is 0 we could have served, there must be a reason we didnt 
                itemscoords = generatefuturecoords(items, escorts,2, escortid, itemid, matrix, IO)
                samexcoords = filter(x -> x[1] == itemx && x[2] >= min(itemy, esc_y) && x[2] <= max(itemy, esc_y), itemscoords) # as moving this item might move another item closer to depot
                minDist = minimum([abs(IO[1] - coord[1]) + abs(IO[2] - coord[2]) for coord in samexcoords])
                if  minDist > length(keys(items))+1 ||
                    path_to_io_exists_if(matrix, itemscoords, IO) # check with A* if this movement would cause some stupid block
                    distx = xgap
                    closestx = itemid
                else 
                    if !haskey(thisescort.banset, iteration+1)
                        thisescort.banset[iteration+1] = [itemid]
                    else
                        push!(thisescort.banset[iteration+1],itemid)
                    end
                end
            end
        end
    end
    # If we could serve an item we move to there
    if distx < disty  && closestx !=0 # go in front of item in Y direction
        if closestx in urgcusts 
            filter!(id -> id != closestx, urgcusts)
        end
        candx , candy = items[closestx].coords
        return true, (candx, esc_y)
    end
    if distx >= disty && closesty !=0 # go in path of item in X direction
        if closesty in urgcusts 
            filter!(id -> id != closesty, urgcusts)
        end
        candx , candy = items[closesty].coords
        return true, (esc_x, candy)
    end
    # CAN WE SERVE ANOTHER CUSTOMER IN NEXT ITERATION? 
    for itemid in setdiff(sortedkeys, urgcusts) # try serve item in next iteration 
        itemx, itemy = items[itemid].coords
        if ((IO[1] < itemx && esc_x < itemx) ||  # check if we can move escort to item path on X
            (IO[1] > itemx && esc_x > itemx)) && itemx != esc_x
            ygap = abs(esc_y - itemy)
            path_blocked = false ; skipItem = false
            for (ox, oy) in other_escorts_coords # if there exists an escort ready to serve this item we dont block it
                if oy == itemy
                    if (IO[1] > itemx && esc_x > itemx) &&  # item going right we want to avoid itemx-ox-escx
                        (itemx < esc_x && ox < esc_x && itemx < ox) # esc_x < ox && itemx <ox || itemx < esc_x && ox < esc_x && itemx < ox # If going left, check if there's an escort further left
                        skipItem = true
                        break
                    elseif (IO[1] < itemx && esc_x < itemx) &&  # item goes left. we want to avoid escx-ox-itemx
                        (itemx > esc_x && ox > esc_x && itemx> ox )# esc_x > ox && itemx >ox || itemx> esc_x && ox > esc_x && itemx > ox  # If going right, check if there's an escort further right
                        skipItem = true
                        break
                    end
                end
            end
            if skipItem
                continue
            end
            if ygap <= disty && ygap > 0 # if gap is 0 we could have served, there must be a reason we didnt
                ymin = min(esc_y, itemy)
                ymax = max(esc_y, itemy)

               
                for y in ymin:ymax
                    if blockmat[esc_x, y] == 1 || matrix[esc_x, y] in allkeys
                        path_blocked = true
                        break
                    end
                end
                if IO[1] > min(itemx, esc_x) && IO[1] < max(itemx, esc_x) # can serve but effects badly 
                    for x in min(esc_x, IO[1]):max(esc_x, IO[1])
                        if matrix[x, itemy] in allkeys 
                            path_blocked = true
                            break
                        end
                    end
                end
            else 
                continue
            end
            if !path_blocked || (ygap == 0 && ((esc_x < itemx && IO[1] < itemx) || (esc_x > itemx && IO[1] > itemx)))
                itemscoords = generatefuturecoords(items, escorts, 1, escortid, itemid, matrix, IO)
                sameycoords = filter(x -> x[2] == itemy && x[1] >= min(itemx, esc_x) && x[1] <= max(itemx, esc_x), itemscoords) # as moving this item might move another item closer to depot
                minDist = minimum([abs(IO[1] - coord[1]) + abs(IO[2] - coord[2]) for coord in sameycoords])
                if minDist  > length(keys(items))+1 || # item far out from IO
                    path_to_io_exists_if(matrix, itemscoords, IO)   # check with A* if this movement would cause some stupid block
                    disty = ygap 
                    closesty = itemid
                else# else we ban it for next iteration to simplify computation on assignment! 
                    if !haskey(thisescort.banset, iteration+1)
                        thisescort.banset[iteration+1] = [itemid]
                    else
                        push!(thisescort.banset[iteration+1],itemid)
                    end
                end
            end
        end
        if esc_y < itemy # check if we can move escort to item path on Y 
            xgap = abs(esc_x - itemx)
            path_blocked = false ; skipItem = false
            for (ox, oy) in other_escorts_coords
                if ox == itemx && oy < itemy
                    skipItem = true
                    break
                end
            end
            if skipItem
                continue
            end
            if xgap <= distx && xgap > 0
                xmin = min(esc_x, itemx)
                xmax = max(esc_x, itemx)
                for x in xmin:xmax
                    if blockmat[x, esc_y] == 1 || matrix[x, esc_y] in allkeys
                        path_blocked = true
                        break
                    end
                end
            else
                continue
            end
            if !path_blocked || xgap==0 # if gap is 0 we could have served, there must be a reason we didnt 
                itemscoords = generatefuturecoords(items, escorts,2, escortid, itemid, matrix, IO)
                samexcoords = filter(x -> x[1] == itemx && x[2] >= min(itemy, esc_y) && x[2] <= max(itemy, esc_y), itemscoords) # as moving this item might move another item closer to depot
                minDist = minimum([abs(IO[1] - coord[1]) + abs(IO[2] - coord[2]) for coord in samexcoords])
                if  minDist > length(keys(items))+1 ||
                    path_to_io_exists_if(matrix, itemscoords, IO) # check with A* if this movement would cause some stupid block
                    distx = xgap
                    closestx = itemid
                else 
                    if !haskey(thisescort.banset, iteration+1)
                        thisescort.banset[iteration+1] = [itemid]
                    else
                        push!(thisescort.banset[iteration+1],itemid)
                    end
                end
            end
        end
    end
    # If we could serve an item we move to there
    if distx < disty  && closestx !=0 # go in front of item in Y direction
        if closestx in urgcusts 
            filter!(id -> id != closestx, urgcusts)
        end
        candx , candy = items[closestx].coords
        return true, (candx, esc_y)
    end
    if distx >= disty && closesty !=0 # go in path of item in X direction
        if closesty in urgcusts 
            filter!(id -> id != closesty, urgcusts)
        end
        candx , candy = items[closesty].coords
        return true, (esc_x, candy)
    end
    return false , (esc_x, esc_y)
end
function directserve_flow_multi_io!(iteration, matrix, items, escorts, escortid,
                                     urgcusts, blockmat, item_to_ios, all_ios)
    thisescort = escorts[escortid]
    esc_x, esc_y = thisescort.coords

    allkeys = setdiff(union(keys(escorts), keys(items)), [escortid])
    other_escorts_coords = [(escorts[esc].coords[1], escorts[esc].coords[2]) for esc in keys(escorts) if esc != escortid]

    distx, disty = size(matrix, 1)+1, size(matrix, 2)+1
    closestx, closesty = 0, 0

    # Sort all items by distance to their nearest assigned IO
    sortedkeys = sort(collect(keys(items)), by = itemid -> begin
        assigned = get(item_to_ios, itemid, all_ios)
        minimum(io -> abs(io[1] - items[itemid].coords[1]) + abs(io[2] - items[itemid].coords[2]), assigned)
    end)

    sorted_urgkeys = sort_urgkeys_by_distance_toescort(items, urgcusts, (esc_x, esc_y), true)

    function try_serve_item!(itemid)
        itemx, itemy = items[itemid].coords
        assigned_ios = get(item_to_ios, itemid, all_ios)

        # ── X-DIRECTION: escort moves to item's y-row ──────────────────────
        # Need an IO where escort and IO are on the same side of the item —
        # that's the IO this item is heading toward, and the escort can intercept
        item_io_x = nothing
        for io in assigned_ios
            if ((io[1] < itemx && esc_x < itemx) || (io[1] > itemx && esc_x > itemx)) && itemx != esc_x
                item_io_x = io
                break
            end
        end

        if item_io_x !== nothing
            iox, ioy = item_io_x
            ygap = abs(esc_y - itemy)
            path_blocked = false; skipItem = false

            for (ox, oy) in other_escorts_coords
                if oy == itemy
                    if (iox > itemx && esc_x > itemx) &&
                        (itemx < esc_x && ox < esc_x && itemx < ox)
                        skipItem = true; break
                    elseif (iox < itemx && esc_x < itemx) &&
                        (itemx > esc_x && ox > esc_x && itemx > ox)
                        skipItem = true; break
                    end
                end
            end

            if !skipItem && ygap <= disty && ygap > 0
                for y in min(esc_y, itemy):max(esc_y, itemy)
                    if blockmat[esc_x, y] == 1 || matrix[esc_x, y] in allkeys
                        path_blocked = true; break
                    end
                end
                # IO sitting between escort and item on x-axis makes the serve harmful
                if iox > min(itemx, esc_x) && iox < max(itemx, esc_x)
                    for x in min(esc_x, iox):max(esc_x, iox)
                        if matrix[x, itemy] in allkeys
                            path_blocked = true; break
                        end
                    end
                end

                if !path_blocked || (ygap == 0 && ((esc_x < itemx && iox < itemx) || (esc_x > itemx && iox > itemx)))
                    itemscoords = generatefuturecoords(items, escorts, 1, escortid, itemid, matrix, item_io_x)
                    sameycoords = filter(x -> x[2] == itemy && x[1] >= min(itemx, esc_x) && x[1] <= max(itemx, esc_x), itemscoords)
                    minDist = minimum([abs(iox - coord[1]) + abs(ioy - coord[2]) for coord in sameycoords])
                    if minDist > length(keys(items)) + 1 ||
                        path_to_io_exists_if(matrix, itemscoords, item_io_x)
                        disty = ygap
                        closesty = itemid
                    else
                        if !haskey(thisescort.banset, iteration+1)
                            thisescort.banset[iteration+1] = [itemid]
                        else
                            push!(thisescort.banset[iteration+1], itemid)
                        end
                    end
                end
            end
        end

        # ── Y-DIRECTION: escort moves to item's x-column ───────────────────
        # Geometry here doesn't depend on which IO — escort just needs to be below item.
        # Use nearest assigned IO only for the path validation calls.
        if esc_y < itemy
            xgap = abs(esc_x - itemx)
            path_blocked = false; skipItem = false

            for (ox, oy) in other_escorts_coords
                if ox == itemx && oy < itemy
                    skipItem = true; break
                end
            end

            if !skipItem && xgap <= distx && xgap > 0
                for x in min(esc_x, itemx):max(esc_x, itemx)
                    if blockmat[x, esc_y] == 1 || matrix[x, esc_y] in allkeys
                        path_blocked = true; break
                    end
                end

                if !path_blocked || xgap == 0
                    item_io_y = argmin(io -> abs(io[1] - itemx) + abs(io[2] - itemy), assigned_ios)
                    iox, ioy = item_io_y
                    itemscoords = generatefuturecoords(items, escorts, 2, escortid, itemid, matrix, item_io_y)
                    samexcoords = filter(x -> x[1] == itemx && x[2] >= min(itemy, esc_y) && x[2] <= max(itemy, esc_y), itemscoords)
                    minDist = minimum([abs(iox - coord[1]) + abs(ioy - coord[2]) for coord in samexcoords])
                    if minDist > length(keys(items)) + 1 ||
                        path_to_io_exists_if(matrix, itemscoords, item_io_y)
                        distx = xgap
                        closestx = itemid
                    else
                        if !haskey(thisescort.banset, iteration+1)
                            thisescort.banset[iteration+1] = [itemid]
                        else
                            push!(thisescort.banset[iteration+1], itemid)
                        end
                    end
                end
            end
        end
    end

    # Urgent customers first
    for itemid in sorted_urgkeys
        try_serve_item!(itemid)
    end

    if distx < disty && closestx != 0
        if closestx in urgcusts; filter!(id -> id != closestx, urgcusts); end
        return true, (items[closestx].coords[1], esc_y)
    end
    if distx >= disty && closesty != 0
        if closesty in urgcusts; filter!(id -> id != closesty, urgcusts); end
        return true, (esc_x, items[closesty].coords[2])
    end

    # Then non-urgent
    for itemid in setdiff(sortedkeys, urgcusts)
        try_serve_item!(itemid)
    end

    if distx < disty && closestx != 0
        return true, (items[closestx].coords[1], esc_y)
    end
    if distx >= disty && closesty != 0
        return true, (esc_x, items[closesty].coords[2])
    end

    return false, (esc_x, esc_y)
end

function urgserve!(iteration, matrix, items, escorts, escortid, urgmats, IO)
    allkeys = setdiff(union(keys(escorts), keys(items)), [escortid])
    thisescort = escorts[escortid]
    esc_x, esc_y = thisescort.coords
    
    # MUST WE SERVE A CUSTOMER SOON? 3-4 Steps 
    if !isempty(keys(urgmats))
        urgentassignmentdict = Dict{String, Tuple{Int, Int, Int}}() # itemid, steps, x, y
        for urgitem in keys(urgmats)
            urgmat= urgmats[urgitem]
            urgx,urgy = items[urgitem].coords
            skip_urgitem = false
            for escid in keys(escorts)
                if escid == escortid
                    continue
                end
                otherescx, otherescy = escorts[escid].coords
                if urgmat[otherescx, otherescy] == 2
                    skip_urgitem = true
                    break
                end
            end
            if skip_urgitem
                continue
            end                 
            foundy = false; foundx = false; completedy = false; completedx = false; distance = Inf; dir = urgx > IO[1] ? -1 : 1
            candidy = 0; xin = deepcopy(esc_x); yin = deepcopy(esc_y); candidx = 0; gapy = Inf ; gapx = Inf
            if urgmat[esc_x, esc_y] == 2
                #println("Escort is 2 steps away from urgent item, should have served in previous step")
                continue 
            end
            while !completedy 
                if ( esc_x < urgx && IO[1] < urgx) ||
                    (esc_x > urgx && IO[1] > urgx)
                    completedy = true
                    break
                end
                if  (esc_y>=urgy)
                    for y in esc_y-1:-1:1
                        if urgmat[xin, y] == 2
                            candidy = y
                            gapy = abs(esc_y-y )
                            foundy = true
                            break
                        elseif urgmat[xin, y] == 1
                            foundy = false
                        end
                    end
                    if foundy || ( xin + dir < 1 ||
                        xin + dir > size(matrix, 1) ||
                            (dir == -1 && xin + dir <= urgx) ||
                            (dir == 1 && xin + dir > urgx))
                        completedy = true  # we cannot move anymore, if we havent found a 2 we cannot move
                    else
                        xin += dir
                    end
                elseif (esc_y < urgy-1) 
                    for y in esc_y+1:urgy-1
                        if urgmat[xin, y] == 2
                            candidy = y
                            gapy = abs(esc_y-y )
                            foundy = true
                            break
                        elseif urgmat[xin, y] == 1
                            foundy = false
                        end
                    end
                    if foundy || ( xin + dir < 1 ||
                        xin + dir > size(matrix, 1) ||
                            (dir == -1 && xin + dir <= urgx) ||
                            (dir == 1 && xin + dir > urgx))
                        completedy = true  # we cannot move anymore, if we havent found a 2 we cannot move
                    else
                        xin += dir
                    end
        
                else
                    completedy = true
                end
                
            end
            while !completedx
                if esc_y<=urgy
                    completedx = true
                    break
                end
                if esc_x>=urgx
                    if dir == -1 # escort on the right side or urg: IO-urg-esc
                        for x in esc_x-1:-1:IO[1]
                            if urgmat[x, esc_y] == 2
                                candidx = x
                                gapx = abs(esc_x - x)
                                foundx = true
                                break
                            elseif urgmat[x, esc_y] == 1
                                foundx = false
                                break
                            end
                        end
                    else # escort on the right side of urg : urg-esc-IO or urg-IO-esc
                        for x in esc_x-1:-1:urgx
                            if urgmat[x, esc_y] == 2
                                candidx = x
                                gapx = abs(esc_x - x)
                                foundx = true
                                break
                            elseif urgmat[x, esc_y] == 1
                                foundx = false
                                break
                            end
                        end
                    end
                    if foundx || yin -1 <= urgy
                        completedx = true # we cannot move anymore, if we havent found a 2 we cannot move
                    else
                        yin -= 1
                    end
                elseif esc_x<urgx-1
                    if dir ==1# escort left of item, item left of IO
                        for x in esc_x+1:IO[1]
                            if urgmat[x, esc_y] == 2
                                candidx = x
                                gapx = abs(esc_x - x)
                                foundx = true
                                break
                            elseif urgmat[x, esc_y] == 1
                                foundx = false
                            end
                        end
                    else # escort left of item, item right of IO
                        for x in esc_x+1:urgx-1
                            if urgmat[x, esc_y] == 2
                                candidx = x
                                gapx = abs(esc_x - x)
                                foundx = true
                                break
                            elseif urgmat[x, esc_y] == 1
                                foundx = false
                            end
                        end
                        for x in esc_x-1:-1:1
                            if urgmat[x, esc_y] == 2
                                gapotherx = abs(esc_x - x)
                                if gapotherx < gapx
                                    gapx = gapotherx
                                    candidx = x
                                end                                
                                foundx = true
                                break
                            elseif urgmat[x, esc_y] == 1
                                foundx = false
                            end
                        end
                    end
                    if foundx || yin -1 <= urgy
                        completedx = true # we cannot move anymore, if we havent found a 2 we cannot move
                    else
                        yin -= 1
                    end
                else
                    completedx = true
                end
            end
            if foundy && foundx
                onx = xin == esc_x ? 1 : 0
                ony = yin == esc_y ? 1 : 0
                if onx + ony == 2 # 3 step both fine
                    if gapx < gapy
                        candidx = esc_x 
                    else 
                        candidy = esc_y
                    end
                elseif onx == 1  # 3 step go down with escort
                    candidy = esc_y; distance = gapx
                elseif ony == 1 # 3 step go left in with escort (if escort right out of item)
                    candidx = esc_x;  distance = gapy
                else # 4 step 
                    gapx = gapx + 5*(abs(esc_y - yin))
                    gapy = gapy + 5*(abs(esc_x- xin))
                    if gapx < gapy
                        candidy = yin; candidx = esc_x ; distance = gapx
                    else
                        candidx = xin ; candidy = esc_y ; distance = gapy
                    end
                end
            elseif foundy
                onx = xin == esc_x ? 1 : 0
                if onx ==1 
                    candidx = esc_x ; distance = gapy
                else # 4 Step
                    gapy = gapy + 5*(abs(esc_x- xin))
                    candidx = xin ; candidy = esc_y ; distance = gapy
                end
            elseif foundx 
                ony = yin == esc_y ? 1 : 0
                if ony ==1 
                    candidy = yin; distance = gapx
                else # 4 Step
                    gapx = gapx + 5*(abs(esc_y - yin))
                    candidy = yin; candidx = esc_x;  distance = gapx # go down 
                end
            end
            # we check how many steps to get to a 2 in the matrix from the position and how far
            if distance != Inf && candidx != 0 && candidy!=0 && !(matrix[candidx, candidy] in keys(escorts))
                urgentassignmentdict[urgitem] =(distance , candidx,candidy) 
            end
        end

        if !isempty(urgentassignmentdict)
            min_distance = Inf
            min_key = ""
            min_tuple = ()
            for (key, value) in urgentassignmentdict
                if value[1] < min_distance
                    newx, newy = value[2], value[3]
                    skipthis = false
                    if esc_x == newx
                        ystart, yend = min(esc_y, newy), max(esc_y, newy)
                        for y in ystart:yend
                            if matrix[esc_x, y] in allkeys
                                skipthis = true
                                break
                            end
                        end
                    elseif esc_y == newy
                        xstart, xend = min(esc_x, newx), max(esc_x, newx)
                        for x in xstart:xend
                            if matrix[x, esc_y] in allkeys
                                skipthis = true
                                break
                            end
                        end
                    end
                    if skipthis
                        continue
                    elseif !((newx, newy) in escorts[escortid].tabu)
                        min_distance = value[1]
                        min_key = key
                        min_tuple = value
                    end
                end
            end 
            
            if  !isempty(min_tuple)
                delete!(urgmats, min_key)
                otheritems = setdiff(keys(urgentassignmentdict), [min_key])
                if !haskey(thisescort.banset, iteration+1)
                    thisescort.banset[iteration+1] = Vector{String}(collect(otheritems))
                else
                    append!(thisescort.banset[iteration+1], otheritems)
                end
                #println("$iteration :$escortid-> $min_key movement decided by urgency policy")
                return true, (min_tuple[2], min_tuple[3]) # we also need some sort of commitment. using the banset I assume TODO 
            end
        end 
    end
   
    return false, (esc_x, esc_y ) # cannot move
end
function urgserve_multi_io!(iteration, matrix, items, escorts, escortid, urgmats, item_to_ios, all_ios)
    allkeys = setdiff(union(keys(escorts), keys(items)), [escortid])
    thisescort = escorts[escortid]
    esc_x, esc_y = thisescort.coords

    if !isempty(keys(urgmats))
        urgentassignmentdict = Dict{String, Tuple{Int, Int, Int}}()
        for urgitem in keys(urgmats)
            urgmat = urgmats[urgitem]
            urgx, urgy = items[urgitem].coords

            # Look up this item's assigned IO — same choice as urgmats_multi_io used
            assigned = get(item_to_ios, urgitem, all_ios)
            item_io = argmin(io -> abs(io[1] - urgx), assigned)
            iox, ioy = item_io   # replaces IO[1]/IO[2] everywhere below

            skip_urgitem = false
            for escid in keys(escorts)
                if escid == escortid; continue; end
                otherescx, otherescy = escorts[escid].coords
                if urgmat[otherescx, otherescy] == 2
                    skip_urgitem = true; break
                end
            end
            if skip_urgitem; continue; end

            foundy = false; foundx = false; completedy = false; completedx = false
            distance = Inf
            dir = urgx > iox ? -1 : 1    # was: urgx > IO[1]
            candidy = 0; xin = deepcopy(esc_x); yin = deepcopy(esc_y)
            candidx = 0; gapy = Inf; gapx = Inf

            if urgmat[esc_x, esc_y] == 2
                continue
            end

            while !completedy
                if (esc_x < urgx && iox < urgx) ||    # was IO[1] < urgx
                    (esc_x > urgx && iox > urgx)       # was IO[1] > urgx
                    completedy = true; break
                end
                if esc_y >= urgy
                    for y in esc_y-1:-1:1
                        if urgmat[xin, y] == 2
                            candidy = y; gapy = abs(esc_y - y); foundy = true; break
                        elseif urgmat[xin, y] == 1
                            foundy = false
                        end
                    end
                    if foundy || (xin + dir < 1 || xin + dir > size(matrix, 1) ||
                        (dir == -1 && xin + dir <= urgx) || (dir == 1 && xin + dir > urgx))
                        completedy = true
                    else
                        xin += dir
                    end
                elseif esc_y < urgy - 1
                    for y in esc_y+1:urgy-1
                        if urgmat[xin, y] == 2
                            candidy = y; gapy = abs(esc_y - y); foundy = true; break
                        elseif urgmat[xin, y] == 1
                            foundy = false
                        end
                    end
                    if foundy || (xin + dir < 1 || xin + dir > size(matrix, 1) ||
                        (dir == -1 && xin + dir <= urgx) || (dir == 1 && xin + dir > urgx))
                        completedy = true
                    else
                        xin += dir
                    end
                else
                    completedy = true
                end
            end

            while !completedx
                if esc_y <= urgy; completedx = true; break; end
                if esc_x >= urgx
                    if dir == -1  # IO-urg-esc: search left toward IO
                        for x in esc_x-1:-1:iox    # was IO[1]
                            if urgmat[x, esc_y] == 2
                                candidx = x; gapx = abs(esc_x - x); foundx = true; break
                            elseif urgmat[x, esc_y] == 1
                                foundx = false; break
                            end
                        end
                    else  # urg-esc-IO or urg-IO-esc: search left toward item
                        for x in esc_x-1:-1:urgx
                            if urgmat[x, esc_y] == 2
                                candidx = x; gapx = abs(esc_x - x); foundx = true; break
                            elseif urgmat[x, esc_y] == 1
                                foundx = false; break
                            end
                        end
                    end
                    if foundx || yin - 1 <= urgy; completedx = true; else; yin -= 1; end
                elseif esc_x < urgx - 1
                    if dir == 1  # escort left of item, item left of IO: search right toward IO
                        for x in esc_x+1:iox    # was IO[1]
                            if urgmat[x, esc_y] == 2
                                candidx = x; gapx = abs(esc_x - x); foundx = true; break
                            elseif urgmat[x, esc_y] == 1
                                foundx = false
                            end
                        end
                    else  # escort left of item, item right of IO
                        for x in esc_x+1:urgx-1
                            if urgmat[x, esc_y] == 2
                                candidx = x; gapx = abs(esc_x - x); foundx = true; break
                            elseif urgmat[x, esc_y] == 1
                                foundx = false
                            end
                        end
                        for x in esc_x-1:-1:1
                            if urgmat[x, esc_y] == 2
                                gapotherx = abs(esc_x - x)
                                if gapotherx < gapx; gapx = gapotherx; candidx = x; end
                                foundx = true; break
                            elseif urgmat[x, esc_y] == 1
                                foundx = false
                            end
                        end
                    end
                    if foundx || yin - 1 <= urgy; completedx = true; else; yin -= 1; end
                else
                    completedx = true
                end
            end

            # Distance scoring and candidate selection — unchanged from urgserve!
            if foundy && foundx
                onx = xin == esc_x ? 1 : 0; ony = yin == esc_y ? 1 : 0
                if onx + ony == 2
                    if gapx < gapy; candidx = esc_x; else; candidy = esc_y; end
                elseif onx == 1
                    candidy = esc_y; distance = gapx
                elseif ony == 1
                    candidx = esc_x; distance = gapy
                else
                    gapx = gapx + 5*(abs(esc_y - yin)); gapy = gapy + 5*(abs(esc_x - xin))
                    if gapx < gapy; candidy = yin; candidx = esc_x; distance = gapx
                    else; candidx = xin; candidy = esc_y; distance = gapy; end
                end
            elseif foundy
                onx = xin == esc_x ? 1 : 0
                if onx == 1; candidx = esc_x; distance = gapy
                else; gapy = gapy + 5*(abs(esc_x - xin)); candidx = xin; candidy = esc_y; distance = gapy; end
            elseif foundx
                ony = yin == esc_y ? 1 : 0
                if ony == 1; candidy = yin; distance = gapx
                else; gapx = gapx + 5*(abs(esc_y - yin)); candidy = yin; candidx = esc_x; distance = gapx; end
            end
            if distance != Inf && candidx != 0 && candidy != 0 && !(matrix[candidx, candidy] in keys(escorts))
                urgentassignmentdict[urgitem] = (distance, candidx, candidy)
            end
        end

        if !isempty(urgentassignmentdict)
            min_distance = Inf; min_key = ""; min_tuple = ()
            for (key, value) in urgentassignmentdict
                if value[1] < min_distance
                    newx, newy = value[2], value[3]; skipthis = false
                    if esc_x == newx
                        for y in min(esc_y, newy):max(esc_y, newy)
                            if matrix[esc_x, y] in allkeys; skipthis = true; break; end
                        end
                    elseif esc_y == newy
                        for x in min(esc_x, newx):max(esc_x, newx)
                            if matrix[x, esc_y] in allkeys; skipthis = true; break; end
                        end
                    end
                    if skipthis; continue
                    elseif !((newx, newy) in escorts[escortid].tabu)
                        min_distance = value[1]; min_key = key; min_tuple = value
                    end
                end
            end
            if !isempty(min_tuple)
                delete!(urgmats, min_key)
                otheritems = setdiff(keys(urgentassignmentdict), [min_key])
                if !haskey(thisescort.banset, iteration+1)
                    thisescort.banset[iteration+1] = Vector{String}(collect(otheritems))
                else
                    append!(thisescort.banset[iteration+1], otheritems)
                end
                return true, (min_tuple[2], min_tuple[3])
            end
        end
    end
    return false, (esc_x, esc_y)
end
function freeroam!(iteration, matrix, items, escorts, escortid, blockmat, IO)
    strategy = IO[1] == 1 ? 1 : IO[1] == size(matrix, 1) ? 3 : 2 # 1: left, 2: middle, 3: right
    
    thisescort = escorts[escortid]
    esc_x, esc_y = thisescort.coords
    avgesc_x = length(keys(escorts)) > 1 ? mean([escorts[esc].coords[1] for esc in keys(escorts) if esc != escortid]) : esc_x
    if strategy ==2 && avgesc_x<IO[1]
        strategy = 3 # if most escorts are on the left we prefer staying as right as possible while moving left
    elseif strategy ==2 && avgesc_x>IO[1]
        strategy = 1# if most escorts are on the right we prefer staying as left as possible while moving right
    end
    moveitnow = false
    if escorts[escortid].lastmoved <= iteration-2 
        moveitnow = true
    end
  
    # FREE ROAM; GO SOMEWHERE ELSE/FREE IF POSSIBLE
    
    worked, asternmat = outwards_astar_with_dirchange(matrix, IO, blockmat,escortid,escorts,items)
    if esc_x == IO[1] && esc_y == IO[2]
        return true, (esc_x, esc_y) # best place it could be 
    elseif esc_x == IO[1] # down, outwards, 
        maxmove_y = checkasternmat(blockmat, matrix, -2, escortid, strategy, escorts, items,IO, asternmat)
        if (maxmove_y == esc_y) || matrix[esc_x, maxmove_y ] in keys(escorts) || (esc_x, maxmove_y) in thisescort.tabu #cannot move down enough , move out of the way right or left 
            avg_x = mean([items[item].coords[1] for item in keys(items)]) # where are the items ? 
            diresc= avg_x <= IO[1] ? 1 : -1 # if items are left we go right, vice versa
            for _ in 1:2 # Try both directions if the first choice fails
                if diresc == 1 || IO[1] ==1 # chose right
                    maxmove = size(matrix, 1)
                    maxmove = checkmatrixforblock!(blockmat, matrix, diresc, escortid, strategy, iteration, escorts, items, IO)
                    if (maxmove > esc_x && !(matrix[maxmove, esc_y] in keys(escorts)))&& !((maxmove, esc_y) in thisescort.tabu) # can move right
                        return true, (maxmove, esc_y)
                    end
                elseif diresc == -1 || IO[1] == size(matrix,1)# chose left
                    maxmove = 1
                    maxmove = checkmatrixforblock!(blockmat, matrix, diresc, escortid, strategy, iteration, escorts, items,IO)
                    if (maxmove < esc_x && !(matrix[maxmove, esc_y] in keys(escorts)))&& !((maxmove, esc_y) in thisescort.tabu) # can move left
                        return true, (maxmove, esc_y)
                    end
                end
                diresc = -diresc # Switch direction
            end 
            if moveitnow # side is also blocked. so now we couldnt move down or sideways
                minup = checkmatrixforblock!(blockmat, matrix, 2, escortid, strategy, iteration, escorts, items,IO)
                if minup > esc_y
                    return true, (esc_x, minup)
                end
            end

        else
            return true, (esc_x, maxmove_y)
        end
    elseif esc_y == IO[2] # go in X direction towards IO , if blocked go up, if must move go outwards 
        if esc_x < IO[1] # io on the right
            maxmove_x = checkasternmat( blockmat, matrix, 1, escortid, strategy, escorts, items,IO, asternmat)
            if maxmove_x == esc_x || matrix[maxmove_x, esc_y] in keys(escorts) || (maxmove_x, esc_y) in thisescort.tabu 
                minup = asternmat[esc_x,esc_y+1] != Inf ? checkasternmat(blockmat, matrix, 2, escortid, strategy, escorts, items,IO, asternmat) :
                    checkmatrixforblock!(blockmat, matrix, 2, escortid, strategy, iteration, escorts, items,IO)
                if minup > esc_y
                    return true, (esc_x, minup)
                elseif moveitnow 
                    maxmove_x = checkasternmat( blockmat, matrix, -1, escortid, strategy, escorts, items,IO, asternmat)
                    if maxmove_x == esc_x || matrix[maxmove_x, esc_y] in keys(escorts) || (maxmove_x, esc_y) in thisescort.tabu 
                        return true, (maxmove_x, esc_y)
                    end
                end
            end                
        else # io on the left
            maxmove_x = checkasternmat( blockmat, matrix, -1, escortid, strategy, escorts, items,IO, asternmat)
            if maxmove_x == esc_x || matrix[maxmove_x, esc_y] in keys(escorts) || (maxmove_x, esc_y) in thisescort.tabu 
                minup = asternmat[esc_x,esc_y+1] != Inf ? checkasternmat(blockmat, matrix, 2, escortid, strategy, escorts, items,IO, asternmat) :
                    checkmatrixforblock!(blockmat, matrix, 2, escortid, strategy, iteration, escorts, items,IO)
                if minup > esc_y
                    return true, (esc_x, minup)
                elseif moveitnow 
                    maxmove_x = checkasternmat( blockmat, matrix, 1, escortid, strategy, escorts, items,IO, asternmat)
                    if maxmove_x == esc_x || matrix[maxmove_x, esc_y] in keys(escorts) || (maxmove_x, esc_y) in thisescort.tabu 
                        return true,(maxmove_x, esc_y)
                    end
                end
            end     
        end  
        return true, (maxmove_x, esc_y)
    else # not at IO coords # down, inwards, upwards, outwards
        avg_x = mean([items[item].coords[1] for item in keys(items)])
        dirx= avg_x <= IO[1] ? 1 : -1 # try go to the opposite direction of the items to be able to serve them
        iodir = dirx
        maxmove_y = checkasternmat(blockmat, matrix, -2, escortid, strategy, escorts, items,IO, asternmat)#checkmatrixforblock!(blockmat, matrix, 1, -2, escortid, strategy, iteration, escorts, items,IO)
        if (maxmove_y == esc_y) || matrix[esc_x, maxmove_y ] in keys(escorts) || (esc_x, maxmove_y) in thisescort.tabu# cannot move down enough , move out of the way right or left 
            for _ in 1:2 
                if dirx == 1 # chose right
                    maxmove = iodir == dirx ?  # if asternmat can be used we use it
                            checkasternmat( blockmat, matrix, dirx, escortid, strategy, escorts, items,IO, asternmat) :
                            checkmatrixforblock!(blockmat, matrix, dirx, escortid, strategy, iteration, escorts, items,IO)
                    if maxmove > esc_x && !(matrix[maxmove, esc_y] in keys(escorts)) && !((maxmove, esc_y) in thisescort.tabu) # can move right
                        return true, (maxmove, esc_y)
                    end
                elseif dirx == -1 # chose left
                    maxmove = iodir == dirx ? 
                            checkasternmat( blockmat, matrix, dirx, escortid, strategy, escorts, items,IO, asternmat) :
                            checkmatrixforblock!(blockmat, matrix, dirx, escortid, strategy, iteration, escorts, items,IO)
                    if (maxmove < esc_x && !(matrix[maxmove, esc_y] in keys(escorts))) && !((maxmove, esc_y) in thisescort.tabu) # can move left
                        return true, (maxmove, esc_y)
                    end
                end
                dirx = -dirx
            end
        else # can go down
            return true, (esc_x, maxmove_y)
        end
        if moveitnow # must move so we try up
            minup = checkmatrixforblock!(blockmat, matrix, 2, escortid, strategy, iteration, escorts, items,IO)
            if minup > esc_y
                return true,(esc_x, minup)
            end
        end
        
    end
    
    return false , (esc_x, esc_y ) # cannot move
end
function freeroam_dumb!(iteration, matrix, items, escorts, escortid, blockmat, IO)
    strategy = IO[1] == 1 ? 1 : IO[1] == size(matrix, 1) ? 3 : 2 # 1: left, 2: middle, 3: right
    
    thisescort = escorts[escortid]
    esc_x, esc_y = thisescort.coords
    avgesc_x = length(keys(escorts)) > 1 ? mean([escorts[esc].coords[1] for esc in keys(escorts) if esc != escortid]) : esc_x
    if strategy ==2 && avgesc_x<IO[1]
        strategy = 3 # if most escorts are on the left we prefer staying as right as possible while moving left
    elseif strategy ==2 && avgesc_x>IO[1]
        strategy = 1# if most escorts are on the right we prefer staying as left as possible while moving right
    end
    moveitnow = false
    if escorts[escortid].lastmoved <= iteration-2 
        moveitnow = true
    end
  
    # FREE ROAM; GO SOMEWHERE ELSE/FREE IF POSSIBLE
    
    worked, asternmat = outwards_astar_with_dirchange(matrix, IO, blockmat,escortid,escorts,items)
    if esc_x == IO[1] && esc_y == IO[2]
        return true, (esc_x, esc_y) # best place it could be 
    elseif esc_x == IO[1] # down, outwards, 
        maxmove_y = checkasternmat(blockmat, matrix, -2, escortid, strategy, escorts, items,IO, asternmat)
        if (maxmove_y == esc_y) || matrix[esc_x, maxmove_y ] in keys(escorts) || (esc_x, maxmove_y) in thisescort.tabu #cannot move down enough , move out of the way right or left 
            avg_x = mean([items[item].coords[1] for item in keys(items)]) # where are the items ? 
            diresc= avg_x <= IO[1] ? 1 : -1 # if items are left we go right, vice versa
            for _ in 1:2 # Try both directions if the first choice fails
                if diresc == 1 || IO[1] ==1 # chose right
                    maxmove = size(matrix, 1)
                    maxmove = checkmatrixforblock!(blockmat, matrix, diresc, escortid, strategy, iteration, escorts, items, IO)
                    if (maxmove > esc_x && !(matrix[maxmove, esc_y] in keys(escorts)))&& !((maxmove, esc_y) in thisescort.tabu) # can move right
                        return true, (maxmove, esc_y)
                    end
                elseif diresc == -1 || IO[1] == size(matrix,1)# chose left
                    maxmove = 1
                    maxmove = checkmatrixforblock!(blockmat, matrix, diresc, escortid, strategy, iteration, escorts, items,IO)
                    if (maxmove < esc_x && !(matrix[maxmove, esc_y] in keys(escorts)))&& !((maxmove, esc_y) in thisescort.tabu) # can move left
                        return true, (maxmove, esc_y)
                    end
                end
                diresc = -diresc # Switch direction
            end 
            if moveitnow # side is also blocked. so now we couldnt move down or sideways
                minup = checkmatrixforblock!(blockmat, matrix, 2, escortid, strategy, iteration, escorts, items,IO)
                if minup > esc_y
                    return true, (esc_x, minup)
                end
            end

        else
            return true, (esc_x, maxmove_y)
        end
    elseif esc_y == IO[2] # go in X direction towards IO , if blocked go up, if must move go outwards 
        if esc_x < IO[1] # io on the right
            maxmove_x = checkasternmat( blockmat, matrix, 1, escortid, strategy, escorts, items,IO, asternmat)
            if maxmove_x == esc_x || matrix[maxmove_x, esc_y] in keys(escorts) || (maxmove_x, esc_y) in thisescort.tabu 
                minup = asternmat[esc_x,esc_y+1] != Inf ? checkasternmat(blockmat, matrix, 2, escortid, strategy, escorts, items,IO, asternmat) :
                    checkmatrixforblock!(blockmat, matrix, 2, escortid, strategy, iteration, escorts, items,IO)
                if minup > esc_y
                    return true, (esc_x, minup)
                elseif moveitnow 
                    maxmove_x = checkasternmat( blockmat, matrix, -1, escortid, strategy, escorts, items,IO, asternmat)
                    if maxmove_x == esc_x || matrix[maxmove_x, esc_y] in keys(escorts) || (maxmove_x, esc_y) in thisescort.tabu 
                        return true, (maxmove_x, esc_y)
                    end
                end
            end                
        else # io on the left
            maxmove_x = checkasternmat( blockmat, matrix, -1, escortid, strategy, escorts, items,IO, asternmat)
            if maxmove_x == esc_x || matrix[maxmove_x, esc_y] in keys(escorts) || (maxmove_x, esc_y) in thisescort.tabu 
                minup = asternmat[esc_x,esc_y+1] != Inf ? checkasternmat(blockmat, matrix, 2, escortid, strategy, escorts, items,IO, asternmat) :
                    checkmatrixforblock!(blockmat, matrix, 2, escortid, strategy, iteration, escorts, items,IO)
                if minup > esc_y
                    return true, (esc_x, minup)
                elseif moveitnow 
                    maxmove_x = checkasternmat( blockmat, matrix, 1, escortid, strategy, escorts, items,IO, asternmat)
                    if maxmove_x == esc_x || matrix[maxmove_x, esc_y] in keys(escorts) || (maxmove_x, esc_y) in thisescort.tabu 
                        return true,(maxmove_x, esc_y)
                    end
                end
            end     
        end  
        return true, (maxmove_x, esc_y)
    else # not at IO coords # down, inwards, upwards, outwards
        avg_x = mean([items[item].coords[1] for item in keys(items)])
        dirx= avg_x <= IO[1] ? 1 : -1 # try go to the opposite direction of the items to be able to serve them
        iodir = dirx
        maxmove_y = checkmatrixforblock!(blockmat, matrix, -2, escortid, strategy, iteration, escorts, items,IO)#checkmatrixforblock!(blockmat, matrix, 1, -2, escortid, strategy, iteration, escorts, items,IO)
        if (maxmove_y == esc_y) || matrix[esc_x, maxmove_y ] in keys(escorts) || (esc_x, maxmove_y) in thisescort.tabu# cannot move down enough , move out of the way right or left 
            for _ in 1:2 
                if dirx == 1 # chose right
                    maxmove = iodir == dirx ?  # if asternmat can be used we use it
                            checkasternmat( blockmat, matrix, dirx, escortid, strategy, escorts, items,IO, asternmat) :
                            checkmatrixforblock!(blockmat, matrix, dirx, escortid, strategy, iteration, escorts, items,IO)
                    if maxmove > esc_x && !(matrix[maxmove, esc_y] in keys(escorts)) && !((maxmove, esc_y) in thisescort.tabu) # can move right
                        return true, (maxmove, esc_y)
                    end
                elseif dirx == -1 # chose left
                    maxmove = iodir == dirx ? 
                            checkasternmat( blockmat, matrix, dirx, escortid, strategy, escorts, items,IO, asternmat) :
                            checkmatrixforblock!(blockmat, matrix, dirx, escortid, strategy, iteration, escorts, items,IO)
                    if (maxmove < esc_x && !(matrix[maxmove, esc_y] in keys(escorts))) && !((maxmove, esc_y) in thisescort.tabu) # can move left
                        return true, (maxmove, esc_y)
                    end
                end
                dirx = -dirx
            end
        else # can go down
            return true, (esc_x, maxmove_y)
        end
        if moveitnow # must move so we try up
            minup = checkmatrixforblock!(blockmat, matrix, 2, escortid, strategy, iteration, escorts, items,IO)
            if minup > esc_y
                return true,(esc_x, minup)
            end
        end
        
    end
    
    return false , (esc_x, esc_y ) # cannot move
end
function checkasternmat(blockmat, matrix, diresc, escortid, strategy, escorts, items, IO,asternmat)
    allkeys = setdiff(union(keys(escorts), keys(items)), [escortid])
    esc_x, esc_y = escorts[escortid].coords
    
    if diresc == 1 
        valid_x_1 = [x for x in esc_x:size(matrix,1) if (blockmat[x, esc_y] == 1 || matrix[x, esc_y] in allkeys)] # right
        if (isempty(valid_x_1) || minimum(valid_x_1) > esc_x+1)
            maxmove = isempty(valid_x_1) ?  size(matrix,1) : minimum(valid_x_1)-1
            valy = asternmat[esc_x, esc_y]+1 ;currmin = asternmat[esc_x, esc_y]
            if strategy == 1 # going right, we prefer as left as possible 
                for x in esc_x:maxmove
                    currval = asternmat[x, esc_y]
                    if currval < valy
                        maxmove = x
                        valy = currval
                    end
                end
            else
                for x in maxmove:-1:esc_x # backwards, as we want to move as far right as we can 
                    currval = asternmat[x, esc_y]
                    if currval < valy
                        maxmove = x
                        valy = currval
                    end
                end
            end 
            if valy >= currmin +1
                return esc_x
            else
                return maxmove
            end
        else 
            return esc_x
        end
    end
    if diresc == -1 # going left checking 
        valid_x_1m = [x for x in esc_x:-1:1 if (blockmat[x, esc_y] == 1 || matrix[x, esc_y] in allkeys)] # left
        if (isempty(valid_x_1m) || maximum(valid_x_1m) < esc_x-1) # can move left
            maxmove = isempty(valid_x_1m) ? 1 : (maximum(valid_x_1m)+1)
            valy = asternmat[esc_x, esc_y]+1 ;currmin = asternmat[esc_x, esc_y]
            if strategy == 3 # prefer near rightside IO
                for x in esc_x:-1:maxmove
                    currval = asternmat[x, esc_y]
                    if currval < valy
                        maxmove = x
                        valy = currval
                    end
                end
            else
                for x in maxmove:esc_x # prefer far out
                    currval = asternmat[x, esc_y]
                    if currval < valy
                        maxmove = x
                        valy = currval
                    end
                end
            end
            if valy >= currmin +1
                return esc_x
            else
                return maxmove
            end
        else 
            return esc_x
        end
    end
    if diresc == 2# lowest possible y
        valid_y= [y for y in esc_y:size(matrix,2) if (blockmat[esc_x, y] == 1 || matrix[esc_x, y] in allkeys)] # up 
        if isempty(valid_y) || minimum(valid_y) - 1 > esc_y # can move up
            minup = isempty(valid_y) ? size(matrix, 2) : minimum(valid_y) - 1 
            min_val = Inf
            min_idx = esc_y
            currmin = asternmat[esc_x, esc_y]
            for y in esc_y:minup 
                if asternmat[esc_x, y] < min_val && y != esc_y
                    min_val = asternmat[esc_x, y]
                    min_idx = y
                end
            end
            if min_val >= currmin +1
                return esc_y
            else
                return min_idx
            end
        else 
            return esc_y
        end
    end
    if diresc == -2 # lowest possible y
        valid_y= [y for y in IO[2]:esc_y-1 if (blockmat[esc_x, y] == 1 || matrix[esc_x, y] in allkeys)] # up 
        if (isempty(valid_y) || maximum(valid_y)+1 < esc_y) # can move up
            range1 = isempty(valid_y) ? IO[2] : maximum(valid_y)+1
            min_val, min_idx = Inf, esc_y; currmin = asternmat[esc_x, esc_y]
            for y in range1:esc_y
                if asternmat[esc_x, y] < min_val
                    min_val = asternmat[esc_x, y]
                    min_idx = y
                end
            end
            if min_val >= currmin +1
                return esc_y
            else
                return min_idx
            end
        else 
            return esc_y
        end
    end
    
    
    
    return maxmove

end
function checkmatrixforblock!(blockmat, matrix, diresc, escortid, strategy, iteration, escorts, items, IO)
    allkeys = setdiff(union(keys(escorts), keys(items)), [escortid])
    esc_x, esc_y = escorts[escortid].coords
    
    if diresc == 1 
        valid_x_1 = [x for x in esc_x:size(matrix,1) if (blockmat[x, esc_y] == 1 || matrix[x, esc_y] in allkeys)] # right
        if (isempty(valid_x_1) || minimum(valid_x_1) > esc_x+1)
            maxmove = isempty(valid_x_1) ?  size(matrix,1) : minimum(valid_x_1)-1
            valy = esc_y
            if strategy == 1 # prefer near leftside IO
                for x in esc_x:maxmove
                    candheight = directionval(matrix, items, escorts, escortid, x, esc_y, 2, iteration,IO) 
                    if candheight < valy
                        maxmove = x
                        valy = candheight
                    end
                end
            else
                for x in maxmove:-1:esc_x # backwards, as we want to move as far right as we can 
                    candheight = directionval(matrix, items, escorts, escortid, x, esc_y, 2, iteration,IO) 
                    if candheight < valy
                        maxmove = x
                        valy = candheight
                    end
                end
            end
            return maxmove
        else 
            return esc_x
        end
    end
    if diresc == -1 # going left checking 
        valid_x_1m = [x for x in esc_x:-1:1 if (blockmat[x, esc_y] == 1 || matrix[x, esc_y] in allkeys)] # left
        if (isempty(valid_x_1m) || maximum(valid_x_1m) < esc_x-1) # can move left
            maxmove = isempty(valid_x_1m) ? 1 : (maximum(valid_x_1m)+1)
            valy = esc_y
            if strategy == 3 # prefer near rightside IO
                for x in esc_x:-1:maxmove
                    candheight = directionval(matrix, items, escorts, escortid, x, esc_y, 2, iteration,IO) 
                    if candheight < valy
                        maxmove = x
                        valy = candheight
                    end
                end
            else
                for x in maxmove:esc_x # prefer far out
                    candheight = directionval(matrix, items, escorts, escortid, x, esc_y, 2, iteration,IO) 
                    if candheight < valy
                        maxmove = x
                        valy = candheight
                    end
                end
            end
            return maxmove
        else 
            return esc_x
        end
    end
    if diresc == 2# lowest possible y
        valid_y= [y for y in esc_y:size(matrix,2) if (blockmat[esc_x, y] == 1 || matrix[esc_x, y] in allkeys)] # up 
        if (isempty(valid_y) || minimum(valid_y)-1 > esc_y) # can move up
            minup = isempty(valid_y) ? size(matrix, 2) : minimum(valid_y)-1 
            for y in esc_y:minup
                if directionclear(items, escorts,escortid, esc_x,y, 1, iteration,IO)
                    minup = y
                    break
                end
            end
            return minup
        else 
            return esc_y
        end
    end
    if diresc == -2 # lowest possible y
        reach = 2 # reach is the left right checking reach in this case. 
        valid_y= [y for y in IO[2]:esc_y-1 if (blockmat[esc_x, y] == 1 || matrix[esc_x, y] in allkeys)] # up 
        if (isempty(valid_y) || maximum(valid_y)+1 < esc_y) # can move up
            range1 = isempty(valid_y) ? IO[2] : maximum(valid_y)+1
            maxdown = esc_y
            for y in range1:esc_y
                if directionclear(items, escorts,escortid, esc_x,y, 1, reach, iteration,IO)
                    maxdown = y
                    break
                end
            end
            return maxdown
        else 
            return esc_y
        end
    end
    
    
    
    return maxmove

end

function directionval( matrix, items, escorts, escortid, coordx, coordy, direction, iteration,IO)
    iox, ioy = IO
    valy = 1 ; valx = 1
    allkeys = setdiff(union(keys(escorts), keys(items)), [escortid])
    if direction ==1 # we give y coord and tell to check 
        for entity in allkeys # check for presence in both collections in the front          
            if haskey(escorts, entity)
                esc_other = escorts[entity]
                if (esc_other.coords[2] == coordy && esc_other.lastmoved == iteration)  # iteration as escort will probably move
                    if (esc_other.coords[1] < min(iox, coordx) || esc_other.coords[1] > max(iox, coordx)) # acceptable if on the other side of iox
                        continue
                    end
                    return false
                end
            elseif haskey(items, entity)
                item_other = items[entity]
                if item_other.coords[2] == coordy
                    if (coordx == iox) ||
                        (coordx > min(item_other.coords[1], iox) && coordx < max(item_other.coords[1], iox))
                        #println(" item:$(entity) can be served by escort:$escortid , shouldnt have happened unless path blocked after move")
                        continue
                    end
                    return false
                end
            end
        end
        return valx
    elseif direction ==2 # we give x coord and tell to check lower y, as we wish to not hurt anything
        if coordy>1
            for y in coordy-1:-1:1
                if matrix[coordx, y] in allkeys
                    valy = y+1
                end
            end
        end
        return valy
    end
    
end
"""
while we check where to move the escort so that we can make another move in the next iteration 

    example: I want to move escort up as its blocked here. i want to check where up can i move so that i can move left/right in the next iteration
"""
function directionclear( items, escorts, escortid, coordx, coordy, direction, iteration,IO)
    iox, ioy = IO
    allkeys = setdiff(union(keys(escorts), keys(items)), [escortid])
    if direction ==1 # we give y coord and tell to check 
        for entity in allkeys # check for presence in both collections in the front          
            if haskey(escorts, entity)
                esc_other = escorts[entity]
                if (esc_other.coords[2] == coordy && esc_other.lastmoved == iteration)  # iteration as escort will probably move
                    if (esc_other.coords[1] < min(iox, coordx) || esc_other.coords[1] > max(iox, coordx)) # acceptable if on the other side of iox
                        continue
                    end
                    return false
                end
            elseif haskey(items, entity)
                item_other = items[entity]
                if item_other.coords[2] == coordy
                    if (coordx == iox) ||
                        (coordx > min(item_other.coords[1], iox) && coordx < max(item_other.coords[1], iox))
                        #println(" item:$(entity) can be served by escort:$escortid , shouldnt have happened unless path blocked after move")
                        continue
                    end
                    return false
                end
            end
        end
        
    elseif direction ==2 # we give x coord and tell to check lower y, as we wish to not hurt anything
        for entity in allkeys # check for presence in both collections in the front
            if haskey(escorts, entity)
                esc_other = escorts[entity]
                if (esc_other.coords[1] == coordx && esc_other.lastmoved == iteration) # iteration as escort will probably move
                    return false
                end
            elseif haskey(items, entity)
                item_other = items[entity]
                if item_other.coords[1] == coordx && item_other.coords[2] < coordy 
                    return false
                end
            end
        end
    end
    return true
end

function directionclear( items, escorts, escortid, coordx, coordy, direction, reach, iteration,IO)
    iox, ioy = IO
    dir = iox < coordx ? -1 : 1
    dir = iox == coordx ? 0 : dir
    allkeys = setdiff(union(keys(escorts), keys(items)), [escortid])
    if direction ==1 # we give y coord and tell to check 
        for entity in allkeys # check for presence in both collections in the front          
            if haskey(escorts, entity)
                esc_other = escorts[entity]
                if (esc_other.coords[2] == coordy && esc_other.lastmoved == iteration)  # iteration as escort will probably move
                    if (esc_other.coords[1] < min(iox, coordx) || esc_other.coords[1] > max(iox, coordx)) # acceptable if on the other side of iox
                        continue
                    elseif (esc_other.coords[1] >= (coordx - reach) && esc_other.coords[1] <= (coordx + reach))
                        return false
                    end
                end
            elseif haskey(items, entity)
                item_other = items[entity]
                if (
                    item_other.coords[2] == coordy &&
                    dir == -1 &&
                    item_other.coords[1] >= (coordx - reach) &&
                    item_other.coords[1] <= coordx
                ) ||
                (
                    item_other.coords[2] == coordy &&
                    dir == 1 &&
                    item_other.coords[1] >= coordx &&
                    item_other.coords[1] <= (coordx + reach)
                )
                    
                    return false
                end
            end
        end
        
    elseif direction ==2 # we give x coord and tell to check lower y, as we wish to not hurt anything
        for entity in allkeys # check for presence in both collections in the front
            if haskey(escorts, entity)
                esc_other = escorts[entity]
                if (esc_other.coords[1] == coordx  &&
                     esc_other.coords[2] >=(coordy - reach) && esc_other.coords[2] <= (coordy))  # iteration as escort will probably move
                    return false
                end
            elseif haskey(items, entity)
                item_other = items[entity]
                if item_other.coords[1] == coordx && 
                    item_other.coords[2] >= coordy-reach &&
                    item_other.coords[2] <= coordy + reach   
                    return false
                end
            end
        end
    end
    return true

end
"""
some items on the way may also be moved (doubleserve) and the doubleserve migh block IO
"""
function generatefuturecoords(items,  escorts,dir, escortid, itemid, matrix, IO) 
    item = items[itemid]
    itemx, itemy = item.coords
    esc_x, esc_y = escorts[escortid].coords
    itemscoords = []
    if dir==2
        for o_itemid in keys(items)
            if o_itemid == itemid
                continue
            else
                o_item = items[o_itemid]
                o_itemx, o_itemy = o_item.coords
                if o_itemx == itemx && o_itemy < itemy && o_itemy > esc_y
                    push!(itemscoords, (o_itemx, (max(1,(o_itemy-1)))))
                else
                    push!(itemscoords, (o_itemx, o_itemy))
                end
            end
        end
        push!(itemscoords,(itemx, (max(1,(itemy-1)))))
    elseif dir==1
        futurecoords = (itemx, itemy)
        dir = IO[1] < itemx ? -1 : 1
        if dir == 1
            futurecoords = (min(itemx+1,size(matrix, 1)), itemy)
        else
            futurecoords = (max(itemx-1,1), itemy)
        end
        for o_itemid in keys(items)
            if o_itemid == itemid
                continue
            else
                o_item = items[o_itemid]
                o_itemx, o_itemy = o_item.coords
                if o_itemy == itemy &&(( o_itemx < itemx && o_itemx > esc_x) || (o_itemx > itemx && esc_x > o_itemx))
                    push!(itemscoords, (o_itemx+dir, o_itemy))
                else
                    push!(itemscoords, (o_itemx, o_itemy))
                end
            end
        end
        push!(itemscoords, futurecoords)
    end
    return itemscoords
end

"""
Multi-IO version of generatefuturecoords: handles items targeting different IOs
Each item uses its own target IO to determine movement direction
"""
function generatefuturecoords_multi_io(items, escorts, dir, escortid, itemid, matrix, item_to_ios, current_io)
    item = items[itemid]
    itemx, itemy = item.coords
    esc_x, esc_y = escorts[escortid].coords
    itemscoords = []
    
    if dir == 2  # y-direction movement
        for o_itemid in keys(items)
            if o_itemid == itemid
                continue
            else
                o_item = items[o_itemid]
                o_itemx, o_itemy = o_item.coords
                
                # Check if item is in vertical path
                if o_itemx == itemx && o_itemy < itemy && o_itemy > esc_y
                    push!(itemscoords, (o_itemx, (max(1, (o_itemy - 1)))))
                else
                    push!(itemscoords, (o_itemx, o_itemy))
                end
            end
        end
        # Main item moves toward its target IO
        push!(itemscoords, (itemx, (max(1, (itemy - 1)))))
        
    elseif dir == 1  # x-direction movement
        # Use current_io to determine direction for main item
        dir_sign = current_io[1] < itemx ? -1 : 1
        futurecoords = (itemx, itemy)
        
        if dir_sign == 1
            futurecoords = (min(itemx + 1, size(matrix, 1)), itemy)
        else
            futurecoords = (max(itemx - 1, 1), itemy)
        end
        
        # Process other items - use their target IOs
        for o_itemid in keys(items)
            if o_itemid == itemid
                continue
            else
                o_item = items[o_itemid]
                o_itemx, o_itemy = o_item.coords
                
                # Check if item is in horizontal path
                if o_itemy == itemy && ((o_itemx < itemx && o_itemx > esc_x) || (o_itemx > itemx && esc_x > o_itemx))
                    # Determine direction for this other item based on its target IO
                    if haskey(item_to_ios, o_itemid) && !isempty(item_to_ios[o_itemid])
                        # Use first target IO for other items
                        other_target_io = item_to_ios[o_itemid][1]
                        other_dir_sign = other_target_io[1] < o_itemx ? -1 : 1
                        if !(dir_sign == other_dir_sign)
                            println("Warning: Item $o_itemid has a different target IO direction than the main item. Defaulting to main item's direction.")
                            other_dir_sign = dir_sign  # Override to ensure consistent movement direction
                        end
                        push!(itemscoords, (o_itemx + other_dir_sign, o_itemy))
                    else
                        # Fallback to same direction as main item if no IO info
                        push!(itemscoords, (o_itemx + dir_sign, o_itemy))
                    end
                else
                    push!(itemscoords, (o_itemx, o_itemy))
                end
            end
        end
        push!(itemscoords, futurecoords)
    end
    
    return itemscoords
end
function generatefuturecoords_fincoord(items,  escorts, dir, escortid, finalcoords, matrix, IO) 
    finx, finy = finalcoords
    esc_x, esc_y = escorts[escortid].coords
    itemscoords = []
    if dir==2
        for o_itemid in keys(items)
          
            o_item = items[o_itemid]
            o_itemx, o_itemy = o_item.coords
            if o_itemx == finx && o_itemy <= finy && finy >= esc_y
                push!(itemscoords, (o_itemx, (max(1,(o_itemy-1)))))
            else
                push!(itemscoords, (o_itemx, o_itemy))
            end
        
        end
    elseif dir==1
        dir = finx < esc_x ? 1 : -1 # careful about direction
        for o_itemid in keys(items)
        
            o_item = items[o_itemid]
            o_itemx, o_itemy = o_item.coords
            if o_itemy == finy && ((esc_x <= o_itemx && o_itemx <= finx ) || (esc_x >= o_itemx && o_itemx >= finx))
                push!(itemscoords, (o_itemx+dir, o_itemy))
            else
                push!(itemscoords, (o_itemx, o_itemy))
            end
           
        end
    end
    return itemscoords
end
function futurecoords_closetoIO(items,  itemid, escorts, escortid, dir, IO) 
    finx, finy = items[itemid].coords
    esc_x, esc_y = escorts[escortid].coords
    iox,ioy = IO
    itemscounter = 0
    if dir==2
        for o_itemid in keys(items)
          
            o_item = items[o_itemid]
            o_itemx, o_itemy = o_item.coords
            if o_itemx == finx && o_itemy <= finy && finy >= esc_y
                currcoords = (o_itemx, (max(1,(o_itemy-1))))
                if abs(currcoords[1] -iox) + abs(currcoords[2] -ioy) <= length(keys(items))-1
                    itemscounter += 1
                end
            elseif abs(o_itemx -iox) + + abs(o_itemy -ioy) <= length(keys(items))-1
                itemscounter += 1
            end
        end
    elseif dir==1
        dir = finx < esc_x ? 1 : -1 # careful about direction
        for o_itemid in keys(items)
    
            o_item = items[o_itemid]
            o_itemx, o_itemy = o_item.coords
            if o_itemy == finy && ((esc_x <= o_itemx && o_itemx <= finx ) || (esc_x >= o_itemx && o_itemx >= finx))
                currcoords =  (o_itemx+dir, o_itemy)
                if abs(currcoords[1] -iox) + abs(currcoords[2] -ioy) <= length(keys(items))-1
                    itemscounter += 1
                end
            elseif abs(o_itemx -iox) + + abs(o_itemy -ioy) <= length(keys(items))-1
                itemscounter += 1
            end
           
        end
    end
    if itemscounter >= length(keys(items))-1
        return true
    else
        return false
    end
end
"""
returns individual matrices for each urgent customer to figure out how to reach them
"""
function urgmats(items, escorts, blockmat, matrix, urgentcustomers, IO)
    allkeys= union(keys(escorts), keys(items))
    urgmats = Dict{String, Matrix{Int}}()
    if !isempty(urgentcustomers)# Then, sort them by urgency:
        for customer_id in urgentcustomers
            urgmat = deepcopy(blockmat)
            urgx, urgy = items[customer_id].coords
            urgmat[urgx, urgy] = 3
            dir = urgx > IO[1] ? -1 : 1
            if urgx != IO[1]
                if dir == 1
                    for xx in min(urgx+1, size(matrix, 1)):IO[1]
                        if !(matrix[xx, urgy] in allkeys)
                            for y in min(urgy+1, size(matrix,2)):size(matrix, 2)
                                if blockmat[xx, y] == 0 && !(matrix[xx, y] in keys(items))
                                    urgmat[xx, y] = 2
                                else
                                    break
                                end
                            end
                        else
                            break
                        end
                    end
                else
                    for xx in max(urgx-1, 1):-1:IO[1]
                        if !(matrix[xx, urgy] in allkeys)
                            for y in min(urgy+1, size(matrix,2)):size(matrix, 2)
                                if blockmat[xx, y] == 0 && !(matrix[xx, y] in keys(items))
                                    urgmat[xx, y] = 2
                                else
                                    break
                                end
                            end
                        else
                            break
                        end
                    end
                end
            end
            if urgy != IO[2]
                for yy in urgy-1:-1:IO[2]
                    if !(matrix[urgx, yy] in allkeys)

                        if dir == -1 || urgx == IO[1]# check rightside
                            for x in min(urgx+1, size(matrix, 1)):size(matrix, 1)
                                if blockmat[x, yy] == 0 && !(matrix[x, yy] in keys(items))
                                    urgmat[x, yy] = 2
                                else
                                    break
                                end
                            end
                        end
                        if dir == 1 || urgx == IO[1]# check leftside
                            for x in max(urgx-1, 1):-1:IO[1]
                                if blockmat[x, yy] == 0 && !(matrix[x, yy] in keys(items))
                                    urgmat[x, yy] = 2
                                else
                                    break
                                end
                            end
                        end
                        
                    else
                        break
                    end
                end
            end

            #print_matrix(urgmat) ; print_matrix(matrix, blockmat)
            urgmats[customer_id] = urgmat
        end
    end

    return urgmats
end
function urgmats_multi_io(items, escorts, blockmat, matrix, urgentcustomers, item_to_ios, all_ios)
    allkeys = union(keys(escorts), keys(items))
    result = Dict{String, Matrix{Int}}()
    for customer_id in urgentcustomers
        urgmat = deepcopy(blockmat)
        urgx, urgy = items[customer_id].coords
        urgmat[urgx, urgy] = 3

        # Each item uses its own assigned IO instead of a global one
        assigned = get(item_to_ios, customer_id, all_ios)
        item_io = argmin(io -> abs(io[1] - urgx) + abs(io[2] - urgy), assigned)
        iox, ioy = item_io

        dir = urgx > iox ? -1 : 1
        if urgx != iox
            if dir == 1
                for xx in min(urgx+1, size(matrix, 1)):iox
                    if !(matrix[xx, urgy] in allkeys)
                        for y in min(urgy+1, size(matrix,2)):size(matrix, 2)
                            if blockmat[xx, y] == 0 && !(matrix[xx, y] in keys(items))
                                urgmat[xx, y] = 2
                            else
                                break
                            end
                        end
                    else
                        break
                    end
                end
            else
                for xx in max(urgx-1, 1):-1:iox
                    if !(matrix[xx, urgy] in allkeys)
                        for y in min(urgy+1, size(matrix,2)):size(matrix, 2)
                            if blockmat[xx, y] == 0 && !(matrix[xx, y] in keys(items))
                                urgmat[xx, y] = 2
                            else
                                break
                            end
                        end
                    else
                        break
                    end
                end
            end
        end
        if urgy != ioy
            for yy in urgy-1:-1:ioy
                if !(matrix[urgx, yy] in allkeys)
                    if dir == -1 || urgx == iox
                        for x in min(urgx+1, size(matrix, 1)):size(matrix, 1)
                            if blockmat[x, yy] == 0 && !(matrix[x, yy] in keys(items))
                                urgmat[x, yy] = 2
                            else
                                break
                            end
                        end
                    end
                    if dir == 1 || urgx == iox
                        for x in max(urgx-1, 1):-1:iox
                            if blockmat[x, yy] == 0 && !(matrix[x, yy] in keys(items))
                                urgmat[x, yy] = 2
                            else
                                break
                            end
                        end
                    end
                else
                    break
                end
            end
        end
        result[customer_id] = urgmat
    end
    return result
end

function resetitems!(items)
    for id in keys(items)
        items[id].escortsx = Vector{String}()
        items[id].escortsy = Vector{String}()
        items[id].direction = 0 
    end
end
function resetescorts!(escorts, iteration)
    for escort_id in keys(escorts) # reset the serving of items. 
        escort = escorts[escort_id]
        escort.itemsx = Vector{String}()
        escort.itemsy = Vector{String}()
        # Remove keys from banset that are smaller than the current iteration
        for key in keys(escort.banset)
            if key < iteration-4
            delete!(escort.banset, key)
            end
        end
        while length(escort.tabu)>2
            escort.tabu = escort.tabu[2:end]
        end
        if escort.lastmoved <= iteration-3
            escort.tabu = Vector{Tuple{Int64, Int64}}()
        end
    end
end
function allowedOrder(esc_x, io_x, xx, itemx) # double serve check 
    return (
        (esc_x <= io_x < xx < itemx) ||
        (esc_x >= io_x > xx > itemx) ||
        (io_x <= esc_x < xx < itemx) ||
        (io_x >= esc_x > xx > itemx)
    )
end
function allowedOrder(esc_x, iox, itemx) # escort can serve
    return (
        (esc_x < itemx && iox < itemx) ||
        (esc_x > itemx && iox > itemx)
    )
end

function print_matrix(matrix)
    printmat = true
    if printmat 
        nrows, ncols = size(matrix)
        println("Matrix: ")
        # Print the matrix in a transposed manner
        for row in nrows:-1:1
            for col in 1:ncols
                element = string(matrix[col, row])
                print(lpad(element, 6), " ")
            end
            println()
            #println()
        end
    end
end
function print_matrix(matrix, blockmat)
    printmat = false
    if printmat 
        nrows, ncols = size(matrix)
        println("Matrix: ")
        # Print the matrix in a transposed manner
        for row in nrows:-1:1
            for col in 1:ncols
                element = string(matrix[col, row])
                print(lpad(element, 6), " ")
            end
            print("   |   ")
            for col in 1:ncols
                element = string(blockmat[col, row])
                print(lpad(element, 6), " ")
            end
            println()
            #println()
        end
        println("End of print")
    end
end
function checksync(matrix, escorts, items, step)
    for eid in keys(escorts)
        ex, ey = escorts[eid].coords
        if matrix[ex, ey] != eid
            println("$step Escort $eid is not in the right place")
        end
    end
    for iid in keys(items)
        ix, iy = items[iid].coords
        if matrix[ix, iy] != iid
            println("$step Item $iid is not in the right place")
        end
    end
end