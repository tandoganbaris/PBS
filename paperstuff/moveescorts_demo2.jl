using Plots
using Measures

const IO_ME = (1, 1)
GS = 5

# ── Scenario ──────────────────────────────────────────────────────────────────
# 5x5 warehouse, IO at (1,1).
# E1 at (2,2), I1 at (2,4) [Y-mover], I2 at (4,5) [X-mover].
#
# One iteration:
#   - E1 serves I1: E1 moves UP from y=2 → y=5 (I2's y-level)
#   - I1 moves one slot down: (2,4) → (2,3)
#   - updateblockmat_e! marks column x=2, y=2→5 as 1
#
# Result: E1 is now at I2's y-level (2,5), ready to serve I2 next.
# ──────────────────────────────────────────────────────────────────────────────

# Initial positions
i1_before = (2, 4);  i2_pos = (4, 5);  e1_before = (2, 2)

# After positions
i1_after  = (2, 3)   # moved one slot down
e1_after  = (2, 5)   # moved up to I2's y-level
blocked_col = 2;  blocked_y = 2:5   # corridor swept by E1

# ── Plot 1 (LEFT): initial state ─────────────────────────────────────────────
# Cell values:
#   0 = free (lightblue)
#   1 = E1 (white)
#   2 = items (tomato)

display_before = zeros(Int, GS, GS)
display_before[e1_before...] = 1
display_before[i1_before...] = 2
display_before[i2_pos...]    = 2

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
    title="Before: Escort below L1, L2 up-right",
    titlefont=font(13),
    titlelocation=:left,
)

for c in 1:GS+1
    plot!(p1, [c-0.5, c-0.5], [0.5, GS+0.5], color=:black, lw=1)
end
for r in 1:GS+1
    plot!(p1, [0.5, GS+0.5], [r-0.5, r-0.5], color=:black, lw=1)
end

labels_before = Dict(e1_before => "Escort", i1_before => "L1", i2_pos => "L2")
for ((x, y), lbl) in labels_before
    annotate!(p1, x, y, text(lbl, :black, :center, 13))
end

# IO box
plot!(p1,
    [IO_ME[1]-0.5, IO_ME[1]+0.5, IO_ME[1]+0.5, IO_ME[1]-0.5, IO_ME[1]-0.5],
    [IO_ME[2]-0.5, IO_ME[2]-0.5, IO_ME[2]+0.5, IO_ME[2]+0.5, IO_ME[2]-0.5],
    color=:green, lw=4, fill=false)
annotate!(p1, IO_ME[1], IO_ME[2], text("I/O", :green, :center, 17))

# Corridor outline: bounding box spanning E1 → I1 (inclusive)
pre_ymin = min(e1_before[2], i1_before[2]) - 0.5
pre_ymax = max(e1_before[2], i1_before[2]) + 0.5
plot!(p1,
    [blocked_col-0.5, blocked_col+0.5, blocked_col+0.5, blocked_col-0.5, blocked_col-0.5],
    [pre_ymin, pre_ymin, pre_ymax, pre_ymax, pre_ymin],
    color=:gray, lw=5, fill=false)

# ── Plot 2 (RIGHT): after one iteration ──────────────────────────────────────
# Cell values:
#   0 = free (lightblue)
#   1 = blocked corridor (lightgrey)
#   2 = items (tomato)
#   3 = E1 new pos (white) — top of corridor

display_after = zeros(Int, GS, GS)
for y in blocked_y
    display_after[blocked_col, y] = 1        # blocked corridor
end
display_after[i1_after...] = 2               # I1 moved down (overwrites 1)
display_after[i2_pos...]   = 2               # I2 unchanged
display_after[e1_after...] = 3               # E1 new pos (overwrites 1)

p2 = heatmap(
    display_after',
    color=cgrad([:lightblue, :lightgrey, :tomato, :white], 4, categorical=true),
    clims=(0, 3),
    axis=false,
    xlims=(0.5, GS + 0.5),
    ylims=(0.5, GS + 0.5),
    aspect_ratio=:equal,
    legend=false,
    colorbar=false,
    title="After: L1 moved down, Escort at L2's y-level",
    titlefont=font(13),
    titlelocation=:left,
)

for c in 1:GS+1
    plot!(p2, [c-0.5, c-0.5], [0.5, GS+0.5], color=:black, lw=1)
end
for r in 1:GS+1
    plot!(p2, [0.5, GS+0.5], [r-0.5, r-0.5], color=:black, lw=1)
end

labels_after = Dict(i1_after => "L1", i2_pos => "L2", e1_after => "Escort")
for ((x, y), lbl) in labels_after
    annotate!(p2, x, y, text(lbl, :black, :center, 13))
end

# IO box
plot!(p2,
    [IO_ME[1]-0.5, IO_ME[1]+0.5, IO_ME[1]+0.5, IO_ME[1]-0.5, IO_ME[1]-0.5],
    [IO_ME[2]-0.5, IO_ME[2]-0.5, IO_ME[2]+0.5, IO_ME[2]+0.5, IO_ME[2]-0.5],
    color=:green, lw=4, fill=false)
annotate!(p2, IO_ME[1], IO_ME[2], text("I/O", :green, :center, 17))

# Corridor outline: bounding box spanning E1's previous → new position (inclusive)
corr_ymin = min(e1_before[2], e1_after[2]) - 0.5
corr_ymax = max(e1_before[2], e1_after[2]) + 0.5
plot!(p2,
    [blocked_col-0.5, blocked_col+0.5, blocked_col+0.5, blocked_col-0.5, blocked_col-0.5],
    [corr_ymin, corr_ymin, corr_ymax, corr_ymax, corr_ymin],
    color=:gray, lw=3, fill=false)

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
savefig(joinpath(outdir, "moveescort2.png"))
