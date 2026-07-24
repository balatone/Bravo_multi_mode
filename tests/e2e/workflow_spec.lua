-- tests/e2e/workflow_spec.lua
-- End-to-end workflow simulations for the bravo++ system.
-- Simulates complete operational workflows including:
--   1. Full HID report cycles (baseline -> rotary -> selector -> trim)
--   2. Rapid mixed events with debouncing
--   3. Mode cycling workflows with CF mode priority resolution
--
-- Time Mock API (from _bootstrap.lua):
--   _G.advance_time(dt)  - Advance mock clock by dt seconds
--   _G.set_time(t)       - Set mock clock to absolute time t

-- Clear module cache to ensure fresh load with mocked globals
package.loaded["bravo++.log"] = nil
package.loaded["bravo++.util"] = nil
package.loaded["bravo++.debug"] = nil
package.loaded["bravo++.state"] = nil
package.loaded["bravo++.decoder"] = nil
package.loaded["bravo++.hardware"] = nil
package.loaded["bravo++.dispatch"] = nil
package.loaded["bravo++.dispatch.action_map"] = nil
package.loaded["bravo++.dispatch.buttons"] = nil
package.loaded["bravo++.dispatch.twist"] = nil
package.loaded["bravo++.dispatch.trim"] = nil
package.loaded["bravo++.dispatch.modes"] = nil

local decoder = require("bravo++.decoder")
local state = require("bravo++.state")
local hardware = require("bravo++.hardware")
local dispatch = require("bravo++.dispatch")
local twist = require("bravo++.dispatch.twist")

-- ============================================================
-- Test Helpers
-- ============================================================

local function make_report(byte15, byte16)
    local report = {}
    for i = 1, 16 do
        report[i] = 0
    end
    if byte15 then report[15] = byte15 end
    if byte16 then report[16] = byte16 end
    return report
end

local function reset_all()
    decoder.reset()
    state.reset()
    dispatch.reset()
    _G.set_time(0)
end

local function create_test_bindings()
    return {
        MODES = "AUTO,NAV,COM",
        NAV_SELECTOR_LABELS = "A,B,C,D,E",
        COM_SELECTOR_LABELS = "A,B,C,D,E",
        AUTO_SELECTOR_LABELS = "A,B,C,D,E",
        NAV_SEL1_BUTTON_LABELS = "B1,B2,B3,B4,B5,B6,B7,B8",
        COM_SEL1_BUTTON_LABELS = "B1,B2,B3,B4,B5,B6,B7,B8",
        SWITCH_LABELS = "S1,S2,S3,S4,S5,S6,S7",
        NAV_BTN1_BUTTON = "sim/nav/cycle_up",
        NAV_SEL1_BTN2_BUTTON = "sim/com/active_freq_up",
        NAV_SEL1_UP = "sim/knob/direct_up",
        NAV_SEL1_DOWN = "sim/knob/direct_down",
        NAV_SEL2_OUTER_UP = "sim/knob/outer_up",
        NAV_SEL2_OUTER_DOWN = "sim/knob/outer_down",
        NAV_SEL2_INNER_UP = "sim/knob/inner_up",
        NAV_SEL2_INNER_DOWN = "sim/knob/inner_down",
        TRIM_INCREMENT = "0.01",
        TRIM_BOOST = "3",
        LONG_CLICK_THRESHOLD = "0.5",
        CONTINUOUS_PRESS_THRESHOLD = "1.0",
    }
end

local function create_test_ctx()
    return {
        modes = { "AUTO", "NAV", "COM" },
        default_selections = { "SEL1", "SEL2", "SEL3", "SEL4", "SEL5" },
        default_button_labels = { "B1", "B2", "B3", "B4", "B5", "B6", "B7", "B8" },
        up_down_modes = { "up", "down" },
        outer_inner_modes = { "outer", "inner" },
    }
end

-- ============================================================
-- Full HID Report Cycle
-- ============================================================

