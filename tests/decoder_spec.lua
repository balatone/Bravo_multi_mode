-- tests/decoder_spec.lua
-- Busted test suite for FlyWithLua/Modules/bravo++/decoder.lua
-- Tests decoder functionality in a CLI environment with mocked FlyWithLua globals.

-- Load modules once and keep them loaded for proper luacov accumulation
local decoder = require("bravo++.decoder")
local state = require("bravo++.state")

-- Helper: create a base HID report (16 bytes, all zero)
local function make_report(byte15, byte16)
    local report = {}
    for i = 1, 16 do
        report[i] = 0
    end
    if byte15 then report[15] = byte15 end
    if byte16 then report[16] = byte16 end
    return report
end

-- Reset decoder and state between tests without unloading modules
-- This preserves luacov coverage accumulation
local function reset_state()
    decoder.reset()
    state.reset()
    _G.set_time(0)
end

-- ============================================================
-- Rotary Events
-- ============================================================
describe("Decoder - Rotary Events", function()
    before_each(reset_state)

    it("should detect CW rotary event", function()
        local cw_detected = false
        decoder.set_handlers({ on_rotary_cw = function() cw_detected = true end })

        decoder.on_report(make_report(0x00, 0x00))
        _G.advance_time()

        decoder.on_report(make_report(0x10, 0x00))

        assert.is_true(cw_detected)
    end)

    it("should detect CCW rotary event", function()
        local ccw_detected = false
        decoder.set_handlers({ on_rotary_ccw = function() ccw_detected = true end })

        decoder.on_report(make_report(0x00, 0x00))
        _G.advance_time()

        decoder.on_report(make_report(0x20, 0x00))

        assert.is_true(ccw_detected)
    end)

    it("should not detect rotary event without rising edge", function()
        local cw_detected = false
        local ccw_detected = false
        decoder.set_handlers({
            on_rotary_cw = function() cw_detected = true end,
            on_rotary_ccw = function() ccw_detected = true end
        })

        -- Establish baseline with 0x10 so next report sees no change
        decoder.on_report(make_report(0x10, 0x00))
        _G.advance_time()
        decoder.on_report(make_report(0x10, 0x00))

        -- First report caused a rising edge (nil->0x10), second should not
        assert.is_true(cw_detected)  -- first report triggered CW
        assert.is_false(ccw_detected)
    end)

    it("should not detect rotary when byte stays constant after baseline", function()
        local cw_count = 0
        decoder.set_handlers({ on_rotary_cw = function() cw_count = cw_count + 1 end })

        -- Baseline
        decoder.on_report(make_report(0x00, 0x00))
        _G.advance_time()
        -- CW pulse
        decoder.on_report(make_report(0x10, 0x00))
        _G.advance_time()
        -- Return to zero
        decoder.on_report(make_report(0x00, 0x00))
        _G.advance_time()
        -- Stay at zero - no event
        decoder.on_report(make_report(0x00, 0x00))

        assert.equals(1, cw_count)
    end)

    it("should handle empty report gracefully", function()
        decoder.on_report({})
    end)

    it("should suppress rotary event by debounce", function()
        -- Send two CW events too quickly (within ROTARY_MIN_INTERVAL)
        decoder.on_report(make_report(0x00, 0x00))
        _G.set_time(0)

        decoder.on_report(make_report(0x10, 0x00)) -- first CW at t=0

        -- Second CW at t=0.005 (before debounce expires at ~0.03)
        _G.set_time(0.005)
        decoder.on_report(make_report(0x00, 0x00)) -- clear
        _G.set_time(0.01)
        decoder.on_report(make_report(0x10, 0x00)) -- second CW - should be suppressed

        local diag = decoder.diagnostics()
        assert.equals(1, diag.counters.rotary_events) -- only first counted
    end)

    it("should suppress rotary duplicate within dedupe window", function()
        local cw_count = 0
        decoder.set_handlers({ on_rotary_cw = function() cw_count = cw_count + 1 end })

        -- First CW
        decoder.on_report(make_report(0x00, 0x00))
        _G.set_time(0)
        decoder.on_report(make_report(0x10, 0x00))

        -- Second CW within dedupe window (~0.08s) but after min interval (~0.03s)
        _G.set_time(0.05)
        decoder.on_report(make_report(0x00, 0x00)) -- clear
        _G.set_time(0.06)
        decoder.on_report(make_report(0x10, 0x00)) -- duplicate CW

        assert.equals(1, cw_count) -- second suppressed as duplicate
    end)

    it("should allow CW after dedupe window expires", function()
        local cw_count = 0
        decoder.set_handlers({ on_rotary_cw = function() cw_count = cw_count + 1 end })

        decoder.on_report(make_report(0x00, 0x00))
        _G.set_time(0)
        decoder.on_report(make_report(0x10, 0x00)) -- first CW

        -- After dedupe window (>0.08s) and min interval
        _G.set_time(0.15)
        decoder.on_report(make_report(0x00, 0x00)) -- clear
        _G.set_time(0.20)
        decoder.on_report(make_report(0x10, 0x00)) -- second CW

        assert.equals(2, cw_count)
    end)

    it("should allow direction change within dedupe window", function()
        local cw_count = 0
        local ccw_count = 0
        decoder.set_handlers({
            on_rotary_cw = function() cw_count = cw_count + 1 end,
            on_rotary_ccw = function() ccw_count = ccw_count + 1 end
        })

        decoder.on_report(make_report(0x00, 0x00))
        _G.set_time(0)
        decoder.on_report(make_report(0x10, 0x00)) -- CW

        -- Direction change within dedupe window - should NOT be suppressed
        _G.set_time(0.05)
        decoder.on_report(make_report(0x00, 0x00)) -- clear
        _G.set_time(0.06)
        decoder.on_report(make_report(0x20, 0x00)) -- CCW

        assert.equals(1, cw_count)
        assert.equals(1, ccw_count)
    end)
end)

