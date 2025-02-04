function item_escort_assigment!(matrix, items, escorts, IO) # TODO: add escort removal and direction reassignment due to conflicts
    sorted_keys = sort(collect(keys(items)), by = x -> sum(length(items[x].escortx) + length(items[x].escorty)), rev = false)
    # sort the items by the increasing number of total escorts
    for escort_id in keys(escorts) # reset the serving of items. 
        escort = escorts[escort_id]
        escort.itemsx = Vector{Char}()
        escort.itemsy = Vector{Char}()
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
            escortid = find_nearest_escort(item, blockmat,2,escorts) # is 0 if no escort is available (path blocked)
            if escortid == 0
                println("No escort found for item ", key)
                item.escortsy = Vector{Char}()
                continue
                
            end
            updateblockmat!( blockmat, item, escorts[escortid])
           
            updateescortsavailable!(sorted_keys,items, escorts, escortid, blockmat)
        end
        if length(item.escortsy) == 0 && length(item.escortsx) > 0
            item.direction = 1
            escortid = find_nearest_escort(item, blockmat,1,escorts) 
            if escortid == 0
                println("No escort found for item ", key)
                item.escortsx = Vector{Char}()
                continue
            end
            updateblockmat!( blockmat, item, escorts[escortid])
            updateescortsavailable!(sorted_keys,items, escorts, escortid, blockmat)
        end
        if length(item.escortsx) > length(item.escortsy) # prefer x direction
            item.direction = 1
            escortid = find_nearest_escort(item, blockmat,1,escorts)
            if escortid == 0
                escortid = find_nearest_escort(item, blockmat,2,escorts)
                if escortid == 0
                    println("No escort found both directions for item ", key)
                    item.escortsy = Vector{Char}()
                    item.escortsx = Vector{Char}()
                    continue
                end
                item.direction = 2
            end
            updateblockmat!( blockmat, item, escorts[escortid])
            updateescortsavailable!(sorted_keys,items, escorts, escortid, blockmat)
        elseif length(item.escortsx) <= length(item.escortsy) # prefer y direction
            item.direction = 2 # move in y
            escortid = find_nearest_escort(item, blockmat,2,escorts)
            if escortid == 0
                escortid = find_nearest_escort(item, blockmat,1,escorts)
                if escortid == 0
                    println("No escort found both directions for item ", key)
                    item.escortsy = Vector{Char}()
                    item.escortsx = Vector{Char}()
                    continue
                end
                item.direction = 1
            end
            updateblockmat!( blockmat, item, escorts[escortid])
            updateescortsavailable!(sorted_keys,items, escorts, escortid, blockmat)
        end
        #Final assignment if escortid is not 0
        if item.direction == 2
            item.escortsy = [escortid] 
            item.escortsx = Vector{Char}()
            escorts[escortid].itemsy = [key]
        elseif item.direction == 1
            item.escortsx = [escortid]
            item.escortsy = Vector{Char}()
            escorts[escortid].itemsx = [key]
        end

        # Remove the key from sorted_keys for the next iteration and re sort according to number of escorts
        
        sorted_keys = sort(collect(keys(items)), by = x -> sum(length(items[x].sescortx) + length(items[x].escorty)), rev = false)
        if all([length(items[key].escortx) == 0 && length(items[key].escorty) == 0 for key in sorted_keys])
            break
        end
    end

end
function updateescortsavailable!(sorted_keys, items, escorts, escortid, blockmat) # remove the escorts that are blocked by previous item/escort assignment
    io_x , io_y = IO
    for key in sorted_keys
        item = deepcopy(items[key])
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

function updateblockmat!( blockmat, item, escort) # ban the block between item and escort
    itemx, itemy = item.coords
    escortx, escorty = escort.coords
    if  itemx == escortx
        xstart = min(itemx, escortx)
        xend = max(itemx, escortx)
        for x in xstart:xend
            blockmat[x, itemy] = 1
        end
    elseif itemy == escorty
        ystart = min(itemy, escorty)
        yend = max(itemy, escorty)
        for y in ystart:yend
            blockmat[itemx, y] = 1
        end
    end
end
function find_nearest_escort(item, blockmat, direction,escorts)
    itemx, itemy = item.coords
    nearest_id = 0
    min_dist = Inf
   
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
                if blockmat[xx, itemy] == 1
                    path_blocked = true
                    break
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
                if blockmat[itemx, yy] == 1
                    path_blocked = true
                    break
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
            
       
    
    return nearest_id
end
function save_item_escorts!(matrix, items, escorts, IO) #saves all escorts for all items.
    io_x , io_y = IO
    for key in keys(items)
        item = items[key]
        x,y = item.coords
        x_dir = io_x > x ? 1 : -1 
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

### Expects the id of the escort and the goal location of the escort
function move_escort!(matrix, items, escorts, escortid, escort_finalcoords)
    xgoal, ygoal = escort_finalcoords
    xcurr, ycuur = escorts[escortid].coords
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
            cand_id = matrix[x, ycuur]
            if haskey(items, cand_id)
                items[cand_id].coords = (x-1, ycuur) # update item's coordinates
            elseif haskey(escorts, cand_id)
                escorts[cand_id].coords = (x-1, ycuur) # update escort's coordinates
            end
            matrix[x-1, ycuur] = cand_id # move block to left
        end
    elseif direction == -1
        for x in xcurr-1:-1:xgoal
            cand_id = matrix[x, ycuur]
            if haskey(items, cand_id)
                items[cand_id].coords = (x+1, ycuur) # update item's coordinates
            elseif haskey(escorts, cand_id)
                escorts[cand_id].coords = (x+1, ycuur) # update escort's coordinates
            end
            matrix[x+1, ycuur] = cand_id # move block to right
        end
    elseif direction == 2
        for y in ycurr+1:ygoal
            cand_id = matrix[xcuur, y]
            if haskey(items, cand_id)
                items[cand_id].coords = (xcuur, y-1) # update item's coordinates
            elseif haskey(escorts, cand_id)
                escorts[cand_id].coords = (xcuur, y-1) # update escort's coordinates
            end
            matrix[xcurr, y-1] = cand_id # move block down
        end
    elseif direction == -2
        for y in ycurr-1:-1:ygoal
            cand_id = matrix[xcuur, y]
            if haskey(items, cand_id)
                items[cand_id].coords = (xcuur, y+1) # update item's coordinates
            elseif haskey(escorts, cand_id)
                escorts[cand_id].coords = (xcuur, y+1) # update escort's coordinates
            end
            matrix[xcurr, y+1] = cand_id # move block up
        end
    end
    matrix[xgoal, ygoal] = escortid # update matrix
    escorts[escortid].coords = (xgoal, ygoal) # update escort's coordinates
end
