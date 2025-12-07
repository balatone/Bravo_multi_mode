local log = require("bravo++.log")

-- **************************************************************
-- Script that will set the correct VFR transponder code according 
-- to whether it is in North America or not.
-- **************************************************************

if log.LOG_LEVEL == nil then 
    log.LOG_LEVEL = log.LOG_DEBUG
end

local xpdr_code = dataref_table("sim/cockpit2/radios/actuators/transponder_code")

local lat = get("sim/flightmodel/position/latitude")
local lon = get("sim/flightmodel/position/longitude")

local function is_in_north_america()
	return lat > 7 and lat < 85 and lon < -52 and lon > -168
end

local vfr_code_default = is_in_north_america()

function handle_transponder_vfr_code()
	if vfr_code_default == true then
		xpdr_code[0] = 1200
	else
		xpdr_code[0] = 7000		
	end
end

function toggle_transponder_vfr_code()
	vfr_code_default = not vfr_code_default
end

create_command(
    "FlyWithLua/Bravo++/set_transponder_vfr_code",
    "Bravo++ sets the vfr transponder code",
    "handle_transponder_vfr_code()", -- Call Lua function when pressed
    "",
    ""
)

create_command(
    "FlyWithLua/Bravo++/toggle_transponder_vfr_code",
    "Bravo++ toggles the vfr transponder code between 1200 and 7000",
    "toggle_transponder_vfr_code()", -- Call Lua function when pressed
    "",
    ""
)