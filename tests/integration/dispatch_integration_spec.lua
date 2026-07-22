-- tests/integration/dispatch_integration_spec.lua
-- Integration tests for cross-module interaction chains:
--   1. Decoder -> State subscriber notification
--   2. Config + Dispatch action map construction
--   3. Hardware injection queue -> Decoder event detection
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
package.loaded["bravo++.dispatch_action_map"] = nil
package.loaded["bravo++.dispatch_buttons"] = nil
package.loaded["bravo++.dispatch_twist"] = nil
package.loaded["bravo++.dispatch_trim"] = nil
package.loaded["bravo++.dispatch_modes"] = nil

local decoder = require("bravo++.decoder")
local state = require("bravo++.state")
local hardware = require("bravo++.hardware")
local dispatch = require("bravo++.dispatch")
local action_map = require("bravo++.dispatch_action_map")
local modes = require("bravo++.dispatch_modes")

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

local function reset_decoder_and_state()
    decoder.reset()
    state.reset()
    _G.set_time(0)
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

        -- Thresholds
        LONG_CLICK_THRESHOLD = "0.3",
        CONTINUOUS_PRESS_THRESHOLD = "0.6",

        -- Trim config
        TRIM_INCREMENT = "0.02",
        TRIM_BOOST = "4",
    }
end

local function create_test_ctx()
    return {
        modes = { "NAV", "COM", "XPNDR" },
        default_selections = { "SEL1", "SEL2", "ALT" },
        default_button_labels = { "BTN1", "BTN2", "BTN3" },
        up_down_modes = { "up", "down" },
        outer_inner_modes = { "outer", "inner" },
    }
end

-- ============================================================
-- Decoder -> State Integration Tests
-- ============================================================

