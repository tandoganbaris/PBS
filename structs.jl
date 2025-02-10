


mutable struct item
    id::Char # item id
    coords::Tuple{Int64, Int64} # x, y
    escortsx::Vector{Char} # escorts serving x now
    escortsy::Vector{Char} #escorts serving y now
    direction::Int64 # 0: not move, 1: move in x, 2: move in y
    deadline:: Float64 # deadline for the item
end
function createitem(id::Char, coords::Tuple{Int64, Int64}, deadline::Float64)
    escortsx = Vector{Char}()
    escortsy = Vector{Char}()
    direction = 0
    return item(id, coords, escortsx, escortsy, direction, deadline)
end
mutable struct escort
    id::Char # escort id
    coords::Tuple{Int64, Int64} # x, y
    itemsx::Vector{Char} # items served by x now
    itemsy::Vector{Char} # items served by y now
    fix::Bool # if the escort is fixed
end
function createescort(id::Char, coords::Tuple{Int64, Int64}, fix::Bool)
    itemsx = Vector{Char}()
    itemsy = Vector{Char}()
    return escort(id, coords, itemsx, itemsy, fix)
end
