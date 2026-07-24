-- ************************************************
-- Mode Manager Module for Bravo++
-- ************************************************
-- Manages mode cycling, CF mode switching, switch
-- mode cycling, and selector index management.
-- Decoupled from UI context building — the manager
-- handles state transitions while GUI updates are
-- triggered via dispatch callbacks after mode changes.
--
-- Extracted from BravoMultiMode.lua (FEAT-019, Phase 3b).
-- Uses M.init(opts) pattern for dependency injection.
-- ************************************************

local util = require("bravo++.util")
local log = require("bravo++.log")

local M = {}

-- Internal state (injected at init time)
local _dispatch_module = nil
local _modes_array = {}
local _selection_map_labels = {}
local _default_selections = {} -- luacheck: ignore (reserved for future API expansion)
local _default_button_labels = {}
local _button_map_labels = {} -- luacheck: ignore (reserved for future API expansion)

-- Selector index managed locally
local _selector_index = 1

-- Mode group info: maps conceptual name -> {count, current_index}
local _mode_group_info = {}
local _conceptual_mode_order = {}

-- ============================================================
-- Initialization
-- ============================================================

--- Initialize the mode manager with required dependencies.
--- @param opts table  Configuration options
---   - dispatch_module: module  The dispatch facade for state management
---   - modes_array: table  Array of mode names
---   - selection_map_labels: table  Mode/selection label mappings
---   - default_selections: table  Default selection names
---   - default_button_labels: table  Default button labels
---   - button_map_labels: table  Button label mappings per mode/selection
---   - on_mode_change: function  Callback invoked after mode changes (for LED refresh)
function M.init(opts)
    if not opts then
        return
    end
    if opts.dispatch_module and type(opts.dispatch_module) == "table" then
        _dispatch_module = opts.dispatch_module
    end
    if opts.modes_array and type(opts.modes_array) == "table" then
        _modes_array = opts.modes_array
    end
    if opts.selection_map_labels and type(opts.selection_map_labels) == "table" then
        _selection_map_labels = opts.selection_map_labels
    end
    if opts.default_selections and type(opts.default_selections) == "table" then
        _default_selections = opts.default_selections
    end
    if opts.default_button_labels and type(opts.default_button_labels) == "table" then
        _default_button_labels = opts.default_button_labels
    end
    if opts.button_map_labels and type(opts.button_map_labels) == "table" then
        _button_map_labels = opts.button_map_labels
    end

    -- Build conceptual mode order and group info
    M._build_mode_group_info()
end

-- ============================================================
-- Public: Mode Cycling
-- ============================================================

--- Cycle to the next mode (up).
--- @return string  New mode name
function M.cycle_mode_up()
    if not _dispatch_module then
        log.warning("mode_manager: dispatch_module not initialized")
        return nil
    end
    return _dispatch_module.cycle_mode_up()
end

--- Cycle to the previous mode (down).
--- @return string  New mode name
function M.cycle_mode_down()
    if not _dispatch_module then
        log.warning("mode_manager: dispatch_module not initialized")
        return nil
    end
    return _dispatch_module.cycle_mode_down()
end

--- Toggle between outer/inner CF mode.
--- @return string  New CF mode
function M.cycle_cf_mode()
    if not _dispatch_module then
        log.warning("mode_manager: dispatch_module not initialized")
        return nil
    end
    return _dispatch_module.cycle_cf_mode()
end

--- Toggle between up/down switch mode.
--- @return string  New switch mode
function M.cycle_switch_mode()
    if not _dispatch_module then
        log.warning("mode_manager: dispatch_module not initialized")
        return nil
    end
    return _dispatch_module.cycle_switch_mode()
end

--- Activate mode select (knob controls mode instead of selection).
function M.activate_mode_select()
    if not _dispatch_module then
        log.warning("mode_manager: dispatch_module not initialized")
        return
    end
    _dispatch_module.activate_mode_select()
end

--- Deactivate mode select.
function M.deactivate_mode_select()
    if not _dispatch_module then
        log.warning("mode_manager: dispatch_module not initialized")
        return
    end
    _dispatch_module.deactivate_mode_select()
end

-- ============================================================
-- Public: Selector Management
-- ============================================================

