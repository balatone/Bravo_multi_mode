--------------------------------------------------------------------------
-- Simple script that logs the last button that was pressed
-- This is used to configure the alt_selector_button in BravoMultiMode.lua
--------------------------------------------------------------------------

local log = require("log")

-- Set this to true if you want to log the last button that was pressed
local write_log = true

function find_assigned_buttons()
    local active_buttons = {}
    for btn = 1, 1024 do
        if button(btn) then
            table.insert(active_buttons, btn)
        end
    end
    return active_buttons
end

function log_last_buttons_pressed()
    buttons_pressed = find_assigned_buttons()
    for i = 1, #buttons_pressed do
        if buttons_pressed[i] > 0 or buttons_pressed[i] < 1024 then
            log.info("Last buttons pressed: " .. buttons_pressed[i])
        end
    end
end

if write_log then
    do_every_draw("log_last_buttons_pressed()")
end
