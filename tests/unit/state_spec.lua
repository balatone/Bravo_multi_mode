-- tests/unit/state_spec.lua
-- Busted test suite for FlyWithLua/Modules/bravo++/state.lua
-- Tests state management, pub/sub, snapshot, and reset functionality.

local state = require("bravo++.state")

-- Helper: reset state between tests
local function reset_state()
    state.reset()
end

-- ============================================================
-- Selector getter/setter
-- ============================================================
describe("State - Selector", function()
    before_each(reset_state)

    it("should return nil for selector initially", function()
        assert.is_nil(state.get_selector())
    end)

    it("should set and get selector value", function()
        state.set_selector("position_1")
        assert.equals("position_1", state.get_selector())
    end)

    it("should not trigger subscriber when value unchanged", function()
        state.set_selector("position_1")
        local called = false
        state.subscribe_state("selector", function() called = true end)
        state.set_selector("position_1") -- same value
        assert.is_false(called)
    end)

    it("should update selector value", function()
        state.set_selector("position_1")
        state.set_selector("position_2")
        assert.equals("position_2", state.get_selector())
    end)
end)

-- ============================================================
-- Rotary getter/setter
-- ============================================================
describe("State - Rotary", function()
    before_each(reset_state)

    it("should return 0 for rotary initially", function()
        assert.equals(0, state.get_rotary())
    end)

    it("should set and get rotary value", function()
        state.set_rotary(42)
        assert.equals(42, state.get_rotary())
    end)

    it("should update rotary value", function()
        state.set_rotary(10)
        state.set_rotary(20)
        assert.equals(20, state.get_rotary())
    end)
end)

-- ============================================================
-- Trim getter/setter
-- ============================================================
describe("State - Trim", function()
    before_each(reset_state)

    it("should return nil for trim initially", function()
        assert.is_nil(state.get_trim())
    end)

    it("should set and get trim value", function()
        state.set_trim("up")
        assert.equals("up", state.get_trim())
    end)

    it("should not trigger subscriber when value unchanged", function()
        state.set_trim("up")
        local called = false
        state.subscribe_state("trim", function() called = true end)
        state.set_trim("up") -- same value
        assert.is_false(called)
    end)

    it("should update trim value", function()
        state.set_trim("up")
        state.set_trim("down")
        assert.equals("down", state.get_trim())
    end)
end)

-- ============================================================
-- Pub/Sub Subscriber Pattern
-- ============================================================
describe("State - Pub/Sub", function()
    before_each(reset_state)

    it("should notify subscriber on selector change", function()
        local received = nil
        state.subscribe_state("selector", function(v) received = v end)
        state.set_selector("pos_1")
        assert.equals("pos_1", received)
    end)

    it("should notify subscriber on rotary change", function()
        local received = nil
        state.subscribe_state("rotary", function(v) received = v end)
        state.set_rotary(99)
        assert.equals(99, received)
    end)

    it("should notify subscriber on trim change", function()
        local received = nil
        state.subscribe_state("trim", function(v) received = v end)
        state.set_trim("down")
        assert.equals("down", received)
    end)

    it("should notify multiple subscribers", function()
        local calls = {}
        state.subscribe_state("selector", function(v) table.insert(calls, "sub1_" .. tostring(v)) end)
        state.subscribe_state("selector", function(v) table.insert(calls, "sub2_" .. tostring(v)) end)
        state.set_selector("pos_1")
        assert.equals(2, #calls)
        assert.equals("sub1_pos_1", calls[1])
        assert.equals("sub2_pos_1", calls[2])
    end)

    it("should isolate subscriber errors via pcall", function()
        local good_called = false
        state.subscribe_state("selector", function() error("bad subscriber") end)
        state.subscribe_state("selector", function() good_called = true end)
        -- Should not crash
        state.set_selector("pos_1")
        assert.is_true(good_called)
    end)

    it("should not notify subscribers for unchanged selector", function()
        state.set_selector("pos_1")
        local called = false
        state.subscribe_state("selector", function() called = true end)
        state.set_selector("pos_1") -- same value, no notification
        assert.is_false(called)
    end)

    it("should not notify subscribers for unchanged trim", function()
        state.set_trim("up")
        local called = false
        state.subscribe_state("trim", function() called = true end)
        state.set_trim("up") -- same value, no notification
        assert.is_false(called)
    end)

    it("should always notify subscribers for rotary changes", function()
        state.set_rotary(10)
        local call_count = 0
        state.subscribe_state("rotary", function() call_count = call_count + 1 end)
        state.set_rotary(10) -- same value, but rotary always notifies
        assert.equals(1, call_count)
    end)
end)

-- ============================================================
-- Snapshot Immutability
-- ============================================================
describe("State - Snapshot", function()
    before_each(reset_state)

    it("should return a table with selector, rotary, and trim", function()
        state.set_selector("pos_1")
        state.set_rotary(5)
        state.set_trim("up")
        local snap = state.snapshot()
        assert.equals("pos_1", snap.selector)
        assert.equals(5, snap.rotary)
        assert.equals("up", snap.trim)
    end)

    it("should be independent of subsequent state mutations", function()
        state.set_selector("pos_1")
        state.set_rotary(5)
        state.set_trim("up")
        local snap = state.snapshot()

        -- Mutate state after snapshot
        state.set_selector("pos_2")
        state.set_rotary(10)
        state.set_trim("down")

        -- Snapshot should be unchanged
        assert.equals("pos_1", snap.selector)
        assert.equals(5, snap.rotary)
        assert.equals("up", snap.trim)
    end)

    it("should return nil values for unset fields", function()
        local snap = state.snapshot()
        assert.is_nil(snap.selector)
        assert.equals(0, snap.rotary)
        assert.is_nil(snap.trim)
    end)

    it("should not be affected by modifying snapshot", function()
        state.set_selector("pos_1")
        local snap = state.snapshot()
        snap.selector = "modified"
        assert.equals("pos_1", state.get_selector()) -- original unchanged
    end)
end)

-- ============================================================
-- Reset
-- ============================================================
describe("State - Reset", function()
    before_each(reset_state)

    it("should reset selector to nil", function()
        state.set_selector("pos_1")
        state.reset()
        assert.is_nil(state.get_selector())
    end)

    it("should reset rotary to 0", function()
        state.set_rotary(99)
        state.reset()
        assert.equals(0, state.get_rotary())
    end)

    it("should reset trim to nil", function()
        state.set_trim("up")
        state.reset()
        assert.is_nil(state.get_trim())
    end)

    it("should clear subscriber list", function()
        local called = false
        state.subscribe_state("selector", function() called = true end)
        state.reset()
        state.set_selector("pos_1")
        assert.is_false(called)
    end)

    it("should reset all values at once", function()
        state.set_selector("pos_1")
        state.set_rotary(42)
        state.set_trim("down")
        state.reset()
        assert.is_nil(state.get_selector())
        assert.equals(0, state.get_rotary())
        assert.is_nil(state.get_trim())
    end)
end)
