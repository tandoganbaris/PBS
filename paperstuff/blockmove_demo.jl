using Plots
using Measures

const IO_ME = (1, 1)
GS = 5

# ── Scenario ──────────────────────────────────────────────────────────────────
# 5x5 warehouse, IO at (1,1).
# Escort at (2,2) [Y-mover], Load (fixed) at (2,5).
#
# Block movement: instead of stepping one slot at a time, the escort moves
# several slots in a single iteration, jumping straight to y=5 — the Load's
# slot — rather than stopping at y=3 as single-slot movement would.
#
# Result: the escort places itself immediately behind the Load, strategically
# queued right in front of it on the way to the IO.
# ──────────────────────────────────────────────────────────────────────────────

# Initial positions
i1_before = (2, 2);  i2_pos = (2, 5)

# After positions
i1_after   = (2, 5)  # jumped 3 slots in one move
i2_after = (2, 4)
blocked_col = 2;  blocked_y = 2:3   # path swept by the block move

# ── Plot 1 (LEFT): initial state ─────────────────────────────────────────────
# Cell values:
#   0 = free (lightblue)
#   1 = Escort (white)
#   2 = Load (tomato)

display_before = zeros(Int, GS, GS)
display_before[i1_before...] = 1
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
    title="Before: Escort far from Load",
    titlefont=font(13),
    titlelocation=:left,
)

for c in 1:GS+1
    plot!(p1, [c-0.5, c-0.5], [0.5, GS+0.5], color=:black, lw=1)
end
for r in 1:GS+1
    plot!(p1, [0.5, GS+0.5], [r-0.5, r-0.5], color=:black, lw=1)
end

labels1 = Dict(1 => "Escort", 2 => "Load")
for x in 1:GS, y in 1:GS
    lbl = get(labels1, display_before[x, y], "")
    if lbl != ""
        annotate!(p1, x, y, text(lbl, :black, :center, 13))
    end
end

# IO box
plot!(p1,
    [IO_ME[1]-0.5, IO_ME[1]+0.5, IO_ME[1]+0.5, IO_ME[1]-0.5, IO_ME[1]-0.5],
    [IO_ME[2]-0.5, IO_ME[2]-0.5, IO_ME[2]+0.5, IO_ME[2]+0.5, IO_ME[2]-0.5],
    color=:green, lw=4, fill=false)
annotate!(p1, IO_ME[1], IO_ME[2], text("I/O", :green, :center, 17))

# ── Plot 2 (RIGHT): after one block move ─────────────────────────────────────
# Cell values:
#   0 = free (lightblue)
#   1 = path swept by the jump (lightgrey)
#   2 = I1 new pos (orange) — directly in front of I2
#   3 = I2 (tomato) — unchanged

display_after = zeros(Int, GS, GS)
for y in blocked_y
    display_after[blocked_col, y] = 1        # slots skipped over in one move
end
display_after[i1_after...] = 2               # I1 jumped here (overwrites 1)
display_after[i2_after...]   = 3               # I2 unchanged

p2 = heatmap(
    display_after',
    color=cgrad([:lightblue, :lightgrey, :white, :tomato], 4, categorical=true),
    clims=(0, 3),
    axis=false,
    xlims=(0.5, GS + 0.5),
    ylims=(0.5, GS + 0.5),
    aspect_ratio=:equal,
    legend=false,
    colorbar=false,
    title="After: Entire block moves, escort is behind Load",
    titlefont=font(13),
    titlelocation=:left,
)

for c in 1:GS+1
    plot!(p2, [c-0.5, c-0.5], [0.5, GS+0.5], color=:black, lw=1)
end
for r in 1:GS+1
    plot!(p2, [0.5, GS+0.5], [r-0.5, r-0.5], color=:black, lw=1)
end

labels2 = Dict(1 => "", 2 => "Escort", 3 => "Load")
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
annotate!(p2, IO_ME[1], IO_ME[2], text("I/O", :green, :center, 17))

# Block outline: bounding box around the swept slots + the Load
block_ymin = minimum(blocked_y) - 0.5
block_ymax = i1_after[2] + 0.5
plot!(p2,
    [blocked_col-0.5, blocked_col+0.5, blocked_col+0.5, blocked_col-0.5, blocked_col-0.5],
    [block_ymin, block_ymin, block_ymax, block_ymax, block_ymin],
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
savefig(joinpath(outdir, "blockmove.png"))
