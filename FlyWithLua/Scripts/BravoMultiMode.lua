-- Composition root (FEAT-021): Load all modules via bravo++ init.lua
local bravo = require("bravo++")

-- Core utilities
local util = bravo.util
local log = bravo.log
local config = bravo.config
local ui = bravo.ui
local MapBuilder = bravo.mapbuilder

-- LED Engine modular components (FEAT-017)
local led_engine = bravo.led_engine
local led_hid_bridge = bravo.led_hid_bridge
local annunciator_leds = bravo.annunciator_leds
local gear_leds = bravo.gear_leds
-- switch_leds module removed (BUGFIX-008): rocker switches have no physical LEDs

-- High Priority Module Extractions (FEAT-018)
local profiler = bravo.profiler
local config_loader = bravo.config_loader
local rocker_switches = bravo.rocker_switches
local button_lifecycle = bravo.button_lifecycle

-- Medium Priority Module Extractions (FEAT-019)
local input_handlers = bravo.input_handlers
local mode_manager = bravo.mode_manager

-- Initialize profiler (FEAT-018)
profiler.init({ enabled = false, log_interval = 60 })

-- Global wrapper for FlyWithLua profiler log task (do_every_frame string callback)
function profiler_log_task() -- luacheck: ignore (used by do_every_frame string callback)
    profiler.log_task()
end

-- Global wrapper for FlyWithLua profiler toggle (create_command callback)
function profiler_toggle() -- luacheck: ignore (used by create_command callback)
    profiler.toggle()
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

-- New modular HID/decoder modules (loaded via composition root)
local bravo_hid = bravo.hardware
local bravo_decoder = bravo.decoder
local bravo_state = bravo.state
local bravo_debug = bravo.debug
local dispatch = bravo.dispatch

local HID_INPUT_DEBUG = false
bravo_debug.enable(HID_INPUT_DEBUG)

-- Detect Windows vs POSIX (package.config first char == directory separator)
local is_windows = (package.config and package.config:sub(1, 1) == "\\")

local bravo_device = hid_open(0x294B, 0x1901) -- Honeycomb Bravo VID/PID

-- Exit immediately if the Bravo device cannot be opened. Simulated mode removed.
if not bravo_device then
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

-- Initialize config loader (FEAT-018)
config_loader.init({
    file_provider = function(path)
        return util.list_files(path)
    end,
    aircraft_dir = aircraft_dir,
})

