using Printf

# Distance matrix: row = von (from), col = nach (to)
# A=1, B=2, C=3, D=4, E=5, F=6
dist = [
     0  30  15  32  43  20;
    30   0  43  47  39  26;
    15  44   0  23  21  11;
    32  49  23   0  21  25;
    43  39  21  21   0  29;
    22  28  11  25  29   0
]

labels = ["A","B","C","D","E","F"]
route  = [1, 3, 6, 4, 5, 2]   # A–C–F–D–E–B

route_cost(r) = sum(dist[r[i], r[mod1(i+1, length(r))]] for i in eachindex(r))
route_str(r)  = join([labels[x] for x in r], "–") * "–" * labels[r[1]]

function two_opt_iteration(route)
    n  = length(route)
    c0 = route_cost(route)
    println("Aktuelle Route: $(route_str(route)) | Distanz = $c0\n")
    @printf("%-30s %8s %16s\n", "Nachbar", "Delta", "Nachbar Distanz")
    println("─"^56)
    for i in 1:n-1, j in i+2:n
        nb = copy(route)
        reverse!(nb, i+1, j)          # 2-opt: reverse segment [i+1 .. j]
        nc = route_cost(nb)
        @printf("%-30s %+8d %16d\n", route_str(nb), nc - c0, nc)
    end
end

two_opt_iteration(route)
