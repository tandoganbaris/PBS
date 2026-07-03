include("../structs.jl")
include("../pbsviz.jl")

using Plots
using Measures

const IO_FR = (1, 1)
GS = 6

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
# 6x6 grid, IO at (1,1).  Single item I1 at (3,1) blocks the y=1 corridor.
# E1 at (5,1) — asternmat value 2.06 (2 direction changes, 6 steps from IO).
# checkasternmat compares neighbours and picks (5,2) with cost 1.05.
#
# Hand-computed float asternmat (rows=x, cols=y), distval=0.01:
#   cost = direction_changes + steps × 0.01
#
#        y=1    y=2    y=3    y=4    y=5    y=6
# x=1:  0.00   0.01   0.02   0.03   0.04   0.05   ← direct horizontal from IO
# x=2:  0.01   1.02   1.03   1.04   1.05   1.06   ← 1 turn + steps
# x=3:   ∞     1.03   1.04   1.05   1.06   1.07   ← I1 blocks (3,1)
# x=4:  2.05   1.04   1.05   1.06   1.07   1.08   ← detour around I1: 2 turns
# x=5:  2.06   1.05   1.06   1.07   1.08   1.09
# x=6:  2.07   1.06   1.07   1.08   1.09   1.10
# ──────────────────────────────────────────────────────────────────────────────

LARGE = 99.0
asternmat = Float64[
    0.00  0.01  0.02  LARGE  2.06  2.07;
    0.01  1.02  1.03  1.04  1.05  1.06;
    LARGE 1.03  1.04  1.05  1.06  1.07;
    2.05  1.04  1.05  1.06  1.07  1.08;
    2.06  1.05  1.06  1.07  1.08  1.09;
    2.07  1.06  1.07  1.08  1.09  1.10;
]

e1_pos          = (5, 1)
i1_pos          = (3, 1)
i2_pos          = (1, 4)
freeroam_target = (5, 2)   # cost 1.05 < E1's current 2.06

item1   = createitem("I1", i1_pos, 1000.0)
item2  = createitem("I2", i2_pos, 1000.0)
escort1 = createescort("E1", e1_pos)
items   = Dict("I1" => item1, "I2" => item2)
escorts = Dict("E1" => escort1)

state = fill("0", GS, GS)
state[i1_pos...] = "I1"
state[i2_pos...] = "I2"
state[e1_pos...] = "E1"

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
    annotate!(p, IO_FR[1], IO_FR[2], text("IO", :green, :center, 10))
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
    title="asternmat  (integer=turns · decimal=distance×0.01)",
    titlelocation=:left,
    titlefont=font(11),
)
add_grid!(p1, GS)
add_io_box!(p1)

for x in 1:GS, y in 1:GS
    v = asternmat[x, y]
    if v >= LARGE
        annotate!(p1, x, y, text("∞", :grey, :center, 12))
    else
        lbl = string(round(v, digits=2))
        col = v < 1 ? :darkgreen : v < 2 ? :black : :darkred
        annotate!(p1, x, y, text(lbl, col, :center, 9))
    end
end

cell_box!(p1, e1_pos..., color=:steelblue)
annotate!(p1, e1_pos[1], e1_pos[2]+0.38, text("E1", :steelblue, :center, 8))

# ── Plot 2: warehouse + freeroam decision ─────────────────────────────────────
p2 = plot_matrix(state, items, escorts, IO_FR)
title!(p2, "freeroam!: E1 (cost 2.06) → (5,2) cost 1.05",
    titlelocation=:left, titlefont=font(11))
add_io_box!(p2)

cell_box!(p2, freeroam_target..., color=:limegreen, lw=3)
#= annotate!(p2, freeroam_target[1], freeroam_target[2]+0.35,
    text("1.05", :darkgreen, :center, 9)) =#

plot!(p2, [e1_pos[1], freeroam_target[1]], [e1_pos[2], freeroam_target[2]],
    arrow=(:closed, 2.5), color=:black, lw=2.5)

#= annotate!(p2, e1_pos[1]+0.4, e1_pos[2],
    text("2.06", :darkred, :left, 9))
 =#
# Show other neighbours and their costs for comparison
#= for (nx, ny, lbl) in [(4,1,"2.05"), (6,1,"2.07")]
    annotate!(p2, nx, ny, text(lbl, :grey, :center, 8))
end
 =#
# ── Combined display ──────────────────────────────────────────────────────────
plot!(p1, right_margin=-5mm)
plot!(p2, left_margin=-5mm)
combined = plot(p1, p2, layout=(1, 2), size=(1000, 480))
display(combined)

outdir = "C:/codestuff/PBS/paperplots"
mkpath(outdir)
savefig(joinpath(outdir, "freeroam_demo.png"))
