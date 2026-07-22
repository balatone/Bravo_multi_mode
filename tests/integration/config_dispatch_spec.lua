-- tests/integration/config_dispatch_spec.lua
-- Integration tests for config module with condition_compiler.
-- Verifies that dispatch.init() correctly consumes the config module
-- and that compile_condition/eval_condition work end-to-end.

-- Clear module cache to ensure fresh load with mocked globals
package.loaded["bravo++.log"] = nil
package.loaded["bravo++.util"] = nil
package.loaded["bravo++.condition_compiler"] = nil
package.loaded["bravo++.config"] = nil
package.loaded["bravo++.dispatch"] = nil
package.loaded["bravo++.dispatch_action_map"] = nil
package.loaded["bravo++.dispatch_buttons"] = nil
package.loaded["bravo++.dispatch_twist"] = nil
package.loaded["bravo++.dispatch_trim"] = nil
package.loaded["bravo++.dispatch_modes"] = nil

local config = require("bravo++.config")
local condition_compiler = require("bravo++.condition_compiler")
local dispatch = require("bravo++.dispatch")

-- ============================================================
-- Test Helpers
-- ============================================================

local function create_test_bindings()
    return {
        MODES = "AUTO,NAV,COM",
        NAV_SELECTOR_LABELS = "A,B,C,D,E",
        COM_SELECTOR_LABELS = "A,B,C,D,E",
        AUTO_SELECTOR_LABELS = "A,B,C,D,E",
        NAV_SEL1_BUTTON_LABELS = "B1,B2,B3,B4,B5,B6,B7,B8",
        NAV_SEL1_KNOB_LABELS = "K1,K2",
        COM_SEL1_BUTTON_LABELS = "B1,B2,B3,B4,B5,B6,B7,B8",
        COM_SEL1_KNOB_LABELS = "K1,K2",
        SWITCH_LABELS = "S1,S2,S3,S4,S5,S6,S7",
        TRIM_INCREMENT = "0.01",
        TRIM_BOOST = "3",
        LONG_CLICK_THRESHOLD = "0.5",
        CONTINUOUS_PRESS_THRESHOLD = "1.0",
    }
end

local function create_test_ctx()
    return {
        modes = { "AUTO", "NAV", "COM" },
        default_selections = { "SEL1", "SEL2" },
        default_button_labels = { "B1", "B2", "B3", "B4", "B5", "B6", "B7", "B8" },
        up_down_modes = { "up", "down" },
        outer_inner_modes = { "outer", "inner" },
    }
end

-- ============================================================
-- config.compile_condition() - Integration Tests
-- ============================================================
describe("Config - compile_condition() integration", function()
    it("should compile valid condition via config module", function()
        local pred = config.compile_condition(">0", "TEST_LED")
        assert.is_table(pred)
        assert.is_function(pred.op)
        assert.equals(0, pred.threshold)
        assert.is_true(pred.op(1, 0))
        assert.is_false(pred.op(0, 0))
    end)

    it("should compile bare number via config module", function()
        local pred = config.compile_condition("5", "TEST_LED")
        assert.is_table(pred)
        assert.is_function(pred.op)
        assert.equals(5, pred.threshold)
        assert.is_true(pred.op(5, 5))
        assert.is_false(pred.op(4, 5))
    end)

    it("should compile invalid condition via config module (always-false)", function()
        local pred = config.compile_condition("invalid", "TEST_LED")
        assert.is_table(pred)
        assert.is_function(pred.op)
        assert.equals(0, pred.threshold)
        assert.is_false(pred.op(0, 0))
        assert.is_false(pred.op(1, 0))
    end)

    it("should accept context parameter for logging", function()
        -- The context parameter is used for logging; the predicate should
        -- still be a valid always-false for invalid conditions
        local pred = config.compile_condition("bad_condition", "MY_KEY")
        assert.is_table(pred)
        assert.is_function(pred.op)
        assert.is_false(pred.op(1, 0))
    end)

    it("should compile all 6 operators via config module", function()
        local operators = {
            { cond = ">0", val = 1, expected = true },
            { cond = ">0", val = 0, expected = false },
            { cond = ">=5", val = 5, expected = true },
            { cond = "<10", val = 9, expected = true },
            { cond = "<=3", val = 3, expected = true },
            { cond = "!=1", val = 1, expected = false },
            { cond = "=0", val = 0, expected = true },
        }
        for _, tc in ipairs(operators) do
            local pred = config.compile_condition(tc.cond, "test")
            local result = config.eval_condition(tc.val, pred)
            assert.equals(tc.expected, result, string.format("operator %s with value %s", tc.cond, tc.val))
        end
    end)
end)

