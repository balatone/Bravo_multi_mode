-- tests/mocks/imgui.lua
-- Minimal ImGui mock for testing ui.lua in CLI environment.
-- Only stubs the specific methods actually called by these modules.
--
-- Full UI integration testing requires FlyWithLua runtime; this mock covers
-- pure computation paths (text wrapping, LRU cache eviction) and rendering
-- method stubs to prevent nil errors during test execution.
--
-- Methods covered (identified via source code review):
--   Dummy, CalcTextSize, SetWindowFontScale, DrawList_AddCircle,
--   DrawList_AddCircleFilled, DrawList_AddRectFilled, PushStyleColor,
--   PopStyleColor, TextColor, TextColored, TextUnformatted, Button,
--   Checkbox, SameLine, Spacing, Separator, NewLine, PushTextWrapPos,
--   PopTextWrapPos, GetCursorScreenPos, GetCursorPosX, GetCursorPosY,
--   SetCursorScreenPos, SetCursorPosX, SetCursorPosY

local imgui = {}

-- Constant table for style colors
imgui.constant = {
    Col = {
        WindowBg = 1,
        Text = 2,
    },
}

-- Cursor position state for tracking cursor movements
local cursor_x = 0
local cursor_y = 0

-- Font scale state for CalcTextSize
local current_font_scale = 1.0

--- Dummy(width, height) - Reserve space without drawing
function imgui.Dummy(w, h)
    -- No-op for testing
end

--- CalcTextSize(text) - Returns {width, height} for text measurement
-- Used by wrap_text_for_width() for text layout calculations
-- Respects current font scale for realistic binary search behavior
function imgui.CalcTextSize(text)
    if type(text) ~= "string" then
        return 0, 0
    end
    -- Approximate: 7px per character width, 15px height, scaled by font scale
    local w = #text * 7 * current_font_scale
    local h = 15 * current_font_scale
    return w, h
end

--- SetWindowFontScale(scale) - Set font scaling
function imgui.SetWindowFontScale(scale)
    current_font_scale = scale or 1.0
end

--- DrawList_AddCircle(x, y, radius, color, segments, thickness)
function imgui.DrawList_AddCircle(x, y, r, color, segments, thickness)
    -- No-op for testing
end

--- DrawList_AddCircleFilled(x, y, radius, color, segments)
function imgui.DrawList_AddCircleFilled(x, y, r, color, segments)
    -- No-op for testing
end

--- DrawList_AddRectFilled(x1, y1, x2, y2, color, rounding)
function imgui.DrawList_AddRectFilled(x1, y1, x2, y2, color, rounding)
    -- No-op for testing
end

--- PushStyleColor(idx, color) - Push a style color override
function imgui.PushStyleColor(idx, color)
    -- No-op for testing
end

--- PopStyleColor(count) - Pop style color overrides
function imgui.PopStyleColor(count)
    -- No-op for testing
end

--- TextColor(r, g, b, a) - Set text color
function imgui.TextColor(r, g, b, a)
    -- No-op for testing
end

--- TextColored(r, g, b, a, text) - Colored text
function imgui.TextColored(r, g, b, a, text)
    -- No-op for testing
end

--- TextUnformatted(text) - Render text without formatting
function imgui.TextUnformatted(text)
    -- No-op for testing
end

--- Button(label, width, height) - Render button, returns clicked state
function imgui.Button(label, w, h)
    return false
end

--- Checkbox(label, value) - Render checkbox
function imgui.Checkbox(label, value)
    return false, value
end

--- SameLine(offset_x, spacing) - Continue on same line
function imgui.SameLine(offset_x, spacing)
    -- No-op for testing
end

--- Spacing() - Add vertical spacing
function imgui.Spacing()
    -- No-op for testing
end

--- Separator() - Draw horizontal separator
function imgui.Separator()
    -- No-op for testing
end

--- NewLine() - Start a new line
function imgui.NewLine()
    -- No-op for testing
end

--- PushTextWrapPos(wrap_pos_x) - Set text wrapping position
function imgui.PushTextWrapPos(wrap_pos_x)
    -- No-op for testing
end

--- PopTextWrapPos() - Restore previous text wrapping position
function imgui.PopTextWrapPos()
    -- No-op for testing
end

--- GetCursorScreenPos() - Get cursor position in screen space
function imgui.GetCursorScreenPos()
    return cursor_x, cursor_y
end

--- GetCursorPosX() - Get cursor X position
function imgui.GetCursorPosX()
    return cursor_x
end

--- GetCursorPosY() - Get cursor Y position
function imgui.GetCursorPosY()
    return cursor_y
end

--- SetCursorScreenPos(x, y) - Set cursor position in screen space
function imgui.SetCursorScreenPos(x, y)
    cursor_x = x or 0
    cursor_y = y or 0
end

--- SetCursorPosX(x) - Set cursor X position
function imgui.SetCursorPosX(x)
    cursor_x = x or 0
end

--- SetCursorPosY(y) - Set cursor Y position
function imgui.SetCursorPosY(y)
    cursor_y = y or 0
end

return imgui
