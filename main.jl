
function main(initialstate, picklist)
    itemstopick = deepcopy(picklist)
    incumbentstate = deepcopy(initialstate)
    n= 3 # batch size
    r = 1 # replenishment size
    batch = createbatch(itemstopick, incumbentstate, time, n)
    escorts = findescorts(incumbentstate) # escorts char may have identifier? like E1, E2, E3
    time = 0
    while isempty(itemstopick) == false
        if length(batchofids) <= n-r #decide on batch 
            newcandidates = createbatch(itemstopick, incumbentstate, time, r) 
            push!(batch, newcandidates)
        end
    
        #save escorts for items # done
        save_item_escorts!(incumbentstate, items, escorts, IO)
        #assign escorts for items unique # mostly done
        moverescortids, blockmat = item_escort_assigment!(incumbentstate, items, escorts, IO) 

        
        #save future coords of items # not done, blockmat done
        #decide where the escorts should land after moving # todo
        #move blocks with escorts,  # todo, use blockmat and escort assignment
        #move remaining escorts to best positon # use blockmat 
        moveescorts!(incumbentstate, items, escorts, moverescortids, blockmat, IO)
        time +=1
    end
end
