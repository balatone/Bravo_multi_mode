--[[
    bravo++.dispatch - Command and Action Mapping Module

    Responsibilities:
    - Build and maintain action maps from parsed config (nav_bindings)
    - Execute button actions (click, hold, long_click, up/down switch)
    - Execute twist knob actions (outer/inner, up/down)
    - Execute rocker switch commands
    - Execute trim wheel commands with boost logic
    - Manage mode cycling (mode up/down, cf mode, switch mode)
    - Provide selector refresh and button label updates

    This module is the "brain" that maps hardware inputs to software actions.
]]

local util = require("bravo++.util")
local log = require("bravo++.log")

-- FlyWithLua global command functions (undefined in luacheck, available at runtime)
-- luacheck: ignore 2143
local command_once_fn = _G.command_once
-- luacheck: ignore 2143
local command_begin_fn = _G.command_begin
-- luacheck: ignore 2143
local command_end_fn = _G.command_end

local dispatch = {}

-- ============================================================
-- Internal State (initialized by init())
-- ============================================================

local button_map_actions = {} -- [mode][selection|button][label] -> {ON_CLICK, ON_HOLD, ...}
local button_is_switch_map = {} -- [mode][ALL|selection][label] -> boolean
local twist_knob_map_actions = {} -- [mode][selection][direction] -> action
local rocker_switch_led_states = {}

-- Mode/switch state (mirrored from bravo++.state but kept local for fast access)
local current_mode = nil
local current_selection = nil
local current_cf_mode = "outer"
local current_switch_mode = "up"
local mode_select = false

-- Trim state
local trim_last_click_time = 0
local trim_dataref = nil
local trim_increment = 0.01
local trim_boost_factor = 3
local trim_boost_window = 0.2

-- Button command state for continuous/long-press tracking
local command_state = {}
local arrow_color = 0xFF00FF00

-- Thresholds (set from config during init)
local long_click_threshold = 0.5
local continuous_press_threshold = 1.0

-- Reference to external maps passed in during init
local selection_map_labels = nil
local button_map_labels = nil
local modes = nil
local default_selections = nil
local default_button_labels = nil
local nav_bindings = nil

-- Mode select command mapping
local mode_select_command = {
	UP = "FlyWithLua/Bravo++/cycle_mode_up",
	DOWN = "FlyWithLua/Bravo++/cycle_mode_down",
}

-- ============================================================
-- Initialization
-- ============================================================

--- Initialize the dispatch module with parsed config and external references.
--- @param bindings table  Parsed configuration bindings from bravo++.config
--- @param ctx table  Context table containing modes, selections, labels, etc.
function dispatch.init(bindings, ctx)
	nav_bindings = bindings
	modes = ctx.modes or {}
	default_selections = ctx.default_selections or {}
	default_button_labels = ctx.default_button_labels or {}
	selection_map_labels = ctx.selection_map_labels or {}
	button_map_labels = ctx.button_map_labels or {}

	current_mode = modes[1]
	current_selection = default_selections[1]

	-- Thresholds from config
	local is_windows = (package.config and package.config:sub(1, 1) == "\\")
	long_click_threshold = nav_bindings.LONG_CLICK_THRESHOLD and tonumber(nav_bindings.LONG_CLICK_THRESHOLD)
		or (is_windows and 0.250 or 0.500)
	continuous_press_threshold = nav_bindings.CONTINUOUS_PRESS_THRESHOLD
			and tonumber(nav_bindings.CONTINUOUS_PRESS_THRESHOLD)
		or (is_windows and 0.750 or 1.0)

	-- Trim config
	trim_increment = tonumber(nav_bindings.TRIM_INCREMENT) or 0.01
	trim_boost_factor = tonumber(nav_bindings.TRIM_BOOST) or 3

	log.info("Initializing button action map...")
	dispatch:_build_button_action_map()

	log.info("Initializing twist knob action map...")
	dispatch:_build_twist_knob_action_map()

	log.info("Dispatch module initialized.")
end

--- Set the dataref table for trim (called after X-Plane dataref system is ready)
function dispatch.set_trim_dataref(dr)
	trim_dataref = dr
end

-- ============================================================
-- Internal: Build Action Maps
-- ============================================================

