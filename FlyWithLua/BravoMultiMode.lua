require("bit")
require("graphics")

if not SUPPORTS_FLOATING_WINDOWS then
    -- to make sure the script doesn't stop old FlyWithLua versions
    logMsg("floating windows not supported by your FlyWithLua version")
    return
end

-- Get aircraft directory from X-Plane's AIRCRAFT_FILENAME
local aircraft_dir = string.match(AIRCRAFT_PATH, "(.*[/\\])")
local nav_cfg_path = aircraft_dir .. "bravo_multi-mode.cfg"

-- Table to hold dataref assignments
local nav_bindings = {}

-- Check if config file exists
local cfg_file = io.open(nav_cfg_path, "r")
if cfg_file then
    for line in cfg_file:lines() do
        -- Skip comments/empty lines and parse key=value
        if not line:match("^%s*#") and line:match("=") then
            local key, value = line:match("%s*([%w_]+)%s*=%s*(.+)%s*")
            if key and value then
                nav_bindings[key] = value:gsub("^\"(.*)\"$", "%1") -- Remove quotes if present
            end
        end
    end
    cfg_file:close()
else
    logMsg("FlyWithLua Error: bravo_multi-mode.cfg not found in " .. aircraft_dir)
    return -- Stop script if config is missing
end

-- Assign datarefs from config (with validation)
local required_keys = {
    "MODES", "PFD_SELECTOR_LABELS", "MFD_SELECTOR_LABELS",
    "PFD_ALT_OUTER_UP", "PFD_ALT_OUTER_DOWN", "PFD_ALT_INNER_UP", "PFD_ALT_INNER_DOWN",
    "MFD_ALT_OUTER_UP", "MFD_ALT_OUTER_DOWN", "MFD_ALT_INNER_UP", "MFD_ALT_INNER_DOWN",
    "AUTO_ALT_UP", "AUTO_ALT_DOWN",
    "PFD_VS_OUTER_UP", "PFD_VS_OUTER_DOWN", "PFD_VS_INNER_UP", "PFD_VS_INNER_DOWN",
    "MFD_VS_OUTER_UP", "MFD_VS_OUTER_DOWN", "MFD_VS_INNER_UP", "MFD_VS_INNER_DOWN",
    "AUTO_VS_UP", "AUTO_VS_DOWN",
    "PFD_HDG_OUTER_UP", "PFD_HDG_INNER_UP",
    "PFD_HDG_OUTER_DOWN", "PFD_HDG_INNER_DOWN",
    "AUTO_HDG_UP", "AUTO_HDG_DOWN",
    "PFD_CRS_UP", "PFD_CRS_DOWN",
    "MFD_CRS_UP", "MFD_CRS_DOWN",
    "AUTO_CRS_UP", "AUTO_CRS_DOWN",
    "PFD_IAS_OUTER_UP", "PFD_IAS_INNER_UP", "PFD_IAS_OUTER_DOWN", "PFD_IAS_INNER_DOWN",
    "MFD_IAS_OUTER_UP", "MFD_IAS_INNER_UP", "MFD_IAS_OUTER_DOWN", "MFD_IAS_INNER_DOWN",
    "AUTO_IAS_DOWN", "AUTO_IAS_DOWN",
    "PFD_PLT_BUTTON", "MFD_PLT_BUTTON", "AUTO_PLT_BUTTON",
    "PFD_ALT_IAS_BUTTON", "MFD_ALT_IAS_BUTTON", "PFD_VS_IAS_BUTTON", "MFD_VS_IAS_BUTTON", "PFD_HDG_IAS_BUTTON",
    "MFD_HDG_IAS_BUTTON", "PFD_IAS_IAS_BUTTON", "MFD_IAS_IAS_BUTTON", "AUTO_IAS_BUTTON",
    "PFD_ALT_VS_BUTTON", "MFD_ALT_VS_BUTTON", "PFD_VS_VS_BUTTON", "MFD_VS_VS_BUTTON", "PFD_IAS_VS_BUTTON",
    "MFD_IAS_VS_BUTTON", "AUTO_VS_BUTTON",
    "PFD_ALT_ALT_BUTTON", "MFD_ALT_ALT_BUTTON", "PFD_VS_ALT_BUTTON", "MFD_VS_ALT_BUTTON", "PFD_IAS_ALT_BUTTON",
    "MFD_IAS_ALT_BUTTON", "AUTO_ALT_BUTTON",
    "PFD_IAS_REV_BUTTON", "MFD_IAS_REV_BUTTON", "AUTO_REV_BUTTON",
    "PFD_IAS_APR_BUTTON", "MFD_IAS_APR_BUTTON", "AUTO_APR_BUTTON",
    "PFD_IAS_NAV_BUTTON", "MFD_IAS_NAV_BUTTON", "AUTO_NAV_BUTTON",
    "PFD_IAS_HDG_BUTTON", "MFD_IAS_HDG_BUTTON", "AUTO_HDG_BUTTON"
}

