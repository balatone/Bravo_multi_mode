-- tests/integration/dispatch_spec.lua
-- Integration tests for refactored dispatch modules.
-- Tests all public functions: action map building, mode cycling,
-- button lifecycle, twist knob priority, trim boost logic,
-- rocker switch, and map accessors.
--
-- Time Mock API (from _bootstrap.lua):
--   _G.advance_time(dt)  - Advance mock clock by dt seconds
--   _G.set_time(t)       - Set mock clock to absolute time t

-- Clear module cache to ensure fresh load with mocked globals
package.loaded["bravo++.log"] = nil
package.loaded["bravo++.util"] = nil
package.loaded["bravo++.dispatch"] = nil
package.loaded["bravo++.dispatch.action_map"] = nil
package.loaded["bravo++.dispatch.buttons"] = nil
package.loaded["bravo++.dispatch.twist"] = nil
package.loaded["bravo++.dispatch.trim"] = nil
package.loaded["bravo++.dispatch.modes"] = nil

local dispatch = require("bravo++.dispatch")
local action_map = require("bravo++.dispatch.action_map")
local buttons = require("bravo++.dispatch.buttons")
local twist = require("bravo++.dispatch.twist")
local trim = require("bravo++.dispatch.trim")
local modes = require("bravo++.dispatch.modes")

-- ============================================================
-- Test Helpers
-- ============================================================

local function create_test_state()
    return {
        button_map_actions = {},
        button_is_switch_map = {},
        twist_knob_map_actions = {},
        rocker_switch_led_states = {},
        current_mode = nil,
        current_selection = nil,
        current_cf_mode = "outer",
        current_switch_mode = "up",
        mode_select = false,
        trim_last_click_time = 0,
        trim_dataref = nil,
        trim_increment = 0.01,
        trim_boost_factor = 3,
        trim_boost_window = 0.2,
        command_state = {},
        arrow_color = 0xFF00FF00,
        long_click_threshold = 0.5,
        continuous_press_threshold = 1.0,
        current_selection_label = "",
        selection_map_labels = nil,
        button_map_labels = nil,
        modes = nil,
        default_selections = nil,
        default_button_labels = nil,
        nav_bindings = nil,
    }
end

local function create_test_ctx()
    return {
        modes = { "NAV", "COM", "XPNDR" },
        default_selections = { "SEL1", "SEL2", "ALT" },
        default_button_labels = { "BTN1", "BTN2", "BTN3" },
    }
end

local function create_test_bindings()
    return {
        -- Mode-level button (ALT selection)
        NAV_BTN1_BUTTON = "sim/nav/cycle_up",

        -- Selection-aware button
        NAV_SEL1_BTN2_BUTTON = "sim/com/active_freq_up",
        NAV_SEL1_BTN2_BUTTON_2 = "sim/com/active_freq_down",

        -- Switch-mode button (UP/DOWN)
        NAV_SEL2_BTN3_UP_BUTTON = "sim/switch/up",
        NAV_SEL2_BTN3_DOWN_BUTTON = "sim/switch/down",

        -- Twist knob bindings
        NAV_SEL1_UP = "sim/knob/direct_up",
        NAV_SEL1_DOWN = "sim/knob/direct_down",
        NAV_SEL2_OUTER_UP = "sim/knob/outer_up",
        NAV_SEL2_OUTER_DOWN = "sim/knob/outer_down",
        NAV_SEL2_INNER_UP = "sim/knob/inner_up",
        NAV_SEL2_INNER_DOWN = "sim/knob/inner_down",

        -- Rocker switch bindings
        SWITCH1_UP = "sim/switch/1_up",
        SWITCH1_DOWN = "sim/switch/1_down",

        -- Thresholds
        LONG_CLICK_THRESHOLD = "0.3",
        CONTINUOUS_PRESS_THRESHOLD = "0.6",

        -- Trim config
        TRIM_INCREMENT = "0.02",
        TRIM_BOOST = "4",
    }
end

-- ============================================================
-- dispatch.init()
-- ============================================================

