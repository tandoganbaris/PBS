function item_escort_assigment!(matrix, items, escorts, IO) # TODO: add escort removal and direction reassignment due to conflicts
    sorted_keys = sort(collect(keys(items)), by = x -> sum(length(items[x].escortx) + length(items[x].escorty)), rev = false)
    # sort the items by the increasing number of total escorts
    for key in sorted_keys
        item = items[key]
        if length(item.escortx) == 0 && length(item.escorty) == 0
            item.direction = 0 # not move
            continue
        end
        if length(item.escortx) == 0
            item.direction = 2 # move in y
            #check for the y escorts and remove the assigned escort from others (also the ones on its path serving perpendicularly others) 
        end
        if length(item.escorty) == 0
            item.direction = 1
            #check for the x escorts and remove  the assigned escort from others (also the ones on its path serving perpendicularly others) 
        end
        if length(item.escortx) > length(item.escorty)
            item.direction = 1
        else
            item.direction = 2
        end


        sorted_keys = sort(collect(keys(items)), by = x -> sum(length(items[x].sescortx) + length(items[x].escorty)), rev = false)
        if all([length(items[key].escortx) == 0 && length(items[key].escorty) == 0 for key in sorted_keys])
            break
        end
    end

end
function save_item_escorts!(matrix, items, escorts, IO)
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
