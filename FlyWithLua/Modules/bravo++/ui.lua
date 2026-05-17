-- bravo++.ui -- All ImGui rendering and layout logic for Bravo++
-- Consumes a context table supplied by the host script so this module
-- remains decoupled from HID, config parsing, or state management.
--
-- lint:imgui is provided by FlyWithLua as a global

local util = require("bravo++.util")

-- imgui is a FlyWithLua global, declared here to silence luacheck
local imgui = imgui --[[@as table]] -- luacheck: ignore (global from FlyWithLua)

-- ---------------------------------------------------------------------------
-- Constants / Layout
-- ---------------------------------------------------------------------------
local H_OFFSET = 10
local H_SPACING = 5
local Y_OFFSET = 10
local WIDGET_WIDTH = 60

-- Arrow color is now supplied via the context table (dispatch.lua manages intent colors)

-- ---------------------------------------------------------------------------
-- Pre-computed symbol metrics (computed once at module load)
-- ---------------------------------------------------------------------------
local symbol_metrics = {}

--- Pre-compute text metrics for common symbols to avoid runtime CalcTextSize calls.
--- Returns {w, h} for a given symbol and font scale.
local function get_symbol_metrics(symbol, scale)
	local cache_key = symbol .. "_" .. tostring(scale)
	if not symbol_metrics[cache_key] then
		imgui.SetWindowFontScale(scale)
		local w, h = imgui.CalcTextSize(symbol)
		imgui.SetWindowFontScale(1.0)
		symbol_metrics[cache_key] = { w = w, h = h }
	end
	return symbol_metrics[cache_key]
end

-- ---------------------------------------------------------------------------
-- Text Layout Cache with LRU eviction
-- ---------------------------------------------------------------------------
local text_layout_cache = {}
local cache_max_size = 100 -- Prevent unbounded growth

--- Evict oldest entries if cache exceeds max size.
local function evict_cache()
	if #text_layout_cache > cache_max_size then
		-- Remove half the oldest entries
		local remove_count = math.floor(cache_max_size / 2)
		for _ = 1, remove_count do
			table.remove(text_layout_cache, 1)
		end
	end
end

--- Wrap *text_str* into lines that fit within *max_width* at the given font scale.
--- Returns {lines}, total_height, max_line_width
local function wrap_text_for_width(text_str, max_width, current_font_scale)
	local lines = {}
	local current_line = ""
	local words = {}
	local max_line_width = 0

	for word in string.gmatch(text_str, "[^%s]+") do
		table.insert(words, word)
	end

	imgui.SetWindowFontScale(current_font_scale)
	local line_height = imgui.CalcTextSize("Wy")

	if #words == 0 then
		imgui.SetWindowFontScale(1.0)
		return {}, 0, 0
	end

	for _, word in ipairs(words) do
		local test_line = current_line
		if current_line ~= "" then
			test_line = test_line .. " "
		end
		test_line = test_line .. word

		local test_w, _ = imgui.CalcTextSize(test_line)

		if test_w <= max_width then
			current_line = test_line
			max_line_width = math.max(max_line_width, test_w)
		else
			if current_line ~= "" then
				table.insert(lines, current_line)
			end
			current_line = word
			max_line_width = math.max(max_line_width, imgui.CalcTextSize(word))
		end
	end
	if current_line ~= "" then
		table.insert(lines, current_line)
	end

	imgui.SetWindowFontScale(1.0)
	return lines, #lines * line_height, max_line_width
end

--- Binary-search for the largest font scale that fits *text_string* inside
--- (*button_width*, *button_height*).  Results are cached with LRU eviction.
local function get_scaled_wrapped_text(text_string, button_width, button_height, min_font_scale)
	min_font_scale = min_font_scale or 0.6
	local key = text_string .. tostring(button_width) .. tostring(button_height) .. tostring(min_font_scale)

	-- Check cache first
	for _, entry in ipairs(text_layout_cache) do
		if entry.key == key then
			return entry.wrapped_lines, entry.total_height, entry.final_scale
		end
	end

	local best_scale = min_font_scale
	local border_width_buffer = 6

	local low = min_font_scale
	local high = 1.0
	local precision = 0.001

	while (high - low) > precision do
		local mid = (low + high) / 2
		local _, required_height, widest_line_width = wrap_text_for_width(text_string, button_width, mid)

		if required_height <= button_height and widest_line_width + border_width_buffer <= button_width then
			best_scale = mid
			low = mid
		else
			high = mid
		end
	end

	local best_lines, best_height = wrap_text_for_width(text_string, button_width, best_scale)

	-- Add to cache with LRU eviction
	table.insert(text_layout_cache, {
		key = key,
		wrapped_lines = best_lines,
		total_height = best_height,
		final_scale = best_scale,
	})
	evict_cache()

	return best_lines, best_height, best_scale