describe("E2E - Full HID Report Cycle", function()
    before_each(reset_all)

    it("should process complete HID report cycle: baseline -> CW -> selector -> trim -> CCW", function()
        local events = {}
        decoder.set_handlers({
            on_rotary_cw = function()
                table.insert(events, "rotary_cw")
            end,
            on_rotary_ccw = function()
                table.insert(events, "rotary_ccw")
            end,
            on_selector_changed = function(s)
                table.insert(events, "selector_" .. s)
            end,
            on_trim_changed = function(d)
                table.insert(events, "trim_" .. d)
            end,
        })

        -- Frame 1: baseline (all zeros)
        decoder.on_report(make_report(0x00, 0x00))
        _G.advance_time()

        -- Frame 2: CW rotary pulse
        decoder.on_report(make_report(0x10, 0x00))
        _G.advance_time()

        -- Frame 3: rotary returns to zero, selector moves to position 1
        decoder.on_report(make_report(0x00, 0x01))
        _G.advance_time()

        -- Frame 4: selector returns to zero, trim down pulse
        decoder.on_report(make_report(0x00, 0x20))
        _G.advance_time()

        -- Frame 5: trim returns to zero, CCW rotary pulse
        decoder.on_report(make_report(0x20, 0x00))

        -- Verify events
        assert.equals(5, #events)
        assert.equals("rotary_cw", events[1])
        assert.equals("selector_5", events[2])
        assert.equals("trim_down", events[3])
        assert.equals("rotary_ccw", events[4])
        assert.equals("trim_down", events[5]) -- falling edge of trim pulse

        -- Verify state transitions
        assert.equals(5, state.get_selector())
        assert.equals("down", state.get_trim())

        -- Verify counters
        local diag = decoder.diagnostics()
        assert.equals(2, diag.counters.rotary_events)
        assert.equals(1, diag.counters.selector_changes)
        assert.equals(2, diag.counters.trim_events)
    end)

    it("should handle full cycle with debouncing suppressing spurious events", function()
        local events = {}
        decoder.set_handlers({
            on_rotary_cw = function()
                table.insert(events, "cw")
            end,
            on_rotary_ccw = function()
                table.insert(events, "ccw")
            end,
            on_selector_changed = function(s)
                table.insert(events, "sel_" .. s)
            end,
            on_trim_changed = function(d)
                table.insert(events, "trim_" .. d)
            end,
        })

        -- Baseline at time 0
        _G.set_time(0.0)
        decoder.on_report(make_report(0x00, 0x00))

        -- CW rotary at time 1.0
        _G.set_time(1.0)
        decoder.on_report(make_report(0x10, 0x00))

        -- Spurious CW at time 1.01 (within 0.030 debounce window) - should be suppressed
        _G.set_time(1.01)
        decoder.on_report(make_report(0x00, 0x00))
        decoder.on_report(make_report(0x10, 0x00))

        -- Selector change after debounce window
        _G.set_time(1.2)
        decoder.on_report(make_report(0x00, 0x00))
        decoder.on_report(make_report(0x00, 0x01))

        -- Trim pulse (rising edge only - no clear to avoid falling edge)
        _G.set_time(1.4)
        decoder.on_report(make_report(0x00, 0x20))

        -- CCW rotary at time 1.6 (byte16=0x00 clears trim, triggering falling edge)
        _G.set_time(1.6)
        decoder.on_report(make_report(0x20, 0x00))

        -- Events: CW(1) + sel5(1) + trim_down_rising(1) + CCW(1) + trim_down_falling(1) = 5
        -- Spurious CW suppressed by debounce (1.01-1.0=0.01 < 0.030)
        assert.equals(5, #events)
        assert.equals("cw", events[1])
        assert.equals("sel_5", events[2])
        assert.equals("trim_down", events[3])
        assert.equals("ccw", events[4])
        assert.equals("trim_down", events[5]) -- falling edge from byte16 0x20->0x00
    end)

    it("should process multiple complete cycles sequentially", function()
        local event_count = 0
        decoder.set_handlers({
            on_rotary_cw = function()
                event_count = event_count + 1
            end,
            on_rotary_ccw = function()
                event_count = event_count + 1
            end,
            on_selector_changed = function()
                event_count = event_count + 1
            end,
            on_trim_changed = function()
                event_count = event_count + 1
            end,
        })

        -- Cycle 1
        decoder.on_report(make_report(0x00, 0x00))
        _G.set_time(0.0)
        decoder.on_report(make_report(0x10, 0x00))
        _G.set_time(0.15)
        decoder.on_report(make_report(0x00, 0x01))
        _G.set_time(0.30)
        decoder.on_report(make_report(0x00, 0x00))
        _G.set_time(0.45)
        decoder.on_report(make_report(0x00, 0x20))

        -- Cycle 2
        _G.set_time(1.0)
        decoder.on_report(make_report(0x00, 0x00))
        _G.set_time(1.15)
        decoder.on_report(make_report(0x20, 0x00))
        _G.set_time(1.30)
        decoder.on_report(make_report(0x00, 0x02))
        _G.set_time(1.45)
        decoder.on_report(make_report(0x00, 0x00))
        _G.set_time(1.60)
        decoder.on_report(make_report(0x00, 0x40))

        -- Verify multiple cycles processed
        assert.is_true(event_count >= 6)
    end)
end)

-- ============================================================
-- Rapid Mixed Events with Debouncing
-- ============================================================

describe("E2E - Rapid Mixed Events with Debouncing", function()
    before_each(reset_all)

    it("should debounce rapid rotary events of same direction", function()
        local cw_count = 0
        decoder.set_handlers({
            on_rotary_cw = function()
                cw_count = cw_count + 1
            end,
        })

        -- Baseline
        decoder.on_report(make_report(0x00, 0x00))

        -- Rapid CW events
        _G.set_time(0.0)
        decoder.on_report(make_report(0x10, 0x00)) -- CW 1 - accepted

        _G.set_time(0.01)
        decoder.on_report(make_report(0x00, 0x00)) -- clear
        _G.set_time(0.02)
        decoder.on_report(make_report(0x10, 0x00)) -- CW 2 - suppressed (debounce)

        _G.set_time(0.03)
        decoder.on_report(make_report(0x00, 0x00)) -- clear
        _G.set_time(0.04)
        decoder.on_report(make_report(0x10, 0x00)) -- CW 3 - suppressed (dedupe)

        -- After dedupe window
        _G.set_time(0.20)
        decoder.on_report(make_report(0x00, 0x00)) -- clear
        _G.set_time(0.25)
        decoder.on_report(make_report(0x10, 0x00)) -- CW 4 - accepted

        assert.equals(2, cw_count)
    end)

    it("should debounce rapid selector changes", function()
        local sel_events = {}
        decoder.set_handlers({
            on_selector_changed = function(s)
                table.insert(sel_events, s)
            end,
        })

        -- Baseline
        decoder.on_report(make_report(0x00, 0x00))

        -- Rapid selector changes
        _G.set_time(0.0)
        decoder.on_report(make_report(0x00, 0x01)) -- sel 5 - accepted

        _G.set_time(0.01)
        decoder.on_report(make_report(0x00, 0x00)) -- clear
        _G.set_time(0.02)
        decoder.on_report(make_report(0x00, 0x02)) -- sel 4 - suppressed (debounce)

        -- After debounce
        _G.set_time(0.20)
        decoder.on_report(make_report(0x00, 0x00)) -- clear
        _G.set_time(0.25)
        decoder.on_report(make_report(0x00, 0x04)) -- sel 3 - accepted

        assert.equals(2, #sel_events)
    end)

    it("should debounce rapid trim events", function()
        local trim_events = {}
        decoder.set_handlers({
            on_trim_changed = function(d)
                table.insert(trim_events, d)
            end,
        })

        -- Baseline
        decoder.on_report(make_report(0x00, 0x00))

        -- Rapid trim events
        _G.set_time(0.0)
        decoder.on_report(make_report(0x00, 0x20)) -- trim down - accepted

        _G.set_time(0.01)
        decoder.on_report(make_report(0x00, 0x00)) -- clear
        _G.set_time(0.02)
        decoder.on_report(make_report(0x00, 0x40)) -- trim up - suppressed (debounce)

        -- After debounce
        _G.set_time(0.20)
        decoder.on_report(make_report(0x00, 0x00)) -- clear
        _G.set_time(0.25)
        decoder.on_report(make_report(0x00, 0x20)) -- trim down - accepted

        assert.equals(2, #trim_events)
    end)

    it("should handle burst of all three feature types simultaneously", function()
        local events = {}
        decoder.set_handlers({
            on_rotary_cw = function()
                table.insert(events, "cw")
            end,
            on_rotary_ccw = function()
                table.insert(events, "ccw")
            end,
            on_selector_changed = function(s)
                table.insert(events, "sel_" .. s)
            end,
            on_trim_changed = function(d)
                table.insert(events, "trim_" .. d)
            end,
        })

        -- Baseline
        decoder.on_report(make_report(0x00, 0x00))

        -- Burst of mixed events with proper spacing
        _G.set_time(0.0)
        decoder.on_report(make_report(0x10, 0x00)) -- CW rotary

        _G.set_time(0.15)
        decoder.on_report(make_report(0x00, 0x00)) -- clear
        _G.set_time(0.20)
        decoder.on_report(make_report(0x00, 0x01)) -- selector 5

        _G.set_time(0.35)
        decoder.on_report(make_report(0x00, 0x00)) -- clear
        _G.set_time(0.40)
        decoder.on_report(make_report(0x00, 0x20)) -- trim down

        _G.set_time(0.55)
        decoder.on_report(make_report(0x00, 0x00)) -- clear
        _G.set_time(0.60)
        decoder.on_report(make_report(0x20, 0x00)) -- CCW rotary

        _G.set_time(0.75)
        decoder.on_report(make_report(0x00, 0x00)) -- clear
        _G.set_time(0.80)
        decoder.on_report(make_report(0x00, 0x02)) -- selector 4

        _G.set_time(0.95)
        decoder.on_report(make_report(0x00, 0x00)) -- clear
        _G.set_time(1.00)
        decoder.on_report(make_report(0x00, 0x40)) -- trim up

        -- Verify all events processed correctly
        -- Trim uses XOR edge detection: rising + falling = 2 events per pulse
        -- Last trim pulse (0x40) has no trailing clear, so only rising edge fires
        -- CW(1) + sel5(1) + trim_down_rising(1) + trim_down_falling(1) + CCW(1) + sel4(1) + trim_up_rising(1) = 7
        assert.equals(7, #events)
        assert.equals("cw", events[1])
        assert.equals("sel_5", events[2])
        assert.equals("trim_down", events[3])
        assert.equals("trim_down", events[4]) -- falling edge of trim pulse
        assert.equals("ccw", events[5])
        assert.equals("sel_4", events[6])
        assert.equals("trim_up", events[7])
    end)

    it("should deduplicate redundant state updates within window", function()
        local state_updates = 0
        state.subscribe_state("selector", function()
            state_updates = state_updates + 1
        end)

        -- First selector change
        decoder.on_report(make_report(0x00, 0x00))
        _G.set_time(0.0)
        decoder.on_report(make_report(0x00, 0x01)) -- selector 5

        -- Same selector within dedupe window - should not update state
        _G.set_time(0.05)
        decoder.on_report(make_report(0x00, 0x00)) -- clear
        _G.set_time(0.10)
        decoder.on_report(make_report(0x00, 0x01)) -- selector 5 again (same value)

        -- Different selector after dedupe window
        _G.set_time(0.50)
        decoder.on_report(make_report(0x00, 0x00)) -- clear
        _G.set_time(0.55)
        decoder.on_report(make_report(0x00, 0x02)) -- selector 4

        assert.equals(2, state_updates)
    end)
end)

-- ============================================================
-- Mode Cycling Workflow
-- ============================================================

describe("E2E - Mode Cycling Workflow", function()
    local bindings
    local ctx

    before_each(function()
        reset_all()
        bindings = create_test_bindings()
        ctx = create_test_ctx()
    end)

    it("should switch modes and verify state transitions", function()
        dispatch.init(bindings, ctx)

        -- Start in AUTO mode
        assert.equals("AUTO", dispatch.get_current_mode())
        assert.equals("SEL1", dispatch.get_current_selection())

        -- Switch to NAV mode
        dispatch.cycle_mode_up()
        assert.equals("NAV", dispatch.get_current_mode())

        -- Switch to COM mode
        dispatch.cycle_mode_up()
        assert.equals("COM", dispatch.get_current_mode())

        -- Wrap back to AUTO
        dispatch.cycle_mode_up()
        assert.equals("AUTO", dispatch.get_current_mode())
    end)

    it("should toggle CF mode and verify twist knob priority changes", function()
        -- Mock command tracking
        local last_command = nil
        _G.command_once = function(cmd)
            last_command = cmd
        end

        dispatch.init(bindings, ctx)
        dispatch.cycle_mode_up() -- Switch to NAV

        -- Set up twist knob action map for testing
        local state = dispatch._get_internal_state()
        state.twist_knob_map_actions = {
            NAV = {
                SEL1 = {
                    UP = "sim/knob/direct_up",
                    DOWN = "sim/knob/direct_down",
                },
                SEL2 = {
                    OUTER = { UP = "sim/knob/outer_up", DOWN = "sim/knob/outer_down" },
                    INNER = { UP = "sim/knob/inner_up", DOWN = "sim/knob/inner_down" },
                },
            },
        }

        -- CF mode starts as "outer"
        assert.equals("outer", dispatch.get_current_cf_mode())

        -- Direct priority: UP/DOWN string takes precedence over OUTER/INNER
        dispatch.set_current_selection("SEL1")
        twist.knob_increase(state)
        assert.equals("sim/knob/direct_up", last_command)

        -- Switch to SEL2 with OUTER/INNER bindings
        dispatch.set_current_selection("SEL2")

        -- CF mode outer -> should execute OUTER UP
        twist.knob_increase(state)
        assert.equals("sim/knob/outer_up", last_command)

        -- Toggle CF mode to inner
        dispatch.cycle_cf_mode()
        assert.equals("inner", dispatch.get_current_cf_mode())

        -- CF mode inner -> should execute INNER UP
        twist.knob_increase(state)
        assert.equals("sim/knob/inner_up", last_command)
    end)

    it("should activate and deactivate mode select", function()
        -- Mock command tracking
        local last_command = nil
        _G.command_once = function(cmd)
            last_command = cmd
        end

        dispatch.init(bindings, ctx)

        -- Mode select should be inactive by default
        assert.is_false(dispatch.is_mode_select())

        -- Activate mode select
        dispatch.activate_mode_select()
        assert.is_true(dispatch.is_mode_select())

        -- Twist knob should cycle mode when mode_select is active
        local state = dispatch._get_internal_state()
        twist.knob_increase(state)
        assert.equals("FlyWithLua/Bravo++/cycle_mode_up", last_command)

        -- Deactivate mode select
        dispatch.deactivate_mode_select()
        assert.is_false(dispatch.is_mode_select())
    end)

    it("should verify selector index propagation through label callbacks", function()
        local callback_count = 0
        local last_label = nil

        dispatch.init(bindings, ctx)
        local int_state = dispatch._get_internal_state()

        -- Set up selection map labels
        int_state.selection_map_labels = {
            AUTO = { "Alpha", "Bravo", "Charlie", "Delta", "Echo" },
            NAV = { "Nav1", "Nav2", "Nav3", "Nav4", "Nav5" },
            COM = { "Com1", "Com2", "Com3", "Com4", "Com5" },
        }

        -- Initialize the selection label to match current selection (SEL1 = index 1)
        dispatch.init_selection_label(int_state.selection_map_labels[int_state.current_mode][1])
        assert.equals("Alpha", dispatch._get_current_selection_label())

        -- Set selector index with callback
        dispatch.set_selector_index(3, function()
            callback_count = callback_count + 1
            last_label = dispatch._get_internal_state().current_selection_label
        end)

        assert.equals("Charlie", last_label)
        assert.equals(1, callback_count)
        assert.equals("SEL3", dispatch.get_current_selection())
    end)

    it("should notify subscribers of state changes during mode cycling", function()
        local notification_count = 0
        local notified_selectors = {}

        -- Subscribe to selector changes
        state.subscribe_state("selector", function()
            notification_count = notification_count + 1
            table.insert(notified_selectors, state.get_selector())
        end)

        dispatch.init(bindings, ctx)
        local int_state = dispatch._get_internal_state()

        -- Set up selection map labels for set_selector_index to work
        int_state.selection_map_labels = {
            AUTO = { "Alpha", "Bravo", "Charlie", "Delta", "Echo" },
            NAV = { "Nav1", "Nav2", "Nav3", "Nav4", "Nav5" },
            COM = { "Com1", "Com2", "Com3", "Com4", "Com5" },
        }

        -- Cycle through selectors, triggering state updates
        for i = 1, 5 do
            dispatch.set_selector_index(i)
            -- set_selector_index updates dispatch state; also update state module for subscribers
            state.set_selector(i)
        end

        -- Verify subscribers were notified
        assert.equals(5, notification_count)
        assert.equals(5, #notified_selectors)
    end)

    it("should handle switch mode toggling correctly", function()
        dispatch.init(bindings, ctx)

        -- Start in UP switch mode
        assert.equals("up", dispatch.get_current_switch_mode())

        -- Toggle to DOWN
        dispatch.cycle_switch_mode()
        assert.equals("down", dispatch.get_current_switch_mode())

        -- Toggle back to UP
        dispatch.cycle_switch_mode()
        assert.equals("up", dispatch.get_current_switch_mode())
    end)

    it("should verify twist knob priority resolution: direct > OUTER > INNER", function()
        local last_command = nil
        _G.command_once = function(cmd)
            last_command = cmd
        end

        dispatch.init(bindings, ctx)
        dispatch.cycle_mode_up() -- NAV mode

        local state = dispatch._get_internal_state()

        -- Test 1: Direct UP/DOWN has highest priority
        state.twist_knob_map_actions = {
            NAV = {
                SEL1 = {
                    UP = "direct_up",
                    DOWN = "direct_down",
                    OUTER = { UP = "outer_up" },
                    INNER = { UP = "inner_up" },
                },
            },
        }
        state.current_cf_mode = "outer"
        twist.knob_increase(state)
        assert.equals("direct_up", last_command)

        -- Test 2: OUTER has priority when cf_mode is outer and no direct
        state.twist_knob_map_actions = {
            NAV = {
                SEL1 = {
                    OUTER = { UP = "outer_up" },
                    INNER = { UP = "inner_up" },
                },
            },
        }
        state.current_cf_mode = "outer"
        twist.knob_increase(state)
        assert.equals("outer_up", last_command)

        -- Test 3: INNER has priority when cf_mode is inner and no direct
        state.current_cf_mode = "inner"
        twist.knob_increase(state)
        assert.equals("inner_up", last_command)
    end)
end)