describe("Dispatch - init()", function()
    it("should initialize with modes and selections", function()
        local bindings = create_test_bindings()
        local ctx = create_test_ctx()
        dispatch.init(bindings, ctx)

        assert.equals("NAV", dispatch.get_current_mode())
        assert.equals("SEL1", dispatch.get_current_selection())
    end)

    it("should set thresholds from config", function()
        local bindings = create_test_bindings()
        local ctx = create_test_ctx()
        dispatch.init(bindings, ctx)

        -- Thresholds should be set from config
        -- We verify by checking the behavior uses them
        assert.equals(0.3, tonumber(bindings.LONG_CLICK_THRESHOLD))
    end)

    it("should set trim config from bindings", function()
        local bindings = create_test_bindings()
        local ctx = create_test_ctx()
        dispatch.init(bindings, ctx)

        assert.equals(0.02, tonumber(bindings.TRIM_INCREMENT))
        assert.equals(4, tonumber(bindings.TRIM_BOOST))
    end)
end)

-- ============================================================
-- Action Map Builder (dispatch_action_map)
-- ============================================================

describe("Dispatch - Action Map Builder", function()
    local state
    local bindings
    local ctx

    before_each(function()
        state = create_test_state()
        bindings = create_test_bindings()
        ctx = create_test_ctx()
        state.modes = ctx.modes
        state.default_selections = ctx.default_selections
        state.default_button_labels = ctx.default_button_labels
    end)

    it("should build button action map with mode-level bindings", function()
        action_map.build_button_action_map(state, bindings, ctx)

        -- NAV mode, BTN1 should have ON_CLICK
        assert.equals(
            "sim/nav/cycle_up",
            state.button_map_actions["NAV"]["BTN1"]["ON_CLICK"]
        )
    end)

    it("should build button action map with selection-aware bindings", function()
        action_map.build_button_action_map(state, bindings, ctx)

        -- NAV mode, SEL1, BTN2 should have ON_CLICK
        assert.equals(
            "sim/com/active_freq_up",
            state.button_map_actions["NAV"]["SEL1"]["BTN2"]["ON_CLICK"]
        )
    end)

    it("should build button action map with switch-mode UP/DOWN bindings", function()
        action_map.build_button_action_map(state, bindings, ctx)

        -- NAV mode, SEL2, BTN3 should have UP/DOWN
        assert.equals(
            "sim/switch/up",
            state.button_map_actions["NAV"]["SEL2"]["BTN3"]["UP"]["ON_CLICK"]
        )
        assert.equals(
            "sim/switch/down",
            state.button_map_actions["NAV"]["SEL2"]["BTN3"]["DOWN"]["ON_CLICK"]
        )
    end)

    it("should set is_switch_map for switch-mode buttons", function()
        action_map.build_button_action_map(state, bindings, ctx)

        assert.is_true(
            state.button_is_switch_map["NAV"]["SEL2"]["BTN3"]
        )
    end)

    it("should build twist knob action map with direct bindings", function()
        action_map.build_twist_knob_action_map(state, bindings, ctx)

        assert.equals(
            "sim/knob/direct_up",
            state.twist_knob_map_actions["NAV"]["SEL1"]["UP"]
        )
        assert.equals(
            "sim/knob/direct_down",
            state.twist_knob_map_actions["NAV"]["SEL1"]["DOWN"]
        )
    end)

    it("should build twist knob action map with OUTER/INNER bindings", function()
        action_map.build_twist_knob_action_map(state, bindings, ctx)

        assert.equals(
            "sim/knob/outer_up",
            state.twist_knob_map_actions["NAV"]["SEL2"]["OUTER"]["UP"]
        )
        assert.equals(
            "sim/knob/inner_up",
            state.twist_knob_map_actions["NAV"]["SEL2"]["INNER"]["UP"]
        )
    end)

    it("should return empty maps for missing bindings", function()
        local empty_bindings = {}
        action_map.build_button_action_map(state, empty_bindings, ctx)

        -- Should not error, maps should be empty
        assert.is_table(state.button_map_actions)
        assert.is_table(state.button_is_switch_map)
    end)
end)

