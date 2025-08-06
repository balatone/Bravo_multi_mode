local log = require("bravo++.log")

-- **************************************************************
-- Custom dataref commands for the Laminar King Air C90B
-- 
-- **************************************************************

if log.LOG_LEVEL == nil then 
    log.LOG_LEVEL = log.LOG_DEBUG
end

local aircraft_name = string.sub(AIRCRAFT_FILENAME, 1, string.len(AIRCRAFT_FILENAME) - 4)

if aircraft_name ~= "C90B" then
    log.info("The current aircraft is not the C90B. The lua script will not be loaded.")
    return
end
--------------------------------------
---- Cabin pressure
--------------------------------------

local cabin_pressure_last_click_time = 0
local cabin_pressure_debounce_delay = 0.04 -- Time in seconds
local cabin_pressure_dataref = dataref_table("sim/cockpit2/pressurization/actuators/cabin_altitude_ft")
local cabin_pressure_min = -1000
local cabin_pressure_max = 10000
local increment = 120.0
local boost_factor = 1

function handle_cabin_pressure_up()
    local current_time = os.clock()
    local diff = current_time - cabin_pressure_last_click_time

    log.debug("Cabin pressure up")
    local current_value = tonumber(cabin_pressure_dataref[0])
    local new_value = current_value
    log.debug("Time since last call: " .. diff)
    if diff < cabin_pressure_debounce_delay then
        new_value = current_value + increment*boost_factor
        log.debug("Boosting cabin pressure up")
    else
        new_value = current_value + increment        
    end
    if new_value <= cabin_pressure_max then 
        cabin_pressure_dataref[0] = new_value
    else
        cabin_pressure_dataref[0] = cabin_pressure_max
    end
    log.debug("New cabin pressure value: " .. new_value)
    cabin_pressure_last_click_time = current_time
end

create_command(
    "FlyWithLua/Bravo++/c90/cabin_pressure_up_handler",
    "Handle increase in cabin pressure",
    "handle_cabin_pressure_up()", -- Call Lua function when pressed
    "",
    ""
)

function handle_cabin_pressure_down()
    local current_time = os.clock()
    local diff = current_time - cabin_pressure_last_click_time

    log.debug("Cabin pressure down")
    local current_value = tonumber(cabin_pressure_dataref[0])
    local new_value = current_value
    log.debug("Time since last call: " .. diff)
    if diff < cabin_pressure_debounce_delay then
        new_value = current_value - increment*boost_factor
        log.debug("Boosting cabin pressure down")
    else
        new_value = current_value - increment        
    end
    if new_value >= cabin_pressure_min then
        cabin_pressure_dataref[0] = new_value -- This updates the dataref
    else
        cabin_pressure_dataref[0] = cabin_pressure_min
    end
    log.debug("New cabin pressure value: " .. new_value)
    cabin_pressure_last_click_time = current_time
end

create_command(
    "FlyWithLua/Bravo++/c90/cabin_pressure_down_handler",
    "Handle decrease in cabin pressure",
    "handle_cabin_pressure_down()", -- Call Lua function when pressed
    "",
    ""
)

--------------------------------------
---- Cabin pressure rate
--------------------------------------

local cabin_pressure_rate_last_click_time = 0
local cabin_pressure_rate_debounce_delay = 0.04 -- Time in seconds
local cabin_pressure_rate_dataref = dataref_table("sim/cockpit2/pressurization/actuators/cabin_vvi_fpm")
local cabin_pressure_rate_min = 250
local cabin_pressure_rate_max = 2500
local increment = 150.0 
local boost_factor = 1

function handle_cabin_pressure_rate_up()
    local current_time = os.clock()
    local diff = current_time - cabin_pressure_rate_last_click_time

    log.debug("Cabin pressure rate up")
    local current_value = tonumber(cabin_pressure_rate_dataref[0])
    local new_value = current_value
    log.debug("Time since last call: " .. diff)
    if diff < cabin_pressure_rate_debounce_delay then
        new_value = current_value + increment*boost_factor
        log.debug("Boosting cabin pressure rate up")
    else
        new_value = current_value + increment        
    end
    if new_value <= cabin_pressure_rate_max then 
        cabin_pressure_rate_dataref[0] = new_value
    else
        cabin_pressure_rate_dataref[0] = cabin_pressure_rate_max
    end
    log.debug("New cabin pressure rate value: " .. new_value)
    cabin_pressure_rate_last_click_time = current_time
end

create_command(
    "FlyWithLua/Bravo++/c90/cabin_pressure_rate_up_handler",
    "Handle increase in cabin pressure rate",
    "handle_cabin_pressure_rate_up()", -- Call Lua function when pressed
    "",
    ""
)

function handle_cabin_pressure_rate_down()
    local current_time = os.clock()
    local diff = current_time - cabin_pressure_rate_last_click_time

    log.debug("Cabin pressure rate down")
    local current_value = tonumber(cabin_pressure_rate_dataref[0])
    local new_value = current_value
    log.debug("Time since last call: " .. diff)
    if diff < cabin_pressure_rate_debounce_delay then
        new_value = current_value - increment*boost_factor
        log.debug("Boosting cabin pressure rate down")
    else
        new_value = current_value - increment        
    end
    if new_value >= cabin_pressure_rate_min then
        cabin_pressure_rate_dataref[0] = new_value -- This updates the dataref
    else
        cabin_pressure_rate_dataref[0] = cabin_pressure_rate_min
    end
    log.debug("New cabin pressure rate value: " .. new_value)
    cabin_pressure_rate_last_click_time = current_time
