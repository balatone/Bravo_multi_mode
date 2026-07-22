-- ************************************************
-- Configuration module for Bravo++
-- Handles reading, key validation, and value validation.
-- ************************************************

local util = require("bravo++.util")
local log = require("bravo++.log")
local condition_compiler = require("bravo++.condition_compiler")

local config = {}

-----------------------------------------------------
--- Constants (Internal to module)
-----------------------------------------------------

local annunciator_labels = {
    "MASTER_WARNING",
    "FIRE_WARNING",
    "OIL_LOW_PRESSURE",
    "FUEL_LOW_PRESSURE",
    "ANTI_ICE",
    "STARTER_ENGAGED",
    "APU",
    "MASTER_CAUTION",
    "VACUUM",
    "HYD_LOW_PRESSURE",
    "AUX_FUEL_PUMP",
    "PARKING_BRAKE",
    "VOLTS_LOW",
    "DOOR",
}

-----------------------------------------------------
--- Internal Helpers
-----------------------------------------------------

--- Validates a condition string during config parsing.
--- Uses inline operator check (mirrors condition_compiler logic).
local function is_valid_condition(cond_str)
    local s = tostring(cond_str):gsub("%s", "")
    if s == "" then
        return false
    end
    local OPERATOR_ORDER = { "!=", "<=", ">=", "<", ">", "=" }
    for _, op in ipairs(OPERATOR_ORDER) do
        if s:sub(1, #op) == op then
            local threshold = tonumber(s:sub(#op + 1))
            if threshold then
                return true
            end
        end
    end
    if tonumber(s) then
        return true
    end
    return false
end

--- Compiles a condition string into a callable table during initialization.
--- `context` is an optional string (e.g. config key name) included in error/warning logs.
--- Returns { op = function, threshold = number } or a fail-safe that always returns false.
---
--- Delegates pure compilation to condition_compiler and adds context-aware
--- logging for invalid conditions.
local function compile_condition(cond_str, context)
    -- Check validity first to determine if we need to log a warning
    if not is_valid_condition(cond_str) then
        local msg = "Invalid LED condition '" .. tostring(cond_str) .. "'"
        if context then
            msg = msg .. " (key: " .. context .. ")"
        end
        msg = msg .. ", defaulting to always OFF."
        log.warning(msg)
    end
    return condition_compiler.compile_condition(cond_str)
end

--- Returns true when the compiled condition is satisfied (LED should be ON).
--- `compiled_cond` is a table with { op = function, threshold = number }.
---
--- Delegates to the pure condition_compiler module.
local function eval_condition(val, compiled_cond)
    return condition_compiler.eval_condition(compiled_cond, val)
end

-----------------------------------------------------
--- Public API
-----------------------------------------------------

--- Read a key=value config file into nav_bindings table.
--- Returns true if successful, false otherwise.
function config.read_file(path, nav_bindings)
    local cfg_file = io.open(path, "r")
    if cfg_file then
        for line in cfg_file:lines() do
            -- Skip comments/empty lines and parse key=value
            if not line:match("^%s*#") and line:match("=") then
                local key, value = line:match("^%s*([%w_]+)%s*=%s*(.-)%s*$")
                if key and value then
                    value = util.trim(value)
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

--- Validate that all config keys are recognized.
--- `context` must contain: { modes, default_selections, default_button_labels, up_down_modes, outer_inner_modes }
--- Returns true if valid, false otherwise.
function config.validate_keys(nav_bindings, context)
    local modes = context.modes
    local default_selections = context.default_selections
    local default_button_labels = context.default_button_labels
    local up_down_modes = context.up_down_modes
    local outer_inner_modes = context.outer_inner_modes

    local valid_keys_set = {}
    local function add_key(key)
        valid_keys_set[key] = true
    end

    local missing_required_keys = {} -- New table to track explicitly required keys
    local validation_failed = false -- Flag to indicate if any validation step fails

    -- **Step 1: Check for the presence and validity of the "MODES" key**
    -- 'modes' is a global variable populated from nav_bindings.MODES.
    -- If nav_bindings["MODES"] is nil or an empty string, 'modes' will be an empty table.
    if not nav_bindings["MODES"] or #modes == 0 then
        table.insert(missing_required_keys, "MODES")
        validation_failed = true
    end
    add_key("MODES") -- Mark 'MODES' as a valid key to prevent it from being flagged as 'invalid' if it exists.

    -- **Step 2: Check for _SELECTOR_LABELS for each declared mode**
    -- This loop will only execute if 'modes' contains actual mode names (i.e. 'MODES' was properly defined).
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
                    add_key(
                        mode .. "_" .. selection .. "_" .. button_label .. "_" .. string.upper(ud_mode) .. "_BUTTON"
                    )
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
    add_key("LONG_CLICK_THRESHOLD")
    add_key("CONTINUOUS_PRESS_THRESHOLD")

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
                log.error(' Missing key: "' .. key .. '"')
            end
        end
        if #invalid_keys_found > 0 then
            log.error("Found " .. #invalid_keys_found .. " INVALID (unrecognized) configuration keys in config file:")
            for _, key in ipairs(invalid_keys_found) do
                log.error(' Invalid key: "' .. key .. '"')
            end
        end
        log.error("---------------------------------------------")
        return false -- Indicates validation failed
    else
        log.info("All configuration keys in bravo_multi-mode.cfg are valid.")
        return true -- Indicates validation passed
    end
end

--- Validate that all config values have correct structure and types.
--- `context` must contain: { two_param_led_keys } (the lookup table)
--- Returns true if valid, false otherwise.
function config.validate_values(nav_bindings, context)
    local two_param_led_keys = context.two_param_led_keys

    local invalid_value_entries = {}
    log.info("Starting configuration value validation...")

    for key, value_string in pairs(nav_bindings) do
        if util.ends_with(key, "_SELECTOR_LABELS") then
            local values = util.create_table(value_string)
            if #values ~= 5 then
                table.insert(invalid_value_entries, {
                    key = key,
                    value = value_string,
                    reason = "Invalid number of values for SELECTOR_LABELS. Expected 5, but found " .. #values .. ".",
                })
            end
        elseif util.ends_with(key, "_BUTTON_LABELS") then
            local values = util.create_table(value_string)
            if #values ~= 8 then
                table.insert(invalid_value_entries, {
                    key = key,
                    value = value_string,
                    reason = "Invalid number of values for BUTTON_LABELS. Expected 8, but found " .. #values .. ".",
                })
            end
        elseif util.ends_with(key, "_KNOB_LABELS") then
            local values = util.create_table(value_string)
            if #values < 1 and #values > 2 then
                table.insert(invalid_value_entries, {
                    key = key,
                    value = value_string,
                    reason = "Invalid number of values for BUTTON_LABELS. Expected 1 or 2, but found "
                        .. #values
                        .. ".",
                })
            end
        elseif key == "SWITCH_LABELS" then
            local values = util.create_table(value_string)
            if #values ~= 7 then
                table.insert(invalid_value_entries, {
                    key = key,
                    value = value_string,
                    reason = "Invalid number of values for BUTTON_LABELS. Expected 7, but found " .. #values .. ".",
                })
            end
        elseif key == "MODES" then
            local values = util.create_table(value_string)
            if values[1] ~= "AUTO" then
                table.insert(invalid_value_entries, {
                    key = key,
                    value = value_string,
                    reason = "The first value in MODES must always be AUTO.",
                })
            end
        elseif util.ends_with(key, "_LED") then
            local binding_parameters = util.create_table(value_string)

            if #binding_parameters < 2 or #binding_parameters > 3 then
                table.insert(invalid_value_entries, {
                    key = key,
                    value = value_string,
                    reason = "Invalid number of parameters for LED. "
                        .. "Expected 2 or 3 (DataRef, Number[, Number]), "
                        .. "but found "
                        .. #binding_parameters
                        .. ".",
                })
            else
                -- Common validation for all _LED keys (DataRef existence and condition parameter type)
                local dr_string = binding_parameters[1]
                local dr_table = util.safe_dataref_lookup(dr_string)
                local cond_param = binding_parameters[2]

                if dr_table == nil then
                    table.insert(invalid_value_entries, {
                        key = key,
                        value = value_string,
                        reason = "First parameter '" .. tostring(binding_parameters[1]) .. "' is not a valid DataRef.",
                    })
                end

                if not is_valid_condition(cond_param) then
                    table.insert(invalid_value_entries, {
                        key = key,
                        value = value_string,
                        reason = "Second parameter '"
                            .. tostring(binding_parameters[2])
                            .. "' is not a valid LED condition (expected e.g. '>0', '!=1', '=0').",
                    })
                end

                -- Apply specific parameter count rules based on the key
                if two_param_led_keys[key] then
                    -- For the explicitly listed keys, only 2 parameters are allowed.
                    -- This implicitly means no index is required, even if the DataRef is an array.
                    if #binding_parameters ~= 2 then
                        table.insert(invalid_value_entries, {
                            key = key,
                            value = value_string,
                            reason = "Invalid number of parameters for this LED. "
                                .. "Expected exactly 2 (DataRef, Number), "
                                .. "but found "
                                .. #binding_parameters
                                .. ".",
                        })
                    end
                else
                    -- For all other _LED keys, apply the general 2 or 3 parameter rule with array checks.

                    if #binding_parameters == 3 then
                        local index_param = tonumber(binding_parameters[3])
                        local is_array_dataref = false
                        if dr_table ~= nil then -- Only check array type if DataRef was valid
                            is_array_dataref = util.is_dataref_array(dr_table)
                        end

                        if not is_array_dataref then
                            table.insert(invalid_value_entries, {
                                key = key,
                                value = value_string,
                                reason = "DataRef is not an array, but an index parameter was provided. "
                                    .. "Only 2 parameters allowed.",
                            })
                        elseif index_param == nil then
                            table.insert(invalid_value_entries, {
                                key = key,
                                value = value_string,
                                reason = "Third parameter '"
                                    .. tostring(binding_parameters[3])
                                    .. "' is not a valid number (expected DataRef index).",
                            })
                        end
                    elseif #binding_parameters == 2 then
                        local is_array_dataref = false
                        if dr_table ~= nil then -- Only check array type if DataRef was valid
                            is_array_dataref = util.is_dataref_array(dr_table)
                        end
                        if is_array_dataref then
                            table.insert(invalid_value_entries, {
                                key = key,
                                value = value_string,
                                reason = "DataRef is an array but no index was provided. "
                                    .. "An index parameter is required.",
                            })
                        end
                    end
                end
            end
        elseif
            key == "TRIM_INCREMENT"
            or key == "TRIM_BOOST"
            or key == "LONG_CLICK_THRESHOLD"
            or key == "CONTINUOUS_PRESS_THRESHOLD"
        then
            local num_value = tonumber(value_string)
            if num_value == nil then
                table.insert(invalid_value_entries, {
                    key = key,
                    value = value_string,
                    reason = "Value '" .. tostring(value_string) .. "' is not a valid number.",
                })
            elseif num_value <= 0 then
                table.insert(invalid_value_entries, {
                    key = key,
                    value = value_string,
                    reason = "Value '" .. tostring(value_string) .. "' must be greater than 0.",
                })
            end
        else -- For other keys, assume the value is a command string
            local command_name = util.create_table(value_string)
            -- Check if it's a known internal command that will be created by this script
            for i = 1, #command_name do
                if
                    command_name[i] == "FlyWithLua/Bravo++/cf_mode_button"
                    or command_name[i] == "FlyWithLua/Bravo++/switch_mode_button"
                    or command_name[i] == "FlyWithLua/Bravo++/toggle_mode_select"
                then
                    -- Log a debug message and skip validation for this internal command
                    log.debug(
                        "Skipping command validation for internal command: '"
                            .. command_name[i]
                            .. "' (will be created later)."
                    )
                elseif not util.safe_command_lookup(command_name[i]) then
                    -- Check if the command exists using XPLMFindCommand
                    table.insert(invalid_value_entries, {
                        key = key,
                        value = value_string,
                        reason = "'"
                            .. tostring(command_name[i])
                            .. "' is not a valid X-Plane Command or caused an error during lookup.",
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

--- Read global user preferences from a key=value file.
--- Unlike read_file(), this does not fail when the file is missing, as it
--- is an optional user-provided configuration layer.
--- Returns true if the file was found and parsed, false otherwise.
local function read_preferences(path, table)
    local cfg_file = io.open(path, "r")
    if not cfg_file then
        return false
    end

    for line in cfg_file:lines() do
        if not line:match("^%s*#") and line:match("=") then
            local key, value = line:match("^%s*([%w_]+)%s*=%s*(.-)%s*$")
            if key and value then
                value = util.trim(value)
                value = value:match('^"(.-)"$') or value
                table[key] = value
            end
        end
    end

    cfg_file:close()
    return true
end

-- Expose compile_condition, eval_condition, and read_preferences for use by the main script during initialization
config.compile_condition = compile_condition
config.eval_condition = eval_condition
config.read_preferences = read_preferences

return config
