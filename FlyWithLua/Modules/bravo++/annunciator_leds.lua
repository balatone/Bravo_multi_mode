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
-- Row 1 = Bank 2 (7 LEDs), Row 2 = Bank 3 (7 LEDs)
local LED_POSITIONS = {
    -- Row 1 (Bank 2)
    MASTER_WARNING = { 2, 1 },
    FIRE_WARNING = { 2, 2 },
    OIL_LOW_PRESSURE = { 2, 3 },
    FUEL_LOW_PRESSURE = { 2, 4 },
    ANTI_ICE = { 2, 5 },
    STARTER_ENGAGED = { 2, 6 },
    APU = { 2, 7 },
    -- Row 2 (Bank 3)
    MASTER_CAUTION = { 3, 1 },
    VACUUM = { 3, 2 },
    HYD_LOW_PRESSURE = { 3, 3 },
    AUX_FUEL_PUMP = { 3, 4 },
    PARKING_BRAKE = { 3, 5 },
    VOLTS_LOW = { 3, 6 },
    DOOR = { 3, 7 },
}

-- Row 1 annunciator labels (Bank 2: 7 annunciators)
local ROW1_LABELS = {
    "MASTER_WARNING",
    "FIRE_WARNING",
    "OIL_LOW_PRESSURE",
    "FUEL_LOW_PRESSURE",
    "ANTI_ICE",
    "STARTER_ENGAGED",
    "APU",
}

-- Row 2 annunciator labels (Bank 3: 7 annunciators)
local ROW2_LABELS = {
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
--- Uses injected eval_fn for comparison.
--- @param label string Annunciator label (e.g. "MASTER_WARNING")
--- @return boolean true if LED should be on
local function evaluate_single_annunciator(label)
    local binding = annunciator_bindings and annunciator_bindings[label]
    if not binding then
        return false
    end

    local dataref = binding[1]
    local condition = binding[2]

    if not util.is_dataref_magic_table(dataref) then
        return false
    end

    if not condition then
        return false
    end

    return eval_fn(dataref, condition)
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
