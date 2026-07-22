--[[
    bravo++.dispatch_buttons - Button Command Executor

    Responsibilities:
    - Resolve button commands via three lookup paths
    - Execute button press lifecycle (begin/continue/end)
    - Handle continuous mode and long-click detection

    This module handles all button press logic including the
    begin/continue/end lifecycle and command resolution.
]]

local util = require("bravo++.util")
local log = require("bravo++.log")

local buttons = {}

--- Execute the resolved button command based on current phase.
--- @param state table  Shared state table
--- @param button_name string  Button identifier
local function _trigger_button_command(state, button_name)
    local cmds = buttons.resolve_button_command(state, button_name)
    if not cmds then
        return
    end

    local is_continuous = state.command_state[button_name] and state.command_state[button_name].is_continuous_mode
    local phase = state.command_state[button_name] and state.command_state[button_name].phase or "begin"

    local success, err = pcall(function()
        if is_continuous then
            if phase == "begin" then
                log.debug("Trigger command begin: " .. (cmds["ON_HOLD"] or cmds["ON_CLICK"]))
                _G.command_begin(cmds["ON_HOLD"] or cmds["ON_CLICK"])
                state.command_state[button_name].phase = "continuous"
            elseif phase == "end" then
                log.debug("Trigger command end: " .. (cmds["ON_HOLD"] or cmds["ON_CLICK"]))
                _G.command_end(cmds["ON_HOLD"] or cmds["ON_CLICK"])
            end
        else
            if phase == "long_click" and cmds["ON_LONG_CLICK"] ~= nil then
                log.debug("Trigger long click: " .. cmds["ON_LONG_CLICK"])
                _G.command_once(cmds["ON_LONG_CLICK"])
            else
                log.debug("Trigger click: " .. (cmds["ON_CLICK"] or "sim/none/none"))
                _G.command_once(cmds["ON_CLICK"] or "sim/none/none")
            end
        end
    end)

    if not success then
        log.error("Button dispatch error for " .. button_name .. ": " .. tostring(err))
    end
end

--- Resolve the command string for a given button and interaction type.
--- Returns the resolved command table/string, or nil if not found.
--- @param state table  Shared state table
--- @param button_name string  Button identifier
function buttons.resolve_button_command(state, button_name)
    local cmd = "sim/none/none"

    -- 1) Check mode-level button (e.g., ALT selection buttons)
    if
        util.is_string(
            state.button_map_actions[state.current_mode][button_name]
                and state.button_map_actions[state.current_mode][button_name]["ON_CLICK"]
        )
    then
        cmd = state.button_map_actions[state.current_mode][button_name]

    -- 2) Check mode-level button with UP/DOWN switch behavior
    elseif
        state.current_switch_mode == "up"
        and util.is_table(state.button_map_actions[state.current_mode][button_name])
        and util.is_table(state.button_map_actions[state.current_mode][button_name]["UP"])
        and util.is_string(state.button_map_actions[state.current_mode][button_name]["UP"]["ON_CLICK"])
    then
        cmd = state.button_map_actions[state.current_mode][button_name]["UP"]
    elseif
        state.current_switch_mode == "down"
        and util.is_table(state.button_map_actions[state.current_mode][button_name])
        and util.is_table(state.button_map_actions[state.current_mode][button_name]["DOWN"])
        and util.is_string(state.button_map_actions[state.current_mode][button_name]["DOWN"]["ON_CLICK"])
    then
        cmd = state.button_map_actions[state.current_mode][button_name]["DOWN"]

    -- 3) Check selection-aware button
    elseif
        util.is_table(state.button_map_actions[state.current_mode][state.current_selection])
        and util.is_table(state.button_map_actions[state.current_mode][state.current_selection][button_name])
    then
        if
            util.is_string(
                state.button_map_actions[state.current_mode][state.current_selection][button_name]["ON_CLICK"]
            )
        then
            cmd = state.button_map_actions[state.current_mode][state.current_selection][button_name]
        elseif
            state.current_switch_mode == "up"
            and util.is_table(state.button_map_actions[state.current_mode][state.current_selection][button_name]["UP"])
            and util.is_string(
                state.button_map_actions[state.current_mode][state.current_selection][button_name]["UP"]["ON_CLICK"]
            )
        then
            cmd = state.button_map_actions[state.current_mode][state.current_selection][button_name]["UP"]
        elseif
            state.current_switch_mode == "down"
            and util.is_table(
                state.button_map_actions[state.current_mode][state.current_selection][button_name]["DOWN"]
            )
            and util.is_string(
                state.button_map_actions[state.current_mode][state.current_selection][button_name]["DOWN"]["ON_CLICK"]
            )
        then
            cmd = state.button_map_actions[state.current_mode][state.current_selection][button_name]["DOWN"]
        else
            log.debug(
                "Button action not found for mode="
                    .. state.current_mode
                    .. " sel="
                    .. state.current_selection
                    .. " btn="
                    .. button_name
            )
        end
    else
        log.debug("Button action not found for btn=" .. button_name)
    end

    return cmd
end

--- Begin button press: initialize timer and state.
--- @param state table  Shared state table
--- @param button_name string  Button identifier
function buttons.button_begin(state, button_name)
    -- Reset arrow color on new press to ensure clean visual state
    state.arrow_color = 0xFF00FF00

    state.command_state[button_name] = {
        start_time = os.clock(),
        is_continuous_mode = false,
        phase = "begin",
    }
end

--- Continue button press: handle continuous mode or long-click detection.
--- @param state table  Shared state table
--- @param button_name string  Button identifier
function buttons.button_continue(state, button_name)
    if not state.command_state[button_name] then
        return
    end

    local elapsed = os.clock() - state.command_state[button_name].start_time

    if elapsed >= state.continuous_press_threshold then
        if not state.command_state[button_name].is_continuous_mode then
            log.debug("Button " .. button_name .. " held long enough. Starting continuous mode.")
            state.command_state[button_name].is_continuous_mode = true
            state.arrow_color = 0xFFED10D8
        end
        _trigger_button_command(state, button_name)
    elseif elapsed >= state.long_click_threshold then
        local cmds = buttons.resolve_button_command(state, button_name)
        if cmds and cmds["ON_LONG_CLICK"] ~= nil then
            state.arrow_color = 0xFF18D1CB
        end
    end
end

--- End button press: trigger single-click or long-click action.
--- @param state table  Shared state table
--- @param button_name string  Button identifier
function buttons.button_end(state, button_name)
    if not state.command_state[button_name] then
        -- Robustness: handle unexpected end without a begin
        log.debug("Button " .. button_name .. " ended without a begin - resetting state")
        state.arrow_color = 0xFF00FF00
        return
    end

    local elapsed = os.clock() - state.command_state[button_name].start_time

    if not state.command_state[button_name].is_continuous_mode and elapsed >= state.long_click_threshold then
        log.debug("Long click detected for " .. button_name)
        state.command_state[button_name].phase = "long_click"
        _trigger_button_command(state, button_name)
    else
        log.debug("Single click for " .. button_name)
        state.command_state[button_name].phase = "end"
        _trigger_button_command(state, button_name)
    end

    -- Clean up state to prevent stale data from corrupting subsequent clicks
    state.command_state[button_name] = nil
    state.arrow_color = 0xFF00FF00
end

return buttons
