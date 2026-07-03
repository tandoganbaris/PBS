include("../structs.jl")
include("../pbsviz.jl")

using Plots
using Measures

const IO_ME = (1, 1)
GS = 8

# ── Scenario ──────────────────────────────────────────────────────────────────
# 8x8 warehouse, IO at (1,1).
# E1 at (5,3), I1 at (5,5) [Y-mover], I2 at (7,7) [X-mover].
#
# One iteration:
#   - E1 serves I1: E1 moves UP from y=3 → y=7 (I2's y-level)
#   - I1 moves one slot down: (5,5) → (5,4)
#   - updateblockmat_e! marks column x=5, y=3→7 as 1
#
# Result: E1 is now at I2's y-level (5,7), ready to serve I2 next.
# ──────────────────────────────────────────────────────────────────────────────

# Initial positions
i1_before = (5, 5);  i2_pos = (7, 7);  e1_before = (5, 3)

# After positions
i1_after  = (5, 4)   # moved one slot down
e1_after  = (5, 7)   # moved up to I2's y-level
blocked_col = 5;  blocked_y = 3:7   # corridor swept by E1

# ── Items / escorts for plot_matrix (left plot) ───────────────────────────────
item1   = createitem("I1", i1_before, 1000.0)
item2   = createitem("I2", i2_pos,    1000.0)
escort1 = createescort("E1", e1_before)
items   = Dict("I1" => item1, "I2" => item2)
escorts = Dict("E1" => escort1)

state_before = fill("0", GS, GS)
state_before[i1_before...] = "I1"
state_before[i2_pos...]    = "I2"
state_before[e1_before...] = "E1"

# ── Plot 1 (LEFT): initial state ─────────────────────────────────────────────
p1 = plot_matrix(state_before, items, escorts, IO_ME)
title!(p1, "Before: E1 below I1, I2 up-right", titlelocation=:left,titlefont=font(11))

# IO box
plot!(p1,
    [IO_ME[1]-0.5, IO_ME[1]+0.5, IO_ME[1]+0.5, IO_ME[1]-0.5, IO_ME[1]-0.5],
    [IO_ME[2]-0.5, IO_ME[2]-0.5, IO_ME[2]+0.5, IO_ME[2]+0.5, IO_ME[2]-0.5],
    color=:green, lw=4, fill=false)
annotate!(p1, IO_ME[1], IO_ME[2], text("IO", :green, :center, 11))

# ── Plot 2 (RIGHT): after one iteration ──────────────────────────────────────
# Cell values:
#   0 = free (lightblue)
#   1 = blocked corridor (lightgrey)
#   2 = I1 new pos (orange) — inside corridor
#   3 = I2 (tomato)
#   4 = E1 new pos (white) — top of corridor

display_after = zeros(Int, GS, GS)
for y in blocked_y
    display_after[blocked_col, y] = 1        # blocked corridor
end
display_after[i1_after...]  = 2              # I1 moved down (overwrites 1)
display_after[i2_pos...]    = 3              # I2 unchanged
display_after[e1_after...]  = 4              # E1 new pos (overwrites 1)

p2 = heatmap(
    display_after',
    color=cgrad([:lightblue, :lightgrey, :tomato, :tomato, :white], 5, categorical=true),
    clims=(0, 4),
    axis=false,
    xlims=(0.5, GS + 0.5),
    ylims=(0.5, GS + 0.5),
    aspect_ratio=:equal,
    legend=false,
    colorbar=false,
    title="After: I1 moved down, E1 at I2's y-level ",
    titlefont=font(11),
    titlelocation=:left,
)

for c in 1:GS+1
    plot!(p2, [c-0.5, c-0.5], [0.5, GS+0.5], color=:black, lw=1)
end
for r in 1:GS+1
    plot!(p2, [0.5, GS+0.5], [r-0.5, r-0.5], color=:black, lw=1)
end

labels2 = Dict(1 => "1", 2 => "I1", 3 => "I2", 4 => "E1")
for x in 1:GS, y in 1:GS
    lbl = get(labels2, display_after[x, y], "")
    if lbl != ""
        annotate!(p2, x, y, text(lbl, :black, :center, 13))
    end
end

# IO box
plot!(p2,
    [IO_ME[1]-0.5, IO_ME[1]+0.5, IO_ME[1]+0.5, IO_ME[1]-0.5, IO_ME[1]-0.5],
    [IO_ME[2]-0.5, IO_ME[2]-0.5, IO_ME[2]+0.5, IO_ME[2]+0.5, IO_ME[2]-0.5],
    color=:green, lw=4, fill=false)
annotate!(p2, IO_ME[1], IO_ME[2], text("IO", :green, :center, 11))

# ── Combined display ──────────────────────────────────────────────────────────
plot!(p1, right_margin=-5mm)
plot!(p2, left_margin=-5mm)
combined = plot(p1, p2, layout=(1, 2), size=(1000, 480))
display(combined)

outdir = "C:/codestuff/PBS/paperplots"
mkpath(outdir)
savefig(joinpath(outdir, "moveescort.png"))
