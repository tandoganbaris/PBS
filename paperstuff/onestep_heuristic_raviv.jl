"""
Julia port of `OneStepHeuristic_v2.py` (Tal Raviv, EscortFlow_code_supplement_anon).

Ported as closely as possible to the original Python: same zone (A/B/C/D)
decomposition, same priority ordering, same guarded-move logic, same
"leave" vs "continue" retrieval-mode handling. This is what actually
produces the "Heuristic UB makespan" baseline used in the CSVs in
`paperstuff/gap_analysis*.jl` for multi-load leave-mode instances (per the
supplement's README — `PBS_DPHeuristic_bm_v2.py`, the DP-table heuristic,
only applies to the single-load case and needs an external precomputed
policy pickle that isn't in this repo).

Coordinates are kept 0-indexed (x in 0:Lx-1, y in 0:Ly-1) to mirror the
Python source exactly, rather than converting to this project's usual
1-indexed convention — that keeps this file directly diffable against the
original for validation.

Differences from the Python version, purely for Julia idiom / ergonomics:
- `onestep` always returns `(A, E, moves, escort_moves, target_move_map)`
  instead of Python's variable-arity return based on `return_escort_moves`/
  `return_target_moves` flags — callers just ignore the extras they don't need.
- Mutation is done via `copy`/`push!`/`delete!` on Dicts/Sets rather than
  Python's dict/set rebinding, since Julia containers are already mutable
  reference types.
"""

using Statistics: mean
using Random

const Loc = Tuple{Int,Int}

# ── Distance map: for each cell, the (dir_x, dir_y) sign vector toward its
# closest output, with a tie-break identical to the Python version. ─────────
function build_dist_map(Lx::Int, Ly::Int, O)
    dist_map = Dict{Loc,Loc}()
    best_dist = Dict{Loc,Float64}()
    for x in 0:Lx-1, y in 0:Ly-1
        best_dist[(x, y)] = Float64(Lx + Ly)
        for o in O
            dist = abs(x - o[1]) + abs(y - o[2]) + x / Lx + y / (Lx * Ly)  # tie-break symmetry
            if dist < best_dist[(x, y)]
                best_dist[(x, y)] = dist
                dist_map[(x, y)] = (sign(o[1] - x), sign(o[2] - y))
            end
        end
    end
    return dist_map
end

