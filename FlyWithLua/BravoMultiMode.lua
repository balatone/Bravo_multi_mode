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
    "PFD_ALT_OUTER_UP","PFD_ALT_OUTER_DOWN","PFD_ALT_INNER_UP","PFD_ALT_INNER_DOWN",
    "MFD_ALT_OUTER_UP","MFD_ALT_OUTER_DOWN","MFD_ALT_INNER_UP","MFD_ALT_INNER_DOWN",
    "AUTO_ALT_UP","AUTO_ALT_DOWN",
    "PFD_VS_OUTER_UP","PFD_VS_OUTER_DOWN","PFD_VS_INNER_UP","PFD_VS_INNER_DOWN",
    "MFD_VS_OUTER_UP","MFD_VS_OUTER_DOWN","MFD_VS_INNER_UP","MFD_VS_INNER_DOWN",
    "AUTO_VS_UP","AUTO_VS_DOWN",
    "PFD_HDG_OUTER_UP","PFD_HDG_INNER_UP",
    "PFD_HDG_OUTER_DOWN","PFD_HDG_INNER_DOWN",
    "AUTO_HDG_UP","AUTO_HDG_DOWN",
    "PFD_CRS_UP","PFD_CRS_DOWN",
    "MFD_CRS_UP","MFD_CRS_DOWN",
    "AUTO_CRS_UP","AUTO_CRS_DOWN",
    "PFD_IAS_OUTER_UP","PFD_IAS_INNER_UP","PFD_IAS_OUTER_DOWN","PFD_IAS_INNER_DOWN",
    "MFD_IAS_OUTER_UP","MFD_IAS_INNER_UP","MFD_IAS_OUTER_DOWN","MFD_IAS_INNER_DOWN",
    "AUTO_IAS_DOWN","AUTO_IAS_DOWN",
    "PFD_PLT_BUTTON","MFD_PLT_BUTTON","AUTO_PLT_BUTTON",
    "PFD_ALT_IAS_BUTTON","MFD_ALT_IAS_BUTTON","PFD_VS_IAS_BUTTON","MFD_VS_IAS_BUTTON","PFD_HDG_IAS_BUTTON","MFD_HDG_IAS_BUTTON","PFD_IAS_IAS_BUTTON","MFD_IAS_IAS_BUTTON","AUTO_IAS_BUTTON",
    "PFD_ALT_VS_BUTTON","MFD_ALT_VS_BUTTON","PFD_VS_VS_BUTTON","MFD_VS_VS_BUTTON","PFD_IAS_VS_BUTTON","MFD_IAS_VS_BUTTON","AUTO_VS_BUTTON",
    "PFD_ALT_ALT_BUTTON","MFD_ALT_ALT_BUTTON","PFD_VS_ALT_BUTTON","MFD_VS_ALT_BUTTON","PFD_IAS_ALT_BUTTON","MFD_IAS_ALT_BUTTON","AUTO_ALT_BUTTON",
    "PFD_IAS_REV_BUTTON","MFD_IAS_REV_BUTTON","AUTO_REV_BUTTON",
    "PFD_IAS_APR_BUTTON","MFD_IAS_APR_BUTTON","AUTO_APR_BUTTON",
    "PFD_IAS_NAV_BUTTON","MFD_IAS_NAV_BUTTON","AUTO_NAV_BUTTON",
    "PFD_IAS_HDG_BUTTON","MFD_IAS_HDG_BUTTON","AUTO_HDG_BUTTON"
    }

for _, key in ipairs(required_keys) do
    if not nav_bindings[key] then
        logMsg("FlyWithLua Error: Missing key in bravo_multi-mode.cfg - " .. key)
        return
    end
end

-- Mode management
local current_mode = "AUTO"
local modes = {"AUTO", "PFD", "MFD"} -- Add more modes as needed
local current_cf_mode = "outer"
local outer_inner_modes = {"outer", "inner"}

