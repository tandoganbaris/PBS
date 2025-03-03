using Test
include("main.jl")

@testset "Main Function Tests" begin
    global makespan_sum = 0
    global average_time_sum = 0
    num_iterations = 100
    timerstart = time()
 

    global saveplot = false
    
    item_deadlines = Dict("$i" => Float64(1000 - i * 10) for i in 1:20)
    IO = (5, 1)
    initialstate = 
    ["12" "E3" "40" "44" "92" "54" "19" "11" "68" "53"; 
    "78" "17" "66" "94" "96" "55" "3" "63" "64" "60"; 
    "65" "7" "38" "49" "10" "26" "4" "83" "90" "50";
     "6" "70" "72" "51" "31" "79" "30" "24" "93" "15"; 
     "29" "82" "85" "61" "9" "76" "59" "25" "52" "1"; 
     "5" "74" "80" "41" "62" "48" "69" "23" "84" "16"; 
     "37" "86" "27" "22" "33" "71" "87" "67" "34" "14"; 
     "95" "18" "45" "56" "58" "E1" "39" "57" "13" "88"; 
     "77" "E2" "81" "89" "28" "46" "91" "42" "20" "43"; 
     "2" "47" "8" "E4" "21" "73" "75" "32" "36" "35"]
    items =Dict{String, Any}("4" => item("4", (3, 7), 0, 0, 960.0, 0), "1" => item("1", (5, 10), 0, 0, 990.0, 0), "12" => item("12", (1, 1), 0, 0, 880.0, 0), "20" => item("20", (9, 9), 0, 0, 800.0, 0), "2" => item("2", (10, 1), 0, 0, 980.0, 0), "6" => item("6", (4, 1), 0, 0, 940.0, 0), "11" => item("11", (1, 8), 0, 0, 890.0, 0), "13" => item("13", (8, 9), 0, 0, 870.0, 0), "15" => item("15", (4, 10), 0, 0, 850.0, 0), "5" => item("5", (6, 1), 0, 0, 950.0, 0), "16" => item("16", (6, 10), 0, 0, 840.0, 0), "14" => item("14", (7, 10), 0, 0, 860.0, 0), "7" => item("7", (3, 2), 0, 0, 930.0, 0), "8" => item("8", (10, 3), 0, 0, 920.0, 0), "17" => item("17", (2, 2), 0, 0, 830.0, 0), "19" => item("19", (1, 7), 0, 0, 810.0, 0), "10" => item("10", (3, 5), 0, 0, 900.0, 0), "9" => item("9", (5, 5), 0, 0, 910.0, 0), "18" => item("18", (8, 2), 0, 0, 820.0, 0), "3" => item("3", (2, 7), 0, 0, 970.0, 0))

    escorts= Dict{String, Any}("E3" => escort("E3", (1, 2), String[], String[], 2, Dict{Int64, Vector{String}}(), Tuple{Int64, Int64}[]), 
    "E2" => escort("E2", (9, 2), String[], String[], 3, Dict{Int64, Vector{String}}(), Tuple{Int64, Int64}[]),
    "E1" => escort("E1", (8, 6), String[], String[], 4, Dict{Int64, Vector{String}}(), Tuple{Int64, Int64}[]),
    "E4" => escort("E4", (10, 4), String[], String[], 1, Dict{Int64, Vector{String}}(), Tuple{Int64, Int64}[]))
    
    # initialstate, items, escorts = randomintialstate((10, 10), 4, item_deadlines, rng)
    save_directory = raw"C:\codestuff\PBS\plots\\"
    save_plot(saveplot, initialstate, items, escorts, IO, "$(0)_test", save_directory)
    finalstate, makespandict = main(initialstate, items, escorts, IO, 1, save_directory)
    sumtime = 0
    max_time = 0
    for itemid in keys(makespandict)
        sumtime += makespandict[itemid]
        if makespandict[itemid] > max_time
            max_time = makespandict[itemid]
        end
    end
    average_time = sumtime / length(keys(makespandict))

    global makespan_sum += max_time
    global average_time_sum += average_time
    
    timerstop = time()

    average_makespan = makespan_sum / num_iterations
    average_of_average_time = average_time_sum / num_iterations
    println("Time elapsed: ", timerstop - timerstart)
    println("Average of makespan: ", average_makespan)
    println("Avg of Avg times: ", average_of_average_time)
end