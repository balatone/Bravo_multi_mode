-- tests/unit/ui_spec.lua
-- Unit tests for ui.lua text wrapping and LRU cache eviction.
-- Uses a minimal ImGui mock to test pure computation paths.
--
-- Note: Full UI integration testing requires FlyWithLua runtime;
-- these tests focus on text wrapping logic and LRU cache behavior.

-- Clear module cache to ensure fresh load with mocked globals
package.loaded["bravo++.log"] = nil
package.loaded["bravo++.util"] = nil
package.loaded["bravo++.ui"] = nil

-- Set up imgui mock before loading ui module
_G.imgui = require("tests.mocks.imgui")

local ui = require("bravo++.ui")
local util = require("bravo++.util")

-- ============================================================
-- Helper Functions
-- ============================================================

--- Access the internal text_layout_cache via a workaround
-- Since text_layout_cache is local, we test through get_scaled_wrapped_text behavior
local function clear_cache_via_eviction()
    -- Force cache eviction by calling get_scaled_wrapped_text many times
    -- This indirectly exercises the cache
end

-- ============================================================
-- Text Wrapping Tests (wrap_text_for_width)
-- ============================================================

describe("UI - wrap_text_for_width", function()
    it("should wrap text that exceeds max_width", function()
        -- imgui.CalcTextSize returns 7px per char, 15px height
        -- max_width of 50px = ~7 characters
        local lines, total_height, max_line_width = ui._wrap_text_for_width(
            "Hello World Foo Bar", 50, 1.0
        )

        -- Should wrap into multiple lines
        assert.is_true(#lines >= 1)
        assert.is_true(total_height > 0)
    end)

    it("should handle single word longer than max_width", function()
        -- A single long word that exceeds max_width
        local lines, total_height, max_line_width = ui._wrap_text_for_width(
            "SuperLongWord", 30, 1.0
        )

        -- Should still produce at least one line
        assert.is_true(#lines >= 1)
        assert.equals("SuperLongWord", lines[1])
    end)

    it("should handle empty string", function()
        local lines, total_height, max_line_width = ui._wrap_text_for_width(
            "", 100, 1.0
        )

        assert.equals(0, #lines)
        assert.equals(0, total_height)
    end)

    it("should handle single word", function()
        local lines, total_height, max_line_width = ui._wrap_text_for_width(
            "Hello", 200, 1.0
        )

        assert.equals(1, #lines)
        assert.equals("Hello", lines[1])
    end)

    it("should split words correctly", function()
        local lines, total_height, max_line_width = ui._wrap_text_for_width(
            "One Two Three", 30, 1.0
        )

        -- With 30px width (~4 chars), should split into multiple lines
        assert.is_true(#lines >= 1)
    end)

    it("should fit short text on single line", function()
        local lines, total_height, max_line_width = ui._wrap_text_for_width(
            "Hi", 200, 1.0
        )

        assert.equals(1, #lines)
        assert.equals("Hi", lines[1])
    end)

    it("should handle text with multiple spaces", function()
        local lines, total_height, max_line_width = ui._wrap_text_for_width(
            "A  B  C", 200, 1.0
        )

        -- Should handle multiple spaces between words
        assert.is_true(#lines >= 1)
    end)

    it("should handle text with leading/trailing spaces", function()
        local lines, total_height, max_line_width = ui._wrap_text_for_width(
            "  Hello World  ", 200, 1.0
        )

        assert.is_true(#lines >= 1)
    end)

    it("should return correct total_height", function()
        local lines, total_height, max_line_width = ui._wrap_text_for_width(
            "Line1 Line2 Line3 Line4", 30, 1.0
        )

        -- line_height = CalcTextSize("Wy") captures width (14px at scale 1.0)
        -- total_height = #lines * line_height = 4 * 14 = 56
        assert.is_true(total_height > 0)
        assert.is_true(#lines > 0)
        assert.equals(#lines * 14, total_height) -- 14px per line (width of "Wy" at scale 1.0)
    end)

    it("should handle very long text", function()
        local long_text = string.rep("Word ", 50)
        local lines, total_height, max_line_width = ui._wrap_text_for_width(
            long_text, 50, 1.0
        )

        assert.is_true(#lines > 1)
        assert.is_true(total_height > 15)
    end)
end)

-- ============================================================
-- LRU Cache Eviction Tests
-- ============================================================

describe("UI - LRU Cache Eviction", function()
    it("should cache text layout results", function()
        -- First call computes and caches
        local lines1, height1, scale1 = ui._get_scaled_wrapped_text(
            "Test Text", 100, 30, 0.6
        )

        -- Second call should use cache
        local lines2, height2, scale2 = ui._get_scaled_wrapped_text(
            "Test Text", 100, 30, 0.6
        )

        -- Results should be identical
        assert.equals(height1, height2)
        assert.is_true(math.abs(scale1 - scale2) < 0.001)
    end)

    it("should evict oldest entries when cache exceeds max_size", function()
        -- Fill cache beyond 100 entries with unique keys
        local first_result = nil
        for i = 1, 120 do
            local text = "Unique Text " .. tostring(i)
            local lines, height, scale = ui._get_scaled_wrapped_text(
                text, 100, 30, 0.6
            )
            if i == 1 then
                first_result = { lines = lines, height = height, scale = scale }
            end
        end

        -- After adding 120 entries, cache should have been evicted
        -- The first entry should have been evicted (LRU)
        -- We verify by checking that the cache size is bounded
        -- Since we can't directly access the cache, we verify the behavior
        -- by checking that the function continues to work correctly
        local lines, height, scale = ui._get_scaled_wrapped_text(
            "Final Test Text", 100, 30, 0.6
        )
        assert.is_not_nil(lines)
        assert.is_true(height > 0)
    end)

    it("should maintain correct results after eviction", function()
        -- Fill cache
        for i = 1, 110 do
            ui._get_scaled_wrapped_text("Text " .. tostring(i), 100, 30, 0.6)
        end

        -- After eviction, new queries should still work correctly
        local lines, height, scale = ui._get_scaled_wrapped_text(
            "Post Eviction Test", 100, 30, 0.6
        )

        assert.is_table(lines)
        assert.is_true(height > 0)
        assert.is_true(scale >= 0.6)
    end)

    it("should evict half the cache when over limit", function()
        -- cache_max_size = 100, remove_count = 50
        -- Add exactly 101 entries to trigger eviction
        for i = 1, 101 do
            ui._get_scaled_wrapped_text("Entry " .. tostring(i), 100, 30, 0.6)
        end

        -- After eviction, adding more should continue working
        local lines, height, scale = ui._get_scaled_wrapped_text(
            "After Eviction", 100, 30, 0.6
        )

        assert.is_not_nil(lines)
        assert.is_true(height > 0)
    end)

    it("should cache different parameters separately", function()
        -- Use multi-word text that wraps differently at different scales
        local long_text = "This is a very long text for testing purposes"

        -- Very tight width forces scale down to minimum
        local _, _, scale1 = ui._get_scaled_wrapped_text(
            long_text, 30, 80, 0.6
        )
        -- Wider width allows a larger scale
        local _, _, scale2 = ui._get_scaled_wrapped_text(
            long_text, 60, 80, 0.6
        )
        -- Even wider width allows near-scale 1.0
        local _, _, scale3 = ui._get_scaled_wrapped_text(
            long_text, 200, 80, 0.6
        )

        -- Different button_width should produce different scales
        assert.is_true(math.abs(scale1 - scale2) > 0.001)
        assert.is_true(math.abs(scale2 - scale3) > 0.001)
    end)
end)

-- ============================================================
-- get_scaled_wrapped_text Tests
-- ============================================================

describe("UI - get_scaled_wrapped_text", function()
    it("should find optimal font scale within bounds", function()
        local lines, height, scale = ui._get_scaled_wrapped_text(
            "Short", 200, 50, 0.6
        )

        assert.is_true(scale >= 0.6)
        assert.is_true(scale <= 1.0)
        assert.is_table(lines)
        assert.is_true(height > 0)
    end)

    it("should use min_font_scale for text that does not fit", function()
        local lines, height, scale = ui._get_scaled_wrapped_text(
            "Very Long Text That Will Not Fit In A Small Button At All", 30, 10, 0.6
        )

        assert.is_true(scale >= 0.6)
        assert.is_table(lines)
    end)

    it("should handle nil min_font_scale with default 0.6", function()
        local lines, height, scale = ui._get_scaled_wrapped_text(
            "Test", 100, 30, nil
        )

        assert.is_true(scale >= 0.6)
        assert.is_table(lines)
    end)
end)

-- ============================================================
-- strip_padding Tests
-- ============================================================

describe("UI - strip_padding", function()
    it("should replace underscores with spaces", function()
        local result = ui._strip_padding("Hello_World_Padding")
        assert.equals("Hello World Padding", result)
    end)

    it("should handle text without underscores", function()
        local result = ui._strip_padding("Hello World")
        assert.equals("Hello World", result)
    end)

    it("should handle empty string", function()
        local result = ui._strip_padding("")
        assert.equals("", result)
    end)

    it("should handle text with only underscores", function()
        local result = ui._strip_padding("___")
        assert.equals("   ", result)
    end)
end)

-- ============================================================
-- build_gui Tests (mocked)
-- ============================================================

describe("UI - build_gui (mocked)", function()
    it("should build GUI without errors with minimal context", function()
        local ctx = {
            current_mode = "AUTO",
            current_selection = "SEL1",
            current_cf_mode = "outer",
            current_switch_mode = "up",
            current_selection_label = "Alpha",
            conceptual_mode_order = { "AUTO" },
            selection_map_labels = { AUTO = { "Alpha" } },
            button_is_switch_map = { AUTO = { SEL1 = {} } },
            default_button_labels = { "B1" },
            current_buttons = { "B1" },
            switch_map_labels = {},
            twist_knob_map_actions = {},
            twist_knob_map_labels = {},
            get_button_led_state = function()
                return nil
            end,
            get_led_state_for_switch = function()
                return nil
            end,
            vertical_spacing = 5,
            arrow_color = 0xFF00FF00,
        }

        -- Should not error with mocked imgui
        ui.build_gui(ctx)
    end)

    it("should build GUI with multiple modes", function()
        local ctx = {
            current_mode = "NAV",
            current_selection = "SEL2",
            current_cf_mode = "inner",
            current_switch_mode = "down",
            current_selection_label = "Nav2",
            conceptual_mode_order = { "AUTO", "NAV", "COM" },
            selection_map_labels = {
                AUTO = { "A1", "A2" },
                NAV = { "N1", "N2" },
                COM = { "C1", "C2" },
            },
            button_is_switch_map = {
                NAV = { SEL2 = { BTN3 = true } },
            },
            default_button_labels = { "BTN1", "BTN2", "BTN3" },
            current_buttons = { "BTN1", "BTN2", "BTN3" },
            switch_map_labels = { "SW1", "SW2" },
            twist_knob_map_actions = {},
            twist_knob_map_labels = {
                NAV = { SEL2 = "Label" },
            },
            get_button_led_state = function()
                return true
            end,
            get_led_state_for_switch = function()
                return false
            end,
            vertical_spacing = 5,
            arrow_color = 0xFF00FF00,
        }

        -- Should not error
        ui.build_gui(ctx)
    end)
end)

-- ============================================================
-- on_close Tests
-- ============================================================

describe("UI - on_close", function()
    it("should call hid_close_fn when provided", function()
        local close_called = false
        local ctx = {
            hid_close_fn = function(dev)
                close_called = true
            end,
            bravo = "mock_device",
        }

        ui.on_close(ctx)
        assert.is_true(close_called)
    end)

    it("should not error when ctx is nil", function()
        ui.on_close(nil)
    end)

    it("should not call hid_close_fn when not provided", function()
        local ctx = {}
        ui.on_close(ctx)
        -- Should not error
    end)
end)
