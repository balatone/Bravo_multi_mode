-- ************************************************
-- Rocker Switch Router Module for Bravo++
-- ************************************************
-- Dynamically creates 14 X-Plane custom commands
-- (7 rocker switches × UP/DOWN directions) using
-- a uniform loop pattern.
--
-- Extracted from BravoMultiMode.lua (FEAT-018, Phase 2).
-- Dependencies: log; injects dispatch_callback_fn.
-- ************************************************

local log = require("bravo++.log")

local M = {}

-- Internal state (injected at init time)
local _dispatch_callback_fn = nil
local _num_switches = 7
local _create_command_fn = nil

--- Initialize the rocker switch router with required dependencies.
--- @param opts table  Configuration options
---   - dispatch_callback_fn: function (name, ...) → any
---   - num_switches: integer (default 7)
---   - create_command_fn: function (dataref, description, press, repeat_, release)
function M.init(opts)
    if not opts then
        return
    end
    if opts.dispatch_callback_fn and type(opts.dispatch_callback_fn) == "function" then
        _dispatch_callback_fn = opts.dispatch_callback_fn
    end
    if opts.num_switches and type(opts.num_switches) == "number" then
        _num_switches = math.floor(opts.num_switches)
    end
    if opts.create_command_fn and type(opts.create_command_fn) == "function" then
        _create_command_fn = opts.create_command_fn
    end
end

--- Register all rocker switch commands.
--- Creates 2 commands per switch (UP and DOWN directions).
function M.register_all()
    if not _create_command_fn then
        log.error("rocker_switches.register_all: create_command_fn not set")
        return
    end

    log.info("Initializing switch commands...")
    for i = 1, _num_switches do
        M._create_switch_command(i, "UP")
        M._create_switch_command(i, "DOWN")
    end
end

--- Get the X-Plane command name for a given switch and direction.
--- @param switch_num integer  Switch number (1-7)
--- @param direction string  Direction ("UP" or "DOWN")
--- @return string  Command name string
function M.get_command_name(switch_num, direction)
    return string.format("FlyWithLua/Bravo++/rocker_switch%d_%s", switch_num, direction:lower())
end

-- Internal helpers

--- Create a single rocker switch command.
--- @param switch_num integer  Switch number (1-7)
--- @param direction string  Direction ("UP" or "DOWN")
function M._create_switch_command(switch_num, direction)
    local func_name = "rocker_switch" .. switch_num .. "_" .. direction:lower()
    local dataref = "FlyWithLua/Bravo++/" .. func_name
    local description = "Bravo++ command for rocker switch "
        .. switch_num
        .. " when it is positioned "
        .. direction:lower()
    local command = string.format("bravo_dispatch('rocker_switch', %d, '%s')", switch_num, direction)

    log.debug("dataref: " .. dataref)
    log.debug("description: " .. description)
    log.debug("command: " .. command)

    _create_command_fn(
        dataref,
        description,
        command, -- Call Lua function when pressed
        "",
        ""
    )
end

return M
