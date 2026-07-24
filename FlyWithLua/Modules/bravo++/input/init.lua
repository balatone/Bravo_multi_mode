--[[
    bravo++/input/init.lua - Input sub-package entry point

    Re-exports the input handlers facade so that require("bravo++.input")
    resolves to the main handlers module when using sub-package directories.
]]
return require("bravo++.input.handlers")