"""
Advance the heuristic by one takt.

Args mirror the Python `OneStep`:
- `Lx, Ly`: PBS dimensions.
- `O`: output cell locations, a `Set{Loc}`.
- `_A`: Dict mapping target-load locations to target ids.
- `_E`: Set of escort locations.
- `dist_map`: optional precomputed distance map from `build_dist_map`.
- `acyclic`: if true, scan targets by increasing target id; otherwise
  dynamic priority by distance to the closest output.
- `retrieval_mode`: `"continue"` — loads at outputs stop being targets but
  don't create new escorts. `"leave"` — they become escorts next step.
- `blocked_cells`: cells occupied this time step; cannot be crossed or used.

Returns `(A, E, moves, escort_moves, target_move_map)`.
"""
function onestep(Lx::Int, Ly::Int, O, _A::Dict{Loc,Int}, _E, dist_map=nothing;
                  acyclic::Bool=false, retrieval_mode::String="continue",
                  blocked_cells=nothing)

    A_new = Dict{Loc,Int}()
    E_new = Set{Loc}()
    A = copy(_A)
    E = Set{Loc}(_E)
    moves = Tuple{Loc,Loc}[]
    escort_moves = Tuple{Int,Int,Int,Int}[]
    target_move_map = Dict{Int,Tuple{Loc,Loc}}()

    for a in collect(keys(_A))
        if a in O
            delete!(A, a)
            retrieval_mode == "leave" && push!(E, a)
        end
    end

    if isempty(A)
        return A, E, moves, escort_moves, target_move_map
    end

    dm = dist_map === nothing ? build_dist_map(Lx, Ly, O) : dist_map

    cell_used = Set{Loc}(blocked_cells === nothing ? Loc[] : collect(blocked_cells))
    moved_target_ids = Set{Int}()

    for x in 0:Lx-1
        push!(cell_used, (x, -1))
        push!(cell_used, (x, Ly))
    end
    for y in 0:Ly-1
        push!(cell_used, (-1, y))
        push!(cell_used, (Lx, y))
    end

    distance_to_closest_output(loc) = minimum(abs(loc[1] - o[1]) + abs(loc[2] - o[2]) for o in O)

    function check_move(x0, y0, x1, y1)
        (x0, y0) in E || return false  # only an escort can move
        dir_x, dir_y = sign(x1 - x0), sign(y1 - y0)
        (dir_x != 0 && dir_y != 0) && return false  # no diagonals

        x, y = x0, y0
        while (x, y) != (x1, y1)
            (x, y) in cell_used && return false
            x += dir_x; y += dir_y
            (x, y) in E && return false
        end
        return !((x, y) in cell_used)
    end

    function move_escort!(x0, y0, x1, y1)
        delete!(E, (x0, y0))
        push!(E_new, (x1, y1))
        push!(escort_moves, (x0, y0, x1, y1))
        dir_x, dir_y = sign(x1 - x0), sign(y1 - y0)

        x, y = x0, y0
        while (x, y) != (x1, y1)
            push!(moves, ((x + dir_x, y + dir_y), (x, y)))
            push!(cell_used, (x, y))

            if haskey(A, (x + dir_x, y + dir_y))
                target_id = A[(x + dir_x, y + dir_y)]
                delete!(A, (x + dir_x, y + dir_y))
                A_new[(x, y)] = target_id
                push!(moved_target_ids, target_id)
                target_move_map[target_id] = ((x + dir_x, y + dir_y), (x, y))
            end
            x += dir_x; y += dir_y
        end
        push!(cell_used, (x, y))  # last cell not included in the loop
    end

    # get_targets_in_priority_order
    A_sorted = if acyclic
        sort(collect(A); by = kv -> kv[2])
    else
        function priority_key(kv)
            loc, _ = kv
            closest_output = argmin(o -> (abs(loc[1] - o[1]) + abs(loc[2] - o[2]), o[1], o[2]), collect(O))
            return (abs(loc[1] - closest_output[1]) + abs(loc[2] - closest_output[2]),
                    closest_output[1], closest_output[2], loc[1], loc[2])
        end
        sort(collect(A); by = priority_key)
    end
    priority_rank = Dict(target_id => idx for (idx, (_, target_id)) in enumerate(A_sorted))

    function move_hurts_lower_priority_targets(x0, y0, x1, y1, current_priority_rank)
        dir_x, dir_y = sign(x1 - x0), sign(y1 - y0)
        x, y = x0, y0
        while (x, y) != (x1, y1)
            next_x, next_y = x + dir_x, y + dir_y
            if haskey(A, (next_x, next_y))
                moved_target_id = A[(next_x, next_y)]
                if priority_rank[moved_target_id] > current_priority_rank
                    current_dist = distance_to_closest_output((next_x, next_y))
                    next_dist = distance_to_closest_output((x, y))
                    next_dist > current_dist && return true
                end
            end
            x, y = next_x, next_y
        end
        return false
    end

    function extend_move_for_lower_priority_targets(x0, y0, x1, y1)
        dir_x, dir_y = sign(x1 - x0), sign(y1 - y0)
        (dir_x == 0 && dir_y == 0) && return (x1, y1)

        best_x, best_y = x1, y1
        xx, yy = x1, y1

        while !((xx + dir_x, yy + dir_y) in E) && !((xx + dir_x, yy + dir_y) in cell_used)
            xx += dir_x; yy += dir_y
            if haskey(A, (xx, yy))
                target_dir = dm[(xx, yy)]
                if (dir_x != 0 && target_dir[1] == dir_x) || (dir_y != 0 && target_dir[2] == dir_y)
                    best_x, best_y = xx, yy
                end
            end
        end
        return (best_x, best_y)
    end

    function choose_guarded_move(candidates, current_priority_rank)
        fallback_move = nothing
        for (x0, y0, x1, y1) in candidates
            check_move(x0, y0, x1, y1) || continue

            x1_ext, y1_ext = extend_move_for_lower_priority_targets(x0, y0, x1, y1)
            if !move_hurts_lower_priority_targets(x0, y0, x1_ext, y1_ext, current_priority_rank)
                return (x0, y0, x1_ext, y1_ext)
            end
            if current_priority_rank == 0 && fallback_move === nothing
                fallback_move = (x0, y0, x1_ext, y1_ext)
            end
        end
        return fallback_move
    end

    """
    Zoning around a target load (see Python OneStepHeuristic_v2.find_zone_escorts
    docstring for the full ASCII diagrams):
      A: same row/column as the target, in the output direction
      B: not in A, but sharing a row/column with an A-cell, not on the target's row/column
      C: not in A or B, but sharing a row/column with a B-cell
      D: not in A, B, or C, but sharing a row/column with a C-cell
    """
    function find_zone_escorts(x_target, y_target)
        A_dir = dm[(x_target, y_target)]
        has_horizontal_a = A_dir[1] != 0
        has_vertical_a = A_dir[2] != 0

        in_horizontal_a(x) = has_horizontal_a && sign(x - x_target) == A_dir[1]
        in_vertical_a(y) = has_vertical_a && sign(y - y_target) == A_dir[2]

        is_zone_a(x, y) = (y == y_target && in_horizontal_a(x)) || (x == x_target && in_vertical_a(y))
        is_zone_b(x, y) = !is_zone_a(x, y) && x != x_target && y != y_target && (in_horizontal_a(x) || in_vertical_a(y))
        row_has_zone_b(y) = y != y_target && (has_horizontal_a || in_vertical_a(y))
        col_has_zone_b(x) = x != x_target && (has_vertical_a || in_horizontal_a(x))
        is_zone_c(x, y) = !is_zone_a(x, y) && !is_zone_b(x, y) && (row_has_zone_b(y) || col_has_zone_b(x))
        function is_zone_d(x, y)
            (is_zone_a(x, y) || is_zone_b(x, y) || is_zone_c(x, y)) && return false
            if has_horizontal_a && !has_vertical_a
                return y == y_target && sign(x - x_target) == -A_dir[1]
            end
            if has_vertical_a && !has_horizontal_a
                return x == x_target && sign(y - y_target) == -A_dir[2]
            end
            return false
        end

        zone_a, zone_b, zone_c, zone_d = Set{Loc}(), Set{Loc}(), Set{Loc}(), Set{Loc}()
        for (x_escort, y_escort) in E
            escort = (x_escort, y_escort)
            if is_zone_a(x_escort, y_escort)
                push!(zone_a, escort)
            elseif is_zone_b(x_escort, y_escort)
                push!(zone_b, escort)
            elseif is_zone_c(x_escort, y_escort)
                push!(zone_c, escort)
            elseif is_zone_d(x_escort, y_escort)
                push!(zone_d, escort)
            end
        end
        return zone_a, zone_b, zone_c, zone_d
    end

    sort_escorts_by_distance(x, y, EE) =
        sort(collect(EE); by = e -> (abs(e[1] - x) + abs(e[2] - y), e[1], e[2]))

    for i in 1:length(A_sorted)
        (x0, y0), target_id = A_sorted[i]

        if target_id in moved_target_ids
            continue  # a higher-priority target already moved this load this takt
        end

        # Try to move the item immediately in the right direction: escort A -> C/D
        zone_a, zone_b, zone_c, zone_d = find_zone_escorts(x0, y0)
        lst = sort_escorts_by_distance(x0, y0, zone_a)
        candidates = [(xe, ye, x0, y0) for (xe, ye) in lst]

        chosen_move = choose_guarded_move(candidates, i - 1)  # 0-indexed rank, matches Python
        if chosen_move !== nothing
            x_escort, y_escort, x1, y1 = chosen_move
            dx, dy = sign(x0 - x_escort), sign(y0 - y_escort)  # only one is nonzero
            move_escort!(x_escort, y_escort, x1, y1)
            x0, y0 = x0 - dx, y0 - dy
            zone_a, zone_b, zone_c, zone_d = find_zone_escorts(x0, y0)
        end
        push!(cell_used, (x0, y0))

        # zone B -> A
        lst = sort_escorts_by_distance(x0, y0, zone_b)
        candidates = Tuple{Int,Int,Int,Int}[]
        for (xe, ye) in lst
            if sign(ye - y0) == dm[(x0, y0)][2]  # escort "below" the load
                push!(candidates, (xe, ye, x0, ye))
            else
                push!(candidates, (xe, ye, xe, y0))
            end
        end
        chosen_move = choose_guarded_move(candidates, i - 1)
        chosen_move !== nothing && move_escort!(chosen_move...)

        # zone C -> B
        lst = sort_escorts_by_distance(x0, y0, zone_c)
        candidates = Tuple{Int,Int,Int,Int}[]
        for (xe, ye) in lst
            dir_x, dir_y = dm[(x0, y0)]
            if dir_x == 0
                push!(candidates, (xe, ye, xe, y0 + dir_y))
            elseif dir_y == 0
                push!(candidates, (xe, ye, x0 + dir_x, ye))
            elseif sign(y0 - ye) == dir_y  # escort "above" the load
                push!(candidates, (xe, ye, x0 + dir_x, ye))
            else
                push!(candidates, (xe, ye, xe, y0 + dir_y))
            end
        end
        chosen_move = choose_guarded_move(candidates, i - 1)
        chosen_move !== nothing && move_escort!(chosen_move...)

        # zone D -> C
        lst = sort_escorts_by_distance(x0, y0, zone_d)
        candidates = Tuple{Int,Int,Int,Int}[]
        for (xe, ye) in lst
            dir_x, dir_y = dm[(x0, y0)]
            if dir_y == 0
                push!(candidates, (xe, ye, xe, ye + 1))
                push!(candidates, (xe, ye, xe, ye - 1))
            elseif dir_x == 0
                push!(candidates, (xe, ye, xe + 1, ye))
                push!(candidates, (xe, ye, xe - 1, ye))
            elseif sign(y0 - ye) == dir_y  # escort "above" the load
                push!(candidates, (xe, ye, xe + 1, ye))
                push!(candidates, (xe, ye, xe - 1, ye))
            else
                push!(candidates, (xe, ye, xe, ye + 1))
                push!(candidates, (xe, ye, xe, ye - 1))
            end
        end
        chosen_move = choose_guarded_move(candidates, i - 1)
        chosen_move !== nothing && move_escort!(chosen_move...)
    end

    merge!(A, A_new)
    return A, union(E, E_new), moves, escort_moves, target_move_map
