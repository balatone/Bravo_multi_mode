local log = require("bravo++.log")

-- **************************************************************
-- Custom dataref commands for the Laminar Cirrus SR22
--
-- **************************************************************

if log.LOG_LEVEL == nil then
	log.LOG_LEVEL = log.LOG_DEBUG
end

local aircraft_name = string.sub(AIRCRAFT_FILENAME, 1, string.len(AIRCRAFT_FILENAME) - 4)

if aircraft_name ~= "Cirrus SR22" then
	log.info("The current aircraft is not the SR22. The lua script will not be loaded.")
	return
else
	log.info("Loading custom SR22 file...")
end
--------------------------------------
---- Cabin heat
--------------------------------------

local cabin_heat_last_click_time = 0
local cabin_heat_debounce_delay = 0.04 -- Time in seconds
local cabin_heat_dataref = dataref_table("laminar/sr22/temp_control")
local cabin_heat_min = 0.0
local cabin_heat_max = 1.0
local increment = 0.075
local boost_factor = 1

function handle_cabin_heat_up()
	local current_time = os.clock()
	local diff = current_time - cabin_heat_last_click_time

	log.debug("Cabin pressure up")
	local current_value = tonumber(cabin_heat_dataref[0])
	local new_value = current_value
	log.debug("Time since last call: " .. diff)
	if diff < cabin_heat_debounce_delay then
		new_value = current_value + increment * boost_factor
		log.debug("Boosting cabin pressure up")
	else
		new_value = current_value + increment
	end
	if new_value <= cabin_heat_max then
		cabin_heat_dataref[0] = new_value
	else
		cabin_heat_dataref[0] = cabin_heat_max
	end
	log.debug("New cabin pressure value: " .. new_value)
	cabin_heat_last_click_time = current_time
end

create_command(
	"FlyWithLua/Bravo++/sr22/cabin_heat_up_handler",
	"Handle increase in cabin heat",
	"handle_cabin_heat_up()", -- Call Lua function when pressed
	"",
	""
)

function handle_cabin_heat_down()
	local current_time = os.clock()
	local diff = current_time - cabin_heat_last_click_time

	log.debug("Cabin pressure down")
	local current_value = tonumber(cabin_heat_dataref[0])
	local new_value = current_value
	log.debug("Time since last call: " .. diff)
	if diff < cabin_heat_debounce_delay then
		new_value = current_value - increment * boost_factor
		log.debug("Boosting cabin pressure down")
	else
		new_value = current_value - increment
	end
	if new_value >= cabin_heat_min then
		cabin_heat_dataref[0] = new_value -- This updates the dataref
	else
		cabin_heat_dataref[0] = cabin_heat_min
	end
	log.debug("New cabin pressure value: " .. new_value)
	cabin_heat_last_click_time = current_time
end

create_command(
	"FlyWithLua/Bravo++/sr22/cabin_heat_down_handler",
	"Handle decrease in cabin heat",
	"handle_cabin_heat_down()", -- Call Lua function when pressed
	"",
	""
)