-- luacheck: no unused args
function dispatch:_build_button_action_map()
	button_map_actions = {}
	button_is_switch_map = {}

	local up_down = { "UP", "DOWN" }

	for i = 1, #modes do
		button_map_actions[modes[i]] = {}
		button_is_switch_map[modes[i]] = {}
		button_is_switch_map[modes[i]]["ALL"] = {}

		for j = 1, #default_selections do
			local sel = default_selections[j]
			button_map_actions[modes[i]][sel] = button_map_actions[modes[i]][sel] or {}
			button_is_switch_map[modes[i]][sel] = button_is_switch_map[modes[i]][sel] or {}

			for k = 1, #default_button_labels do
				local btn = default_button_labels[k]
				button_map_actions[modes[i]][btn] = button_map_actions[modes[i]][btn] or {}
				button_map_actions[modes[i]][sel][btn] = button_map_actions[modes[i]][sel][btn] or {}

				-- Handle ALT selection: buttons are mode-level, not selection-aware
				if sel == "ALT" and nav_bindings[modes[i] .. "_" .. btn .. "_BUTTON"] then
					local full_key = modes[i] .. "_" .. btn .. "_BUTTON"
					local bindings = util.create_table(nav_bindings[full_key])

					button_map_actions[modes[i]][btn]["ON_CLICK"] = bindings[1]
					log.info("Adding " .. full_key .. " = " .. bindings[1] .. " for ON_CLICK")

					local on_hold_action = bindings[2] or bindings[1]
					button_map_actions[modes[i]][btn]["ON_HOLD"] = on_hold_action
					log.info("Adding " .. full_key .. " = " .. on_hold_action .. " for ON_HOLD")
				elseif sel == "ALT" and not nav_bindings[modes[i] .. "_" .. btn .. "_BUTTON"] then
					-- ALT buttons with UP/DOWN switch behavior
					local is_current_button_a_switch = false

					for l = 1, #up_down do
						local full_key = modes[i] .. "_" .. btn .. "_" .. up_down[l] .. "_BUTTON"
						local bindings = util.create_table(nav_bindings[full_key])

						if bindings[1] then
							button_map_actions[modes[i]][btn][up_down[l]] = button_map_actions[modes[i]][btn][up_down[l]]
								or {}
							button_map_actions[modes[i]][btn][up_down[l]]["ON_CLICK"] = bindings[1]
							log.info("Adding " .. full_key .. " = " .. bindings[1] .. " for ON_CLICK")

							local on_hold_action = bindings[2] or bindings[1]
							button_map_actions[modes[i]][btn][up_down[l]]["ON_HOLD"] = on_hold_action
							log.info("Adding " .. full_key .. " = " .. on_hold_action .. " for ON_HOLD")

							button_map_actions[modes[i]][btn][up_down[l]]["ON_LONG_CLICK"] =
								"FlyWithLua/Bravo++/switch_mode_button"
							log.info(
								"Adding " .. full_key .. " = FlyWithLua/Bravo++/switch_mode_button for ON_LONG_CLICK"
							)

							is_current_button_a_switch = true
						end
					end

					if is_current_button_a_switch then
						button_is_switch_map[modes[i]]["ALL"][btn] = is_current_button_a_switch
					end
				end

				-- Selection-aware button bindings
				local key = modes[i] .. "_" .. sel
				local full_key = key .. "_" .. btn .. "_BUTTON"
				local bindings = util.create_table(nav_bindings[full_key])
				local is_select_context_aware = false

				if bindings[1] then
					button_map_actions[modes[i]][sel][btn]["ON_CLICK"] = bindings[1]
					log.info("Adding " .. full_key .. " = " .. bindings[1] .. " for ON_CLICK")

					local on_hold_action = bindings[2] or bindings[1]
					button_map_actions[modes[i]][sel][btn]["ON_HOLD"] = on_hold_action
					log.info("Adding " .. full_key .. " = " .. on_hold_action .. " for ON_HOLD")

					is_select_context_aware = true
				else
					-- Selection-aware buttons with UP/DOWN switch behavior
					local is_current_button_a_switch = false

					for l = 1, #up_down do
						full_key = key .. "_" .. btn .. "_" .. up_down[l] .. "_BUTTON"
						bindings = util.create_table(nav_bindings[full_key])

						if bindings[1] then
							button_map_actions[modes[i]][sel][btn][up_down[l]] = button_map_actions[modes[i]][sel][btn][up_down[l]]
								or {}
							button_map_actions[modes[i]][sel][btn][up_down[l]]["ON_CLICK"] = bindings[1]
							log.info("Adding " .. full_key .. " = " .. bindings[1] .. " for ON_CLICK")

							local on_hold_action = bindings[2] or bindings[1]
							button_map_actions[modes[i]][sel][btn][up_down[l]]["ON_HOLD"] = on_hold_action
							log.info("Adding " .. full_key .. " = " .. on_hold_action .. " for ON_HOLD")

							button_map_actions[modes[i]][sel][btn][up_down[l]]["ON_LONG_CLICK"] =
								"FlyWithLua/Bravo++/switch_mode_button"
							log.info(
								"Adding " .. full_key .. " = FlyWithLua/Bravo++/switch_mode_button for ON_LONG_CLICK"
							)

							is_current_button_a_switch = true
							is_select_context_aware = true
						end
					end

					if is_current_button_a_switch then
						button_is_switch_map[modes[i]][sel][btn] = is_current_button_a_switch
					end
				end

				if not is_select_context_aware and sel == "ALT" then
					log.info(
						"************* Adding is switch to ALL ************ "
							.. tostring(button_is_switch_map[modes[i]]["ALL"][btn])
					)
				end
			end
		end
	end