-- Bindings for the selector knob
local current_selection = "ALT"
local default_selections = {"ALT","VS","HDG","CRS","IAS"}
local current_selection_label = "ALT"
local selections1 = default_selections
local selections2 = {"COM","NAV","BARO/CRS","RNG","FMS"}
local selections3 = {"COM","NAV","BARO/CRS","RNG","FMS"}

-- The button labels that will be displayed on the console
local default_button_labels = {"HDG","NAV","APR","REV","ALT","VS","IAS","PLT"}
local current_buttons = default_button_labels
local com_button_labels = {"   ","   ","   ","   ","1&2","<->","O/I","   "}
local nav_button_labels = {"   ","   ","   ","   ","1&2","<->","O/I","   "}
local baro_crs_button_labels = {"   ","   ","   ","   ","   ","   ","O/I","   "}
local rng_button_labels = {"   ","   ","   ","   ","   ","   ","   ","   "}
local fms_button_labels = {"MNU","FPL","PRC","CLR","ENT","PSH","O/I","   "}

local button_map_labels = {
    AUTO = {ALT = default_button_labels, VS = default_button_labels, HDG = default_button_labels, CRS = default_button_labels, IAS = default_button_labels},
        PFD = {COM = com_button_labels, NAV = nav_button_labels, ["BARO/CRS"] = baro_crs_button_labels, RNG = rng_button_labels, FMS = fms_button_labels},
        MFD = {COM = com_button_labels, NAV = nav_button_labels, ["BARO/CRS"] = baro_crs_button_labels, RNG = rng_button_labels, FMS = fms_button_labels}
}

-- The button actions that will be used depending on mode and selection
local cf_mode_toggle = "FlyWithLua/custom/cf_mode_button"
local default_button_actions = {HDG = nav_bindings.AUTO_HDG_BUTTON, NAV = nav_bindings.AUTO_NAV_BUTTON, APR = nav_bindings.AUTO_APR_BUTTON, REV = nav_bindings.AUTO_REV_BUTTON, 
                                ALT = nav_bindings.AUTO_ALT_BUTTON, VS = nav_bindings.AUTO_VS_BUTTON, IAS = nav_bindings.AUTO_IAS_BUTTON, PLT = nav_bindings.AUTO_PLT_BUTTON}
local com_PFD_button_actions = {HDG = nil, NAV = nil, APR = nil, REV = nil, ALT = nav_bindings.PFD_ALT_ALT_BUTTON, VS = nav_bindings.PFD_ALT_VS_BUTTON, IAS = nav_bindings.PFD_ALT_IAS_BUTTON, PLT = nil}
local baro_crs_PFD_button_actions = {HDG = nil, NAV = nil, APR = nil, REV = nil, ALT = nil, VS = nil, IAS = nav_bindings.PFD_HDG_IAS_BUTTON, PLT = nil}
local rng_PFD_button_actions = {HDG = nil, NAV = nil, APR = nil, REV = nil, ALT = nil, VS = nil, IAS = nil, PLT = nil}
local fms_PFD_button_actions = {HDG = nav_bindings.PFD_IAS_HDG_BUTTON, NAV = nav_bindings.PFD_IAS_NAV_BUTTON, APR = nav_bindings.PFD_IAS_APR_BUTTON, REV = nav_bindings.PFD_IAS_REV_BUTTON, 
                                ALT = nav_bindings.PFD_IAS_ALT_BUTTON, VS = nav_bindings.PFD_IAS_VS_BUTTON, IAS = nav_bindings.PFD_IAS_IAS_BUTTON, PLT = nav_bindings.PFD_PLT_BUTTON}

