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
"com1_PFD_outer_freq_up","com1_PFD_outer_freq_down","com1_PFD_inner_freq_up","com1_PFD_inner_freq_down",
"com1_MFD_outer_freq_up","com1_MFD_outer_freq_down","com1_MFD_inner_freq_up","com1_MFD_inner_freq_down",
"original_altitude_up","original_altitude_down",
"nav1_PFD_outer_freq_up","nav1_PFD_outer_freq_down","nav1_PFD_inner_freq_up","nav1_PFD_inner_freq_down",
"nav1_MFD_outer_freq_up","nav1_MFD_outer_freq_down","nav1_MFD_inner_freq_up","nav1_MFD_inner_freq_down",
"original_nose_up","original_nose_down",
"baro_outer_up","crs_inner_up",
"baro_outer_down","crs_inner_down",
"original_hdg_up","original_hdg_down",
"range1_up","range1_down",
"range2_up","range2_down",
"original_crs_up","original_crs_down",
"fms1_outer_up","fms1_inner_up","fms1_outer_down","fms1_inner_down",
"fms2_outer_up","fms2_inner_up","fms2_outer_down","fms2_inner_down",
"original_ias_up","original_ias_down",
"PFD_autopilot_button","MFD_autopilot_button","original_autopilot_button",
"original_ias_button",
"com_PFD_ias_button","com_MFD_ias_button","nav_PFD_ias_button","nav_MFD_ias_button","baro_crs_PFD_ias_button","baro_crs_MFD_ias_button","fms_PFD_ias_button","fms_MFD_ias_button","original_ias_button",
"com_PFD_vs_button","com_MFD_vs_button","nav_PFD_vs_button","nav_MFD_vs_button","fms_PFD_vs_button","fms_MFD_vs_button","original_vs_button",
"com_PFD_alt_button","com_MFD_alt_button","nav_PFD_alt_button","nav_MFD_alt_button","fms_PFD_alt_button","fms_MFD_alt_button","original_alt_button",
"fms_PFD_rev_button","fms_MFD_rev_button","original_rev_button",
"fms_PFD_apr_button","fms_MFD_apr_button","original_apr_button",
"fms_PFD_nav_button","fms_MFD_nav_button","original_nav_button",
"fms_PFD_hdg_button","fms_MFD_hdg_button","original_hdg_button"
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

local default_button_labels = {"HDG","NAV","APR","REV","ALT","VS","IAS"}
local current_buttons = default_button_labels

-- Bindings for the selector knob
local current_selection = "ALT"
local selections1 = {"ALT","VS","HDG","CRS","IAS"}
local selections2 = {"COM","NAV","BARO/CRS","RNG","FMS"}
local selections3 = {"COM","NAV","BARO/CRS","RNG","FMS"}

-- The button labels that will be displayed on the console
local com_button_labels = {"   ","   ","   ","   ","1&2","<->","O/I"}
local nav_button_labels = {"   ","   ","   ","   ","1&2","<->","O/I"}
local baro_crs_button_labels = {"   ","   ","   ","   ","   ","   ","O/I"}
local rng_button_labels = {"   ","   ","   ","   ","   ","   ","   "}
local fms_button_labels = {"MNU","FPL","PRC","CLR","ENT","PSH","O/I"}

local button_map_labels = {
	AUTO = {ALT = default_button_labels, VS = default_button_labels, HDG = default_button_labels, CRS = default_button_labels, IAS = default_button_labels},
     PFD = {COM = com_button_labels, NAV = nav_button_labels, ["BARO/CRS"] = baro_crs_button_labels, RNG = rng_button_labels, FMS = fms_button_labels},
     MFD = {COM = com_button_labels, NAV = nav_button_labels, ["BARO/CRS"] = baro_crs_button_labels, RNG = rng_button_labels, FMS = fms_button_labels}
}

-- The button actions that will be used depending on mode and selection
local cf_mode_toggle = "FlyWithLua/custom/cf_mode_button"
local default_button_actions = {HDG = nav_bindings.original_hdg_button, NAV = nav_bindings.original_nav_button, APR = nav_bindings.original_apr_button, REV = nav_bindings.original_rev_button, 
								ALT = nav_bindings.original_alt_button, VS = nav_bindings.original_vs_button, IAS = nav_bindings.original_ias_button, PLT = nav_bindings.original_autopilot_button}
