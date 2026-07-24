-- ************************************************
-- LED HID Bridge Module for Bravo++
-- Converts the LED buffer into a bit-packed HID feature
-- report and sends it to the Bravo device.
--
-- Injected dependencies:
--   device_handle: HID handle from hid_open()
--   bit_lib: bit library reference (bit.bor, bit.lshift)
-- ************************************************

-- luacheck: globals hid_send_filled_feature_report
local log = require("bravo++.log")
local util = require("bravo++.util")

local M = {}

-- Internal state (set during init)
local device_handle = nil
local bit_lib = nil
local button_map_leds_state = nil
local led_engine_module = nil

-- Pre-allocated report buffer: reused across assemble_report() calls
local report_data = { 0, 0, 0, 0 }

--- Convert button LED states into bank-1 byte via bit manipulation.
--- Uses injected button_map_leds_state from closure scope.
--- @param button_labels array of button name strings
--- @param dispatch_module dispatch module for mode/selection queries
--- @return integer bank-1 byte value
local function button_to_byte(button_labels, dispatch_module)
    local byte_val = 0

    for i = 1, #button_labels do
        local button_name = button_labels[i]
        local mode = dispatch_module.get_current_mode()
        local selection = dispatch_module.get_current_selection()

        local is_on = false

        if
            util.is_table(button_map_leds_state[mode]["ALL"])
            and button_map_leds_state[mode]["ALL"][button_name] == true
        then
            is_on = true
        elseif
            util.is_table(button_map_leds_state[mode][selection])
            and button_map_leds_state[mode][selection][button_name] == true
        then
            is_on = true
        end

        if is_on then
            byte_val = bit_lib.bor(byte_val, bit_lib.lshift(1, i - 1))
        end
    end

    return byte_val
end

--- Initialize the HID bridge module.
--- @param opts table { device_handle, bit_lib, button_map_leds_state, led_engine_module }
function M.init(opts)
    if not opts then
        log.error("led_hid_bridge: init called without opts")
        return
    end

    device_handle = opts.device_handle
    bit_lib = opts.bit_lib
    button_map_leds_state = opts.button_map_leds_state
    led_engine_module = opts.led_engine_module

    if not device_handle then
        log.error("led_hid_bridge: device_handle is required")
        return
    end

    if not bit_lib then
        log.error("led_hid_bridge: bit_lib is required")
        return
    end
end

--- Assemble the 4-byte HID report from LED buffer and button states.
--- Does NOT send; returns data only for testing/debugging.
--- @param buffer_ref table LED buffer (buffer[bank][bit])
--- @param default_button_labels array of button name strings
--- @param dispatch_module dispatch module for mode/selection queries
--- @return table|nil Array of 4 integers (bytes), or nil on invalid input
function M.assemble_report(buffer_ref, default_button_labels, dispatch_module)
    if not buffer_ref or not default_button_labels or not dispatch_module or not button_map_leds_state then
        return nil
    end

    -- Reset pre-allocated buffer in-place
    for bank = 1, 4 do
        report_data[bank] = 0
    end

    -- Bank 1: Button LEDs
    report_data[1] = button_to_byte(default_button_labels, dispatch_module)

    -- Banks 2-4: Buffer LEDs
    for bank = 2, 4 do
        if buffer_ref[bank] then
            for abit = 1, 8 do
                if buffer_ref[bank][abit] == true then
                    report_data[bank] = bit_lib.bor(report_data[bank], bit_lib.lshift(1, abit - 1))
                end
            end
        end
    end

    return report_data
end

--- Assemble and send the HID feature report.
--- On success, calls led_engine.clear_dirty() through the injected reference.
--- DSGN-001 spec signature: (buffer_ref, default_button_labels, dispatch_module)
--- @param buffer_ref table LED buffer (buffer[bank][bit])
--- @param default_button_labels array of button name strings
--- @param dispatch_module dispatch module for mode/selection queries
--- @return boolean true if send was successful (65 bytes written)
function M.assemble_and_send(buffer_ref, default_button_labels, dispatch_module)
    local data = M.assemble_report(buffer_ref, default_button_labels, dispatch_module)

    if not data then
        log.error("led_hid_bridge: Failed to assemble report")
        return false
    end

    local bytes_written = hid_send_filled_feature_report(device_handle, 0, 65, data[1], data[2], data[3], data[4])

    if bytes_written == 65 then
        -- Success: clear dirty flag through led_engine
        if led_engine_module and led_engine_module.clear_dirty then
            led_engine_module.clear_dirty()
        end
        return true
    elseif bytes_written == nil or bytes_written == -1 then
        log.error("LED HID Bridge: Feature report write failed, an error occurred")
        return false
    elseif bytes_written < 65 then
        log.error("LED HID Bridge: Feature report write failed, only " .. bytes_written .. " bytes written")
        return false
    end

    return false
end

return M
