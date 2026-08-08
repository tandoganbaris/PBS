include("../structs.jl")
include("../pbsviz.jl")

using Plots
using Measures

const IO_FR = (1, 1)
GS = 5

# ── What asternmat encodes ─────────────────────────────────────────────────────
# outwards_astar_with_dirchange runs A* from IO *outward* (distval = 0.01):
#
#   cost_here = dist[prev] + direction_change_penalty + distval
#
# Each step adds distval=0.01 (distance).  Changing direction costs +1.
# No floor() applied when distval > 0, so final value = N + D×0.01
#   where N = number of direction changes, D = number of steps from IO.
#
#   integer part  → direction changes needed
#   decimal part  → distance from IO (steps × 0.01)
#
# freeroam! / checkasternmat picks moves that minimise this combined cost.
# ──────────────────────────────────────────────────────────────────────────────

# ── Scenario ──────────────────────────────────────────────────────────────────
# 5x5 grid, IO at (1,1).  Single item I1 at (3,1) blocks the y=1 corridor.
# E1 at (5,1) — asternmat value 2.06 (2 direction changes, 6 steps from IO).
# checkasternmat compares neighbours and picks (5,2) with cost 1.05.
# (Same underlying asternmat as the 6x6 version, cropped to a 5x5 grid.)
# ──────────────────────────────────────────────────────────────────────────────

LARGE = 99.0
asternmat = Float64[
    0.00  0.01  0.02  LARGE  2.06;
    0.01  1.02  1.03  1.04  1.05;
    LARGE 1.03  1.04  1.05  1.06;
    2.05  1.04  1.05  1.06  1.07;
    2.06  1.05  1.06  1.07  1.08;
]

e1_pos          = (5, 1)
i1_pos          = (3, 1)
i2_pos          = (1, 4)
freeroam_target = (5, 2)   # cost 1.05 < E1's current 2.06

item1   = createitem("I1", i1_pos, 1000.0)
item2   = createitem("I2", i2_pos, 1000.0)
escort1 = createescort("E1", e1_pos)
items   = Dict("I1" => item1, "I2" => item2)
escorts = Dict("E1" => escort1)

state = fill("", GS, GS)
state[i1_pos...] = "L1"
state[i2_pos...] = "L2"
state[e1_pos...] = "Escort"

# ── Helpers ───────────────────────────────────────────────────────────────────
function add_grid!(p, gs)
    for c in 1:gs+1
        plot!(p, [c-0.5, c-0.5], [0.5, gs+0.5], color=:black, lw=1)
    end
    for r in 1:gs+1
        plot!(p, [0.5, gs+0.5], [r-0.5, r-0.5], color=:black, lw=1)
    end
end

function add_io_box!(p)
    plot!(p,
        [IO_FR[1]-0.5, IO_FR[1]+0.5, IO_FR[1]+0.5, IO_FR[1]-0.5, IO_FR[1]-0.5],
        [IO_FR[2]-0.5, IO_FR[2]-0.5, IO_FR[2]+0.5, IO_FR[2]+0.5, IO_FR[2]-0.5],
        color=:green, lw=4, fill=false)
    annotate!(p, IO_FR[1], IO_FR[2]+0.32, text("I/O", :green, :center, 13))
end

function cell_box!(p, x, y; color=:steelblue, lw=3)
    plot!(p, [x-0.5,x+0.5,x+0.5,x-0.5,x-0.5],
             [y-0.5,y-0.5,y+0.5,y+0.5,y-0.5],
          color=color, lw=lw, fill=false)
end

# ── Plot 1: asternmat float heatmap ──────────────────────────────────────────
# Colour bands: 0.xx=green, 1.xx=yellow, 2.xx=orange, ∞=grey
# Map: clamp LARGE→3 for colouring, everything ≥3 will look grey.
display_astar = min.(asternmat, 3.0)

p1 = heatmap(
    display_astar',
    color=cgrad([:limegreen, :limegreen, :yellow, :yellow, :orange, :orange, :lightgrey],
                [0, 0.33, 0.34, 0.66, 0.67, 0.99, 1.0]),
    clims=(0, 3),
    axis=false,
    xlims=(0.5, GS+0.5),
    ylims=(0.5, GS+0.5),
    aspect_ratio=:equal,
    legend=false,
    colorbar=false,
    title="Astarmat: turns and distance",
    titlelocation=:left,
    titlefont=font(13),
)
add_grid!(p1, GS)
add_io_box!(p1)

for x in 1:GS, y in 1:GS
    v = asternmat[x, y]
    if v >= LARGE
        annotate!(p1, x, y, text("∞", :grey, :center, 15))
    else
        lbl = string(round(v, digits=2))
        col = v < 1 ? :darkgreen : v < 2 ? :black : :darkred
        annotate!(p1, x, y, text(lbl, col, :center, 10))
    end
end

cell_box!(p1, e1_pos..., color=:steelblue)
annotate!(p1, e1_pos[1], e1_pos[2]+0.3, text("Escort", :steelblue, :center, 15))

# ── Plot 2: warehouse + freeroam decision ─────────────────────────────────────
p2 = plot_matrix(state, items, escorts, IO_FR)
title!(p2, "Towards I/O: Escort moves to lower-cost cell",
    titlelocation=:left, titlefont=font(13))
# IO box
plot!(p2,
    [IO_FR[1]-0.5, IO_FR[1]+0.5, IO_FR[1]+0.5, IO_FR[1]-0.5, IO_FR[1]-0.5],
    [IO_FR[2]-0.5, IO_FR[2]-0.5, IO_FR[2]+0.5, IO_FR[2]+0.5, IO_FR[2]-0.5],
    color=:green, lw=4, fill=false)
annotate!(p2, IO_FR[1], IO_FR[2], text("I/O", :green, :center, 17))
tx, ty = freeroam_target
plot!(p2, Shape([tx-0.5, tx+0.5, tx+0.5, tx-0.5], [ty-0.5, ty-0.5, ty+0.5, ty+0.5]),
    color=:limegreen, linecolor=:black, label=false)
add_grid!(p2, GS)
annotate!(p2, tx, ty, text("✓", :black, :center, 20))

plot!(p2, [e1_pos[1], freeroam_target[1]], [e1_pos[2] + 0.2, freeroam_target[2]-0.15],
    arrow=(:closed, 2.5), color=:black, lw=2.5)

# ── Combined display ──────────────────────────────────────────────────────────
plot!(p1, right_margin=8mm)
plot!(p2, left_margin=2mm)
combined = plot(p1, p2, layout=(1, 2), size=(1150, 480))
display(combined)

outdir = "C:/codestuff/PBS/paperplots"
mkpath(outdir)
savefig(joinpath(outdir, "freeroam_demo2.png"))
