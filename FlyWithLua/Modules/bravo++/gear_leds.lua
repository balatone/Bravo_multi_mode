-- ************************************************
-- Gear LEDs Module for Bravo++
-- Implements the three-channel green/red landing gear
-- LED state machine: deployed=green, stowed=off, moving=red.
--
-- Injected dependencies:
--   gear_dataref: dataref magic table or nil (fixed gear)
--   led_constants: table mapping LED names to {bank, bit} positions
-- ************************************************

local log = require("bravo++.log")

local M = {}

-- Internal state (set during init)
local gear_dataref = nil
local led_constants = nil

-- Module-level constants: allocated once at load time, reused in hot path
local CHANNEL_INDICES = { 0, 1, 2 }
local LED_KEYS = {
    "LED_LDG_N_GREEN",
    "LED_LDG_N_RED",
    "LED_LDG_L_GREEN",
    "LED_LDG_L_RED",
    "LED_LDG_R_GREEN",
    "LED_LDG_R_RED",
}

--- Interpret a single gear channel value to {green, red} state pair.
--- 0 = stowed (both off), 1 = deployed (green), other = moving (red)
--- @param value number|nil Gear channel value
--- @return boolean green, boolean red
local function interpret_channel(value)
    if value == nil then
        return false, false
    end

    if value == 0 then
        -- Gear stowed: both LEDs off
        return false, false
    elseif value == 1 then
        -- Gear deployed: green on, red off
        return true, false
    else
        -- Gear moving: green off, red on
        return false, true
    end
end

--- Initialize the gear LEDs module.
--- @param opts table { gear_dataref: table|nil, led_constants: table }
function M.init(opts)
    if not opts then
        log.error("gear_leds: init called without opts")
        return
    end

    gear_dataref = opts.gear_dataref
    led_constants = opts.led_constants

    if not led_constants then
        log.error("gear_leds: led_constants is required")
        return
    end
end

--- Evaluate gear LED states and write to LED engine buffer.
--- Reads gear dataref values at indices 0, 1, 2 (nose, left, right).
--- @param led_engine_module table with set_led(bank, bit, state) method
function M.evaluate(led_engine_module)
    if not led_engine_module or not led_engine_module.set_led then
        return
    end

    -- Channel order: nose (index 0), left (index 1), right (index 2)
    -- LED constant order matches: N_GREEN, N_RED, L_GREEN, L_RED, R_GREEN, R_RED
    for ch = 1, 3 do
        local green_state = false
        local red_state = false

        if gear_dataref ~= nil then
            local value = gear_dataref[CHANNEL_INDICES[ch]]
            green_state, red_state = interpret_channel(value)
        end
        -- If gear_dataref is nil (fixed gear), both states remain false

        -- Write green LED
        local green_key = LED_KEYS[(ch - 1) * 2 + 1]
        local green_pos = led_constants[green_key]
        if green_pos then
            led_engine_module.set_led(green_pos[1], green_pos[2], green_state)
        end

        -- Write red LED
        local red_key = LED_KEYS[(ch - 1) * 2 + 2]
        local red_pos = led_constants[red_key]
        if red_pos then
            led_engine_module.set_led(red_pos[1], red_pos[2], red_state)
        end
    end
end

--- Get current interpreted gear state without writing to buffer.
--- Returns array of 3 {green, red} pairs.
--- @return table|nil Array of {green, red} pairs, or nil if not initialized
function M.get_gear_state()
    if not led_constants then
        return nil
    end

    local result = {}

    for i = 1, 3 do
        local green_state = false
        local red_state = false

        if gear_dataref ~= nil then
            local value = gear_dataref[CHANNEL_INDICES[i]]
            green_state, red_state = interpret_channel(value)
        end

        result[i] = { green = green_state, red = red_state }
    end

    return result
end

return M
