-- Example FlyWithLua script for Honeycomb Bravo Selector Knob

if not SUPPORTS_FLOATING_WINDOWS then
    -- to make sure the script doesn't stop old FlyWithLua versions
    logMsg("floating windows not supported by your FlyWithLua version")
    return
end

require("graphics")

-- Mode management
local current_mode = "AUTO"
local modes = {"AUTO", "PFD", "MFD"} -- Add more modes as needed
local current_cf_mode = "outer"
local outer_inner_modes = {"outer", "inner"}

local current_buttons = {"HDG","NAV","APR","REV","ALT","VS","IAS"}

local last_button_mode_state = false
local last_button_mode_change_time = 0
local last_button_cf_mode_state = false
local last_button_cf_mode_change_time = 0
local DEBOUNCE_DELAY = 0.0 -- 300 milliseconds debounce

-- Bindings for the selector knob
local current_selection = "ALT"
local selections1 = {"ALT","VS","HDG","CRS","IAS"}
local selections2 = {"COM","NAV","BARO/CRS","RNG","FMS"}
local selections3 = {"COM","NAV","BARO/CRS","RNG","FMS"}
local SELECTOR1 = 660
local SELECTOR2 = SELECTOR1 - 1
local SELECTOR3 = SELECTOR1 - 2
local SELECTOR4 = SELECTOR1 - 3
local SELECTOR5 = SELECTOR1 - 4

-- Screen position for the overlay
local OVERLAY_X = 50  -- X position (pixels from left)
local OVERLAY_Y = SCREEN_HEIGHT - 500  -- Y position (pixels from top)

-- imgui only works inside a floating window, so we need to create one first:
my_floating_wnd = float_wnd_create(330, 120, 1, false)
float_wnd_set_title(my_floating_wnd, "Bravo multi-mode")
float_wnd_set_position(my_floating_wnd, SCREEN_WIDTH * 2/3 + 50, SCREEN_HIGHT * 1/6)
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
		glColor3f(1, 1, 0) -- Green for default
		draw_string_Helvetica_18(x3 + h_offset, v_offset + offset_mode, current_buttons[i])
		h_offset = h_offset + h_spacing 
	end
end

function on_close_floating_window(demo_floating_wnd)
end