--[[for _, key in ipairs(required_keys) do
    if not nav_bindings[key] then
        logMsg("FlyWithLua Error: Missing key in bravo_multi-mode.cfg - " .. key)
        return
    end
end
]]

local function create_table(value_string)
    local value_table = {}
    local idx = 1

    if value_string == nil then
        return value_table
    end

    local gmatch_result = string.gmatch(value_string, "[^,]+")
    if gmatch_result then
        for value in gmatch_result do
            value_table[idx] = value
            idx = idx + 1
        end
    else
        logMsg("Error: " ..
            value_string ..
            "is not a valid comma-separated value. Make sure the values only contain alpha-numeric and non-special characters. If you want a blank value, use one or more spaces.")
    end
    return value_table
end

-- Mode management
-- local modes = {"AUTO", "PFD", "MFD"} -- Add more modes as needed
local modes = create_table(nav_bindings.MODES)
local current_mode = modes[1]
local outer_inner_modes = { "outer", "inner" }
local current_cf_mode = outer_inner_modes[1]

-- Bindings for the selector knob
local default_selections = { "ALT", "VS", "HDG", "CRS", "IAS" }
local current_selection = default_selections[1]

local current_selection_label = default_selections[1]

logMsg("Initializing the selector labels map...")
local selection_map_labels = {}
for i = 1, #modes do
    if modes[i] ~= "AUTO" then
        local key = modes[i] .. "_SELECTOR_LABELS"
        selection_map_labels[modes[i]] = create_table(nav_bindings[key])
        logMsg("Adding " .. key .. " = " .. nav_bindings[key])
    else
        selection_map_labels[modes[i]] = default_selections
        logMsg("Adding default selector labels.")
    end
end

-- The button labels that will be displayed on the console
local default_button_labels = { "HDG", "NAV", "APR", "REV", "ALT", "VS", "IAS", "PLT" }
local no_button_labels = { "   ", "   ", "   ", "   ", "   ", "   ", "   ", "   " }
local current_buttons = default_button_labels

logMsg("Initializing the button labels map...")
local button_map_labels = {}
for i = 1, #modes do
    local select_map = {}
    for j = 1, #default_selections do
        select_map[default_selections[j]] = {}
        if modes[i] ~= "AUTO" then
            local key = modes[i] .. "_" .. default_selections[j] .. "_BUTTON_LABELS"
            if nav_bindings[key] ~= nil then
                select_map[default_selections[j]] = create_table(nav_bindings[key])
                button_map_labels[modes[i]] = select_map
                logMsg("Adding " .. key .. " = " .. nav_bindings[key])
            else
                select_map[default_selections[j]] = no_button_labels
                button_map_labels[modes[i]] = select_map
                logMsg("No binding found for " .. key .. ". Using no labels.")
            end
        else
            select_map[default_selections[j]] = default_button_labels
            button_map_labels[modes[i]] = select_map
            logMsg("Adding default button labels.")
        end
    end
end

-- The button actions that will be used depending on mode and selection
logMsg("Initializing the button action map...")
local button_map_actions = {}
for i = 1, #modes do
    button_map_actions[modes[i]] = {}
    local select_map = {}
    for j = 1, #default_selections do
        select_map[default_selections[j]] = {}
        for k = 1, #default_button_labels do
            local full_key = modes[i] .. "_" .. default_button_labels[k] .. "_BUTTON"
            if default_selections[j] == "ALT" and nav_bindings[full_key] then
                button_map_actions[modes[i]][default_button_labels[k]] = nav_bindings[full_key]
                logMsg("Adding " .. full_key .. " = " .. nav_bindings[full_key])
            end
            local key = modes[i] .. "_" .. default_selections[j]
            full_key = key .. "_" .. default_button_labels[k] .. "_BUTTON"
            if nav_bindings[full_key] then
                select_map[default_selections[j]][default_button_labels[k]] = nav_bindings[full_key]
                button_map_actions[modes[i]] = select_map
                logMsg("Adding " .. full_key .. " = " .. nav_bindings[full_key])
            end
        end
    end
