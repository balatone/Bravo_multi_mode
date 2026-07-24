--[[
    bravo++/led/init.lua - LED sub-package entry point

    Re-exports the LED engine facade so that require("bravo++.led")
    resolves to the main engine module when using sub-package directories.
]]
return require("bravo++.led.engine")