--- Set the local selector index.
--- The composition root (set_current_selector) calls dispatch.set_selector_index
--- separately with the on_update callback for LED refresh.
--- @param idx integer  1-based selector index
function M.set_selector_index(idx)
    _selector_index = idx
    -- Note: do NOT call _dispatch_module.set_selector_index(idx) here.
    -- The composition root (set_current_selector) calls dispatch.set_selector_index
    -- with the on_update callback for LED refresh. Calling it here without the
    -- callback would update the selection state prematurely, causing the callback
    -- in the composition root to be skipped (new_label == current_label check fails).
end

--- Get the current selector index.
--- @return integer
function M.get_selector_index()
    return _selector_index
end

-- ============================================================
-- Public: State Queries
-- ============================================================

--- Get the current mode from dispatch.
--- @return string  Current mode name
function M.get_current_mode()
    if not _dispatch_module then
        return nil
    end
    return _dispatch_module.get_current_mode()
end

--- Get the current selection from dispatch.
--- @return string  Current selection name
function M.get_current_selection()
    if not _dispatch_module then
        return nil
    end
    return _dispatch_module.get_current_selection()
end

--- Get the total number of modes.
--- @return integer
function M.get_mode_count()
    return #_modes_array
end

--- Get the conceptual mode order array.
--- @return table  Array of unique conceptual mode names
function M.get_conceptual_mode_order()
    return _conceptual_mode_order
end

--- Get the mode group info table.
--- @return table  Mode group info with counts and current indices
function M.get_mode_group_info()
    return _mode_group_info
end

-- ============================================================
-- Public: UI Context Building
-- ============================================================

--- Build UI context table for rendering.
--- Updates dynamic state (current_index) based on active mode.
--- @return table  UI context table
function M.build_ui_context()
    if not _dispatch_module then
        return {}
    end

    local current_mode = _dispatch_module.get_current_mode()
    local current_mode_conceptual = util.get_name_before_index(current_mode)

    -- Update current_index dynamically based on active mode
    for conceptual_name, group in pairs(_mode_group_info) do
        if group.count > 1 then
            group.current_index = nil -- reset until found
            local idx = 0
            for i = 1, #_modes_array do
                if util.get_name_before_index(_modes_array[i]) == conceptual_name then
                    idx = idx + 1
                    if _modes_array[i] == current_mode and conceptual_name == current_mode_conceptual then
                        group.current_index = idx
                        break
                    end
                end
            end
        end
    end

    return {
        current_mode = _dispatch_module.get_current_mode(),
        current_selection = _dispatch_module.get_current_selection(),
        current_cf_mode = _dispatch_module.get_current_cf_mode(),
        current_cf_mode_upper = string.upper(_dispatch_module.get_current_cf_mode()),
        current_switch_mode = _dispatch_module.get_current_switch_mode(),
        current_selection_label = _dispatch_module._get_current_selection_label(),
        conceptual_mode_order = _conceptual_mode_order,
        mode_group_info = _mode_group_info,
        selection_map_labels = _selection_map_labels,
        button_is_switch_map = _dispatch_module.get_button_is_switch_map(),
        default_button_labels = _default_button_labels,
        current_buttons = _dispatch_module.get_current_buttons(),
        twist_knob_map_actions = _dispatch_module.get_twist_knob_map_actions(),
    }
end

-- ============================================================
-- Internal Helpers
-- ============================================================

--- Build conceptual mode order and group info from modes array.
function M._build_mode_group_info()
    _conceptual_mode_order = {}
    _mode_group_info = {}

    local conceptual_name_seen = {}

    for i = 1, #_modes_array do
        local name_conceptual = util.get_name_before_index(_modes_array[i])
        if not conceptual_name_seen[name_conceptual] then
            table.insert(_conceptual_mode_order, name_conceptual)
            conceptual_name_seen[name_conceptual] = true
        end
    end

    for _, conceptual_name in ipairs(_conceptual_mode_order) do
        local count = 0
        for i = 1, #_modes_array do
            if util.get_name_before_index(_modes_array[i]) == conceptual_name then
                count = count + 1
            end
        end
        _mode_group_info[conceptual_name] = { count = count }
    end
end

return M
