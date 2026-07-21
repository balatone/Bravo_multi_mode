-- tests/_bootstrap.lua
-- Bootstrap for busted test suite.
-- Sets up package.path and mocks FlyWithLua host globals.
-- This file is loaded by busted via --helper option.
--
-- Time Mock API (canonical across all test categories):
--   _G.advance_time(dt)  - Advance mock clock by dt seconds (default 0.5)
--   _G.set_time(t)       - Set mock clock to absolute time t
-- These mocks replace os.clock() to enable deterministic debounce/dedup testing.

-- Load luacov for coverage instrumentation
local status, err = pcall(require, "luacov")
if not status then
    -- luacov not found, which is fine for standard test runs
end

-- Resolve project root relative to this bootstrap file's location.
-- debug.getinfo(1).source returns "@/path/to/file.lua" for file-loaded chunks.
-- We strip the leading "@" and walk up two directories: tests/ -> repo root.
-- This dynamic resolution works regardless of which subdirectory the test file
-- resides in (unit/, integration/, e2e/) or where busted is invoked from.
local bootstrap_path = debug.getinfo(1).source:sub(2)             -- remove leading "@"
local tests_path = bootstrap_path:match("(.*[/\\])")              -- directory containing _bootstrap.lua
local project_root = tests_path:match("(.*[/\\])")                -- parent = repo root

-- Mock logMsg provided by FlyWithLua host environment
-- decoder.lua -> log.lua depends on this global
_G.logMsg = function() end

-- Mock command_* functions provided by FlyWithLua host environment
-- dispatch.lua depends on these for action methods and command lifecycle
_G.command_once = function(...) end
_G.command_begin = function(...) end
_G.command_end = function(...) end

-- Mock dataref_table provided by FlyWithLua host environment
-- config.lua validation and mapbuilder.lua LED initialization depend on this
-- Accepts optional DataRef name parameter, returns empty table stub
_G.dataref_table = function(ref) return {} end

-- Mock XPLMFindDataRef provided by X-Plane SDK
-- config.lua validation and mapbuilder.lua LED initialization depend on this
-- Returns nil as a safe fallback for DataRef lookups
_G.XPLMFindDataRef = function(...) return nil end

-- Add FlyWithLua modules to package search path
-- The bravo++ modules use require("bravo++.xxx") which maps to bravo++/xxx.lua
local modules_path = project_root .. "FlyWithLua/Modules"
package.path = modules_path .. "/?.lua;" .. package.path
package.path = modules_path .. "/?/init.lua;" .. package.path

-- Add tests/ directory to package path for shim modules (e.g. bit.lua)
package.path = tests_path .. "?.lua;" .. package.path

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
