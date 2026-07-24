-- ************************************************
-- LED Engine Module for Bravo++
-- Core LED state management: buffer operations, dirty-flag
-- tracking, and main orchestration of all sub-module LED
-- evaluations.
--
-- Injected dependencies:
--   dispatch: dispatch.lua module for mode/selection queries
--   button_map_leds_state: state storage for button LEDs
--   default_button_labels: list of physical button labels
--   bus_voltage_ref: dataref for sim/cockpit2/electrical/bus_volts
-- ************************************************

local log = require("bravo++.log")
local util = require("bravo++.util")

local M = {}

-- Internal state
local buffer = {} -- LED buffer: buffer[bank][bit] = boolean
local led_state_modified = false -- Dirty flag: true when buffer has changed since last HID send

-- Injected dependencies
local dispatch_module = nil
local button_map_leds_state = nil
local default_button_labels = nil
local bus_voltage_ref = nil

-- Sub-handler callbacks (pre-registered via set_sub_handlers)
local on_annunciator_row1 = nil
local on_annunciator_row2 = nil
local on_gear = nil
local on_switches = nil

-- First sync state
local leds_first_sync_done = false
local leds_first_sync_timer = nil
local led_first_time_delay = 4 -- seconds before setting LEDs

-- Master state tracking
local master_state = false

--- Initialize the LED engine module.
--- @param opts table { dispatch, button_map_leds_state, default_button_labels, bus_voltage_ref }
function M.init(opts)
    if not opts then
        log.error("led_engine: init called without opts")
        return
    end

    dispatch_module = opts.dispatch
    button_map_leds_state = opts.button_map_leds_state
    default_button_labels = opts.default_button_labels
    bus_voltage_ref = opts.bus_voltage_ref

    if not dispatch_module then
        log.error("led_engine: dispatch module is required")
        return
    end

    if not button_map_leds_state then
        log.error("led_engine: button_map_leds_state is required")
        return
    end

    if not default_button_labels then
        log.error("led_engine: default_button_labels is required")
        return
    end

    -- Initialize buffer: 4 banks, 8 bits each
    for bank = 1, 4 do
        buffer[bank] = {}
        for bit = 1, 8 do
            buffer[bank][bit] = false
        end
    end

    led_state_modified = false
    leds_first_sync_done = false
    leds_first_sync_timer = os.clock()
    master_state = false
end

--- Register sub-handler callbacks for pre-invocation during orchestration.
--- Callbacks are stored in closure scope for zero-allocation hot path.
--- @param handlers table { on_annunciator_row1, on_annunciator_row2, on_gear, on_switches }
function M.set_sub_handlers(handlers)
    if not handlers then
        log.error("led_engine: set_sub_handlers called without handlers")
        return
    end

    on_annunciator_row1 = handlers.on_annunciator_row1
    on_annunciator_row2 = handlers.on_annunciator_row2
    on_gear = handlers.on_gear
    on_switches = handlers.on_switches

    -- Validate all handlers are present
    if not on_annunciator_row1 then
        log.error("led_engine: on_annunciator_row1 handler is required")
    end
    if not on_annunciator_row2 then
        log.error("led_engine: on_annunciator_row2 handler is required")
    end
    if not on_gear then
        log.error("led_engine: on_gear handler is required")
    end
    if not on_switches then
        log.error("led_engine: on_switches handler is required")
    end
end

--- Write LED state to buffer at [bank][bit].
--- Sets dirty flag if value changed from previous state.
--- @param bank integer Bank number (1-4)
--- @param bit integer Bit position (1-8)
--- @param state boolean New LED state
function M.set_led(bank, bit, state)
    if not buffer[bank] then
        buffer[bank] = {}
    end

    local current = buffer[bank][bit]
    if state ~= current then
        buffer[bank][bit] = state
        led_state_modified = true
    end
end

--- Read current LED state at [bank][bit].
--- @param bank integer Bank number (1-4)
--- @param bit integer Bit position (1-8)
--- @return boolean|nil Current LED state, or nil if not initialized
function M.get_led(bank, bit)
    if not buffer[bank] then
        return nil
    end
    return buffer[bank][bit]
end

