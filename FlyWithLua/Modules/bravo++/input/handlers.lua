-- ************************************************
-- Input Handlers Module for Bravo++
-- ************************************************
-- Consolidates trim wheel and twist knob input
-- handlers with safe command execution via injected
-- dispatch module.
--
-- Extracted from BravoMultiMode.lua (FEAT-019, Phase 3b).
-- Resolves _G.command_once bypass (RAD-005 Finding 3)
-- by routing all command invocations through the
-- dispatch module's error handling wrapper.
-- ************************************************

local log = require("bravo++.log")

local M = {}

-- Internal state (injected at init time)
local _dispatch_module = nil
local _decoder_handler_fn = nil
local _selector_handler_fn = nil

-- ============================================================
-- Initialization
-- ============================================================

--- Initialize the input handlers module with required dependencies.
--- @param opts table  Configuration options
---   - dispatch_module: module  The dispatch facade for command execution
---   - decoder_handler_fn: function  Optional decoder callback registration function
---   - selector_handler_fn: function  Selector change handler (called with raw value)
function M.init(opts)
    if not opts then
        return
    end
    if opts.dispatch_module and type(opts.dispatch_module) == "table" then
        _dispatch_module = opts.dispatch_module
    end
    if opts.decoder_handler_fn and type(opts.decoder_handler_fn) == "function" then
        _decoder_handler_fn = opts.decoder_handler_fn
    end
    if opts.selector_handler_fn and type(opts.selector_handler_fn) == "function" then
        _selector_handler_fn = opts.selector_handler_fn
    end
end

-- ============================================================
-- Public: Trim Wheel Handlers
-- ============================================================

--- Handle trim wheel input (nose up or nose down).
--- Delegates to dispatch module with safe command execution.
--- @param direction string  "up" or "down"
function M.handle_trim(direction)
    if not _dispatch_module then
        log.warning("input_handlers: dispatch_module not initialized")
        return
    end

    if direction == "up" then
        _dispatch_module.trim_nose_up()
    elseif direction == "down" then
        _dispatch_module.trim_nose_down()
    else
        log.debug("input_handlers: unknown trim direction: " .. tostring(direction))
    end
end

-- ============================================================
-- Public: Twist Knob Handlers
-- ============================================================

--- Handle twist knob input (increase or decrease).
--- Delegates to dispatch module with safe command execution.
--- @param direction string  "increase" or "decrease"
function M.handle_twist(direction)
    if not _dispatch_module then
        log.warning("input_handlers: dispatch_module not initialized")
        return
    end

    if direction == "increase" then
        _dispatch_module.knob_increase()
    elseif direction == "decrease" then
        _dispatch_module.knob_decrease()
    else
        log.debug("input_handlers: unknown twist direction: " .. tostring(direction))
    end
end

-- ============================================================
-- Public: Decoder Event Handlers
-- ============================================================

--- Handle decoder events (selector, rotary, trim).
--- Routes all events through dispatch module with safe command execution.
--- @param event_type string  "selector", "rotary_cw", "rotary_ccw", "trim"
--- @param value any  Event-specific value
function M.handle_decoder_event(event_type, value)
    if not _dispatch_module then
        log.warning("input_handlers: dispatch_module not initialized")
        return
    end

    if event_type == "selector" then
        M._handle_selector_changed(value)
    elseif event_type == "rotary_cw" then
        M.handle_twist("increase")
    elseif event_type == "rotary_ccw" then
        M.handle_twist("decrease")
    elseif event_type == "trim" then
        M.handle_trim(value)
    else
        log.debug("input_handlers: unknown decoder event: " .. tostring(event_type))
    end
end

--- Register decoder handlers with the decoder module.
--- Uses injected decoder_handler_fn for registration.
function M.register_decoder_handlers()
    if not _decoder_handler_fn then
        log.warning("input_handlers: decoder_handler_fn not set")
        return
    end

    _decoder_handler_fn({
        on_selector_changed = function(new)
            M._handle_selector_changed(new)
        end,
        on_rotary_cw = function()
            M.handle_twist("increase")
        end,
        on_rotary_ccw = function()
            M.handle_twist("decrease")
        end,
        on_trim_changed = function(v)
            M.handle_trim(v)
        end,
    })
end

-- ============================================================
-- Internal Helpers
-- ============================================================

--- Handle selector change events.
--- Uses injected selector_handler_fn if available, otherwise falls back to dispatch.
--- @param value any  Raw selector value (number or other)
function M._handle_selector_changed(value)
    if _selector_handler_fn then
        -- Delegate to composition root handler (handles LED refresh, etc.)
        _selector_handler_fn(value)
    elseif type(value) == "number" and value >= 1 and value <= 5 then
        -- Fallback: direct dispatch update
        if _dispatch_module and _dispatch_module.set_selector_index then
            _dispatch_module.set_selector_index(value)
        end
    elseif type(value) == "number" then
        log.info("input_handlers: selector change raw=" .. tostring(value))
    else
        log.info("input_handlers: selector change (non-numeric) " .. tostring(value))
    end
end

return M
