--[[
    bravo++.dispatch - Command and Action Mapping Module (Facade)

    Responsibilities:
    - Facade for dispatch sub-modules
    - Maintains shared state across sub-modules
    - Provides unified API for BravoMultiMode.lua

    This module maintains backward compatibility by providing the same
    public API as the original monolithic dispatch module. All logic
    has been extracted into sub-modules for testability.
]]

local log = require("bravo++.log")

-- Import sub-modules
local action_map = require("bravo++.dispatch_action_map")
local buttons = require("bravo++.dispatch_buttons")
local twist = require("bravo++.dispatch_twist")
local trim = require("bravo++.dispatch_trim")
local modes = require("bravo++.dispatch_modes")

local dispatch = {}

-- ============================================================
-- Shared State (initialized by init())
-- ============================================================

local state = {
    -- Action maps
    button_map_actions = {},
    button_is_switch_map = {},
    twist_knob_map_actions = {},

    -- Rocker switch LED states
    rocker_switch_led_states = {},

    -- Mode/switch state
    current_mode = nil,
    current_selection = nil,
    current_cf_mode = "outer",
    current_switch_mode = "up",
    mode_select = false,

    -- Trim state
    trim_last_click_time = 0,
    trim_dataref = nil,
    trim_increment = 0.01,
    trim_boost_factor = 3,
    trim_boost_window = 0.2,

    -- Button command state
    command_state = {},
    arrow_color = 0xFF00FF00,

    -- Thresholds
    long_click_threshold = 0.5,
    continuous_press_threshold = 1.0,

    -- Selection label
    current_selection_label = "",

    -- External references (set during init)
    selection_map_labels = nil,
    button_map_labels = nil,
    modes = nil,
    default_selections = nil,
    default_button_labels = nil,
    nav_bindings = nil,
}

-- ============================================================
-- Initialization
-- ============================================================

--- Initialize the dispatch module with parsed config and external references.
--- @param bindings table  Parsed configuration bindings from bravo++.config
--- @param ctx table  Context table containing modes, selections, labels, etc.
function dispatch.init(bindings, ctx)
    state.nav_bindings = bindings
    state.modes = ctx.modes or {}
    state.default_selections = ctx.default_selections or {}
    state.default_button_labels = ctx.default_button_labels or {}
    state.selection_map_labels = ctx.selection_map_labels or {}
    state.button_map_labels = ctx.button_map_labels or {}

    state.current_mode = state.modes[1]
    state.current_selection = state.default_selections[1]

    -- Thresholds from config
    local is_windows = (package.config and package.config:sub(1, 1) == "\\")
    state.long_click_threshold = state.nav_bindings.LONG_CLICK_THRESHOLD
            and tonumber(state.nav_bindings.LONG_CLICK_THRESHOLD)
        or (is_windows and 0.250 or 0.500)
    state.continuous_press_threshold = state.nav_bindings.CONTINUOUS_PRESS_THRESHOLD
            and tonumber(state.nav_bindings.CONTINUOUS_PRESS_THRESHOLD)
        or (is_windows and 0.750 or 1.0)

    -- Trim config
    state.trim_increment = tonumber(state.nav_bindings.TRIM_INCREMENT) or 0.01
    state.trim_boost_factor = tonumber(state.nav_bindings.TRIM_BOOST) or 3

    log.info("Initializing button action map...")
    action_map.build_button_action_map(state, state.nav_bindings, {
        modes = state.modes,
        default_selections = state.default_selections,
        default_button_labels = state.default_button_labels,
    })

    log.info("Initializing twist knob action map...")
    action_map.build_twist_knob_action_map(state, state.nav_bindings, {
        modes = state.modes,
        default_selections = state.default_selections,
    })

    log.info("Dispatch module initialized.")
end

--- Set the dataref table for trim (called after X-Plane dataref system is ready)
function dispatch.set_trim_dataref(dr)
    state.trim_dataref = dr
end

-- ============================================================
-- Public: State Accessors/Mutators
-- ============================================================

function dispatch.get_current_mode()
    return state.current_mode
end

function dispatch.set_current_mode(m)
    state.current_mode = m
end

function dispatch.get_current_selection()
    return state.current_selection
end

function dispatch.set_current_selection(s)
    state.current_selection = s
end

function dispatch.get_current_cf_mode()
    return state.current_cf_mode
end

function dispatch.get_current_switch_mode()
    return state.current_switch_mode
end

function dispatch.is_mode_select()
    return state.mode_select
end

-- ============================================================
-- Public: Mode Cycling (delegated to dispatch_modes)
-- ============================================================

function dispatch.cycle_mode_up()
    return modes.cycle_mode_up(state)