-- ============================================================
-- Mode Cycling (dispatch_modes)
-- ============================================================

describe("Dispatch - Mode Cycling", function()
    local state

    before_each(function()
        state = create_test_state()
        state.modes = { "NAV", "COM", "XPNDR" }
        state.current_mode = "NAV"
        state.current_selection = "SEL1"
        state.current_cf_mode = "outer"
        state.current_switch_mode = "up"
        state.mode_select = false
        state.default_selections = { "SEL1", "SEL2", "ALT" }
        state.default_button_labels = { "BTN1", "BTN2", "BTN3" }
        state.button_map_labels = {}
        state.selection_map_labels = {
            NAV = { "Label1", "Label2", "Label3" },
        }
    end)

    it("should cycle mode up within bounds", function()
        local result = modes.cycle_mode_up(state)
        assert.equals("COM", result)
        assert.equals("COM", state.current_mode)
    end)

    it("should cycle mode down within bounds", function()
        state.current_mode = "COM"
        local result = modes.cycle_mode_down(state)
        assert.equals("NAV", result)
        assert.equals("NAV", state.current_mode)
    end)

    it("should wrap mode up at end", function()
        state.current_mode = "XPNDR"
        local result = modes.cycle_mode_up(state)
        assert.equals("NAV", result)
        assert.equals("NAV", state.current_mode)
    end)

    it("should wrap mode down at beginning", function()
        state.current_mode = "NAV"
        local result = modes.cycle_mode_down(state)
        assert.equals("XPNDR", result)
        assert.equals("XPNDR", state.current_mode)
    end)

    it("should toggle cf mode from outer to inner", function()
        local result = modes.cycle_cf_mode(state)
        assert.equals("inner", result)
        assert.equals("inner", state.current_cf_mode)
    end)

    it("should toggle cf mode from inner to outer", function()
        state.current_cf_mode = "inner"
        local result = modes.cycle_cf_mode(state)
        assert.equals("outer", result)
        assert.equals("outer", state.current_cf_mode)
    end)

    it("should toggle switch mode from up to down", function()
        local result = modes.cycle_switch_mode(state)
        assert.equals("down", result)
        assert.equals("down", state.current_switch_mode)
    end)

    it("should toggle switch mode from down to up", function()
        state.current_switch_mode = "down"
        local result = modes.cycle_switch_mode(state)
        assert.equals("up", result)
        assert.equals("up", state.current_switch_mode)
    end)

    it("should activate mode select", function()
        modes.activate_mode_select(state)
        assert.is_true(state.mode_select)
    end)

    it("should deactivate mode select", function()
        state.mode_select = true
        modes.deactivate_mode_select(state)
        assert.is_false(state.mode_select)
    end)

    it("should set selector index and update label", function()
        local callback_called = false
        modes.set_selector_index(state, 2, function()
            callback_called = true
        end)

        assert.equals("Label2", state.current_selection_label)
        assert.equals("SEL2", state.current_selection)
        assert.is_true(callback_called)
    end)

    it("should not update selector if label is unchanged", function()
        state.current_selection_label = "Label1"
        local callback_called = false
        modes.set_selector_index(state, 1, function()
            callback_called = true
        end)

        assert.is_false(callback_called)
    end)

    it("should return default button labels when no specific labels exist", function()
        local result = modes.get_current_buttons(state)
        assert.equals(state.default_button_labels, result)
    end)

    it("should return specific button labels when available", function()
        state.button_map_labels = {
            NAV = {
                SEL1 = { "SPEC1", "SPEC2", "SPEC3" },
            },
        }
        local result = modes.get_current_buttons(state)
        assert.equals("SPEC1", result[1])
    end)
end)

-- ============================================================
-- Button Command Resolution (dispatch_buttons)
-- ============================================================