end

-- luacheck: ignore 212
function dispatch:_build_twist_knob_action_map()
	twist_knob_map_actions = {}

	local up_down = { "UP", "DOWN" }
	local outer_inner = { "OUTER", "INNER" }

	for i = 1, #modes do
		twist_knob_map_actions[modes[i]] = {}

		for j = 1, #default_selections do
			local sel = default_selections[j]
			twist_knob_map_actions[modes[i]][sel] = {}

			local outer_map = {}
			for l = 1, #outer_inner do
				local oi = outer_inner[l]
				outer_map[oi] = {}

				for k = 1, #up_down do
					local dir = up_down[k]
					local key = modes[i] .. "_" .. sel

					-- Check for INNER-specific binding (fallback if no OUTER/INNER specified)
					if oi == "INNER" and nav_bindings[key .. "_" .. dir] then
						local full_key = key .. "_" .. dir
						twist_knob_map_actions[modes[i]][sel][dir] = nav_bindings[full_key]
						log.info("Adding " .. full_key .. " = " .. nav_bindings[full_key])
					end

					-- Check for OUTER/INNER specific binding
					if nav_bindings[key .. "_" .. oi .. "_" .. dir] then
						local full_key = key .. "_" .. oi .. "_" .. dir
						outer_map[oi][dir] = nav_bindings[full_key]
						twist_knob_map_actions[modes[i]][sel] = outer_map
						log.info("Adding " .. full_key .. " = " .. nav_bindings[full_key] .. " to " .. oi)
					end
				end
			end
		end
	end
end

-- ============================================================
-- Public: State Accessors/Mutators
-- ============================================================

function dispatch.get_current_mode()
	return current_mode
end

function dispatch.set_current_mode(m)
	current_mode = m
end

function dispatch.get_current_selection()
	return current_selection
end

function dispatch.set_current_selection(s)
	current_selection = s
end

function dispatch.get_current_cf_mode()
	return current_cf_mode
end

function dispatch.get_current_switch_mode()
	return current_switch_mode
end

function dispatch.is_mode_select()
	return mode_select
end

-- ============================================================
-- Public: Mode Cycling
-- ============================================================

