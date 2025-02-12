using Statistics
"""
assigns escorts to items based on the initial sorting (in the function) and the positions in the matrix
"""
function item_escort_assigment!(matrix, items, escorts, IO) 

    sorted_keys = sort_keys_by_distance_and_sum(items, IO)
    escortstomovefirst= []
    # sort the items by the increasing number of total escorts
    for escort_id in keys(escorts) # reset the serving of items. 
        escort = escorts[escort_id]
        escort.itemsx = Vector{String}()
        escort.itemsy = Vector{String}()
    end
    blockmat = [0 for _ in 1:size(matrix, 1), _ in 1:size(matrix, 2)]
    for key in sorted_keys
        item = items[key]
        x,y = item.coords
        sorted_keys = filter(x -> x != key, sorted_keys) # remove this item as now we will decide its future
        if length(item.escortsx) == 0 && length(item.escortsy) == 0
            item.direction = 0 # not move               
            continue
        end
        if length(item.escortsx) == 0 && length(item.escortsy) > 0
            item.direction = 2 # move in y
            escortid = find_nearest_escort(item, items, sorted_keys, matrix, IO, blockmat,2,escorts) # is 0 if no escort is available (path blocked)
            if escortid == 0
                println("No escort found for item ", key)
                item.escortsy = Vector{String}()
                continue
                
            end
            updateblockmat!( blockmat, item, escorts[escortid])
            updateescortsavailable!(sorted_keys, items, escorts, escortid, blockmat)
        end
        if length(item.escortsy) == 0 && length(item.escortsx) > 0
            item.direction = 1
            escortid = find_nearest_escort(item, items, sorted_keys, matrix, IO, blockmat,1,escorts) 
            if escortid == 0
                println("No escort found for item ", key)
                item.escortsx = Vector{String}()
                continue
            end
            updateblockmat!( blockmat, item, escorts[escortid])
            updateescortsavailable!(sorted_keys,items, escorts, escortid, blockmat)
        end
        if length(item.escortsx)>0 && length(item.escortsy) > 0 # prefer x direction
            preferred_dir = length(item.escortsx) > length(item.escortsy) ? 1 : 2
            secondary_dir = preferred_dir == 1 ? 2 : 1
            item.direction = preferred_dir
            escortid = find_nearest_escort(item, items, sorted_keys, matrix, IO, blockmat, preferred_dir, escorts)
            if escortid == 0
                escortid = find_nearest_escort(item, items, sorted_keys, matrix, IO, blockmat, secondary_dir, escorts)
                if escortid == 0
                    println("No escort found both directions for item ", key)
                    item.escortsy = Vector{String}()
                    item.escortsx = Vector{String}()
                    continue
                end
                item.direction = secondary_dir
            end
            updateblockmat!(blockmat, item, escorts[escortid])
            updateescortsavailable!(sorted_keys, items, escorts, escortid, blockmat)
        end
        #Final assignment if escortid is not 0
        push!(escortstomovefirst, escortid)
        if item.direction == 2
            item.escortsy = [escortid] 
            item.escortsx = Vector{String}()
            escorts[escortid].itemsy = [key]
        elseif item.direction == 1
            item.escortsx = [escortid]
            item.escortsy = Vector{String}()
            escorts[escortid].itemsx = [key]
        end

        # Remove the key from sorted_keys for the next iteration and re sort according to number of escorts
        
        sorted_keys = sort_keys_by_distance_and_sum(items, IO)
        if all([length(items[key].escortsx) == 0 && length(items[key].escortsy) == 0 for key in sorted_keys])
            break
        end
    end
    print_matrix(matrix, blockmat)
    return escortstomovefirst, blockmat

end

function euclidean_distance(coords1, coords2)
    return sqrt((coords1[1] - coords2[1])^2 + (coords1[2] - coords2[2])^2)
