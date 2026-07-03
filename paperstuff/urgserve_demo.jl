include("../structs.jl")
include("../pbsviz.jl")

using Plots

const IO_DEMO = (1, 1)
GS = 8  # grid size

# ── Scenario ──────────────────────────────────────────────────────────────────
# 8x8 warehouse, IO at (1,1) (left column, bottom row).
# Item I1 at (5,3): urgent, deadline passed, moving toward IO.
# Escort E1 at (7,6): not yet positioned to serve I1.
# Goal: urgserve! figures out E1 should move to (7,2) — a 2-zone.
# ──────────────────────────────────────────────────────────────────────────────

item1   = createitem("I1", (5, 3), 0.0)   # deadline 0 → urgent
escort1 = createescort("E1", (7, 6))

items   = Dict("I1" => item1)
escorts = Dict("E1" => escort1)

state = fill("0", GS, GS)
state[5, 3] = "I1"
state[7, 6] = "E1"

blockmat = zeros(Int, GS, GS)

# Block row y=4 for x=2,3,4 — prevents horizontal interception zone from extending above y=4
blockmat[2, 4] = 1
blockmat[3, 4] = 1
blockmat[4, 4] = 1

# ── Build urgmat for I1 (same logic as urgmats()) ─────────────────────────────
urgx, urgy = item1.coords   # (5, 3)
dir = urgx > IO_DEMO[1] ? -1 : 1  # 5 > 1 → dir = -1

urgmat = deepcopy(blockmat)
urgmat[urgx, urgy] = 3  # mark item

# Horizontal strip: columns urgx-1 → IO[1], rows above item (y > urgy)
for xx in max(urgx - 1, 1):-1:IO_DEMO[1]
    if state[xx, urgy] ∉ keys(escorts) && state[xx, urgy] ∉ keys(items)
        for y in min(urgy + 1, GS):GS
            if blockmat[xx, y] == 0 && state[xx, y] ∉ keys(items)
                urgmat[xx, y] = 2
            else
                break
            end
        end
    else
        break
    end
end

# Vertical strip: rows urgy-1 → IO[2], columns to the right of item (dir==-1)
for yy in urgy - 1:-1:IO_DEMO[2]
    if state[urgx, yy] ∉ keys(escorts) && state[urgx, yy] ∉ keys(items)
        if dir == -1 || urgx == IO_DEMO[1]
            for x in min(urgx + 1, GS):GS
                if blockmat[x, yy] == 0 && state[x, yy] ∉ keys(items)
                    urgmat[x, yy] = 2
                else
                    break
                end
            end
        end
        if dir == 1 || urgx == IO_DEMO[1]
            for x in max(urgx - 1, 1):-1:IO_DEMO[1]
                if blockmat[x, yy] == 0 && state[x, yy] ∉ keys(items)
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

# ── urgserve! search trace ────────────────────────────────────────────────────
# Escort at (7,6). Y-scan: move x toward IO (dir=-1), find 2 in column.
#   At x=7, scan y=5 down: urgmat[7,2]=2 → candidy=2, gapy=4, xin=7 (no x move)
# X-scan: scan x toward IO from esc_x=7, at y=6.
#   urgmat[4,6]=2 → candidx=4, gapx=3, yin=6 (no y move)
# Both found, onx=1, ony=1 (escort already at those rows) → gapx(3)<gapy(4) → go to (7,2)
target = (7, 2)

# ── Plot 1: Warehouse state ───────────────────────────────────────────────────
p1 = plot_matrix(state, items, escorts, IO_DEMO)
title!(p1, "Warehouse: E1 must serve urgent I1 (orange=2-zone, red=item, white=escort)",titlelocation=:left)

# ── Plot 2: Urgmat (interception zones) ──────────────────────────────────────
colors = [:white, :lightgrey, :orange, :tomato, :lightgreen]
#          0=free   1=blocked   2=zone    3=item    4=escort/target

display_mat = copy(urgmat)
esc_x, esc_y = escort1.coords
display_mat[esc_x, esc_y] = 4          # escort in green
display_mat[target[1], target[2]] = 5  # target (highlighted below)

p2 = heatmap(
    display_mat',
    color=cgrad([:lightblue, :lightgrey, :orange, :tomato, :white, :orange], 6, categorical=true), #color=[:lightblue, :tomato, :white],
    clims=(0, 5),
    axis=false,
    xlims=(0.5, GS + 0.5),
    ylims=(0.5, GS + 0.5),
    aspect_ratio=:equal,
    legend=false,
    colorbar=false,
    size=(60 * GS, 60 * GS),
   
)

for c in 1:GS+1
    plot!(p2, [c - 0.5, c - 0.5], [0.5, GS + 0.5], color=:black, lw=1)
end
for r in 1:GS+1
    plot!(p2, [0.5, GS + 0.5], [r - 0.5, r - 0.5], color=:black, lw=1)
end

labels = Dict(0 => "", 1 => "1", 2 => "2", 3 => "I1", 4 => "E1", 5 => "←")
for x in 1:GS, y in 1:GS
    v = display_mat[x, y]
    lbl = get(labels, v, "")
    annotate!(p2, x, y, text(lbl, :black, :center, 14))
end

# IO box
plot!(p2,
    [IO_DEMO[1]-0.5, IO_DEMO[1]+0.5, IO_DEMO[1]+0.5, IO_DEMO[1]-0.5, IO_DEMO[1]-0.5],
    [IO_DEMO[2]-0.5, IO_DEMO[2]-0.5, IO_DEMO[2]+0.5, IO_DEMO[2]+0.5, IO_DEMO[2]-0.5],
    color=:green, lw=4, fill=false)
annotate!(p2, IO_DEMO[1], IO_DEMO[2], text("IO", :green, :center, 12))

# Arrow: escort → target (move down in y, stay in x)
plot!(p2, [esc_x, target[1]], [esc_y, target[2]],
    arrow=(:closed, 2.0), color=:black, lw=2)

# ── Combined display ──────────────────────────────────────────────────────────
combined = plot(p1, p2, layout=(1, 2), size=(1400, 560))
display(combined)
using Measures

plot!(p1, right_margin=-5mm)
plot!(p2, left_margin=-5mm)
combined = plot(p1, p2, layout=(1, 2), size=(1000, 480))
display(combined)

outdir = "C:/codestuff/PBS/paperplots"
mkpath(outdir)
savefig(joinpath(outdir, "urgserve.png"))