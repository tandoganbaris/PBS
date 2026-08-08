using Plots
using Measures

const IO_DS = (1, 1)
GS = 5

# ── Scenario ──────────────────────────────────────────────────────────────────
# 5x5 warehouse, IO at (1,1).
# Escort at (2,2). Item (normal) at (4,5).
# urgcusts is empty — no urgent items, so the normal loop runs.
#
# directserve_flow! evaluates two approaches for the item:
#
#   Y-approach: escort stays at x=2, moves to item's y=5  → target (2,5)
#     Condition: IO[1]=1 < itemx=4 AND esc_x=2 < itemx=4  ✓ (same side)
#     ygap = |esc_y - itemy| = |2-5| = 3
#
#   X-approach: escort moves to item's x=4, stays at y=2  → target (4,2)
#     Condition: esc_y=2 < itemy=5  ✓ (escort below item)
#     xgap = |esc_x - itemx| = |2-4| = 2
#
# Decision: distx(2) < disty(3)  →  X-approach wins  →  move to (4,2)
# Escort gets in front of the item in the Y-lane; next iteration it serves it.
# ──────────────────────────────────────────────────────────────────────────────

esc_x, esc_y = (2, 2)
itemx, itemy = (4, 5)

target_Y = (esc_x, itemy)       # (2,5) — Y-approach, ygap=3, rejected
target_X = (itemx, esc_y)       # (4,2) — X-approach, xgap=2, WINNER

# ── Plot 1 (LEFT): warehouse state ───────────────────────────────────────────
# Cell values:
#   0 = free (lightblue)
#   1 = Escort (white)
#   2 = Item (tomato)

display_before = zeros(Int, GS, GS)
display_before[esc_x, esc_y]   = 1
display_before[itemx, itemy]   = 2

p1 = heatmap(
    display_before',
    color=cgrad([:lightblue, :white, :tomato], 3, categorical=true),
    clims=(0, 2),
    axis=false,
    xlims=(0.5, GS + 0.5),
    ylims=(0.5, GS + 0.5),
    aspect_ratio=:equal,
    legend=false,
    colorbar=false,
    title="Two-Step Service: choosing the shortest path                         (green=chosen, yellow=rejected)",
    titlefont=font(13),
    titlelocation=:left,
)

for c in 1:GS+1
    plot!(p1, [c-0.5, c-0.5], [0.5, GS+0.5], color=:black, lw=1)
end
for r in 1:GS+1
    plot!(p1, [0.5, GS+0.5], [r-0.5, r-0.5], color=:black, lw=1)
end

labels1 = Dict((esc_x, esc_y) => "Escort", (itemx, itemy) => "Load")
for ((x, y), lbl) in labels1
    annotate!(p1, x, y, text(lbl, :black, :center, 13))
end

# IO box
plot!(p1,
    [IO_DS[1]-0.5, IO_DS[1]+0.5, IO_DS[1]+0.5, IO_DS[1]-0.5, IO_DS[1]-0.5],
    [IO_DS[2]-0.5, IO_DS[2]-0.5, IO_DS[2]+0.5, IO_DS[2]+0.5, IO_DS[2]-0.5],
    color=:green, lw=4, fill=false)
annotate!(p1, IO_DS[1], IO_DS[2], text("I/O", :green, :center, 17))

# ── Plot 2 (RIGHT): decision map ─────────────────────────────────────────────
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

cell_labels = Dict(2 => "Load", 4 => "Escort", 5 => "✓", 6 => "✗")
for x in 1:GS, y in 1:GS
    lbl = get(cell_labels, display_mat[x, y], "")
    if lbl != ""
        annotate!(p2, x, y, text(lbl, :black, :center, 15))
    end
end

# IO box
plot!(p2,
    [IO_DS[1]-0.5, IO_DS[1]+0.5, IO_DS[1]+0.5, IO_DS[1]-0.5, IO_DS[1]-0.5],
    [IO_DS[2]-0.5, IO_DS[2]-0.5, IO_DS[2]+0.5, IO_DS[2]+0.5, IO_DS[2]-0.5],
    color=:green, lw=4, fill=false)
annotate!(p2, IO_DS[1], IO_DS[2], text("I/O", :green, :center, 17))

# Rejected Y-approach arrow (dashed grey)
plot!(p2, [esc_x, target_Y[1]], [(esc_y+0.2), (target_Y[2]-0.2)],
    arrow=(:closed, 1.5), color=:grey, lw=1.5, linestyle=:dash)
annotate!(p2, esc_x + 0.15, ((esc_y + target_Y[2])/2)+0.35,
    text("ygap=3", :grey, :left, 11))

# Chosen X-approach arrow (solid black)
plot!(p2, [(esc_x +0.4), (target_X[1]-0.2)], [esc_y, target_X[2]],
    arrow=(:closed, 2.5), color=:black, lw=2.5)
annotate!(p2, (esc_x + target_X[1])/2, esc_y - 0.2,
    text("xgap=2", :black, :center, 11))

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
savefig(joinpath(outdir, "directserve2.png"))
