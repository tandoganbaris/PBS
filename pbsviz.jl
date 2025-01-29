
using Plots

function plot_matrix(matrix, items, escorts, IO)
    nrows, ncols = size(matrix)
    heatmap_matrix = fill(1, nrows, ncols)
    
 
    for (char, (r, c)) in items
        heatmap_matrix[r, c] = 2
    end
    
 
    for (char, (r, c)) in escorts
        heatmap_matrix[r, c] = 3
    end
    
    heatmap_colors = [:lightblue, :tomato, :linen]
    
    p = heatmap(
        heatmap_matrix,
        color=heatmap_colors,
        axis=false,
        xlims=(0.5, ncols + 0.5),
        ylims=(0.5, nrows + 0.5),
        aspect_ratio=:equal,
        legend=false,
        colorbar=false
    )
 
    for i in 1:nrows+1
        plot!(p, [0.5, ncols+0.5], [i-0.5, i-0.5], color=:black, lw=1)
    end
    for j in 1:ncols+1
        plot!(p, [j-0.5, j-0.5], [0.5, nrows+0.5], color=:black, lw=1)
    end
    
    for i in 1:nrows
        for j in 1:ncols
            annotate!(p, j, i, text(matrix[i, j], :black, :center))
        end
    end
    
    r, c = IO
    plot!(
        p,
        [c-0.5, c+0.5, c+0.5, c-0.5, c-0.5],
        [r-0.5, r-0.5, r+0.5, r+0.5, r-0.5],
        color=:green,
        lw=5,
        fill=false
    )
    
    return p
end
# Example usage
matrix = [
    'a' 'b' 'c' 'd' 'e' 'f' 'g' 'h';
    'i' 'j' 'k' 'l' 'm' 'n' 'o' 'p';
    'q' 'r' 's' 't' 'u' 'v' 'w' 'x';
    'y' 'z' '1' '2' '3' '4' '5' '6';
    '7' '8' '9' '0' 'A' 'B' 'C' 'D';
    'E' 'F' 'G' 'H' 'I' 'J' 'K' 'L'
]

items   = Dict('a' => (2,3), 'e' => (2,7))
escorts = Dict('c' => (5,2), 'i' => (3,5))
io = (1,1)
plot_matrix(matrix, items, escorts, io)