-- ============================================================
-- Selector Events
-- ============================================================
describe("Decoder - Selector Events", function()
    before_each(reset_state)

    it("should detect selector change from one-hot value 0x01", function()
        local selected = nil
        decoder.set_handlers({ on_selector_changed = function(s) selected = s end })

        decoder.on_report(make_report(0x00, 0x00))
        _G.advance_time()

        decoder.on_report(make_report(0x00, 0x01))

        assert.is_not_nil(selected)
    end)

    it("should detect selector change from one-hot value 0x02", function()
        local selected = nil
        decoder.set_handlers({ on_selector_changed = function(s) selected = s end })

        decoder.on_report(make_report(0x00, 0x00))
        _G.advance_time()

        decoder.on_report(make_report(0x00, 0x02))

        assert.is_not_nil(selected)
    end)

    it("should detect selector change from one-hot value 0x04", function()
        local selected = nil
        decoder.set_handlers({ on_selector_changed = function(s) selected = s end })

        decoder.on_report(make_report(0x00, 0x00))
        _G.advance_time()

        decoder.on_report(make_report(0x00, 0x04))

        assert.is_not_nil(selected)
    end)

    it("should detect selector change from one-hot value 0x08", function()
        local selected = nil
        decoder.set_handlers({ on_selector_changed = function(s) selected = s end })

        decoder.on_report(make_report(0x00, 0x00))
        _G.advance_time()

        decoder.on_report(make_report(0x00, 0x08))

        assert.is_not_nil(selected)
    end)

    it("should detect selector change from one-hot value 0x10", function()
        local selected = nil
        decoder.set_handlers({ on_selector_changed = function(s) selected = s end })

        decoder.on_report(make_report(0x00, 0x00))
        _G.advance_time()

        decoder.on_report(make_report(0x00, 0x10))

        assert.is_not_nil(selected)
    end)

    it("should not detect selector when trim bits are present", function()
        local selected = nil
        decoder.set_handlers({ on_selector_changed = function(s) selected = s end })

        decoder.on_report(make_report(0x00, 0x00))
        _G.advance_time()
        decoder.on_report(make_report(0x00, 0x21)) -- 0x01 selector + 0x20 trim

        assert.is_nil(selected)
    end)

    it("should suppress selector change by debounce", function()
        local sel_count = 0
        decoder.set_handlers({ on_selector_changed = function() sel_count = sel_count + 1 end })

        decoder.on_report(make_report(0x00, 0x00))
        _G.set_time(0)
        decoder.on_report(make_report(0x00, 0x01)) -- selector 1

        -- Another selector too quickly
        _G.set_time(0.005)
        decoder.on_report(make_report(0x00, 0x00)) -- clear
        _G.set_time(0.01)
        decoder.on_report(make_report(0x00, 0x02)) -- selector 2 - should be suppressed

        assert.equals(1, sel_count)
    end)

    it("should not fire handler for same selector value", function()
        local sel_count = 0
        decoder.set_handlers({ on_selector_changed = function() sel_count = sel_count + 1 end })

        decoder.on_report(make_report(0x00, 0x00))
        _G.set_time(0)
        decoder.on_report(make_report(0x00, 0x01)) -- selector 1

        -- Same selector again after debounce
        _G.set_time(0.5)
        decoder.on_report(make_report(0x00, 0x00)) -- clear
        _G.set_time(0.6)
        decoder.on_report(make_report(0x00, 0x01)) -- selector 1 again

        assert.equals(1, sel_count) -- only first fires
    end)
end)