local com_PFD_button_actions = {HDG = nil, NAV = nil, APR = nil, REV = nil, ALT = nav_bindings.com_PFD_alt_button, VS = nav_bindings.com_PFD_vs_button, IAS = nav_bindings.com_PFD_ias_button, PLT = nil}
local baro_crs_PFD_button_actions = {HDG = nil, NAV = nil, APR = nil, REV = nil, ALT = nil, VS = nil, IAS = nav_bindings.baro_crs_PFD_ias_button, PLT = nil}
local rng_PFD_button_actions = {HDG = nil, NAV = nil, APR = nil, REV = nil, ALT = nil, VS = nil, IAS = nil, PLT = nil}
local fms_PFD_button_actions = {HDG = nav_bindings.fms_PFD_hdg_button, NAV = nav_bindings.fms_PFD_nav_button, APR = nav_bindings.fms_PFD_apr_button, REV = nav_bindings.fms_PFD_rev_button, 
								ALT = nav_bindings.fms_PFD_alt_button, VS = nav_bindings.fms_PFD_vs_button, IAS = nav_bindings.fms_PFD_ias_button, PLT = nav_bindings.PFD_autopilot_button}

local com_MFD_button_actions = {HDG = nil, NAV = nil, APR = nil, REV = nil, ALT = nav_bindings.com_MFD_alt_button, VS = nav_bindings.com1_MFD_vs_button, IAS = nav_bindings.com_MFD_ias_button, PLT = nil}
local baro_crs_MFD_button_actions = {HDG = nil, NAV = nil, APR = nil, REV = nil, ALT = nil, VS = nil, IAS = nav_bindings.baro_crs_MFD_ias_button, PLT = nil}
local rng_MFD_button_actions = {HDG = nil, NAV = nil, APR = nil, REV = nil, ALT = nil, VS = nil, IAS = nil, PLT = nil}
local fms_MFD_button_actions = {HDG = nav_bindings.fms_MFD_hdg_button, NAV = nav_bindings.fms_MFD_nav_button, APR = nav_bindings.fms_MFD_apr_button, REV = nav_bindings.fms_MFD_rev_button, 
								ALT = nav_bindings.fms_MFD_alt_button, VS = nav_bindings.fms_MFD_vs_button, IAS = nav_bindings.fms_MFD_ias_button, PLT = nav_bindings.MFD_autopilot_button}

local button_map_actions = {
	AUTO = {ALT = default_button_actions, VS = default_button_actions, HDG = default_button_actions, CRS = default_button_actions, IAS = default_button_actions},
     PFD = {COM = com_PFD_button_actions, NAV = com_PFD_button_actions, ["BARO/CRS"] = baro_crs_PFD_button_actions, RNG = rng_PFD_button_actions, FMS = fms_PFD_button_actions},
     MFD = {COM = com_MFD_button_actions, NAV = com_MFD_button_actions, ["BARO/CRS"] = baro_crs_MFD_button_actions, RNG = rng_MFD_button_actions, FMS = fms_MFD_button_actions},
}

-- The actions that will br triggred when twisting the right knob depedning on mode and selection


-- imgui only works inside a floating window, so we need to create one first:
my_floating_wnd = float_wnd_create(330, 120, 1, false)
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
    draw_string_Helvetica_18(x3 + 80, v_offset + offset_selection, current_selection)

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

function refresh_selector()
    local pos = 0
	local num, data1, data2, data3, data4, data5, data6, data7, data8, data9, data10, data11, data12, data13, data14, data15, data16, data17, data18= hid_read(bravo, 64)
	selector = data15
    if selector and selector > 0 then
		idx = 6 - find_position(selector)
        set_current_selector(idx)
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

function set_current_selector(index)
	if current_mode == "AUTO" then
		current_selection	= selections1[index]
	elseif current_mode == "PFD" then
		current_selection	= selections2[index]
	else
		current_selection	= selections3[index]
	end
end

function set_current_buttons()
	if button_map_labels[current_mode][current_selection] then
		current_buttons = button_map_labels[current_mode][current_selection]
	end