end

"""
Repeatedly apply `onestep` until all target loads are retrieved.
Returns `(makespan, flow_time, movements, move_history)`.
"""
function solve_greedy(Lx::Int, Ly::Int, O, _A, _E; verbal::Bool=false, max_steps::Int=500,
                       acyclic::Bool=false, retrieval_mode::String="continue")
    ordered_targets = sort(collect(Set(_A));
        by = a -> (minimum(abs(a[1] - o[1]) + abs(a[2] - o[2]) for o in O), a[1], a[2]))
    all_targets = Dict{Loc,Int}(loc => idx for (idx, loc) in enumerate(ordered_targets))

    local A::Dict{Loc,Int}, current_output_stays::Dict{Loc,Int}
    if retrieval_mode == "leave"
        A = Dict(loc => tid for (loc, tid) in all_targets if !(loc in O))
        current_output_stays = Dict(loc => tid for (loc, tid) in all_targets if loc in O)
    else
        A = copy(all_targets)
        current_output_stays = Dict{Loc,Int}()
    end
    E = Set{Loc}(_E)

    dist_map = build_dist_map(Lx, Ly, O)

    verbal && println("initial A = $A\ninitial E = $E")

    flow_time = 0
    makespan = 0
    movements = 0
    move_history = Vector{Vector{Tuple{Loc,Loc}}}()

    while !isempty(A)
        flow_time += length(A)

        one_step_retrieval_mode = retrieval_mode == "leave" ? "continue" : retrieval_mode
        blocked = retrieval_mode == "leave" ? Set(keys(current_output_stays)) : nothing

        next_A, next_E, mv, _, _ = onestep(Lx, Ly, O, A, E, dist_map;
            acyclic = acyclic, retrieval_mode = one_step_retrieval_mode, blocked_cells = blocked)

        if retrieval_mode == "leave"
            A = Dict(loc => tid for (loc, tid) in next_A if !(loc in O))
            E = union(next_E, Set(keys(current_output_stays)))
            current_output_stays = Dict(loc => tid for (loc, tid) in next_A if loc in O)
        else
            A, E = next_A, next_E
        end

        push!(move_history, mv)
        verbal && println("After step: $makespan\nA $A\nE $E\nMoves $mv")
        makespan += 1
        movements += length(mv)

        if makespan >= max_steps
            error("Panic: could not solve in $max_steps steps")
        end
    end

    return makespan, flow_time, movements, move_history
