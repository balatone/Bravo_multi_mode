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
-- Support nested sub-package paths: require("bravo++.dispatch.action_map") -> bravo++/dispatch/action_map.lua
package.path = modules_path .. "/bravo++/dispatch/?.lua;" .. package.path
-- Support led sub-package paths: require("bravo++.led.engine") -> bravo++/led/engine.lua
package.path = modules_path .. "/bravo++/led/?.lua;" .. package.path
-- Support input sub-package paths: require("bravo++.input.handlers") -> bravo++/input/handlers.lua
package.path = modules_path .. "/bravo++/input/?.lua;" .. package.path

-- Add tests/ directory to package path for shim modules (e.g. bit.lua)
local tests_path = "/home/eb/git/Bravo_multi_mode/agentic-refactoring/tests"
package.path = tests_path .. "/?.lua;" .. package.path