-- ============================================================
-- config.eval_condition() - Integration Tests
-- ============================================================
describe("Config - eval_condition() integration", function()
    it("should evaluate compiled condition via config module", function()
        local pred = config.compile_condition(">=5", "TEST")
        assert.is_true(config.eval_condition(5, pred))
        assert.is_true(config.eval_condition(10, pred))
        assert.is_false(config.eval_condition(4, pred))
    end)

    it("should evaluate always-false predicate via config module", function()
        local pred = config.compile_condition("invalid", "TEST")
        assert.is_false(config.eval_condition(0, pred))
        assert.is_false(config.eval_condition(1, pred))
    end)

    it("should error on nil value in eval_condition with comparison operator", function()
        local pred = config.compile_condition(">0", "TEST")
        -- nil compared to number in Lua throws an error
        local ok, err = pcall(config.eval_condition, nil, pred)
        assert.is_false(ok)
    end)
end)

-- ============================================================
-- dispatch.init() - Integration Tests
-- ============================================================
describe("Dispatch - init() integration", function()
    it("should initialize dispatch with test bindings", function()
        local bindings = create_test_bindings()
        local ctx = create_test_ctx()

        dispatch.init(bindings, ctx)

        assert.equals("AUTO", dispatch.get_current_mode())
        assert.equals("SEL1", dispatch.get_current_selection())
        assert.is_table(dispatch.get_modes())
        assert.is_table(dispatch.get_default_selections())
        assert.is_table(dispatch.get_default_button_labels())
    end)

    it("should build action maps during init", function()
        local bindings = create_test_bindings()
        local ctx = create_test_ctx()

        dispatch.init(bindings, ctx)

        assert.is_table(dispatch.get_button_is_switch_map())
        assert.is_table(dispatch.get_twist_knob_map_actions())
    end)

    it("should handle minimal bindings", function()
        local bindings = {
            MODES = "AUTO",
            TRIM_INCREMENT = "0.01",
            TRIM_BOOST = "3",
            LONG_CLICK_THRESHOLD = "0.5",
            CONTINUOUS_PRESS_THRESHOLD = "1.0",
        }
        local ctx = {
            modes = { "AUTO" },
            default_selections = { "SEL1" },
            default_button_labels = { "B1" },
        }

        dispatch.init(bindings, ctx)

        assert.equals("AUTO", dispatch.get_current_mode())
        assert.equals("SEL1", dispatch.get_current_selection())
    end)

    it("should set thresholds from config", function()
        local bindings = {
            MODES = "AUTO",
            TRIM_INCREMENT = "0.05",
            TRIM_BOOST = "5",
            LONG_CLICK_THRESHOLD = "0.3",
            CONTINUOUS_PRESS_THRESHOLD = "0.8",
        }
        local ctx = {
            modes = { "AUTO" },
            default_selections = { "SEL1" },
            default_button_labels = { "B1" },
        }

        dispatch.init(bindings, ctx)

        -- Verify that dispatch initialized without errors
        assert.equals("AUTO", dispatch.get_current_mode())
    end)
end)

-- ============================================================
-- End-to-End: compile_condition -> eval_condition via config
-- ============================================================
describe("End-to-End: config condition pipeline", function()
    it("should compile and evaluate '>0' correctly", function()
        local pred = config.compile_condition(">0", "GEAR_DEPLOYMENT_LED")
        assert.is_true(config.eval_condition(1, pred))
        assert.is_false(config.eval_condition(0, pred))
    end)

    it("should compile and evaluate '!=1' correctly", function()
        local pred = config.compile_condition("!=1", "MASTER_WARNING_1_LED")
        assert.is_false(config.eval_condition(1, pred))
        assert.is_true(config.eval_condition(0, pred))
        assert.is_true(config.eval_condition(2, pred))
    end)

    it("should compile and evaluate '=0' correctly", function()
        local pred = config.compile_condition("=0", "FIRE_WARNING_LED")
        assert.is_true(config.eval_condition(0, pred))
        assert.is_false(config.eval_condition(1, pred))
    end)

    it("should compile and evaluate bare number '5' correctly", function()
        local pred = config.compile_condition("5", "TEST_LED")
        assert.is_true(config.eval_condition(5, pred))
        assert.is_false(config.eval_condition(4, pred))
        assert.is_false(config.eval_condition(6, pred))
    end)

    it("should handle invalid condition gracefully in pipeline", function()
        local pred = config.compile_condition("not_a_condition", "TEST_LED")
        -- Always-false predicate
        assert.is_false(config.eval_condition(0, pred))
        assert.is_false(config.eval_condition(1, pred))
        assert.is_false(config.eval_condition(999, pred))
    end)
end)

