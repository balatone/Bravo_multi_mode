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

local last_button_mode_state = false
local last_button_mode_change_time = 0
local last_button_cf_mode_state = false
local last_button_cf_mode_change_time = 0
local DEBOUNCE_DELAY = 0.2 -- 300 milliseconds debounce

-- Bindings for the selector knob
local current_selection = "ALT"
local selections1 = {"ALT","VS","HDG","CRS","IAS"}
local selections2 = {"COM1","NAV1","BARO/CRS","RNG","FMS"}
local selections3 = {"COM2","NAV2","BARO/CRS","RNG","FMS"}
local SELECTOR1 = 660
local SELECTOR2 = SELECTOR1 - 1
local SELECTOR3 = SELECTOR1 - 2
local SELECTOR4 = SELECTOR1 - 3
local SELECTOR5 = SELECTOR1 - 4

-- Bindings for the decrement/increment knob
local KNOB_INCREASE = 652
local KNOB_DECREASE = 653

local outer_inner_TOGGLE = 815

-- Mode toggling
local MODE_TOGGLE = 802

-- Screen position for the overlay
local OVERLAY_X = 50  -- X position (pixels from left)
local OVERLAY_Y = SCREEN_HEIGHT - 500  -- Y position (pixels from top)

-- Create the custom window
local window_id

local message = ""


lastClickX3 = 640 / 2
lastClickY3 = 480 / 2

local line_y_inc = 50

-- imgui only works inside a floating window, so we need to create one first:
my_floating_wnd = float_wnd_create(260, 80, 1, false)
float_wnd_set_title(my_floating_wnd, "Bravo++")
float_wnd_set_position(my_floating_wnd, SCREEN_WIDTH / 2 - 640 / 2, SCREEN_HIGHT / 2 - 480 / 2)
float_wnd_set_ondraw(my_floating_wnd, "on_draw_floating_window")
-- float_wnd_set_onclick(my_floating_wnd, "on_click_floating_window")
float_wnd_set_onclose(my_floating_wnd, "on_close_floating_window")

function on_draw_floating_window(my_floating_wnd, x3, y3)
    local offset_mode = -20
	local v_spacing = -30
	local offset_selection = 10
	local v_offset = y3 + 80
	
	for i = 1, #modes  do	
		if current_mode == modes[i] then
			glColor3f(0, 1, 0) -- Green for default
			offset_selection = offset_mode
		else
			glColor3f(0.2, 0.2, 0.2) -- Balck semitransparent
		end	   
		draw_string_Helvetica_18(x3, v_offset + offset_mode, modes[i])
        offset_mode = offset_mode + v_spacing	
	end
	
    glColor3f(1, 1, 1) -- Balck semitransparent
    draw_string_Helvetica_18(x3 + 80, v_offset + offset_selection, message)

    local offset_mode = -20

	for i = 1, #outer_inner_modes  do	
		if current_cf_mode == outer_inner_modes[i] then
			glColor3f(0, 1, 0) -- Green for default
			offset_selection = offset_mode
		else
			glColor3f(0.2, 0.2, 0.2) -- Balck semitransparent
		end	   
		draw_string_Helvetica_18(x3 + 180, v_offset + offset_mode, outer_inner_modes[i])
        offset_mode = offset_mode + v_spacing	
	end	
end

function on_close_floating_window(demo_floating_wnd)
end
-- Function to draw the overlay on screen
function draw_mode_overlay()
    -- Draw background box
    glColor4f(0.1, 0.1, 0.1, 1) -- Semi-transparent black background
    glRectf(OVERLAY_X - 10, OVERLAY_Y - 90, OVERLAY_X + 250, OVERLAY_Y)

    local offset_mode = -20
	local v_spacing = -30
	local offset_selection = 10
	
	for i = 1, #modes  do	
		if current_mode == modes[i] then
			glColor4f(0, 1, 0, 1) -- Green for default
			offset_selection = offset_mode
		else
			glColor4f(0.2, 0.2, 0.2, 0.5) -- Balck semitransparent
		end	   
		draw_string_Helvetica_18(OVERLAY_X, OVERLAY_Y + offset_mode, modes[i])
        offset_mode = offset_mode + v_spacing	
	end
	
    glColor4f(1, 1, 1, 1) -- Balck semitransparent
    draw_string_Helvetica_18(OVERLAY_X + 80, OVERLAY_Y + offset_selection, message)

    local offset_mode = -20

	for i = 1, #outer_inner_modes  do	
		if current_cf_mode == outer_inner_modes[i] then
			glColor4f(0, 1, 0, 1) -- Green for default
			offset_selection = offset_mode
		else
			glColor4f(0.2, 0.2, 0.2, 0.5) -- Balck semitransparent
		end	   
		draw_string_Helvetica_18(OVERLAY_X + 180, OVERLAY_Y + offset_mode, outer_inner_modes[i])
        offset_mode = offset_mode + v_spacing	
	end	
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

-- Function to handle mode switching
function handle_mode_switch()
    local current_time = os.clock()
	local button_mode_state = button(MODE_TOGGLE)
	local button_cf_mode_state = button(outer_inner_TOGGLE)

    if button_mode_state ~= last_button_mode_state then
        if current_time - last_button_mode_change_time > DEBOUNCE_DELAY then
            if not button_mode_state then -- Button released
                cycle_mode()
            end
            last_button_mode_change_time = current_time
        end
        last_button_mode_state = button_mode_state
    elseif button_cf_mode_state ~= last_button_cf_mode_state then
        if current_time - last_button_cf_mode_change_time > DEBOUNCE_DELAY then
            if not button_cf_mode_state then -- Button released
                cycle_cf_mode()
            end
            last_button_cf_mode_change_time = current_time
        end
        last_button_cf_mode_state = button_cf_mode_state
    end
