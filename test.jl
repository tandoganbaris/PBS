using Test
include("main.jl")

@testset "Main Function Tests" begin
    global makespan_sum = 0
    global average_time_sum = 0
    num_iterations = 100
    timerstart = time()
 

    global saveplot = true
    
    item_deadlines = Dict("$i" => Float64(1000 - i * 10) for i in 1:20)
    IO = (5, 1)
    initialstate = 
    ["63" "58" "32" "E4" "18" "7" "21" "86" "80" "70"; 
    "83" "48" "44" "E2" "91" "23" "76" "12" "54" "66"; 
    "92" "13" "90" "93" "14" "28" "82" "74" "45" "4"; 
    "8" "49" "79" "27" "17" "35" "40" "57" "9" "43";
    "46" "24" "75" "55" "62" "96" "61" "87" "42" "59"; 
    "16" "39" "77" "36" "84" "51" "15" "2" "10" "81";
    "41" "69" "95" "64" "94" "30" "68" "11" "47" "72"; 
    "73" "26" "E3" "38" "85" "20" "19" "25" "6" "50"; 
    "5" "56" "22" "3" "31" "37" "E1" "1" "52" "71"; 
    "65" "29" "53" "67" "60" "88" "34" "33" "89" "78"]
    items = Dict{String, Any}("4" => item("4", (3, 10), 0, 0, 960.0, 0), "1" => item("1", (9, 8), 0, 0, 990.0, 0), "12" => item("12", (2, 8), 0, 0, 880.0, 0), "20" => item("20", (8, 6), 0, 0, 800.0, 0), "2" => item("2", (6, 8), 0, 0, 980.0, 0), "6" => item("6", (8, 9), 0, 0, 940.0, 0), "11" => item("11", (7, 8), 0, 0, 890.0, 0), "13" => item("13", (3, 2), 0, 0, 870.0, 0), "15" => item("15", (6, 7), 0, 0, 850.0, 0), "5" => item("5", (9, 1), 0, 0, 950.0, 0), "16" => item("16", (6, 1), 0, 0, 840.0, 0), "14" => item("14", (3, 5), 0, 0, 860.0, 0), "7" => item("7", (1, 6), 0, 0, 930.0, 0), "8" => item("8", (4, 1), 0, 0, 920.0, 0), "17" => item("17", (4, 5), 0, 0, 830.0, 0), "10" => item("10", (6, 9), 0, 0, 900.0, 0), "19" => item("19", (8, 7), 0, 0, 810.0, 0), "18" => item("18", (1, 5), 0, 0, 820.0, 0), "9" => item("9", (4, 9), 0, 0, 910.0, 0), "3" => item("3", (9, 4), 0, 0, 970.0, 0))

    escorts= Dict{String, Any}("E3" => escort("E3", (8, 3), String[], String[], 3, Dict{Int64, Vector{String}}(), Tuple{Int64, Int64}[]), 
    "E2" => escort("E2", (2, 4), String[], String[], 0, Dict{Int64, Vector{String}}(), Tuple{Int64, Int64}[]), 
    "E1" => escort("E1", (9, 7), String[], String[], 4, Dict{Int64, Vector{String}}(), Tuple{Int64, Int64}[]), 
    "E4" => escort("E4", (1, 4), String[], String[], 0, Dict{Int64, Vector{String}}(), Tuple{Int64, Int64}[]))
    
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