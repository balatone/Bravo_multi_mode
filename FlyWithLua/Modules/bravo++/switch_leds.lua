-- ************************************************
-- Switch LEDs Module for Bravo++
-- Evaluates 7 rocker switch LEDs based on pre-compiled
-- dataref conditions.
--
-- Injected dependencies:
--   switch_bindings: table of { dataref_table, condition_string, optional_index }
--   dispatch_module: dispatch.lua module for rocker switch LED state
--   eval_fn: function (dataref_table, condition_string, index?) -> boolean
-- ************************************************

local log = require("bravo++.log")
local util = require("bravo++.util")

local M = {}

-- Internal state (set during init)
local switch_bindings = nil
local dispatch_module = nil
local eval_fn = nil
local led_engine_module_ref = nil

-- Number of rocker switches
local NUM_SWITCHES = 7

-- Switch LED position mapping: maps each switch label to {bank, bit} in the LED engine buffer.
-- Switch LEDs are assigned to Bank 1, bits 1-7 (bit 8 unused).
local SWITCH_LED_POSITIONS = {
    SWITCH1_LED = { 1, 1 },
    SWITCH2_LED = { 1, 2 },
    SWITCH3_LED = { 1, 3 },
    SWITCH4_LED = { 1, 4 },
    SWITCH5_LED = { 1, 5 },
    SWITCH6_LED = { 1, 6 },
    SWITCH7_LED = { 1, 7 },
}

--- Evaluate a single switch's dataref against its compiled condition.
--- Handles nil guards on dataref access.
--- @param binding table { dataref_table, condition_string, optional_index }
--- @return boolean true if LED should be on
local function evaluate_switch(binding)
    if not binding then
        return false
    end

    local dataref = binding[1]
    local condition = binding[2]
    local index = binding[3]

    if not util.is_dataref_magic_table(dataref) then
        return false
    end

    if not condition then
        return false
    end

    return eval_fn(dataref, condition, index)
end

--- Initialize the switch LEDs module.
--- @param opts table { switch_bindings: table, dispatch_module: table, eval_fn: function, led_engine_module: table }
function M.init(opts)
    if not opts then
        log.error("switch_leds: init called without opts")
        return
    end

    switch_bindings = opts.switch_bindings
    dispatch_module = opts.dispatch_module
    eval_fn = opts.eval_fn
    led_engine_module_ref = opts.led_engine_module

    if not eval_fn then
        log.error("switch_leds: eval_fn is required")
        return
    end

    if not dispatch_module then
        log.error("switch_leds: dispatch_module is required")
        return
    end

    if not led_engine_module_ref then
        log.error("switch_leds: led_engine_module is required")
        return
    end

    if not switch_bindings then
        log.warning("switch_leds: no switch_bindings provided")
    end
end

--- Evaluate all rocker switch LED states and update dispatch module.
--- Iterates SWITCH1_LED through SWITCH7_LED, writing to LED engine buffer
--- via set_led() for each switch with a configured binding.
function M.evaluate()
    if not dispatch_module or not led_engine_module_ref then
        return
    end

    for i = 1, NUM_SWITCHES do
        local switch_label = "SWITCH" .. i .. "_LED"
        local binding = switch_bindings and switch_bindings[switch_label]

        if not binding then
            -- No binding configured for this switch; skip
        elseif not util.is_dataref_magic_table(binding[1]) then
            -- Invalid dataref; skip
        else
            local current_state = evaluate_switch(binding)

            -- Check if the state has changed to minimize unnecessary updates
            local previous_state = dispatch_module.get_rocker_switch_led
                and dispatch_module.get_rocker_switch_led(switch_label)

            if previous_state ~= current_state then
                if dispatch_module.set_rocker_switch_led then
                    dispatch_module.set_rocker_switch_led(switch_label, current_state)
                end

                -- Write to LED engine buffer via set_led() with position mapping
                local led_pos = SWITCH_LED_POSITIONS[switch_label]
                if led_pos then
                    led_engine_module_ref.set_led(led_pos[1], led_pos[2], current_state)
                end
            end
        end
    end
end

--- Get current rocker switch LED states from dispatch module.
--- Returns map of switch label to boolean state.
--- @return table Map of { "SWITCH1_LED" = boolean, ... }
function M.get_current_states()
    if not dispatch_module or not dispatch_module.get_rocker_switch_led then
        return {}
    end

    local result = {}
    for i = 1, NUM_SWITCHES do
        local switch_label = "SWITCH" .. i .. "_LED"
        result[switch_label] = dispatch_module.get_rocker_switch_led(switch_label) or false
    end

    return result
end

return M
