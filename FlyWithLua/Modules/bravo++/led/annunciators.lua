-- ************************************************
-- Annunciator LEDs Module for Bravo++
-- Evaluates Row 1 and Row 2 annunciator LED states
-- based on pre-compiled dataref conditions.
--
-- Injected dependencies:
--   annunciator_bindings: table of { dataref_table, condition_string }
--   eval_fn: function (dataref_table, condition_string, index?) -> boolean
-- ************************************************

local log = require("bravo++.log")
local util = require("bravo++.util")

local M = {}

-- Internal state (set during init)
local annunciator_bindings = nil
local eval_fn = nil

-- LED position constants for annunciators (shared with composition root)
-- Bank 2 bits 1-6 are gear LEDs; annunciators use bits 7-8 in Bank 2,
-- all of Bank 3, and bits 1-4 in Bank 4.
local LED_POSITIONS = {
    -- Bank 2 (bits 7-8, after gear LEDs)
    MASTER_WARNING = { 2, 7 },
    FIRE_WARNING = { 2, 8 },
    -- Bank 3 (all 8 bits)
    OIL_LOW_PRESSURE = { 3, 1 },
    FUEL_LOW_PRESSURE = { 3, 2 },
    ANTI_ICE = { 3, 3 },
    STARTER_ENGAGED = { 3, 4 },
    APU = { 3, 5 },
    MASTER_CAUTION = { 3, 6 },
    VACUUM = { 3, 7 },
    HYD_LOW_PRESSURE = { 3, 8 },
    -- Bank 4 (bits 1-4)
    AUX_FUEL_PUMP = { 4, 1 },
    PARKING_BRAKE = { 4, 2 },
    VOLTS_LOW = { 4, 3 },
    DOOR = { 4, 4 },
}

-- Row 1 annunciator labels (Bank 2: bits 7-8)
local ROW1_LABELS = {
    "MASTER_WARNING",
    "FIRE_WARNING",
}

-- Row 2 annunciator labels (Banks 3-4: all remaining annunciators)
local ROW2_LABELS = {
    "OIL_LOW_PRESSURE",
    "FUEL_LOW_PRESSURE",
    "ANTI_ICE",
    "STARTER_ENGAGED",
    "APU",
    "MASTER_CAUTION",
    "VACUUM",
    "HYD_LOW_PRESSURE",
    "AUX_FUEL_PUMP",
    "PARKING_BRAKE",
    "VOLTS_LOW",
    "DOOR",
}

--- Evaluate a single annunciator's dataref against its compiled condition.
--- Handles both scalar and array datarefs with proper nil guards.
--- Supports indexed bindings (e.g. ANTI_ICE_1_LED, ANTI_ICE_2_LED) where
--- the binding is a table of {dataref, condition} pairs keyed by integer index.
--- If any indexed binding evaluates true, the LED is on (OR logic).
--- Uses injected eval_fn for comparison.
--- @param label string Annunciator label (e.g. "MASTER_WARNING")
--- @return boolean true if LED should be on
local function evaluate_single_annunciator(label)
    local binding = annunciator_bindings and annunciator_bindings[label]
    if not binding then
        return false
    end

    -- Check if this is an indexed binding (table of {dataref, condition} pairs
    -- keyed by integer indices, e.g. ANTI_ICE_1_LED, ANTI_ICE_2_LED).
    -- A non-indexed binding has its dataref at binding[1] and it IS a magic table.
    -- An indexed binding has binding[1] as a regular Lua table (the first pair).
    local dataref = binding[1]

    if util.is_dataref_magic_table(dataref) then
        -- Non-indexed binding: { dataref_magic_table, "condition" }
        local condition = binding[2]
        if not condition then
            return false
        end
        return eval_fn(dataref, condition)
    else
        -- Indexed binding: { [1] = {dataref, cond}, [2] = {dataref, cond}, ... }
        -- OR logic: if ANY indexed dataref matches, the LED is on
        for _, pair in ipairs(binding) do
            if util.is_dataref_magic_table(pair[1]) and pair[2] then
                if eval_fn(pair[1], pair[2]) then
                    return true
                end
            end
        end
        return false
    end
end

--- Initialize the annunciator LEDs module.
--- @param opts table { annunciator_bindings: table, eval_fn: function }
function M.init(opts)
    if not opts then
        log.error("annunciator_leds: init called without opts")
        return
    end

    annunciator_bindings = opts.annunciator_bindings
    eval_fn = opts.eval_fn

    if not eval_fn then
        log.error("annunciator_leds: eval_fn is required")
        return
    end

    if not annunciator_bindings then
        log.warning("annunciator_leds: no annunciator_bindings provided")
    end
end

--- Evaluate Row 1 annunciators and write to LED engine buffer.
--- @param led_engine_module table with set_led(bank, bit, state) method
function M.evaluate_row1(led_engine_module)
    if not led_engine_module or not led_engine_module.set_led then
        return
    end

    for _, label in ipairs(ROW1_LABELS) do
        local pos = LED_POSITIONS[label]
        if pos then
            local state = evaluate_single_annunciator(label)
            led_engine_module.set_led(pos[1], pos[2], state)
        end
    end
end

--- Evaluate Row 2 annunciators and write to LED engine buffer.
--- @param led_engine_module table with set_led(bank, bit, state) method
function M.evaluate_row2(led_engine_module)
    if not led_engine_module or not led_engine_module.set_led then
        return
    end

    for _, label in ipairs(ROW2_LABELS) do
        local pos = LED_POSITIONS[label]
        if pos then
            local state = evaluate_single_annunciator(label)
            led_engine_module.set_led(pos[1], pos[2], state)
        end
    end
end

--- Convenience wrapper that evaluates both rows.
--- @param led_engine_module table with set_led(bank, bit, state) method
function M.evaluate_all(led_engine_module)
    M.evaluate_row1(led_engine_module)
    M.evaluate_row2(led_engine_module)
end

return M