end

-- COM1 PFD
local com1_PFD_outer_freq_up = nav_bindings.com1_PFD_outer_freq_up
local com1_PFD_outer_freq_down = nav_bindings.com1_PFD_outer_freq_down
local com1_PFD_inner_freq_up = nav_bindings.com1_PFD_inner_freq_up
local com1_PFD_inner_freq_down = nav_bindings.com1_PFD_inner_freq_down

-- COM1 MFD
local com1_MFD_outer_freq_up = nav_bindings.com1_MFD_outer_freq_up
local com1_MFD_outer_freq_down = nav_bindings.com1_MFD_outer_freq_down
local com1_MFD_inner_freq_up = nav_bindings.com1_MFD_inner_freq_up
local com1_MFD_inner_freq_down = nav_bindings.com1_MFD_inner_freq_down

-- Store original commands
local original_altitude_up = nav_bindings.original_altitude_up
local original_altitude_down = nav_bindings.original_altitude_down


-- Function to handle button press based on mode
function handle_bravo_knob_increase_alt()
    if current_mode == "AUTO" then
        command_once(original_altitude_up) 
    elseif current_mode == "PFD" then
	    if current_cf_mode == "outer" then
			command_once(com1_PFD_outer_freq_up) 
		else
			command_once(com1_PFD_inner_freq_up) 
		end
    elseif current_mode == "MFD" then
	    if current_cf_mode == "outer" then
			command_once(com1_MFD_outer_freq_up) 
		else
			command_once(com1_MFD_inner_freq_up) 
		end
	end
end

-- Create a custom command for bravo knob increase
create_command(
    "FlyWithLua/custom/knob_increase_handler_alt",
    "Handle button on bravo that increments based on mode and selection ALT",
    "handle_bravo_knob_increase_alt()", -- Call Lua function when pressed
    "",
    ""
)
-- Function to handle button press based on mode
function handle_bravo_knob_decrease_alt()
    if current_mode == "AUTO" then
        command_once(original_altitude_down) 
    elseif current_mode == "PFD" then
	    if current_cf_mode == "outer" then
			command_once(com1_PFD_outer_freq_down) 
		else
			command_once(com1_PFD_inner_freq_down) 
		end		
    elseif current_mode == "MFD" then
	    if current_cf_mode == "outer" then
			command_once(com1_MFD_outer_freq_down) 
		else
			command_once(com1_MFD_inner_freq_down) 
		end		
    end
end

-- Create a custom command for bravo knob decrease
create_command(
    "FlyWithLua/custom/knob_decrease_handler_alt",
    "Handle button on bravo that decrements based on mode and selection ALT",
    "handle_bravo_knob_decrease_alt()", -- Call Lua function when pressed
    "",
    ""
)

-- NAV1 PFD
local nav1_PFD_outer_freq_up = nav_bindings.nav1_PFD_outer_freq_up
local nav1_PFD_outer_freq_down = nav_bindings.nav1_PFD_outer_freq_down
local nav1_PFD_inner_freq_up = nav_bindings.nav1_PFD_inner_freq_up
local nav1_PFD_inner_freq_down = nav_bindings.nav1_PFD_inner_freq_down

-- NAV1 MFD
local nav1_MFD_outer_freq_up = nav_bindings.nav1_MFD_outer_freq_up
local nav1_MFD_outer_freq_down = nav_bindings.nav1_MFD_outer_freq_down
local nav1_MFD_inner_freq_up = nav_bindings.nav1_MFD_inner_freq_up
local nav1_MFD_inner_freq_down = nav_bindings.nav1_MFD_inner_freq_down

-- Store original commands
local original_nose_up = nav_bindings.original_nose_up
local original_nose_down = nav_bindings.original_nose_down


-- Function to handle button press based on mode
function handle_bravo_knob_increase_vs()
    if current_mode == "AUTO" then
        command_once(original_nose_up) 
    elseif current_mode == "PFD" then
	    if current_cf_mode == "outer" then
			command_once(nav1_PFD_outer_freq_up) 
		else
			command_once(nav1_PFD_inner_freq_up) 
		end
    elseif current_mode == "MFD" then
	    if current_cf_mode == "outer" then
			command_once(nav1_MFD_outer_freq_up) 
		else
			command_once(nav1_MFD_inner_freq_up) 
		end
	end
