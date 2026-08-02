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

local function get_state()
	return G1000_COM_STATE_DR[0] or 0
end

local function set_state(state)
	G1000_COM_STATE_DR[0] = state
end

if G1000_COM_STATE_DR[0] < 0 or G1000_COM_STATE_DR[0] > 3 then
	set_state(0)
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