end

function dispatch.cycle_mode_down()
    return modes.cycle_mode_down(state)
end

function dispatch.cycle_cf_mode()
    return modes.cycle_cf_mode(state)
end

function dispatch.cycle_switch_mode()
    return modes.cycle_switch_mode(state)
end

function dispatch.activate_mode_select()
    modes.activate_mode_select(state)
end

function dispatch.deactivate_mode_select()
    modes.deactivate_mode_select(state)
end

-- ============================================================
-- Public: Selector & Button Label Management (delegated to dispatch_modes)
-- ============================================================

function dispatch.set_selector_index(idx, on_update)
    modes.set_selector_index(state, idx, on_update)
end

function dispatch.get_current_buttons()
    return modes.get_current_buttons(state)
end

function dispatch._get_current_selection_label()
    return modes._get_current_selection_label(state)
end

function dispatch._set_current_selection_label(v)
    modes._set_current_selection_label(state, v)
end

function dispatch.init_selection_label(l)
    modes.init_selection_label(state, l)
end

-- ============================================================
-- Public: Button Action Execution (delegated to dispatch_buttons)
-- ============================================================

function dispatch.resolve_button_command(button_name)
    return buttons.resolve_button_command(state, button_name)
end

function dispatch.button_begin(button_name)
    buttons.button_begin(state, button_name)
end

function dispatch.button_continue(button_name)
    buttons.button_continue(state, button_name)
end

function dispatch.button_end(button_name)
    buttons.button_end(state, button_name)
end

-- ============================================================
-- Public: Twist Knob Execution (delegated to dispatch_twist)
-- ============================================================

function dispatch.knob_increase()
    twist.knob_increase(state)
end

function dispatch.knob_decrease()
    twist.knob_decrease(state)
end

-- ============================================================
-- Public: Rocker Switch Execution
-- ============================================================

function dispatch.rocker_switch(rocker_number, dir)
    local key = "SWITCH" .. rocker_number .. "_" .. dir
    local binding = state.nav_bindings and state.nav_bindings[key]

    if binding then
        log.info("Rocker switch " .. rocker_number .. " " .. dir .. ": " .. binding)
        _G.command_once(binding)
    else
        log.warning("No binding for rocker switch " .. rocker_number .. " " .. dir)
    end
end

function dispatch.get_rocker_switch_led(name)
    return state.rocker_switch_led_states[name] or false
end

function dispatch.set_rocker_switch_led(name, led_state)
    state.rocker_switch_led_states[name] = led_state or false
end

-- ============================================================
-- Public: Trim Wheel Execution (delegated to dispatch_trim)
-- ============================================================

function dispatch.trim_nose_up()
    trim.trim_nose_up(state)
end

function dispatch.trim_nose_down()
    trim.trim_nose_down(state)
end

-- ============================================================
-- Public: Map Accessors (delegated to dispatch_action_map)
-- ============================================================

function dispatch.get_button_is_switch_map()
    return action_map.get_button_is_switch_map(state)
end

function dispatch.get_twist_knob_map_actions()
    return action_map.get_twist_knob_map_actions(state)
end

function dispatch.get_modes()
    return state.modes
end

function dispatch.get_default_selections()
    return state.default_selections
end

function dispatch.get_default_button_labels()
    return state.default_button_labels
end

-- ============================================================
-- Public: Arrow Color (for UI)
-- ============================================================

function dispatch.get_arrow_color()
    return state.arrow_color
end

-- ============================================================
-- Test-only accessor for E2E/integration tests
-- ============================================================

function dispatch._get_internal_state()
    return state
end

function dispatch.set_switch_mode(m)
    state.current_switch_mode = m
end

--- Reset all internal state to defaults. Use for testing isolation.
function dispatch.reset()
    state.button_map_actions = {}
    state.button_is_switch_map = {}
    state.twist_knob_map_actions = {}
    state.rocker_switch_led_states = {}
    state.current_mode = nil
    state.current_selection = nil
    state.current_cf_mode = "outer"
    state.current_switch_mode = "up"
    state.mode_select = false
    state.trim_last_click_time = 0
    state.trim_dataref = nil
    state.trim_increment = 0.01
    state.trim_boost_factor = 3
    state.trim_boost_window = 0.2
    state.command_state = {}
    state.arrow_color = 0xFF00FF00
    state.long_click_threshold = 0.5
    state.continuous_press_threshold = 1.0
    state.current_selection_label = ""
    state.selection_map_labels = nil
    state.button_map_labels = nil
    state.modes = nil
    state.default_selections = nil
    state.default_button_labels = nil
    state.nav_bindings = nil
end

return dispatch
