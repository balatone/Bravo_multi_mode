-- bravo++.plugincheck -- Detect conflicting Honeycomb Bridge plugin and warn the user.
--
-- The Honeycomb Bridge (AFC_Bridge) also communicates with Bravo hardware via HID,
-- which can cause input conflicts when this script is running simultaneously.
--
-- Detection strategy:
--   1. Check for the AFC_Bridge folder in X-Plane's plugins directory.
--      We look for the extracted plugin (win_x64/AFC_Bridge.xpl) rather than
--      just the .7z archive, since only an extracted/active install can conflict.
--   2. Optionally check if the bridge process is running via tasklist on Windows.

local log = require("bravo++.log")

local M = {}

--- Path to X-Plane's plugins directory (FlyWithLua global RESOURCE_PATH points here)
local PLUGINS_DIR = RESOURCE_PATH --[[@as string]]

-- ---------------------------------------------------------------------------
-- Detection helpers
-- ---------------------------------------------------------------------------

--- Check whether the Honeycomb Bridge plugin folder exists and contains an .xpl file.
--- Returns true if the bridge appears to be installed (extracted, not just archived).
local function is_bridge_folder_present()
	local bridge_dir = PLUGINS_DIR .. "AFC_Bridge"

	-- Use io.popen to list files in win_x64 subfolder for AFC_Bridge.xpl
	local is_windows = (package.config and package.config:sub(1, 1) == "\\")

	-- Build a dir/ls command to check for the platform subfolder inside AFC_Bridge
	local cmd = is_windows and ('dir /b "' .. bridge_dir .. '" 2>nul') or ('ls "' .. bridge_dir .. '" 2>/dev/null')

	-- luacheck: ignore (io.popen is available in FlyWithLua sandbox)
	local handle = io.popen(cmd)
	if not handle then
		return false
	end

	for line in handle:lines() do
		if string.find(line, "win_x64") or string.find(line, "mac_x64") then
			handle:close()
			return true -- Subfolder found, bridge is extracted
		end
	end
	handle:close()
	return false
end

--- Check if the Honeycomb Bridge process is currently running (Windows only).
--- Returns true if honeycomb-configurator.exe or AFC_Bridge.xpl parent processes are active.
local function is_bridge_process_running()
	local is_windows = (package.config and package.config:sub(1, 1) == "\\")
	if not is_windows then
		return false -- Linux/mac detection can be added later if needed
	end

	-- Check for honeycomb-configurator.exe process
	local cmd = 'tasklist /FI "IMAGENAME eq honeycomb-configurator.exe" 2>NUL'

	-- luacheck: ignore (io.popen is available in FlyWithLua sandbox)
	local handle = io.popen(cmd)
	if not handle then
		return false
	end

	for line in handle:lines() do
		if string.find(line, "honeycomb-configurator.exe") then
			handle:close()
			return true
		end
	end
	handle:close()
	return false
end

--- Check if the Honeycomb Bridge plugin is installed and/or running.
--- Returns a table with detection results:
---   { folder_present = bool, process_running = bool }
function M.check_bridge_status()
	local status = {
		folder_present = is_bridge_folder_present(),
		process_running = is_bridge_process_running(),
	}

	if status.folder_present then
		log.info("Honeycomb Bridge plugin folder detected at " .. PLUGINS_DIR .. "AFC_Bridge")
	end
	if status.process_running then
		log.warning("Honeycomb Bridge process (honeycomb-configurator.exe) is currently running")
	end

	return status
end

--- Returns true if the bridge should trigger a warning.
function M.should_warn()
	local s = M.check_bridge_status()
	return s.folder_present or s.process_running
end

-- ---------------------------------------------------------------------------
-- Warning window (ImGui-based floating window)
-- ---------------------------------------------------------------------------

local imgui = imgui --[[@as table]] -- luacheck: ignore (global from FlyWithLua)

local warning_wnd = nil
local warning_dismissed = false

--- Build the ImGui content for the warning dialog.
-- luacheck: ignore 212
function M.build_warning_gui(wnd, x, y)
	imgui.PushStyleColor(imgui.constant.Col.WindowBg, 0xFF2A1A1A) -- Dark red background

	-- Title bar text
	imgui.SetWindowFontScale(1.3)
	imgui.TextColored(1.0, 0.4, 0.4, 1.0, "⚠ Honeycomb Bridge Detected")
	imgui.NewLine()
	imgui.SetWindowFontScale(1.0)

	-- Separator
	imgui.Separator()
	imgui.NewLine()

	-- Warning message with word wrap
	local msg = [[The Honeycomb Bridge plugin (AFC_Bridge) has been detected in your X-Plane plugins directory.

This plugin also talks to Honeycomb Bravo hardware via HID and may
interfere with this script's operation, causing:

  • Duplicate or conflicting button/switch inputs
  • Unpredictable LED state changes
  • Throttle quadrant conflicts

If you experience issues, please disable the Honeycomb Bridge plugin via X-Plane's Plugin Manager.]]

	imgui.PushTextWrapPos(400)
	imgui.TextColored(1.0, 0.95, 0.8, 1.0, msg)
	imgui.PopTextWrapPos()
	imgui.NewLine()
	imgui.Separator()
	imgui.NewLine()

	-- Dismiss button
	local btn_w = 200
	local btn_h = 30
	local cursor_x = imgui.GetCursorPosX()
	imgui.SetCursorPosX(cursor_x + (450 - btn_w) / 2) -- Center the button in a ~450px window

	if imgui.Button("I understand, dismiss this warning", btn_w, btn_h) then
		warning_dismissed = true
	end

	imgui.PopStyleColor()
end

--- Create and show the warning floating window. Call once at startup if bridge is detected.
function M.show_warning_if_needed()
	if not M.should_warn() then
		return -- No conflict, nothing to do
	end

	warning_wnd = float_wnd_create(480, 320, 1, true)
	float_wnd_set_title(warning_wnd, "Plugin Conflict Warning")
	float_wnd_set_imgui_builder(warning_wnd, "bravo_plugincheck_warning_gui")
	-- Center the window on screen
	float_wnd_set_position(warning_wnd, SCREEN_WIDTH * 0.35, SCREEN_HEIGHT * 0.2)

	log.warning("Honeycomb Bridge conflict warning displayed to user")
end

--- Global wrapper for FlyWithLua's imgui_builder callback (must be global).
-- luacheck: ignore (used by float_wnd_set_imgui_builder string callback)
function bravo_plugincheck_warning_gui(_wnd, _x, _y)
	M.build_warning_gui(_wnd, _x, _y)
	if warning_dismissed then
		float_wnd_destroy(warning_wnd)
		warning_wnd = nil
	end
end

return M