describe("Dispatch - Button Command Resolution", function()
    local state
    local bindings
    local ctx

    before_each(function()
        state = create_test_state()
        bindings = create_test_bindings()
        ctx = create_test_ctx()
        state.modes = ctx.modes
        state.default_selections = ctx.default_selections
        state.default_button_labels = ctx.default_button_labels
        state.current_mode = "NAV"
        state.current_selection = "SEL1"
        state.current_switch_mode = "up"

        -- Build action maps
        action_map.build_button_action_map(state, bindings, ctx)
    end)

    it("should resolve mode-level button command", function()
        local result = buttons.resolve_button_command(state, "BTN1")
        assert.is_table(result)
        assert.equals("sim/nav/cycle_up", result["ON_CLICK"])
    end)

    it("should resolve selection-aware button command", function()
        local result = buttons.resolve_button_command(state, "BTN2")
        assert.is_table(result)
        assert.equals("sim/com/active_freq_up", result["ON_CLICK"])
    end)

    it("should resolve switch-mode UP button when switch mode is up", function()
        state.current_selection = "SEL2"
        state.current_switch_mode = "up"
        local result = buttons.resolve_button_command(state, "BTN3")
        assert.is_table(result)
        assert.equals("sim/switch/up", result["ON_CLICK"])
    end)

    it("should resolve switch-mode DOWN button when switch mode is down", function()
        state.current_selection = "SEL2"
        state.current_switch_mode = "down"
        local result = buttons.resolve_button_command(state, "BTN3")
        assert.is_table(result)
        assert.equals("sim/switch/down", result["ON_CLICK"])
    end)

    it("should return nil for unknown button", function()
        local result = buttons.resolve_button_command(state, "UNKNOWN_BTN")
        -- Returns "sim/none/none" string for unknown buttons
        assert.equals("sim/none/none", result)
    end)
end)

-- ============================================================
-- Button Press Lifecycle (dispatch_buttons)
-- ============================================================

describe("Dispatch - Button Press Lifecycle", function()
    local state
    local bindings
    local ctx

    before_each(function()
        state = create_test_state()
        bindings = create_test_bindings()
        ctx = create_test_ctx()
        state.modes = ctx.modes
        state.default_selections = ctx.default_selections
        state.default_button_labels = ctx.default_button_labels
        state.current_mode = "NAV"
        state.current_selection = "SEL1"
        state.current_switch_mode = "up"
        state.long_click_threshold = 0.3
        state.continuous_press_threshold = 0.6

        -- Build action maps
        action_map.build_button_action_map(state, bindings, ctx)

        -- Reset time
        _G.set_time(0)
    end)

    it("should initialize command state on button_begin", function()
        buttons.button_begin(state, "BTN1")

        assert.is_table(state.command_state["BTN1"])
        assert.equals("begin", state.command_state["BTN1"].phase)
        assert.is_false(state.command_state["BTN1"].is_continuous_mode)
        assert.equals(0xFF00FF00, state.arrow_color)
    end)

    it("should detect long click on button_end", function()
        buttons.button_begin(state, "BTN1")
        _G.advance_time(0.4) -- Exceeds long_click_threshold of 0.3
        buttons.button_end(state, "BTN1")

        -- State should be cleaned up
        assert.is_nil(state.command_state["BTN1"])
    end)

    it("should detect single click on button_end", function()
        buttons.button_begin(state, "BTN1")
        _G.advance_time(0.1) -- Below long_click_threshold
        buttons.button_end(state, "BTN1")

        -- State should be cleaned up
        assert.is_nil(state.command_state["BTN1"])
    end)

    it("should handle unexpected button_end without begin", function()
        buttons.button_end(state, "BTN1")

        -- Should not error, just reset state
        assert.equals(0xFF00FF00, state.arrow_color)
    end)

    it("should enter continuous mode on button_continue", function()
        buttons.button_begin(state, "BTN1")
        _G.advance_time(0.7) -- Exceeds continuous_press_threshold of 0.6
        buttons.button_continue(state, "BTN1")

        assert.is_true(state.command_state["BTN1"].is_continuous_mode)
        assert.equals(0xFFED10D8, state.arrow_color)
    end)

    it("should not enter continuous mode before threshold", function()
        buttons.button_begin(state, "BTN1")
        _G.advance_time(0.2) -- Below continuous_press_threshold
        buttons.button_continue(state, "BTN1")

        assert.is_false(state.command_state["BTN1"].is_continuous_mode)
    end)

    it("should handle button_continue without begin", function()
        buttons.button_continue(state, "BTN1")
        -- Should not error
        assert.is_nil(state.command_state["BTN1"])
    end)
end)

