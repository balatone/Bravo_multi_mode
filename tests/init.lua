-- tests/init.lua
-- Bootstrap for busted test suite.
-- Sets up package.path and mocks FlyWithLua host globals.

-- Mock logMsg provided by FlyWithLua host environment
-- decoder.lua -> log.lua depends on this global
logMsg = function(msg)
    -- Silent by default; set to print for verbose test output
    -- io.stderr:write(msg, "\n")
end

-- Add FlyWithLua modules to package search path
-- The bravo++ modules use require("bravo++.xxx") which maps to bravo++/xxx.lua
local modules_path = "/home/eb/git/Bravo_multi_mode/agentic-refactoring/FlyWithLua/Modules"
package.path = modules_path .. "/?.lua;" .. package.path
package.path = modules_path .. "/?/init.lua;" .. package.path

-- Add tests/ directory to package path for shim modules (e.g. bit.lua)
local tests_path = "/home/eb/git/Bravo_multi_mode/agentic-refactoring/tests"
package.path = tests_path .. "/?.lua;" .. package.path
