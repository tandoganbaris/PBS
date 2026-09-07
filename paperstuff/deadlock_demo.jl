using Plots
using Measures

const IO_DL = (1, 1)
GS = 5

# ── Scenario ──────────────────────────────────────────────────────────────────
# 5x5 warehouse, IO at (1,1).
# Three loads form a diagonal wall: L1 (1,3), L2 (2,2), L3 (3,1).
# Escort E1 sits up-and-right of the wall, at (3,3).
#
# E1 can only move straight in x or y. Both straight-line routes toward the
# IO are blocked by the diagonal wall:
#   - moving left along y=3 runs into L1 at (1,3)
#   - moving down along x=3 runs into L3 at (3,1)
# The diagonal of loads seals E1 off from the IO — a diagonal deadlock.
# ──────────────────────────────────────────────────────────────────────────────

l1_pos = (1, 3)
l2_pos = (2, 2)
l3_pos = (3, 1)
e1_pos = (3, 3)

# ── Plot: warehouse state ─────────────────────────────────────────────────────
# Cell values: 0 = free (lightblue), 1 = escort (white), 2 = load (tomato)

display_mat = zeros(Int, GS, GS)
display_mat[e1_pos...] = 1
display_mat[l1_pos...] = 2
display_mat[l2_pos...] = 2
display_mat[l3_pos...] = 2

p1 = heatmap(
    display_mat',
    color=cgrad([:lightblue, :white, :tomato], 3, categorical=true),
    clims=(0, 2),
    axis=false,
    xlims=(0.5, GS + 0.5),
    ylims=(0.5, GS + 0.5),
    aspect_ratio=:equal,
    legend=false,
    colorbar=false,
    title="Diagonal deadlock",
    titlefont=font(13),
    titlelocation=:left,
)

for c in 1:GS+1
    plot!(p1, [c-0.5, c-0.5], [0.5, GS+0.5], color=:black, lw=1)
end
for r in 1:GS+1
    plot!(p1, [0.5, GS+0.5], [r-0.5, r-0.5], color=:black, lw=1)
end

labels = Dict(l1_pos => "L1", l2_pos => "L2", l3_pos => "L3", e1_pos => "Escort")
for ((x, y), lbl) in labels
    annotate!(p1, x, y, text(lbl, :black, :center, 18))
end

# IO box
plot!(p1,
    [IO_DL[1]-0.5, IO_DL[1]+0.5, IO_DL[1]+0.5, IO_DL[1]-0.5, IO_DL[1]-0.5],
    [IO_DL[2]-0.5, IO_DL[2]-0.5, IO_DL[2]+0.5, IO_DL[2]+0.5, IO_DL[2]-0.5],
    color=:green, lw=4, fill=false)
annotate!(p1, IO_DL[1], IO_DL[2], text("I/O", :green, :center, 18))

#= # Blocked straight-line routes from E1 toward the IO (stop just short of the load)
plot!(p1, [e1_pos[1]-1, l1_pos[1]+0.5], [e1_pos[2], l1_pos[2]],
    arrow=(:closed, 2.0), color=:red, lw=2.5, linestyle=:dash)   # left, blocked by L1
plot!(p1, [e1_pos[1], l3_pos[1]], [e1_pos[2]-1, l3_pos[2]+0.5],
    arrow=(:closed, 2.0), color=:red, lw=2.5, linestyle=:dash)   # down, blocked by L3 =#

# ── Plot 2 (RIGHT): diagonal wall positions reachable from IO ─────────────────
# Arrows fanning out from the IO toward each point on the x+y=5 diagonal:
# (1,4), (2,3), (3,2), (4,1) — the set of cells a diagonal wall could occupy.

p2 = heatmap(
    display_mat',
    color=cgrad([:lightblue, :white, :tomato], 3, categorical=true),
    clims=(0, 2),
    axis=false,
    xlims=(0.5, GS + 0.5),
    ylims=(0.5, GS + 0.5),
    aspect_ratio=:equal,
    legend=false,
    colorbar=false,
    title="Positions with |B| distance from I/O",
    titlefont=font(13),
    titlelocation=:left,
)

for c in 1:GS+1
    plot!(p2, [c-0.5, c-0.5], [0.5, GS+0.5], color=:black, lw=1)
end
for r in 1:GS+1
    plot!(p2, [0.5, GS+0.5], [r-0.5, r-0.5], color=:black, lw=1)
end

for ((x, y), lbl) in labels
    annotate!(p2, x, y, text(lbl, :black, :center, 18))
end

diag_targets = [(1, 4), (2, 3), (3, 2), (4, 1)]
for (x, y) in diag_targets
    dx, dy = x - IO_DL[1], y - IO_DL[2]
    len = sqrt(dx^2 + dy^2)
    start_trim = 0.35 / len # pull the tail away from the I/O label
    end_trim = 0.3 / len    # stop the arrowhead just short of the target cell
    plot!(p2, [IO_DL[1] + dx*start_trim, x - dx*end_trim], [IO_DL[2] + dy*start_trim, y - dy*end_trim],
        arrow=(:closed, 2.0), color=:green, lw=2.0)
    annotate!(p2, x, y, text("($x,$y)", :black, :center, 11))
end

# IO box
plot!(p2,
    [IO_DL[1]-0.5, IO_DL[1]+0.5, IO_DL[1]+0.5, IO_DL[1]-0.5, IO_DL[1]-0.5],
    [IO_DL[2]-0.5, IO_DL[2]-0.5, IO_DL[2]+0.5, IO_DL[2]+0.5, IO_DL[2]-0.5],
    color=:green, lw=4, fill=false)
annotate!(p2, IO_DL[1], IO_DL[2], text("I/O", :green, :center, 18))

# ── Combined display / save ────────────────────────────────────────────────────
plot!(p1, right_margin=8mm)
plot!(p2, left_margin=2mm)
combined = plot(p1, p2, layout=(1, 2), size=(1150, 480))
display(combined)

outdir = "C:/codestuff/PBS/paperplots"
mkpath(outdir)
savefig(joinpath(outdir, "deadlock_demo.png"))
