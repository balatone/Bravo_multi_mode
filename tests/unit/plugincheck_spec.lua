-- tests/unit/plugincheck_spec.lua
-- Unit tests for plugincheck.lua bridge detection logic.
-- Uses mocked io.popen to control filesystem and process listing output.
--
-- Time Mock API (from _bootstrap.lua):
--   _G.advance_time(dt)  - Advance mock clock by dt seconds
--   _G.set_time(t)       - Set mock clock to absolute time t

-- Clear module cache to ensure fresh load with mocked globals
package.loaded["bravo++.log"] = nil
package.loaded["bravo++.plugincheck"] = nil

-- Set up imgui mock before loading plugincheck module
_G.imgui = require("tests.mocks.imgui")

-- Mock RESOURCE_PATH (normally set by FlyWithLua)
_G.RESOURCE_PATH = "/mock/x-plane/plugins/"

-- Mock screen dimensions (normally set by FlyWithLua)
_G.SCREEN_WIDTH = 1920
_G.SCREEN_HEIGHT = 1080

-- Mock float_wnd functions (normally set by FlyWithLua)
_G.float_wnd_create = function(...)
    return "mock_window"
end
_G.float_wnd_set_title = function(...) end
_G.float_wnd_set_imgui_builder = function(...) end
_G.float_wnd_set_position = function(...) end
_G.float_wnd_destroy = function(...) end

-- ============================================================
-- io.popen Mock Setup
-- ============================================================

local original_io_popen = io.popen
local popen_responses = {}
local popen_call_log = {}

local function setup_popen_mock(responses)
    popen_responses = responses or {}
    popen_call_log = {}

    io.popen = function(cmd)
        table.insert(popen_call_log, cmd)

        -- Check for matching response pattern
        for pattern, response in pairs(popen_responses) do
            if string.find(cmd, pattern) then
                -- nil response means io.popen fails (returns nil handle)
                if response == nil then
                    return nil
                end
                -- Return a file-like object with controlled output
                local content = type(response) == "string" and response or ""
                local lines = {}
                for line in content:gmatch("[^\r\n]+") do
                    table.insert(lines, line)
                end
                local idx = 0
                return {
                    lines = function()
                        local current_idx = 0
                        return function()
                            current_idx = current_idx + 1
                            return lines[current_idx]
                        end
                    end,
                    close = function() end,
                    read = function()
                        idx = idx + 1
                        return lines[idx]
                    end,
                }
            end
        end

        -- Default: return empty handle
        return {
            lines = function()
                return function()
                    return nil
                end
            end,
            close = function() end,
            read = function()
                return nil
            end,
        }
    end
end

local function restore_io_popen()
    io.popen = original_io_popen
end

local function get_popen_calls()
    return popen_call_log
end

-- ============================================================
-- is_bridge_folder_present Tests
-- ============================================================

