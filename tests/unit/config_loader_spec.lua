-- ************************************************
-- Unit tests for config_loader module (FEAT-018)
-- ************************************************

local config_loader = require("bravo++.config_loader")

describe("config_loader module", function()
    describe("init", function()
        it("should accept file_provider and aircraft_dir options", function()
            config_loader.init({
                file_provider = function(path) return {} end,
                aircraft_dir = "/test/dir/",
            })
            -- init should not error
        end)

        it("should handle nil options", function()
            config_loader.init(nil) -- should not error
        end)
    end)

    describe("detect_config", function()
        it("should return not found when no aircraft directory", function()
            config_loader.init({})
            local result = config_loader.detect_config("C90B")
            assert.is_false(result.found)
            assert.is_nil(result.path)
        end)

        it("should return not found when no config files exist", function()
            config_loader.init({
                file_provider = function(path) return {} end,
                aircraft_dir = "/test/dir/",
            })
            local result = config_loader.detect_config("C90B")
            assert.is_false(result.found)
        end)
    end)

    describe("read_file", function()
        it("should return false for non-existent file", function()
            local nav_bindings = {}
            local result = config_loader.read_file("/nonexistent/path.cfg", nav_bindings)
            assert.is_false(result)
        end)

        it("should parse key=value pairs", function()
            -- Create a temp file
            local f = io.open("/tmp/test_config.cfg", "w")
            f:write("MODES=AUTO,MANUAL\n")
            f:write("TEST_KEY=test_value\n")
            f:write("# comment line\n")
            f:close()

            local nav_bindings = {}
            local result = config_loader.read_file("/tmp/test_config.cfg", nav_bindings)
            assert.is_true(result)
            assert.equals("AUTO,MANUAL", nav_bindings["MODES"])
            assert.equals("test_value", nav_bindings["TEST_KEY"])
        end)
    end)

    describe("read_preferences", function()
        it("should return false for non-existent file", function()
            local nav_bindings = {}
            local result = config_loader.read_preferences("/nonexistent/prefs.cfg", nav_bindings)
            assert.is_false(result)
        end)
    end)

    describe("build_validation_context", function()
        it("should return a table with expected keys", function()
            local context = config_loader.build_validation_context({})
            assert.is_table(context)
            -- gear_dataref may be nil if not in nav_bindings
            assert.is_not_nil(context.switch_bindings)
            assert.is_not_nil(context.annunciator_bindings)
            assert.is_not_nil(context.button_bindings)
        end)

        it("should extract switch bindings", function()
            local nav_bindings = {
                ["SWITCH1_LED"] = "sim/cockpit/switch1,>0",
                ["SWITCH2_LED"] = "sim/cockpit/switch2,>0",
            }
            local context = config_loader.build_validation_context(nav_bindings)
            assert.is_table(context.switch_bindings)
            assert.is_not_nil(context.switch_bindings["SWITCH1_LED"])
            assert.is_not_nil(context.switch_bindings["SWITCH2_LED"])
        end)
    end)
end)
