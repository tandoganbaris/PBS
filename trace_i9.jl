include("main.jl")
global saveplot = false

escorts = Dict{String, escort}()
escorts["E1"] = escort("E1", (2,2), String[], String[], 0, Dict{Int64,Vector{String}}(), Tuple{Int64,Int64}[])
items = Dict{String, item}()
items["I1"] = item("I1", (2,7), 0, 0, 1000.0, 1, nothing)
items["I2"] = item("I2", (4,6), 0, 0, 1000.0, 1, nothing)

Lx, Ly = 6, 7
initialstate = fill("0", Lx, Ly)
for (k,e) in escorts; x,y=e.coords; initialstate[x,y]=k; end
for (k,it) in items;   x,y=it.coords; initialstate[x,y]=k; end

IO = [(1,1),(1,2)]

DEBUG_MOVE_TRACE[] = true
_, _, ms = main(initialstate, items, escorts, IO, "i9", raw"C:\codestuff\PBS\plots";
    n=2, no_cores=1, mode="continue", mm="lm", iter_cap=55)
println("iterations=$ms moves=$(TOTAL_MOVES[])")
