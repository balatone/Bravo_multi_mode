--------------------------------------------------------------------------
-- Simple script that logs the last button that was pressed
-- This is used to configure the alt_selector_button in BravoMultiMode.lua
--------------------------------------------------------------------------

local log = require("log")

-- Set this to true if you want to log the last button that was pressed
local write_log = false

function find_assigned_buttons()
    local active_buttons = {}
    for btn = 1, 1024 do
        if button(btn) then
            table.insert(active_buttons, btn)
        end
    end
    return active_buttons
end

local last_buttons_pressed = {}
local last_button_pressed = 0
function log_last_buttons_pressed()
    local buttons_pressed = find_assigned_buttons()

    for i = 1, #buttons_pressed do
        if table.find(last_buttons_pressed, buttons_pressed[i]) == nil and (buttons_pressed[i] > 0 and buttons_pressed[i] < 1024) then
            log.info("Last buttons pressed: " .. buttons_pressed[i])
            last_button_pressed = buttons_pressed[i]
            last_buttons_pressed = buttons_pressed
        end
    end
    huge_bubble(MOUSE_X, MOUSE_Y, "ButtonLogUtils","Use this for determining the ALT selector button assigned to your Honeycomb Bravo by X-Plane.", "Just turn the left selector knob to ALT and note the number.", "Last button pressed: " .. last_button_pressed)
end

-- Helper function to find index in table (used for cycling modes)
function table.find(t, value)
    for i, v in ipairs(t) do
        if v == value then return i end
    end
    return nil -- Not found.
end

if write_log then
    do_every_draw("log_last_buttons_pressed()")
end
