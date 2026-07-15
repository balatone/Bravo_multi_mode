-- tests/_bootstrap.lua
-- Bootstrap for busted test suite.
-- Sets up package.path and mocks FlyWithLua host globals.
-- This file is loaded by busted via --helper option.

-- Load luacov for coverage instrumentation
require("luacov")

-- Determine project root relative to this bootstrap file
local project_root = "/home/eb/git/Bravo_multi_mode/agentic-refactoring"

-- Mock logMsg provided by FlyWithLua host environment
-- decoder.lua -> log.lua depends on this global
_G.logMsg = function() end

-- Add FlyWithLua modules to package search path
-- The bravo++ modules use require("bravo++.xxx") which maps to bravo++/xxx.lua
local modules_path = project_root .. "/FlyWithLua/Modules"
package.path = modules_path .. "/?.lua;" .. package.path
package.path = modules_path .. "/?/init.lua;" .. package.path

-- Add tests/ directory to package path for shim modules (e.g. bit.lua)
local tests_path = project_root .. "/tests"
package.path = tests_path .. "/?.lua;" .. package.path

-- Time mocker: controls os.clock() to bypass debounce
local mock_time = 0
os.clock = function() return mock_time end

_G.advance_time = function(dt)
    dt = dt or 0.5
    mock_time = mock_time + dt
end

_G.set_time = function(t)
    mock_time = t
end
