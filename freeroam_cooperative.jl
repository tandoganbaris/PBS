# freeroam_cooperative.jl
#
# Drop-in replacement for the sequential nonmover freeroam loop.
# Uses cooperative A* to plan all nonmover escorts' single-step moves jointly,
# minimizing (steps to IO + turn count) per escort while keeping moves conflict-free.
#
# Integration — replace the freeroam loop in moveescorts_makespan! (around line 1561):
#
#   nonmovers_free = [eid for eid in nonmovers
#                     if blockmat[escorts[eid].coords[1], escorts[eid].coords[2]] != 1]
#   moved_any += cooperative_freeroam!(iteration, matrix, items, escorts,
#                                      nonmovers_free, blockmat, IO)

using DataStructures

# ─── A* from escort → IO ──────────────────────────────────────────────────────
#
# State: (x, y, dir), dir ∈ {1=initial, 2=horizontal, 3=vertical}
# Edge cost: 1 per step + 1 if direction changes (turn penalty).
# `extra_blocked`: cells reserved by previously-planned escorts (in addition to blockmat).
#
# Returns (path, cost). path = [(sx,sy), …, (iox,ioy)], empty if unreachable.
function _escort_astar(
        start         :: Tuple{Int,Int},
        IO            :: Tuple{Int,Int},
        blockmat      :: AbstractMatrix,
        extra_blocked :: Set{Tuple{Int,Int}},
        rows          :: Int,
        cols          :: Int
    ) :: Tuple{Vector{Tuple{Int,Int}}, Float64}

    sx, sy = start
    gx, gy = IO

    dist     = fill(Inf, rows, cols, 3)
    has_from = fill(false, rows, cols, 3)
    from     = Array{Tuple{Int,Int,Int}}(undef, rows, cols, 3)

    heap    = BinaryMinHeap{Tuple{Float64,Int,Int,Int}}()
    visited = fill(false, rows, cols, 3)

    h(x, y) = Float64(abs(x - gx) + abs(y - gy))

    dist[sx, sy, 1] = 0.0
    push!(heap, (h(sx, sy), sx, sy, 1))

    while !isempty(heap)
        (_, cx, cy, cd) = pop!(heap)
        visited[cx, cy, cd] && continue
        visited[cx, cy, cd] = true

        if cx == gx && cy == gy
            # reconstruct path by following `from` pointers back to start
            path = Tuple{Int,Int}[]
            x, y, d = cx, cy, cd
            while true
                push!(path, (x, y))
                !has_from[x, y, d] && break   # reached start (no parent set)
                x, y, d = from[x, y, d]
            end
            return reverse!(path), dist[cx, cy, cd]
        end

        for (nx, ny) in ((cx+1,cy),(cx-1,cy),(cx,cy+1),(cx,cy-1))
            (1 ≤ nx ≤ rows && 1 ≤ ny ≤ cols) || continue
            blockmat[nx, ny] == 1             && continue
            (nx, ny) ∈ extra_blocked          && continue

            nd   = (nx == cx) ? 3 : 2          # same x → vertical, else horizontal
            turn = (cd == 1 || cd == nd) ? 0.0 : 1.0
            g    = dist[cx, cy, cd] + 1.0 + turn

            if g < dist[nx, ny, nd]
                dist[nx, ny, nd]     = g
                from[nx, ny, nd]     = (cx, cy, cd)
                has_from[nx, ny, nd] = true
                push!(heap, (g + h(nx, ny), nx, ny, nd))
            end
        end
    end

    return Tuple{Int,Int}[], Inf   # IO unreachable from this start
end


