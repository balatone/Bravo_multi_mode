local log = require("bravo++.log")

-- **************************************************************
-- Custom dataref commands for the Aerobask DA42 and DA62
-- 
-- **************************************************************

if log.LOG_LEVEL == nil then 
    log.LOG_LEVEL = log.LOG_DEBUG
end

local aircraft_name = string.sub(AIRCRAFT_FILENAME, 1, string.len(AIRCRAFT_FILENAME) - 4)

if aircraft_name ~= "DA42" and aircraft_name ~= "DA62" then
    log.info("The current aircraft is not the DA42 or DA62. The lua script will not be loaded.")
    return
end
--------------------------------------
---- Rudder trim
--------------------------------------

local rudder_trim_last_click_time = 0
local rudder_trim_debounce_delay = 0.04 -- Time in seconds
local rudder_trim_dataref = dataref_table("sim/cockpit2/controls/rudder_trim")
local rudder_trim_min = -1
local rudder_trim_max = 1
local increment = 0.05
local boost_factor = 1

function handle_rudder_trim_right()
    local current_time = os.clock()
    local diff = current_time - rudder_trim_last_click_time

    log.debug("Rudder trim right")
    local current_value = tonumber(rudder_trim_dataref[0])
    local new_value = current_value
    log.debug("Time since last call: " .. diff)
    if diff < rudder_trim_debounce_delay then
        new_value = current_value + increment*boost_factor
        log.debug("Boosting rudder trim right")
    else
        new_value = current_value + increment        
    end
    if new_value <= rudder_trim_max then 
        rudder_trim_dataref[0] = new_value
    else
        rudder_trim_dataref[0] = rudder_trim_max
    end
    log.debug("New rudder trim value: " .. new_value)
    rudder_trim_last_click_time = current_time
end

create_command(
    "FlyWithLua/Bravo++/da42/handle_rudder_trim_right",
    "Handle rudder trim right",
    "handle_rudder_trim_right()",
    "",
    ""
)

function handle_rudder_trim_left()
    local current_time = os.clock()
    local diff = current_time - rudder_trim_last_click_time

    log.debug("Rudder trim left")
    local current_value = tonumber(rudder_trim_dataref[0])
    local new_value = current_value
    log.debug("Time since last call: " .. diff)
    if diff < rudder_trim_debounce_delay then
        new_value = current_value - increment*boost_factor
        log.debug("Boosting rudder trim left")
    else
        new_value = current_value - increment        
    end
    if new_value >= rudder_trim_min then
        rudder_trim_dataref[0] = new_value -- This updates the dataref
    else
        rudder_trim_dataref[0] = rudder_trim_min
    end
    log.debug("New rudder trim value: " .. new_value)
    rudder_trim_last_click_time = current_time
end

create_command(
    "FlyWithLua/Bravo++/da42/handle_rudder_trim_left",
    "Handle rudder trim left",
    "handle_rudder_trim_left()",
    "",
    ""
)