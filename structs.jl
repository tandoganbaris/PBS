


mutable struct item
    id::Char # item id
    coords::Tuple{Int64, Int64} # x, y
    escortsx::Vector{Char} # escorts serving x now
    escortsy::Vector{Char} #escorts serving y now
    direction::Int64 # 0: not move, 1: move in x, 2: move in y
end
mutable struct escort
    id::Char # escort id
    coords::Tuple{Int64, Int64} # x, y
    itemsx::Vector{Char} # items served by x now
    itemsy::Vector{Char} # items served by y now
    fix::Bool # if the escort is fixed
end