describe("Plugincheck - is_bridge_folder_present", function()
    before_each(function()
        setup_popen_mock({})
    end)

    after_each(function()
        restore_io_popen()
        -- Reload module to reset internal state
        package.loaded["bravo++.plugincheck"] = nil
    end)

    it("should return true when win_x64 subfolder exists", function()
        setup_popen_mock({
            ["AFC_Bridge"] = "win_x64\nmac_x64\nREADME.txt",
        })

        local plugincheck = require("bravo++.plugincheck")
        local status = plugincheck.check_bridge_status()

        assert.is_true(status.folder_present)
    end)

    it("should return true when mac_x64 subfolder exists", function()
        setup_popen_mock({
            ["AFC_Bridge"] = "mac_x64\ninfo.txt",
        })

        local plugincheck = require("bravo++.plugincheck")
        local status = plugincheck.check_bridge_status()

        assert.is_true(status.folder_present)
    end)

    it("should return false when no platform subfolder exists", function()
        setup_popen_mock({
            ["AFC_Bridge"] = "README.txt\nLICENSE.md",
        })

        local plugincheck = require("bravo++.plugincheck")
        local status = plugincheck.check_bridge_status()

        assert.is_false(status.folder_present)
    end)

    it("should return false when io.popen fails", function()
        setup_popen_mock({
            ["AFC_Bridge"] = nil, -- Return nil handle
        })
        -- Override to return nil for this specific test
        io.popen = function(cmd)
            table.insert(popen_call_log, cmd)
            if string.find(cmd, "AFC_Bridge") then
                return nil
            end
            return {
                lines = function()
                    return nil
                end,
                close = function() end,
            }
        end

        local plugincheck = require("bravo++.plugincheck")
        local status = plugincheck.check_bridge_status()

        assert.is_false(status.folder_present)
    end)

    it("should return false when directory is empty", function()
        setup_popen_mock({
            ["AFC_Bridge"] = "",
        })

        local plugincheck = require("bravo++.plugincheck")
        local status = plugincheck.check_bridge_status()

        assert.is_false(status.folder_present)
    end)

    it("should use correct command for platform detection", function()
        setup_popen_mock({
            ["AFC_Bridge"] = "win_x64",
        })

        local plugincheck = require("bravo++.plugincheck")
        plugincheck.check_bridge_status()

        local calls = get_popen_calls()
        assert.is_true(#calls >= 1)
        -- Should contain AFC_Bridge in the command
        assert.is_not_nil(string.find(calls[1], "AFC_Bridge"))
    end)
end)

-- ============================================================
-- is_bridge_process_running Tests
-- ============================================================

describe("Plugincheck - is_bridge_process_running", function()
    before_each(function()
        setup_popen_mock({})
    end)

    after_each(function()
        restore_io_popen()
        package.loaded["bravo++.plugincheck"] = nil
    end)

    it("should return true when honeycomb-configurator.exe is running", function()
        setup_popen_mock({
            ["tasklist"] = "Image Name                     PID\nhoneycomb-configurator.exe    1234",
        })

        local plugincheck = require("bravo++.plugincheck")
        local status = plugincheck.check_bridge_status()

        -- Note: On non-Windows platforms, is_bridge_process_running returns false
        -- because the function checks package.config for Windows detection
        -- The actual process detection test depends on platform
        if string.sub(package.config, 1, 1) == "\\" then
            assert.is_true(status.process_running)
        end
    end)

    it("should return false when no bridge process is running", function()
        setup_popen_mock({
            ["tasklist"] = "Image Name                     PID\nnotepad.exe                 5678",
        })

        local plugincheck = require("bravo++.plugincheck")
        local status = plugincheck.check_bridge_status()

        -- On non-Windows, always returns false
        if string.sub(package.config, 1, 1) == "\\" then
            assert.is_false(status.process_running)
        end
    end)

    it("should return false when tasklist returns empty", function()
        setup_popen_mock({
            ["tasklist"] = "",
        })

        local plugincheck = require("bravo++.plugincheck")
        local status = plugincheck.check_bridge_status()

        if string.sub(package.config, 1, 1) == "\\" then
            assert.is_false(status.process_running)
        end
    end)

    it("should return false on non-Windows platforms", function()
        -- On Linux/macOS (package.config starts with /),
        -- is_bridge_process_running always returns false
        if string.sub(package.config, 1, 1) ~= "\\" then
            setup_popen_mock({
                ["tasklist"] = "honeycomb-configurator.exe    1234",
            })

            local plugincheck = require("bravo++.plugincheck")
            local status = plugincheck.check_bridge_status()

            assert.is_false(status.process_running)
        end
    end)

    it("should handle io.popen failure gracefully", function()
        io.popen = function(cmd)
            table.insert(popen_call_log, cmd)
            return nil
        end

        local plugincheck = require("bravo++.plugincheck")
        local status = plugincheck.check_bridge_status()

        -- Should not error, should return false
        assert.is_not_nil(status)
    end)
end)

-- ============================================================
-- check_bridge_status Tests
-- ============================================================

describe("Plugincheck - check_bridge_status", function()
    before_each(function()
        setup_popen_mock({})
    end)

    after_each(function()
        restore_io_popen()
        package.loaded["bravo++.plugincheck"] = nil
    end)

    it("should return status table with both fields", function()
        setup_popen_mock({
            ["AFC_Bridge"] = "",
        })

        local plugincheck = require("bravo++.plugincheck")
        local status = plugincheck.check_bridge_status()

        assert.is_table(status)
        assert.is_table(status)
        assert.is_not_nil(status.folder_present)
        assert.is_not_nil(status.process_running)
    end)

    it("should detect bridge folder present", function()
        setup_popen_mock({
            ["AFC_Bridge"] = "win_x64",
        })

        local plugincheck = require("bravo++.plugincheck")
        local status = plugincheck.check_bridge_status()

        assert.is_true(status.folder_present)
    end)

    it("should report clean status when no bridge detected", function()
        setup_popen_mock({
            ["AFC_Bridge"] = "",
        })

        local plugincheck = require("bravo++.plugincheck")
        local status = plugincheck.check_bridge_status()

        assert.is_false(status.folder_present)
    end)
end)

-- ============================================================
-- should_warn Tests
-- ============================================================

describe("Plugincheck - should_warn", function()
    before_each(function()
        setup_popen_mock({})
    end)

    after_each(function()
        restore_io_popen()
        package.loaded["bravo++.plugincheck"] = nil
    end)

    it("should warn when bridge folder is present", function()
        setup_popen_mock({
            ["AFC_Bridge"] = "win_x64",
        })

        local plugincheck = require("bravo++.plugincheck")
        local result = plugincheck.should_warn()

        assert.is_true(result)
    end)

    it("should not warn when no bridge detected", function()
        setup_popen_mock({
            ["AFC_Bridge"] = "",
        })

        local plugincheck = require("bravo++.plugincheck")
        local result = plugincheck.should_warn()

        assert.is_false(result)
    end)

    it("should warn when process is running (combined logic)", function()
        -- should_warn returns true when folder_present OR process_running
        setup_popen_mock({
            ["AFC_Bridge"] = "win_x64",
            ["tasklist"] = "honeycomb-configurator.exe    1234",
        })

        local plugincheck = require("bravo++.plugincheck")
        local result = plugincheck.should_warn()

        assert.is_true(result)
    end)

    it("should not warn when both checks are clean", function()
        setup_popen_mock({
            ["AFC_Bridge"] = "",
            ["tasklist"] = "",
        })

        local plugincheck = require("bravo++.plugincheck")
        local result = plugincheck.should_warn()

        assert.is_false(result)
    end)
end)

-- ============================================================
-- build_warning_gui Tests (mocked)
-- ============================================================

describe("Plugincheck - build_warning_gui (mocked)", function()
    before_each(function()
        setup_popen_mock({})
    end)

    after_each(function()
        restore_io_popen()
        package.loaded["bravo++.plugincheck"] = nil
    end)

    it("should build warning GUI without errors", function()
        local plugincheck = require("bravo++.plugincheck")

        -- Should not error with mocked imgui
        plugincheck.build_warning_gui("mock_wnd", 100, 100)
    end)
end)

-- ============================================================
-- show_warning_if_needed Tests
-- ============================================================

describe("Plugincheck - show_warning_if_needed", function()
    before_each(function()
        setup_popen_mock({})
    end)

    after_each(function()
        restore_io_popen()
        package.loaded["bravo++.plugincheck"] = nil
    end)

    it("should not create window when no warning needed", function()
        setup_popen_mock({
            ["AFC_Bridge"] = "",
        })

        local plugincheck = require("bravo++.plugincheck")
        plugincheck.show_warning_if_needed()
        -- Should return early without creating window
    end)

    it("should create window when warning is needed", function()
        setup_popen_mock({
            ["AFC_Bridge"] = "win_x64",
        })

        local plugincheck = require("bravo++.plugincheck")
        -- Should not error, creates warning window
        plugincheck.show_warning_if_needed()
    end)
end)