end

-- The button led that will be displayed depending on mode and selection
logMsg("Initializing the button led map...")
local button_map_leds = {}
local button_map_leds_state = {}
for i = 1, #modes do
    button_map_leds[modes[i]] = {}
    button_map_leds_state[modes[i]] = {}
    local select_map = {}
    local select_map2 = {}
    for j = 1, #default_selections do
        select_map[default_selections[j]] = {}
        select_map2[default_selections[j]] = {}
        for k = 1, #default_button_labels do
            local full_key = modes[i] .. "_" .. default_button_labels[k] .. "_BUTTON_LED"
            if default_selections[j] == "ALT" and nav_bindings[full_key] then
                button_map_leds[modes[i]][default_button_labels[k]] = nav_bindings[full_key]
                button_map_leds_state[modes[i]][default_button_labels[k]] = false
                logMsg("Adding " .. full_key .. " = " .. nav_bindings[full_key])
            end
            local key = modes[i] .. "_" .. default_selections[j]
            full_key = key .. "_" .. default_button_labels[k] .. "_BUTTON_LED"
            if nav_bindings[full_key] then
                select_map[default_selections[j]][default_button_labels[k]] = nav_bindings[full_key]
                button_map_leds[modes[i]] = select_map
                select_map2[default_selections[j]][default_button_labels[k]] = false
                button_map_leds_state[modes[i]] = select_map2
                logMsg("Adding " .. full_key .. " = " .. nav_bindings[full_key])
            end
        end
    end
end

--[[local value = nil
if button_map_leds_state["SYS"]["ALT"]["PLT"] == false then
    value = "false"
elseif button_map_leds_state["SYS"]["ALT"]["PLT"] == true then
    value = "true"
end
logMsg("button_map_leds_state[SYS][ALT][PLT]: " .. value)]]

-- The actions that will be triggered when twisting the right knob depedning on mode and selection
logMsg("Initializing the twist knob action map...")
local up_down = { "UP", "DOWN" }
local outer_inner = { "OUTER", "INNER" }
local twist_knob_map_actions = {}
for i = 1, #modes do
    twist_knob_map_actions[modes[i]] = {}
    local select_map = {}
    for j = 1, #default_selections do
        select_map[default_selections[j]] = {}
        local outer_map = {}
        for l = 1, #outer_inner do
            local oi = outer_inner[l]
            outer_map[oi] = {}
            for k = 1, #up_down do
                local key = modes[i] .. "_" .. default_selections[j]
                if outer_inner[l] == "INNER" and nav_bindings[key .. "_" .. up_down[k]] then
                    local dir = up_down[k]
                    local full_key = key .. "_" .. dir
                    select_map[default_selections[j]][dir] = nav_bindings[full_key]
                    twist_knob_map_actions[modes[i]] = select_map
                    logMsg("Adding " .. full_key .. " = " .. nav_bindings[full_key])
                end
                if nav_bindings[key .. "_" .. outer_inner[l] .. "_" .. up_down[k]] then
                    local dir = up_down[k]
                    local full_key = key .. "_" .. oi .. "_" .. dir
                    outer_map[oi][dir] = nav_bindings[full_key]
                    select_map[default_selections[j]] = outer_map
                    twist_knob_map_actions[modes[i]] = select_map
                    logMsg("Adding " .. full_key .. " = " .. nav_bindings[full_key] .. " to " .. oi)
                end
            end
        end
    end
end