end

create_command(
    "FlyWithLua/Bravo++/c90/cabin_pressure_rate_down_handler",
    "Handle decrease in cabin pressure rate",
    "handle_cabin_pressure_rate_down()", -- Call Lua function when pressed
    "",
    ""
)

--------------------------------------
---- Decision height
--------------------------------------

local decision_height_last_click_time = 0
local decision_height_debounce_delay = 0.04 -- Time in seconds
local decision_height_dataref = dataref_table("sim/cockpit2/gauges/actuators/radio_altimeter_bug_ft_pilot")
local decision_height_min = 0
local decision_height_max = 10000
local increment = 1.0 
local boost_factor = 10

function handle_decision_height_up()
    local current_time = os.clock()
    local diff = current_time - decision_height_last_click_time

    log.debug("Decision height up")
    local current_value = tonumber(decision_height_dataref[0])
    local new_value = current_value
    log.debug("Time since last call: " .. diff)
    if diff < decision_height_debounce_delay then
        new_value = current_value + increment*boost_factor
        log.debug("Boosting decision height up")
    else
        new_value = current_value + increment        
    end
    if new_value <= decision_height_max then 
        decision_height_dataref[0] = new_value
    else
        decision_height_dataref[0] = decision_height_max
    end
    log.debug("New decision height value: " .. new_value)
    decision_height_last_click_time = current_time
end

create_command(
    "FlyWithLua/Bravo++/c90/decision_height_up_handler",
    "Handle increase in decision height",
    "handle_decision_height_up()", -- Call Lua function when pressed
    "",
    ""
)

function handle_decision_height_down()
    local current_time = os.clock()
    local diff = current_time - decision_height_last_click_time

    log.debug("Decision height down")
    local current_value = tonumber(decision_height_dataref[0])
    local new_value = current_value
    log.debug("Time since last call: " .. diff)
    if diff < decision_height_debounce_delay then
        new_value = current_value - increment*boost_factor
        log.debug("Boosting decision height down")
    else
        new_value = current_value - increment        
    end
    if new_value >= decision_height_min then
        decision_height_dataref[0] = new_value -- This updates the dataref
    else
        decision_height_dataref[0] = decision_height_min
    end
    log.debug("New decision height value: " .. new_value)
    decision_height_last_click_time = current_time
end

create_command(
    "FlyWithLua/Bravo++/c90/decision_height_down_handler",
    "Handle decrease in decision height",
    "handle_decision_height_down()", -- Call Lua function when pressed
    "",
    ""
)

--------------------------------------
---- Cabin temperature
--------------------------------------

local cabin_temperature_last_click_time = 0
local cabin_temperature_debounce_delay = 0.2 -- Time in seconds
local cabin_temperature_dataref = dataref_table("laminar/c90/airCon/dial/cabin_temp")
local cabin_temperature_min = 0
local cabin_temperature_max = 1
local increment = 0.01 
local boost_factor = 2

function handle_cabin_temperature_up()
    local current_time = os.clock()
    local diff = current_time - cabin_temperature_last_click_time

    log.debug("Cabin temperature up")
    local current_value = tonumber(cabin_temperature_dataref[0])
    local new_value = current_value
    log.debug("Time since last call: " .. diff)
    if diff < cabin_temperature_debounce_delay then
        new_value = current_value + increment*boost_factor
        log.debug("Boosting cabin temperature up")
    else
        new_value = current_value + increment        
    end
    if new_value <= cabin_temperature_max then 
        cabin_temperature_dataref[0] = new_value
    else
        cabin_temperature_dataref[0] = cabin_temperature_max
    end
    log.debug("New cabin temperature value: " .. new_value)
    cabin_temperature_last_click_time = current_time
end

create_command(
    "FlyWithLua/Bravo++/c90/cabin_temperature_up_handler",
    "Handle increase in cabin temperature",
    "handle_cabin_temperature_up()", -- Call Lua function when pressed
    "",
    ""
)

function handle_cabin_temperature_down()
    local current_time = os.clock()
    local diff = current_time - cabin_temperature_last_click_time

    log.debug("Cabin temperature down")
    local current_value = tonumber(cabin_temperature_dataref[0])
    local new_value = current_value
    log.debug("Time since last call: " .. diff)
    if diff < cabin_temperature_debounce_delay then
        new_value = current_value - increment*boost_factor
        log.debug("Boosting cabin temperature down")
    else
        new_value = current_value - increment        
    end
    if new_value >= cabin_temperature_min then
        cabin_temperature_dataref[0] = new_value -- This updates the dataref
    else
        cabin_temperature_dataref[0] = cabin_temperature_min
    end
    log.debug("New cabin temperature value: " .. new_value)
    cabin_temperature_last_click_time = current_time
end

create_command(
    "FlyWithLua/Bravo++/c90/cabin_temperature_down_handler",
    "Handle decrease in cabin temperature",
    "handle_cabin_temperature_down()", -- Call Lua function when pressed
    "",
    ""
)