end

# ── Random instance generator, mirroring PBSCom.GeneretaeRandomInstance ──────
function generate_random_instance(rng, locations::Vector{Loc}, num_escorts::Int, num_load::Int=1)
    shuffled = shuffle(rng, locations)
    return sort(shuffled[1:num_load]), sort(shuffled[num_load+1:num_load+num_escorts])
end

# ── Standalone smoke test / mini-benchmark, mirroring the Python __main__ ────
function run_minibenchmark()
    O = Set{Loc}([(0, 0)])
    Lx, Ly = 10, 10
    locations = Loc[(x, y) for x in 0:Lx-1 for y in 0:Ly-1]

    num_of_loads = 4
    n = 1000
    total_makespan = 0
    total_flow_time = 0
    total_movements = 0

    rng = MersenneTwister(0)
    for seed in 0:n-1
        Random.seed!(rng, seed)
        loads, escorts = generate_random_instance(rng, locations, 12, num_of_loads)
        step_cap = (Lx + Ly) * num_of_loads * 20 ÷ 12
        makespan, flow_time, movements, _ = solve_greedy(Lx, Ly, O, Set(loads), Set(escorts);
            max_steps = step_cap)
        total_makespan += makespan
        total_flow_time += flow_time
        total_movements += movements
    end

    println("makespan $(total_makespan/n)")
    println("total flow_time $(total_flow_time/n)")
    println("mean flowtime $(total_flow_time/n/num_of_loads)")
    println("movements $(total_movements/n)")
end

if abspath(PROGRAM_FILE) == @__FILE__
    run_minibenchmark()
end