-- imgui only works inside a floating window, so we need to create one first:
local height = 30 + 30 * #modes
my_floating_wnd = float_wnd_create(400, height, 1, false)
float_wnd_set_title(my_floating_wnd, "Bravo multi-mode")
-- float_wnd_set_position(my_floating_wnd, SCREEN_WIDTH * 2/3 + 50, SCREEN_HEIGHT * 1/6)
float_wnd_set_position(my_floating_wnd, SCREEN_WIDTH * 0.25, SCREEN_HEIGHT * 0.25)
float_wnd_set_ondraw(my_floating_wnd, "on_draw_floating_window")
-- float_wnd_set_onclick(my_floating_wnd, "on_click_floating_window")
float_wnd_set_onclose(my_floating_wnd, "on_close_floating_window")

function on_draw_floating_window(my_floating_wnd, x3, y3)
    local offset_mode = -20
    local v_spacing = -30
    local h_spacing = 50
    local offset_selection = 10
    local v_offset = y3 + height

    for i = 1, #modes do
        if current_mode == modes[i] then
            glColor3f(0, 1, 0) -- Green for default
            offset_selection = offset_mode
        else
            glColor3f(0.2, 0.2, 0.2) -- Grey
        end
        draw_string_Helvetica_18(x3, v_offset + offset_mode, modes[i])
        offset_mode = offset_mode + v_spacing
    end

    glColor3f(1, 1, 1) -- White
    draw_string_Helvetica_18(x3 + 80, v_offset + offset_selection, current_selection_label)

    -- offset_mode = offset_mode + v_spacing	
    local h_offset = 0
    for i = 1, #current_buttons do
        -- logMsg("current mode: " .. "[" .. current_mode .. "][" .. current_selection .. "][" .. default_button_labels[i] .. "]")
        if is_boolean(button_map_leds_state[current_mode][default_button_labels[i]]) then
            if button_map_leds_state[current_mode][default_button_labels[i]] == true then
                glColor3f(1, 1, 1)       -- White
            else
                glColor3f(0.6, 0.6, 0.6) -- Yellow
            end
        elseif is_table(button_map_leds_state[current_mode][current_selection]) and button_map_leds_state[current_mode][current_selection][default_button_labels[i]] == true then
            glColor3f(1, 1, 1)       -- White
        else
            glColor3f(0.6, 0.6, 0.6) -- Yellow
        end
        if i ~= #current_buttons then
            draw_string_Helvetica_18(x3 + h_offset, v_offset + offset_mode, current_buttons[i])
        else
            -- graphics.draw_rectangle(x3 + h_offset, v_offset + offset_mode - v_spacing, x3 + h_offset + h_spacing, v_offset + offset_mode - 2*v_spacing)
            -- glColor3f(0, 0, 0) -- Black
            draw_string_Times_Roman_24(x3 + h_offset, v_offset + offset_mode - v_spacing, current_buttons[i])
        end
        h_offset = h_offset + h_spacing
    end

    local offset_mode = -20

    for i = 1, #outer_inner_modes do
        if current_cf_mode == outer_inner_modes[i] then
            glColor3f(0, 1, 0) -- Green for default
            offset_selection = offset_mode
        else
            glColor3f(0.2, 0.2, 0.2) -- Balck semitransparent
        end
        draw_string_Helvetica_18(x3 + 290, v_offset + offset_mode, outer_inner_modes[i])
        offset_mode = offset_mode + v_spacing
    end
end

function on_close_floating_window(my_floating_wnd)
    if bravo then
        hid_close(bravo)
    end
end

-- Determine the position of the selector knob
local bravo = hid_open(0x294B, 0x1901) -- Honeycomb Bravo VID/PID

if bravo then
    hid_set_nonblocking(bravo, 1)
end

function find_position(n)
    if n == 0 or (bit.band(n, (n - 1)) ~= 0) then
        return -1
    end

    local pos = 1;
    local val = 1;
    while bit.band(val, n) == 0 do
        val = bit.lshift(val, 1)
        pos = pos + 1
    end
    return pos
end

function refresh_selector_hid()
    local pos = 0
    local start_time = os.clock()
    local num, data1, data2, data3, data4, data5, data6, data7, data8, data9, data10, data11, data12, data13, data14, data15, data16, data17, data18 =
        hid_read(bravo, 64)
    selector = data15
    if selector and selector > 0 then
        idx = 6 - find_position(selector)
        set_current_selector(idx)
    end
end