end

-- Create a custom command for bravo knob increase
create_command(
    "FlyWithLua/custom/knob_increase_handler_vs",
    "Handle button on bravo that increments based on mode and selction vs",
    "handle_bravo_knob_increase_vs()", -- Call Lua function when pressed
    "",
    ""
)
-- Function to handle button press based on mode
function handle_bravo_knob_decrease_vs()
    if current_mode == "AUTO" then
        command_once(original_nose_down) 
    elseif current_mode == "PFD" then
	    if current_cf_mode == "outer" then
			command_once(nav1_PFD_outer_freq_down) 
		else
			command_once(nav1_PFD_inner_freq_down) 
		end		
    elseif current_mode == "MFD" then
	    if current_cf_mode == "outer" then
			command_once(nav1_MFD_outer_freq_down) 
		else
			command_once(nav1_MFD_inner_freq_down) 
		end		
    end
end

-- Create a custom command for bravo knob decrease
create_command(
    "FlyWithLua/custom/knob_decrease_handler_vs",
    "Handle button on bravo that decrements based on mode and selection vs",
    "handle_bravo_knob_decrease_vs()", -- Call Lua function when pressed
    "",
    ""
)

-- BARO and HSI
local baro_outer_up = nav_bindings.baro_outer_up
local crs_inner_up = nav_bindings.crs_inner_up
local baro_outer_down = nav_bindings.baro_outer_down
local crs_inner_down = nav_bindings.crs_inner_down

-- Store original commands
local original_hdg_up = nav_bindings.original_hdg_up
local original_hdg_down = nav_bindings.original_hdg_down


-- Function to handle button press based on mode
function handle_bravo_knob_increase_hdg()
    if current_mode == "AUTO" then
        command_once(original_hdg_up) 
    elseif current_mode == "PFD" then
	    if current_cf_mode == "outer" then
			command_once(baro_outer_up) 
		else
			command_once(crs_inner_up) 
		end
    elseif current_mode == "MFD" then
	    if current_cf_mode == "outer" then
			command_once(baro_outer_up) 
		else
			command_once(crs_inner_up) 
		end
	end
end

-- Create a custom command for bravo knob increase
create_command(
    "FlyWithLua/custom/knob_increase_handler_hdg",
    "Handle button on bravo that increments based on mode and selection hdg",
    "handle_bravo_knob_increase_hdg()", -- Call Lua function when pressed
    "",
    ""
)
-- Function to handle button press based on mode
function handle_bravo_knob_decrease_hdg()
    if current_mode == "AUTO" then
        command_once(original_hdg_down) 
    elseif current_mode == "PFD" then
	    if current_cf_mode == "outer" then
			command_once(baro_outer_down) 
		else
			command_once(crs_inner_down) 
		end
    elseif current_mode == "MFD" then
	    if current_cf_mode == "outer" then
			command_once(baro_outer_down) 
		else
			command_once(crs_inner_down) 
		end
    end
end

-- Create a custom command for bravo knob increase
create_command(
    "FlyWithLua/custom/knob_decrease_handler_hdg",
    "Handle button on bravo that decrements based on mode and selection hdg",
    "handle_bravo_knob_decrease_hdg()", -- Call Lua function when pressed
    "",
    ""
)

-- Range
local range1_up = nav_bindings.range1_up
local range1_down = nav_bindings.range1_down
local range2_up = nav_bindings.range2_up
local range2_down = nav_bindings.range2_down

-- Store original commands
local original_crs_up = nav_bindings.original_crs_up
local original_crs_down = nav_bindings.original_crs_down


-- Function to handle button press based on mode
function handle_bravo_knob_increase_crs()
    if current_mode == "AUTO" then
        command_once(original_crs_up) 
    elseif current_mode == "PFD" then
		command_once(range1_up) 
    elseif current_mode == "MFD" then
		command_once(range2_up) 
	end
end