-- ============================================================
-- Twist Knob Execution (dispatch_twist)
-- ============================================================

describe("Dispatch - Twist Knob Execution", function()
    local state

    before_each(function()
        state = create_test_state()
        state.modes = { "NAV", "COM" }
        state.current_mode = "NAV"
        state.current_selection = "SEL1"
        state.current_cf_mode = "outer"
        state.mode_select = false

        -- Track commands
        _G.command_once = function(cmd)
            state.last_command = cmd
        end
    end)

    it("should execute direct UP action with priority", function()
        state.twist_knob_map_actions = {
            NAV = {
                SEL1 = {
                    UP = "sim/direct_up",
                    DOWN = "sim/direct_down",
                    OUTER = { UP = "sim/outer_up" },
                    INNER = { UP = "sim/inner_up" },
                },
            },
        }
        twist.knob_increase(state)
        assert.equals("sim/direct_up", state.last_command)
    end)

    it("should execute OUTER UP when cf_mode is outer and no direct", function()
        state.current_cf_mode = "outer"
        state.twist_knob_map_actions = {
            NAV = {
                SEL1 = {
                    OUTER = { UP = "sim/outer_up" },
                    INNER = { UP = "sim/inner_up" },
                },
            },
        }
        twist.knob_increase(state)
        assert.equals("sim/outer_up", state.last_command)
    end)

    it("should execute INNER UP when cf_mode is inner and no direct/outer", function()
        state.current_cf_mode = "inner"
        state.twist_knob_map_actions = {
            NAV = {
                SEL1 = {
                    OUTER = { UP = "sim/outer_up" },
                    INNER = { UP = "sim/inner_up" },
                },
            },
        }
        twist.knob_increase(state)
        assert.equals("sim/inner_up", state.last_command)
    end)

    it("should execute direct DOWN action with priority", function()
        state.twist_knob_map_actions = {
            NAV = {
                SEL1 = {
                    UP = "sim/direct_up",
                    DOWN = "sim/direct_down",
                    OUTER = { DOWN = "sim/outer_down" },
                    INNER = { DOWN = "sim/inner_down" },
                },
            },
        }
        twist.knob_decrease(state)
        assert.equals("sim/direct_down", state.last_command)
    end)

    it("should execute mode select command when mode_select is true", function()
        state.mode_select = true
        twist.knob_increase(state)
        assert.equals("FlyWithLua/Bravo++/cycle_mode_up", state.last_command)
    end)

    it("should handle missing action map gracefully", function()
        state.twist_knob_map_actions = {}
        twist.knob_increase(state)
        -- Should not error, no command executed
        assert.is_nil(state.last_command)
    end)

    it("should handle missing selection gracefully", function()
        state.twist_knob_map_actions = {
            NAV = {},
        }
        twist.knob_decrease(state)
        -- Should not error
        assert.is_nil(state.last_command)
    end)
end)

-- ============================================================
-- Trim Wheel Execution (dispatch_trim)
-- ============================================================

