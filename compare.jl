function directserve_flow!(iteration, matrix, items, escorts, escortid, urgcusts, blockmat, IO)
    thisescort = escorts[escortid]
    esc_x, esc_y = thisescort.coords

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
function urgserve_flow!(iteration, matrix, items, escorts, escortid, urgmats, IO)
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
    # FREE ROAM; GO SOMEWHERE ELSE/FREE IF POSSIBLE
   
    return false, (esc_x, esc_y ) # cannot move
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
            maxmove_x = maxmove_x = checkasternmat( blockmat, matrix, -1, escortid, strategy, escorts, items,IO, asternmat)
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