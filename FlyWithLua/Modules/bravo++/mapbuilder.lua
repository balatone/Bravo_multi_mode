--[[
    MapBuilder.lua
    Unified mapping initialization utility for BravoMultiMode.

    Performs a single hierarchical traversal over modes, selections, and buttons
    to populate all registry tables in one pass:
      - selection_map_labels
      - button_map_labels
      - twist_knob_map_labels
      - button_map_leds
      - button_map_leds_state
      - button_map_leds_cond
      - button_map_leds_index

    This replaces the deeply nested, redundant loops that previously lived in
    BravoMultiMode.lua.
]]

local util = require("bravo++.util")
local log = require("bravo++.log")

-- FlyWithLua globals (undefined in luacheck, available at runtime)
-- luacheck: ignore 2143
local dataref_table_fn = _G.dataref_table

local MapBuilder = {}

------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------

--- Check whether a mode should use config bindings or defaults.
--- AUTO mode only uses bindings when an explicit binding exists;
--- all other modes always prefer bindings (falling back to defaults).
local function should_use_bindings(mode, key, nav_bindings)
	if mode ~= "AUTO" then
		return true
	end
	-- For AUTO: use bindings only if the specific key exists
	return nav_bindings[key] ~= nil
end

------------------------------------------------------------------------
-- Registry initializers  (create the nested table skeletons)
------------------------------------------------------------------------

local function init_selection_map_labels(modes)
	local m = {}
	for _, mode in ipairs(modes) do
		m[mode] = {}
	end
	return m
end

local function init_button_map_labels(modes, default_selections)
	local m = {}
	for _, mode in ipairs(modes) do
		m[mode] = {}
		for _, sel in ipairs(default_selections) do
			m[mode][sel] = {}
		end
	end
	return m
end

local function init_twist_knob_map_labels(modes, default_selections)
	local m = {}
	for _, mode in ipairs(modes) do
		m[mode] = {}
		for _, sel in ipairs(default_selections) do
			m[mode][sel] = {}
		end
	end
	return m
end

--- Initialize the four parallel LED maps.
--- Structure: [mode]["ALL"|selection][button] -> value
local function init_led_maps(modes)
	local leds = {}
	local leds_cond = {}
	local leds_state = {}
	local leds_index = {}

	for _, mode in ipairs(modes) do
		leds[mode] = {}
		leds_cond[mode] = {}
		leds_state[mode] = {}
		leds_index[mode] = {}
	end

	return leds, leds_cond, leds_state, leds_index
end

------------------------------------------------------------------------
-- Single-pass builder
------------------------------------------------------------------------