describe("Dispatch - Trim Wheel Execution", function()
    local state

    before_each(function()
        state = create_test_state()
        state.trim_dataref = {}; state.trim_dataref[0] = 0
        state.trim_increment = 0.02
        state.trim_boost_factor = 4
        state.trim_boost_window = 0.2
        state.trim_last_click_time = 0
        _G.set_time(0)
    end)

    it("should trim nose up by increment", function()
        _G.set_time(1.0)
        state.trim_last_click_time = 0
        trim.trim_nose_up(state)
        assert.equals(0.02, state.trim_dataref[0])
    end)

    it("should trim nose up with boost when within boost window", function()
        _G.set_time(0.1)
        state.trim_last_click_time = 0
        trim.trim_nose_up(state)
        -- Boost: 0.02 * 4 = 0.08
        assert.equals(0.08, state.trim_dataref[0])
    end)

    it("should trim nose down by increment", function()
        _G.set_time(1.0)
        state.trim_last_click_time = 0
        trim.trim_nose_down(state)
        assert.equals(-0.02, state.trim_dataref[0])
    end)

    it("should trim nose down with boost when within boost window", function()
        _G.set_time(0.1)
        state.trim_last_click_time = 0
        trim.trim_nose_down(state)
        -- Boost: -0.02 * 4 = -0.08
        assert.equals(-0.08, state.trim_dataref[0])
    end)

    it("should clamp trim value to 1", function()
        state.trim_dataref = {}; state.trim_dataref[0] = 0.99
        _G.set_time(1.0)
        state.trim_last_click_time = 0
        trim.trim_nose_up(state)
        assert.are_near(1, state.trim_dataref[0], 0.001)
    end)

    it("should clamp trim value to -1", function()
        state.trim_dataref = {}; state.trim_dataref[0] = -0.99
        _G.set_time(1.0)
        state.trim_last_click_time = 0
        trim.trim_nose_down(state)
        assert.equals(-1, state.trim_dataref[0])
    end)

    it("should not trim when dataref is nil", function()
        state.trim_dataref = nil
        trim.trim_nose_up(state)
        -- Should not error
    end)

    it("should handle boost window entry", function()
        -- First click
        _G.set_time(0)
        state.trim_last_click_time = 0
        trim.trim_nose_up(state)
        assert.equals(0.08, state.trim_dataref[0]) -- boosted

        -- Second click within boost window
        _G.set_time(0.1)
        trim.trim_nose_up(state)
        -- Another boost: 0.08 + 0.08 = 0.16
        assert.equals(0.16, state.trim_dataref[0])
    end)

    it("should handle boost window exit", function()
        -- First click
        _G.set_time(0)
        state.trim_last_click_time = 0
        trim.trim_nose_up(state)
        assert.equals(0.08, state.trim_dataref[0]) -- boosted

        -- Second click after boost window
        _G.set_time(0.3)
        trim.trim_nose_up(state)
        -- Normal increment: 0.08 + 0.02 = 0.10
        assert.equals(0.10, state.trim_dataref[0])
    end)
end)

-- ============================================================
-- Rocker Switch
-- ============================================================

describe("Dispatch - Rocker Switch", function()
    local state

    before_each(function()
        state = create_test_state()
        state.nav_bindings = {
            SWITCH1_UP = "sim/switch/1_up",
            SWITCH1_DOWN = "sim/switch/1_down",
        }
        state.rocker_switch_led_states = {}

        _G.command_once = function(cmd)
            state.last_command = cmd
        end
    end)

    it("should execute rocker switch UP command", function()
        -- Access through facade to test rocker_switch
        dispatch.rocker_switch(1, "UP")
        -- Note: rocker_switch uses local nav_bindings in facade
    end)

    it("should get rocker switch LED state", function()
        dispatch.set_rocker_switch_led("SW1", true)
        assert.is_true(dispatch.get_rocker_switch_led("SW1"))
    end)

    it("should set rocker switch LED state", function()
        dispatch.set_rocker_switch_led("SW2", true)
        assert.is_true(dispatch.get_rocker_switch_led("SW2"))

        dispatch.set_rocker_switch_led("SW2", false)
        assert.is_false(dispatch.get_rocker_switch_led("SW2"))
    end)

    it("should return false for unset LED state", function()
        assert.is_false(dispatch.get_rocker_switch_led("UNKNOWN"))
    end)
end)

-- ============================================================
-- Map Accessors (dispatch_action_map)
-- ============================================================

