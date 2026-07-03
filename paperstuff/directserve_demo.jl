include("../structs.jl")
include("../pbsviz.jl")

using Plots
using Measures

const IO_DS = (1, 1)
GS = 8

# ── Scenario ──────────────────────────────────────────────────────────────────
# 8x8 warehouse, IO at (1,1).
# Escort E1 at (2,2). Item I1 (normal) at (6,7).
# urgcusts is empty — no urgent items, so the normal loop runs.
#
# directserve_flow! evaluates two approaches for I1:
#
#   Y-approach: escort stays at x=2, moves to item's y=7  → target (2,7)
#     Condition: IO[1]=1 < itemx=6 AND esc_x=2 < itemx=6  ✓ (same side)
#     ygap = |esc_y - itemy| = |2-7| = 5
#
#   X-approach: escort moves to item's x=6, stays at y=2  → target (6,2)
#     Condition: esc_y=2 < itemy=7  ✓ (escort below item)
#     xgap = |esc_x - itemx| = |2-6| = 4
#
# Decision: distx(4) < disty(5)  →  X-approach wins  →  move to (6,2)
# Escort gets in front of I1 in the Y-lane; next iteration it serves I1.
# ──────────────────────────────────────────────────────────────────────────────

item1   = createitem("I1", (6, 7), 1000.0)
escort1 = createescort("E1", (2, 2))

items   = Dict("I1" => item1)
escorts = Dict("E1" => escort1)

state = fill("0", GS, GS)
state[6, 7] = "I1"
state[2, 2] = "E1"

esc_x, esc_y = escort1.coords   # (2,2)
itemx, itemy = item1.coords     # (6,7)

target_Y = (esc_x, itemy)       # (2,7) — Y-approach, ygap=5, rejected
target_X = (itemx, esc_y)       # (6,2) — X-approach, xgap=4, WINNER

# ── Plot 1: Warehouse state ───────────────────────────────────────────────────
p1 = plot_matrix(state, items, escorts, IO_DS)
title!(p1, "Warehouse: E1 movement choice (green=chosen, yellow=rejected, red=item, white=escort)", titlelocation=:left,titlefont=font(12))

# ── Plot 2: Decision map ──────────────────────────────────────────────────────
# Values: 0=free, 2=item, 4=escort, 5=chosen, 6=rejected

display_mat = zeros(Int, GS, GS)
display_mat[itemx, itemy]             = 2
display_mat[esc_x, esc_y]             = 4
display_mat[target_X[1], target_X[2]] = 5
display_mat[target_Y[1], target_Y[2]] = 6

p2 = heatmap(
    display_mat',
    color=cgrad([:lightblue, :lightgrey, :tomato, :tomato, :white, :limegreen, :yellow], 7, categorical=true),
    clims=(0, 6),
    axis=false,
    xlims=(0.5, GS + 0.5),
    ylims=(0.5, GS + 0.5),
    aspect_ratio=:equal,
    legend=false,
    colorbar=false,
)

for c in 1:GS+1
    plot!(p2, [c-0.5, c-0.5], [0.5, GS+0.5], color=:black, lw=1)
end
for r in 1:GS+1
    plot!(p2, [0.5, GS+0.5], [r-0.5, r-0.5], color=:black, lw=1)
end

cell_labels = Dict(2 => "I1", 4 => "E1", 5 => "✓", 6 => "✗")
for x in 1:GS, y in 1:GS
    lbl = get(cell_labels, display_mat[x, y], "")
    if lbl != ""
        annotate!(p2, x, y, text(lbl, :black, :center, 13))
    end
end

# IO box
plot!(p2,
    [IO_DS[1]-0.5, IO_DS[1]+0.5, IO_DS[1]+0.5, IO_DS[1]-0.5, IO_DS[1]-0.5],
    [IO_DS[2]-0.5, IO_DS[2]-0.5, IO_DS[2]+0.5, IO_DS[2]+0.5, IO_DS[2]-0.5],
    color=:green, lw=4, fill=false)
annotate!(p2, IO_DS[1], IO_DS[2], text("IO", :green, :center, 11))

# Rejected Y-approach arrow (dashed grey)
plot!(p2, [esc_x, target_Y[1]], [esc_y, target_Y[2]],
    arrow=(:closed, 1.5), color=:grey, lw=1.5, linestyle=:dash)
annotate!(p2, esc_x + 0.35, (esc_y + target_Y[2])/2,
    text("ygap=5", :grey, :left, 9))

# Chosen X-approach arrow (solid black)
plot!(p2, [esc_x, target_X[1]], [esc_y, target_X[2]],
    arrow=(:closed, 2.5), color=:black, lw=2.5)
annotate!(p2, (esc_x + target_X[1])/2, esc_y - 0.3,
    text("xgap=4 ✓", :black, :center, 9))

# ── Combined display ──────────────────────────────────────────────────────────
plot!(p1, right_margin=-5mm)
plot!(p2, left_margin=-5mm)
combined = plot(p1, p2, layout=(1, 2), size=(1000, 480))
display(combined)
savefig("directserve_demo.png")
