local log = require("bravo++.log")

-- **************************************************************
-- Script that will toggle com1 and com2 without issues
-- **************************************************************

log.info("Loading gns com toggling script...")

if log.LOG_LEVEL == nil then
	log.LOG_LEVEL = log.LOG_DEBUG
end

local com1_freq = dataref_table("sim/cockpit2/radios/actuators/com1_frequency_hz_833")
local com1_stby_freq = dataref_table("sim/cockpit2/radios/actuators/com1_standby_frequency_hz_833")
local com2_freq = dataref_table("sim/cockpit2/radios/actuators/com2_frequency_hz_833")
local com2_stby_freq = dataref_table("sim/cockpit2/radios/actuators/com2_standby_frequency_hz_833")

function handle_swap_com1()
    log.info("swap com1")
	local tmp = com1_freq[0]
	com1_freq[0] = com1_stby_freq[0]
	com1_stby_freq[0] = tmp
end

function handle_swap_com2()
    log.info("swap com2")
	local tmp = com2_freq[0]
	com2_freq[0] = com2_stby_freq[0]
	com2_stby_freq[0] = tmp
end

create_command(
	"FlyWithLua/Bravo++/GNS/toggle_gns_n1_com_stdby_freq",
	"Bravo++ toggles COM1 and stdby freq on PFD",
	"handle_swap_com1()", -- Call Lua function when pressed
	"",
	""
)

create_command(
	"FlyWithLua/Bravo++/GNS/toggle_gns_n2_com_stdby_freq",
	"Bravo++ toggles COM2 and stdby freq on MFD",
	"handle_swap_com2()", -- Call Lua function when pressed
	"",
	""
)