-- ============================================================
-- config.read_preferences() - Integration Tests
-- ============================================================
describe("Config - read_preferences() integration", function()
    it("should return false when preferences file does not exist", function()
        local prefs = {}
        local result = config.read_preferences("/nonexistent/path/preferences.cfg", prefs)
        assert.is_false(result)
        assert.equals(0, #prefs)
    end)

    it("should parse key=value pairs from preferences file", function()
        local prefs = {}
        local tmp_file = os.tmpname()
        local f = io.open(tmp_file, "w")
        assert.is_not_nil(f)
        f:write("# This is a comment\n")
        f:write("TRIM_INCREMENT=0.05\n")
        f:write('CUSTOM_LABEL="My Label"\n')
        f:write("EMPTY_VAL=\n")
        f:write("  SPACED_KEY  =  spaced_value  \n")
        f:close()

        local result = config.read_preferences(tmp_file, prefs)
        assert.is_true(result)
        assert.equals("0.05", prefs["TRIM_INCREMENT"])
        assert.equals("My Label", prefs["CUSTOM_LABEL"])
        assert.equals("", prefs["EMPTY_VAL"])
        assert.equals("spaced_value", prefs["SPACED_KEY"])

        os.remove(tmp_file)
    end)

    it("should skip comment lines and blank lines", function()
        local prefs = {}
        local tmp_file = os.tmpname()
        local f = io.open(tmp_file, "w")
        assert.is_not_nil(f)
        f:write("# comment line\n")
        f:write("\n")
        f:write("  # indented comment\n")
        f:write("VALID_KEY=some_value\n")
        f:close()

        local result = config.read_preferences(tmp_file, prefs)
        assert.is_true(result)
        assert.equals("some_value", prefs["VALID_KEY"])
        assert.is_nil(prefs["comment line"])
        assert.is_nil(prefs["indented comment"])

        os.remove(tmp_file)
    end)

    it("should skip lines without equals sign", function()
        local prefs = {}
        local tmp_file = os.tmpname()
        local f = io.open(tmp_file, "w")
        assert.is_not_nil(f)
        f:write("NO_EQUALS_HERE\n")
        f:write("GOOD_KEY=good_value\n")
        f:close()

        local result = config.read_preferences(tmp_file, prefs)
        assert.is_true(result)
        assert.equals("good_value", prefs["GOOD_KEY"])
        assert.is_nil(prefs["NO_EQUALS_HERE"])

        os.remove(tmp_file)
    end)

    it("should handle empty preferences file", function()
        local prefs = {}
        local tmp_file = os.tmpname()
        local f = io.open(tmp_file, "w")
        assert.is_not_nil(f)
        f:write("")
        f:close()

        local result = config.read_preferences(tmp_file, prefs)
        assert.is_true(result)
        assert.equals(0, #prefs)

        os.remove(tmp_file)
    end)
end)

-- ============================================================
-- Module independence verification
-- ============================================================
describe("Module independence", function()
    it("should have condition_compiler as a separate module from config", function()
        assert.is_not(config, condition_compiler)
        assert.is_function(condition_compiler.compile_condition)
        assert.is_function(condition_compiler.eval_condition)
    end)

    it("should have config.compile_condition delegate to condition_compiler", function()
        -- Both should produce equivalent predicates for valid conditions
        local pred1 = config.compile_condition(">0", "test")
        local pred2 = condition_compiler.compile_condition(">0")
        assert.equals(pred2.threshold, pred1.threshold)
        -- Both should evaluate the same
        assert.equals(pred2.op(1, 0), pred1.op(1, 0))
        assert.equals(pred2.op(0, 0), pred1.op(0, 0))
    end)

    it("should have config.eval_condition delegate to condition_compiler", function()
        local pred = condition_compiler.compile_condition(">=5")
        local result1 = config.eval_condition(5, pred)
        local result2 = condition_compiler.eval_condition(pred, 5)
        assert.equals(result2, result1)
    end)
end)