end

--- Strip underscore characters used as invisible padding in button labels.
-- Underscores are measured during layout (so they affect font scaling and wrapping)
-- but removed before rendering, allowing paired buttons to share the same scale.
local function strip_padding(text)
	return text:gsub("_", " ")
end

--- Draw a simple centred text label inside a *width*×*height* box.
local function draw_label(text, width, height, text_color_int)
	local cx, cy = imgui.GetCursorScreenPos()

	imgui.Dummy(width, height)

	local display_text = strip_padding(text)
	local text_w, text_h = imgui.CalcTextSize(display_text)
	local text_draw_x = cx + (width - text_w) / 2
	local text_draw_y = cy + (height - text_h) / 2

	imgui.SetCursorScreenPos(text_draw_x, text_draw_y)
	imgui.PushStyleColor(imgui.constant.Col.Text, text_color_int)
	imgui.TextUnformatted(display_text)
	imgui.PopStyleColor()
end

--- Draw a button with wrapped text and optional switch indicator (^^ / vv).
local function draw_button(
	text,
	width,
	height,
	box_bg_color_int,
	text_color_int,
	is_switch_button,
	switch_mode,
	arrow_color_int
)
	local cx, cy = imgui.GetCursorScreenPos()
	imgui.Dummy(width, height)
	imgui.DrawList_AddRectFilled(cx, cy, cx + width, cy + height, box_bg_color_int, 0)

	local wrapped_lines, text_total_height, final_font_scale = get_scaled_wrapped_text(text, width, height, 0.6)

	-- Batch font scale changes: only set if different from current
	imgui.SetWindowFontScale(final_font_scale)

	local start_text_y = cy + (height - text_total_height) / 2

	local current_line_y = start_text_y
	for _, line in ipairs(wrapped_lines) do
		local display_line = strip_padding(line)
		local line_w, line_h = imgui.CalcTextSize(display_line)
		local line_draw_x = cx + (width - line_w) / 2

		imgui.SetCursorScreenPos(line_draw_x, current_line_y)
		imgui.PushStyleColor(imgui.constant.Col.Text, text_color_int)
		imgui.TextUnformatted(display_line)
		imgui.PopStyleColor()

		current_line_y = current_line_y + line_h
	end

	-- Switch indicator - use a fixed font scale independent of button text
	if is_switch_button then
		local ud_symbol = ""
		local symbol_offset_y = 0
		local padding = -2

		imgui.SetWindowFontScale(1.0)

		-- Get pre-computed symbol metrics at the arrow's own scale
		local sym_metrics = get_symbol_metrics("^^", 1.0)
		local symbol_w, symbol_h = sym_metrics.w, sym_metrics.h

		if switch_mode == "up" then
			ud_symbol = "^^"
			symbol_offset_y = -(height / 2 + symbol_h + padding)
		elseif switch_mode == "down" then
			ud_symbol = "vv"
			symbol_offset_y = (height / 2 + padding)
		end

		local symbol_draw_x = cx + (width - symbol_w) / 2
		local symbol_draw_y = cy + height / 2 + symbol_offset_y

		imgui.SetCursorScreenPos(symbol_draw_x, symbol_draw_y)
		imgui.PushStyleColor(imgui.constant.Col.Text, arrow_color_int or 0xFF00FF00)
		imgui.TextUnformatted(ud_symbol)
		imgui.PopStyleColor()
	end

	-- Reset font scale once after all text drawing
	imgui.SetWindowFontScale(1.0)
end

