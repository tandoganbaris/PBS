


mutable struct item
    id::String # item id
    coords::Tuple{Int64, Int64} # x, y
    escortsx::Vector{String} # escorts serving x now
    escortsy::Vector{String} #escorts serving y now
    direction::Int64 # 0: not move, 1: move in x, 2: move in y
    deadline:: Float64 # deadline for the item
end
function createitem(id::String, coords::Tuple{Int64, Int64}, deadline::Float64)
    escortsx = Vector{String}()
    escortsy = Vector{String}()
    direction = 0
    return item(id, coords, escortsx, escortsy, direction, deadline)
end
mutable struct escort
    id::String # escort id
    coords::Tuple{Int64, Int64} # x, y
    itemsx::Vector{String} # items served by x now
    itemsy::Vector{String} # items served by y now
    lastmoved::Int64 # if the escort is fixed
end
function createescort(id::String, coords::Tuple{Int64, Int64}, lastmoved::Int64= 0)
    itemsx = Vector{String}()
    itemsy = Vector{String}()
    return escort(id, coords, itemsx, itemsy, lastmoved)
end
