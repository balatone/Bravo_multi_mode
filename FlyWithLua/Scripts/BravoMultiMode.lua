require("bit")
require("graphics")
local log = require("log")

-- Change the logging level to log.LOG_DEBUG if troubleshooting
log.LOG_LEVEL = log.LOG_INFO
local log_led_state = false

-- Set this to either 0 or the button number assigned for the alt selector in x-plane.
-- Setting to 0 will result in using HID to determine the selector state, but will introduce lag in Windows. 
-- Use the ButtonLogUtil.lua to determine the button number asigned by x-plane
local alt_selector_button = 0

local bravo = hid_open(0x294B, 0x1901) -- Honeycomb Bravo VID/PID

if bravo then
    hid_set_nonblocking(bravo, 1)
else
    log.error("No Honeycomb Bravo device detected! Make sure that it's plugged in properly to the PC.")
    return
end

if not SUPPORTS_FLOATING_WINDOWS then
    -- to make sure the script doesn't stop old FlyWithLua versions
    log.error("Floating windows not supported by your FlyWithLua version")
    return
end

local function trim(s)
    return (s:gsub("^%s*(.-)%s*$", "%1"))
end

function is_dataref_magic_table(candidate_table)
    -- First, check if it's a Lua table at all
    if type(candidate_table) ~= "table" then
        return false
    end
    if type(candidate_table.reftype) == "number" then
        return true
    end
    -- If 'reftype' is nil or not a number, it's not a magic DataRef table.
    return false
end

-- Must determine if it's an array using reftype
function is_dataref_array(dr_table)
    for k,v in pairs(dr_table) do
        if tostring(k) == "reftype" and (tostring(v) == "8" or tostring(v) == "16") then
            return true
        end
    end
    return false
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

local function read_config_file(nav_cfg_path, nav_bindings)
    local cfg_file = io.open(nav_cfg_path, "r")
    if cfg_file then
        for line in cfg_file:lines() do
            -- Skip comments/empty lines and parse key=value
            if not line:match("^%s*#") and line:match("=") then
                local key, value = line:match("^%s*([%w_]+)%s*=%s*(.-)%s*$")
                if key and value then
                    value = trim(value)
                    -- Remove surrounding quotes only if both present
                    value = value:match('^"(.-)"$') or value
                    nav_bindings[key] = value
                end
            end
        end
        cfg_file:close()
        return true
    else
        return false
    end
end

-- Get aircraft directory from X-Plane's AIRCRAFT_PATH and AIRCRAFT_FILENAME if there are more than one .acf file
local aircraft_dir = string.match(AIRCRAFT_PATH, "(.*[/\\])")
local aircraft_name = string.sub(AIRCRAFT_FILENAME, 1, string.len(AIRCRAFT_FILENAME) - 4)

-- Table to hold dataref assignments
local nav_bindings = {}
local nav_cfg_file_full_path = aircraft_dir .. "bravo_multi-mode.cfg" 
-- Check if config file exists
local file_ok =  read_config_file(nav_cfg_file_full_path, nav_bindings)

if file_ok then 
    log.info("Successfully parsed config file")
else
    local nav_cfg_file_name = "bravo_multi-mode." .. aircraft_name .. ".cfg"
    local nav_cfg_file_full_path = aircraft_dir .. nav_cfg_file_name
    log.info("nav_cfg_file: " .. nav_cfg_file_full_path)
    file_ok = read_config_file(nav_cfg_file_full_path, nav_bindings)
    if file_ok then
        log.info("Successfully parsed config file specific for " .. aircraft_name)        
    else
        log.warning("No config file found in  " .. aircraft_dir .. " with name bravo_multi-mode.cfg or " .. nav_cfg_file_name .. ". Bravo script will be stopped.")
        return -- Stop script if config is missing
    end
end


-- The annunciator labels. These are used for validation and in the led logic.
local annunciator_labels = {
        "MASTER_WARNING", "FIRE_WARNING", "OIL_LOW_PRESSURE", "FUEL_LOW_PRESSURE", "ANTI_ICE", "STARTER_ENGAGED", "APU",
        "MASTER_CAUTION", "VACUUM", "HYD_LOW_PRESSURE", "AUX_FUEL_PUMP", "PARKING_BRAKE", "VOLTS_LOW", "DOOR"}


