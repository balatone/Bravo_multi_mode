local log = require("bravo++.log")

-- **************************************************************
-- Script that will toggle com1 and com2 without issues
-- **************************************************************

log.info("Loading G1000 com toggling script...")

if log.LOG_LEVEL == nil then
	log.LOG_LEVEL = log.LOG_DEBUG
end

local G1000_COM_STATE_DR = create_dataref_table("FlyWithLua/Bravo++/G1000_COM_STATE", "Int")

local com1_freq = dataref_table("sim/cockpit2/radios/actuators/com1_frequency_hz_833")
local com1_stby_freq = dataref_table("sim/cockpit2/radios/actuators/com1_standby_frequency_hz_833")
local com2_freq = dataref_table("sim/cockpit2/radios/actuators/com2_frequency_hz_833")
local com2_stby_freq = dataref_table("sim/cockpit2/radios/actuators/com2_standby_frequency_hz_833")

local FLAG_PFD_COM2 = 0x01
local FLAG_MFD_COM2 = 0x02

-- ============================================================
-- Persistent state: external file survives FlyWithLua restarts
-- (custom datarefs are cleared on script reload)
-- File format: single line — total_flight_time_sec
--
-- sim/time/total_flight_time_sec resets when a new aircraft is loaded
-- but stays unaffected when reloading the Lua script.
--
-- I/O strategy: read once at init, keep in memory. Only write when
-- a reload is detected (flight time went backwards).
-- ============================================================

--- Absolute path to the checkpoint file, derived from this script's location.
local STATE_FILE = MODULES_DIRECTORY .. "bravo++" .. DIRECTORY_SEPARATOR .. "g1000_reload_flag.txt"
-- local STATE_FILE = string.match(debug.getinfo(1, "S").source, "(.*)/[^/]+$") .. "/g1000_reload_flag.txt"

--- Read the checkpoint file and return the saved flight time.
--- Returns nil if the file doesn't exist or is unreadable.
local function read_checkpoint()
	local f = io.open(STATE_FILE, "r")
	if not f then
		return nil
	end
	local t = tonumber(f:read("*n")) or 0
	f:close()
	return t
end

--- Write the current flight time to the checkpoint file.
local function write_checkpoint(flight_time)
	local f, err = io.open(STATE_FILE, "w")
	if not f then
		log.error("G1000: failed to write checkpoint: " .. tostring(err))
		return
	end
	f:write(tostring(flight_time))
	f:close()
end

--- Reset all G1000 COM state to defaults. Call this when the aircraft changes or flight is reloaded.
local function reset_state()
	G1000_COM_STATE_DR[0] = 0
	log.info("G1000 COM state reset")
end

-- Read checkpoint once at init (only I/O at startup)
local saved_flight_time = read_checkpoint()

--- Track time between polls (seconds).
local POLL_INTERVAL = 5.0
local last_poll_time = os.clock()

--- Detect flight reload and reset state. Called every frame but only executes once per second.
function G1000_COM_STDBY_detect_aircraft_change()
	local now = os.clock()
	if now - last_poll_time < POLL_INTERVAL then
		return -- Skip this frame; not enough time has passed
	end
	last_poll_time = now

	local current_flight_time = get("sim/time/total_flight_time_sec") or 0

	-- First run — save the flight time for future comparison
	if not saved_flight_time then
		saved_flight_time = current_flight_time
		write_checkpoint(current_flight_time)
		return
	end

	-- Detect: flight reload (total_flight_time_sec went backwards = aircraft was reloaded)
	if current_flight_time < saved_flight_time then
		log.info(
			"G1000: state reset (flight reloaded, flight_time "
				.. tostring(saved_flight_time)
				.. " -> "
				.. tostring(current_flight_time)
				.. ")"
		)
		reset_state()
		saved_flight_time = current_flight_time
		write_checkpoint(current_flight_time)
	end
end

-- Register a lower polling callback
do_often("G1000_COM_STDBY_detect_aircraft_change()")

--- Manual reset command (fallback when auto-detection is insufficient).
create_command(
	"FlyWithLua/Bravo++/G1000/reset_state",
	"Reset G1000 COM state (manual)",
	"G1000_COM_STATE_DR[0] = 0; log.info('G1000: manual state reset')",
	"",
	""
)

--- Get the current G1000 COM state from the dataref.
local function get_state()
	return G1000_COM_STATE_DR[0] or 0
end

--- Set the G1000 COM state in the dataref.
local function set_state(state)
	G1000_COM_STATE_DR[0] = state
end

local function is_com2(display_flag)
	return bit.band(get_state(), display_flag) ~= 0
end

local function set_com2(display_flag, enable)
	local state = get_state()
	if enable then
		state = bit.bor(state, display_flag)
	else
		state = bit.band(state, bit.bnot(display_flag))
	end
	set_state(state)
end

local function toggle_com2(display_flag)
	set_com2(display_flag, not is_com2(display_flag))
end

local function swap_com1()
	local tmp = com1_freq[0]
	com1_freq[0] = com1_stby_freq[0]
	com1_stby_freq[0] = tmp
end

local function swap_com2()
	local tmp = com2_freq[0]
	com2_freq[0] = com2_stby_freq[0]
	com2_stby_freq[0] = tmp
end

local function swap_selected(display_flag)
	if is_com2(display_flag) then
		swap_com2()
	else
		swap_com1()
	end
end

function handle_toggle_com12_PFD()
	command_once("sim/GPS/g1000n1_com12")
	toggle_com2(FLAG_PFD_COM2)
end

function handle_toggle_com12_MFD()
	command_once("sim/GPS/g1000n3_com12")
	toggle_com2(FLAG_MFD_COM2)
end

function handle_toggle_com12_stby_PFD()
	swap_selected(FLAG_PFD_COM2)
end

function handle_toggle_com12_stby_MFD()
	swap_selected(FLAG_MFD_COM2)
end

create_command(
	"FlyWithLua/Bravo++/G1000/toggle_n1_com12",
	"Bravo++ toggles COM1/COM2 being active on PFD",
	"handle_toggle_com12_PFD()", -- Call Lua function when pressed
	"",
	""
)

create_command(
	"FlyWithLua/Bravo++/G1000/toggle_n3_com12",
	"Bravo++ toggles COM1/COM2 being active on MFD",
	"handle_toggle_com12_MFD()", -- Call Lua function when pressed
	"",
	""
)

create_command(
	"FlyWithLua/Bravo++/G1000/toggle_n1_com12_stdby_freq",
	"Bravo++ toggles conditional COM1/COM2 and stdby freq on PFD",
	"handle_toggle_com12_stby_PFD()", -- Call Lua function when pressed
	"",
	""
)

create_command(
	"FlyWithLua/Bravo++/G1000/toggle_n3_com12_stdby_freq",
	"Bravo++ toggles conditional COM1/COM2 and stdby freq on MFD",
	"handle_toggle_com12_stby_MFD()", -- Call Lua function when pressed
	"",
	""
)