local com_MFD_button_actions = {HDG = nil, NAV = nil, APR = nil, REV = nil, ALT = nav_bindings.MFD_ALT_ALT_BUTTON, VS = nav_bindings.MFD_ALT_VS_BUTTON, IAS = nav_bindings.MFD_ALT_IAS_BUTTON, PLT = nil}
local baro_crs_MFD_button_actions = {HDG = nil, NAV = nil, APR = nil, REV = nil, ALT = nil, VS = nil, IAS = nav_bindings.MFD_HDG_IAS_BUTTON, PLT = nil}
local rng_MFD_button_actions = {HDG = nil, NAV = nil, APR = nil, REV = nil, ALT = nil, VS = nil, IAS = nil, PLT = nil}
local fms_MFD_button_actions = {HDG = nav_bindings.MFD_IAS_HDG_BUTTON, NAV = nav_bindings.MFD_IAS_NAV_BUTTON, APR = nav_bindings.MFD_IAS_APR_BUTTON, REV = nav_bindings.MFD_IAS_REV_BUTTON, 
                                ALT = nav_bindings.MFD_IAS_ALT_BUTTON, VS = nav_bindings.MFD_IAS_VS_BUTTON, IAS = nav_bindings.MFD_IAS_IAS_BUTTON, PLT = nav_bindings.MFD_PLT_BUTTON}

local button_map_actions = {
    AUTO = {ALT = default_button_actions, VS = default_button_actions, HDG = default_button_actions, CRS = default_button_actions, IAS = default_button_actions},
        PFD = {COM = com_PFD_button_actions, NAV = com_PFD_button_actions, ["BARO/CRS"] = baro_crs_PFD_button_actions, RNG = rng_PFD_button_actions, FMS = fms_PFD_button_actions},
        MFD = {COM = com_MFD_button_actions, NAV = com_MFD_button_actions, ["BARO/CRS"] = baro_crs_MFD_button_actions, RNG = rng_MFD_button_actions, FMS = fms_MFD_button_actions},
}


logMsg("Initializing the button action map...")
local button_map_actions = {}
for i = 1, #modes  do
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

logMsg("Button action: " .. button_map_actions["AUTO"]["ALT"])
logMsg("Button action: " .. button_map_actions["PFD"]["ALT"]["ALT"])
logMsg("Button action: " .. button_map_actions["AUTO"]["PLT"])
logMsg("Button action: " .. button_map_actions["PFD"]["ALT"]["IAS"])

if not button_map_actions["PFD"]["IAS"] then 
    logMsg("PFD -> IAS is nil")
end

logMsg("Initializing the twist knob action map...")
-- The actions that will br triggered when twisting the right knob depedning on mode and selection
local up_down = {"UP","DOWN"}
local outer_inner = {"OUTER","INNER"}
local twist_knob_map_actions = {}
for i = 1, #modes  do
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
my_floating_wnd = float_wnd_create(380, 120, 1, false)
float_wnd_set_title(my_floating_wnd, "Bravo multi-mode")
-- float_wnd_set_position(my_floating_wnd, SCREEN_WIDTH * 2/3 + 50, SCREEN_HEIGHT * 1/6)
float_wnd_set_position(my_floating_wnd, SCREEN_WIDTH *0.25, SCREEN_HEIGHT*0.25)
float_wnd_set_ondraw(my_floating_wnd, "on_draw_floating_window")
-- float_wnd_set_onclick(my_floating_wnd, "on_click_floating_window")
float_wnd_set_onclose(my_floating_wnd, "on_close_floating_window")

