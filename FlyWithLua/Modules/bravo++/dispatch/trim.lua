--[[
    bravo++.dispatch_trim - Trim Wheel Executor

    Responsibilities:
    - Execute trim nose up (elevator trim forward)
    - Execute trim nose down (elevator trim aft)
    - Handle boost window logic
    - Clamp values to [-1, 1]

    This module handles all trim wheel input logic.
]]

local log = require("bravo++.log")

local trim = {}

--- Execute trim nose up (elevator trim forward).
--- @param state table  Shared state table
function trim.trim_nose_up(state)
    if not state.trim_dataref then
        return
    end

    local current_time = os.clock()
    local diff = current_time - state.trim_last_click_time

    local current_value = tonumber(state.trim_dataref[0]) or 0
    local new_value

    if diff < state.trim_boost_window then
        new_value = current_value + (state.trim_increment * state.trim_boost_factor)
        log.debug("Boosting nose up")
    else
        new_value = current_value + state.trim_increment
    end

    if new_value <= 1 then
        state.trim_dataref[0] = new_value
    elseif current_value ~= 1 then
        state.trim_dataref[0] = 1
    end

    log.debug("New trim value: " .. state.trim_dataref[0])
    state.trim_last_click_time = current_time
end

--- Execute trim nose down (elevator trim aft).
--- @param state table  Shared state table
function trim.trim_nose_down(state)
    if not state.trim_dataref then
        return
    end

    local current_time = os.clock()
    local diff = current_time - state.trim_last_click_time

    local current_value = tonumber(state.trim_dataref[0]) or 0
    local new_value

    if diff < state.trim_boost_window then
        new_value = current_value - (state.trim_increment * state.trim_boost_factor)
        log.debug("Boosting nose down")
    else
        new_value = current_value - state.trim_increment
    end

    if new_value >= -1 then
        state.trim_dataref[0] = new_value
    elseif current_value ~= -1 then
        state.trim_dataref[0] = -1
    end

    log.debug("New trim value: " .. state.trim_dataref[0])
    state.trim_last_click_time = current_time
end

return trim
