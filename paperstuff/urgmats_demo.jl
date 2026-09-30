include("../structs.jl")

using Plots
using Measures

const IO_UM = (1, 1)
GS = 5  # grid size

# ── The function under test (copied verbatim from move.jl) ──────────────────
function urgmats(items, escorts, blockmat, matrix, urgentcustomers, IO)
    allkeys = union(keys(escorts), keys(items))
    urgmats = Dict{String, Matrix{Int}}()
    if !isempty(urgentcustomers)
        for customer_id in urgentcustomers
            urgmat = deepcopy(blockmat)
            urgx, urgy = items[customer_id].coords
            urgmat[urgx, urgy] = 3
            dir = urgx > IO[1] ? -1 : 1
            if urgx != IO[1]
                if dir == 1
                    for xx in min(urgx+1, size(matrix, 1)):IO[1]
                        if !(matrix[xx, urgy] in allkeys)
                            for y in min(urgy+1, size(matrix,2)):size(matrix, 2)
                                if blockmat[xx, y] == 0 && !(haskey(items, matrix[xx, y]))
                                    urgmat[xx, y] = 2
                                else
                                    break
                                end
                            end
                        else
                            break
                        end
                    end
                else
                    for xx in max(urgx-1, 1):-1:IO[1]
                        if !(matrix[xx, urgy] in allkeys)
                            for y in min(urgy+1, size(matrix,2)):size(matrix, 2)
                                if blockmat[xx, y] == 0 && !(haskey(items, matrix[xx, y]))
                                    urgmat[xx, y] = 2
                                else
                                    break
                                end
                            end
                        else
                            break
                        end
                    end
                end
            end
            if urgy != IO[2]
                for yy in urgy-1:-1:IO[2]
                    if !(matrix[urgx, yy] in allkeys)
                        if dir == -1 || urgx == IO[1]
                            for x in min(urgx+1, size(matrix, 1)):size(matrix, 1)
                                if blockmat[x, yy] == 0 && !(haskey(items, matrix[x, yy]))
                                    urgmat[x, yy] = 2
                                else
                                    break
                                end
                            end
                        end
                        if dir == 1 || urgx == IO[1]
                            for x in max(urgx-1, 1):-1:IO[1]
                                if blockmat[x, yy] == 0 && !(haskey(items, matrix[x, yy]))
                                    urgmat[x, yy] = 2
                                else
                                    break
                                end
                            end
                        end
                    else
                        break
                    end
                end
            end
            urgmats[customer_id] = urgmat
        end
    end
    return urgmats
end

# ── Scenario ──────────────────────────────────────────────────────────────────
# 5x5 warehouse, IO at (1,1).
# L1 (urgent item) at (4,3). L2 (another item) at (2,4), directly above L1's row.
# Escort E1 at (5,5) — further right and up than L1, not yet positioned to serve it.
#
# blockmat blocks y = urgy+1 for x = 1 .. urgx (except L2's cell) — i.e.
# (1,4),(3,4),(4,4) — so together with L2 the whole row above L1 is sealed.
#
# Effect: the horizontal arm (columns 3,2,1, scanning upward from y=urgy+1=4)
# hits a block or L2 on its very first step at every column it tries, so it
# marks nothing — the arm is killed before it can start. The vertical arm
# (rows y=2,1, scanning right from L1) is untouched and marks (5,2) and (5,1).
# ──────────────────────────────────────────────────────────────────────────────

l1_pos = (4, 3)
l2_pos = (2, 4)
e1_pos = (5, 5)

item_l1 = createitem("L1", l1_pos, 0.0)
item_l2 = createitem("L2", l2_pos, 100.0)
items   = Dict("L1" => item_l1, "L2" => item_l2)
escort1 = createescort("E1", e1_pos)
escorts = Dict("E1" => escort1)

state = fill("", GS, GS)
state[l1_pos...] = "L1"
state[l2_pos...] = "L2"
state[e1_pos...] = "Escort"

blockmat = zeros(Int, GS, GS)
urgx, urgy = l1_pos
for x in 1:urgx
    (x, urgy+1) != l2_pos && (blockmat[x, urgy+1] = 1)
end

result = urgmats(items, escorts, blockmat, state, ["L1"], IO_UM)
urgmat = result["L1"]

# ── Plot 1: Warehouse state ───────────────────────────────────────────────────
# Cell values: 0 = free, 1 = blocked, 3 = items (tomato), 4 = escort (white)

display_before = zeros(Int, GS, GS)
for x in 1:GS, y in 1:GS
    if blockmat[x, y] == 1
        display_before[x, y] = 1
    end
end
display_before[l1_pos...] = 3
display_before[l2_pos...] = 3
display_before[e1_pos...] = 4

p1 = heatmap(
    display_before',
    color=cgrad([:lightblue, :lightgrey, :orange, :tomato, :white], 5, categorical=true),
    clims=(0, 4),
    axis=false,
    xlims=(0.5, GS + 0.5),
    ylims=(0.5, GS + 0.5),
    aspect_ratio=:equal,
    legend=false,
    colorbar=false,
    title="3-Step Service: Escort must serve urgent L1",
    titlefont=font(13),
    titlelocation=:left,
)

