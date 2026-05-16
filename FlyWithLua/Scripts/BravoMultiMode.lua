-- Modules needed for logging and general functionality
local util = require("bravo++.util")
local log = require("bravo++.log")
local config = require("bravo++.config")
local ui = require("bravo++.ui")
local MapBuilder = require("bravo++.mapbuilder")

-----------------------------------------------------
--- PERFORMANCE PROFILER (Method 2: Cumulative Stats)
-----------------------------------------------------
-- Lightweight profiler to track CPU time consumption of core tasks.
-- Logs cumulative stats every 60 seconds to X-Plane log for "before/after" comparison.
local PROFILER_ENABLED = false -- Set to true to enable profiling

local profiler = {
	_tasks = {},
	_last_log_time = os.clock(),
	_log_interval = 60, -- seconds
}

--- Start timing a specific task
function profiler.start(task_name)
	if not PROFILER_ENABLED then
		return nil -- Zero overhead when disabled
	end
	if not profiler._tasks[task_name] then
		profiler._tasks[task_name] = { total_time = 0, calls = 0 }
	end
	return os.clock()
end

--- Stop timing and record the delta for the task
function profiler.stop(task_name, start_time)
	if not PROFILER_ENABLED or not start_time then
		return -- Zero overhead when disabled
	end
	if profiler._tasks[task_name] then
		local delta = os.clock() - start_time
		profiler._tasks[task_name].total_time = profiler._tasks[task_name].total_time + delta
		profiler._tasks[task_name].calls = profiler._tasks[task_name].calls + 1
	end
end

--- Log all accumulated stats and reset the counters
function profiler.log_and_reset()
	log.info("======================================================")
	log.info("BRAVO++ PERFORMANCE PROFILER (Last " .. profiler._log_interval .. "s)")
	log.info("------------------------------------------------------")

	-- Sort tasks by total time descending for easier analysis
	local sorted_tasks = {}
	for name, stats in pairs(profiler._tasks) do
		table.insert(sorted_tasks, { name = name, stats = stats })
	end
	table.sort(sorted_tasks, function(a, b)
		return a.stats.total_time > b.stats.total_time
	end)

	for _, entry in ipairs(sorted_tasks) do
		local name = entry.name
		local stats = entry.stats
		local avg = (stats.calls > 0) and (stats.total_time / stats.calls) or 0
		log.info(
			string.format(
				"Task: %-30s | Calls: %5d | Total: %.4fs | Avg: %.6fs",
				name,
				stats.calls,
				stats.total_time,
				avg
			)
		)
	end

	log.info("======================================================")

	-- Reset for next interval
	profiler._tasks = {}
end

--- Periodic logging task (called every frame via FlyWithLua string callback)
-- Must be global because do_every_frame evaluates strings in the global environment.
function profiler_log_task() -- luacheck: ignore (used by do_every_frame string callback)
	if not PROFILER_ENABLED then
		return -- Zero overhead when disabled
	end
	local now = os.clock()
	if (now - profiler._last_log_time) >= profiler._log_interval then
		profiler.log_and_reset()
		profiler._last_log_time = now
	end
end

--- Toggle profiling on/off at runtime via custom command
function profiler_toggle() -- luacheck: ignore (used by create_command callback)
	PROFILER_ENABLED = not PROFILER_ENABLED
	log.info("Profiling " .. (PROFILER_ENABLED and "ENABLED" or "DISABLED"))
end

create_command(
	"FlyWithLua/Bravo++/toggle_profiler",
	"Toggle Bravo++ performance profiler on/off",
	"profiler_toggle()",
	"",
	""
)

-- Register periodic logging to run every frame (lightweight check)
do_every_frame("profiler_log_task()")

-- Custom commands that will only be imported when corresponding aircraft is loaded
local custom_directory = MODULES_DIRECTORY .. "bravo++" .. DIRECTORY_SEPARATOR .. "custom" .. DIRECTORY_SEPARATOR
dofile(custom_directory .. "C90B.lua")
dofile(custom_directory .. "DA42.lua")
dofile(custom_directory .. "B58.lua")
dofile(custom_directory .. "Transponder.lua")

-- Change the logging level to log.LOG_DEBUG if troubleshooting
log.LOG_LEVEL = log.LOG_INFO
local log_led_state = false

-- New modular HID/decoder modules
local bravo_hid = require("bravo++.hardware")
local bravo_decoder = require("bravo++.decoder")
local bravo_state = require("bravo++.state")
local bravo_debug = require("bravo++.debug")
local dispatch = require("bravo++.dispatch")

local HID_INPUT_DEBUG = false
bravo_debug.enable(HID_INPUT_DEBUG)

-- Detect Windows vs POSIX (package.config first char == directory separator)
local is_windows = (package.config and package.config:sub(1, 1) == "\\")

local bravo = hid_open(0x294B, 0x1901) -- Honeycomb Bravo VID/PID

-- Exit immediately if the Bravo device cannot be opened. Simulated mode removed.
if not bravo then
	log.error("Bravo device was not found (VID=0x294B PID=0x1901). Stopping script.")
	return
end

-- Initialize the modular hid module if available and start draining reports
if bravo and bravo_hid and bravo_hid.init then
	bravo_hid.init({ device_handle = bravo, packet_size = 64 })
	bravo_hid.start()
	log.info("HID polling has started")
else
	log.error("Bravo device was not found (VID=0x294B PID=0x1901). Stopping script.")
	return
end

if not SUPPORTS_FLOATING_WINDOWS then
	-- to make sure the script doesn't stop old FlyWithLua versions
	log.error("Floating windows not supported by your FlyWithLua version")
	return
end

-- NOTE:
-- FlyWithLua executes callback *strings* in the global environment.
-- We therefore keep only a minimal set of global entrypoints and keep
-- the error wrapper local.

-- Helper function to find index in table (used for cycling modes)
-- NOTE: avoid polluting the global `table` namespace.
-- Function that logs any function that fails
local function try_catch(tryBlock, source)
	local success, errorMessage = pcall(tryBlock)
	if not success then
		log.error("Caught error from " .. tostring(source) .. " : " .. tostring(errorMessage))
	end
end

-- FlyWithLua runs callback strings in the global environment, so we keep a
-- single global dispatcher and register local implementations in a table.
local dispatch_callbacks = {}

-- LuaJIT (Lua 5.1) has global `unpack`, while Lua 5.2+ uses `table.unpack`.
local unpack_fn = table.unpack or unpack

function bravo_dispatch(name, ...)
	local fn = dispatch_callbacks[name]
	if not fn then
		log.warning("No dispatch target for: " .. tostring(name))
		return
	end

	-- NOTE: varargs (`...`) are not lexically scoped in Lua, so we must not
	-- reference `...` inside the closure passed to try_catch.
	local args = { ... }
	return try_catch(function()
		fn(unpack_fn(args))
	end, "bravo_dispatch:" .. tostring(name))
