include("structs.jl")
include("pbsviz.jl")

const IO = (1, 1)

ESCORT_POSITIONS = [
    (1, 1),
    (2, 1),
    (2, 2),
    (3, 2),
]

MARKED_ITEM_POSITIONS = [
    (1, 3),
    (4, 2),
    (3, 1),
    (3, 9),
]

function build_presentation_state(escort_positions, item_positions)
    state   = fill("0", 10, 10)
    escorts = Dict{String, Any}()
    items   = Dict{String, Any}()

    for (k, (i, j)) in enumerate(escort_positions)
        eid = "A*" * string(k)
        state[i, j] = eid
        escorts[eid] = createescort(eid, (i, j))
    end

    for (k, (i, j)) in enumerate(item_positions)
        iid = string(k)
        state[i, j] = iid
        items[iid] = createitem(iid, (i, j), 1000.0)
    end

    return state, items, escorts
end

state, items, escorts = build_presentation_state(ESCORT_POSITIONS, MARKED_ITEM_POSITIONS)

p = plot_matrix(state, items, escorts, IO)
display(p)

saveplot = true
testid = "deadlock"
iter = 2
save_directory = raw"C:\Users\baris\PBSproject\plots\presentation"
save_plot(saveplot, state, items, escorts, IO, "$(testid)_$(iter)_test", save_directory)