# ─── cooperative planner ───────────────────────────────────────────────────────
#
# Why cooperative instead of sequential freeroam!?
#   - freeroam! uses hand-coded heuristics (go down, go sideways, etc.).
#     Each escort plans independently, so two escorts can choose conflicting
#     targets or cancel each other out with no global awareness.
#   - Here, all escorts share a single growing `reserved` set. The escort
#     closest to IO plans first and claims a cell; escorts farther away
#     automatically route around it. The turn penalty in the A* cost means
#     the planner naturally prefers L-shaped paths (one turn) over zigzags.
#
# Conflict types handled:
#   1. Same target  → later escort (farther from IO) routes around the first.
#   2. Swap         → A→B's cell while B→A's cell. Resolved post-planning:
#                     the escort farther from IO yields (stays put).
#
# `nonmovers`: pre-filtered to exclude escorts on blocked (blockmat==1) cells.
function cooperative_freeroam!(
        iteration :: Int,
        matrix    :: AbstractMatrix,
        items     :: Dict,
        escorts   :: Dict,
        nonmovers :: Vector,
        blockmat  :: AbstractMatrix,
        IO        :: Tuple{Int,Int}
    ) :: Int

    isempty(nonmovers) && return 0

    rows, cols = size(matrix)
    iox, ioy   = IO
    mdist(c)   = abs(c[1] - iox) + abs(c[2] - ioy)

    # ── planning order: closest-to-IO first ─────────────────────────────────
    # Closest escorts claim positions first; farther ones adapt.
    order = sort(collect(nonmovers), by = id -> mdist(escorts[id].coords))

    # ── build the static blocked set ────────────────────────────────────────
    # Items and mover (assigned) escorts are treated as permanent obstacles.
    # Other nonmovers are NOT pre-blocked: they will move, so their current
    # cells become available. We handle conflicts via `reserved` as we plan.
    reserved = Set{Tuple{Int,Int}}()
    for iid in keys(items)
        push!(reserved, items[iid].coords)
    end
    for eid in keys(escorts)
        eid ∈ nonmovers && continue
        push!(reserved, escorts[eid].coords)
    end

    # ── plan one step per escort ─────────────────────────────────────────────
    planned = Dict{Any, Tuple{Int,Int}}()   # escortid → intended next cell

    for eid in order
        esc    = escorts[eid]
        sx, sy = esc.coords

        # already at IO: best position, no move needed
        if (sx, sy) == IO
            planned[eid] = IO
            push!(reserved, IO)
            continue
        end

        # remove own cell temporarily so A* can start there without treating
        # it as a wall (it may have been added by a previous escort's old cell)
        delete!(reserved, (sx, sy))

        path, _ = _escort_astar((sx, sy), IO, blockmat, reserved, rows, cols)

        # pick the next cell: path[2] is the first step toward IO.
        # fall back to staying if path is blocked or the step is in tabu.
        target = if length(path) >= 2 && path[2] ∉ esc.tabu
            path[2]
        else
            (sx, sy)
        end

        planned[eid] = target
        push!(reserved, target)   # claim target; later escorts route around it
        # do not re-add (sx,sy): this escort is leaving, later escorts can use it
    end

    # ── resolve swap conflicts ───────────────────────────────────────────────
    # Swap: A wants B's current cell AND B wants A's current cell.
    # The escort farther from IO yields (its move is cancelled).
    changed = true
    while changed
        changed = false
        ids = collect(keys(planned))
        for i in eachindex(ids)
            for j in i+1:length(ids)
                a, b   = ids[i], ids[j]
                ca, cb = escorts[a].coords, escorts[b].coords
                if planned[a] == cb && planned[b] == ca
                    loser = mdist(ca) >= mdist(cb) ? a : b
                    planned[loser] = escorts[loser].coords
                    changed = true
                end
            end
        end
    end

    # ── apply moves ─────────────────────────────────────────────────────────
    moved_count = 0
    for eid in order
        esc    = escorts[eid]
        sx, sy = esc.coords
        tx, ty = planned[eid]
        (sx, sy) == (tx, ty) && continue

        push!(esc.tabu, (sx, sy))
        move_escort!(matrix, items, escorts, eid, (tx, ty))
        updateblockmat_e!(blockmat, sx, sy, tx, ty)
        escorts[eid].lastmoved = iteration
        moved_count += 1
    end

    return moved_count
end