for c in 1:GS+1
    plot!(p1, [c-0.5, c-0.5], [0.5, GS+0.5], color=:black, lw=1)
end
for r in 1:GS+1
    plot!(p1, [0.5, GS+0.5], [r-0.5, r-0.5], color=:black, lw=1)
end

labels1 = Dict(l1_pos => "L1", l2_pos => "L2", e1_pos => "Escort")
for ((x, y), lbl) in labels1
    annotate!(p1, x, y, text(lbl, :black, :center, 18))
end

# IO box
plot!(p1,
    [IO_UM[1]-0.5, IO_UM[1]+0.5, IO_UM[1]+0.5, IO_UM[1]-0.5, IO_UM[1]-0.5],
    [IO_UM[2]-0.5, IO_UM[2]-0.5, IO_UM[2]+0.5, IO_UM[2]+0.5, IO_UM[2]-0.5],
    color=:green, lw=4, fill=false)
annotate!(p1, IO_UM[1], IO_UM[2], text("I/O", :green, :center, 18))

# Red frame around the urgent item L1
plot!(p1,
    [l1_pos[1]-0.5, l1_pos[1]+0.5, l1_pos[1]+0.5, l1_pos[1]-0.5, l1_pos[1]-0.5],
    [l1_pos[2]-0.5, l1_pos[2]-0.5, l1_pos[2]+0.5, l1_pos[2]+0.5, l1_pos[2]-0.5],
    color=:red, lw=3, fill=false)

# ── Plot 2: Urgmat (interception zones) ──────────────────────────────────────
# Cell values: 0 = free, 1 = blocked, 2 = zone (orange), 3 = L1, 4 = escort

display_mat = copy(urgmat)
display_mat[l2_pos...] = 3
display_mat[e1_pos...] = 4

p2 = heatmap(
    display_mat',
    color=cgrad([:lightblue, :lightgrey, :orange, :tomato, :white], 5, categorical=true),
    clims=(0, 4),
    axis=false,
    xlims=(0.5, GS + 0.5),
    ylims=(0.5, GS + 0.5),
    aspect_ratio=:equal,
    legend=false,
    colorbar=false,
    title="Urgmat: zone (orange) around L1",
    titlefont=font(13),
    titlelocation=:left,
)

for c in 1:GS+1
    plot!(p2, [c-0.5, c-0.5], [0.5, GS+0.5], color=:black, lw=1)
end
for r in 1:GS+1
    plot!(p2, [0.5, GS+0.5], [r-0.5, r-0.5], color=:black, lw=1)
end

labels2 = Dict(l1_pos => "L1", l2_pos => "L2", e1_pos => "Escort")
for ((x, y), lbl) in labels2
    annotate!(p2, x, y, text(lbl, :black, :center, 18))
end

# IO box
plot!(p2,
    [IO_UM[1]-0.5, IO_UM[1]+0.5, IO_UM[1]+0.5, IO_UM[1]-0.5, IO_UM[1]-0.5],
    [IO_UM[2]-0.5, IO_UM[2]-0.5, IO_UM[2]+0.5, IO_UM[2]+0.5, IO_UM[2]-0.5],
    color=:green, lw=4, fill=false)
annotate!(p2, IO_UM[1], IO_UM[2], text("I/O", :green, :center, 18))

# Red frame around the urgent item L1
plot!(p2,
    [l1_pos[1]-0.5, l1_pos[1]+0.5, l1_pos[1]+0.5, l1_pos[1]-0.5, l1_pos[1]-0.5],
    [l1_pos[2]-0.5, l1_pos[2]-0.5, l1_pos[2]+0.5, l1_pos[2]+0.5, l1_pos[2]-0.5],
    color=:red, lw=3, fill=false)

# Arrow to the orange cell closest to the Escort, marked with a checkmark
orange_cells = [(x, y) for x in 1:GS, y in 1:GS if urgmat[x, y] == 2]
closest_orange = argmin(c -> (c[1]-e1_pos[1])^2 + (c[2]-e1_pos[2])^2, orange_cells)

arrow_end_y = closest_orange[2] + 0.4 * sign(e1_pos[2] - closest_orange[2])
plot!(p2, [e1_pos[1], closest_orange[1]], [e1_pos[2]-0.2, arrow_end_y],
    arrow=(:closed, 2.0), color=:black, lw=2)
annotate!(p2, closest_orange[1], closest_orange[2], text("✓", :black, :center, 20))

# ── Combined display ──────────────────────────────────────────────────────────
#= plot!(p1, right_margin=-5mm)
plot!(p2, left_margin=-5mm)
combined = plot(p1, p2, layout=(1, 2), size=(1000, 480)) =#
plot!(p1, right_margin=8mm)
plot!(p2, left_margin=2mm)
combined = plot(p1, p2, layout=(1, 2), size=(1150, 480))
display(combined)

outdir = "C:/codestuff/PBS/paperplots"
mkpath(outdir)
savefig(joinpath(outdir, "urgmats_demo.png"))