function MapBuilder.build(
	nav_bindings,
	modes,
	default_selections,
	default_button_labels,
	no_button_labels,
	default_selections_for_auto
)
	-- Require config module for compile_condition (available at runtime)
	local config = require("bravo++.config")

	-- Initialise result tables with proper nested skeletons
	local selection_map_labels = init_selection_map_labels(modes)
	local button_map_labels = init_button_map_labels(modes, default_selections)
	local twist_knob_map_labels = init_twist_knob_map_labels(modes, default_selections)
	local button_map_leds, button_map_leds_cond, button_map_leds_state, button_map_leds_index = init_led_maps(modes)

	------------------------------------------------------------------
	-- Main traversal: modes -> selections -> buttons
	------------------------------------------------------------------
	for _, mode in ipairs(modes) do
		----------------------------------------------------------
		-- 1. Selection labels  (mode-level, outside selection loop)
		----------------------------------------------------------
		local sel_key = mode .. "_SELECTOR_LABELS"
		if should_use_bindings(mode, sel_key, nav_bindings) and nav_bindings[sel_key] then
			selection_map_labels[mode] = util.create_table(nav_bindings[sel_key])
			log.info("Adding " .. sel_key .. " = " .. nav_bindings[sel_key])
		else
			selection_map_labels[mode] = default_selections_for_auto or default_selections
			log.info("Adding default selector labels for mode " .. mode)
		end

		----------------------------------------------------------
		-- 2-4. Per-selection pass: button labels, knob labels, LEDs
		----------------------------------------------------------
		for _, sel in ipairs(default_selections) do
			----------------------------------------------
			-- 2. Button labels
			----------------------------------------------
			local btn_lbl_key = mode .. "_" .. sel .. "_BUTTON_LABELS"
			if should_use_bindings(mode, btn_lbl_key, nav_bindings) then
				if nav_bindings[btn_lbl_key] then
					button_map_labels[mode][sel] = util.create_table(nav_bindings[btn_lbl_key])
					log.info("Adding " .. btn_lbl_key .. " = " .. nav_bindings[btn_lbl_key])
				else
					button_map_labels[mode][sel] = no_button_labels
					log.info("No bindings found for " .. btn_lbl_key .. ". Adding no button labels.")
				end
			else
				-- AUTO with no explicit binding -> default labels
				button_map_labels[mode][sel] = default_button_labels
				log.info("Adding default button labels for " .. mode .. "/" .. sel)
			end

			----------------------------------------------
			-- 3. Twist knob labels
			----------------------------------------------
			local knob_key = mode .. "_" .. sel .. "_KNOB_LABELS"
			if nav_bindings[knob_key] then
				local bindings = util.create_table(nav_bindings[knob_key])
				if #bindings > 1 then
					twist_knob_map_labels[mode][sel]["OUTER"] = bindings[1]
					twist_knob_map_labels[mode][sel]["INNER"] = bindings[2]
				elseif #bindings == 1 then
					twist_knob_map_labels[mode][sel] = bindings[1]
				end
				log.info("Adding " .. knob_key .. " = " .. nav_bindings[knob_key])
			else
				log.info("No bindings found for " .. knob_key .. ". Adding no knob labels.")
			end

			----------------------------------------------
			-- 4. Button LEDs
			----------------------------------------------
			for _, btn in ipairs(default_button_labels) do
				local binding
				local full_key
				local handled = false

				-- ALT selection: check mode-level LED key first
				if sel == "ALT" then
					full_key = mode .. "_" .. btn .. "_BUTTON_LED"
					if nav_bindings[full_key] then
						binding = util.create_table(nav_bindings[full_key])

						-- Populate the "ALL" bucket (applies to every selection)
						if not button_map_leds[mode]["ALL"] then
							button_map_leds[mode]["ALL"] = {}
							button_map_leds_cond[mode]["ALL"] = {}
							button_map_leds_state[mode]["ALL"] = {}
							button_map_leds_index[mode]["ALL"] = {}
						end

						button_map_leds[mode]["ALL"][btn] = dataref_table_fn(binding[1])
						button_map_leds_cond[mode]["ALL"][btn] = config.compile_condition(binding[2], full_key)
						button_map_leds_state[mode]["ALL"][btn] = false
						if binding[3] ~= nil then
							button_map_leds_index[mode]["ALL"][btn] = binding[3]
						end

						log.debug("navbinding: " .. nav_bindings[full_key])
						log.debug("datref: " .. binding[1])
						log.debug("cond: " .. binding[2])
						if binding[3] ~= nil then
							log.debug("index: " .. binding[3])
						end
						log.info("Adding " .. full_key .. " = " .. nav_bindings[full_key])

						-- Mode-level LED takes precedence for ALT; skip selection-level check
						handled = true
					end
				end

				if not handled then
					-- Normal selection-level LED key
					full_key = mode .. "_" .. sel .. "_" .. btn .. "_BUTTON_LED"
					if nav_bindings[full_key] then
						binding = util.create_table(nav_bindings[full_key])

						-- Ensure per-selection sub-table exists
						if not button_map_leds[mode][sel] then
							button_map_leds[mode][sel] = {}
							button_map_leds_cond[mode][sel] = {}
							button_map_leds_state[mode][sel] = {}
							button_map_leds_index[mode][sel] = {}
						end

						button_map_leds[mode][sel][btn] = dataref_table_fn(binding[1])
						button_map_leds_cond[mode][sel][btn] = config.compile_condition(binding[2], full_key)
						button_map_leds_state[mode][sel][btn] = false
						if binding[3] ~= nil then
							button_map_leds_index[mode][sel][btn] = binding[3]
						end

						log.debug("navbinding: " .. nav_bindings[full_key])
						log.debug("datref: " .. binding[1])
						log.debug("cond: " .. binding[2])
						if binding[3] ~= nil then
							log.debug("index: " .. binding[3])
						end
						log.info("Adding " .. full_key .. " = " .. nav_bindings[full_key])
					end
				end
			end
		end
	end

	------------------------------------------------------------------
	-- Return all populated maps
	------------------------------------------------------------------
	return {
		selection_map_labels = selection_map_labels,
		button_map_labels = button_map_labels,
		twist_knob_map_labels = twist_knob_map_labels,
		button_map_leds = button_map_leds,
		button_map_leds_cond = button_map_leds_cond,
		button_map_leds_state = button_map_leds_state,
		button_map_leds_index = button_map_leds_index,
	}
end

return MapBuilder
