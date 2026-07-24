-- ************************************************
-- Configuration Loader Module for Bravo++
-- ************************************************
-- Handles multi-step configuration file detection
-- (exact match → variant match → generic fallback),
-- parses configuration files, and reads preferences.
--
-- Extracted from BravoMultiMode.lua (FEAT-018, Phase 2).
-- Dependencies: log, util; injects file_provider function.
-- ************************************************

local log = require("bravo++.log")
local util = require("bravo++.util")

local M = {}

-- Internal state (injected at init time)
local _file_provider = nil
local _aircraft_dir = nil

--- Initialize the config loader with required dependencies.
--- @param opts table  Configuration options
---   - file_provider: function (path) → table of filenames
---   - aircraft_dir: string (optional, aircraft directory path)
function M.init(opts)
    if not opts then
        return
    end
    if opts.file_provider and type(opts.file_provider) == "function" then
        _file_provider = opts.file_provider
    end
    if opts.aircraft_dir and type(opts.aircraft_dir) == "string" then
        _aircraft_dir = opts.aircraft_dir
    end
end

--- Detect the appropriate configuration file for the given aircraft.
--- Three-step detection:
---   1. Exact match: bravo_multi-mode.<aircraft_name>.cfg
---   2. Variant match: bravo_multi-mode.<aircraft_name>.*.cfg
---   3. Generic fallback: bravo_multi-mode.cfg
---
--- @param aircraft_name string  Aircraft name (e.g. "C90B")
--- @return table  { path: string|nil, found: boolean }
function M.detect_config(aircraft_name)
    local dir = _aircraft_dir
    if not dir then
        log.error("config_loader.detect_config: no aircraft directory specified")
        return { path = nil, found = false }
    end

    -- Step 1: Exact aircraft name match
    local candidate = "bravo_multi-mode." .. aircraft_name .. ".cfg"
    local full_path = dir .. candidate
    log.info("Trying config: " .. full_path)
    if M._file_exists(full_path) then
        log.info("Successfully found exact-match config for " .. aircraft_name)
        return { path = full_path, found = true }
    end

    -- Step 2: Variant match (bravo_multi-mode.<aircraft_name>.*.cfg)
    local escaped_name = aircraft_name:gsub("%-", "%%-"):gsub("%.", "%%.")
    local variant_pattern = "^bravo_multi%-mode%." .. escaped_name .. "%.([^.]+)%.[cC][fF][gG]$"

    local all_files = M._list_files(dir)
    local variant_matches = {}
    for _, filename in ipairs(all_files) do
        if string.match(filename, variant_pattern) then
            table.insert(variant_matches, filename)
        end
    end

    if #variant_matches > 0 then
        -- Sort for deterministic selection when multiple variants exist
        table.sort(variant_matches)

        if #variant_matches > 1 then
            log.warning(
                "Multiple variant config files found: "
                    .. table.concat(variant_matches, ", ")
                    .. ". Using first alphabetically."
            )
        end

        full_path = dir .. variant_matches[1]
        log.info("Trying variant config: " .. full_path)
        return { path = full_path, found = true }
    end

    -- Step 3: Generic fallback
    candidate = "bravo_multi-mode.cfg"
    full_path = dir .. candidate
    log.info("Trying generic config: " .. full_path)
    if M._file_exists(full_path) then
        log.info("Successfully found generic config")
        return { path = full_path, found = true }
    end

    -- No config found
    return { path = nil, found = false }
end

--- Read a key=value config file into nav_bindings table.
--- Returns true if successful, false otherwise.
---
--- @param path string  Full path to the config file
--- @param nav_bindings table  Table to populate with config values
--- @return boolean  Success status
function M.read_file(path, nav_bindings)
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

--- Read global user preferences from a key=value file.
--- Unlike read_file(), this does not fail when the file is missing, as it
--- is an optional user-provided configuration layer.
---
--- @param path string  Full path to the preferences file
--- @param nav_bindings table  Table to populate with preference values
--- @return boolean  True if file was found and parsed, false otherwise
function M.read_preferences(path, nav_bindings)
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
                nav_bindings[key] = value
            end
        end
    end

    cfg_file:close()
    return true
end

--- Build a validation context table from nav_bindings data.
--- Extracts structured data for all LED subsystems and other features.
---
--- @param nav_bindings table  Parsed configuration values
--- @return table  Validation context with gear_dataref, switch_bindings,
---                annunciator_bindings, and button_bindings
function M.build_validation_context(nav_bindings)
    return {
        gear_dataref = nav_bindings["GEAR_DEPLOYMENT_LED"],
        switch_bindings = M._extract_switch_bindings(nav_bindings),
        annunciator_bindings = M._extract_annunciator_bindings(nav_bindings),
        button_bindings = M._extract_button_bindings(nav_bindings),
    }
end

-- Internal helpers

--- Check if a file exists using io.open.
--- @param path string  File path to check
--- @return boolean  True if file exists and is readable
function M._file_exists(path)
    local f = io.open(path, "r")
    if f then
        f:close()
        return true
    end
    return false
end

--- List files in a directory.
--- Uses injected file_provider if available, falls back to util.list_files.
--- @param dir_path string  Directory path
--- @return table  Table of filenames
function M._list_files(dir_path)
    if _file_provider and type(_file_provider) == "function" then
        return _file_provider(dir_path)
    end
    if util and util.list_files then
        return util.list_files(dir_path)
    end
    return {}
end

--- Extract switch LED bindings from nav_bindings.
--- @param nav_bindings table  Configuration values
--- @return table  Switch bindings keyed by SWITCH{i}_LED
local function _extract_switch_bindings(nav_bindings)
    local result = {}
    for i = 1, 7 do
        local key = "SWITCH" .. i .. "_LED"
        if util.is_string(nav_bindings[key]) then
            result[key] = util.create_table(nav_bindings[key])
        end
    end
    return result
end

--- Extract annunciator LED bindings from nav_bindings.
--- @param nav_bindings table  Configuration values
--- @return table  Annunciator bindings keyed by label
local function _extract_annunciator_bindings(nav_bindings)
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

    local result = {}
    for _, label in ipairs(annunciator_labels) do
        local key = label .. "_LED"
        if util.is_string(nav_bindings[key]) then
            result[label] = util.create_table(nav_bindings[key])
        elseif util.is_string(nav_bindings[label .. "_1_LED"]) then
            -- Indexed annunciator (e.g. DOOR_1_LED, DOOR_2_LED)
            local idx = 1
            local indexed_key = label .. "_" .. tostring(idx) .. "_LED"
            result[label] = {}
            while util.is_string(nav_bindings[indexed_key]) do
                result[label][idx] = util.create_table(nav_bindings[indexed_key])
                idx = idx + 1
                indexed_key = label .. "_" .. tostring(idx) .. "_LED"
            end
        end
    end
    return result
end

--- Extract button LED bindings from nav_bindings.
--- @param nav_bindings table  Configuration values
--- @return table  Button bindings keyed by mode/button combinations
local function _extract_button_bindings(nav_bindings)
    local result = {}
    for key, value in pairs(nav_bindings) do
        if key:match("_BUTTON_LED$") then
            result[key] = util.create_table(value)
        end
    end
    return result
end

-- Expose internal helpers for build_validation_context
M._extract_switch_bindings = _extract_switch_bindings
M._extract_annunciator_bindings = _extract_annunciator_bindings
M._extract_button_bindings = _extract_button_bindings

return M
