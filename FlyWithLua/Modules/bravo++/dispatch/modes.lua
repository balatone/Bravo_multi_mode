--[[
    bravo++.dispatch.modes - Mode Cycling Manager

    Responsibilities:
    - Mode cycling with index wrapping (cycle_mode_up, cycle_mode_down)
    - CF mode toggle (outer/inner)
    - Switch mode toggle (up/down)
    - Mode select activation/deactivation
    - Selector index setting with label updates
    - Button label management

    This module handles all mode cycling, selector management,
    and related state accessors.
]]

local util = require("bravo++.util")

local modes = {}

--- Cycle to the next mode (up).
--- @param state table  Shared state table
function modes.cycle_mode_up(state)
    local index = util.find(state.modes, state.current_mode)
    index = (index % #state.modes) + 1
    state.current_mode = state.modes[index]
    return state.current_mode
end

--- Cycle to the previous mode (down).
--- @param state table  Shared state table
function modes.cycle_mode_down(state)
    local index = util.find(state.modes, state.current_mode)
    index = ((index - 2) % #state.modes) + 1
    state.current_mode = state.modes[index]
    return state.current_mode
end

--- Toggle between outer/inner cf mode.
--- @param state table  Shared state table
function modes.cycle_cf_mode(state)
    local outer_inner_modes = { "outer", "inner" }
    local index = util.find(outer_inner_modes, state.current_cf_mode)
    index = (index % #outer_inner_modes) + 1
    state.current_cf_mode = outer_inner_modes[index]
    return state.current_cf_mode
end

--- Toggle between up/down switch mode.
--- @param state table  Shared state table
function modes.cycle_switch_mode(state)
    local up_down_modes = { "up", "down" }
    local index = util.find(up_down_modes, state.current_switch_mode)
    index = (index % #up_down_modes) + 1
    state.current_switch_mode = up_down_modes[index]
    return state.current_switch_mode
end

--- Activate mode select (knob controls mode instead of selection).
--- @param state table  Shared state table
function modes.activate_mode_select(state)
    state.mode_select = true
end

--- Deactivate mode select.
--- @param state table  Shared state table
function modes.deactivate_mode_select(state)
    state.mode_select = false
end

--- Set the selector index and update current selection label.
--- @param state table  Shared state table
--- @param idx integer  1-based selector index
--- @param on_update function  Callback to trigger LED refresh (optional)
function modes.set_selector_index(state, idx, on_update)
    if not state.selection_map_labels or not state.selection_map_labels[state.current_mode] then
        return
    end

    local new_label = state.selection_map_labels[state.current_mode][idx]
    if new_label and new_label ~= modes._get_current_selection_label(state) then
        modes._set_current_selection_label(state, new_label)
        state.current_selection = state.default_selections[idx]
        if on_update then
            on_update()
        end
    end
end

--- Get the current button labels for the active mode/selection.
--- @param state table  Shared state table
function modes.get_current_buttons(state)
    if
        state.button_map_labels
        and state.button_map_labels[state.current_mode]
        and state.button_map_labels[state.current_mode][state.current_selection]
    then
        return state.button_map_labels[state.current_mode][state.current_selection]
    end
    return state.default_button_labels
end

--- Get the current selection label.
--- @param state table  Shared state table
function modes._get_current_selection_label(state)
    return state.current_selection_label
end

--- Set the current selection label.
--- @param state table  Shared state table
--- @param v string  New label value
function modes._set_current_selection_label(state, v)
    state.current_selection_label = v
end

--- Initialize the selection label.
--- @param state table  Shared state table
--- @param l string  Label value (optional)
function modes.init_selection_label(state, l)
    state.current_selection_label = l or ""
end

return modes
