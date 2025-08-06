-- ************************************************
-- Helper functions used in Bravo++
-- ************************************************

local log = require("bravo++.log")

local util = {}

function util.trim(s)
    return (s:gsub("^%s*(.-)%s*$", "%1"))
end

function util.is_dataref_magic_table(candidate_table)
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

-- Must determine if dataref is an array using reftype and numeric value
function util.is_dataref_array(dr_table)
    for k,v in pairs(dr_table) do
        if tostring(k) == "reftype" and (tostring(v) == "8" or tostring(v) == "16") then
            return true
        end
    end
    return false
end

function util.is_boolean(cand)
    return type(cand) == "boolean"
end

function util.is_string(cand)
    return type(cand) == "string"
end

function util.is_table(cand)
    return type(cand) == "table"
end

function util.create_table(value_string)
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

function util.get_name_before_index(full_mode_string)
    local conceptual_name = full_mode_string:gsub("_%d+$", "")
    return conceptual_name
end

-- Helper function to check if a string ends with a specific suffix
function util.ends_with(str, suffix)
    return #str >= #suffix and str:sub(-#suffix) == suffix
end

--- Helper function to safely call dataref_table and return its result.
-- Catches any errors thrown by dataref_table that pcall can intercept, and logs if DataRef is not found.
-- Returns the actual result (table or nil) if no error occurred.
function util.safe_dataref_lookup(dataref_name_string)
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
function util.safe_command_lookup(command_name_string)
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

return util