function on_draw_floating_window(my_floating_wnd, x3, y3)
    local offset_mode = -20
	local v_spacing = -30
	local h_spacing = 50
	local offset_selection = 10
	local v_offset = y3 + 120
		
	for i = 1, #modes  do	
		if current_mode == modes[i] then
			glColor3f(0, 1, 0) -- Green for default
			offset_selection = offset_mode
		else
			glColor3f(0.2, 0.2, 0.2) -- Black semitransparent
		end	   
		draw_string_Helvetica_18(x3, v_offset + offset_mode, modes[i])
        offset_mode = offset_mode + v_spacing	
	end
	
    glColor3f(1, 1, 1) -- Black semitransparent
    draw_string_Helvetica_18(x3 + 80, v_offset + offset_selection, current_selection_label)

    local offset_mode = -20

	for i = 1, #outer_inner_modes  do	
		if current_cf_mode == outer_inner_modes[i] then
			glColor3f(0, 1, 0) -- Green for default
			offset_selection = offset_mode
		else
			glColor3f(0.2, 0.2, 0.2) -- Balck semitransparent
		end	   
		draw_string_Helvetica_18(x3 + 290, v_offset + offset_mode, outer_inner_modes[i])
        offset_mode = offset_mode + v_spacing	
	end
	
    offset_mode = offset_mode + v_spacing	
	local h_offset = 0
	for i = 1, #current_buttons do
		glColor3f(1, 1, 0) -- Yellow
		draw_string_Helvetica_18(x3 + h_offset, v_offset + offset_mode, current_buttons[i])
		h_offset = h_offset + h_spacing 
	end
end

function on_close_floating_window(demo_floating_wnd)
	if bravo then
		hid_close(bravo)
	end
end

-- Determine the position of the selector knob
local bravo = hid_open(0x294B, 0x1901)  -- Honeycomb Bravo VID/PID
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
	local num, data1, data2, data3, data4, data5, data6, data7, data8, data9, data10, data11, data12, data13, data14, data15, data16, data17, data18= hid_read(bravo, 64)
	selector = data15
    if selector and selector > 0 then
		idx = 6 - find_position(selector)
        set_current_selector(idx)
    end
end

-- Define button numbers for each selector position
local alt_selector_button = nav_bindings.ALT_SELECTOR and nav_bindings.ALT_SELECTOR + 0 or 0
logMsg("ALT_SELECTOR was set to " .. alt_selector_button)
local selector_buttons = {}-- Replace with actual button numbers
if alt_selector_button and alt_selector_button > 0 then
    for i = 1, 6, 1 do
        selector_buttons[i] = alt_selector_button - i + 1
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

function find_assigned_buttons()
    local active_buttons = {}
    for btn = 1, 1024 do
        if button(btn) then
            table.insert(active_buttons, btn)
        end
    end
    return active_buttons
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
    if current_mode == "AUTO" then
		current_selection_label	= selections1[index]
        current_selection = default_selections[index]
	elseif current_mode == "PFD" then
		current_selection_label	= selections2[index]
        current_selection = default_selections[index]
    elseif current_mode == "MFD" then
		current_selection_label	= selections3[index]
        current_selection = default_selections[index]
	end
end

function set_current_buttons()
	if button_map_labels[current_mode][current_selection_label] then
		current_buttons = button_map_labels[current_mode][current_selection_label]
	end
end

-- Update the currently available buttons
do_every_draw("set_current_buttons()")

local last_click_time = 0
local debounce_delay = 0.05 -- 50ms

function handle_bravo_knob_increase()
    local current_time = os.clock()
    local current_twist_knob_action = twist_knob_map_actions[current_mode][selections1[index]]
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
    local current_twist_knob_action = twist_knob_map_actions[current_mode][selections1[index]]
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

function handle_bravo_button(button_name)
    logMsg("[" .. current_mode .. "][" .. current_selection .. "][" .. button_name .. "]")
    if button_map_actions[current_mode][current_selection][button_name] then
        local command = button_map_actions[current_mode][current_selection][button_name]
        logMsg("Command: " .. command)
        command_once(command)
    elseif  button_map_actions[current_mode][button_name] then
        local command = button_map_actions[current_mode][button_name]
        logMsg("Command: " .. command)
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

-- Helper function to find index in table (used for cycling modes)
function table.find(t, value)
    for i, v in ipairs(t) do
        if v == value then return i end
    end
    return nil -- Not found.
end
