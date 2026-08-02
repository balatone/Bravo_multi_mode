local log = require("bravo++.log")

-- **************************************************************
-- Script that will toggle com1 and com2 without issues
-- **************************************************************

log.info("Loading G1000 com toggling script...")

if log.LOG_LEVEL == nil then
	log.LOG_LEVEL = log.LOG_DEBUG
end

local G1000_COM_STATE_DR = create_dataref_table("FlyWithLua/Bravo++/G1000_COM_STATE", "Int")
local LAST_AIRCRAFT_PATH = create_dataref_table("FlyWithLua/Bravo++/LAST_AIRCRAFT_PATH", "Data")
local LAST_AIRCRAFT_NAME = create_dataref_table("FlyWithLua/Bravo++/LAST_AIRCRAFT_NAME", "Data")

local com1_freq = dataref_table("sim/cockpit2/radios/actuators/com1_frequency_hz_833")
local com1_stby_freq = dataref_table("sim/cockpit2/radios/actuators/com1_standby_frequency_hz_833")
local com2_freq = dataref_table("sim/cockpit2/radios/actuators/com2_frequency_hz_833")
local com2_stby_freq = dataref_table("sim/cockpit2/radios/actuators/com2_standby_frequency_hz_833")

local FLAG_PFD_COM2 = 0x01
local FLAG_MFD_COM2 = 0x02

-- Track last-known aircraft to detect switches (AIRCRAFT_PATH/Filename update every frame in FlyWithLua)
local last_aircraft_path = LAST_AIRCRAFT_PATH[0] or ""
local last_aircraft_filename = LAST_AIRCRAFT_NAME[0] or ""

--- Reset all G1000 COM state to defaults. Call this when the aircraft changes or flight is reloaded.
local function reset_state()
	G1000_COM_STATE_DR[0] = 0
	log.info("G1000 COM state reset")
end

--- Track time between polls (seconds). 1 Hz is plenty — aircraft loads are infrequent events.
local POLL_INTERVAL = 5.0
local last_poll_time = os.clock()

--- Detect aircraft change (or flight reload) and reset state. Called every frame but only executes once per second.
function G1000_COM_STDBY_detect_aircraft_change()
	local now = os.clock()
	if now - last_poll_time < POLL_INTERVAL then
		return -- Skip this frame; not enough time has passed
	end
	last_poll_time = now

	local new_path = AIRCRAFT_PATH or ""
	local new_name = AIRCRAFT_FILENAME or ""

	-- Detect: different aircraft OR same aircraft but flight was reloaded (counter incremented)
	if
		new_path ~= last_aircraft_path
		or new_name ~= last_aircraft_filename
	then
		--log.info("G1000: state reset (" .. last_aircraft_filename .. ", load=" .. current_load_count .. ")")
		log.info("G1000: state reset (" .. last_aircraft_filename .. ")")
		reset_state()
		LAST_AIRCRAFT_PATH[0] = new_path
		LAST_AIRCRAFT_NAME[1] = new_name
		last_aircraft_path = new_path
		last_aircraft_filename = new_name
	end

end

-- Register a per-frame callback (rate-limited to 1 Hz inside the function).
do_every_frame("G1000_COM_STDBY_detect_aircraft_change()")

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