-- Define button numbers for each selector position
local alt_selector_button = nav_bindings.ALT_SELECTOR and nav_bindings.ALT_SELECTOR + 0 or 0
local selector_buttons = {}
if alt_selector_button and alt_selector_button > 0 then
    logMsg("ALT_SELECTOR was set to " .. alt_selector_button)
    for i = 1, 5, 1 do
        selector_buttons[i] = alt_selector_button - i + 1
        logMsg("Selector " .. default_selections[i] .. " set to button " .. selector_buttons[i])
    end
end

function refresh_selector()
    for idx, button_num in ipairs(selector_buttons) do
        if button(button_num) then
            -- logMsg("Selector is at position: " .. idx)
            set_current_selector(idx) -- Update your logic here
            break
        end
    end
end

local index = 1
function cycle_selector()
    if index < 5 then
        index = index + 1
    else
        index = 1
    end
end

-- Create a custom command for bravo knob increase
create_command(
    "FlyWithLua/custom/cycle_selector",
    "Cycle the selection (use only when Bravo hardware is not available) ",
    "cycle_selector()", -- Call Lua function when pressed
    "",
    ""
)

function refresh_selector_mock()
    set_current_selector(index)
end

-- Choose the available method for updating the selector
if bravo then
    if alt_selector_button > 0 then
        do_every_draw("refresh_selector()")
    else
        do_every_draw("refresh_selector_hid()")
    end
else
    do_every_draw("refresh_selector_mock()")
end