-- Function to cycle through modes
function cycle_mode()
	local index = table.find(modes, current_mode)
	index = (index % #modes) + 1
	current_mode = modes[index]
end

-- Function to cycle through outer/inner modes
function cycle_cf_mode()
	local index = table.find(outer_inner_modes, current_cf_mode)
	index = (index % #outer_inner_modes) + 1
	current_cf_mode = outer_inner_modes[index]
end

-- Function that applies the correct action depending on mode 
function refresh_selector()
	if button(SELECTOR1) then
        -- Action for Position 1
		set_current_selector(1)
    elseif button(SELECTOR2) then
        -- Action for Position 2
		set_current_selector(2)
    elseif button(SELECTOR3) then
        -- Action for Position 3
		set_current_selector(3)
    elseif button(SELECTOR4) then
        -- Action for Position 4
		set_current_selector(4)
    elseif button(SELECTOR5) then
        -- Action for Position 5
		set_current_selector(5)
    end
end

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
	if current_mode == "AUTO" then
		current_buttons = {"HDG","NAV","APR","REV","ALT","VS","IAS"}
	elseif current_mode == "PFD" or current_mode == "MFD" then
		if current_selection == "COM" or current_selection == "NAV" then
			current_buttons = {"   ","   ","   ","   ","1&2","<->","O/I"}
		elseif current_selection == "BARO/CRS" then
			current_buttons = {"   ","   ","   ","   ","   ","   ","O/I"}
		elseif current_selection == "RNG" then
			current_buttons = {"   ","   ","   ","   ","   ","   ","   "}
		elseif current_selection == "FMS" then
			current_buttons = {"MNU","FPL","PRC","CLR","ENT","PSH","O/I"}
		end
	end
end

-- COM1 PFD
local com1_PFD_outer_freq_up = "sim/GPS/g1000n1_com_outer_up"
local com1_PFD_outer_freq_down = "sim/GPS/g1000n1_com_outer_down"
local com1_PFD_inner_freq_up = "sim/GPS/g1000n1_com_inner_up"
local com1_PFD_inner_freq_down = "sim/GPS/g1000n1_com_inner_down"

-- COM1 MFD
local com1_MFD_outer_freq_up = "sim/GPS/g1000n3_com_outer_up"
local com1_MFD_outer_freq_down = "sim/GPS/g1000n3_com_outer_down"
local com1_MFD_inner_freq_up = "sim/GPS/g1000n3_com_inner_up"
local com1_MFD_inner_freq_down = "sim/GPS/g1000n3_com_inner_down"

-- Store original commands
local original_altitude_up = "sim/autopilot/altitude_up"
local original_altitude_down = "sim/autopilot/altitude_down"


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
local nav1_PFD_outer_freq_up = "sim/GPS/g1000n1_nav_outer_up"
local nav1_PFD_outer_freq_down = "sim/GPS/g1000n1_nav_outer_down"
local nav1_PFD_inner_freq_up = "sim/GPS/g1000n1_nav_inner_up"
local nav1_PFD_inner_freq_down = "sim/GPS/g1000n1_nav_inner_down"

-- NAV1 MFD
local nav1_MFD_outer_freq_up = "sim/GPS/g1000n3_nav_outer_up"
local nav1_MFD_outer_freq_down = "sim/GPS/g1000n3_nav_outer_down"
local nav1_MFD_inner_freq_up = "sim/GPS/g1000n3_nav_inner_up"
local nav1_MFD_inner_freq_down = "sim/GPS/g1000n3_nav_inner_down"

-- Store original commands
local original_nose_up = "sim/autopilot/nose_up"
local original_nose_down = "sim/autopilot/nose_down"


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
local baro_outer_up = "sim/instruments/barometer_up"
local crs_inner_up = "sim/radios/obs_HSI_up"
local baro_outer_down = "sim/instruments/barometer_down"
local crs_inner_down = "sim/radios/obs_HSI_down"

-- Store original commands
local original_hdg_up = "sim/GPS/g1000n1_hdg_up"
local original_hdg_down = "sim/GPS/g1000n1_hdg_down"


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
local range1_up = "sim/GPS/g1000n1_range_up"
local range1_down = "sim/GPS/g1000n1_range_down"
local range2_up = "sim/GPS/g1000n3_range_up"
local range2_down = "sim/GPS/g1000n3_range_down"

-- Store original commands
local original_crs_up = "sim/radios/obs_HSI_up"
local original_crs_down = "sim/radios/obs_HSI_down"


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
local fms1_outer_up = "sim/GPS/g1000n1_fms_outer_up"
local fms1_inner_up = "sim/GPS/g1000n1_fms_inner_up"
local fms1_outer_down = "sim/GPS/g1000n1_fms_outer_down"
local fms1_inner_down = "sim/GPS/g1000n1_fms_inner_down"

local fms2_outer_up = "sim/GPS/g1000n3_fms_outer_up"
local fms2_inner_up = "sim/GPS/g1000n3_fms_inner_up"
local fms2_outer_down = "sim/GPS/g1000n3_fms_outer_down"
local fms2_inner_down = "sim/GPS/g1000n3_fms_inner_down"

-- Store original commands
local original_ias_up = "sim/autopilot/airspeed_up"
local original_ias_down = "sim/autopilot/airspeed_down"


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
local PFD_autopilot_button = "sim/GPS/g1000n1_direct"
local MFD_autopilot_button = "sim/GPS/g1000n3_direct"

-- Store original commands
local original_autopilot_button = "sim/autopilot/servos_toggle"

-- Function to handle button press based on mode
function handle_bravo_autopilot_button()
    if current_mode == "AUTO" then
        command_once(original_autopilot_button) 
    elseif current_mode == "PFD" then
        command_once(PFD_autopilot_button) 		
    elseif current_mode == "MFD" then
        command_once(MFD_autopilot_button) 				
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

-- Store original commands
local original_ias_button = "sim/autopilot/speed_hold"


-- Function to handle button press based on mode
function handle_bravo_ias_button()
    if current_mode == "AUTO" then
        command_once(original_ias_button) 
    elseif current_mode == "PFD" then
		if current_selection == "COM" then
			cycle_cf_mode()
		elseif current_selection == "NAV" then
			cycle_cf_mode()
		elseif current_selection == "BARO/CRS" then
			cycle_cf_mode()
		elseif current_selection == "FMS" then
			cycle_cf_mode()
		end
    elseif current_mode == "MFD" then
		if current_selection == "COM" then
			cycle_cf_mode()
		elseif current_selection == "NAV" then
			cycle_cf_mode()
		elseif current_selection == "BARO/CRS" then
			cycle_cf_mode()
		elseif current_selection == "FMS" then
			cycle_cf_mode()
		end			
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
local com1_PFD_vs_button = "sim/GPS/g1000n1_com_ff"
local com1_MFD_vs_button = "sim/GPS/g1000n3_com_ff"
local nav1_PFD_vs_button = "sim/GPS/g1000n1_nav_ff"
local nav1_MFD_vs_button = "sim/GPS/g1000n3_nav_ff"
local fms_PFD_vs_button = "sim/GPS/g1000n1_cursor"
local fms_MFD_vs_button = "sim/GPS/g1000n3_cursor"


-- Store original commands
local original_vs_button = "sim/autopilot/vertical_speed"

-- Function to handle button press based on mode
function handle_bravo_vs_button()
    if current_mode == "AUTO" then
        command_once(original_vs_button) 
    elseif current_mode == "PFD" then
		if current_selection == "COM" then
			command_once(com1_PFD_vs_button)
		elseif current_selection == "NAV" then
			command_once(nav1_PFD_vs_button)
		elseif current_selection == "FMS" then
			command_once(fms_PFD_vs_button) 
		end
    elseif current_mode == "MFD" then
		if current_selection == "COM" then
			command_once(com1_MFD_vs_button)
		elseif current_selection == "NAV" then
			command_once(nav1_MFD_vs_button)
		elseif current_selection == "FMS" then
			command_once(fms_MFD_vs_button)
		end			
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
local com_PFD_alt_button = "sim/GPS/g1000n1_com12"
local com_MFD_alt_button = "sim/GPS/g1000n3_com12"
local nav_PFD_alt_button = "sim/GPS/g1000n1_nav12"
local nav_MFD_alt_button = "sim/GPS/g1000n3_nav12"

local fms_PFD_alt_button = "sim/GPS/g1000n1_ent"
local fms_MFD_alt_button = "sim/GPS/g1000n3_ent"

-- Store original commands
local original_alt_button = "sim/autopilot/altitude_hold"


-- Function to handle button press based on mode
function handle_bravo_alt_button()
    if current_mode == "AUTO" then
        command_once(original_alt_button) 
    elseif current_mode == "PFD" then
		if current_selection == "COM" then
			command_once(com_PFD_alt_button) 		
		elseif current_selection == "NAV" then
			command_once(nav_PFD_alt_button) 
		elseif current_selection == "FMS" then
			command_once(fms_PFD_alt_button) 
		end
    elseif current_mode == "MFD" then
		if current_selection == "COM" then
			command_once(com_MFD_alt_button) 		
		elseif current_selection == "NAV" then
			command_once(nav_MFD_alt_button) 
		elseif current_selection == "FMS" then
			command_once(fms_MFD_alt_button)
		end			
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
local fms_PFD_rev_button = "sim/GPS/g1000n1_clr"
local fms_MFD_rev_button = "sim/GPS/g1000n3_clr"

-- Store original commands
local original_rev_button = "sim/autopilot/back_course"

-- Function to handle button press based on mode
function handle_bravo_rev_button()
    if current_mode == "AUTO" then
        command_once(original_rev_button) 
    elseif current_mode == "PFD" then
		if current_selection == "FMS" then
			command_once(fms_PFD_rev_button) 
		end
    elseif current_mode == "MFD" then
		if current_selection == "FMS" then
			command_once(fms_MFD_rev_button)
		end			
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
local fms_PFD_apr_button = "sim/GPS/g1000n1_proc"
local fms_MFD_apr_button = "sim/GPS/g1000n3_proc"

-- Store original commands
local original_apr_button = "sim/autopilot/approach"

-- Function to handle button press based on mode
function handle_bravo_apr_button()
    if current_mode == "AUTO" then
        command_once(original_apr_button) 
    elseif current_mode == "PFD" then
		if current_selection == "FMS" then
			command_once(fms_PFD_apr_button) 
		end
    elseif current_mode == "MFD" then
		if current_selection == "FMS" then
			command_once(fms_MFD_apr_button)
		end			
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
local fms_PFD_nav_button = "sim/GPS/g1000n1_fpl"
local fms_MFD_nav_button = "sim/GPS/g1000n3_fpl"

-- Store original commands
-- local original_nav_button = "sim/GPS/g1000n3_nav"
local original_nav_button = "sim/autopilot/NAV"
-- Function to handle button press based on mode
function handle_bravo_nav_button()
    if current_mode == "AUTO" then
        command_once(original_nav_button)
    elseif current_mode == "PFD" then
		if current_selection == "FMS" then
			command_once(fms_PFD_nav_button) 
		end
    elseif current_mode == "MFD" then
		if current_selection == "FMS" then
			command_once(fms_MFD_nav_button)
		end			
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
local fms_PFD_hdg_button = "sim/GPS/g1000n1_menu"
local fms_MFD_hdg_button = "sim/GPS/g1000n3_menu"

-- Store original commands
local original_hdg_button = "sim/GPS/g1000n3_hdg"

-- Function to handle button press based on mode
function handle_bravo_hdg_button()
    if current_mode == "AUTO" then
        command_once(original_hdg_button)
    elseif current_mode == "PFD" then
		if current_selection == "FMS" then
			command_once(fms_PFD_hdg_button) 
		end
    elseif current_mode == "MFD" then
		if current_selection == "FMS" then
			command_once(fms_MFD_hdg_button)
		end			
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

-- Create a custom command for changing mode
create_command(
    "FlyWithLua/custom/mode_button",
    "Bravo++ toggles mode button",
    "cycle_mode()", -- Call Lua function when pressed
    "",
    ""
)

-- Create a custom command for changing cf mode
create_command(
    "FlyWithLua/custom/cf_mode_button",
    "Bravo++ toggles cf mode button",
    "cycle_cf_mode()", -- Call Lua function when pressed
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
-- do_every_draw("draw_mode_overlay()")
do_every_draw("set_current_buttons()")
do_every_draw("refresh_selector()")

