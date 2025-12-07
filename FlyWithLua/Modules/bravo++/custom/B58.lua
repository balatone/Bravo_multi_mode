local log = require("bravo++.log")

-- **************************************************************
-- Custom dataref commands for the Baron 58
-- 
-- **************************************************************

if log.LOG_LEVEL == nil then 
    log.LOG_LEVEL = log.LOG_DEBUG
end

local aircraft_name = string.sub(AIRCRAFT_FILENAME, 1, string.len(AIRCRAFT_FILENAME) - 4)

if aircraft_name ~= "Baron_58" then
    log.info("The current aircraft is not the Baron 58. The lua script will not be loaded.")
    return
else
    log.info("Loading custom B58 file...")
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
    "FlyWithLua/Bravo++/b58/handle_rudder_trim_right",
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
    "FlyWithLua/Bravo++/b58/handle_rudder_trim_left",
    "Handle rudder trim left",
    "handle_rudder_trim_left()",
    "",
    ""
)

local left_cowl_flap_last_click_time = 0
local left_cowl_flap_debounce_delay = 0.04 -- Time in seconds
local left_cowl_flap_dataref = dataref_table("sim/cockpit2/engine/actuators/cowl_flap_ratio")
local left_cowl_flap_min = 0
local left_cowl_flap_max = 1

function handle_left_cowl_up()
    local current_time = os.clock()
    local diff = current_time - left_cowl_flap_last_click_time

    log.debug("Left cowl up")
    local current_value = tonumber(left_cowl_flap_dataref[0])
    local new_value = current_value
    log.debug("Time since last call: " .. diff)
    if diff < left_cowl_flap_debounce_delay then
        new_value = current_value + increment*boost_factor
        log.debug("Boosting left cowl up")
    else
        new_value = current_value + increment        
    end
    if new_value >= left_cowl_flap_min then
        left_cowl_flap_dataref[0] = new_value -- This updates the dataref
    else
        left_cowl_flap_dataref[0] = left_cowl_flap_min
    end
    log.debug("New left cowl flap value: " .. new_value)
    left_cowl_flap_last_click_time = current_time
end

create_command(
    "FlyWithLua/Bravo++/b58/handle_left_cowl_up",
    "Handle left cowl up",
    "handle_left_cowl_up()",
    "",
    ""
)

function handle_left_cowl_down()
    local current_time = os.clock()
    local diff = current_time - left_cowl_flap_last_click_time

    log.debug("Left cowl down")
    local current_value = tonumber(left_cowl_flap_dataref[0])
    log.debug("current_value = " .. tostring(current_value))
    local new_value = current_value
    log.debug("Time since last call: " .. diff)
    if diff < left_cowl_flap_debounce_delay then
        new_value = current_value - increment*boost_factor
        log.debug("Boosting left cowl down")
    else
        new_value = current_value - increment        
    end
    if new_value <= left_cowl_flap_max then
        left_cowl_flap_dataref[0] = new_value -- This updates the dataref
    else
        left_cowl_flap_dataref[0] = left_cowl_flap_max
    end
    log.debug("New left cowl flap value: " .. new_value)
    left_cowl_flap_last_click_time = current_time
end

create_command(
    "FlyWithLua/Bravo++/b58/handle_left_cowl_down",
    "Handle left cowl down",
    "handle_left_cowl_down()",
    "",
    ""
)

local right_cowl_flap_last_click_time = 0
local right_cowl_flap_debounce_delay = 0.04 -- Time in seconds
local right_cowl_flap_dataref = dataref_table("sim/cockpit2/engine/actuators/cowl_flap_ratio")
local right_cowl_flap_min = 0
local right_cowl_flap_max = 1

function handle_right_cowl_up()
    local current_time = os.clock()
    local diff = current_time - right_cowl_flap_last_click_time

    log.debug("right cowl up")
    local current_value = tonumber(right_cowl_flap_dataref[1])
    local new_value = current_value
    log.debug("Time since last call: " .. diff)
    if diff < right_cowl_flap_debounce_delay then
        new_value = current_value + increment*boost_factor
        log.debug("Boosting right cowl up")
    else
        new_value = current_value + increment        
    end
    if new_value >= right_cowl_flap_min then
        right_cowl_flap_dataref[1] = new_value -- This updates the dataref
    else
        right_cowl_flap_dataref[1] = right_cowl_flap_min
    end
    log.debug("New right cowl flap value: " .. new_value)
    right_cowl_flap_last_click_time = current_time
end

create_command(
    "FlyWithLua/Bravo++/b58/handle_right_cowl_up",
    "Handle right cowl up",
    "handle_right_cowl_up()",
    "",
    ""
)

function handle_right_cowl_down()
    local current_time = os.clock()
    local diff = current_time - right_cowl_flap_last_click_time

    log.debug("right cowl down")
    local current_value = tonumber(right_cowl_flap_dataref[1])
    log.debug("current_value = " .. tostring(current_value))
    local new_value = current_value
    log.debug("Time since last call: " .. diff)
    if diff < right_cowl_flap_debounce_delay then
        new_value = current_value - increment*boost_factor
        log.debug("Boosting right cowl down")
    else
        new_value = current_value - increment        
    end
    if new_value <= right_cowl_flap_max then
        right_cowl_flap_dataref[1] = new_value -- This updates the dataref
    else
        right_cowl_flap_dataref[1] = right_cowl_flap_max
    end
    log.debug("New right cowl flap value: " .. new_value)
    right_cowl_flap_last_click_time = current_time
end

create_command(
    "FlyWithLua/Bravo++/b58/handle_right_cowl_down",
    "Handle right cowl down",
    "handle_right_cowl_down()",
    "",
    ""
)