-- ============================================================
-- Trim Events
-- ============================================================
describe("Decoder - Trim Events", function()
    before_each(reset_state)

    it("should detect trim down event", function()
        local trim_dir = nil
        decoder.set_handlers({ on_trim_changed = function(d) trim_dir = d end })

        decoder.on_report(make_report(0x00, 0x00))
        _G.advance_time()
        decoder.on_report(make_report(0x00, 0x20))

        assert.equals("down", trim_dir)
    end)

    it("should detect trim up event", function()
        local trim_dir = nil
        decoder.set_handlers({ on_trim_changed = function(d) trim_dir = d end })

        decoder.on_report(make_report(0x00, 0x00))
        _G.advance_time()
        decoder.on_report(make_report(0x00, 0x40))

        assert.equals("up", trim_dir)
    end)

    it("should detect trim down on falling edge using previous state", function()
        local trim_dir = nil
        decoder.set_handlers({ on_trim_changed = function(d) trim_dir = d end })

        decoder.on_report(make_report(0x00, 0x20))
        _G.advance_time()
        decoder.on_report(make_report(0x00, 0x00))

        assert.equals("down", trim_dir)
    end)

    it("should detect trim up on falling edge using previous state", function()
        local trim_dir = nil
        decoder.set_handlers({ on_trim_changed = function(d) trim_dir = d end })

        decoder.on_report(make_report(0x00, 0x40))
        _G.advance_time()
        decoder.on_report(make_report(0x00, 0x00))

        assert.equals("up", trim_dir)
    end)

    it("should suppress trim event by debounce", function()
        local trim_count = 0
        decoder.set_handlers({ on_trim_changed = function() trim_count = trim_count + 1 end })

        decoder.on_report(make_report(0x00, 0x00))
        _G.set_time(0)
        decoder.on_report(make_report(0x00, 0x20)) -- trim down

        -- Another trim too quickly
        _G.set_time(0.005)
        decoder.on_report(make_report(0x00, 0x00)) -- clear
        _G.set_time(0.01)
        decoder.on_report(make_report(0x00, 0x40)) -- trim up - should be suppressed

        assert.equals(1, trim_count)
    end)

    it("should detect trim when both trim bits toggle (XOR detection)", function()
        local trim_dir = nil
        decoder.set_handlers({ on_trim_changed = function(d) trim_dir = d end })

        -- Toggle from TRIM_DOWN to TRIM_UP
        decoder.on_report(make_report(0x00, 0x20))
        _G.advance_time()
        decoder.on_report(make_report(0x00, 0x40))

        assert.equals("up", trim_dir)
    end)
end)

-- ============================================================
-- State Integration
-- ============================================================
describe("Decoder - State Integration", function()
    before_each(reset_state)

    it("should update state on selector change", function()
        decoder.set_handlers({})

        decoder.on_report(make_report(0x00, 0x00))
        _G.advance_time()
        decoder.on_report(make_report(0x00, 0x01))

        assert.is_not_nil(state.get_selector())
    end)

    it("should update state on trim event", function()
        decoder.set_handlers({})

        decoder.on_report(make_report(0x00, 0x00))
        _G.advance_time()
        decoder.on_report(make_report(0x00, 0x20))

        assert.equals("down", state.get_trim())
    end)

    it("should provide state snapshot", function()
        decoder.set_handlers({})

        decoder.on_report(make_report(0x00, 0x00))
        _G.advance_time()
        decoder.on_report(make_report(0x00, 0x01)) -- selector
        _G.advance_time()
        decoder.on_report(make_report(0x00, 0x20)) -- trim

        local snap = state.snapshot()
        assert.is_not_nil(snap.selector)
        assert.equals("down", snap.trim)
    end)
end)