--- Draw the twist-knob graphic with highlighted inner/outer rings.
local function draw_knob(
	centerX,
	centerY,
	outerRad,
	innerRad,
	segments,
	thickness,
	current_mode,
	current_selection,
	current_cf_mode,
	current_cf_mode_upper,
	twist_knob_map_actions,
	twist_knob_map_labels
)
	local outer_outline_color = 0xFF222222
	local inner_outline_color = 0xFF222222
	local outer_color = 0xFF505050
	local inner_color = 0xFF505050
	local knob_text_color = 0xFFFFFFFF

	local highlight_color = 0x4400FF00
	local highlight_outline_color = 0xFF00FF00

	if
		util.is_table(twist_knob_map_actions[current_mode])
		and util.is_table(twist_knob_map_actions[current_mode][current_selection])
	then
		if util.is_table(twist_knob_map_actions[current_mode][current_selection]["INNER"]) then
			if current_cf_mode == "outer" then
				outer_color = highlight_color
				outer_outline_color = highlight_outline_color
			elseif current_cf_mode == "inner" then
				inner_color = highlight_color
				inner_outline_color = highlight_outline_color
			end
		elseif util.is_string(twist_knob_map_actions[current_mode][current_selection]["UP"]) then
			outer_color = highlight_color
			outer_outline_color = highlight_outline_color
			inner_color = highlight_color
			inner_outline_color = highlight_outline_color
		end
	end

	imgui.DrawList_AddCircle(centerX, centerY, outerRad, outer_outline_color, segments, thickness)
	imgui.DrawList_AddCircleFilled(centerX, centerY, outerRad, outer_color, segments)
	imgui.DrawList_AddCircle(centerX, centerY, innerRad, inner_outline_color, segments, thickness)
	imgui.DrawList_AddCircleFilled(centerX, centerY, innerRad, inner_color, segments)

	if util.is_table(twist_knob_map_labels[current_mode]) then
		local text_to_display = nil
		if util.is_table(twist_knob_map_labels[current_mode][current_selection]) then
			text_to_display = twist_knob_map_labels[current_mode][current_selection][current_cf_mode_upper]
		elseif util.is_string(twist_knob_map_labels[current_mode][current_selection]) then
			text_to_display = twist_knob_map_labels[current_mode][current_selection]
		end

		if text_to_display ~= nil then
			local knob_text_max_width = innerRad * 2
			local knob_text_max_height = innerRad * 2

			local wrapped_lines, text_total_height, final_font_scale =
				get_scaled_wrapped_text(text_to_display, knob_text_max_width, knob_text_max_height, 0.6)

			imgui.SetWindowFontScale(final_font_scale)

			local start_text_y = centerY - text_total_height / 2

			local current_line_y = start_text_y
			for _, line in ipairs(wrapped_lines) do
				local line_w, line_h = imgui.CalcTextSize(line)
				local line_draw_x = centerX - line_w / 2

				imgui.SetCursorPosX(line_draw_x)
				imgui.SetCursorPosY(current_line_y)

				draw_label(line, line_w, line_h, knob_text_color)

				current_line_y = current_line_y + line_h
			end

			imgui.SetWindowFontScale(1.0)
		end
	end
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------
local M = {}