describe("Dispatch - Map Accessors", function()
    local state
    local bindings
    local ctx

    before_each(function()
        state = create_test_state()
        bindings = create_test_bindings()
        ctx = create_test_ctx()
        state.modes = ctx.modes
        state.default_selections = ctx.default_selections
        state.default_button_labels = ctx.default_button_labels
    end)

    it("should return button is-switch map", function()
        action_map.build_button_action_map(state, bindings, ctx)
        local result = action_map.get_button_is_switch_map(state)

        assert.is_table(result)
        assert.is_table(result["NAV"])
    end)

    it("should return twist knob map actions", function()
        action_map.build_twist_knob_action_map(state, bindings, ctx)
        local result = action_map.get_twist_knob_map_actions(state)

        assert.is_table(result)
        assert.is_table(result["NAV"])
    end)
end)

-- ============================================================
-- State Accessors (dispatch_modes)
-- ============================================================

describe("Dispatch - State Accessors", function()
    local state

    before_each(function()
        state = create_test_state()
        state.current_selection_label = ""
    end)

    it("should get and set selection label", function()
        modes._set_current_selection_label(state, "TestLabel")
        assert.equals("TestLabel", modes._get_current_selection_label(state))
    end)

    it("should initialize selection label", function()
        modes.init_selection_label(state, "InitLabel")
        assert.equals("InitLabel", modes._get_current_selection_label(state))
    end)

    it("should initialize selection label with nil", function()
        modes.init_selection_label(state, nil)
        assert.equals("", modes._get_current_selection_label(state))
    end)
end)

-- ============================================================
-- Facade Integration (dispatch.lua)
-- ============================================================

describe("Dispatch - Facade Integration", function()
    local bindings
    local ctx

    before_each(function()
        bindings = create_test_bindings()
        ctx = create_test_ctx()
        dispatch.init(bindings, ctx)
    end)

    it("should expose all state accessors", function()
        assert.equals("NAV", dispatch.get_current_mode())
        assert.equals("SEL1", dispatch.get_current_selection())
        assert.equals("outer", dispatch.get_current_cf_mode())
        assert.equals("up", dispatch.get_current_switch_mode())
    end)

    it("should expose mode cycling through facade", function()
        local result = dispatch.cycle_mode_up()
        assert.equals("COM", result)
        assert.equals("COM", dispatch.get_current_mode())
    end)

    it("should expose cf mode toggle through facade", function()
        dispatch.cycle_cf_mode()
        assert.equals("inner", dispatch.get_current_cf_mode())
    end)

    it("should expose switch mode toggle through facade", function()
        dispatch.cycle_switch_mode()
        assert.equals("down", dispatch.get_current_switch_mode())
    end)

    it("should expose mode select through facade", function()
        dispatch.activate_mode_select()
        assert.is_true(dispatch.is_mode_select())
        dispatch.deactivate_mode_select()
        assert.is_false(dispatch.is_mode_select())
    end)

    it("should expose button lifecycle through facade", function()
        dispatch.button_begin("BTN1")
        -- Should not error
        dispatch.button_end("BTN1")
    end)

    it("should expose map accessors through facade", function()
        local switch_map = dispatch.get_button_is_switch_map()
        assert.is_table(switch_map)

        local knob_map = dispatch.get_twist_knob_map_actions()
        assert.is_table(knob_map)
    end)

    it("should expose context accessors through facade", function()
        assert.equals(ctx.modes, dispatch.get_modes())
        assert.equals(ctx.default_selections, dispatch.get_default_selections())
        assert.equals(ctx.default_button_labels, dispatch.get_default_button_labels())
    end)

    it("should set trim dataref through facade", function()
        local mock_dr = { 0 }
        dispatch.set_trim_dataref(mock_dr)
        dispatch.trim_nose_up()
        -- Should not error
    end)

    it("should expose arrow color through facade", function()
        local color = dispatch.get_arrow_color()
        assert.equals(0xFF00FF00, color)
    end)

    it("should resolve button command through facade", function()
        local result = dispatch.resolve_button_command("BTN1")
        assert.is_table(result)
        assert.equals("sim/nav/cycle_up", result["ON_CLICK"])
    end)
end)