--- Reset all LEDs to off state.
function M.all_off()
    -- Turn off all button LEDs
    if default_button_labels and button_map_leds_state then
        for i = 1, #default_button_labels do
            local button_label = default_button_labels[i]
            local mode = dispatch_module.get_current_mode()
            local selection = dispatch_module.get_current_selection()

            if util.is_table(button_map_leds_state[mode]) then
                if
                    util.is_table(button_map_leds_state[mode]["ALL"])
                    and util.is_boolean(button_map_leds_state[mode]["ALL"][button_label])
                then
                    button_map_leds_state[mode]["ALL"][button_label] = false
                elseif
                    util.is_table(button_map_leds_state[mode][selection])
                    and util.is_boolean(button_map_leds_state[mode][selection][button_label])
                then
                    button_map_leds_state[mode][selection][button_label] = false
                end
            end
        end
    end

    -- Clear banks 2-4 of buffer
    for bank = 2, 4 do
        buffer[bank] = {}
        for bit = 1, 8 do
            buffer[bank][bit] = false
        end
    end

    -- Turn off all rocker switch LEDs
    if dispatch_module and dispatch_module.set_rocker_switch_led then
        for i = 1, 7 do
            local key = "SWITCH" .. i .. "_LED"
            dispatch_module.set_rocker_switch_led(key, false)
        end
    end

    led_state_modified = true
end

--- Prime button LED states for mode change detection.
--- Forces all button LED states to false so handle_led_changes
--- can detect changes to false if needed.
function M.prime_for_mode_change()
    if not default_button_labels or not button_map_leds_state then
        return
    end

    local mode = dispatch_module.get_current_mode()
    local selection = dispatch_module.get_current_selection()
    local led_detected = false

    for i = 1, #default_button_labels do
        local button_label = default_button_labels[i]

        -- Check "ALL" selection
        if util.is_table(button_map_leds_state[mode]) and util.is_table(button_map_leds_state[mode]["ALL"]) then
            if util.is_boolean(button_map_leds_state[mode]["ALL"][button_label]) then
                button_map_leds_state[mode]["ALL"][button_label] = false
                led_state_modified = true
                led_detected = true
            end
        elseif util.is_table(button_map_leds_state[mode]) and util.is_table(button_map_leds_state[mode][selection]) then
            if util.is_boolean(button_map_leds_state[mode][selection][button_label]) then
                button_map_leds_state[mode][selection][button_label] = false
                led_state_modified = true
                led_detected = true
            end
        end
    end

    if not led_detected then
        M.all_off()
    end
end

--- Get current dirty flag state.
--- @return boolean true if any LED state has changed since last send
function M.is_dirty()
    return led_state_modified
end

--- Clear dirty flag after successful HID send.
function M.clear_dirty()
    led_state_modified = false
end

--- Get current bus voltage.
--- @return number|nil Current bus voltage value
function M.get_bus_voltage()
    if not bus_voltage_ref then
        return nil
    end
    return bus_voltage_ref[0]
end

--- Get current button LED state for a given button name.
--- Used by UI to display LED states.
--- @param button_name string Button label (e.g. "PLT", "IAS")
--- @return boolean|nil Current LED state
function M.get_button_led_state(button_name)
    if not button_map_leds_state or not dispatch_module then
        return nil
    end

    local mode = dispatch_module.get_current_mode()
    local selection = dispatch_module.get_current_selection()

    if
        util.is_table(button_map_leds_state[mode]["ALL"])
        and util.is_boolean(button_map_leds_state[mode]["ALL"][button_name])
    then
        return button_map_leds_state[mode]["ALL"][button_name]
    elseif
        util.is_table(button_map_leds_state[mode][selection])
        and util.is_boolean(button_map_leds_state[mode][selection][button_name])
    then
        return button_map_leds_state[mode][selection][button_name]
    end

    return nil
end

--- Set button LED state in button_map_leds_state.
--- @param button_name string Button label
--- @param state boolean New LED state
function M.set_button_led_state(button_name, state)
    if not button_map_leds_state or not dispatch_module then
        return
    end

    local mode = dispatch_module.get_current_mode()
    local selection = dispatch_module.get_current_selection()
    local current_led_state = M.get_button_led_state(button_name)

    if current_led_state ~= nil and state ~= current_led_state then
        if
            util.is_table(button_map_leds_state[mode]["ALL"])
            and util.is_boolean(button_map_leds_state[mode]["ALL"][button_name])
        then
            button_map_leds_state[mode]["ALL"][button_name] = state
        elseif
            util.is_table(button_map_leds_state[mode][selection])
            and util.is_boolean(button_map_leds_state[mode][selection][button_name])
        then
            button_map_leds_state[mode][selection][button_name] = state
        end
        led_state_modified = true
    end
end