local function create_table(value_string)
    local value_table = {}
    local idx = 1

    if value_string == nil then
        return value_table
    end

    local gmatch_result = string.gmatch(value_string .. ",", "([^,]*),")
    if gmatch_result then
        for value in gmatch_result do
            value_table[idx] = value
            idx = idx + 1
        end
    else
        log.error("Error: " ..
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
local up_down_modes = {"up", "down"}
local current_switch_mode = up_down_modes[1]

-- Bindings for the selector knob
local default_selections = { "ALT", "VS", "HDG", "CRS", "IAS" }
local current_selection = default_selections[1]

local current_selection_label = default_selections[1]

-- The button labels that will be displayed on the console
local default_button_labels = { "HDG", "NAV", "APR", "REV", "ALT", "VS", "IAS", "PLT" }
local no_button_labels = { "   ", "   ", "   ", "   ", "   ", "   ", "   ", "   " }

-----------------------------------------------------
--- VALIDATION OF THE CONFIG FILE
-----------------------------------------------------
function validate_config_keys()
    local valid_keys_set = {}
    local function add_key(key)
        valid_keys_set[key] = true
    end

    local missing_required_keys = {}   -- New table to track explicitly required keys
    local validation_failed = false    -- Flag to indicate if any validation step fails

    -- **Step 1: Check for the presence and validity of the "MODES" key**
    -- 'modes' is a global variable populated from nav_bindings.MODES.
    -- If nav_bindings["MODES"] is nil or an empty string, 'modes' will be an empty table.
    if not nav_bindings["MODES"] or #modes == 0 then
        table.insert(missing_required_keys, "MODES")
        validation_failed = true
    end
    add_key("MODES") -- Mark 'MODES' as a valid key to prevent it from being flagged as 'invalid' if it exists.

    -- **Step 2: Check for _SELECTOR_LABELS for each declared mode**
    -- This loop will only execute if 'modes' contains actual mode names (i.e., 'MODES' was properly defined).
    if #modes > 0 then
        for _, mode in ipairs(modes) do
            local selector_label_key = mode .. "_SELECTOR_LABELS"
            add_key(selector_label_key) -- Mark this specific selector label key as valid if it appears.
            if mode ~= "AUTO" and not nav_bindings[selector_label_key] then
                table.insert(missing_required_keys, selector_label_key)
                validation_failed = true
            end
        end
    end

    -- Button Labels: MODE_SELECTION_BUTTON_LABELS
    for _, mode in ipairs(modes) do
        for _, selection in ipairs(default_selections) do
            add_key(mode .. "_" .. selection .. "_BUTTON_LABELS")
            add_key(mode .. "_" .. selection .. "_KNOB_LABELS")
        end
    end

    -- Switch labels, actions and leds
    add_key("SWITCH_LABELS")
    for i = 1, 7 do
        add_key("SWITCH" .. i .. "_LED")
        add_key("SWITCH" .. i .. "_UP")
        add_key("SWITCH" .. i .. "_DOWN")
    end

    -- Button Actions and LEDs (including general mode-level and specific mode-selection combinations)
    for _, mode in ipairs(modes) do
        for _, button_label in ipairs(default_button_labels) do
            add_key(mode .. "_" .. button_label .. "_BUTTON")
            add_key(mode .. "_" .. button_label .. "_BUTTON_LED")
            for _, ud_mode in ipairs(up_down_modes) do
                add_key(mode .. "_" .. button_label .. "_" .. string.upper(ud_mode) .. "_BUTTON")
            end
            for _, selection in ipairs(default_selections) do
                add_key(mode .. "_" .. selection .. "_" .. button_label .. "_BUTTON")
                add_key(mode .. "_" .. selection .. "_" .. button_label .. "_BUTTON_LED")
                for _, ud_mode in ipairs(up_down_modes) do
                    add_key(mode .. "_" .. selection .. "_" .. button_label .. "_" .. string.upper(ud_mode) .. "_BUTTON")
                end
            end
        end
    end

    -- Twist Knob Actions
    for _, mode in ipairs(modes) do
        for _, selection in ipairs(default_selections) do
            for _, ud_mode in ipairs(up_down_modes) do
                add_key(mode .. "_" .. selection .. "_" .. string.upper(ud_mode))
            end
            for _, oi_mode in ipairs(outer_inner_modes) do
                for _, ud_mode in ipairs(up_down_modes) do
                    add_key(mode .. "_" .. selection .. "_" .. string.upper(oi_mode) .. "_" .. string.upper(ud_mode))
                end
            end
        end
    end

    -- Global LED Bindings (Annunciator and Gear)
    add_key("GEAR_DEPLOYMENT_LED")
    for _, label in ipairs(annunciator_labels) do
        add_key(label .. "_LED")
        for i = 1, 16 do
            add_key(label .. "_" .. tostring(i) .. "_LED")
        end
    end

    -- Manual Trim Configuration
    add_key("TRIM_INCREMENT")
    add_key("TRIM_BOOST")

    -- **Step 3: Check for invalid (unrecognized) keys**
    -- This part identifies keys in the config file that are not defined as valid.
    local invalid_keys_found = {}
    for key, _ in pairs(nav_bindings) do
        if not valid_keys_set[key] then
            table.insert(invalid_keys_found, key)
            validation_failed = true
        end
    end

    -- **Step 4: Report validation results**
    if validation_failed then
        log.error("--- Configuration Keys Validation Failed ---")
        if #missing_required_keys > 0 then
            log.error("Found " .. #missing_required_keys .. " MISSING REQUIRED configuration keys:")
            for _, key in ipairs(missing_required_keys) do
                log.error(" Missing key: \"" .. key .. "\"")
            end
        end
        if #invalid_keys_found > 0 then
            log.error("Found " .. #invalid_keys_found .. " INVALID (unrecognized) configuration keys in config file:")
            for _, key in ipairs(invalid_keys_found) do
                log.error(" Invalid key: \"" .. key .. "\"")
            end
        end
        log.error("---------------------------------------------")
        return false -- Indicates validation failed
    else
        log.info("All configuration keys in bravo_multi-mode.cfg are valid.")
        return true -- Indicates validation passed
    end
end

-- Helper function to check if a string ends with a specific suffix
local function ends_with(str, suffix)
    return #str >= #suffix and str:sub(-#suffix) == suffix
end

--- Helper function to safely call dataref_table and return its result.
-- Catches any errors thrown by dataref_table that pcall can intercept, and logs if DataRef is not found.
-- Returns the actual result (table or nil) if no error occurred.
local function safe_dataref_lookup(dataref_name_string)
    -- Defensive check: Ensure the input is a string
    if type(dataref_name_string) ~= "string" then
        log.error("safe_dataref_lookup received non-string argument: '" .. tostring(dataref_name_string) .. "'")
        return nil
    end

    local cmd_ref = XPLMFindDataRef(dataref_name_string) --
    if cmd_ref == nil then
        log.warning("Dataref '" .. tostring(dataref_name_string) .. "' not found in X-Plane's command list.")
        return nil
    end
    return dataref_table(dataref_name_string)
end

--- Helper function to safely check if an X-Plane command exists.
-- Returns true if the command is found, false otherwise.
local function safe_command_lookup(command_name_string)
    -- Defensive check: Ensure the input is a string
    if type(command_name_string) ~= "string" then
        log.error("safe_command_lookup received non-string argument: '" .. tostring(command_name_string) .. "'")
        return false
    end

    -- XPLMFindCommand returns a userdata (a reference) if the command exists, or nil if not.
    -- This function doesn't typically throw Lua errors that pcall would catch,
    -- but rather returns nil directly on failure to find.
    local cmd_ref = XPLMFindCommand(command_name_string) --
    if cmd_ref == nil then
        log.warning("Command '" .. tostring(command_name_string) .. "' not found in X-Plane's command list.")
        return false
    end
    -- If cmd_ref is not nil, it's a valid userdata reference to the command.
    return true
end

local two_param_led_keys = {}

two_param_led_keys["GEAR_DEPLOYMENT_LED"] = true

for _, label in ipairs(annunciator_labels) do
	two_param_led_keys[label .. "_LED"] = true
	-- Account for indexed annunciator labels like AUX_FUEL_PUMP_1_LED, DOOR_1_LED
	-- Assuming a max index based on observed data (e.g., DOOR_3_LED)
	for i = 1, 16 do
		two_param_led_keys[label .. "_" .. tostring(i) .. "_LED"] = true
	end
end

--- Validates the values assigned to configuration keys in the nav_bindings table.
function validate_config_values()
    local invalid_value_entries = {}
    log.info("Starting configuration value validation...")

    for key, value_string in pairs(nav_bindings) do
        if ends_with(key, "_SELECTOR_LABELS") then
            local values = create_table(value_string)
            if #values ~= 5 then
                table.insert(invalid_value_entries, {
                    key = key,
                    value = value_string,
                    reason = "Invalid number of values for SELECTOR_LABELS. Expected 5, but found " .. #values .. "."
                })
            end
        elseif ends_with(key, "_BUTTON_LABELS") then
            local values = create_table(value_string)
            if #values ~= 8 then
                table.insert(invalid_value_entries, {
                    key = key,
                    value = value_string,
                    reason = "Invalid number of values for BUTTON_LABELS. Expected 8, but found " .. #values .. "."
                })
            end
        elseif ends_with(key, "_KNOB_LABELS") then
            local values = create_table(value_string)
            if #values < 1 and #values > 2  then
                table.insert(invalid_value_entries, {
                    key = key,
                    value = value_string,
                    reason = "Invalid number of values for BUTTON_LABELS. Expected 1 or 2, but found " .. #values .. "."
                })
            end
        elseif key == "SWITCH_LABELS" then
            local values = create_table(value_string)
            if #values ~= 7 then
                table.insert(invalid_value_entries, {
                    key = key,
                    value = value_string,
                    reason = "Invalid number of values for BUTTON_LABELS. Expected 7, but found " .. #values .. "."
                })
            end
        elseif key == "MODES" then
            local values = create_table(value_string)
            if values[1] ~= "AUTO" then
                table.insert(invalid_value_entries, {
                    key = key,
                    value = value_string,
                    reason = "The first value in MODES must always be AUTO."
                })                
            end
        elseif ends_with(key, "_LED") then
            local binding_parameters = create_table(value_string)
            local current_entry_valid = true

            if #binding_parameters < 2 or #binding_parameters > 3 then
                table.insert(invalid_value_entries, {
                    key = key,
                    value = value_string,
                    reason = "Invalid number of parameters for LED. Expected 2 or 3 (DataRef, Number[, Number]), but found " .. #binding_parameters .. "."
                })
                current_entry_valid = false
            else
                -- Common validation for all _LED keys (DataRef existence and condition parameter type)
                local dr_string = binding_parameters[1]
                local dr_table = safe_dataref_lookup(dr_string)
                local cond_param = tonumber(binding_parameters[2])

                if dr_table == nil then
                    table.insert(invalid_value_entries, {
                        key = key,
                        value = value_string,
                        reason = "First parameter '" .. tostring(binding_parameters[1]) .. "' is not a valid DataRef."
                    })
                    current_entry_valid = false
                end

                if cond_param == nil then
                    table.insert(invalid_value_entries, {
                        key = key,
                        value = value_string,
                        reason = "Second parameter '" .. tostring(binding_parameters[2]) .. "' is not a valid number (expected LED condition)."
                    })
                    current_entry_valid = false
                end

                -- Apply specific parameter count rules based on the key
                if two_param_led_keys[key] then
                    -- For the explicitly listed keys, only 2 parameters are allowed.
                    -- This implicitly means no index is required, even if the DataRef is an array.
                    if #binding_parameters ~= 2 then
                        table.insert(invalid_value_entries, {
                            key = key,
                            value = value_string,
                            reason = "Invalid number of parameters for this LED. Expected exactly 2 (DataRef, Number), but found " .. #binding_parameters .. "."
                        })
                        current_entry_valid = false
                    end
                else
                    -- For all other _LED keys, apply the general 2 or 3 parameter rule with array checks.

                    if #binding_parameters == 3 then
                        local index_param = tonumber(binding_parameters[3])
                        local is_array_dataref = false
                        if dr_table ~= nil then -- Only check array type if DataRef was valid
                            is_array_dataref = is_dataref_array(dr_table)
                        end

                        if not is_array_dataref then
                            table.insert(invalid_value_entries, {
                                key = key,
                                value = value_string,
                                reason = "DataRef is not an array DataRef, but a third parameter (index) was provided. Only 2 parameters are allowed for non-array DataRefs."
                            })
                            current_entry_valid = false
                        elseif index_param == nil then
                            table.insert(invalid_value_entries, {
                                key = key,
                                value = value_string,
                                reason = "Third parameter '" .. tostring(binding_parameters[3]) .. "' is not a valid number (expected DataRef index)."
                            })
                            current_entry_valid = false
                        end
                    elseif #binding_parameters == 2 then
                        local is_array_dataref = false
                        if dr_table ~= nil then -- Only check array type if DataRef was valid
                            is_array_dataref = is_dataref_array(dr_table)
                        end
                        if is_array_dataref then
                            table.insert(invalid_value_entries, {
                                key = key,
                                value = value_string,
                                reason = "DataRef is an array DataRef, but no index was provided. A third parameter (index) is required for array DataRefs."
                            })
                            current_entry_valid = false
                        end
                    end
                end
            end
        elseif key == "TRIM_INCREMENT" or key == "TRIM_BOOST" then
            local trim_value = tonumber(value_string)
            if trim_value == nil then
                table.insert(invalid_value_entries, {
                    key = key,
                    value = value_string,
                    reason = "Trim value '" .. tostring(value_string) .. "' is not a valid number."
                })
            elseif trim_value < 0 then
                table.insert(invalid_value_entries, {
                    key = key,
                    value = value_string,
                    reason = "Trim value '" .. tostring(value_string) .. "' must be greater than 0."
                })
            end
        else -- For other keys, assume the value is a command string
            local command_name = create_table(value_string)
            -- Check if it's a known internal command that will be created by this script
                for i = 1, #command_name do
            if command_name[i] == "FlyWithLua/Bravo++/cf_mode_button" or 
               command_name[i] == "FlyWithLua/Bravo++/switch_mode_button" or
               command_name[i] == "FlyWithLua/Bravo++/toggle_mode_select" then
                -- Log a debug message and skip validation for this internal command
                log.debug("Skipping command validation for internal command: '" .. command_name[i] .. "' (will be created later).")
            elseif not safe_command_lookup(command_name[i]) then -- Check if the command exists using XPLMFindCommand
					table.insert(invalid_value_entries, {
						key = key,
						value = value_string,
						reason = "'" .. tostring(command_name[i]) .. "' is not a valid X-Plane Command or caused an error during lookup."
					})
				end
            end
        end
    end

    if #invalid_value_entries > 0 then
        log.error("--- Configuration Values Validation Failed ---")
        for _, entry in ipairs(invalid_value_entries) do
            log.error("Key: '" .. entry.key .. "', Value: '" .. entry.value .. "', Reason: " .. entry.reason)
        end
        return false
    else
        log.info("All configuration values in bravo_multi-mode.cfg are valid.")
        return true
    end
end

log.info("Validating the config file...")
local keys_valid = validate_config_keys()
local values_valid = validate_config_values()

if not keys_valid or not values_valid then return end

-----------------------------------------------------
--- Initialize the various maps/tables
-----------------------------------------------------
log.info("Initializing the selector labels map...")
local selection_map_labels = {}
for i = 1, #modes do
    if modes[i] ~= "AUTO" then
        local key = modes[i] .. "_SELECTOR_LABELS"
        selection_map_labels[modes[i]] = create_table(nav_bindings[key])
        log.info("Adding " .. key .. " = " .. nav_bindings[key])
    else
        selection_map_labels[modes[i]] = default_selections
        log.info("Adding default selector labels.")
    end
end

log.info("Initializing the button labels map...")
local button_map_labels = {}
for i = 1, #modes do
    local select_map = {}
    for j = 1, #default_selections do
        select_map[default_selections[j]] = {}
        local key = modes[i] .. "_" .. default_selections[j] .. "_BUTTON_LABELS"
        if modes[i] ~= "AUTO" or (modes[i] == "AUTO" and nav_bindings[key] ~= nil) then
            if nav_bindings[key] ~= nil then
                select_map[default_selections[j]] = create_table(nav_bindings[key])
                button_map_labels[modes[i]] = select_map
                log.info("Adding " .. key .. " = " .. nav_bindings[key])
			else
				select_map[default_selections[j]] = no_button_labels
				button_map_labels[modes[i]] = select_map
				log.info("No bindings found for mode and selection. Adding no button labels.")			
            end
        else
			select_map[default_selections[j]] = default_button_labels
			button_map_labels[modes[i]] = select_map
			log.info("Adding default button labels.")
        end
    end
end

-- The labels for the rocker switches
log.info("Initializing the switch labels...")
local switch_map_labels = {}

if nav_bindings["SWITCH_LABELS"] ~= nil then
    switch_map_labels = create_table(nav_bindings["SWITCH_LABELS"])
end

-- The labels used for the right twist knob
log.info("Initializing the right twist knob labels...")
local twist_knob_map_labels = {}
for i = 1, #modes do
    local select_map = {}
    for j = 1, #default_selections do
        select_map[default_selections[j]] = {}
        local key = modes[i] .. "_" .. default_selections[j] .. "_KNOB_LABELS"
        if nav_bindings[key] ~= nil then
            local bindings = create_table(nav_bindings[key])
            if #bindings > 1 then
                select_map[default_selections[j]]["OUTER"] = bindings[1]
                select_map[default_selections[j]]["INNER"] = bindings[2]
            elseif #bindings == 1 then
                select_map[default_selections[j]] = bindings[1]
            end
            twist_knob_map_labels[modes[i]] = select_map
            log.info("Adding " .. key .. " = " .. nav_bindings[key])
        else
            log.info("No bindings found for mode and selection. Adding no knob labels.")			
        end
    end
end

-- The button actions that will be used depending on mode and selection
log.info("Initializing the button action map...")
local button_map_actions = {}
local up_down = { "UP", "DOWN" }
for i = 1, #modes do
    button_map_actions[modes[i]] = {}
    for j = 1, #default_selections do
        button_map_actions[modes[i]][default_selections[j]] = button_map_actions[modes[i]][default_selections[j]] or {}
        for k = 1, #default_button_labels do
            button_map_actions[modes[i]][default_button_labels[k]] = button_map_actions[modes[i]][default_button_labels[k]] or {}
            local full_key = modes[i] .. "_" .. default_button_labels[k] .. "_BUTTON"
            local bindings = nil
            if default_selections[j] == "ALT" and nav_bindings[full_key] then                
                bindings = create_table(nav_bindings[full_key])
                button_map_actions[modes[i]][default_button_labels[k]]["ON_CLICK"] = bindings[1]
                log.info("Adding " .. full_key .. " = " .. bindings[1] .. " for ON_CLICK")
                local on_hold_action = bindings[2] or bindings[1]
                button_map_actions[modes[i]][default_button_labels[k]]["ON_HOLD"] = on_hold_action
                log.info("Adding " .. full_key .. " = " .. on_hold_action .. " for ON_HOLD")
            elseif default_selections[j] == "ALT" and nav_bindings[full_key] == nil then
                -- local switch_map = {}
                for l = 1, #up_down do
                    local full_key = modes[i] .. "_" .. default_button_labels[k] .. "_" .. up_down[l] .. "_BUTTON"
                    bindings = create_table(nav_bindings[full_key])
                    if bindings[1] then
                        button_map_actions[modes[i]][default_button_labels[k]][up_down[l]] = button_map_actions[modes[i]][default_button_labels[k]][up_down[l]] or {}
                        button_map_actions[modes[i]][default_button_labels[k]][up_down[l]]["ON_CLICK"] = bindings[1]
                        log.info("Adding " .. full_key .. " = " .. bindings[1] .. " for ON_CLICK")
                        local on_hold_action = bindings[2] or bindings[1]
                        button_map_actions[modes[i]][default_button_labels[k]][up_down[l]]["ON_HOLD"] = on_hold_action
                        log.info("Adding " .. full_key .. " = " .. on_hold_action .. " for ON_HOLD")
                        local on_long_click_action = "FlyWithLua/Bravo++/switch_mode_button"
						button_map_actions[modes[i]][default_button_labels[k]][up_down[l]]["ON_LONG_CLICK"] = on_long_click_action
                        log.info("Adding " .. full_key .. " = " .. on_long_click_action .. " for ON_LONG_CLICK")
                    end
                end
			end
			local key = modes[i] .. "_" .. default_selections[j]
			full_key = key .. "_" .. default_button_labels[k] .. "_BUTTON"
			bindings = create_table(nav_bindings[full_key])
			button_map_actions[modes[i]][default_selections[j]][default_button_labels[k]] = button_map_actions[modes[i]][default_selections[j]][default_button_labels[k]] or {}
			
			if bindings[1] then
				button_map_actions[modes[i]][default_selections[j]][default_button_labels[k]]["ON_CLICK"] = bindings[1]
				log.info("Adding " .. full_key .. " = " .. bindings[1] .. " for ON_CLICK")
				local on_hold_action = bindings[2] or bindings[1]
				button_map_actions[modes[i]][default_selections[j]][default_button_labels[k]]["ON_HOLD"] = on_hold_action
				log.info("Adding " .. full_key .. " = " .. on_hold_action .. " for ON_HOLD")
			else
				for l = 1, #up_down do
					key = modes[i] .. "_" .. default_selections[j]
					full_key = key .. "_" .. default_button_labels[k] .. "_" .. up_down[l] .. "_BUTTON"
					bindings = create_table(nav_bindings[full_key])
					if bindings[1] then
						button_map_actions[modes[i]][default_selections[j]][default_button_labels[k]][up_down[l]] = button_map_actions[modes[i]][default_selections[j]][default_button_labels[k]][up_down[l]] or {}
						button_map_actions[modes[i]][default_selections[j]][default_button_labels[k]][up_down[l]]["ON_CLICK"] = bindings[1]
						log.info("Adding " .. full_key .. " = " .. bindings[1] .. " for ON_CLICK")
						local on_hold_action = bindings[2] or bindings[1]
						button_map_actions[modes[i]][default_selections[j]][default_button_labels[k]][up_down[l]]["ON_HOLD"] = on_hold_action
						log.info("Adding " .. full_key .. " = " .. on_hold_action .. " for ON_HOLD")
                        local on_long_click_action = "FlyWithLua/Bravo++/switch_mode_button"
						button_map_actions[modes[i]][default_selections[j]][default_button_labels[k]][up_down[l]]["ON_LONG_CLICK"] = on_long_click_action
                        log.info("Adding " .. full_key .. " = " .. on_long_click_action .. " for ON_LONG_CLICK")
					end
				end
			end
        end
    end
end

-- The button led that will be displayed depending on mode and selection
log.info("Initializing the button led map...")
local button_map_leds = {}
local button_map_leds_state = {}
local button_map_leds_cond = {}
local button_map_leds_index = {}

for i = 1, #modes do
    button_map_leds[modes[i]] = {}
    button_map_leds_state[modes[i]] = {}
    button_map_leds_cond[modes[i]] = {}
    button_map_leds_index[modes[i]] = {}
    local select_map = {}
    local select_map2 = {}
    local select_map3 = {}
    local select_map4 = {}
    for j = 1, #default_selections do
        select_map[default_selections[j]] = {}
        select_map2[default_selections[j]] = {}
        select_map3[default_selections[j]] = {}
        select_map4[default_selections[j]] = {}
        for k = 1, #default_button_labels do
            local full_key = modes[i] .. "_" .. default_button_labels[k] .. "_BUTTON_LED"
            if default_selections[j] == "ALT" and nav_bindings[full_key] then
				select_map["ALL"] = select_map["ALL"] or {}
				select_map2["ALL"] = select_map2["ALL"] or {}
				select_map3["ALL"] = select_map3["ALL"] or {}
				select_map4["ALL"] = select_map4["ALL"] or {}
                log.debug("navbinding: " .. nav_bindings[full_key])
                local binding = create_table(nav_bindings[full_key])
                log.debug("datref: " .. binding[1])
                log.debug("cond: " .. binding[2])
                select_map["ALL"][default_button_labels[k]] = dataref_table(binding[1])
                button_map_leds[modes[i]] = select_map
                select_map2["ALL"][default_button_labels[k]] = binding[2]
                button_map_leds_cond[modes[i]] = select_map2
                select_map3["ALL"][default_button_labels[k]] = false
                button_map_leds_state[modes[i]] = select_map3

				if binding[3] ~= nil then
					log.debug("index: " .. binding[3])
					select_map4["ALL"][default_button_labels[k]] = binding[3]
					button_map_leds_index[modes[i]] = select_map4
				end
                log.info("Adding " .. full_key .. " = " .. nav_bindings[full_key])
            else
                local key = modes[i] .. "_" .. default_selections[j]
                full_key = key .. "_" .. default_button_labels[k] .. "_BUTTON_LED"
                if nav_bindings[full_key] then
                    log.debug("navbinding: " .. nav_bindings[full_key])
                    local binding = create_table(nav_bindings[full_key])
                    log.debug("datref: " .. binding[1])
                    log.debug("cond: " .. binding[2])
                    select_map[default_selections[j]][default_button_labels[k]] = dataref_table(binding[1])
                    button_map_leds[modes[i]] = select_map
                    select_map2[default_selections[j]][default_button_labels[k]] = binding[2]
                    button_map_leds_cond[modes[i]] = select_map2
                    select_map3[default_selections[j]][default_button_labels[k]] = false
                    button_map_leds_state[modes[i]] = select_map3
                    if binding[3] ~= nil then
                        log.debug("index: " .. binding[3])
                        select_map4[default_selections[j]][default_button_labels[k]] = binding[3]
                        button_map_leds_index[modes[i]] = select_map4
                    end
                    log.info("Adding " .. full_key .. " = " .. nav_bindings[full_key])
                end
            end
        end
    end
end

-- The actions that will be triggered when twisting the right knob depedning on mode and selection
log.info("Initializing the twist knob action map...")
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
                    log.info("Adding " .. full_key .. " = " .. nav_bindings[full_key])
                end
                if nav_bindings[key .. "_" .. outer_inner[l] .. "_" .. up_down[k]] then
                    local dir = up_down[k]
                    local full_key = key .. "_" .. oi .. "_" .. dir
                    outer_map[oi][dir] = nav_bindings[full_key]
                    select_map[default_selections[j]] = outer_map
                    twist_knob_map_actions[modes[i]] = select_map
                    log.info("Adding " .. full_key .. " = " .. nav_bindings[full_key] .. " to " .. oi)
                end
            end
        end
    end
end

-----------------------------------------------------
--- CREATE THE GUI PANEL
-----------------------------------------------------
local current_buttons = default_button_labels
local vertical_spacing = 40
local height = 150

if #switch_map_labels > 0 then
	height = 40*4 + 20
else
	height = 40*3 + 20
end

my_floating_wnd = float_wnd_create(550, height, 1, true)
float_wnd_set_title(my_floating_wnd, "Bravo++ multi-mode")
float_wnd_set_imgui_builder(my_floating_wnd, "build_bravo_gui")
-- float_wnd_set_positioning_mode(my_floating_wnd, 4, -1)
float_wnd_set_title(my_floating_wnd, "Bravo++ multi-mode")
-- float_wnd_set_position(my_floating_wnd, SCREEN_WIDTH * 2/3 + 50, SCREEN_HEIGHT * 1/6)
float_wnd_set_position(my_floating_wnd, SCREEN_WIDTH * 0.25, SCREEN_HEIGHT * 0.25)


-- float_wnd_set_onclick(my_floating_wnd, "on_click_floating_window")
float_wnd_set_onclose(my_floating_wnd, "on_close_floating_window")

function get_name_before_index(full_mode_string)
    local conceptual_name = full_mode_string:gsub("_%d+$", "")
    return conceptual_name
end

function build_bravo_gui(wnd, x, y)
    local win_width = imgui.GetWindowWidth()
    local win_height = imgui.GetWindowHeight()

    -- Set the ImGui window background style color using AABBGGRR hex format.
    -- imgui.PushStyleColor(imgui.constant.Col.Border, 0xFF262626)
    imgui.PushStyleColor(imgui.constant.Col.WindowBg, 0xCC333333) -- Light Grey

    local vertical_spacing = 0.75*vertical_spacing

    local conceptual_mode_active = {} -- Stores boolean: true if current_mode falls under this conceptual name
    local conceptual_mode_order = {}  -- Stores unique conceptual names in the order they first appear
    local conceptual_name_seen = {}   -- Helper to track if a conceptual name has been added to order

    -- Populate conceptual_mode_active and conceptual_mode_order tables
    for i = 1, #modes do
        local name_conceptual = get_name_before_index(modes[i]) -- Get the base name, e.g., "AUTO" from "AUTO_2"
        if not conceptual_name_seen[name_conceptual] then
            table.insert(conceptual_mode_order, name_conceptual) -- Add unique conceptual name to maintain order
            conceptual_name_seen[name_conceptual] = true
        end
        -- If the current actual mode (e.g., "AUTO_2") matches the mode in the loop (modes[i]),
        -- then mark its conceptual name (e.g., "AUTO") as active for highlighting.
        if current_mode == modes[i] then
            conceptual_mode_active[name_conceptual] = true
        end
    end

    -- Replace the existing mode display loop (which starts around imgui.SetCursorPosX(h_offset_mode))
    -- with the following code:

    -- Parameters for mode label display
    local h_offset_mode = 10 -- Initial horizontal offset for the first mode label
    local h_spacing_mode = 5 -- Horizontal spacing between mode labels
    local y_offset_mode = 10 -- Vertical position for mode labels
    local mode_width = 60 -- Fixed width for each mode label

    imgui.NewLine() -- Start a new line for the mode labels
    imgui.SetWindowFontScale(1.2) -- Set font scale for mode labels

    -- Step 2: Draw the conceptual mode names based on the collected info
    for i, conceptual_name_to_draw in ipairs(conceptual_mode_order) do
        local current_x_position = h_offset_mode + (i - 1) * (mode_width + h_spacing_mode)
        imgui.SetCursorPosX(current_x_position)
        imgui.SetCursorPosY(y_offset_mode)

        local text_color_for_label = 0xFF111111 -- Default color: Dark Grey
        if conceptual_mode_active[conceptual_name_to_draw] then
            text_color_for_label = 0xFF00FF00 -- Highlight color: Green
        end
        draw_label(conceptual_name_to_draw, mode_width, 20, text_color_for_label)
    end
    imgui.SetWindowFontScale(1.0) -- Restore default font scale for subsequent UI elements

    local h_offset_select = h_offset_mode -- Initial horizontal offset for buttons
    local h_spacing_select = 5 -- Horizontal spacing between button columns
    local y_offset_select = 40
    local select_width = mode_width

    -- Current Selection Label
    for i = 1, #selection_map_labels[current_mode] do
        local selection_label = selection_map_labels[current_mode][i]
        -- log.info("Selection label: " .. selection_label)
        local h_offset_select = h_offset_select + (i - 1) * (select_width + h_spacing_select)
        imgui.SetCursorPosX(h_offset_select)
        imgui.SetCursorPosY(y_offset_select)

        local text_color = 0xFF000000
        if current_selection_label == selection_label then
            text_color = 0xFFFFFFFF -- White (AABBGGRR)
        else
            text_color = 0xFF111111 -- Dark Grey (AABBGGRR)
        end
        draw_label(selection_label, select_width, 20, text_color)            
    end

    imgui.SetWindowFontScale(1.0)

    -- Button Labels and States
    local h_offset_button = h_offset_mode -- Initial horizontal offset for buttons
    local h_spacing_button = 5 -- Horizontal spacing between button columns
    local y_offset_button = 90 -- 80
    local button_width = 60    -- Width of button as used in draw_button
    local button_color = 0xFF575049
	local button_off_label_color = 0xFF111111 -- 0xFF5A5A5A
	local button_on_label_color = 0xFFFFFFFF
	local button_no_led_label_color = 0xFF18D1CB -- 0xFF111111

    imgui.NewLine() -- Start a new line after selection label for buttons
    imgui.SetCursorPosX(h_offset_button) 
    imgui.SetCursorPosY(y_offset_button)

    for i = 1, #current_buttons do
        local button_label = current_buttons[i]
        local button_name = default_button_labels[i]
        local led_state = get_button_led_state(button_name)
        local button_label_color =  button_no_led_label_color
        if led_state == true then
            button_label_color = button_on_label_color
        elseif led_state == false then
            button_label_color = button_off_label_color
        end

        local is_switch = false
        if is_table(button_map_actions[current_mode]) then
            if is_table(button_map_actions[current_mode][current_selection]) and
               is_table(button_map_actions[current_mode][current_selection][button_name]) then
                if is_table(button_map_actions[current_mode][current_selection][button_name]["UP"]) or
                   is_table(button_map_actions[current_mode][current_selection][button_name]["DOWN"]) then
                    is_switch = true
                end
            elseif is_table(button_map_actions[current_mode][button_name]) then
                if is_table(button_map_actions[current_mode][button_name]["UP"]) or
                   is_table(button_map_actions[current_mode][button_name]["DOWN"]) then
                    is_switch = true
                end
            end
        end

        local current_button_x = h_offset_button + (i - 1) * (button_width + h_spacing_button)
		
		if i == #current_buttons then
			current_button_x = h_offset_button + (i - 2) * (button_width + h_spacing_button)
			y_offset_button = y_offset_button - 45
		end

        imgui.SetCursorPosX(current_button_x)
        imgui.SetCursorPosY(y_offset_button)            
        draw_button(button_name, button_label, button_width, 30, button_color, button_label_color, is_switch)
    end

    -- Switch Labels and States
    local h_offset_switch = h_offset_mode -- Initial horizontal offset for buttons
    local h_spacing_switch = 5 -- Horizontal spacing between button columns
    local y_offset_switch = 170
    local switch_width = 60    -- Width of button as used in draw_button
    local switch_color = button_color

    imgui.NewLine()
    imgui.SetCursorPosX(h_offset_button) 
    imgui.SetCursorPosY(y_offset_button)

    for i = 1, #switch_map_labels do
        local switch_label = switch_map_labels[i]
        local current_switch_x = h_offset_switch + (i - 1) * (switch_width + h_spacing_switch)
        local led_state = get_led_state_for_switch("SWITCH" .. i .. "_LED")
        local switch_label_color =  button_no_led_label_color
        if led_state == true then
            switch_label_color = button_on_label_color
        elseif led_state == false then
            switch_label_color = button_off_label_color
        end
        imgui.SetCursorPosX(current_switch_x)
        imgui.SetCursorPosY(y_offset_switch - vertical_spacing*1.5)
        draw_button(switch_label, switch_width, 30, switch_color, switch_label_color, false)        
    end

    -- **Call the new draw_knob function**
    local graphic_center_x = 505
    local graphic_center_y = 75
    local outer_radius = 36
    local inner_radius = 25
    local num_segments = 32
    local outline_thickness = 2

    draw_knob(
        graphic_center_x, graphic_center_y,
        outer_radius, inner_radius,
        num_segments, outline_thickness,
        current_mode, current_selection, current_cf_mode,
        twist_knob_map_actions, twist_knob_map_labels
    )
end

function draw_knob(centerX, centerY, outerRad, innerRad, segments, thickness, current_mode, current_selection, current_cf_mode, twist_knob_map_actions, twist_knob_map_labels)
    -- Base colors for the knob components (from original build_bravo_gui)
    local outer_outline_color = 0xFF222222 -- Opaque Gray
    local inner_outline_color = 0xFF222222 -- Opaque Gray
    local outer_color = 0xFF505050        -- Opaque Dark Gray for the interior
    local inner_color = 0xFF505050        -- Opaque Dark Gray for the interior
    local knob_text_color = 0xFFFFFFFF    -- White for the text

    -- Highlight colors (semi-transparent and opaque green, also from original)
    local highlight_color = 0x4400FF00      -- Semi-transparent Green
    local highlight_outline_color = 0xFF00FF00 -- Opaque Green

    -- **Apply highlighting logic based on current_cf_mode and available actions**
    if is_table(twist_knob_map_actions[current_mode]) and is_table(twist_knob_map_actions[current_mode][current_selection]) then
        if is_table(twist_knob_map_actions[current_mode][current_selection]["INNER"]) then
            -- This path is for knobs with explicit inner/outer functionality
            if current_cf_mode == "outer" then
                outer_color = highlight_color
                outer_outline_color = highlight_outline_color
            elseif current_cf_mode == "inner" then
                inner_color = highlight_color
                inner_outline_color = highlight_outline_color
            end
        elseif is_string(twist_knob_map_actions[current_mode][current_selection]["UP"]) then
            -- This path is for simpler knobs that use only "UP" / "DOWN" without "INNER" / "OUTER" distinction
            outer_color = highlight_color
            outer_outline_color = highlight_outline_color
            inner_color = highlight_color
            inner_outline_color = highlight_outline_color
        end
    end

    -- **Draw the circles that form the knob's appearance**
    imgui.DrawList_AddCircle(centerX, centerY, outerRad, outer_outline_color, segments, thickness)
    imgui.DrawList_AddCircleFilled(centerX, centerY, outerRad, outer_color, segments)
    imgui.DrawList_AddCircle(centerX, centerY, innerRad, inner_outline_color, segments, thickness)
    imgui.DrawList_AddCircleFilled(centerX, centerY, innerRad, inner_color, segments)

    -- **Draw the text label on the knob**
    if is_table(twist_knob_map_labels[current_mode]) then
        local text_to_display = nil
        if is_table(twist_knob_map_labels[current_mode][current_selection]) then
            -- Retrieve text for inner/outer knob, dependent on current_cf_mode
            text_to_display = twist_knob_map_labels[current_mode][current_selection][string.upper(current_cf_mode)]
        elseif is_string(twist_knob_map_labels[current_mode][current_selection]) then
            -- Retrieve text for simple knob (single label)
            text_to_display = twist_knob_map_labels[current_mode][current_selection]
        end

        if text_to_display ~= nil then
            -- Determine the available text area within the knob
            -- The knob's inner circle has a radius of 'innerRad'.
            -- So, the maximum square area for text within it would be 2 * innerRad on each side.
            local knob_text_max_width = innerRad * 2
            local knob_text_max_height = innerRad * 2 -- Allow text to span vertically if needed

            -- **Use get_scaled_wrapped_text to get wrapped lines and the optimal font scale**
            local wrapped_lines, text_total_height, final_font_scale =
                get_scaled_wrapped_text(tostring(text_to_display), knob_text_max_width, knob_text_max_height, 0.6) -- 0.6 is the minimum font scale used in draw_button

            -- Apply the determined font scale for drawing the text
            imgui.SetWindowFontScale(final_font_scale)

            -- Calculate the vertical starting position to center the block of text within the knob
            local start_text_y = centerY - text_total_height / 2

            -- Draw each wrapped line of text
            local current_line_y = start_text_y
            for _, line in ipairs(wrapped_lines) do
                -- Recalculate line size at the final_font_scale for accurate centering
                local line_w, line_h = imgui.CalcTextSize(line)
                local line_draw_x = centerX - line_w / 2 -- Center each line horizontally within the knob

                -- Set cursor position for the current line's top-left corner
                imgui.SetCursorPosX(line_draw_x)
                imgui.SetCursorPosY(current_line_y)

                -- Call the global draw_label function to render the text for this line
                draw_label(line, line_w, line_h, knob_text_color)

                current_line_y = current_line_y + line_h -- Move the Y position down for the next line
            end

            -- Restore the original font scale to avoid affecting subsequent UI elements
            imgui.SetWindowFontScale(1.0)
        end
    end
end

function draw_label(text, width, height, text_color_int)
    local cx, cy = imgui.GetCursorScreenPos()

    imgui.Dummy(width, height)

    local text_w, text_h = imgui.CalcTextSize(tostring(text))
    local text_draw_x = cx + (width - text_w) / 2
    local text_draw_y = cy + (height - text_h) / 2

    imgui.SetCursorScreenPos(text_draw_x, text_draw_y)
    imgui.PushStyleColor(imgui.constant.Col.Text, text_color_int)
    imgui.TextUnformatted(tostring(text))
    imgui.PopStyleColor()
end

-- Helper function to wrap text for a given width and font scale
local function wrap_text_for_width(text_str, max_width, current_font_scale)
    local lines = {}
    local current_line = ""
    local words = {}
    local max_line_width = 0 -- NEW: Track the maximum width of any line

    -- Split the text into words by one or more spaces [Conversational Turn 1]
    for word in string.gmatch(text_str, "[^%s]+") do
        table.insert(words, word)
    end

    -- Temporarily apply scale for accurate measurement [Conversational Turn 1]
    imgui.SetWindowFontScale(current_font_scale) 
    
    local line_height = imgui.CalcTextSize("Wy") -- Get height of a typical line at this scale [Conversational Turn 1]

    -- Handle empty text case
    if #words == 0 then
        imgui.SetWindowFontScale(1.0) -- Reset font scale after measurement [Conversational Turn 1]
        return {}, 0, 0
    end

    for i, word in ipairs(words) do
        local test_line = current_line
        if current_line ~= "" then
            test_line = test_line .. " " -- Add space if not the first word
        end
        test_line = test_line .. word

        local test_w, _ = imgui.CalcTextSize(test_line) -- Get width of the test line

        if test_w <= max_width then
            current_line = test_line
            max_line_width = math.max(max_line_width, test_w) -- Update max_line_width if this line is wider
        else
            -- If adding the current word makes the line exceed max_width, save current_line and start a new one
            if current_line ~= "" then
                table.insert(lines, current_line)
            end
            current_line = word -- Start a new line with the current word
            -- Important: If the single 'word' itself is wider than max_width, it will be on its own line.
            -- Its width should also be considered for max_line_width.
            max_line_width = math.max(max_line_width, imgui.CalcTextSize(word)) -- Update for the new single word line
        end
    end
    -- Add the last line if any content remains
    if current_line ~= "" then
        table.insert(lines, current_line)
    end

    imgui.SetWindowFontScale(1.0) -- Reset font scale after measurement [Conversational Turn 1]
    -- NEW RETURN VALUE: Return table of lines, total height, AND the maximum line width found
    return lines, #lines * line_height, max_line_width 
end

-- Main helper function to determine best font scale and wrapped text
function get_scaled_wrapped_text(text_string, button_width, button_height, min_font_scale)
    min_font_scale = min_font_scale or 0.6 -- Define a minimum readable font scale (e.g., 60% of original) [Conversational Turn 1]

    local best_scale = 1.0
    local best_lines = {}
    local best_height = 0
    local border_width_buffer = 6
    local found_fitting_scale = false -- Flag to track if a suitable scale was found

    local current_scale = 1.0
    -- Loop downwards from 1.0 to find the largest scale that fits both horizontally and vertically
    while current_scale >= min_font_scale - 0.001 do -- Loop down to just below min_font_scale for precision [Conversational Turn 1]
        -- Call updated wrap_text_for_width to get lines, required height, and widest line width
        local lines, required_height, widest_line_width = wrap_text_for_width(tostring(text_string), button_width, current_scale)
        
        -- Check if BOTH total height AND the widest line's width fit
        if required_height <= button_height and widest_line_width + border_width_buffer <= button_width then
            best_scale = current_scale
            best_lines = lines
            best_height = required_height
            found_fitting_scale = true -- Mark that a fitting scale has been found
            break -- Found the largest scale that fits all criteria, so exit the loop
        end
        
        -- If it doesn't fit, try a smaller scale
        current_scale = current_scale - 0.05 -- Decrement step; adjust as needed for performance/granularity [Conversational Turn 1]
    end

    -- Fallback: If no scale within the tested range (down to min_font_scale) fully fit both criteria,
    -- use the results from the minimum font scale as a last resort. This means there might still be
    -- visual overflow if the text is exceptionally large or the button is exceptionally small.
    if not found_fitting_scale then
        best_lines, best_height, _ = wrap_text_for_width(tostring(text_string), button_width, min_font_scale)
        best_scale = min_font_scale
    end

    return best_lines, best_height, best_scale
end

local arrow_color = 0xFF00FF00

function draw_button(button_name, text, width, height, box_bg_color_int, text_color_int, is_switch_button)
    imgui.SetWindowFontScale(1.0) -- Always reset to default at the start [Conversational Turn 1]
    local cx, cy = imgui.GetCursorScreenPos() -- Get current cursor position for drawing
    imgui.Dummy(width, height) -- Reserve space for the button in the layout
    imgui.DrawList_AddRectFilled(cx, cy, cx + width, cy + height, box_bg_color_int, 0) -- Draw button background

    -- Step 1: Determine the appropriate font scale and wrap the text
    -- The 'get_scaled_wrapped_text' function now handles splitting text into lines and
    -- finding the largest font scale that allows the text to fit both horizontally and vertically.
    local wrapped_lines, text_total_height, final_font_scale = get_scaled_wrapped_text(tostring(text), width, height, 0.6)

    -- Apply the determined font scale for drawing the text on this button [Conversational Turn 1]
    imgui.SetWindowFontScale(final_font_scale)

    -- Step 2: Calculate the vertical starting position to center the block of text within the button
    local start_text_y = cy + (height - text_total_height) / 2
    
    -- Step 3: Draw each wrapped line of text
    local current_line_y = start_text_y
    for _, line in ipairs(wrapped_lines) do
        -- Recalculate size at the final_font_scale, this will now respect the scaling
        local line_w, line_h = imgui.CalcTextSize(line) 
        local line_draw_x = cx + (width - line_w) / 2 -- Center each line horizontally
        
        imgui.SetCursorScreenPos(line_draw_x, current_line_y) -- Set cursor for current line
        imgui.PushStyleColor(imgui.constant.Col.Text, text_color_int) -- Set text color
        imgui.TextUnformatted(line) -- Draw the line of text
        imgui.PopStyleColor() -- Revert text color
        
        current_line_y = current_line_y + line_h -- Move the Y position down for the next line
    end

    -- Crucially, reset font scale to default (1.0) after drawing the button's text
    imgui.SetWindowFontScale(1.0) 
                                  
    -- Step 4: Handle the drawing of the switch indicator (^^ or vv) if it's a switch button
    if is_switch_button then
        local ud_symbol = ""
        local symbol_offset_y = 0
        local padding = -2

        -- Measure the symbol using the same final font scale determined for the main text
        imgui.SetWindowFontScale(final_font_scale) 
        local symbol_w, symbol_h = imgui.CalcTextSize("^^") -- Get height of the symbol at the scaled size
        imgui.SetWindowFontScale(1.0) -- Reset immediately after measuring [Conversational Turn 1]

        -- Determine symbol and its vertical offset
        if current_switch_mode == "up" then -- `current_switch_mode` is a local variable in the script
            ud_symbol = "^^"
            -- symbol_offset_y = -(text_total_height / 2 + symbol_h + padding)
            symbol_offset_y = -(height / 2 + symbol_h + padding)
        elseif current_switch_mode == "down" then
            ud_symbol = "vv"
            -- symbol_offset_y = (text_total_height / 2 + padding)
            symbol_offset_y = (height / 2 + padding)
        end

        -- Apply the determined font scale before drawing the symbol
        imgui.SetWindowFontScale(final_font_scale) 
        local symbol_draw_x = cx + (width - symbol_w) / 2 -- Center the symbol horizontally
        local symbol_draw_y = cy + height / 2 + symbol_offset_y -- Calculate the base Y (center of the button) and then apply the offset
        -- local symbol_draw_y = cy + height / 2 -- Calculate the base Y (center of the button) and then apply the offset

        imgui.SetCursorScreenPos(symbol_draw_x, symbol_draw_y)
		imgui.PushStyleColor(imgui.constant.Col.Text, arrow_color) -- Set symbol color to yellow
        imgui.TextUnformatted(ud_symbol)
        imgui.PopStyleColor()
        imgui.SetWindowFontScale(1.0) -- Reset font scale after drawing the symbol
    end
end

function on_close_floating_window(my_floating_wnd)
    if bravo then
        hid_close(bravo)
    end
end

--------------------------------------------------------------
--- CREATE THE FUNCTIONS FOR REFRESHING THE MODE AND SELECTOR
--------------------------------------------------------------
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
    local num, data1, data2, data3, data4, data5, data6, data7, data8, data9, data10, data11, data12, data13, data14, data15, data16, data17, data18 =
        hid_read(bravo, 64)
    selector = data15
    if selector and selector > 0 then
		log.debug("Selector: " .. selector)
        local idx = 6 - find_position(selector)
        set_current_selector(idx)
    end
end

-- Define button numbers for each selector position
-- local alt_selector_button = nav_bindings.ALT_SELECTOR and nav_bindings.ALT_SELECTOR + 0 or 0
local selector_buttons = {}
if alt_selector_button and alt_selector_button > 0 then
    log.debug("ALT_SELECTOR was set to " .. alt_selector_button)
    for i = 1, 5, 1 do
        selector_buttons[i] = alt_selector_button - i + 1
        log.debug("Selector " .. default_selections[i] .. " set to button " .. selector_buttons[i])
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
    "FlyWithLua/Bravo++/cycle_selector",
    "Cycle the selection (use only when Bravo hardware is not available) ",
    "cycle_selector()", -- Call Lua function when pressed
    "",
    ""
)

-- Choose the available method for updating the selector
if alt_selector_button > 0 then
    do_every_frame("tryCatch(refresh_selector,'refresh_selector')")
else
    do_every_frame("tryCatch(refresh_selector_hid,'refresh_selector_hid')")
end


-- Function to cycle the mode down one
function cycle_mode_down()
    local index = table.find(modes, current_mode)
    index = ((index - 2) % #modes) + 1
    current_mode = modes[index]
    prime_button_led_states_for_mode_change()
    led_state_modified = true
    handle_led_changes()
end


-- Function to cycle the mode down one
function cycle_mode_up()
    local index = table.find(modes, current_mode)
    index = (index % #modes) + 1
    current_mode = modes[index]
	prime_button_led_states_for_mode_change()
    led_state_modified = true
    handle_led_changes()
end

-- Create a custom command for changing mode
create_command(
    "FlyWithLua/Bravo++/mode_button",
    "Bravo++ toggles MODE",
    "tryCatch(cycle_mode_down,'cycle_mode_down')", -- Call Lua function when pressed
    "",
    ""
)

-- Moves the current mode up one
create_command(
    "FlyWithLua/Bravo++/cycle_mode_up",
    "Bravo++ cycle mode up",
    "tryCatch(cycle_mode_up,'cycle_mode_up')", -- Call Lua function when pressed
    "",
    ""
)

-- Moves the current mode down one
create_command(
    "FlyWithLua/Bravo++/cycle_mode_down",
    "Bravo++ cycle mode down",
    "tryCatch(cycle_mode_down,'cycle_mode_down')", -- Call Lua function when pressed
    "",
    ""
)

local mode_select_command = {}
mode_select_command["UP"] = "FlyWithLua/Bravo++/cycle_mode_up"
mode_select_command["DOWN"] = "FlyWithLua/Bravo++/cycle_mode_down"

local mode_select = false

function toggle_mode_select_true()
    mode_select = true
end

function toggle_mode_select_false()
    mode_select = false
end

create_command(
    "FlyWithLua/Bravo++/toggle_mode_select",
    "Activates the mode select when button in pressed in. Deactivates it when button is released.",
    "",
    "tryCatch(toggle_mode_select_true,'toggle_mode_select_true')",
    "tryCatch(toggle_mode_select_false,'toggle_mode_select_false')"
)


-- Function to cycle through outer/inner modes
function cycle_cf_mode()
    local index = table.find(outer_inner_modes, current_cf_mode)
    index = (index % #outer_inner_modes) + 1
    current_cf_mode = outer_inner_modes[index]
end

-- Create a custom command for changing cf mode
create_command(
    "FlyWithLua/Bravo++/cf_mode_button",
    "Bravo++ toggles INNER/OUTER mode",
    "tryCatch(cycle_cf_mode,'cycle_cf_mode')", -- Call Lua function when pressed
    "",
    ""
)

-- Function to cycle through up/down switch modes
function cycle_switch_mode()
    local index = table.find(up_down_modes, current_switch_mode)
    index = (index % #up_down_modes) + 1
    current_switch_mode = up_down_modes[index]
end

-- Create a custom command for changing ud mode
create_command(
    "FlyWithLua/Bravo++/switch_mode_button",
    "Bravo++ toggles UP/DOWN switch mode",
    "tryCatch(cycle_switch_mode,'cycle_switch_mode')", -- Call Lua function when pressed
    "",
    ""
)


function set_current_selector(idx)
    index = idx
    if current_selection_label ~= selection_map_labels[current_mode][index] then
        current_selection_label = selection_map_labels[current_mode][index]
        current_selection = default_selections[index]
		prime_button_led_states_for_mode_change()
        led_state_modified = true
        handle_led_changes()
    end
end

function set_current_buttons()
    if button_map_labels[current_mode][current_selection] ~= nil then
        current_buttons = button_map_labels[current_mode][current_selection]
    end
end

-- Update the currently available buttons
do_every_frame("tryCatch(set_current_buttons,'set_current_buttons')")

--------------------------------------
---- ROCKER SWITCHES
--------------------------------------

function handle_rocker_switch(rocker_number, dir)
    local key = "SWITCH" .. rocker_number .. "_" .. dir
    local binding = nav_bindings[key]
    log.info("SWITCH: " .. binding)
    local command_dataref = binding or "sim/none/none"
    command_once(command_dataref)
end

function rocker_switch1_up()
    handle_rocker_switch(1,"UP")
end

function rocker_switch2_up()
    handle_rocker_switch(2,"UP")
end

function rocker_switch3_up()
    handle_rocker_switch(3,"UP")
end

function rocker_switch4_up()
    handle_rocker_switch(4,"UP")
end

function rocker_switch5_up()
    handle_rocker_switch(5,"UP")
end

function rocker_switch6_up()
    handle_rocker_switch(6,"UP")
end

function rocker_switch7_up()
    handle_rocker_switch(7,"UP")
end

function rocker_switch1_down()
    handle_rocker_switch(1,"DOWN")
end

function rocker_switch2_down()
    handle_rocker_switch(2,"DOWN")
end

function rocker_switch3_down()
    handle_rocker_switch(3,"DOWN")
end

function rocker_switch4_down()
    handle_rocker_switch(4,"DOWN")
end

function rocker_switch5_down()
    handle_rocker_switch(5,"DOWN")
end

function rocker_switch6_down()
    handle_rocker_switch(6,"DOWN")
end

function rocker_switch7_down()
    handle_rocker_switch(7,"DOWN")
end

-- Initialize the rocker switch commands
log.info("Initializing switch commands...")
for i = 1, 7 do
    local func_up_name = "rocker_switch" .. i .. "_up"

    local dataref = "FlyWithLua/Bravo++/" .. func_up_name
    local description = "Bravo++ command for rocker switch" .. i .. " when it is positioned up"
    local command = "tryCatch(".. func_up_name .. ",\'" .. func_up_name.. "\')"
    log.debug("dataref: " .. dataref)
    log.debug("description: " .. description)
    log.debug("command: " .. command)

    create_command(
        dataref,
        description,
        command, -- Call Lua function when pressed
        "",
        ""
    )

    local func_down_name = "rocker_switch" .. i .. "_down"

    local dataref = "FlyWithLua/Bravo++/" .. func_down_name
    local description = "Bravo++ command for rocker switch" .. i .. " when it is positioned down"
    local command = "tryCatch(".. func_down_name .. ",\'" .. func_down_name.. "\')"
    log.debug("dataref: " .. dataref)
    log.debug("description: " .. description)
    log.debug("command: " .. command)

    create_command(
        dataref,
        description,
        command, -- Call Lua function when pressed
        "",
        ""
    )
end

--------------------------------------
---- TRIM WHEEL
--------------------------------------

local trim_last_click_time = 0
local trim_debounce_delay = 0.2 -- 200ms
local trim_dataref = dataref_table("sim/flightmodel2/controls/elevator_trim")
local increment = nav_bindings.TRIM_INCREMENT and nav_bindings.TRIM_INCREMENT + 0 or 0.01 
local boost_factor = nav_bindings.TRIM_BOOST and nav_bindings.TRIM_BOOST + 0 or 3

function handle_bravo_trim_nose_up()
    local current_time = os.clock()
    local diff = current_time - trim_last_click_time

    log.debug("Trim nose up")
    local current_value = tonumber(trim_dataref[0])
    local new_value = current_value
    log.debug("Time since last call: " .. diff)
    if diff < trim_debounce_delay then
        new_value = current_value + increment*boost_factor
        log.debug("Boosting nose up")
    else
        new_value = current_value + increment        
    end
    if new_value <= 1 then 
        trim_dataref[0] = new_value
    elseif  current_value ~= 1 then
        trim_dataref[0] = 1
    end
    log.debug("New trim value: " .. new_value)
    trim_last_click_time = current_time
end

create_command(
    "FlyWithLua/Bravo++/trim_nose_up_handler",
    "Handle trim on bravo for nose up",
    "tryCatch(handle_bravo_trim_nose_up,'handle_bravo_trim_nose_up')", -- Call Lua function when pressed
    "",
    ""
)

function handle_bravo_trim_nose_down()
    local current_time = os.clock()
    local diff = current_time - trim_last_click_time

    log.debug("Trim nose down")
    local current_value = tonumber(trim_dataref[0])
    local new_value = current_value
    log.debug("Time since last call: " .. diff)
    if diff < trim_debounce_delay then
        new_value = current_value - increment*boost_factor
        log.debug("Boosting nose down")
    else
        new_value = current_value - increment        
    end
    if new_value >= -1 then
        trim_dataref[0] = new_value -- This updates the dataref
    elseif  current_value ~= -1 then
        trim_dataref[0] = -1
    end
    log.debug("New trim value: " .. new_value)
    trim_last_click_time = current_time
end

create_command(
    "FlyWithLua/Bravo++/trim_nose_down_handler",
    "Handle trim on bravo for nose down",
    "tryCatch(handle_bravo_trim_nose_down,'handle_bravo_trim_nose_down')", -- Call Lua function when pressed
    "",
    ""
)

-----------------------------------------------------
--- HANDLE TWIST-KNOB THAT INCREASES/DECREASES VALUES
-----------------------------------------------------

local last_click_time = 0
local debounce_delay = 0.02 -- 20ms

function handle_bravo_knob_increase()
    local current_time = os.clock()
    local current_twist_knob_action = nil
    if mode_select then
        current_twist_knob_action = mode_select_command
    else
        current_twist_knob_action = twist_knob_map_actions[current_mode][current_selection]       
    end    
    if current_twist_knob_action ~= nil and (current_time - last_click_time) > debounce_delay then
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
            log.debug("Nothing to do.")
        end
    end
end

create_command(
    "FlyWithLua/Bravo++/knob_increase_handler",
    "Handle button on bravo that increments values",
    "tryCatch(handle_bravo_knob_increase,'handle_bravo_knob_increase')", -- Call Lua function when pressed
    "",
    ""
)

function handle_bravo_knob_decrease()
    local current_time = os.clock()

    local current_twist_knob_action = nil
    if mode_select then
        current_twist_knob_action = mode_select_command
    else
        current_twist_knob_action = twist_knob_map_actions[current_mode][current_selection]
    end
    if current_twist_knob_action ~= nil and (current_time - last_click_time) > debounce_delay then
		if current_twist_knob_action["DOWN"] then
			command_once(current_twist_knob_action["DOWN"])
            last_click_time = current_time
		elseif current_cf_mode == "outer" and current_twist_knob_action["OUTER"] then
			command_once(current_twist_knob_action["OUTER"]["DOWN"])
            last_click_time = current_time
		elseif current_cf_mode == "inner" and current_twist_knob_action["INNER"] then
			command_once(current_twist_knob_action["INNER"]["DOWN"])
            last_click_time = current_time
		else
			log.debug("Nothing to do.")
		end
	end
end

create_command(
    "FlyWithLua/Bravo++/knob_decrease_handler",
    "Handle button on bravo that decrements values",
    "tryCatch(handle_bravo_knob_decrease,'handle_bravo_knob_decrease')", -- Call Lua function when pressed
    "",
    ""
)

--------------------------------------
---- BUTTON HANDLING
--------------------------------------
-- Define a threshold for what constitutes a "long press" in seconds
local LONG_CLICK_THRESHOLD = 0.25 -- Adjust this value as needed (e.g., 0.25 seconds)
local CONTINUOUS_PRESS_THRESHOLD = 0.75 -- Adjust this value as needed (e.g., 0.25 seconds)

-- Declare global variables to track button state across command phases
-- These are necessary because the different parts of create_command run in independent Lua blocks.
local command = "sim/none/none"
local command_state = {}

function start_timer(button_name)
    command_state[button_name] = {}
    command_state[button_name]["start_time"] = os.clock()
    command_state[button_name]["is_continous_mode"] = false
    command_state[button_name]["phase"] = "begin"
end

function handle_continuous_mode(button_name)
    if os.clock() - command_state[button_name]["start_time"] >= CONTINUOUS_PRESS_THRESHOLD then
        if not command_state[button_name]["is_continous_mode"] then
            log.debug("Button " .. button_name .. " held down long enough. Starting continuous mode.")
            command_state[button_name]["is_continous_mode"] = true
			arrow_color = 0xFFED10D8
        end        
        trigger_command_for(button_name)
	elseif os.clock() - command_state[button_name]["start_time"] >= LONG_CLICK_THRESHOLD then
		local commands = get_commands_for_button(button_name)
		if commands["ON_LONG_CLICK"] ~= nil then
			arrow_color = 0xFF18D1CB
		end	
    end
end

function handle_single_click_mode(button_name)
	log.debug("Calling handle_single_click_mode for " .. button_name)
    if not command_state[button_name]["is_continous_mode"] and os.clock() - command_state[button_name]["start_time"] >= LONG_CLICK_THRESHOLD then
		log.debug("Changing state to long_click")
		command_state[button_name]["phase"] = "long_click"
		trigger_command_for(button_name)
	else
		log.debug("Changing state to end")
		command_state[button_name]["phase"] = "end"
		trigger_command_for(button_name)
	end
	arrow_color = 0xFF00FF00
end

function get_commands_for_button(button_name)
    local command = "sim/none/none"
    if is_string(button_map_actions[current_mode][button_name]["ON_CLICK"]) then
        command = button_map_actions[current_mode][button_name]
    elseif current_switch_mode == "up" and is_table(button_map_actions[current_mode][button_name]) and is_table(button_map_actions[current_mode][button_name]["UP"]) and is_string(button_map_actions[current_mode][button_name]["UP"]["ON_CLICK"]) then
        command = button_map_actions[current_mode][button_name]["UP"]
    elseif current_switch_mode == "down" and is_table(button_map_actions[current_mode][button_name]) and  is_table(button_map_actions[current_mode][button_name]["DOWN"] and is_string(button_map_actions[current_mode][button_name]["DOWN"]["ON_CLICK"])) then
        command = button_map_actions[current_mode][button_name]["DOWN"]
    elseif is_table(button_map_actions[current_mode][current_selection]) and is_table(button_map_actions[current_mode][current_selection][button_name]) then
        if is_string(button_map_actions[current_mode][current_selection][button_name]["ON_CLICK"]) then
            command = button_map_actions[current_mode][current_selection][button_name]
        elseif current_switch_mode == "up" and is_string(button_map_actions[current_mode][current_selection][button_name]["UP"]["ON_CLICK"]) then
            command = button_map_actions[current_mode][current_selection][button_name]["UP"]
        elseif current_switch_mode == "down" and is_string(button_map_actions[current_mode][current_selection][button_name]["DOWN"]["ON_CLICK"]) then
            command = button_map_actions[current_mode][current_selection][button_name]["DOWN"]
        else
            log.debug("Button action not found!")
        end
    else
        log.debug("Button action not found!")
    end
    return command
end

function trigger_command_for(button_name)
    local commands = get_commands_for_button(button_name)
    local button_is_continuous_mode = command_state[button_name]["is_continous_mode"]
    local command_phase = command_state[button_name]["phase"]
    tryCatch(function()
        if button_is_continuous_mode then 
            if command_phase == "begin" then
                log.debug("Trigger command begin: " .. commands["ON_HOLD"])
                command_begin(commands["ON_HOLD"])
                command_state[button_name]["phase"] = "continuous"
            elseif command_phase == "end" then
                log.debug("Trigger command end: " .. commands["ON_HOLD"])
                command_end(commands["ON_HOLD"])
            end
        elseif not button_is_continuous_mode then
            if command_phase == "long_click" and commands["ON_LONG_CLICK"] ~= nil then
                log.debug("Trigger command once: " .. commands["ON_LONG_CLICK"])
                command_once(commands["ON_LONG_CLICK"])
            else
                log.debug("Trigger command once: " .. commands["ON_CLICK"])
                command_once(commands["ON_CLICK"])
            end
        end

    end, "handle_bravo_button")
end

-- Autopilot button
function start_timer_for_PLT_button()
    start_timer("PLT")
end

function handle_continuous_mode_for_PLT_button()
    handle_continuous_mode("PLT")
end

function handle_single_click_mode_for_PLT_button()
    handle_single_click_mode("PLT")
end

create_command(
    "FlyWithLua/Bravo++/autopilot_button",
    "Bravo++ toggles AUTOPILOT button",
    "tryCatch(start_timer_for_PLT_button,'start_timer_for_PLT_button')", -- Call Lua function when pressed
    "tryCatch(handle_continuous_mode_for_PLT_button,'handle_continuous_mode_for_PLT_button')",
    "tryCatch(handle_single_click_mode_for_PLT_button,'handle_single_click_mode_for_PLT_button')"
)

-- IAS button
function start_timer_for_IAS_button()
    start_timer("IAS")
end

function handle_continuous_mode_for_IAS_button()
    handle_continuous_mode("IAS")
end

function handle_single_click_mode_for_IAS_button()
    handle_single_click_mode("IAS")
end

create_command(
    "FlyWithLua/Bravo++/ias_button",
    "Bravo++ toggles IAS button",
    "tryCatch(start_timer_for_IAS_button,'start_timer_for_IAS_button')", -- Call Lua function when pressed
    "tryCatch(handle_continuous_mode_for_IAS_button,'handle_continuous_mode_for_IAS_button')",
    "tryCatch(handle_single_click_mode_for_IAS_button,'handle_single_click_mode_for_IAS_button')"
)

-- VS button
function start_timer_for_VS_button()
    start_timer("VS")
end

function handle_continuous_mode_for_VS_button()
    handle_continuous_mode("VS")
end

function handle_single_click_mode_for_VS_button()
    handle_single_click_mode("VS")
end

create_command(
    "FlyWithLua/Bravo++/vs_button",
    "Bravo++ toggles VS button",
    "tryCatch(start_timer_for_VS_button,'start_timer_for_VS_button')", -- Call Lua function when pressed
    "tryCatch(handle_continuous_mode_for_VS_button,'handle_continuous_mode_for_VS_button')",
    "tryCatch(handle_single_click_mode_for_VS_button,'handle_single_click_mode_for_VS_button')"
)

-- ALT button
function start_timer_for_ALT_button()
    start_timer("ALT")
end

function handle_continuous_mode_for_ALT_button()
    handle_continuous_mode("ALT")
end

function handle_single_click_mode_for_ALT_button()
    handle_single_click_mode("ALT")
end

create_command(
    "FlyWithLua/Bravo++/alt_button",
    "Bravo++ toggles ALT button",
    "tryCatch(start_timer_for_ALT_button,'start_timer_for_ALT_button')", -- Call Lua function when pressed
    "tryCatch(handle_continuous_mode_for_ALT_button,'handle_continuous_mode_for_ALT_button')",
    "tryCatch(handle_single_click_mode_for_ALT_button,'handle_single_click_mode_for_ALT_button')"
)

-- REV button
function start_timer_for_REV_button()
    start_timer("REV")
end

function handle_continuous_mode_for_REV_button()
    handle_continuous_mode("REV")
end

function handle_single_click_mode_for_REV_button()
    handle_single_click_mode("REV")
end

create_command(
    "FlyWithLua/Bravo++/rev_button",
    "Bravo++ toggles REV button",
    "tryCatch(start_timer_for_REV_button,'start_timer_for_REV_button')", -- Call Lua function when pressed
    "tryCatch(handle_continuous_mode_for_REV_button,'handle_continuous_mode_for_REV_button')",
    "tryCatch(handle_single_click_mode_for_REV_button,'handle_single_click_mode_for_REV_button')"
)

-- APR button
function start_timer_for_APR_button()
    start_timer("APR")
end

function handle_continuous_mode_for_APR_button()
    handle_continuous_mode("APR")
end

function handle_single_click_mode_for_APR_button()
    handle_single_click_mode("APR")
end

create_command(
    "FlyWithLua/Bravo++/apr_button",
    "Bravo++ toggles APR button",
    "tryCatch(start_timer_for_APR_button,'start_timer_for_APR_button')", -- Call Lua function when pressed
    "tryCatch(handle_continuous_mode_for_APR_button,'handle_continuous_mode_for_APR_button')",
    "tryCatch(handle_single_click_mode_for_APR_button,'handle_single_click_mode_for_APR_button')"
)

-- NAV button
function start_timer_for_NAV_button()
    start_timer("NAV")
end

function handle_continuous_mode_for_NAV_button()
    handle_continuous_mode("NAV")
end

function handle_single_click_mode_for_NAV_button()
    handle_single_click_mode("NAV")
end

create_command(
    "FlyWithLua/Bravo++/nav_button",
    "Bravo++ toggles NAV button",
    "tryCatch(start_timer_for_NAV_button,'start_timer_for_NAV_button')", -- Call Lua function when pressed
    "tryCatch(handle_continuous_mode_for_NAV_button,'handle_continuous_mode_for_NAV_button')",
    "tryCatch(handle_single_click_mode_for_NAV_button,'handle_single_click_mode_for_NAV_button')"
)

-- HDG button
function start_timer_for_HDG_button()
    start_timer("HDG")
end

function handle_continuous_mode_for_HDG_button()
    handle_continuous_mode("HDG")
end

function handle_single_click_mode_for_HDG_button()
    handle_single_click_mode("HDG")
end

create_command(
    "FlyWithLua/Bravo++/hdg_button",
    "Bravo++ toggles HDG button",
    "tryCatch(start_timer_for_HDG_button,'start_timer_for_HDG_button')", -- Call Lua function when pressed
    "tryCatch(handle_continuous_mode_for_HDG_button,'handle_continuous_mode_for_HDG_button')",
    "tryCatch(handle_single_click_mode_for_HDG_button,'handle_single_click_mode_for_HDG_button')"
)

--------------------------------------
---- LED HANDLING
--------------------------------------
local LED_LDG_L_GREEN =		{2, 1}
local LED_LDG_L_RED =		{2, 2}
local LED_LDG_N_GREEN =		{2, 3}
local LED_LDG_N_RED =		{2, 4}
local LED_LDG_R_GREEN =		{2, 5}
local LED_LDG_R_RED =		{2, 6}
local LED_ANC_MSTR_WARNG =	{2, 7}
local LED_ANC_ENG_FIRE =	{2, 8}
local LED_ANC_OIL =			{3, 1}
local LED_ANC_FUEL =		{3, 2}
local LED_ANC_ANTI_ICE =	{3, 3}
local LED_ANC_STARTER =		{3, 4}
local LED_ANC_APU =			{3, 5}
local LED_ANC_MSTR_CTN =	{3, 6}
local LED_ANC_VACUUM =		{3, 7}
local LED_ANC_HYD =			{3, 8}
local LED_ANC_AUX_FUEL =	{4, 1}
local LED_ANC_PRK_BRK =		{4, 2}
local LED_ANC_VOLTS =		{4, 3}
local LED_ANC_DOOR =		{4, 4}

local led_state_modified = false

-- BUTTON LED handling
function get_button_led_state(button_name)
    if is_table(button_map_leds_state[current_mode]["ALL"]) and is_boolean(button_map_leds_state[current_mode]["ALL"][button_name]) then
        if log_led_state then
            log.debug("get_led_state for mode ALL and button name " .. button_name)
        end
        return button_map_leds_state[current_mode]["ALL"][button_name]
    elseif is_table(button_map_leds_state[current_mode][current_selection]) and is_boolean(button_map_leds_state[current_mode][current_selection][button_name]) then
        if log_led_state then
            log.debug("get_led_state for mode " .. current_mode .. ", current selection " .. current_selection .. " and button name " .. button_name)
        end
        return button_map_leds_state[current_mode][current_selection][button_name]
    else
        if log_led_state then       
            log.debug("Return nil for mode " .. current_mode .. " and button_name " .. button_name)
        end
        return nil
    end
end


function set_button_led_state(button_name, state)
    local current_led_state = get_button_led_state(button_name)
    if current_led_state ~= nil and state ~= current_led_state then
        if log_led_state then
            log.debug("get_led_state for " .. button_name .. " = " .. tostring(current_led_state))
        end
        if is_table(button_map_leds_state[current_mode]["ALL"]) and is_boolean(button_map_leds_state[current_mode]["ALL"][button_name]) then
            button_map_leds_state[current_mode]["ALL"][button_name] = state
        elseif is_table(button_map_leds_state[current_mode][current_selection]) and  is_boolean(button_map_leds_state[current_mode][current_selection][button_name]) then
            button_map_leds_state[current_mode][current_selection][button_name] = state
        end
        led_state_modified = true
    else
        if log_led_state then
            if current_led_state ~= nil then
                log.debug("state did not change for mode " .. current_mode .. " and button " .. button_name)
            else
                log.debug("state does not exist for mode " .. current_mode .. " and button " .. button_name)
            end
        end
    end
end

local buffer = {}

function get_led(led)
    -- logMsg("buffer[" .. led[1] .. "][" .. led[2] .. "]")
    return buffer[led[1]][led[2]]
end

function set_led(led, state)
    if state ~= get_led(led) then
        buffer[led[1]][led[2]] = state
        led_state_modified = true
    end
end

-- New helper function to "prime" button LED states for change detection.
-- This temporarily forces the internal state for relevant buttons to 'true'
-- so that handle_led_changes can detect a change to 'false' if needed.
function prime_button_led_states_for_mode_change()
    -- Iterate through all possible physical button labels as defined in default_button_labels [1]
	local led_detected = false -- Used to check whether there are any leds in this selection
    for i = 1, #default_button_labels do
        local button_label = default_button_labels[i]

        -- Check and set for "ALL" selection within the current mode context
        -- The "ALL" selection is used for LEDs that are common across all selector positions within a mode [2, 3]
        if is_table(button_map_leds_state[current_mode]) and is_table(button_map_leds_state[current_mode]["ALL"]) then
            -- Only prime if the LED state entry actually exists for this button in the "ALL" category [4, 5]
            if is_boolean(button_map_leds_state[current_mode]["ALL"][button_label]) then
                button_map_leds_state[current_mode]["ALL"][button_label] = false
                -- Manually setting led_state_modified to true ensures a HID update will be sent [6, 7].
                -- This is a safeguard in case no other state changes occur that would trigger it.
				if log_led_state then
                    log.debug("Setting led to true for [" .. current_mode .. "][ALL][" .. button_label .."]")
                end
                led_state_modified = true
				led_detected = true
            end
        elseif is_table(button_map_leds_state[current_mode]) and is_table(button_map_leds_state[current_mode][current_selection]) then
            -- Only prime if the LED state entry actually exists for this button in this specific selection [5, 9]
            if is_boolean(button_map_leds_state[current_mode][current_selection][button_label]) then
                button_map_leds_state[current_mode][current_selection][button_label] = false
                -- As above, manually forcing led_state_modified to ensure a HID update.
                if log_led_state then
                    log.debug("Setting led to true for [" .. current_mode .. "][" .. current_selection .. "][" .. button_label .."]")
                end
                led_state_modified = true
				led_detected = true
            end
        end
    end
	if not led_detected then -- Ensures all leds are off if no leds are used
		all_leds_off()
	end
    if log_led_state then
        log.debug("Internal button LED states 'primed' to true for mode change evaluation.")
    end
end

function all_leds_off()
    for i = 1, #default_button_labels do
        set_button_led_state(default_button_labels[i], false)
    end

    for bank = 2, 4 do
        buffer[bank] = {}
        for bit = 1, 8 do
            buffer[bank][bit] = false
        end
    end

    led_state_modified = true
    if log_led_state then
        log.debug("Set all leds to off")
    end
end

function send_hid_data()
    local data = {}

    for bank = 1, 4 do
        data[bank] = 0
    end

    for i = 1, #default_button_labels do
        local button_name = default_button_labels[i]
        if is_table(button_map_leds_state[current_mode]["ALL"]) and button_map_leds_state[current_mode]["ALL"][button_name] == true then
            data[1] = bit.bor(data[1], bit.lshift(1, i - 1))
        elseif is_table(button_map_leds_state[current_mode][current_selection]) and button_map_leds_state[current_mode][current_selection][button_name] == true then
            data[1] = bit.bor(data[1], bit.lshift(1, i - 1))
        end
    end

    for bank = 2, 4 do
        for abit = 1, 8 do
            if buffer[bank][abit] == true then
                data[bank] = bit.bor(data[bank], bit.lshift(1, abit - 1))
            end
        end
    end

    local bytes_written = hid_send_filled_feature_report(bravo, 0, 65, data[1], data[2], data[3], data[4]) -- 65 = 1 byte (report ID) + 64 bytes (data)

    if bytes_written == 65 then
        led_state_modified = false
    elseif bytes_written == nil or bytes_written == -1 then
        log.error('ERROR Feature report write failed, an error occurred')
    elseif bytes_written < 65 then
        log.error('ERROR Feature report write failed, only ' .. bytes_written .. ' bytes written')
    end
end

function get_led_state_for_dataref(dr_table, cond, index)
    if dr_table == nil then
        return false
    end
    if is_dataref_array(dr_table) then
		--if is_string(index) then
		--	log.debug("index: " .. index)
		--end
		if index == nil then
			for i = 0, 19 do
				if dr_table[i] ~= tonumber(cond) then
					return true
				end
			end
		else
			-- log.debug("index: " .. index)
			return dr_table[tonumber(index) - 1] ~= tonumber(cond)
		end
		return false
    else
        if dr_table[0] ~= tonumber(cond) then
            return true
        else
			return false
		end
    end
end


local switch_map_leds = {}
local switch_map_leds_cond = {}
local switch_map_leds_index = {}

for i = 1, 7 do
    local key = "SWITCH" .. i .. "_LED"
    if is_string(nav_bindings[key]) then
        local binding = create_table(nav_bindings[key])
        switch_map_leds[key] = dataref_table(binding[1])
        switch_map_leds_cond[key] = binding[2]
        if #binding == 3 then
            switch_map_leds_index[key] = binding[3]
        end
    end
end

function get_led_state_for_switch(switch_label)
    local dataref = switch_map_leds[switch_label]
    if is_dataref_magic_table(dataref) then
        return get_led_state_for_dataref(dataref, switch_map_leds_cond[switch_label], switch_map_leds_index[switch_label])
    end
end

local bus_voltage = dataref_table('sim/cockpit2/electrical/bus_volts')
local master_state = false

-- Landing gear LEDs
local gear = nil
if nav_bindings["GEAR_DEPLOYMENT_LED"] ~= nil then
    local binding = create_table(nav_bindings["GEAR_DEPLOYMENT_LED"])
    gear = dataref_table(binding[1])
end

local annunciator_map_leds = {}
local annunciator_map_leds_cond = {}

for i = 1, #annunciator_labels do
    local key = annunciator_labels[i] .. "_LED"
    if is_string(nav_bindings[key]) then
        local binding = create_table(nav_bindings[key])
        annunciator_map_leds[annunciator_labels[i]] = dataref_table(binding[1])
        annunciator_map_leds_cond[annunciator_labels[i]] = binding[2]
    elseif is_string(nav_bindings[annunciator_labels[i] .. "_1_LED"]) then
        annunciator_map_leds[annunciator_labels[i]] = {}
        annunciator_map_leds_cond[annunciator_labels[i]] = {}
        local idx = 1
        local key = annunciator_labels[i] .. "_" .. tostring(idx) .. "_LED"
        -- logMsg("key: " .. key)
        while is_string(nav_bindings[key]) do
            local binding = create_table(nav_bindings[key])
            annunciator_map_leds[annunciator_labels[i]][idx] = dataref_table(binding[1])
            annunciator_map_leds_cond[annunciator_labels[i]] = binding[2]
            idx = idx + 1
            key = annunciator_labels[i] .. "_" .. tostring(idx) .. "_LED"
            -- logMsg("key: " .. key)
        end
    end 
end

function get_led_state_for_annunciator(annunciator_label)
    local dataref = annunciator_map_leds[annunciator_label]
    -- logMsg("get dataref for: " .. annunciator_label)
    if is_dataref_magic_table(dataref) then
        return get_led_state_for_dataref(dataref, annunciator_map_leds_cond[annunciator_label])
    elseif is_table(dataref) then
        for i = 1, #dataref do
            if get_led_state_for_dataref(dataref[i], annunciator_map_leds_cond[annunciator_label]) == true then
                return true
            end
        end
        return false
    end
end

-- Initialize the initial state
all_leds_off()
send_hid_data()

function handle_button_led_changes()
	for i = 1, #default_button_labels do
        local led_state_for_dataref = nil
        local led_state_for_button = nil
		local button_label = default_button_labels[i]

		-- log.debug("Before if: [" .. current_mode .. "][" .. current_selection .. "][" .. button_label .. "]")
		if is_table(button_map_leds[current_mode]["ALL"]) then
			local dataref = button_map_leds[current_mode]["ALL"][button_label]
            if dataref ~= nil then
                local index = nil
                if is_table(button_map_leds_index[current_mode]["ALL"]) then
                    index = button_map_leds_index[current_mode]["ALL"][button_label]
                end
                
                led_state_for_dataref = get_led_state_for_dataref(dataref, button_map_leds_cond[current_mode]["ALL"][button_label], index)
                led_state_for_button = button_map_leds_state[current_mode]["ALL"][button_label]
            end
		elseif is_table(button_map_leds[current_mode][current_selection]) then
			local dataref = button_map_leds[current_mode][current_selection][button_label]

            if dataref ~= nil then
                local index = nil
                if is_table(button_map_leds_index[current_mode][current_selection]) then
                    index = button_map_leds_index[current_mode][current_selection][button_label]
                end

                led_state_for_dataref = get_led_state_for_dataref(dataref, button_map_leds_cond[current_mode][current_selection][button_label], index)
                led_state_for_button = button_map_leds_state[current_mode][current_selection][button_label]
            end
		end
        -- Check if we need to update the state of the button
        if  led_state_for_dataref ~= led_state_for_button then
            set_button_led_state(button_label, led_state_for_dataref)
        end
	end            
end

function handle_gear_led_changes()
	-- Landing gear
	local gear_leds = {}

	if gear ~= nil then
		for i = 1, 3 do
			gear_leds[i] = {nil, nil} -- green, red

			if gear[i - 1] == 0 then
				-- Gear stowed
				gear_leds[i][1] = false
				gear_leds[i][2] = false
			elseif gear[i - 1] == 1 then
				-- Gear deployed
				gear_leds[i][1] = true
				gear_leds[i][2] = false
			else
				-- Gear moving
				gear_leds[i][1] = false
				gear_leds[i][2] = true
			end
		end
	else
		-- Fixed gear
		for i = 1, 3 do
			gear_leds[i] = {nil, nil} -- green, red

			-- Gear deployed
			gear_leds[i][1] = true
			gear_leds[i][2] = false
		end
	end
	
	set_led(LED_LDG_N_GREEN, gear_leds[1][1])
	set_led(LED_LDG_N_RED, gear_leds[1][2])
	set_led(LED_LDG_L_GREEN, gear_leds[2][1])
	set_led(LED_LDG_L_RED, gear_leds[2][2])
	set_led(LED_LDG_R_GREEN, gear_leds[3][1])
	set_led(LED_LDG_R_RED, gear_leds[3][2])
end

function handle_annunciator_row1_led_changes()
	-- MASTER WARNING
	set_led(LED_ANC_MSTR_WARNG, get_led_state_for_annunciator("MASTER_WARNING"))

	-- ENGINE FIRE
	set_led(LED_ANC_ENG_FIRE, get_led_state_for_annunciator("FIRE_WARNING"))

	-- LOW OIL PRESSURE
	set_led(LED_ANC_OIL, get_led_state_for_annunciator("OIL_LOW_PRESSURE"))

	-- LOW FUEL PRESSURE
	set_led(LED_ANC_FUEL, get_led_state_for_annunciator("FUEL_LOW_PRESSURE"))

	-- ANTI ICE
	set_led(LED_ANC_ANTI_ICE, get_led_state_for_annunciator("ANTI_ICE"))

	-- STARTER ENGAGED
	set_led(LED_ANC_STARTER, get_led_state_for_annunciator("STARTER_ENGAGED"))

	-- APU
	set_led(LED_ANC_APU, get_led_state_for_annunciator("APU"))
end

function handle_annunciator_row2_led_changes()
	-- MASTER CAUTION
	set_led(LED_ANC_MSTR_CTN, get_led_state_for_annunciator("MASTER_CAUTION"))

	-- VACUUM
	set_led(LED_ANC_VACUUM, get_led_state_for_annunciator("VACUUM"))

	-- LOW HYD PRESSURE
	set_led(LED_ANC_HYD, get_led_state_for_annunciator("HYD_LOW_PRESSURE"))

	-- AUX FUEL PUMP
	set_led(LED_ANC_AUX_FUEL, get_led_state_for_annunciator("AUX_FUEL_PUMP"))

	-- PARKING BRAKE
	set_led(LED_ANC_PRK_BRK, get_led_state_for_annunciator("PARKING_BRAKE"))

	-- LOW VOLTS
	set_led(LED_ANC_VOLTS, get_led_state_for_annunciator("VOLTS_LOW"))

	-- DOOR
	set_led(LED_ANC_DOOR, get_led_state_for_annunciator("DOOR"))
end

function handle_led_changes()
    if bus_voltage[0] > 0 then
        master_state = true

		tryCatch(handle_button_led_changes, "handle_button_led_changes")
		
        -- Handle the remaining leds
		tryCatch(handle_gear_led_changes, "handle_gear_led_changes")
		tryCatch(handle_annunciator_row1_led_changes, "handle_annunciator_row1_led_changes")
		tryCatch(handle_annunciator_row2_led_changes, "handle_annunciator_row2_led_changes")
		
    elseif master_state == true then
        log.debug("No voltage detected. Turning all leds off.")
        -- No bus voltage, disable all LEDs
        master_state = false
        tryCatch(all_leds_off, 'all_leds_off')
    end

    -- If we have any LED changes, send them to the device
    if led_state_modified == true then
        tryCatch(send_hid_data,'send_hid_data')
    end
end

local last_call = os.clock()

function do_more_often(func_to_execute, description, interval_seconds)
    local current_time = os.clock()
    -- Check if enough time has passed since the last successful call
    -- The condition (current_time - last_call) >= interval_seconds correctly calculates elapsed time [Conversation History]
    if (current_time - last_call) >= interval_seconds then
        -- Execute the passed function, with its given source name for tryCatch logging
        -- The tryCatch function is designed to log errors with a source string [1]
        tryCatch(func_to_execute, description)
        last_call = current_time -- Update the last call time only if the function was executed
    end
end

function handle_led_changes_task()
    do_more_often(handle_led_changes, 'handle_led_changes', 0.25)
end

-- Register the corrected function to be called every frame
do_every_frame('handle_led_changes_task()')

-- do_every_frame('tryCatch(handle_led_changes)')
-- do_every_frame('handle_led_changes()')

-- Helper function to find index in table (used for cycling modes)
function table.find(t, value)
    for i, v in ipairs(t) do
        if v == value then return i end
    end
    return nil -- Not found.
end

-- Function that logs any function that fails
function tryCatch(tryBlock, source)
  local success, errorMessage = pcall(tryBlock)
  if not success then
    log.error("Caught error from " .. source .. " : " .. errorMessage)
  end
end