-- Function to cycle through modes
function cycle_mode()
    local index = table.find(modes, current_mode)
    index = (index % #modes) + 1
    current_mode = modes[index]
    all_leds_off()
end

-- Create a custom command for changing mode
create_command(
    "FlyWithLua/custom/mode_button",
    "Bravo++ toggles mode button",
    "cycle_mode()", -- Call Lua function when pressed
    "",
    ""
)

-- Function to cycle through outer/inner modes
function cycle_cf_mode()
    local index = table.find(outer_inner_modes, current_cf_mode)
    index = (index % #outer_inner_modes) + 1
    current_cf_mode = outer_inner_modes[index]
end

-- Create a custom command for changing cf mode
create_command(
    "FlyWithLua/custom/cf_mode_button",
    "Bravo++ toggles cf mode button",
    "cycle_cf_mode()", -- Call Lua function when pressed
    "",
    ""
)

function set_current_selector(idx)
    index = idx
    if current_selection_label ~= selection_map_labels[current_mode][index] then
        current_selection_label = selection_map_labels[current_mode][index]
        current_selection = default_selections[index]
        all_leds_off()
    end
end

function set_current_buttons()
    if button_map_labels[current_mode][current_selection] then
        current_buttons = button_map_labels[current_mode][current_selection]
    end
end

-- Update the currently available buttons
do_every_draw("set_current_buttons()")

-----------------------------------------------------
--- HANDLE TWIST-KNOB THAT INCREASES/DECREASES VALUES
-----------------------------------------------------
local last_click_time = 0
local debounce_delay = 0.05 -- 50ms

function handle_bravo_knob_increase()
    local current_time = os.clock()
    local current_twist_knob_action = twist_knob_map_actions[current_mode][current_selection]
    if current_time - last_click_time > debounce_delay then
        if current_twist_knob_action["UP"] then
            command_once(current_twist_knob_action["UP"])
            last_click_time = current_time
        elseif current_cf_mode == "outer" and current_twist_knob_action["OUTER"] then
            command_once(current_twist_knob_action["OUTER"]["UP"])
            last_click_time = current_time
        elseif current_cf_mode == "inner" and current_twist_knob_action["INNER"] then
            command_once(current_twist_knob_action["INNER"]["UP"])
            last_click_time = current_time
        else
            logMsg("Nothing to do.")
        end
    end
end

create_command(
    "FlyWithLua/custom/knob_increase_handler",
    "Handle button on bravo that increments values",
    "handle_bravo_knob_increase()", -- Call Lua function when pressed
    "",
    ""
)

function handle_bravo_knob_decrease()
    local current_twist_knob_action = twist_knob_map_actions[current_mode][current_selection]
    if current_twist_knob_action["DOWN"] then
        command_once(current_twist_knob_action["DOWN"])
    elseif current_cf_mode == "outer" and current_twist_knob_action["OUTER"] then
        command_once(current_twist_knob_action["OUTER"]["DOWN"])
    elseif current_cf_mode == "inner" and current_twist_knob_action["INNER"] then
        command_once(current_twist_knob_action["INNER"]["DOWN"])
    else
        logMsg("Nothing to do.")
    end
end

create_command(
    "FlyWithLua/custom/knob_decrease_handler",
    "Handle button on bravo that decrements values",
    "handle_bravo_knob_decrease()", -- Call Lua function when pressed
    "",
    ""
)

--------------------------------------
---- BUTTON HANDLING
--------------------------------------
function handle_bravo_button(button_name)
    -- logMsg("[" .. current_mode .. "][" .. current_selection .. "][" .. button_name .. "]")
    if button_map_actions[current_mode][current_selection][button_name] then
        local command = button_map_actions[current_mode][current_selection][button_name]
        command_once(command)
    elseif button_map_actions[current_mode][button_name] then
        local command = button_map_actions[current_mode][button_name]
        command_once(command)
    else
        logMsg("Do nothing!")
    end
end

-- Autopilot button
function handle_bravo_autopilot_button()
    handle_bravo_button("PLT")
end

-- Create a custom command for bravo knob increase
create_command(
    "FlyWithLua/custom/autopilot_button",
    "Bravo++ toggles autopilot button",
    "handle_bravo_autopilot_button()", -- Call Lua function when pressed
    "",
    ""
)

-- IAS button
function handle_bravo_ias_button()
    handle_bravo_button("IAS")
end

-- Create a custom command for bravo knob increase
create_command(
    "FlyWithLua/custom/ias_button",
    "Bravo++ toggles ias button",
    "handle_bravo_ias_button()", -- Call Lua function when pressed
    "",
    ""
)

-- VS button
function handle_bravo_vs_button()
    handle_bravo_button("VS")
end

-- Create a custom command for bravo knob increase
create_command(
    "FlyWithLua/custom/vs_button",
    "Bravo++ toggles vs button",
    "handle_bravo_vs_button()", -- Call Lua function when pressed
    "",
    ""
)

-- ALT button
function handle_bravo_alt_button()
    handle_bravo_button("ALT")
end

-- Create a custom command for bravo knob increase
create_command(
    "FlyWithLua/custom/alt_button",
    "Bravo++ toggles alt button",
    "handle_bravo_alt_button()", -- Call Lua function when pressed
    "",
    ""
)

-- REV button
function handle_bravo_rev_button()
    handle_bravo_button("REV")
end

-- Create a custom command for bravo knob increase
create_command(
    "FlyWithLua/custom/rev_button",
    "Bravo++ toggles rev button",
    "handle_bravo_rev_button()", -- Call Lua function when pressed
    "",
    ""
)

-- APR button
function handle_bravo_apr_button()
    handle_bravo_button("APR")
end

-- Create a custom command for bravo knob increase
create_command(
    "FlyWithLua/custom/apr_button",
    "Bravo++ toggles apr button",
    "handle_bravo_apr_button()", -- Call Lua function when pressed
    "",
    ""
)

-- NAV button
function handle_bravo_nav_button()
    handle_bravo_button("NAV")
end

-- Create a custom command for bravo knob increase
create_command(
    "FlyWithLua/custom/nav_button",
    "Bravo++ toggles nav button",
    "handle_bravo_nav_button()", -- Call Lua function when pressed
    "",
    ""
)

-- HDG button
function handle_bravo_hdg_button()
    handle_bravo_button("HDG")
end

-- Create a custom command for bravo knob increase
create_command(
    "FlyWithLua/custom/hdg_button",
    "Bravo++ toggles hdg button",
    "handle_bravo_hdg_button()", -- Call Lua function when pressed
    "",
    ""
)

local button_state_modified = false

-- BUTTON LED handling
function get_led_state(button_name)
    if is_boolean(button_map_leds_state[current_mode][button_name]) then
        logMsg("get_led_state for mode " .. current_mode .. " and button name " .. button_name)
        return button_map_leds_state[current_mode][button_name]
    elseif is_table(button_map_leds_state[current_mode][current_selection]) and is_boolean(button_map_leds_state[current_mode][current_selection][button_name]) then
        logMsg("get_led_state for mode " ..
            current_mode .. ", current selection " .. current_selection .. " and button name " .. button_name)
        return button_map_leds_state[current_mode][current_selection][button_name]
    else
        logMsg("Return nil for mode " .. current_mode .. " and button_name " .. button_name)
        return nil
    end
end

function set_led_state(button_name, state)
    if get_led_state(button_name) ~= nil and state ~= get_led_state(button_name) then
        logMsg("get_led_state for " .. button_name .. " = " .. tostring(get_led_state(button_name)))
        if is_boolean(button_map_leds_state[current_mode][button_name]) then
            button_map_leds_state[current_mode][button_name] = state
        elseif is_table(button_map_leds_state[current_mode][current_selection]) and  is_boolean(button_map_leds_state[current_mode][current_selection][button_name]) then
            button_map_leds_state[current_mode][current_selection][button_name] = state
        end
        button_state_modified = true
    else
        if get_led_state(button_name) ~= nil then
            logMsg("state did not change for mode " .. current_mode .. " and button " .. button_name)
        else
            logMsg("state does not exist for mode " .. current_mode .. " and button " .. button_name)
        end
    end
end

function all_leds_off()
    for i = 1, #default_button_labels do
        logMsg("Set button led " .. default_button_labels[i] .. " to off.")
        set_led_state(default_button_labels[i], false)
    end

    button_state_modified = true
    logMsg("Set all leds to off")
end

function is_boolean(cand)
    return type(cand) == "boolean"
end

function is_string(cand)
    return type(cand) == "string"
end

function is_table(cand)
    return type(cand) == "table"
end

function send_hid_data()
    local data = {}

    for bank = 1, 4 do
        data[bank] = 0
    end

    for i = 1, #default_button_labels do
        local button_name = default_button_labels[i]
        if is_boolean(button_map_leds_state[current_mode][button_name]) then
            if button_map_leds_state[current_mode][button_name] == true then
                data[1] = bit.bor(data[1], bit.lshift(1, i - 1))
            end
        elseif not is_boolean(button_map_leds_state[current_mode][current_selection]) and button_map_leds_state[current_mode][current_selection] ~= nil and button_map_leds_state[current_mode][current_selection][button_name] == true then
            data[1] = bit.bor(data[1], bit.lshift(1, i - 1))
        end
    end

    local bytes_written = hid_send_filled_feature_report(bravo, 0, 65, data[1], data[2], data[3], data[4]) -- 65 = 1 byte (report ID) + 64 bytes (data)
    if bytes_written == -1 then
        logMsg('ERROR Feature report write failed, an error occurred')
    elseif bytes_written < 65 then
        logMsg('ERROR Feature report write failed, only ' .. bytes_written .. ' bytes written')
    else
        button_state_modified = false
    end
end

local bus_voltage = dataref_table('sim/cockpit2/electrical/bus_volts')
local master_state = false

function get_ap_state(array)
    if array[0] == 0 then
        return false
    else
        return true
    end
end

function handle_led_changes()
    if bus_voltage[0] > 0 then
        master_state = true

        for i = 1, #default_button_labels do
            local button_label = default_button_labels[i]
            -- logMsg("Button name: " .. button_label)
            if is_string(button_map_leds[current_mode][button_label]) then
                local dataref = dataref_table(button_map_leds[current_mode][button_label])
                if get_ap_state(dataref) ~= button_map_leds_state[current_mode][button_label] then
                    set_led_state(button_label, get_ap_state(dataref))
                end
            elseif is_table(button_map_leds[current_mode][current_selection]) and button_map_leds[current_mode][current_selection][button_label] then
                local dataref = dataref_table(button_map_leds[current_mode][current_selection][button_label])
                if get_ap_state(dataref) ~= button_map_leds_state[current_mode][current_selection][button_label] then
                    set_led_state(button_label, get_ap_state(dataref))
                end
            end
        end
    elseif master_state == true then
        -- No bus voltage, disable all LEDs
        master_state = false
        all_leds_off()
    end

    -- If we have any LED changes, send them to the device
    if button_state_modified == true then
        send_hid_data()
    end
end

do_every_frame('handle_led_changes()')

-- Helper function to find index in table (used for cycling modes)
function table.find(t, value)
    for i, v in ipairs(t) do
        if v == value then return i end
    end
    return nil -- Not found.
end