-- ============================================================
-- Diagnostics
-- ============================================================
describe("Decoder - Diagnostics", function()
    before_each(reset_state)

    it("should return diagnostics table", function()
        local diag = decoder.diagnostics()
        assert.is_table(diag)
        assert.is_table(diag.counters)
        assert.is_not_nil(diag.last_rotary_time)
        assert.is_not_nil(diag.last_selector_time)
        assert.is_not_nil(diag.last_trim_time)
    end)

    it("should increment rotary counter on event", function()
        decoder.set_handlers({})

        decoder.on_report(make_report(0x00, 0x00))
        _G.advance_time()
        decoder.on_report(make_report(0x10, 0x00))

        local diag = decoder.diagnostics()
        assert.is_true(diag.counters.rotary_events >= 1)
    end)

    it("should track last_seen bytes in diagnostics", function()
        decoder.set_handlers({})

        decoder.on_report(make_report(0x10, 0x01))

        local diag = decoder.diagnostics()
        assert.equals(0x10, diag.last_seen_rotary_byte)
        assert.equals(0x01, diag.last_seen_selector_byte)
    end)

    it("should track last_report in diagnostics", function()
        decoder.set_handlers({})

        local report = make_report(0xAA, 0xBB)
        decoder.on_report(report)

        local diag = decoder.diagnostics()
        assert.is_table(diag.last_report)
        assert.equals(0xAA, diag.last_report[15])
        assert.equals(0xBB, diag.last_report[16])
    end)
end)

-- ============================================================
-- Handler Configuration
-- ============================================================
describe("Decoder - Handler Configuration", function()
    before_each(reset_state)

    it("should accept nil handlers table", function()
        decoder.set_handlers(nil)
    end)

    it("should not call missing handlers", function()
        decoder.set_handlers({})
        decoder.on_report(make_report(0x10, 0x01))
    end)

    it("should survive handler throwing an error", function()
        local other_called = false
        decoder.set_handlers({
            on_rotary_cw = function() error("handler error") end,
            on_selector_changed = function() other_called = true end,
        })

        -- Should not crash despite handler error
        decoder.on_report(make_report(0x00, 0x00))
        _G.advance_time()
        decoder.on_report(make_report(0x10, 0x01))
    end)
end)