end

-- Forward declarations for locals that are referenced before their definitions.
-- (We keep only FlyWithLua string-callback entrypoints global.)
local get_button_led_state
local get_led_state_for_switch
local prime_button_led_states_for_mode_change
local handle_led_changes

local command_begin = command_begin
local command_once = command_once
local command_end = command_end

-- Shared LED "dirty" flag; must be in scope for mode/selector handlers too.
local led_state_modified = false

-- Get aircraft directory from X-Plane's AIRCRAFT_PATH and AIRCRAFT_FILENAME if there are more than one .acf file
local aircraft_dir = string.match(AIRCRAFT_PATH, "(.*[/\\])")
local aircraft_name = string.sub(AIRCRAFT_FILENAME, 1, string.len(AIRCRAFT_FILENAME) - 4)

-- Table to hold dataref assignments
local nav_bindings = {}

-- Load global user preferences first (optional file, won't fail if missing).
-- Aircraft config loaded below will override any overlapping keys.
local prefs_path = MODULES_DIRECTORY .. "bravo++" .. DIRECTORY_SEPARATOR .. "preferences.cfg"
if config.read_preferences(prefs_path, nav_bindings) then
	log.info("Loaded global preferences from " .. prefs_path)
end

-- Load aircraft-specific config (takes precedence over global preferences)
local nav_cfg_file_full_path = aircraft_dir .. "bravo_multi-mode.cfg"
local file_ok = config.read_file(nav_cfg_file_full_path, nav_bindings)

if file_ok then
	log.info("Successfully parsed config file")
else
	local nav_cfg_file_name = "bravo_multi-mode." .. aircraft_name .. ".cfg"
	nav_cfg_file_full_path = aircraft_dir .. nav_cfg_file_name
	log.info("nav_cfg_file: " .. nav_cfg_file_full_path)
	file_ok = config.read_file(nav_cfg_file_full_path, nav_bindings)
	if file_ok then
		log.info("Successfully parsed config file specific for " .. aircraft_name)
	else
		log.warning(
			"No config file found in  "
				.. aircraft_dir
				.. " with name bravo_multi-mode.cfg or "
				.. nav_cfg_file_name
				.. ". Bravo script will be stopped."
		)
		return -- Stop script if config is missing
	end
end

-- The annunciator labels. These are used for validation and in the led logic.
local annunciator_labels = {
	"MASTER_WARNING",
	"FIRE_WARNING",
	"OIL_LOW_PRESSURE",
	"FUEL_LOW_PRESSURE",
	"ANTI_ICE",
	"STARTER_ENGAGED",
	"APU",
	"MASTER_CAUTION",
	"VACUUM",
	"HYD_LOW_PRESSURE",
	"AUX_FUEL_PUMP",
	"PARKING_BRAKE",
	"VOLTS_LOW",
	"DOOR",
}

-- Mode management (managed by dispatch module)
-- local modes = {"AUTO", "PFD", "MFD"} -- Add more modes as needed
local modes = util.create_table(nav_bindings.MODES)
local outer_inner_modes = { "outer", "inner" }
local up_down_modes = { "up", "down" }

-- Bindings for the selector knob (managed by dispatch module)
local default_selections = { "ALT", "VS", "HDG", "CRS", "IAS" }

-- The button labels that will be displayed on the console
local default_button_labels = { "HDG", "NAV", "APR", "REV", "ALT", "VS", "IAS", "PLT" }
local no_button_labels = { "   ", "   ", "   ", "   ", "   ", "   ", "   ", "   " }

local two_param_led_keys = {}

two_param_led_keys["GEAR_DEPLOYMENT_LED"] = true

for _, label in ipairs(annunciator_labels) do
	two_param_led_keys[label .. "_LED"] = true
	-- Account for indexed annunciator labels like AUX_FUEL_PUMP_1_LED, DOOR_1_LED
	-- Assuming a max index based on observed data (e.g., DOOR_3_LED)
	for i = 1, 16 do
		two_param_led_keys[label .. "_" .. tostring(i) .. "_LED"] = true
	end
end

log.info("Validating the config file...")

-- Build context table for validation functions
local validation_context = {
	modes = modes,
	default_selections = default_selections,
	default_button_labels = default_button_labels,
	up_down_modes = up_down_modes,
	outer_inner_modes = outer_inner_modes,
	annunciator_labels = annunciator_labels,
	two_param_led_keys = two_param_led_keys,
}

local keys_valid = config.validate_keys(nav_bindings, validation_context)
local values_valid = config.validate_values(nav_bindings, validation_context)

if not keys_valid or not values_valid then
	return
end

-----------------------------------------------------
--- Unified mapping initialization via MapBuilder
-----------------------------------------------------
log.info("Initializing all maps via unified MapBuilder...")
local built = MapBuilder.build(
	nav_bindings,
	modes,
	default_selections,
	default_button_labels,
	no_button_labels,
	default_selections -- used as fallback selector labels for AUTO mode
)

local selection_map_labels = built.selection_map_labels
local button_map_labels = built.button_map_labels
local twist_knob_map_labels = built.twist_knob_map_labels
local button_map_leds = built.button_map_leds
local button_map_leds_cond = built.button_map_leds_cond
local button_map_leds_state = built.button_map_leds_state
local button_map_leds_index = built.button_map_leds_index

-- The labels for the rocker switches
log.info("Initializing the switch labels...")
local switch_map_labels = {}
if nav_bindings["SWITCH_LABELS"] ~= nil then
	switch_map_labels = util.create_table(nav_bindings["SWITCH_LABELS"])
end

-- Initialize the dispatch module with bindings and validation context
log.info("Initializing button action map, twist knob action map, and rocker switch states via dispatch module...")
dispatch.init(nav_bindings, {
	modes = modes,
	default_selections = default_selections,
	default_button_labels = default_button_labels,
	selection_map_labels = selection_map_labels,
	button_map_labels = button_map_labels,
})

-- Twist knob action map and rocker switch LED states are now managed by dispatch module.

local current_buttons = default_button_labels
local vertical_spacing = 30
local height = 150

if #switch_map_labels > 0 then
	height = 40 * 4 + 20
else
	height = 40 * 3 + 20
end

local my_floating_wnd = float_wnd_create(550, height, 1, true)
float_wnd_set_title(my_floating_wnd, "Bravo++ multi-mode")
float_wnd_set_imgui_builder(my_floating_wnd, "build_bravo_gui")
-- float_wnd_set_positioning_mode(my_floating_wnd, 4, -1)
float_wnd_set_title(my_floating_wnd, "Bravo++ multi-mode")
-- float_wnd_set_position(my_floating_wnd, SCREEN_WIDTH * 2/3 + 50, SCREEN_HEIGHT * 1/6)
float_wnd_set_position(my_floating_wnd, SCREEN_WIDTH * 0.25, SCREEN_HEIGHT * 0.25)

-- float_wnd_set_onclick(my_floating_wnd, "on_click_floating_window")
float_wnd_set_onclose(my_floating_wnd, "on_close_floating_window")

-- Initialize the static tables pertaining to mode
local conceptual_mode_order = {} -- Stores unique conceptual names in the order they first appear
local conceptual_name_seen = {} -- Helper to track if a conceptual name has been added to order

for i = 1, #modes do
	local name_conceptual = util.get_name_before_index(modes[i]) -- Get the base name, e.g., "AUTO" from "AUTO_2"
	if not conceptual_name_seen[name_conceptual] then
		table.insert(conceptual_mode_order, name_conceptual) -- Add unique conceptual name to maintain order
		conceptual_name_seen[name_conceptual] = true
	end
end

-- Build a context table for the UI module so it stays decoupled from globals.
local function build_ui_context()
	return {
		current_mode = dispatch.get_current_mode(),
		current_selection = dispatch.get_current_selection(),
		current_cf_mode = dispatch.get_current_cf_mode(),
		current_cf_mode_upper = string.upper(dispatch.get_current_cf_mode()),
		current_switch_mode = dispatch.get_current_switch_mode(),
		current_selection_label = dispatch._get_current_selection_label(),
		conceptual_mode_order = conceptual_mode_order,
		selection_map_labels = selection_map_labels,
		button_is_switch_map = dispatch.get_button_is_switch_map(),
		default_button_labels = dispatch.get_default_button_labels(),
		current_buttons = dispatch.get_current_buttons(),
		switch_map_labels = switch_map_labels,
		twist_knob_map_actions = dispatch.get_twist_knob_map_actions(),
		twist_knob_map_labels = twist_knob_map_labels,
		get_button_led_state = get_button_led_state,
		get_led_state_for_switch = dispatch.get_rocker_switch_led,
		vertical_spacing = 30,
		arrow_color = dispatch.get_arrow_color(),
	}
end

dispatch_callbacks.build_bravo_gui = function(wnd, x, y)
	local t = profiler.start("build_gui")
	ui.build_gui(build_ui_context())
	profiler.stop("build_gui", t)
end
function build_bravo_gui(wnd, x, y)
	return bravo_dispatch("build_bravo_gui", wnd, x, y)
end

local function on_close_floating_window_impl(my_floating_wnd)
	ui.on_close({ hid_close_fn = hid_close, bravo = bravo })
end

dispatch_callbacks.on_close_floating_window = on_close_floating_window_impl

-- Global wrapper for FlyWithLua float window callback
function on_close_floating_window(my_floating_wnd)
	return bravo_dispatch("on_close_floating_window", my_floating_wnd)
end

--------------------------------------------------------------
--- CREATE THE FUNCTIONS FOR REFRESHING THE MODE AND SELECTOR
--------------------------------------------------------------
-- Track the selector index locally.
-- (Previously this leaked as a global because it was assigned before being declared local.)
local selector_index = 1

local function set_current_selector(idx)
	selector_index = idx
	dispatch.set_selector_index(idx, function()
		prime_button_led_states_for_mode_change()
		led_state_modified = true
		handle_led_changes()
	end)
end

local function refresh_selector_hid()
	-- Use decoded selector state from the modular decoder/state instead of calling hid_read()
	local sel = bravo_state.get_selector()
	if sel and type(sel) == "number" and sel > 0 then
		-- Map decoded raw selector to index if known
		if sel >= 1 and sel <= 5 then
			set_current_selector(sel)
		else
			-- Unknown raw, log for later mapping
			log.debug("refresh_selector_hid: decoded selector raw=" .. tostring(sel))
		end
	end
end

-- Choose the available method for updating the selector
local function refresh_selector_task()
	local t = profiler.start("refresh_selector")
	refresh_selector_hid()
	profiler.stop("refresh_selector", t)
end

dispatch_callbacks.refresh_selector_task = refresh_selector_task

do_every_frame("bravo_dispatch('refresh_selector_task')")

-- Function to cycle the mode down one
local function cycle_mode_down()
	return try_catch(function()
		dispatch.cycle_mode_down()
		prime_button_led_states_for_mode_change()
		led_state_modified = true
		handle_led_changes()
	end, "cycle_mode_down")
end

dispatch_callbacks.cycle_mode_down = cycle_mode_down

-- Function to cycle the mode up one
local function cycle_mode_up()
	return try_catch(function()
		dispatch.cycle_mode_up()
		prime_button_led_states_for_mode_change()
		led_state_modified = true
		handle_led_changes()
	end, "cycle_mode_up")
end

dispatch_callbacks.cycle_mode_up = cycle_mode_up

-- Create a custom command for changing mode
create_command(
	"FlyWithLua/Bravo++/mode_button",
	"Bravo++ toggles MODE",
	"bravo_dispatch('cycle_mode_down')", -- Call Lua function when pressed
	"",
	""
)

-- Moves the current mode up one
create_command(
	"FlyWithLua/Bravo++/cycle_mode_up",
	"Bravo++ cycle mode up",
	"bravo_dispatch('cycle_mode_up')", -- Call Lua function when pressed
	"",
	""
)

-- Moves the current mode down one
create_command(
	"FlyWithLua/Bravo++/cycle_mode_down",
	"Bravo++ cycle mode down",
	"bravo_dispatch('cycle_mode_down')", -- Call Lua function when pressed
	"",
	""
)

local function toggle_mode_select_true()
	return try_catch(function()
		dispatch.activate_mode_select()
	end, "toggle_mode_select_true")
end

dispatch_callbacks.toggle_mode_select_true = toggle_mode_select_true

local function toggle_mode_select_false()
	return try_catch(function()
		dispatch.deactivate_mode_select()
	end, "toggle_mode_select_false")
end

dispatch_callbacks.toggle_mode_select_false = toggle_mode_select_false

create_command(
	"FlyWithLua/Bravo++/toggle_mode_select",
	"Activates the mode select when button in pressed in. Deactivates it when button is released.",
	"",
	"bravo_dispatch('toggle_mode_select_true')",
	"bravo_dispatch('toggle_mode_select_false')"
)

-- Function to cycle through outer/inner modes
local function cycle_cf_mode()
	return try_catch(function()
		dispatch.cycle_cf_mode()
	end, "cycle_cf_mode")
end

dispatch_callbacks.cycle_cf_mode = cycle_cf_mode

-- Create a custom command for changing cf mode
create_command(
	"FlyWithLua/Bravo++/cf_mode_button",
	"Bravo++ toggles INNER/OUTER mode",
	"bravo_dispatch('cycle_cf_mode')", -- Call Lua function when pressed
	"",
	""
)

-- Function to cycle through up/down switch modes
local function cycle_switch_mode()
	return try_catch(function()
		dispatch.cycle_switch_mode()
	end, "cycle_switch_mode")
end

dispatch_callbacks.cycle_switch_mode = cycle_switch_mode

-- Create a custom command for changing ud mode
create_command(
	"FlyWithLua/Bravo++/switch_mode_button",
	"Bravo++ toggles UP/DOWN switch mode",
	"bravo_dispatch('cycle_switch_mode')", -- Call Lua function when pressed
	"",
	""
)

local function set_current_buttons()
	if button_map_labels[dispatch.get_current_mode()][dispatch.get_current_selection()] ~= nil then
		current_buttons = button_map_labels[dispatch.get_current_mode()][dispatch.get_current_selection()]
	end
end

local function set_current_buttons_task()
	local t = profiler.start("set_current_buttons")
	set_current_buttons()
	profiler.stop("set_current_buttons", t)
end

dispatch_callbacks.set_current_buttons_task = set_current_buttons_task

-- Update the currently available buttons
do_every_frame("bravo_dispatch('set_current_buttons_task')")

--------------------------------------
---- ROCKER SWITCHES
--------------------------------------

-- Route rocker switch commands through the dispatch module.
dispatch_callbacks.rocker_switch = function(rocker_number, dir)
	return try_catch(function()
		dispatch.rocker_switch(rocker_number, dir)
	end, "rocker_switch:" .. rocker_number .. ":" .. dir)
end

-- Initialize the rocker switch commands
log.info("Initializing switch commands...")
for i = 1, 7 do
	local func_up_name = "rocker_switch" .. i .. "_up"

	local dataref = "FlyWithLua/Bravo++/" .. func_up_name
	local description = "Bravo++ command for rocker switch" .. i .. " when it is positioned up"
	local command = string.format("bravo_dispatch('rocker_switch', %d, 'UP')", i)
	log.debug("dataref: " .. dataref)
	log.debug("description: " .. description)
	log.debug("command: " .. command)

	create_command(
		dataref,
		description,
		command, -- Call Lua function when pressed
		"",
		""
	)

	local func_down_name = "rocker_switch" .. i .. "_down"

	local dataref = "FlyWithLua/Bravo++/" .. func_down_name
	local description = "Bravo++ command for rocker switch" .. i .. " when it is positioned down"
	local command = string.format("bravo_dispatch('rocker_switch', %d, 'DOWN')", i)
	log.debug("dataref: " .. dataref)
	log.debug("description: " .. description)
	log.debug("command: " .. command)

	create_command(
		dataref,
		description,
		command, -- Call Lua function when pressed
		"",
		""
	)
end

--------------------------------------
---- TRIM WHEEL
--------------------------------------

-- Trim wheel is handled by the dispatch module.
-- Set up the dataref after initialization (X-Plane may not be ready yet).
local trim_dataref = dataref_table("sim/flightmodel2/controls/elevator_trim")
dispatch.set_trim_dataref(trim_dataref)

-- Thin wrappers that delegate to dispatch module
dispatch_callbacks.trim_nose_up = function()
	return try_catch(dispatch.trim_nose_up, "trim_nose_up")
end

create_command(
	"FlyWithLua/Bravo++/trim_nose_up_handler",
	"Handle trim on bravo for nose up",
	"bravo_dispatch('trim_nose_up')", -- Call Lua function when pressed
	"",
	""
)

dispatch_callbacks.trim_nose_down = function()
	return try_catch(dispatch.trim_nose_down, "trim_nose_down")
end

create_command(
	"FlyWithLua/Bravo++/trim_nose_down_handler",
	"Handle trim on bravo for nose down",
	"bravo_dispatch('trim_nose_down')", -- Call Lua function when pressed
	"",
	""
)

-----------------------------------------------------
--- HANDLE TWIST-KNOB THAT INCREASES/DECREASES VALUES
-----------------------------------------------------

-- Thin wrappers that delegate to dispatch module
dispatch_callbacks.knob_increase = function()
	return try_catch(dispatch.knob_increase, "knob_increase")
end

create_command(
	"FlyWithLua/Bravo++/knob_increase_handler",
	"Handle button on bravo that increments values",
	"bravo_dispatch('knob_increase')", -- Call Lua function when pressed
	"",
	""
)

dispatch_callbacks.knob_decrease = function()
	return try_catch(dispatch.knob_decrease, "knob_decrease")
end

-- Wire the new modular decoder to dispatch-based handlers
bravo_decoder.set_handlers({
	on_selector_changed = function(new)
		-- new is a raw byte for now; attempt to map to selector index if possible
		if type(new) == "number" then
			if new >= 1 and new <= 5 then
				set_current_selector(new)
			else
				-- leave as debug info until mapping is confirmed
				log.info("Decoder: selector change raw=" .. tostring(new))
			end
		else
			log.info("Decoder: selector change (non-numeric) " .. tostring(new))
		end
	end,
	on_rotary_cw = function()
		pcall(dispatch.knob_increase)
	end,
	on_rotary_ccw = function()
		pcall(dispatch.knob_decrease)
	end,
	on_trim_changed = function(v)
		if v == "down" then
			pcall(dispatch.trim_nose_down)
		elseif v == "up" then
			pcall(dispatch.trim_nose_up)
		else
			log.info("Decoder: trim change raw=" .. tostring(v))
		end
	end,
})

-- Subscribe decoder to hid reports
bravo_hid.subscribe(bravo_decoder.on_report)

-- Ensure bravo_hid.poll is called every frame via the centralized dispatcher
dispatch_callbacks.bravo_hid_poll_task = function()
	local t = profiler.start("bravo_hid_poll")
	bravo_hid.poll()
	profiler.stop("bravo_hid_poll", t)
end
-- Use bravo_dispatch so FlyWithLua stores a short string
do_every_frame("bravo_dispatch('bravo_hid_poll_task')")

-- Small tap to log each report received by the hid poller for debugging
-- Only log and persist non-empty reports to avoid flooding the log during normal frames.
local raw_log_path = "raw_hid_log.txt"
local function append_raw_log(line)
	local f = io.open(raw_log_path, "a")
	if f then
		f:write(line .. "")
		f:close()
	end
end

local function report_is_empty(report)
	if not report then
		return true
	end
	for i = 1, #report do
		if (report[i] or 0) ~= 0 then
			return false
		end
	end
	return true
end

local function __bravo_debug_tap(report)
	if report_is_empty(report) then
		return
	end
	-- log a short info line and a hex dump at debug level
	-- log.debug('BRAVO TAP: decoder callback invoked; len=' .. tostring(#report or 0))
	local hex = {}
	for i = 1, #report do
		hex[#hex + 1] = string.format("%02X", report[i])
	end
	local line = string.format("%0.3f [BRAVO++ RAW] %s", os.clock(), table.concat(hex, " "))
	-- log.debug('BRAVO TAP REPORT: ' .. table.concat(hex, ' '))
	append_raw_log(line)
end
local __bravo_tap_id = nil
if HID_INPUT_DEBUG then
	__bravo_tap_id = bravo_hid.subscribe(__bravo_debug_tap)
end

create_command(
	"FlyWithLua/Bravo++/knob_decrease_handler",
	"Handle button on bravo that decrements values",
	"bravo_dispatch('knob_decrease')", -- Call Lua function when pressed
	"",
	""
)

--------------------------------------
---- BUTTON HANDLING
--------------------------------------
-- Button handling is delegated to the dispatch module.
-- Thin wrappers that delegate to dispatch module:

-- Autopilot panel buttons
-- FlyWithLua executes callback strings in the global environment.
-- Route autopilot panel commands via the global bravo_dispatch entrypoint.
dispatch_callbacks.ap_begin = function(button_name)
	return try_catch(function()
		dispatch.button_begin(button_name)
	end, "ap_begin:" .. button_name)
end

dispatch_callbacks.ap_continue = function(button_name)
	return try_catch(function()
		dispatch.button_continue(button_name)
	end, "ap_continue:" .. button_name)
end

dispatch_callbacks.ap_end = function(button_name)
	return try_catch(function()
		dispatch.button_end(button_name)
	end, "ap_end:" .. button_name)
end

local ap_buttons = {
	{ key = "PLT", command = "autopilot_button", description = "AUTOPILOT" },
	{ key = "IAS", command = "ias_button", description = "IAS" },
	{ key = "VS", command = "vs_button", description = "VS" },
	{ key = "ALT", command = "alt_button", description = "ALT" },
	{ key = "REV", command = "rev_button", description = "REV" },
	{ key = "APR", command = "apr_button", description = "APR" },
	{ key = "NAV", command = "nav_button", description = "NAV" },
	{ key = "HDG", command = "hdg_button", description = "HDG" },
}

for _, b in ipairs(ap_buttons) do
	create_command(
		"FlyWithLua/Bravo++/" .. b.command,
		"Bravo++ toggles " .. b.description .. " button",
		string.format("bravo_dispatch('ap_begin', '%s')", b.key),
		string.format("bravo_dispatch('ap_continue', '%s')", b.key),
		string.format("bravo_dispatch('ap_end', '%s')", b.key)
	)
end

--------------------------------------
---- LED HANDLING
--------------------------------------
local LED_LDG_L_GREEN = { 2, 1 }
local LED_LDG_L_RED = { 2, 2 }
local LED_LDG_N_GREEN = { 2, 3 }
local LED_LDG_N_RED = { 2, 4 }
local LED_LDG_R_GREEN = { 2, 5 }
local LED_LDG_R_RED = { 2, 6 }
local LED_ANC_MSTR_WARNG = { 2, 7 }
local LED_ANC_ENG_FIRE = { 2, 8 }
local LED_ANC_OIL = { 3, 1 }
local LED_ANC_FUEL = { 3, 2 }
local LED_ANC_ANTI_ICE = { 3, 3 }
local LED_ANC_STARTER = { 3, 4 }
local LED_ANC_APU = { 3, 5 }
local LED_ANC_MSTR_CTN = { 3, 6 }
local LED_ANC_VACUUM = { 3, 7 }
local LED_ANC_HYD = { 3, 8 }
local LED_ANC_AUX_FUEL = { 4, 1 }
local LED_ANC_PRK_BRK = { 4, 2 }
local LED_ANC_VOLTS = { 4, 3 }
local LED_ANC_DOOR = { 4, 4 }

-- led_state_modified is declared once near the top of the script (shared across mode/selector + LED code)

-- BUTTON LED handling
get_button_led_state = function(button_name)
	if
		util.is_table(button_map_leds_state[dispatch.get_current_mode()]["ALL"])
		and util.is_boolean(button_map_leds_state[dispatch.get_current_mode()]["ALL"][button_name])
	then
		if log_led_state then
			log.debug("get_led_state for mode ALL and button name " .. button_name)
		end
		return button_map_leds_state[dispatch.get_current_mode()]["ALL"][button_name]
	elseif
		util.is_table(button_map_leds_state[dispatch.get_current_mode()][dispatch.get_current_selection()])
		and util.is_boolean(
			button_map_leds_state[dispatch.get_current_mode()][dispatch.get_current_selection()][button_name]
		)
	then
		if log_led_state then
			log.debug(
				"get_led_state for mode "
					.. dispatch.get_current_mode()
					.. ", current selection "
					.. dispatch.get_current_selection()
					.. " and button name "
					.. button_name
			)
		end
		return button_map_leds_state[dispatch.get_current_mode()][dispatch.get_current_selection()][button_name]
	else
		if log_led_state then
			log.debug("Return nil for mode " .. dispatch.get_current_mode() .. " and button_name " .. button_name)
		end
		return nil
	end
end

local function set_button_led_state(button_name, state)
	local current_led_state = get_button_led_state(button_name)
	if current_led_state ~= nil and state ~= current_led_state then
		if log_led_state then
			log.debug("get_led_state for " .. button_name .. " = " .. tostring(current_led_state))
		end
		if
			util.is_table(button_map_leds_state[dispatch.get_current_mode()]["ALL"])
			and util.is_boolean(button_map_leds_state[dispatch.get_current_mode()]["ALL"][button_name])
		then
			button_map_leds_state[dispatch.get_current_mode()]["ALL"][button_name] = state
		elseif
			util.is_table(button_map_leds_state[dispatch.get_current_mode()][dispatch.get_current_selection()])
			and util.is_boolean(
				button_map_leds_state[dispatch.get_current_mode()][dispatch.get_current_selection()][button_name]
			)
		then
			button_map_leds_state[dispatch.get_current_mode()][dispatch.get_current_selection()][button_name] = state
		end
		led_state_modified = true
	else
		if log_led_state then
			if current_led_state ~= nil then
				log.debug(
					"state did not change for mode " .. dispatch.get_current_mode() .. " and button " .. button_name
				)
			else
				log.debug(
					"state does not exist for mode " .. dispatch.get_current_mode() .. " and button " .. button_name
				)
			end
		end
	end
end

local buffer = {}

local function get_led(led)
	-- logMsg("buffer[" .. led[1] .. "][" .. led[2] .. "]")
	return buffer[led[1]][led[2]]
end

local function set_led(led, state)
	if state ~= get_led(led) then
		buffer[led[1]][led[2]] = state
		led_state_modified = true
	end
end

local function all_leds_off()
	for i = 1, #default_button_labels do
		set_button_led_state(default_button_labels[i], false)
	end

	for bank = 2, 4 do
		buffer[bank] = {}
		for bit = 1, 8 do
			buffer[bank][bit] = false
		end
	end

	for i = 1, 7 do
		local key = "SWITCH" .. i .. "_LED"
		dispatch.set_rocker_switch_led(key, false)
	end

	led_state_modified = true
	if log_led_state then
		log.debug("Set all leds to off")
	end
end

-- New helper function to "prime" button LED states for change detection.
-- This temporarily forces the internal state for relevant buttons to 'true'
-- so that handle_led_changes can detect a change to 'false' if needed.
prime_button_led_states_for_mode_change = function()
	-- Iterate through all possible physical button labels as defined in default_button_labels [1]
	local led_detected = false -- Used to check whether there are any leds in this selection
	for i = 1, #default_button_labels do
		local button_label = default_button_labels[i]

		-- Check and set for "ALL" selection within the current mode context
		-- The "ALL" selection is used for LEDs that are common across all selector positions within a mode [2, 3]
		if
			util.is_table(button_map_leds_state[dispatch.get_current_mode()])
			and util.is_table(button_map_leds_state[dispatch.get_current_mode()]["ALL"])
		then
			-- Only prime if the LED state entry actually exists for this button in the "ALL" category [4, 5]
			if util.is_boolean(button_map_leds_state[dispatch.get_current_mode()]["ALL"][button_label]) then
				button_map_leds_state[dispatch.get_current_mode()]["ALL"][button_label] = false
				-- Manually setting led_state_modified to true ensures a HID update will be sent [6, 7].
				-- This is a safeguard in case no other state changes occur that would trigger it.
				if log_led_state then
					log.debug(
						"Setting led to true for [" .. dispatch.get_current_mode() .. "][ALL][" .. button_label .. "]"
					)
				end
				led_state_modified = true
				led_detected = true
			end
		elseif
			util.is_table(button_map_leds_state[dispatch.get_current_mode()])
			and util.is_table(button_map_leds_state[dispatch.get_current_mode()][dispatch.get_current_selection()])
		then
			-- Only prime if the LED state entry actually exists for this button in this specific selection [5, 9]
			if
				util.is_boolean(
					button_map_leds_state[dispatch.get_current_mode()][dispatch.get_current_selection()][button_label]
				)
			then
				button_map_leds_state[dispatch.get_current_mode()][dispatch.get_current_selection()][button_label] =
					false
				-- As above, manually forcing led_state_modified to ensure a HID update.
				if log_led_state then
					log.debug(
						"Setting led to true for ["
							.. dispatch.get_current_mode()
							.. "]["
							.. dispatch.get_current_selection()
							.. "]["
							.. button_label
							.. "]"
					)
				end
				led_state_modified = true
				led_detected = true
			end
		end
	end
	if not led_detected then -- Ensures all leds are off if no leds are used
		all_leds_off()
	end
	if log_led_state then
		log.debug("Internal button LED states 'primed' to true for mode change evaluation.")
	end
end

local function send_hid_data()
	local data = {}

	for bank = 1, 4 do
		data[bank] = 0
	end

	for i = 1, #default_button_labels do
		local button_name = default_button_labels[i]
		if
			util.is_table(button_map_leds_state[dispatch.get_current_mode()]["ALL"])
			and button_map_leds_state[dispatch.get_current_mode()]["ALL"][button_name] == true
		then
			data[1] = bit.bor(data[1], bit.lshift(1, i - 1))
		elseif
			util.is_table(button_map_leds_state[dispatch.get_current_mode()][dispatch.get_current_selection()])
			and button_map_leds_state[dispatch.get_current_mode()][dispatch.get_current_selection()][button_name]
				== true
		then
			data[1] = bit.bor(data[1], bit.lshift(1, i - 1))
		end
	end

	for bank = 2, 4 do
		for abit = 1, 8 do
			if buffer[bank][abit] == true then
				data[bank] = bit.bor(data[bank], bit.lshift(1, abit - 1))
			end
		end
	end

	local bytes_written = hid_send_filled_feature_report(bravo, 0, 65, data[1], data[2], data[3], data[4]) -- 65 = 1 byte (report ID) + 64 bytes (data)

	if bytes_written == 65 then
		led_state_modified = false
	elseif bytes_written == nil or bytes_written == -1 then
		log.error("ERROR Feature report write failed, an error occurred")
	elseif bytes_written < 65 then
		log.error("ERROR Feature report write failed, only " .. bytes_written .. " bytes written")
	end
end

-- Replacement get_led_state_for_dataref written by assistant
--- Evaluate a numeric value against a conditional string.
--- Supported cond syntax: "<9", ">=10", "<=5", ">3", "!=5", "=0", "0"
--- Check whether a string is a valid LED condition.
--- Accepts: "<9", ">=10", "<=5", ">3", "!=5", "=0", "0"
--- Returns true if the format is valid, false otherwise.
local function get_led_state_for_dataref(dr_table, cond, index)
	if dr_table == nil then
		return false
	end
	if util.is_dataref_array(dr_table) then
		-- If an explicit index was provided, use it (cfg uses 1-based indexing; dataref table is 0-based)
		if index ~= nil then
			local idx = tonumber(index)
			if idx == nil then
				return false
			end
			local val = dr_table[idx - 1]
			if val == nil then
				-- Index not present in array -> treat as 'no' (do not light)
				return false
			end
			local vnum = tonumber(val)
			if vnum ~= nil then
				return config.eval_condition(vnum, cond)
			else
				return false -- non-numeric value cannot satisfy numeric condition
			end
		end

		-- No explicit index: iterate only the actual elements of the array dataref.
		local name = dr_table.refname or dr_table.name or dr_table._dataref or dr_table._name or "unknown dataref"

		-- Query the real array size from X-Plane via XPLMGetDataRefInfo
		local arraySize = util.get_dataref_array_size(dr_table)

		-- If we cannot determine the size, fall back to a safe bounded scan
		if arraySize == nil or arraySize <= 0 then
			log.warning("Could not determine array size for dataref: " .. name)
			arraySize = 3
		end

		log.debug("Dataref: " .. name .. " (array size: " .. arraySize .. ")")

		for i = 0, arraySize - 1 do
			local v = dr_table[i]
			local vnum = tonumber(v)
			if vnum == nil then
				break
			end
			log.debug("i: " .. i .. ", vnum: " .. vnum)
			if config.eval_condition(vnum, cond) then
				return true
			end
		end
		return false
	else
		-- Non-array dataref: compare the single value at index 0
		local val = dr_table[0]
		if val == nil then
			return false
		end
		local vnum = tonumber(val)
		if vnum ~= nil then
			return config.eval_condition(vnum, cond)
		else
			return false -- non-numeric value cannot satisfy numeric condition
		end
	end
end
local switch_map_leds = {}
local switch_map_leds_cond = {}
local switch_map_leds_index = {}

for i = 1, 7 do
	local key = "SWITCH" .. i .. "_LED"
	if util.is_string(nav_bindings[key]) then
		local binding = util.create_table(nav_bindings[key])
		switch_map_leds[key] = dataref_table(binding[1])
		switch_map_leds_cond[key] = config.compile_condition(binding[2], key)
		if #binding == 3 then
			switch_map_leds_index[key] = binding[3]
		end
	end
end

get_led_state_for_switch = function(switch_label)
	return dispatch.get_rocker_switch_led(switch_label) or false
end

local function handle_rocker_switch_led_changes()
	-- Iterate through the predefined rocker switch labels (SWITCH1_LED, SWITCH2_LED, etc.)
	-- `switch_map_leds` stores the `dataref_table` objects, `switch_map_leds_cond` stores the condition,
	-- and `switch_map_leds_index` stores the array index for each switch [4].
	for i = 1, 7 do -- There are 7 rocker switches [5]
		local switch_label_key = "SWITCH" .. i .. "_LED" -- Construct the key like "SWITCH1_LED"

		local dataref_table_obj = switch_map_leds[switch_label_key] -- Get the dataref_table object

		-- Only proceed if a DataRef is actually configured for this switch LED
		if util.is_dataref_magic_table(dataref_table_obj) then
			local condition_value = switch_map_leds_cond[switch_label_key]
			local dataref_index = switch_map_leds_index[switch_label_key]

			-- Call the existing helper function to get the current LED state from the DataRef
			local current_state_from_dataref =
				get_led_state_for_dataref(dataref_table_obj, condition_value, dataref_index)

			-- Check if the state has changed to minimize unnecessary updates
			if dispatch.get_rocker_switch_led(switch_label_key) ~= current_state_from_dataref then
				dispatch.set_rocker_switch_led(switch_label_key, current_state_from_dataref)
				led_state_modified = true -- Mark `led_state_modified` to trigger a HID update for the device
			end
		end
	end
end

local bus_voltage = dataref_table("sim/cockpit2/electrical/bus_volts")
local master_state = false

-- Landing gear LEDs
local gear = nil
if nav_bindings["GEAR_DEPLOYMENT_LED"] ~= nil then
	local binding = util.create_table(nav_bindings["GEAR_DEPLOYMENT_LED"])
	gear = dataref_table(binding[1])
end

local annunciator_map_leds = {}
local annunciator_map_leds_cond = {}

for i = 1, #annunciator_labels do
	local key = annunciator_labels[i] .. "_LED"
	if util.is_string(nav_bindings[key]) then
		local binding = util.create_table(nav_bindings[key])
		annunciator_map_leds[annunciator_labels[i]] = dataref_table(binding[1])
		annunciator_map_leds_cond[annunciator_labels[i]] = config.compile_condition(binding[2], key)
	elseif util.is_string(nav_bindings[annunciator_labels[i] .. "_1_LED"]) then
		annunciator_map_leds[annunciator_labels[i]] = {}
		annunciator_map_leds_cond[annunciator_labels[i]] = {}
		local idx = 1
		local key = annunciator_labels[i] .. "_" .. tostring(idx) .. "_LED"
		-- logMsg("key: " .. key)
		while util.is_string(nav_bindings[key]) do
			local binding = util.create_table(nav_bindings[key])
			annunciator_map_leds[annunciator_labels[i]][idx] = dataref_table(binding[1])
			annunciator_map_leds_cond[annunciator_labels[i]] = config.compile_condition(binding[2], key)
			idx = idx + 1
			key = annunciator_labels[i] .. "_" .. tostring(idx) .. "_LED"
			-- logMsg("key: " .. key)
		end
	end
end

local function get_led_state_for_annunciator(annunciator_label)
	local dataref = annunciator_map_leds[annunciator_label]
	-- logMsg("get dataref for: " .. annunciator_label)
	if util.is_dataref_magic_table(dataref) then
		return get_led_state_for_dataref(dataref, annunciator_map_leds_cond[annunciator_label])
	elseif util.is_table(dataref) then
		for i = 1, #dataref do
			if get_led_state_for_dataref(dataref[i], annunciator_map_leds_cond[annunciator_label]) == true then
				return true
			end
		end
		return false
	end
end

local function handle_button_led_changes()
	for i = 1, #default_button_labels do
		local led_state_for_dataref = nil
		local led_state_for_button = nil
		local button_label = default_button_labels[i]

		-- log.debug("Before if: [" .. dispatch.get_current_mode() .. "][" .. dispatch.get_current_selection() .. "][" .. button_label .. "]")
		if util.is_table(button_map_leds[dispatch.get_current_mode()]["ALL"]) then
			local dataref = button_map_leds[dispatch.get_current_mode()]["ALL"][button_label]
			if dataref ~= nil then
				local index = nil
				if util.is_table(button_map_leds_index[dispatch.get_current_mode()]["ALL"]) then
					index = button_map_leds_index[dispatch.get_current_mode()]["ALL"][button_label]
				end

				led_state_for_dataref = get_led_state_for_dataref(
					dataref,
					button_map_leds_cond[dispatch.get_current_mode()]["ALL"][button_label],
					index
				)
				led_state_for_button = button_map_leds_state[dispatch.get_current_mode()]["ALL"][button_label]
			end
		elseif util.is_table(button_map_leds[dispatch.get_current_mode()][dispatch.get_current_selection()]) then
			local dataref = button_map_leds[dispatch.get_current_mode()][dispatch.get_current_selection()][button_label]

			if dataref ~= nil then
				local index = nil
				if
					util.is_table(button_map_leds_index[dispatch.get_current_mode()][dispatch.get_current_selection()])
				then
					index =
						button_map_leds_index[dispatch.get_current_mode()][dispatch.get_current_selection()][button_label]
				end

				led_state_for_dataref = get_led_state_for_dataref(
					dataref,
					button_map_leds_cond[dispatch.get_current_mode()][dispatch.get_current_selection()][button_label],
					index
				)
				led_state_for_button =
					button_map_leds_state[dispatch.get_current_mode()][dispatch.get_current_selection()][button_label]
			end
		end
		-- Check if we need to update the state of the button
		if led_state_for_dataref ~= led_state_for_button then
			set_button_led_state(button_label, led_state_for_dataref)
		end
	end
end

local function handle_gear_led_changes()
	-- Landing gear
	local gear_leds = {}

	if gear ~= nil then
		for i = 1, 3 do
			gear_leds[i] = { nil, nil } -- green, red

			if gear[i - 1] == 0 then
				-- Gear stowed
				gear_leds[i][1] = false
				gear_leds[i][2] = false
			elseif gear[i - 1] == 1 then
				-- Gear deployed
				gear_leds[i][1] = true
				gear_leds[i][2] = false
			else
				-- Gear moving
				gear_leds[i][1] = false
				gear_leds[i][2] = true
			end
		end
	else
		-- Fixed gear
		for i = 1, 3 do
			gear_leds[i] = { nil, nil } -- green, red

			-- Gear deployed
			gear_leds[i][1] = false
			gear_leds[i][2] = false
		end
	end

	set_led(LED_LDG_N_GREEN, gear_leds[1][1])
	set_led(LED_LDG_N_RED, gear_leds[1][2])
	set_led(LED_LDG_L_GREEN, gear_leds[2][1])
	set_led(LED_LDG_L_RED, gear_leds[2][2])
	set_led(LED_LDG_R_GREEN, gear_leds[3][1])
	set_led(LED_LDG_R_RED, gear_leds[3][2])
end

local function handle_annunciator_row1_led_changes()
	-- MASTER WARNING
	set_led(LED_ANC_MSTR_WARNG, get_led_state_for_annunciator("MASTER_WARNING"))

	-- ENGINE FIRE
	set_led(LED_ANC_ENG_FIRE, get_led_state_for_annunciator("FIRE_WARNING"))

	-- LOW OIL PRESSURE
	set_led(LED_ANC_OIL, get_led_state_for_annunciator("OIL_LOW_PRESSURE"))

	-- LOW FUEL PRESSURE
	set_led(LED_ANC_FUEL, get_led_state_for_annunciator("FUEL_LOW_PRESSURE"))

	-- ANTI ICE
	set_led(LED_ANC_ANTI_ICE, get_led_state_for_annunciator("ANTI_ICE"))

	-- STARTER ENGAGED
	set_led(LED_ANC_STARTER, get_led_state_for_annunciator("STARTER_ENGAGED"))

	-- APU
	set_led(LED_ANC_APU, get_led_state_for_annunciator("APU"))
end

local function handle_annunciator_row2_led_changes()
	-- MASTER CAUTION
	set_led(LED_ANC_MSTR_CTN, get_led_state_for_annunciator("MASTER_CAUTION"))

	-- VACUUM
	set_led(LED_ANC_VACUUM, get_led_state_for_annunciator("VACUUM"))

	-- LOW HYD PRESSURE
	set_led(LED_ANC_HYD, get_led_state_for_annunciator("HYD_LOW_PRESSURE"))

	-- AUX FUEL PUMP
	set_led(LED_ANC_AUX_FUEL, get_led_state_for_annunciator("AUX_FUEL_PUMP"))

	-- PARKING BRAKE
	set_led(LED_ANC_PRK_BRK, get_led_state_for_annunciator("PARKING_BRAKE"))

	-- LOW VOLTS
	set_led(LED_ANC_VOLTS, get_led_state_for_annunciator("VOLTS_LOW"))

	-- DOOR
	set_led(LED_ANC_DOOR, get_led_state_for_annunciator("DOOR"))
end

-- A time delay is required on the initial loading of the aircraft in order to set the leds correctly
local leds_first_sync_done = false
local leds_first_sync_timer = os.clock()
local led_first_time_delay = 4 -- 10 second delay before setting the leds

handle_led_changes = function()
	if leds_first_sync_done then
		if bus_voltage[0] > 0 then
			master_state = true

			try_catch(handle_button_led_changes, "handle_button_led_changes")

			-- Handle the remaining leds
			try_catch(handle_gear_led_changes, "handle_gear_led_changes")
			try_catch(handle_annunciator_row1_led_changes, "handle_annunciator_row1_led_changes")
			try_catch(handle_annunciator_row2_led_changes, "handle_annunciator_row2_led_changes")

			-- Handle the rocker switches
			try_catch(handle_rocker_switch_led_changes, "handle_rocker_switch_led_changes")
		elseif master_state == true then
			log.debug("No voltage detected. Turning all leds off.")
			-- No bus voltage, disable all LEDs
			master_state = false
			try_catch(all_leds_off, "all_leds_off")
		end

		-- If we have any LED changes, send them to the device
		if led_state_modified == true then
			try_catch(send_hid_data, "send_hid_data")
		end
	elseif os.clock() - leds_first_sync_timer > led_first_time_delay then
		leds_first_sync_done = true
	end
end

-- Initialize the initial state
all_leds_off()

local last_call = os.clock()

local function do_more_often(func_to_execute, description, interval_seconds)
	local current_time = os.clock()
	-- Check if enough time has passed since the last successful call
	-- The condition (current_time - last_call) >= interval_seconds correctly calculates elapsed time [Conversation History]
	if (current_time - last_call) >= interval_seconds then
		-- Execute the passed function, with its given source name for error logging
		try_catch(func_to_execute, description)
		last_call = current_time -- Update the last call time only if the function was executed
	end
end

local function handle_led_changes_task()
	local t = profiler.start("handle_led_changes")
	do_more_often(handle_led_changes, "handle_led_changes", 0.25)
	profiler.stop("handle_led_changes", t)
end

dispatch_callbacks.handle_led_changes_task = handle_led_changes_task

-- Register the corrected function to be called every frame
do_every_frame("bravo_dispatch('handle_led_changes_task')")

-- Ensure device LEDs are reset when FlyWithLua / X-Plane exits
local function do_on_exit_task()
	try_catch(function()
		log.info("Calling do_on_exit")
		if bravo == nil then
			return
		end

		-- Turn off all internal LED state
		try_catch(all_leds_off, "all_leds_off_do_on_exit")

		-- Send cleared HID report
		try_catch(send_hid_data, "send_hid_data_do_on_exit")

		-- Optionally close the hid device if available
		if bravo then
			try_catch(function()
				hid_close(bravo)
			end, "hid_close_do_on_exit")
			bravo = nil
		end

		-- Small delay to allow OS/driver to flush the report if necessary
		-- local t0 = os.clock(); while os.clock() - t0 < 0.08 do end
	end, "do_on_exit")
end

dispatch_callbacks.do_on_exit_task = do_on_exit_task

do_on_exit("bravo_dispatch('do_on_exit_task')")
