--[[
    bravo++/init.lua - Composition Root

    This file acts as the composition root for the bravo++ module.
    When require("bravo++") is called, it loads all modules from their
    final locations and returns a table of all module references.

    Usage:
        local bravo = require("bravo++")
        -- Access modules via bravo.util, bravo.log, bravo.dispatch, etc.
]]

-- Core utilities
local util = require("bravo++.util")
local log = require("bravo++.log")
local config = require("bravo++.config")
local condition_compiler = require("bravo++.condition_compiler")
local debug = require("bravo++.debug")
local profiler = require("bravo++.profiler")

-- Hardware & decoding
local hardware = require("bravo++.hardware")
local decoder = require("bravo++.decoder")
local state = require("bravo++.state")

-- Configuration
local config_loader = require("bravo++.config_loader")

-- UI
local ui = require("bravo++.ui")
local mapbuilder = require("bravo++.mapbuilder")

-- LED Engine modules (FEAT-017)
local led_engine = require("bravo++.led_engine")
local led_hid_bridge = require("bravo++.led_hid_bridge")
local annunciator_leds = require("bravo++.annunciator_leds")
local gear_leds = require("bravo++.gear_leds")

-- Input & mode management (FEAT-018/019)
local input_handlers = require("bravo++.input_handlers")
local mode_manager = require("bravo++.mode_manager")
local rocker_switches = require("bravo++.rocker_switches")
local button_lifecycle = require("bravo++.button_lifecycle")

-- Dispatch sub-package (FEAT-021)
local dispatch = require("bravo++.dispatch")
local action_map = require("bravo++.dispatch.action_map")
local buttons = require("bravo++.dispatch.buttons")
local twist = require("bravo++.dispatch.twist")
local trim = require("bravo++.dispatch.trim")
local modes = require("bravo++.dispatch.modes")

return {
    -- Core utilities
    util = util,
    log = log,
    config = config,
    condition_compiler = condition_compiler,
    debug = debug,
    profiler = profiler,

    -- Hardware & decoding
    hardware = hardware,
    decoder = decoder,
    state = state,

    -- Configuration
    config_loader = config_loader,

    -- UI
    ui = ui,
    mapbuilder = mapbuilder,

    -- LED Engine
    led_engine = led_engine,
    led_hid_bridge = led_hid_bridge,
    annunciator_leds = annunciator_leds,
    gear_leds = gear_leds,

    -- Input & mode management
    input_handlers = input_handlers,
    mode_manager = mode_manager,
    rocker_switches = rocker_switches,
    button_lifecycle = button_lifecycle,

    -- Dispatch sub-package
    dispatch = dispatch,
    dispatch_action_map = action_map,
    dispatch_buttons = buttons,
    dispatch_twist = twist,
    dispatch_trim = trim,
    dispatch_modes = modes,
}