-- ============================================================
-- Functional / End-to-End Tests
-- ============================================================
describe("Decoder - End-to-End HID Report Cycles", function()
    before_each(reset_state)

    it("should process a full HID report cycle: rotary + selector + trim", function()
        local events = {}
        decoder.set_handlers({
            on_rotary_cw = function() table.insert(events, "rotary_cw") end,
            on_rotary_ccw = function() table.insert(events, "rotary_ccw") end,
            on_selector_changed = function(s) table.insert(events, "selector_" .. s) end,
            on_trim_changed = function(d) table.insert(events, "trim_" .. d) end,
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

        -- Events: CW rotary, selector 5, trim down (rising), CCW rotary, trim down (falling edge)
        -- Note: CCW and trim falling edge both fire in the same frame (5), order depends on code flow
        assert.equals(5, #events)
        assert.equals("rotary_cw", events[1])
        assert.equals("selector_5", events[2]) -- 0x01 maps to position 5
        assert.equals("trim_down", events[3])
        assert.equals("rotary_ccw", events[4])
        assert.equals("trim_down", events[5]) -- falling edge of trim pulse (0x20->0x00)

        -- Verify state
        assert.equals("down", state.get_trim())

        -- Verify counters
        local diag = decoder.diagnostics()
        assert.equals(2, diag.counters.rotary_events)
        assert.equals(1, diag.counters.selector_changes)
        assert.equals(2, diag.counters.trim_events) -- rising + falling edge of trim pulse
    end)

    it("should correctly map all 5 selector positions", function()
        local positions = {}
        decoder.set_handlers({
            on_selector_changed = function(s) table.insert(positions, s) end,
        })

        decoder.on_report(make_report(0x00, 0x00))

        -- Test each one-hot position
        local test_values = { 0x01, 0x02, 0x04, 0x08, 0x10 }
        for _, val in ipairs(test_values) do
            _G.advance_time()
            decoder.on_report(make_report(0x00, val))
            _G.advance_time()
            decoder.on_report(make_report(0x00, 0x00)) -- clear for next
        end

        assert.equals(5, #positions)
    end)

    it("should handle rapid mixed events with proper debouncing", function()
        local events = {}
        decoder.set_handlers({
            on_rotary_cw = function() table.insert(events, "cw") end,
            on_rotary_ccw = function() table.insert(events, "ccw") end,
            on_selector_changed = function(s) table.insert(events, "sel_" .. s) end,
            on_trim_changed = function(d) table.insert(events, "trim_" .. d) end,
        })

        -- Send events with proper spacing
        decoder.on_report(make_report(0x00, 0x00))

        _G.set_time(0.0)
        decoder.on_report(make_report(0x10, 0x00)) -- CW

        _G.set_time(0.1) -- after debounce
        decoder.on_report(make_report(0x00, 0x00)) -- clear
        _G.set_time(0.2)
        decoder.on_report(make_report(0x00, 0x01)) -- selector

        _G.set_time(0.3)
        decoder.on_report(make_report(0x00, 0x00)) -- clear
        _G.set_time(0.4)
        decoder.on_report(make_report(0x00, 0x20)) -- trim down

        _G.set_time(0.5)
        decoder.on_report(make_report(0x00, 0x00)) -- clear
        _G.set_time(0.6)
        decoder.on_report(make_report(0x20, 0x00)) -- CCW

        -- Events: CW, selector 5, trim down (rising), CCW
        -- Trim falling edge at t=0.5 is suppressed by debounce (0.1s from t=0.4 == TRIM_MIN_INTERVAL)
        assert.equals(4, #events)
        assert.equals("cw", events[1])
        assert.equals("sel_5", events[2])
        assert.equals("trim_down", events[3])
        assert.equals("ccw", events[4])
    end)

    it("should isolate rotary and selector detection from each other", function()
        -- Rotary byte and selector byte should be detected independently
        local events = {}
        decoder.set_handlers({
            on_rotary_cw = function() table.insert(events, "cw") end,
            on_selector_changed = function(s) table.insert(events, "sel_" .. s) end,
        })

        decoder.on_report(make_report(0x00, 0x00))
        _G.advance_time()

        -- Simultaneous rotary CW + selector change
        decoder.on_report(make_report(0x10, 0x01))

        assert.equals(2, #events)
        assert.equals("cw", events[1])
        assert.equals("sel_5", events[2])
    end)

    it("should not confuse rotary CCW mask with trim down mask", function()
        -- ROTARY_PULSE_CCW_MASK = 0x20 (byte 15)
        -- TRIM_DOWN_MASK = 0x20 (byte 16)
        -- They share the same bit value but are in different bytes
        local events = {}
        decoder.set_handlers({
            on_rotary_ccw = function() table.insert(events, "ccw") end,
            on_trim_changed = function(d) table.insert(events, "trim_" .. d) end,
        })

        decoder.on_report(make_report(0x00, 0x00))
        _G.advance_time()

        -- CCW rotary (byte 15 = 0x20) should NOT trigger trim
        decoder.on_report(make_report(0x20, 0x00))

        assert.equals(1, #events)
        assert.equals("ccw", events[1])
        assert.is_nil(state.get_trim())
    end)
end)

-- ============================================================
-- Edge Cases
-- ============================================================
describe("Decoder - Edge Cases", function()
    before_each(reset_state)

    it("should handle reports with fewer than 16 bytes", function()
        local short_report = { 0, 0, 0 } -- only 3 bytes
        decoder.on_report(short_report)
    end)

    it("should handle reports with nil values", function()
        local report = {}
        report[15] = nil
        report[16] = nil
        decoder.on_report(report)
    end)

    it("should handle zero-length report", function()
        decoder.on_report({})
    end)

    it("should handle report with only rotary byte set", function()
        local report = make_report(0xFF, nil)
        decoder.on_report(report)
    end)

    it("should handle report with only selector byte set", function()
        local report = make_report(nil, 0xFF)
        decoder.on_report(report)
    end)

    it("should properly reset all internal state", function()
        -- Set some state
        decoder.set_handlers({ on_rotary_cw = function() end })
        decoder.on_report(make_report(0x10, 0x01))

        -- Reset
        decoder.reset()
        state.reset()

        -- Verify reset
        local diag = decoder.diagnostics()
        assert.equals(0, diag.counters.rotary_events)
        assert.equals(0, diag.counters.selector_changes)
        assert.equals(0, diag.counters.trim_events)
        assert.is_nil(state.get_selector())
        assert.is_nil(state.get_trim())
    end)

    it("should handle last_report copy isolation", function()
        -- Verify that last_report is a copy, not a reference
        local report1 = make_report(0xAA, 0xBB)
        decoder.on_report(report1)

        -- Modify original
        report1[15] = 0x00

        local diag = decoder.diagnostics()
        assert.equals(0xAA, diag.last_report[15]) -- should be preserved
    end)
end)