--- Evaluate button LED states from datarefs.
--- @param button_map_leds table Dataref bindings for button LEDs
--- @param button_map_leds_cond table Compiled conditions for button LEDs
--- @param button_map_leds_index table Optional indices for button LEDs
--- @param get_led_state_for_dataref function Dataref evaluator
local function handle_button_led_changes(
    button_map_leds,
    button_map_leds_cond,
    button_map_leds_index,
    get_led_state_for_dataref
)
    if not button_map_leds or not button_map_leds_state or not dispatch_module then
        return
    end

    local mode = dispatch_module.get_current_mode()
    local selection = dispatch_module.get_current_selection()

    for i = 1, #default_button_labels do
        local button_label = default_button_labels[i]
        local led_state_for_dataref = nil
        local led_state_for_button = nil

        -- Check "ALL" selection
        if util.is_table(button_map_leds[mode]["ALL"]) then
            local dataref = button_map_leds[mode]["ALL"][button_label]
            if dataref ~= nil then
                local index = nil
                if util.is_table(button_map_leds_index[mode]["ALL"]) then
                    index = button_map_leds_index[mode]["ALL"][button_label]
                end

                led_state_for_dataref =
                    get_led_state_for_dataref(dataref, button_map_leds_cond[mode]["ALL"][button_label], index)
                led_state_for_button = button_map_leds_state[mode]["ALL"][button_label]
            end
        elseif util.is_table(button_map_leds[mode][selection]) then
            local dataref = button_map_leds[mode][selection][button_label]

            if dataref ~= nil then
                local index = nil
                if util.is_table(button_map_leds_index[mode][selection]) then
                    index = button_map_leds_index[mode][selection][button_label]
                end

                led_state_for_dataref =
                    get_led_state_for_dataref(dataref, button_map_leds_cond[mode][selection][button_label], index)
                led_state_for_button = button_map_leds_state[mode][selection][button_label]
            end
        end

        if led_state_for_dataref ~= led_state_for_button then
            M.set_button_led_state(button_label, led_state_for_dataref)
        end
    end
end

--- Main orchestration function.
--- Evaluates all LED sub-systems in order:
--- button LEDs -> gear LEDs -> annunciator row 1 -> annunciator row 2 -> rocker switch LEDs
--- @param opts table  Options with button_map_leds, button_map_leds_cond,
---                    button_map_leds_index, get_led_state_for_dataref
--- @return boolean true if any LEDs were updated (dirty flag set)
function M.handle_led_changes(opts)
    -- First sync delay
    if not leds_first_sync_done then
        if os.clock() - leds_first_sync_timer > led_first_time_delay then
            leds_first_sync_done = true
        else
            return false
        end
    end

    local bus_voltage = opts and opts.bus_voltage
    if bus_voltage == nil and bus_voltage_ref then
        bus_voltage = bus_voltage_ref[0]
    end

    if bus_voltage and bus_voltage > 0 then
        master_state = true

        -- Handle button LEDs
        if opts and opts.button_map_leds then
            local success, err = pcall(function()
                handle_button_led_changes(
                    opts.button_map_leds,
                    opts.button_map_leds_cond,
                    opts.button_map_leds_index,
                    opts.get_led_state_for_dataref
                )
            end)
            if not success then
                log.error("LED Engine: handle_button_led_changes error: " .. tostring(err))
            end
        end

        -- Handle gear LEDs
        if on_gear then
            local success, err = pcall(on_gear)
            if not success then
                log.error("LED Engine: on_gear error: " .. tostring(err))
            end
        end

        -- Handle annunciator row 1
        if on_annunciator_row1 then
            local success, err = pcall(on_annunciator_row1)
            if not success then
                log.error("LED Engine: on_annunciator_row1 error: " .. tostring(err))
            end
        end

        -- Handle annunciator row 2
        if on_annunciator_row2 then
            local success, err = pcall(on_annunciator_row2)
            if not success then
                log.error("LED Engine: on_annunciator_row2 error: " .. tostring(err))
            end
        end

        -- Handle rocker switch LEDs
        if on_switches then
            local success, err = pcall(on_switches)
            if not success then
                log.error("LED Engine: on_switches error: " .. tostring(err))
            end
        end
    elseif master_state == true then
        log.debug("No voltage detected. Turning all LEDs off.")
        master_state = false
        M.all_off()
    end

    return led_state_modified
end

--- Get a shallow copy of the internal buffer (for HID bridge access).
--- Returns a new table so callers cannot mutate internal state.
--- @return table A shallow copy of the internal buffer
function M.get_buffer_snapshot()
    local snapshot = {}
    for bank = 1, 4 do
        snapshot[bank] = {}
        for bit = 1, 8 do
            snapshot[bank][bit] = buffer[bank] and buffer[bank][bit] or false
        end
    end

    return snapshot
end

return M
