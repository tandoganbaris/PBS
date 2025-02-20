using Statistics
using DataStructures
"""
assigns escorts to items based on the initial sorting (in the function) and the positions in the matrix
"""
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
      
    for key in sorted_keys
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
function sort_keys_by_distance_and_sum(items, IO)
    sorted_keys = sort(collect(deepcopy(keys(items))), by = x -> (
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
function updateblockmat_e!( blockmat, escortx, escorty, finx, finy) # ban the block between item and escort
    if escortx == finx # direction Y 
        ystart = min(escorty, finy)
        yend = max(escorty, finy)
        for y in ystart:yend
            blockmat[escortx, y] = 1
        end           
    elseif escorty == finy # direction X
        xstart = min(escortx, finx)
        xend = max(escortx, finx)
        for x in xstart:xend
            blockmat[x, escorty] = 1
        end
    end
end
"""
Given everything it finds the nearest escort to item. checks the path, if another item can be servd it serves it too.

"""
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
            x_max += dir
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
function outwards_astar_with_dirchange(matrix, IO, blockmat, escortid, escorts, items)
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
                cost_here = dist[cx, cy, cdir] +  extra_cost
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
            min_cost[x, y] = floor(minimum(dist[x, y, 1:3]))
        end
    end

    return (found_path, min_cost)
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
        return
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
    #return matrix
end

"""
moves all escorts, starting with the mover escorts
"""
function moveescorts!(iteration, matrix, items, escorts, moverescortids, blockmat, IO)
# MOVERS FIRST
    iox, ioy = IO
    if iteration == 10
        #println("here")
    end
    serveditems = []
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
            if length(moverescortids)>1
                itemscoords = generatefuturecoords_fincoord(items,  escorts, direction, escortid, escort_finalcoords, matrix, IO) 
                samecoords = direction == 2 ? 
                filter(x -> x[1] == itemx && x[2] >= min(itemy, escorty) && x[2] <= max(itemy, escorty), itemscoords) :
                filter(x -> x[2] == itemy && x[1] >= min(itemx, escortx) && x[1] <= max(itemx, escortx), itemscoords) # as moving this item might move another item closer to depot
                minDist = minimum([abs(IO[1] - coord[1]) + abs(IO[2] - coord[2]) for coord in samecoords])
                if minDist  > length(keys(items))+1 || # item far out from IO
                    path_to_io_exists_if(matrix, itemscoords, IO)   # check with A* if this movement would cause some stupid block
                    
                    push!(escorts[escortid].tabu, (escortx,escorty))
                    move_escort!(matrix, items, escorts, escortid, escort_finalcoords)
                    updateblockmat_e!(blockmat, escortx, escorty, escort_finalcoords[1], escort_finalcoords[2])
                    escorts[escortid].lastmoved = iteration
    
                else# else we ban it for next iteration to simplify computation on assignment! 
                    if !haskey(escorts[escortid].banset, iteration+1)
                        escorts[escortid].banset[iteration+1] = [itemid]
                    else
                        push!(escorts[escortid].banset[iteration+1],itemid)
                    end
                    filter!(x -> x != escortid, moverescortids)
                end
            else
                push!(escorts[escortid].tabu, (escortx,escorty))
                move_escort!(matrix, items, escorts, escortid, escort_finalcoords)
                updateblockmat_e!(blockmat, escortx, escorty, escort_finalcoords[1], escort_finalcoords[2])
                escorts[escortid].lastmoved = iteration
            end

           
        end
    end
    
    # First, filter the customers:
    urgentcustomers = filter(customer_id ->  floor(Int,iteration+ (abs(iox -items[customer_id].coords[1]) + items[customer_id].coords[2]) * 1.5) >= items[customer_id].deadline,keys(items))
    urgentmatrixes = urgmats(items, escorts, blockmat, matrix, urgentcustomers, IO)
    
    
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

    for escortid in nonmovers
        esc_x , esc_y = escorts[escortid].coords
        if blockmat[esc_x, esc_y] == 1
            continue
        end
        escort_finalcoords = find_nearest_item_toescort!(iteration, matrix, items, escorts, escortid, urgentmatrixes, blockmat, IO)
        if escort_finalcoords != (esc_x,esc_y)
            push!(escorts[escortid].tabu, (esc_x,esc_y))
            move_escort!(matrix, items, escorts, escortid, escort_finalcoords)
            updateblockmat_e!(blockmat, esc_x, esc_y, escort_finalcoords[1], escort_finalcoords[2])
            escorts[escortid].lastmoved = iteration
        end
        #print_matrix(matrix, blockmat)
    end
    #checksync(matrix, escorts, items)
    print_matrix(matrix, blockmat)
    #return matrix
end

"""
in the effort to moveescorts! we find the nearest item to the current item to figure out where the escort should move
"""
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
    if ((iteration == 9 || iteration ==10 ) && escortid == "E3")
        #println("here")
    end
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
                    if itemx < esc_x && itemx < ox # esc_x < ox && itemx <ox || itemx < esc_x && ox < esc_x && itemx < ox # If going left, check if there's an escort further left
                        skipItem = true
                        break
                    elseif itemx > esc_x && itemx> ox# esc_x > ox && itemx >ox || itemx> esc_x && ox > esc_x && itemx > ox  # If going right, check if there's an escort further right
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
                    minup = checkmatrixforblock!(blockmat, matrix, 2, escortid, strategy, iteration, escorts, items,IO)
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
                    minup = checkasternmat(blockmat, matrix, 2, escortid, strategy, escorts, items,IO, asternmat)
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
                minup = checkasternmat(blockmat, matrix, 2, escortid, strategy, escorts, items,IO, asternmat) #checkmatrixforblock!(blockmat, matrix, minup, 2, escortid, strategy, iteration, escorts, items,IO)
                if minup > esc_y
                    return (esc_x, minup)
                end
            end
            
        end
    end
    return (finx, finy) # cannot move
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
        reach = 1 # reach is the left right checking reach in this case. 
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
                    println("noreach")
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
                if o_itemy == itemy && o_itemx < itemx && o_itemx > esc_x
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
        dir = IO[1] < finx ? -1 : 1
        for o_itemid in keys(items)
        
            o_item = items[o_itemid]
            o_itemx, o_itemy = o_item.coords
            if o_itemy == finy && o_itemx <= finx && o_itemx >= esc_x
                push!(itemscoords, (o_itemx+dir, o_itemy))
            else
                push!(itemscoords, (o_itemx, o_itemy))
            end
           
        end
    end
    return itemscoords
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
            if key < iteration-1
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