describe("Integration - Decoder to State subscriber notification", function()
    before_each(reset_decoder_and_state)

    it("should update state via decoder on selector change", function()
        -- Decoder should call state.set_selector() when a selector event is detected
        decoder.on_report(make_report(0x00, 0x00))
        _G.advance_time()
        decoder.on_report(make_report(0x00, 0x01)) -- selector position 5

        assert.is_not_nil(state.get_selector())
        assert.equals(5, state.get_selector())
    end)

    it("should update state via decoder on trim event", function()
        -- Decoder should call state.set_trim() when a trim event is detected
        decoder.on_report(make_report(0x00, 0x00))
        _G.advance_time()
        decoder.on_report(make_report(0x00, 0x20)) -- trim down

        assert.equals("down", state.get_trim())
    end)

    it("should fire subscriber callback with correct selector value", function()
        local received_selector = nil
        state.subscribe_state("selector", function(val)
            received_selector = val
        end)

        decoder.on_report(make_report(0x00, 0x00))
        _G.advance_time()
        decoder.on_report(make_report(0x00, 0x02)) -- selector position 4

        assert.equals(4, received_selector)
    end)

    it("should fire subscriber callback with correct trim value", function()
        local received_trim = nil
        state.subscribe_state("trim", function(val)
            received_trim = val
        end)

        decoder.on_report(make_report(0x00, 0x00))
        _G.advance_time()
        decoder.on_report(make_report(0x00, 0x40)) -- trim up

        assert.equals("up", received_trim)
    end)

    it("should notify multiple subscribers in order", function()
        local call_order = {}
        state.subscribe_state("selector", function()
            table.insert(call_order, "sub1")
        end)
        state.subscribe_state("selector", function()
            table.insert(call_order, "sub2")
        end)

        decoder.on_report(make_report(0x00, 0x00))
        _G.advance_time()
        decoder.on_report(make_report(0x00, 0x04)) -- selector position 3

        assert.equals(2, #call_order)
        assert.equals("sub1", call_order[1])
        assert.equals("sub2", call_order[2])
    end)

    it("should isolate subscriber errors via pcall", function()
        local good_called = false
        -- First subscriber throws an error
        state.subscribe_state("selector", function()
            error("subscriber error")
        end)
        -- Second subscriber should still be called
        state.subscribe_state("selector", function()
            good_called = true
        end)

        decoder.on_report(make_report(0x00, 0x00))
        _G.advance_time()
        decoder.on_report(make_report(0x00, 0x08)) -- selector position 2

        -- Second subscriber should have been called despite first error
        assert.is_true(good_called)
    end)

    it("should not fire subscriber for duplicate selector value", function()
        local call_count = 0
        state.subscribe_state("selector", function()
            call_count = call_count + 1
        end)

        -- First selector change
        decoder.on_report(make_report(0x00, 0x00))
        _G.advance_time()
        decoder.on_report(make_report(0x00, 0x01)) -- selector 5

        -- Same selector value again (should not fire)
        _G.advance_time()
        decoder.on_report(make_report(0x00, 0x00))
        _G.advance_time()
        decoder.on_report(make_report(0x00, 0x01)) -- selector 5 again

        assert.equals(1, call_count)
    end)

    it("should not fire subscriber for duplicate trim value", function()
        local call_count = 0
        state.subscribe_state("trim", function()
            call_count = call_count + 1
        end)

        -- First trim event
        decoder.on_report(make_report(0x00, 0x00))
        _G.advance_time()
        decoder.on_report(make_report(0x00, 0x20)) -- trim down

        -- Same trim value (should not fire)
        _G.advance_time()
        decoder.on_report(make_report(0x00, 0x00))
        _G.advance_time()
        decoder.on_report(make_report(0x00, 0x20)) -- trim down again

        assert.equals(1, call_count)
    end)
end)

-- ============================================================
-- Config + Dispatch Integration Tests
-- ============================================================

describe("Integration - Config and Dispatch action map construction", function()
    local bindings
    local ctx

    before_each(function()
        dispatch.reset()
        bindings = create_test_bindings()
        ctx = create_test_ctx()
    end)

    it("should build button action maps from parsed config bindings", function()
        dispatch.init(bindings, ctx)
        -- Already in NAV mode (first mode)

        -- Verify mode-level button
        local result = dispatch.resolve_button_command("BTN1")
        assert.is_table(result)
        assert.equals("sim/nav/cycle_up", result["ON_CLICK"])
    end)

    it("should build selection-aware button action maps", function()
        dispatch.init(bindings, ctx)
        -- Already in NAV mode (first mode)

        -- Verify selection-aware button
        local result = dispatch.resolve_button_command("BTN2")
        assert.is_table(result)
        assert.equals("sim/com/active_freq_up", result["ON_CLICK"])
    end)

    it("should resolve switch-mode UP button correctly", function()
        dispatch.init(bindings, ctx)
        -- Already in NAV mode (first mode)
        dispatch.set_current_selection("SEL2")
        dispatch.set_switch_mode("up")

        local result = dispatch.resolve_button_command("BTN3")
        assert.is_table(result)
        assert.equals("sim/switch/up", result["ON_CLICK"])
    end)

    it("should resolve switch-mode DOWN button correctly", function()
        dispatch.init(bindings, ctx)
        -- Already in NAV mode (first mode)
        dispatch.set_current_selection("SEL2")
        dispatch.set_switch_mode("down")

        local result = dispatch.resolve_button_command("BTN3")
        assert.is_table(result)
        assert.equals("sim/switch/down", result["ON_CLICK"])
    end)

    it("should build twist knob action maps from bindings", function()
        dispatch.init(bindings, ctx)

        local knob_map = dispatch.get_twist_knob_map_actions()
        assert.is_table(knob_map)
        assert.is_table(knob_map["NAV"])
    end)

    it("should build twist knob action maps with direct bindings", function()
        dispatch.init(bindings, ctx)
        -- Already in NAV mode (first mode)

        local knob_map = dispatch.get_twist_knob_map_actions()
        assert.equals("sim/knob/direct_up", knob_map["NAV"]["SEL1"]["UP"])
        assert.equals("sim/knob/direct_down", knob_map["NAV"]["SEL1"]["DOWN"])
    end)

    it("should verify action map construction via dispatch.init()", function()
        dispatch.init(bindings, ctx)

        -- Verify all maps were constructed
        local switch_map = dispatch.get_button_is_switch_map()
        assert.is_table(switch_map)
        assert.is_table(switch_map["NAV"])

        -- Verify switch-mode buttons are marked as switches in NAV mode
        assert.is_true(switch_map["NAV"]["SEL2"]["BTN3"])
    end)

    it("should handle mode cycling and action map resolution", function()
        dispatch.init(bindings, ctx)

        -- Start in NAV mode (first mode)
        assert.equals("NAV", dispatch.get_current_mode())

        -- BTN1 should resolve correctly in NAV mode
        local result = dispatch.resolve_button_command("BTN1")
        assert.is_table(result)
        assert.equals("sim/nav/cycle_up", result["ON_CLICK"])

        -- Cycle to COM mode
        dispatch.cycle_mode_up()
        assert.equals("COM", dispatch.get_current_mode())
    end)

    it("should compile and consume conditions in dispatch init", function()
        -- Verify that dispatch.init() completes without error
        -- and consumes compiled conditions correctly
        dispatch.init(bindings, ctx)

        -- Basic state should be initialized
        assert.equals("NAV", dispatch.get_current_mode())
        assert.equals("SEL1", dispatch.get_current_selection())
        assert.equals("outer", dispatch.get_current_cf_mode())
        assert.equals("up", dispatch.get_current_switch_mode())
    end)
end)

-- ============================================================
-- Hardware -> Decoder Integration Tests
-- ============================================================

describe("Integration - Hardware injection queue to Decoder event detection", function()
    before_each(function()
        reset_decoder_and_state()
        hardware.init({ simulate = true })
        hardware.start()
    end)

    after_each(function()
        hardware.stop()
    end)

    it("should inject and poll reports through hardware to decoder", function()
        -- Subscribe decoder to hardware reports
        hardware.subscribe(function(report)
            decoder.on_report(report)
        end)

        -- Inject a CW rotary report
        hardware.inject_report(make_report(0x10, 0x00))
        _G.advance_time()

        -- Poll hardware - should process the injected report
        local drained = hardware.poll()
        assert.equals(1, drained)

        -- Verify decoder detected the event
        local diag = decoder.diagnostics()
        assert.is_true(diag.counters.rotary_events >= 1)
    end)

    it("should drain multiple injected reports in FIFO order", function()
        local received_reports = {}
        hardware.subscribe(function(report)
            table.insert(received_reports, report)
        end)

        -- Inject multiple reports
        hardware.inject_report(make_report(0x10, 0x00)) -- CW
        hardware.inject_report(make_report(0x00, 0x01)) -- selector
        hardware.inject_report(make_report(0x00, 0x20)) -- trim

        -- Poll and verify all reports were processed
        local drained = hardware.poll()
        assert.equals(3, drained)
        assert.equals(3, #received_reports)

        -- Verify FIFO order
        assert.equals(0x10, received_reports[1][15])
        assert.equals(0x01, received_reports[2][16])
        assert.equals(0x20, received_reports[3][16])
    end)

    it("should enforce max_reports_per_poll cap", function()
        local received_count = 0
        hardware.subscribe(function()
            received_count = received_count + 1
        end)

        -- Inject more reports than the cap
        for i = 1, 20 do
            hardware.inject_report(make_report(0x00, 0x00))
        end

        local drained = hardware.poll()
        assert.is_true(drained <= hardware.max_reports_per_poll)
        assert.equals(drained, received_count)
    end)

    it("should pass injected reports through to decoder handlers", function()
        local cw_detected = false
        decoder.set_handlers({
            on_rotary_cw = function()
                cw_detected = true
            end,
        })

        hardware.subscribe(function(report)
            decoder.on_report(report)
        end)

        -- Inject baseline first
        hardware.inject_report(make_report(0x00, 0x00))
        hardware.poll()

        -- Advance time for debounce
        _G.advance_time()

        -- Inject CW rotary
        hardware.inject_report(make_report(0x10, 0x00))
        hardware.poll()

        assert.is_true(cw_detected)
    end)

    it("should handle empty injection queue gracefully", function()
        hardware.subscribe(function()
            -- Should not be called
            assert.is_true(false)
        end)

        local drained = hardware.poll()
        assert.equals(0, drained)
    end)

    it("should update diagnostics after polling", function()
        hardware.subscribe(function(report)
            decoder.on_report(report)
        end)

        hardware.inject_report(make_report(0x10, 0x00))
        hardware.poll()

        local diag = hardware.diagnostics()
        assert.is_true(diag.total_reports >= 1)
        assert.is_true(diag.poll_calls >= 1)
        assert.equals(1, diag.last_drained)
    end)

    it("should support subscriber error isolation", function()
        local good_called = false

        -- First subscriber throws error
        hardware.subscribe(function()
            error("subscriber error")
        end)

        -- Second subscriber should still be called
        hardware.subscribe(function()
            good_called = true
        end)

        hardware.inject_report(make_report(0x00, 0x00))
        hardware.poll()

        assert.is_true(good_called)
    end)

    it("should allow unsubscribe to stop receiving reports", function()
        local received = 0
        local sub_id = hardware.subscribe(function()
            received = received + 1
        end)

        hardware.inject_report(make_report(0x00, 0x00))
        hardware.poll()
        assert.equals(1, received)

        -- Unsubscribe
        hardware.unsubscribe(sub_id)

        hardware.inject_report(make_report(0x00, 0x00))
        hardware.poll()
        assert.equals(1, received) -- Should not increment
    end)
end)
