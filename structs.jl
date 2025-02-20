


mutable struct item
    id::String # item id
    coords::Tuple{Int64, Int64} # x, y
    escortssum::Int64 # escorts that can serve item
    direction::Int64 # 0: not move, 1: move in x, 2: move in y
    deadline:: Float64 # deadline for the item
end
function createitem(id::String, coords::Tuple{Int64, Int64}, deadline::Float64)
    escorts= 0
    direction = 0
    return item(id, coords, escorts, direction, deadline)
end
mutable struct escort
    id::String # escort id
    coords::Tuple{Int64, Int64} # x, y
    itemsx::Vector{String} # items served by x now
    itemsy::Vector{String} # items served by y now
    lastmoved::Int64 # if the escort is fixed
    banset:: Dict{Int64, Vector{String}} # items that cannot be served by the escort
    tabu::Vector{Tuple{Int64, Int64}} # tabu list
end
function createescort(id::String, coords::Tuple{Int64, Int64}, lastmoved::Int64= 0)
    itemsx = Vector{String}()
    itemsy = Vector{String}()
    banset = Dict{Int64, Vector{String}}()
    tabu = Vector{Tuple{Int64, Int64}}()
    return escort(id, coords, itemsx, itemsy, lastmoved, banset, tabu)
end