end
"""
sorting function. currently by decreasing distance and then increasing number of escorts. (furthest away item is first)
"""
function sort_keys_by_distance_and_sum(items, IO)
    sorted_keys = sort(collect(keys(items)), by = x -> (
        -euclidean_distance(items[x].coords, IO),  # Negative Euclidean distance for decreasing order
        sum(length(items[x].escortsx) + length(items[x].escortsy))  # Sum of lengths for increasing order
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
"""
between all remaining items and escorts it checks if the path is blocked by previous assignments and removes the escorts that are blocked from item possible escorts.

"""
function updateescortsavailable!(sorted_keys, items, escorts, escortid, blockmat) # remove the escorts that are blocked by previous item/escort assignment
    io_x , io_y = IO
    for key in sorted_keys
        item = items[key]
        x,y = item.coords
        x_dir = io_x > x ? 1 : -1 
        idxremove = [escortid]
        idyremove = [escortid]
    
        for escort_id in item.escortsx
            escort = escorts[escort_id]
            ex, ey = escort.coords
            xstart = min(x, ex)
            xend   = max(x, ex)
            path_blocked = false
            for xx in xstart:xend
                # blockmat entry is a tuple, skip if first value is 1
                if blockmat[xx, y] == 1 
                    path_blocked = true
                    break
                end
            end
            if path_blocked 
                push!(idxremove, escort_id)
            end
            
        end
        for escort_id in item.escortsy
            escort = escorts[escort_id]
            ex, ey = escort.coords
            ystart = min(y, ey)
            yend   = max(y, ey)
            path_blocked = false
            for yy in ystart:yend
                # blockmat entry is a tuple, skip if first value is 1
                if blockmat[x, yy] == 1
                    path_blocked = true
                    break
                end
            end
            if path_blocked
                push!(idyremove, escort_id)
            end
        end  

        item.escortsx = setdiff(item.escortsx, idxremove)
        item.escortsy = setdiff(item.escortsy, idxremove)
    end
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
function find_nearest_escort(item, items, sorted_keys, matrix, IO, blockmat, direction,escorts)
    itemx, itemy = item.coords
    nearest_id = 0
    min_dist = Inf
    iox, ioy = IO
    doubleserve = []

    if direction == 1 # x_
        for e_id in item.escortsx
            escort_x, escort_y = escorts[e_id].coords 
            if escort_y != itemy
                println("saved escort in wrong position, direction x but y coord is different")
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
                    if iox > min(itemx, escort_x) && iox < max(itemx, escort_x) # IO is in the path, we skip escort
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
        for e_id in item.escortsy
            escort_x, escort_y = escorts[e_id].coords
            if escort_x != itemx
                println("saved escort in wrong position, direction y but x coord is different")
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
                    if ioy > min(itemy, escort_y) && ioy < max(itemy, escort_y)
                        println("IO_y in the path of y movement, should not happen, check error")
                    end 
                    push!(doubleserve, matrix[itemx, yy])
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
        for key in doubleserve # we are lucky to serve two items 
            filter!(x -> x != key, sorted_keys)
            items[key].direction = direction
            if direction == 1
                items[key].escortsx = [nearest_id] 
                items[key].escortsy = Vector{String}()
                push!(escorts[nearest_id].itemsx, key)
            elseif direction == 2
                items[key].escortsy = [nearest_id] 
                items[key].escortsx = Vector{String}()
                push!(escorts[nearest_id].itemsy, key)
            end
        end
    end
       
    
    return nearest_id
end
function save_item_escorts!(matrix, items, escorts, IO) #saves all escorts for all items.
    io_x , io_y = IO
    for key in keys(items)
        item = items[key]
        x,y = item.coords
        x_dir = io_x > x ? 1 : -1 
        x_dir = io_x == x ? 0 : x_dir
        for escort_id in keys(escorts)
            escort = escorts[escort_id]
            ex, ey = escort.coords
            if x_dir == 1 && ex > x && ey == y # escort is on the right side and item has to move right
                push!(item.escortsx, escort_id)
            elseif x_dir == -1 && ex < x && ey == y # escort is on the left side and item has to move left
                push!(item.escortsx, escort_id)
            elseif ey < y && ex == x # escort is below the item and the x coord is the save_item_escorts
                push!(item.escortsy, escort_id)
            end
        end  
    end
end

"""moves one escort to the final coordinates, modifying the incumbent matrix and the positions of items and escorts"""
function move_escort!(matrixout, items, escorts, escortid, escort_finalcoords)
    matrix = deepcopy(matrixout)
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
        end
    end
    matrix[xgoal, ygoal] = escortid # update matrix
    escorts[escortid].coords = (xgoal, ygoal) # update escort's coordinates
    return matrix
end

"""
moves all escorts, starting with the mover escorts
"""
function moveescorts!(iteration, matrix, items, escorts, moverescortids, blockmat, IO)
# MOVERS FIRST
    if iteration == 3 # TODO check pngs for this
        println("here")
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
    
        item = items[itemid]
        if (item.direction != direction) 
            println("Item direction and escort direction do not match")
        end

        itemx, itemy = item.coords
        escortx, escorty = escorts[escortid].coords
        # Here onwards until the move_escort! function, we find the nearest item where this escort could be useful in next time step
        candid,candx,candy = find_nearest_item_toitem(matrix, items, itemid, blockmat, IO, direction)
        if direction == 1
            if candid == 0 || candx == itemx
                escort_finalcoords = (itemx, escorty)
            else 
                if items[candid].direction == 1 # moving in x
                    if IO[1] > min(itemx, candx) 
                        escort_finalcoords = (max(1, candx+1), itemy) # IO on the right
                    else IO[1] < min(itemx, candx)
                        escort_finalcoords = (max(1, candx-1), itemy) # IO on the left
                    end
                elseif items[candid].direction == 2 # moving in y
                    escort_finalcoords = (candx, itemy)
                end
            end
        elseif direction == 2
            if candid == 0 || candy == itemy
                escort_finalcoords = (escortx, itemy)
            else 
                if items[candid].direction == 1 # moving in x
                    escort_finalcoords = (itemx, candy) 
                elseif items[candid].direction == 2 # moving in y
                    escort_finalcoords = (itemx, max(1, candy-1))
                end
            end
        end
        if escort_finalcoords != ( escortx, escorty)
            matrix = move_escort!(matrix, items, escorts, escortid, escort_finalcoords)
            updateblockmat_e!(blockmat, escortx, escorty, escort_finalcoords[1], escort_finalcoords[2])
            escorts[escortid].lastmoved = iteration
        end
        print_matrix(matrix, blockmat)
        
    end
    nonmovers = setdiff(keys(escorts), moverescortids) 
# NON MOVERS (nonassigned in earlier stage) 
    for escortid in nonmovers
        if  (escortid == "E2") && escorts[escortid].coords[1] == 3 && escorts[escortid].coords[2] == 4
            println("E1 is at ")
        end
        esc_x , esc_y = escorts[escortid].coords
        escort_finalcoords = find_nearest_item_toescort(iteration, matrix, items, escorts, escortid, blockmat, IO)
        if escort_finalcoords != (esc_x,esc_y)
            matrix = move_escort!(matrix, items, escorts, escortid, escort_finalcoords)
            updateblockmat_e!(blockmat, esc_x, esc_y, escort_finalcoords[1], escort_finalcoords[2])
            escorts[escortid].lastmoved = iteration
        end
        
        print_matrix(matrix, blockmat)
        
    end
    resetitems!(items) # gets rid of escort assignments
    return matrix
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
function find_nearest_item_toescort(iteration, matrix, items, escorts, escortid, blockmat, IO) # TODO
    thisescort = escorts[escortid]
    esc_x, esc_y = thisescort.coords
    distx, disty = size(matrix, 1)+1, size(matrix, 2)+1
    closestx , closesty = 0 , 0 
    finx , finy = esc_x, esc_y 
    sortedkeys = sort_keys_by_distance(items, IO, true) # sort by distance to IO
    for itemid in sortedkeys # try serve item in next iteration 
        itemx, itemy = items[itemid].coords
        
        if itemx == esc_x && itemy == esc_y
           println("Escort and item are in the same position, there must be an error")
           continue
        end

     
        if (IO[1] < itemx && esc_x < itemx) ||  # check if we can move escort to item path on X
            (IO[1] > itemx && esc_x > itemx)
            ygap = abs(esc_y - itemy)
            if ygap < disty && ygap > 0 # if gap is 0 we could have served, there must be a reason we didnt
                ymin = min(esc_y, itemy)
                ymax = max(esc_y, itemy)
                path_blocked = false
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
                if !path_blocked
                    disty = ygap
                    closesty = itemid
                end
            end
            
        end
        if esc_y < itemy # check if we can move escort to item path on Y 
            xgap = abs(esc_x - itemx)
            if xgap < distx && xgap > 0
                xmin = min(esc_x, itemx)
                xmax = max(esc_x, itemx)
                path_blocked = false
                for x in xmin:xmax
                    if blockmat[x, esc_y] == 1 || matrix[x, esc_y] in keys(items)
                        path_blocked = true
                        break
                    end
                end
                if !path_blocked
                    distx = xgap
                    closestx = itemid
                end
            end
        end
    end

    # after checking all items we decide where to move the escort
    if closestx ==0  && closesty == 0 # Most complex part of this entire algorithm
        
        if esc_x == IO[1] && esc_y == IO[2]
            return (esc_x, esc_y) # best place it could be 
        elseif esc_x == IO[1] # TRY  go down, if thats not good then left/right
            avg_y = mean([items[item].coords[1] for item in keys(items)])
            valid_y = [y for y in IO[2]:max(1, esc_y-1) if (blockmat[esc_x, y] == 1 || matrix[esc_x, y] in keys(items) || matrix[esc_x, y] in keys(escorts))]
            maxmove_y = isempty(valid_y) ? IO[2] : min(esc_y, (maximum(valid_y)+1))
            if (maxmove_y >= floor(avg_y)) # cannot move down enough , move out of the way right or left 
                avg_x = mean([items[item].coords[1] for item in keys(items)]) # where are the items ? 
                diresc= avg_x <= IO[1] ? 1 : -1 # if items are left we go right, vice versa
                for _ in 1:2 # Try both directions if the first choice fails
                    if diresc == 1 # chose right
                        maxmove = size(matrix, 1)
                        maxmove = checkmatrixforblock!(blockmat, matrix, maxmove, diresc, escortid, iteration, escorts, items)
                        if maxmove > esc_x # can move right
                            return (maxmove, esc_y)
                        end
                    elseif diresc == -1 # chose left
                        maxmove = 1
                        maxmove = checkmatrixforblock!(blockmat, matrix, maxmove, diresc, escortid, iteration, escorts, items)
                        if maxmove < esc_x # can move left
                            return (maxmove, esc_y)
                        end
                    end
                    diresc = -diresc # Switch direction
                end
            else
                return (esc_x, maxmove_y)
            end
        elseif esc_y == IO[2] # go in X direction towards IO 
            if esc_x < IO[1] # io on the right
                valid_x = [x for x in (esc_x+1):IO[1] if (blockmat[x, esc_y] == 1 || matrix[x, esc_y] in keys(items))]
                maxmove_x = isempty(valid_x) ? IO[1] : minimum(valid_x)-1 
                if maxmove_x == esc_x
                    minup = checkmatrixforblock!(blockmat, matrix, maxmove_x, 2, escortid, iteration, escorts, items)
                    if minup > esc_y
                        return (esc_x, minup)
                    end
                end                
            else # io on the left
                valid_x = [x for x in IO[1]:max(IO[1], esc_x-1) if (blockmat[x, esc_y] == 1 || matrix[x, esc_y] in keys(items))]
                maxmove_x = isempty(valid_x) ? IO[1] : (maximum(valid_x)+1)
                if maxmove_x == esc_x
                    minup = checkmatrixforblock!(blockmat, matrix, maxmove_x, 2, escortid, iteration, escorts, items)
                    if minup > esc_y
                        return (esc_x, minup)
                    end
                end     
            end  
            return (maxmove_x, esc_y)
        else 
            avg_y = mean([items[item].coords[1] for item in keys(items)])
            avg_x = mean([items[item].coords[1] for item in keys(items)])
            dirx= avg_x <= IO[1] ? -1 : 1
         
            valid_y = [y for y in IO[2]:max(1, esc_y-1) if (blockmat[esc_x, y] == 1 || matrix[esc_x, y] in keys(items) || matrix[esc_x, y] in keys(escorts))]
            maxmove_y = isempty(valid_y) ? IO[2] : (maximum(valid_y)+1)
            if (maxmove_y >= floor(avg_y) || maxmove_y == esc_y) # cannot move down enough , move out of the way right or left 

                if dirx == 1 # chose right
                    maxmove = size(matrix, 1)
                    maxmove = checkmatrixforblock!(blockmat, matrix, maxmove, dirx, escortid, iteration, escorts, items)
                    if maxmove > esc_x # can move right
                        return (maxmove, esc_y)
                    end
                elseif dirx == -1 # chose left
                    maxmove = 1
                    maxmove = checkmatrixforblock!(blockmat, matrix, maxmove, dirx, escortid, iteration, escorts, items)
                    if maxmove < esc_x # can move left
                        return (maxmove, esc_y)
                    end
                end
            else
                return (esc_x, maxmove_y)
            end
              # havent returned so we couldnt go down or inwards , try upwards
            minup = size(matrix,2)
            minup = checkmatrixforblock!(blockmat, matrix, minup, 2, escortid, iteration, escorts, items)
            if minup > esc_y
                return (esc_x, minup)
            end
            # that didnt return so we try to go outwards. if this doesnt return too we will be blocked anyways
            dirx = -dirx
            if escorts[escortid].lastmoved < iteration -1 # we allow one iteration no movement, else we trigger outwards movement
                if dirx == 1 # chose right
                    maxmove = size(matrix, 1)
                    maxmove = checkmatrixforblock!(blockmat, matrix, maxmove, dirx, escortid, iteration, escorts, items)
                    if maxmove > esc_x # can move right
                        return (maxmove, esc_y)
                    end
                elseif dirx == -1 # chose left
                    maxmove = 1
                    maxmove = checkmatrixforblock!(blockmat, matrix, maxmove, dirx, escortid, iteration, escorts, items)
                    if maxmove < esc_x # can move left
                        return (maxmove, esc_y)
                    end
                end
            end
        end

    elseif distx < disty # go in front of item in Y direction
        candx, candy = items[closestx].coords
        return (candx, esc_y)

    elseif distx >= disty # go in path of item in X direction
        candx, candy = items[closesty].coords
        return (esc_x, candy)
    end
    return (finx, finy) # cannot move
end
function checkmatrixforblock!(blockmat, matrix, maxmove, diresc, escortid, iteration, escorts, items)
    esc_x, esc_y = escorts[escortid].coords
    if diresc == 1 
        valid_x_1 = [x for x in esc_x:size(matrix,1) if (blockmat[x, esc_y] == 1 || matrix[x, esc_y] in keys(items))] # right
        if (isempty(valid_x_1) || minimum(valid_x_1) > esc_x+1)
            maxmove = isempty(valid_x_1) ?  size(matrix,1) : minimum(valid_x_1)-1
            for x in maxmove:-1:esc_x # backwards, as we want to move as far right as we can 
                if directionclear(items, escorts, escortid, x, esc_y, 2)
                    maxmove = x
                    break
                end
            end
            return maxmove
        else 
            return esc_x
        end
    end
    if diresc == -1 # going left checking 
        valid_x_1m = [x for x in esc_x:-1:1 if (blockmat[x, esc_y] == 1 || matrix[x, esc_y] in keys(items))] # left
        if (isempty(valid_x_1m) || maximum(valid_x_1m) < esc_x-1) # can move left
            maxmove = isempty(valid_x_1m) ? 1 : (maximum(valid_x_1m)+1)
            for x in maxmove:size(matrix, 1)
                if directionclear(items, escorts,escortid, x, esc_y , 2)
                    maxmove = x
                    break
                end
            end
            return maxmove
        else 
            return esc_x
        end
    end
    if diresc == 2
        valid_y= [y for y in esc_y:size(matrix,2) if (blockmat[esc_x, y] == 1 || matrix[esc_x, y] in keys(items))] # up 
        if (isempty(valid_y) || minimum(valid_y) > esc_y) # can move up
            minup = isempty(valid_y) ? esc_y : minimum(valid_y)+1
            for y in minup:size(matrix, 2)
                if directionclear(items, escorts,escortid, esc_x,y, 1)
                    minup = y
                    break
                end
            end
            return minup
        else 
            return esc_y
        end
    end
    
    
    
    return maxmove

end
"""
while we check where to move the escort so that we can make another move in the next iteration 

    example: I want to move escort up as its blocked here. i want to check where up can i move so that i can move left/right in the next iteration
"""
function directionclear( items, escorts, escortid, coordx, coordy, direction)
    if direction ==1 # we give y coord and tell to check 
        for entity in union(keys(escorts), keys(items)) # check for presence in both collections in the front
            if entity != escortid
                if haskey(escorts, entity)
                    esc_other = escorts[entity]
                    if (esc_other.coords[2] == coordy && esc_other.lastmoved == iteration)  # iteration as escort will probably move
                        if (esc_other.coords[1] < min(IO[1], coordx) || esc_other.coords[1] > max(IO[1], coordx)) # acceptable if on the other side of IO[1]
                            continue
                        end
                        return false
                    end
                elseif haskey(items, entity)
                    item_other = items[entity]
                    if item_other.coords[2] == coordy
                        if coordx > min(item_other.coords[1], IO[1]) && coordx < max(item_other.coords[1], IO[1]) # item can be served
                            printl("an item can be served by escort, shouldnt have happened")
                            continue
                        end
                        return false
                    end
                end
            end
        end
    elseif direction ==2 # we give x coord and tell to check lower y, as we wish to not hurt anything
        for entity in union(keys(escorts), keys(items)) # check for presence in both collections in the front
            if entity != escortid
                if haskey(escorts, entity)
                    esc_other = escorts[entity]
                    if (esc_other.coords[1] == coordx && esc_other.lastmoved == iteration) # iteration as escort will probably move
                        return false
                    end
                elseif haskey(items, entity)
                    item_other = items[entity]
                    if item_other.coords[1] == coordx
                        return false
                    end
                end
            end
        end
    end
    return true

end
function resetitems!(items)
    for id in keys(items)
        items[id].escortsx = Vector{String}()
        items[id].escortsy = Vector{String}()
    end
end
function print_matrix(matrix)
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
function print_matrix(matrix, blockmat)
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