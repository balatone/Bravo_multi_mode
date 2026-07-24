-- ************************************************
-- Button Lifecycle Manager Module for Bravo++
-- ************************************************
-- Manages the autopilot button lifecycle by registering
-- begin/continue/end callbacks for each AP button.
--
-- Extracted from BravoMultiMode.lua (FEAT-018, Phase 2).
-- Dependencies: log; injects ap_buttons and dispatch_callback_fn.
-- ************************************************

local log = require("bravo++.log")

local M = {}

-- Internal state (injected at init time)
local _ap_buttons = {}
local _create_command_fn = nil

--- Initialize the button lifecycle manager with required dependencies.
--- @param opts table  Configuration options
---   - ap_buttons: array of { key, command, description }
---   - create_command_fn: function (dataref, description, press, repeat_, release)
function M.init(opts)
    if not opts then
        return
    end
    if opts.ap_buttons and type(opts.ap_buttons) == "table" then
        _ap_buttons = opts.ap_buttons
    end
    if opts.create_command_fn and type(opts.create_command_fn) == "function" then
        _create_command_fn = opts.create_command_fn
    end
end

--- Register all AP button lifecycle commands.
--- Creates 3 commands per button: begin, continue, end.
function M.register_all()
    if not _create_command_fn then
        log.error("button_lifecycle.register_all: create_command_fn not set")
        return
    end

    for _, b in ipairs(_ap_buttons) do
        M._register_button(b)
    end
end

--- Get the three X-Plane command names for a given AP button.
--- @param button_key string  Button key (e.g. "PLT", "IAS")
--- @return table  { begin: string, continue: string, end: string }
function M.get_button_commands(button_key)
    local entry = nil
    for _, b in ipairs(_ap_buttons) do
        if b.key == button_key then
            entry = b
            break
        end
    end
    if not entry then
        return nil
    end
    return {
        begin = "FlyWithLua/Bravo++/" .. entry.command .. "_begin",
        continue = "FlyWithLua/Bravo++/" .. entry.command .. "_continue",
        ["end"] = "FlyWithLua/Bravo++/" .. entry.command .. "_end",
    }
end

-- Internal helpers

--- Create all three lifecycle commands for a single AP button.
--- @param button_entry table  { key, command, description }
function M._register_button(button_entry)
    local dataref = "FlyWithLua/Bravo++/" .. button_entry.command
    local description = "Bravo++ toggles " .. button_entry.description .. " button"

    local press_cmd = string.format("bravo_dispatch('ap_begin', '%s')", button_entry.key)
    local repeat_cmd = string.format("bravo_dispatch('ap_continue', '%s')", button_entry.key)
    local release_cmd = string.format("bravo_dispatch('ap_end', '%s')", button_entry.key)

    _create_command_fn(dataref, description, press_cmd, repeat_cmd, release_cmd)
end

return M
