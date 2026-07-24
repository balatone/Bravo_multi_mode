--[[
    bravo++.dispatch.twist - Twist Knob Executor

    Responsibilities:
    - Execute twist knob increase (clockwise)
    - Execute twist knob decrease (counter-clockwise)
    - Handle priority resolution: direct > OUTER > INNER based on cf_mode state
    - Use safe command execution via state.command_fn (FEAT-019)

    This module handles all twist knob input logic.
]]

local log = require("bravo++.log")

local twist = {}

--- Mode select command mapping.
local mode_select_command = {
    UP = "FlyWithLua/Bravo++/cycle_mode_up",
    DOWN = "FlyWithLua/Bravo++/cycle_mode_down",
}

--- Execute a command through the safe command executor.
--- Uses state.command_fn if available, falls back to _G.command_once.
--- @param state table  Shared state table
--- @param cmd string  Command name to execute
local function execute_command(state, cmd)
    if state.command_fn and type(state.command_fn) == "function" then
        state.command_fn(cmd)
    else
        -- Fallback for backward compatibility and testing
        _G.command_once(cmd)
    end
end

--- Execute twist knob increase (clockwise).
--- @param state table  Shared state table
function twist.knob_increase(state)
    local current_action

    if state.mode_select then
        current_action = mode_select_command
    else
        current_action = state.twist_knob_map_actions[state.current_mode]
            and state.twist_knob_map_actions[state.current_mode][state.current_selection]
    end

    if not current_action then
        return
    end

    -- Priority: direct UP > OUTER.UP (if cf=outer) > INNER.UP (if cf=inner)
    if current_action["UP"] then
        execute_command(state, current_action["UP"])
    elseif state.current_cf_mode == "outer" and current_action["OUTER"] and current_action["OUTER"]["UP"] then
        execute_command(state, current_action["OUTER"]["UP"])
    elseif state.current_cf_mode == "inner" and current_action["INNER"] and current_action["INNER"]["UP"] then
        execute_command(state, current_action["INNER"]["UP"])
    else
        log.debug("No UP action for twist knob.")
    end
end

--- Execute twist knob decrease (counter-clockwise).
--- @param state table  Shared state table
function twist.knob_decrease(state)
    local current_action

    if state.mode_select then
        current_action = mode_select_command
    else
        current_action = state.twist_knob_map_actions[state.current_mode]
            and state.twist_knob_map_actions[state.current_mode][state.current_selection]
    end

    if not current_action then
        return
    end

    -- Priority: direct DOWN > OUTER.DOWN (if cf=outer) > INNER.DOWN (if cf=inner)
    if current_action["DOWN"] then
        execute_command(state, current_action["DOWN"])
    elseif state.current_cf_mode == "outer" and current_action["OUTER"] and current_action["OUTER"]["DOWN"] then
        execute_command(state, current_action["OUTER"]["DOWN"])
    elseif state.current_cf_mode == "inner" and current_action["INNER"] and current_action["INNER"]["DOWN"] then
        execute_command(state, current_action["INNER"]["DOWN"])
    else
        log.debug("No DOWN action for twist knob.")
    end
end

return twist