-- Load global user preferences first (optional file, won't fail if missing).
-- Aircraft config loaded below will override any overlapping keys.
local prefs_path = MODULES_DIRECTORY .. "bravo++" .. DIRECTORY_SEPARATOR .. "preferences.cfg"
if config_loader.read_preferences(prefs_path, nav_bindings) then
    log.info("Loaded global preferences from " .. prefs_path)
end

-- Load aircraft-specific config (takes precedence over global preferences).
-- Detection order:
--   1. bravo_multi-mode.<aircraft_name>.cfg       (exact match, e.g. C90B)
--   2. bravo_multi-mode.<aircraft_name>.*.cfg     (variant match, e.g. C90B.EVO)
--   3. bravo_multi-mode.cfg                       (generic fallback)
-- If none are found, stop the script.

local config_result = config_loader.detect_config(aircraft_name)
local nav_cfg_file_full_path = config_result.path
local file_ok = config_result.found

if file_ok then
    file_ok = config_loader.read_file(nav_cfg_file_full_path, nav_bindings)
end

-- No config found — stop script
if not file_ok then
    log.warning(
        "No config file found in "
            .. aircraft_dir
            .. ". Tried bravo_multi-mode."
            .. aircraft_name
            .. ".cfg, variant configs, and bravo_multi-mode.cfg. Bravo script will be stopped."
    )
    return -- Stop script if config is missing
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

-- FEAT-019: Safe command execution wrapper (resolves _G.command_once bypass)
-- All command invocations flow through this wrapper with try_catch error handling.
local function safe_command(cmd)
    try_catch(function()
        command_once(cmd)
    end, "safe_command:" .. tostring(cmd))
end

-- Initialize the dispatch module with bindings and validation context
log.info("Initializing button action map, twist knob action map, and rocker switch states via dispatch module...")
dispatch.init(nav_bindings, {
    modes = modes,
    default_selections = default_selections,
    default_button_labels = default_button_labels,
    selection_map_labels = selection_map_labels,
    button_map_labels = button_map_labels,
    -- FEAT-019: Inject safe command executor (resolves _G.command_once bypass)
    command_fn = safe_command,
})

-- Initialize mode manager (FEAT-019)
mode_manager.init({
    dispatch_module = dispatch,
    modes_array = modes,
    selection_map_labels = selection_map_labels,
    default_selections = default_selections,
    default_button_labels = default_button_labels,
    button_map_labels = button_map_labels,
})

-- Input handlers initialized after set_current_selector (FEAT-019)
-- See below for input_handlers.init() call

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

-- Build a context table for the UI module so it stays decoupled from globals.
-- Mode cycling state (conceptual_mode_order, mode_group_info) is managed by mode_manager (FEAT-019).
local function build_ui_context()
    local base_context = mode_manager.build_ui_context()

    return {
        current_mode = base_context.current_mode,
        current_selection = base_context.current_selection,
        current_cf_mode = base_context.current_cf_mode,
        current_cf_mode_upper = base_context.current_cf_mode_upper,
        current_switch_mode = base_context.current_switch_mode,
        current_selection_label = base_context.current_selection_label,
        conceptual_mode_order = base_context.conceptual_mode_order,
        mode_group_info = base_context.mode_group_info,
        selection_map_labels = base_context.selection_map_labels,
        button_is_switch_map = base_context.button_is_switch_map,
        default_button_labels = base_context.default_button_labels,
        current_buttons = base_context.current_buttons,
        switch_map_labels = switch_map_labels,
        twist_knob_map_actions = base_context.twist_knob_map_actions,
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
    ui.on_close({ hid_close_fn = hid_close, bravo = bravo_device })
end

dispatch_callbacks.on_close_floating_window = on_close_floating_window_impl

-- Global wrapper for FlyWithLua float window callback
function on_close_floating_window(my_floating_wnd)
    return bravo_dispatch("on_close_floating_window", my_floating_wnd)
end

--------------------------------------------------------------
--- CREATE THE FUNCTIONS FOR REFRESHING THE MODE AND SELECTOR
--------------------------------------------------------------
-- Selector index is now managed by mode_manager (FEAT-019).

local function set_current_selector(idx)
    mode_manager.set_selector_index(idx)
    dispatch.set_selector_index(idx, function()
        prime_button_led_states_for_mode_change()
        led_state_modified = true
        handle_led_changes()
    end)
end

-- Initialize input handlers (FEAT-019)
-- Must be after set_current_selector is defined (used as selector_handler_fn)
input_handlers.init({
    dispatch_module = dispatch,
    decoder_handler_fn = function(handlers)
        bravo_decoder.set_handlers(handlers)
    end,
    selector_handler_fn = set_current_selector,
})

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

-- Function to cycle the mode down one (FEAT-019: delegates to mode_manager)
local function cycle_mode_down()
    return try_catch(function()
        mode_manager.cycle_mode_down()
        prime_button_led_states_for_mode_change()
        led_state_modified = true
        handle_led_changes()
    end, "cycle_mode_down")
end

dispatch_callbacks.cycle_mode_down = cycle_mode_down

-- Function to cycle the mode up one (FEAT-019: delegates to mode_manager)
local function cycle_mode_up()
    return try_catch(function()
        mode_manager.cycle_mode_up()
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
        mode_manager.activate_mode_select()
    end, "toggle_mode_select_true")
end

dispatch_callbacks.toggle_mode_select_true = toggle_mode_select_true

local function toggle_mode_select_false()
    return try_catch(function()
        mode_manager.deactivate_mode_select()
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

-- Function to cycle through outer/inner modes (FEAT-019: delegates to mode_manager)
local function cycle_cf_mode()
    return try_catch(function()
        mode_manager.cycle_cf_mode()
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

-- Function to cycle through up/down switch modes (FEAT-019: delegates to mode_manager)
local function cycle_switch_mode()
    return try_catch(function()
        mode_manager.cycle_switch_mode()
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
---- ROCKER SWITCHES (FEAT-018: rocker_switches module)
--------------------------------------

-- Route rocker switch commands through the dispatch module.
dispatch_callbacks.rocker_switch = function(rocker_number, dir)
    return try_catch(function()
        dispatch.rocker_switch(rocker_number, dir)
    end, "rocker_switch:" .. rocker_number .. ":" .. dir)
end

-- Initialize rocker switch commands via module (FEAT-018)
rocker_switches.init({
    dispatch_callback_fn = function(name, ...)
        bravo_dispatch(name, ...)
    end,
    num_switches = 7,
    create_command_fn = create_command,
})
rocker_switches.register_all()

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

-- Wire decoder handlers through input_handlers (FEAT-019)
-- All command invocations flow through dispatch module with try_catch error handling.
input_handlers.register_decoder_handlers()

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
---- BUTTON HANDLING (FEAT-018: button_lifecycle module)
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

-- AP button definitions (FEAT-018: injected into button_lifecycle module)
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

-- Initialize button lifecycle via module (FEAT-018)
button_lifecycle.init({
    ap_buttons = ap_buttons,
    create_command_fn = create_command,
})
button_lifecycle.register_all()

--------------------------------------
---- LED HANDLING (FEAT-017: Modular LED Engine)
--------------------------------------

-- LED position constants (injected into gear_leds module)
local LED_CONSTANTS = {
    LED_LDG_N_GREEN = { 2, 3 },
    LED_LDG_N_RED = { 2, 4 },
    LED_LDG_L_GREEN = { 2, 1 },
    LED_LDG_L_RED = { 2, 2 },
    LED_LDG_R_GREEN = { 2, 5 },
    LED_LDG_R_RED = { 2, 6 },
}

-- Dataref evaluator function (injected into annunciator_leds and switch handler)
local function get_led_state_for_dataref(dr_table, cond, index)
    if dr_table == nil then
        return false
    end
    if util.is_dataref_array(dr_table) then
        if index ~= nil then
            local idx = tonumber(index)
            if idx == nil then
                return false
            end
            local val = dr_table[idx - 1]
            if val == nil then
                return false
            end
            local vnum = tonumber(val)
            if vnum ~= nil then
                return config.eval_condition(vnum, cond)
            else
                return false
            end
        end

        local name = dr_table.refname or dr_table.name or dr_table._dataref or dr_table._name or "unknown dataref"

        local arraySize = util.get_dataref_array_size(dr_table)

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
        local val = dr_table[0]
        if val == nil then
            return false
        end
        local vnum = tonumber(val)
        if vnum ~= nil then
            return config.eval_condition(vnum, cond)
        else
            return false
        end
    end
end

-- Build switch LED bindings (needed for switch state handler)
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

-- Build switch bindings table for switch state handler
local switch_led_bindings = {}
for i = 1, 7 do
    local key = "SWITCH" .. i .. "_LED"
    if switch_map_leds[key] ~= nil then
        switch_led_bindings[key] = {
            switch_map_leds[key],
            switch_map_leds_cond[key],
            switch_map_leds_index[key],
        }
    end
end

-- Standalone handler for rocker switch LED state updates (BUGFIX-008).
-- Replaces the removed switch_leds.lua module.
-- Updates dispatch state for UI display only — no physical LEDs on switches.
local function handle_rocker_switch_led_changes()
    for i = 1, 7 do
        local switch_label = "SWITCH" .. i .. "_LED"
        local binding = switch_led_bindings and switch_led_bindings[switch_label]
        if binding then
            local current_state = get_led_state_for_dataref(binding[1], binding[2], binding[3])
            -- Only update dispatch state for UI display — NO LED buffer writes
            if dispatch.set_rocker_switch_led then
                dispatch.set_rocker_switch_led(switch_label, current_state)
            end
        end
    end
end

-- Bus voltage dataref
local bus_voltage = dataref_table("sim/cockpit2/electrical/bus_volts")

-- Landing gear dataref
local gear_dataref = nil
if nav_bindings["GEAR_DEPLOYMENT_LED"] ~= nil then
    local binding = util.create_table(nav_bindings["GEAR_DEPLOYMENT_LED"])
    gear_dataref = dataref_table(binding[1])
end

-- Build annunciator bindings table for annunciator_leds module
local annunciator_led_bindings = {}

for i = 1, #annunciator_labels do
    local key = annunciator_labels[i] .. "_LED"
    if util.is_string(nav_bindings[key]) then
        local binding = util.create_table(nav_bindings[key])
        annunciator_led_bindings[annunciator_labels[i]] = {
            dataref_table(binding[1]),
            config.compile_condition(binding[2], key),
        }
    elseif util.is_string(nav_bindings[annunciator_labels[i] .. "_1_LED"]) then
        -- Indexed annunciator (e.g. DOOR_1_LED, DOOR_2_LED)
        local idx = 1
        local indexed_key = annunciator_labels[i] .. "_" .. tostring(idx) .. "_LED"
        while util.is_string(nav_bindings[indexed_key]) do
            local binding = util.create_table(nav_bindings[indexed_key])
            annunciator_led_bindings[annunciator_labels[i]] = annunciator_led_bindings[annunciator_labels[i]] or {}
            annunciator_led_bindings[annunciator_labels[i]][idx] = {
                dataref_table(binding[1]),
                config.compile_condition(binding[2], indexed_key),
            }
            idx = idx + 1
            indexed_key = annunciator_labels[i] .. "_" .. tostring(idx) .. "_LED"
        end
    end
end

-- Initialize LED engine modules
log.info("Initializing LED Engine modules (FEAT-017)...")

-- 1. LED Engine (core state manager)
led_engine.init({
    dispatch = dispatch,
    button_map_leds_state = button_map_leds_state,
    default_button_labels = default_button_labels,
    bus_voltage_ref = bus_voltage,
})

-- 2. Annunciator LEDs
annunciator_leds.init({
    annunciator_bindings = annunciator_led_bindings,
    eval_fn = get_led_state_for_dataref,
})

-- 3. Gear LEDs
gear_leds.init({
    gear_dataref = gear_dataref,
    led_constants = LED_CONSTANTS,
})

-- 4. HID Bridge
led_hid_bridge.init({
    device_handle = bravo_device,
    bit_lib = bit,
    button_map_leds_state = button_map_leds_state,
    led_engine_module = led_engine,
})

-- Register sub-handler callbacks with led_engine (injection-based wiring)
led_engine.set_sub_handlers({
    on_annunciator_row1 = function()
        annunciator_leds.evaluate_row1(led_engine)
    end,
    on_annunciator_row2 = function()
        annunciator_leds.evaluate_row2(led_engine)
    end,
    on_gear = function()
        gear_leds.evaluate(led_engine)
    end,
    on_switches = handle_rocker_switch_led_changes,
})

-- Wire get_button_led_state through led_engine (for UI context)
get_button_led_state = function(button_name)
    return led_engine.get_button_led_state(button_name)
end

-- Wire get_led_state_for_switch (for UI context)
get_led_state_for_switch = function(switch_label)
    return dispatch.get_rocker_switch_led(switch_label) or false
end

-- Wire prime_button_led_states_for_mode_change through led_engine
prime_button_led_states_for_mode_change = function()
    led_engine.prime_for_mode_change()
    led_state_modified = true
end

-- Send HID data through led_hid_bridge (wrapper for backward compat)
local function send_hid_data()
    led_hid_bridge.assemble_and_send(led_engine.get_buffer_snapshot(), default_button_labels, dispatch)
end

-- Handle LED changes through led_engine orchestrator
handle_led_changes = function()
    if
        led_engine.handle_led_changes({
            bus_voltage = bus_voltage[0],
            button_map_leds = button_map_leds,
            button_map_leds_cond = button_map_leds_cond,
            button_map_leds_index = button_map_leds_index,
            get_led_state_for_dataref = get_led_state_for_dataref,
        })
    then
        try_catch(send_hid_data, "send_hid_data")
    end
end

-- Initialize the initial state
led_engine.all_off()

local last_call = os.clock()

local function do_more_often(func_to_execute, description, interval_seconds)
    local current_time = os.clock()
    if (current_time - last_call) >= interval_seconds then
        try_catch(func_to_execute, description)
        last_call = current_time
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
        if bravo_device == nil then
            return
        end

        -- Turn off all internal LED state
        try_catch(function()
            led_engine.all_off()
        end, "all_leds_off_do_on_exit")

        -- Send cleared HID report
        try_catch(send_hid_data, "send_hid_data_do_on_exit")

        -- Optionally close the hid device if available
        if bravo_device then
            try_catch(function()
                hid_close(bravo_device)
            end, "hid_close_do_on_exit")
            bravo_device = nil
        end
    end, "do_on_exit")
end

dispatch_callbacks.do_on_exit_task = do_on_exit_task

do_on_exit("bravo_dispatch('do_on_exit_task')")