--- Cycle to the next mode (up)
function dispatch.cycle_mode_up()
	local index = util.find(modes, current_mode)
	index = (index % #modes) + 1
	current_mode = modes[index]
	return current_mode
end

--- Cycle to the previous mode (down)
function dispatch.cycle_mode_down()
	local index = util.find(modes, current_mode)
	index = ((index - 2) % #modes) + 1
	current_mode = modes[index]
	return current_mode
end

--- Toggle between outer/inner cf mode
function dispatch.cycle_cf_mode()
	local outer_inner_modes = { "outer", "inner" }
	local index = util.find(outer_inner_modes, current_cf_mode)
	index = (index % #outer_inner_modes) + 1
	current_cf_mode = outer_inner_modes[index]
	return current_cf_mode
end

--- Toggle between up/down switch mode
function dispatch.cycle_switch_mode()
	local up_down_modes = { "up", "down" }
	local index = util.find(up_down_modes, current_switch_mode)
	index = (index % #up_down_modes) + 1
	current_switch_mode = up_down_modes[index]
	return current_switch_mode
end

--- Activate mode select (knob controls mode instead of selection)
function dispatch.activate_mode_select()
	mode_select = true
end

--- Deactivate mode select
function dispatch.deactivate_mode_select()
	mode_select = false
end

-- ============================================================
-- Public: Selector & Button Label Management
-- ============================================================

--- Set the selector index and update current selection label
--- @param idx integer  1-based selector index
--- @param on_update function  Callback to trigger LED refresh (optional)
function dispatch.set_selector_index(idx, on_update)
	if not selection_map_labels or not selection_map_labels[current_mode] then
		return
	end

	local new_label = selection_map_labels[current_mode][idx]
	if new_label and new_label ~= dispatch._get_current_selection_label() then
		dispatch._set_current_selection_label(new_label)
		current_selection = default_selections[idx]
		if on_update then
			on_update()
		end
	end
end

--- Get the current button labels for the active mode/selection
function dispatch.get_current_buttons()
	if button_map_labels and button_map_labels[current_mode] and button_map_labels[current_mode][current_selection] then
		return button_map_labels[current_mode][current_selection]
	end
	return default_button_labels
end

-- Internal label tracking
local current_selection_label = ""
function dispatch._get_current_selection_label()
	return current_selection_label
end
function dispatch._set_current_selection_label(v)
	current_selection_label = v
end
function dispatch.init_selection_label(l)
	current_selection_label = l or ""
end

-- ============================================================
-- Internal: Button Command Execution (hoisted before callers)
-- ============================================================

--- Execute the resolved button command based on current phase
local function _trigger_button_command(button_name)
	local cmds = dispatch.resolve_button_command(button_name)
	if not cmds then
		return
	end

	local is_continuous = command_state[button_name] and command_state[button_name].is_continuous_mode
	local phase = command_state[button_name] and command_state[button_name].phase or "begin"

	local success, err = pcall(function()
		if is_continuous then
			if phase == "begin" then
				log.debug("Trigger command begin: " .. (cmds["ON_HOLD"] or cmds["ON_CLICK"]))
				command_begin_fn(cmds["ON_HOLD"] or cmds["ON_CLICK"])
				command_state[button_name].phase = "continuous"
			elseif phase == "end" then
				log.debug("Trigger command end: " .. (cmds["ON_HOLD"] or cmds["ON_CLICK"]))
				command_end_fn(cmds["ON_HOLD"] or cmds["ON_CLICK"])
			end
		else
			if phase == "long_click" and cmds["ON_LONG_CLICK"] ~= nil then
				log.debug("Trigger long click: " .. cmds["ON_LONG_CLICK"])
				command_once_fn(cmds["ON_LONG_CLICK"])
			else
				log.debug("Trigger click: " .. (cmds["ON_CLICK"] or "sim/none/none"))
				command_once_fn(cmds["ON_CLICK"] or "sim/none/none")
			end
		end
	end)

	if not success then
		log.error("Button dispatch error for " .. button_name .. ": " .. tostring(err))
	end
end

-- ============================================================
-- Public: Button Action Execution
-- ============================================================

--- Resolve the command string for a given button and interaction type.
--- Returns the resolved command table/string, or nil if not found.
function dispatch.resolve_button_command(button_name)
	local cmd = "sim/none/none"

	-- 1) Check mode-level button (e.g., ALT selection buttons)
	if
		util.is_string(
			button_map_actions[current_mode][button_name] and button_map_actions[current_mode][button_name]["ON_CLICK"]
		)
	then
		cmd = button_map_actions[current_mode][button_name]

	-- 2) Check mode-level button with UP/DOWN switch behavior
	elseif
		current_switch_mode == "up"
		and util.is_table(button_map_actions[current_mode][button_name])
		and util.is_table(button_map_actions[current_mode][button_name]["UP"])
		and util.is_string(button_map_actions[current_mode][button_name]["UP"]["ON_CLICK"])
	then
		cmd = button_map_actions[current_mode][button_name]["UP"]
	elseif
		current_switch_mode == "down"
		and util.is_table(button_map_actions[current_mode][button_name])
		and util.is_table(button_map_actions[current_mode][button_name]["DOWN"])
		and util.is_string(button_map_actions[current_mode][button_name]["DOWN"]["ON_CLICK"])
	then
		cmd = button_map_actions[current_mode][button_name]["DOWN"]

	-- 3) Check selection-aware button
	elseif
		util.is_table(button_map_actions[current_mode][current_selection])
		and util.is_table(button_map_actions[current_mode][current_selection][button_name])
	then
		if util.is_string(button_map_actions[current_mode][current_selection][button_name]["ON_CLICK"]) then
			cmd = button_map_actions[current_mode][current_selection][button_name]
		elseif
			current_switch_mode == "up"
			and util.is_string(button_map_actions[current_mode][current_selection][button_name]["UP"]["ON_CLICK"])
		then
			cmd = button_map_actions[current_mode][current_selection][button_name]["UP"]
		elseif
			current_switch_mode == "down"
			and util.is_string(button_map_actions[current_mode][current_selection][button_name]["DOWN"]["ON_CLICK"])
		then
			cmd = button_map_actions[current_mode][current_selection][button_name]["DOWN"]
		else
			log.debug(
				"Button action not found for mode="
					.. current_mode
					.. " sel="
					.. current_selection
					.. " btn="
					.. button_name
			)
		end
	else
		log.debug("Button action not found for btn=" .. button_name)
	end

	return cmd
end

--- Begin button press: initialize timer and state
function dispatch.button_begin(button_name)
	-- Reset arrow color on new press to ensure clean visual state
	arrow_color = 0xFF00FF00

	command_state[button_name] = {
		start_time = os.clock(),
		is_continuous_mode = false,
		phase = "begin",
	}
end

--- Continue button press: handle continuous mode or long-click detection
function dispatch.button_continue(button_name)
	if not command_state[button_name] then
		return
	end

	local elapsed = os.clock() - command_state[button_name].start_time

	if elapsed >= continuous_press_threshold then
		if not command_state[button_name].is_continuous_mode then
			log.debug("Button " .. button_name .. " held long enough. Starting continuous mode.")
			command_state[button_name].is_continuous_mode = true
			arrow_color = 0xFFED10D8
		end
		_trigger_button_command(button_name)
	elseif elapsed >= long_click_threshold then
		local cmds = dispatch.resolve_button_command(button_name)
		if cmds and cmds["ON_LONG_CLICK"] ~= nil then
			arrow_color = 0xFF18D1CB
		end
	end
end

--- End button press: trigger single-click or long-click action
function dispatch.button_end(button_name)
	if not command_state[button_name] then
		-- Robustness: handle unexpected end without a begin
		log.debug("Button " .. button_name .. " ended without a begin - resetting state")
		arrow_color = 0xFF00FF00
		return
	end

	local elapsed = os.clock() - command_state[button_name].start_time

	if not command_state[button_name].is_continuous_mode and elapsed >= long_click_threshold then
		log.debug("Long click detected for " .. button_name)
		command_state[button_name].phase = "long_click"
		_trigger_button_command(button_name)
	else
		log.debug("Single click for " .. button_name)
		command_state[button_name].phase = "end"
		_trigger_button_command(button_name)
	end

	-- Clean up state to prevent stale data from corrupting subsequent clicks
	command_state[button_name] = nil
	arrow_color = 0xFF00FF00
end

-- ============================================================
-- Public: Twist Knob Execution
-- ============================================================

--- Execute twist knob increase (clockwise)
function dispatch.knob_increase()
	local current_action

	if mode_select then
		current_action = mode_select_command
	else
		current_action = twist_knob_map_actions[current_mode]
			and twist_knob_map_actions[current_mode][current_selection]
	end

	if not current_action then
		return
	end

	-- Priority: direct UP > OUTER.UP (if cf=outer) > INNER.UP (if cf=inner)
	if current_action["UP"] then
		command_once_fn(current_action["UP"])
	elseif current_cf_mode == "outer" and current_action["OUTER"] and current_action["OUTER"]["UP"] then
		command_once_fn(current_action["OUTER"]["UP"])
	elseif current_cf_mode == "inner" and current_action["INNER"] and current_action["INNER"]["UP"] then
		command_once_fn(current_action["INNER"]["UP"])
	else
		log.debug("No UP action for twist knob.")
	end
end

--- Execute twist knob decrease (counter-clockwise)
function dispatch.knob_decrease()
	local current_action

	if mode_select then
		current_action = mode_select_command
	else
		current_action = twist_knob_map_actions[current_mode]
			and twist_knob_map_actions[current_mode][current_selection]
	end

	if not current_action then
		return
	end

	-- Priority: direct DOWN > OUTER.DOWN (if cf=outer) > INNER.DOWN (if cf=inner)
	if current_action["DOWN"] then
		command_once_fn(current_action["DOWN"])
	elseif current_cf_mode == "outer" and current_action["OUTER"] and current_action["OUTER"]["DOWN"] then
		command_once_fn(current_action["OUTER"]["DOWN"])
	elseif current_cf_mode == "inner" and current_action["INNER"] and current_action["INNER"]["DOWN"] then
		command_once_fn(current_action["INNER"]["DOWN"])
	else
		log.debug("No DOWN action for twist knob.")
	end
end

-- ============================================================
-- Public: Rocker Switch Execution
-- ============================================================

--- Execute a rocker switch command
--- @param rocker_number integer  1-7
--- @param dir string  "UP" or "DOWN"
function dispatch.rocker_switch(rocker_number, dir)
	local key = "SWITCH" .. rocker_number .. "_" .. dir
	local binding = nav_bindings and nav_bindings[key]

	if binding then
		log.info("Rocker switch " .. rocker_number .. " " .. dir .. ": " .. binding)
		command_once_fn(binding)
	else
		log.warning("No binding for rocker switch " .. rocker_number .. " " .. dir)
	end
end

--- Get the LED state for a rocker switch (for UI rendering)
function dispatch.get_rocker_switch_led(name)
	return rocker_switch_led_states[name] or false
end

--- Set the LED state for a rocker switch
function dispatch.set_rocker_switch_led(name, state)
	rocker_switch_led_states[name] = state or false
end

-- ============================================================
-- Public: Trim Wheel Execution
-- ============================================================

--- Execute trim nose up (elevator trim forward)
function dispatch.trim_nose_up()
	if not trim_dataref then
		return
	end

	local current_time = os.clock()
	local diff = current_time - trim_last_click_time

	local current_value = tonumber(trim_dataref[0]) or 0
	local new_value

	if diff < trim_boost_window then
		new_value = current_value + (trim_increment * trim_boost_factor)
		log.debug("Boosting nose up")
	else
		new_value = current_value + trim_increment
	end

	if new_value <= 1 then
		trim_dataref[0] = new_value
	elseif current_value ~= 1 then
		trim_dataref[0] = 1
	end

	log.debug("New trim value: " .. trim_dataref[0])
	trim_last_click_time = current_time
end

--- Execute trim nose down (elevator trim aft)
function dispatch.trim_nose_down()
	if not trim_dataref then
		return
	end

	local current_time = os.clock()
	local diff = current_time - trim_last_click_time

	local current_value = tonumber(trim_dataref[0]) or 0
	local new_value

	if diff < trim_boost_window then
		new_value = current_value - (trim_increment * trim_boost_factor)
		log.debug("Boosting nose down")
	else
		new_value = current_value - trim_increment
	end

	if new_value >= -1 then
		trim_dataref[0] = new_value
	elseif current_value ~= -1 then
		trim_dataref[0] = -1
	end

	log.debug("New trim value: " .. trim_dataref[0])
	trim_last_click_time = current_time
end

-- ============================================================
-- Public: Map Accessors (for UI module)
-- ============================================================

function dispatch.get_button_is_switch_map()
	return button_is_switch_map
end

function dispatch.get_twist_knob_map_actions()
	return twist_knob_map_actions
end

function dispatch.get_modes()
	return modes
end

function dispatch.get_default_selections()
	return default_selections
end

function dispatch.get_default_button_labels()
	return default_button_labels
end

-- ============================================================
-- Public: Arrow Color (for UI)
-- ============================================================

function dispatch.get_arrow_color()
	return arrow_color
end

return dispatch
