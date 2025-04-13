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
    local msg = ""
    for i = 1, #buttons_pressed do
        if buttons_pressed[i] < 180 or buttons_pressed[i] > 206 then
            msg = msg .. buttons_pressed[i] .. ", "   
        end
    end

    --huge_bubble(100, pos, "Last buttons pressed:", msg)
    if msg ~= "" then 
        logMsg("Last buttons pressed: " .. msg)
    end

end

function register_button_press()
    if button(172) then
        huge_bubble(100, pos, "Pressed 172")
    elseif button(173) then
        huge_bubble(100, pos, "Pressed 173")
    end
end


-- do_every_draw("register_button_press()")
-- do_every_draw("log_last_buttons_pressed()")