--- Build the Bravo++ floating-window GUI.
---
--- *ctx* is a table supplied by the host script with the following keys:
---   current_mode, current_selection, current_cf_mode, current_switch_mode,
---   current_selection_label, conceptual_mode_order, selection_map_labels,
---   button_is_switch_map, default_button_labels, current_buttons,
---   switch_map_labels, twist_knob_map_actions, twist_knob_map_labels,
---   get_button_led_state, get_led_state_for_switch, vertical_spacing
function M.build_gui(ctx)
	imgui.PushStyleColor(imgui.constant.Col.WindowBg, 0xCC333333)

	local current_mode_conceptual_name = util.get_name_before_index(ctx.current_mode)

	-- ---- Mode labels row ----------------------------------------------------
	local h_offset_mode = H_OFFSET
	local h_spacing_mode = H_SPACING
	local y_offset_mode = Y_OFFSET
	local mode_width = WIDGET_WIDTH

	imgui.NewLine()
	imgui.SetWindowFontScale(1.2)

	for i, conceptual_name_to_draw in ipairs(ctx.conceptual_mode_order) do
		local current_x_position = h_offset_mode + (i - 1) * (mode_width + h_spacing_mode)
		imgui.SetCursorPosX(current_x_position)
		imgui.SetCursorPosY(y_offset_mode)

		local text_color_for_label = 0xFF111111
		if conceptual_name_to_draw == current_mode_conceptual_name then
			text_color_for_label = 0xFF00FF00
		end
		draw_label(conceptual_name_to_draw, mode_width, 20, text_color_for_label)

		-- Draw mode group dots if there are multiple variants (e.g., AUTO_1, AUTO_2)
		local group_info = ctx.mode_group_info and ctx.mode_group_info[conceptual_name_to_draw]
		if group_info and group_info.count > 1 then
			local current_idx = group_info.current_index or 1
			local dot_radius = 3
			local dot_spacing = 10
			local total_width = (group_info.count - 1) * dot_spacing
			local start_x = current_x_position + mode_width / 2 - total_width / 2
			local dot_y = y_offset_mode + 20 + dot_radius

			for j = 1, group_info.count do
				local is_selected = (j == current_idx)
				local dot_color = is_selected and 0xFF00FF00 or 0xFF333333
				local center_x = start_x + (j - 1) * dot_spacing

				imgui.DrawList_AddCircleFilled(center_x, dot_y, dot_radius, dot_color, 8)
			end
		end
	end
	imgui.SetWindowFontScale(1.0)

	-- ---- Selection labels row -----------------------------------------------
	local h_offset_select = H_OFFSET
	local h_spacing_select = H_SPACING
	local y_offset_select = 45
	local select_width = WIDGET_WIDTH

	local selection_labels = ctx.selection_map_labels[ctx.current_mode] or {}
	for i, selection_label in ipairs(selection_labels) do
		local x = h_offset_select + (i - 1) * (select_width + h_spacing_select)
		imgui.SetCursorPosX(x)
		imgui.SetCursorPosY(y_offset_select)

		local text_color = ctx.current_selection_label == selection_label and 0xFFFFFFFF or 0xFF111111
		draw_label(selection_label, select_width, 20, text_color)
	end

	imgui.SetWindowFontScale(1.0)

	-- ---- Buttons row --------------------------------------------------------
	local h_offset_button = H_OFFSET
	local h_spacing_button = H_SPACING
	local y_offset_button = 90
	local button_width = WIDGET_WIDTH
	local button_color = 0xFF575049
	local button_off_label_color = 0xFF111111
	local button_on_label_color = 0xFFFFFFFF
	local button_no_led_label_color = 0xFF18D1CB

	imgui.NewLine()
	imgui.SetCursorPosX(h_offset_button)
	imgui.SetCursorPosY(y_offset_button)

	local mode_switch_map = ctx.button_is_switch_map[ctx.current_mode] or {}
	local selection_switch_map = mode_switch_map[ctx.current_selection] or {}
	local all_switch_map = mode_switch_map["ALL"] or {}

	for i = 1, #ctx.current_buttons do
		local button_label = ctx.current_buttons[i]
		local button_name = ctx.default_button_labels[i]
		local led_state = ctx.get_button_led_state(button_name)
		local button_label_color = button_no_led_label_color
		if led_state == true then
			button_label_color = button_on_label_color
		elseif led_state == false then
			button_label_color = button_off_label_color
		end

		local is_switch = (selection_switch_map[button_name] == true) or (all_switch_map[button_name] == true)

		local current_button_x = h_offset_button + (i - 1) * (button_width + h_spacing_button)

		if i == #ctx.current_buttons then
			current_button_x = h_offset_button + (i - 2) * (button_width + h_spacing_button)
			y_offset_button = y_offset_button - 45
		end

		imgui.SetCursorPosX(current_button_x)
		imgui.SetCursorPosY(y_offset_button)
		draw_button(
			button_label,
			button_width,
			30,
			button_color,
			button_label_color,
			is_switch,
			ctx.current_switch_mode,
			ctx.arrow_color
		)
	end

	-- ---- Switch labels row --------------------------------------------------
	local h_offset_switch = H_OFFSET
	local h_spacing_switch = 5
	local y_offset_switch = 180
	local switch_width = 60
	local switch_color = button_color

	imgui.NewLine()
	imgui.SetCursorPosX(h_offset_button)
	imgui.SetCursorPosY(y_offset_button)

	for i = 1, #ctx.switch_map_labels do
		local switch_label = ctx.switch_map_labels[i]
		local current_switch_x = h_offset_switch + (i - 1) * (switch_width + h_spacing_switch)
		local led_state = ctx.get_led_state_for_switch("SWITCH" .. i .. "_LED")
		local switch_label_color = button_no_led_label_color
		if led_state == true then
			switch_label_color = button_on_label_color
		elseif led_state == false then
			switch_label_color = button_off_label_color
		end
		imgui.SetCursorPosX(current_switch_x)
		imgui.SetCursorPosY(y_offset_switch - ctx.vertical_spacing * 1.5)
		draw_button(switch_label, switch_width, 30, switch_color, switch_label_color, false, nil)
	end

	-- ---- Twist knob ---------------------------------------------------------
	local graphic_center_x = 505
	local graphic_center_y = 75
	local outer_radius = 36
	local inner_radius = 25
	local num_segments = 32
	local outline_thickness = 2

	draw_knob(
		graphic_center_x,
		graphic_center_y,
		outer_radius,
		inner_radius,
		num_segments,
		outline_thickness,
		ctx.current_mode,
		ctx.current_selection,
		ctx.current_cf_mode,
		ctx.current_cf_mode_upper,
		ctx.twist_knob_map_actions,
		ctx.twist_knob_map_labels
	)
end

--- Called when the floating window is closed.  *ctx* may contain a
--- `hid_close` callback and a device handle (`bravo`).
function M.on_close(ctx)
	if ctx.hid_close_fn and ctx.bravo then
		ctx.hid_close_fn(ctx.bravo)
	end
end

return M