-- Create a custom command for bravo knob increase
create_command(
    "FlyWithLua/custom/knob_increase_handler_crs",
    "Handle button on bravo that increments based on mode and selection crs",
    "handle_bravo_knob_increase_crs()", -- Call Lua function when pressed
    "",
    ""
)
-- Function to handle button press based on mode
function handle_bravo_knob_decrease_crs()
    if current_mode == "AUTO" then
        command_once(original_crs_down) 
    elseif current_mode == "PFD" then
		command_once(range1_down) 
    elseif current_mode == "MFD" then
		command_once(range2_down) 
    end
end

-- Create a custom command for bravo knob decrease
create_command(
    "FlyWithLua/custom/knob_decrease_handler_crs",
    "Handle button on bravo that decrements based on mode and selection crs",
    "handle_bravo_knob_decrease_crs()", -- Call Lua function when pressed
    "",
    ""
)

-- FMS
local fms1_outer_up = nav_bindings.fms1_outer_up
local fms1_inner_up = nav_bindings.fms1_inner_up
local fms1_outer_down = nav_bindings.fms1_outer_down
local fms1_inner_down = nav_bindings.fms1_inner_down

local fms2_outer_up = nav_bindings.fms2_outer_up
local fms2_inner_up = nav_bindings.fms2_inner_up
local fms2_outer_down = nav_bindings.fms2_outer_down
local fms2_inner_down = nav_bindings.fms2_inner_down

-- Store original commands
local original_ias_up = nav_bindings.original_ias_up
local original_ias_down = nav_bindings.original_ias_down


-- Function to handle button press based on mode
function handle_bravo_knob_increase_ias()
    if current_mode == "AUTO" then
        command_once(original_ias_up) 
    elseif current_mode == "PFD" then
	    if current_cf_mode == "outer" then
			command_once(fms1_outer_up) 
		else
			command_once(fms1_inner_up) 
		end
    elseif current_mode == "MFD" then
	    if current_cf_mode == "outer" then
			command_once(fms2_outer_up) 
		else
			command_once(fms2_inner_up) 
		end
	end
end

-- Create a custom command for bravo knob increase
create_command(
    "FlyWithLua/custom/knob_increase_handler_ias",
    "Handle button on bravo that increments based on mode and selection ias",
    "handle_bravo_knob_increase_ias()", -- Call Lua function when pressed
    "",
    ""
)

-- Function to handle button press based on mode
function handle_bravo_knob_decrease_ias()
    if current_mode == "AUTO" then
        command_once(original_ias_down) 
    elseif current_mode == "PFD" then
	    if current_cf_mode == "outer" then
			command_once(fms1_outer_down) 
		else
			command_once(fms1_inner_down) 
		end
    elseif current_mode == "MFD" then
	    if current_cf_mode == "outer" then
			command_once(fms2_outer_down) 
		else
			command_once(fms2_inner_down) 
		end
    end
end

-- Create a custom command for bravo knob increase
create_command(
    "FlyWithLua/custom/knob_decrease_handler_ias",
    "Handle button on bravo that decrements based on mode and selection ias",
    "handle_bravo_knob_decrease_ias()", -- Call Lua function when pressed
    "",
    ""
)

-- Autopilot button
function handle_bravo_ias_button()
	local command = button_map_actions[current_mode][current_selection]["PLT"]
	if  command then
		command_once(command)
	end
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
	local command = button_map_actions[current_mode][current_selection]["IAS"]
	if  command then
		command_once(command)
	end
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
	local command = button_map_actions[current_mode][current_selection]["VS"]
	if  command then
		command_once(command)
	end
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
	local command = button_map_actions[current_mode][current_selection]["ALT"]
	if  command then
		command_once(command)
	end
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
	local command = button_map_actions[current_mode][current_selection]["REV"]
	if  command then
		command_once(command)
	end
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
	local command = button_map_actions[current_mode][current_selection]["APR"]
	if  command then
		command_once(command)
	end
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
	local command = button_map_actions[current_mode][current_selection]["NAV"]
	if  command then
		command_once(command)
	end
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
	local cmd = button_map_actions[current_mode][current_selection]["HDG"]
	if cmd then
		command_once(cmd)
	end
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

-- Register the drawing function
do_every_draw("set_current_buttons()")
if bravo then
	do_every_draw("refresh_selector()")
else
	do_every_draw("refresh_selector_mock()")
end