end

-- Function that applies the correct action depending on mode 
function refresh_selector()
	if button(SELECTOR1) then
        -- Action for Position 1
		set_current_selector(1)
        set_button_assignment(KNOB_INCREASE, "FlyWithLua/custom/knob_increase_handler_alt")
		set_button_assignment(KNOB_DECREASE, "FlyWithLua/custom/knob_decrease_handler_alt")
    elseif button(SELECTOR2) then
        -- Action for Position 2
		set_current_selector(2)
        set_button_assignment(KNOB_INCREASE, "FlyWithLua/custom/knob_increase_handler_vs")
		set_button_assignment(KNOB_DECREASE, "FlyWithLua/custom/knob_decrease_handler_vs")
    elseif button(SELECTOR3) then
        -- Action for Position 3
		set_current_selector(3)
        set_button_assignment(KNOB_INCREASE, "FlyWithLua/custom/knob_increase_handler_hdg")
		set_button_assignment(KNOB_DECREASE, "FlyWithLua/custom/knob_decrease_handler_hdg")
    elseif button(SELECTOR4) then
        -- Action for Position 4
		set_current_selector(4)
        set_button_assignment(KNOB_INCREASE, "FlyWithLua/custom/knob_increase_handler_crs")
		set_button_assignment(KNOB_DECREASE, "FlyWithLua/custom/knob_decrease_handler_crs")
    elseif button(SELECTOR5) then
        -- Action for Position 5
		set_current_selector(5)
        set_button_assignment(KNOB_INCREASE, "FlyWithLua/custom/knob_increase_handler_ias")
		set_button_assignment(KNOB_DECREASE, "FlyWithLua/custom/knob_decrease_handler_ias")
    end
end

function set_current_selector(index)
	if current_mode == "AUTO" then
		message	= selections1[index]
	elseif current_mode == "PFD" then
		message	= selections2[index]
	else
		message	= selections3[index]
	end
end

-- COM1
local com1_outer_freq_up = "sim/GPS/g1000n1_com_outer_up"
local com1_outer_freq_down = "sim/GPS/g1000n1_com_outer_down"
local com1_inner_freq_up = "sim/GPS/g1000n1_com_inner_up"
local com1_inner_freq_down = "sim/GPS/g1000n1_com_inner_down"

-- COM2
local com2_outer_freq_up = "sim/GPS/g1000n2_com_outer_up"
local com2_outer_freq_down = "sim/GPS/g1000n2_com_outer_down"
local com2_inner_freq_up = "sim/GPS/g1000n2_com_inner_up"
local com2_inner_freq_down = "sim/GPS/g1000n2_com_inner_down"

-- Store original commands
local original_altitude_up = "sim/autopilot/altitude_up"
local original_altitude_down = "sim/autopilot/altitude_down"


-- Function to handle button press based on mode
function handle_bravo_knob_increase_alt()
    if current_mode == "AUTO" then
        command_once(original_altitude_up) 
    elseif current_mode == "PFD" then
	    if current_cf_mode == "outer" then
			command_once(com1_outer_freq_up) 
		else
			command_once(com1_inner_freq_up) 
		end
    elseif current_mode == "MFD" then
	    if current_cf_mode == "outer" then
			command_once(com2_outer_freq_up) 
		else
			command_once(com2_inner_freq_up) 
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
			command_once(com1_outer_freq_down) 
		else
			command_once(com1_inner_freq_down) 
		end		
    elseif current_mode == "MFD" then
	    if current_cf_mode == "outer" then
			command_once(com2_outer_freq_down) 
		else
			command_once(com2_inner_freq_down) 
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

-- NAV1
local nav1_outer_freq_up = "sim/GPS/g1000n1_nav_outer_up"
local nav1_outer_freq_down = "sim/GPS/g1000n1_nav_outer_down"
local nav1_inner_freq_up = "sim/GPS/g1000n1_nav_inner_up"
local nav1_inner_freq_down = "sim/GPS/g1000n1_nav_inner_down"

-- NAV2
local nav2_outer_freq_up = "sim/GPS/g1000n2_nav_outer_up"
local nav2_outer_freq_down = "sim/GPS/g1000n2_nav_outer_down"
local nav2_inner_freq_up = "sim/GPS/g1000n2_nav_inner_up"
local nav2_inner_freq_down = "sim/GPS/g1000n2_nav_inner_down"

-- Store original commands
local original_nose_up = "sim/autopilot/nose_up"
local original_nose_down = "sim/autopilot/nose_down"


-- Function to handle button press based on mode
function handle_bravo_knob_increase_vs()
    if current_mode == "AUTO" then
        command_once(original_nose_up) 
    elseif current_mode == "PFD" then
	    if current_cf_mode == "outer" then
			command_once(nav1_outer_freq_up) 
		else
			command_once(nav1_inner_freq_up) 
		end
    elseif current_mode == "MFD" then
	    if current_cf_mode == "outer" then
			command_once(nav2_outer_freq_up) 
		else
			command_once(nav2_inner_freq_up) 
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
			command_once(nav1_outer_freq_down) 
		else
			command_once(nav1_inner_freq_down) 
		end		
    elseif current_mode == "MFD" then
	    if current_cf_mode == "outer" then
			command_once(nav2_outer_freq_down) 
		else
			command_once(nav2_inner_freq_down) 
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

-- BARO and HSI
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

-- Helper function to find index in table (used for cycling modes)
function table.find(t, value)
    for i, v in ipairs(t) do
        if v == value then return i end
    end
    return nil -- Not found.
end

-- Register the drawing function
-- do_every_draw("draw_mode_overlay()")
do_every_draw("handle_mode_switch()")
do_every_draw("refresh_selector()")

