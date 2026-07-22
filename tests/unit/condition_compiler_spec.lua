-- tests/unit/condition_compiler_spec.lua
-- Busted test suite for FlyWithLua/Modules/bravo++/condition_compiler.lua
-- Tests pure condition compilation and evaluation logic.

-- Clear module cache to ensure fresh load
package.loaded["bravo++.condition_compiler"] = nil
local cc = require("bravo++.condition_compiler")

-- ============================================================
-- compile_condition() - Operator Tests
-- ============================================================
describe("ConditionCompiler - compile_condition() - Operators", function()
    it("should compile '>0' (greater than)", function()
        local pred = cc.compile_condition(">0")
        assert.is_function(pred.op)
        assert.equals(0, pred.threshold)
        assert.is_true(pred.op(1, 0))
        assert.is_false(pred.op(0, 0))
        assert.is_false(pred.op(-1, 0))
    end)

    it("should compile '>=5' (greater than or equal)", function()
        local pred = cc.compile_condition(">=5")
        assert.is_function(pred.op)
        assert.equals(5, pred.threshold)
        assert.is_true(pred.op(5, 5))
        assert.is_true(pred.op(6, 5))
        assert.is_false(pred.op(4, 5))
    end)

    it("should compile '<10' (less than)", function()
        local pred = cc.compile_condition("<10")
        assert.is_function(pred.op)
        assert.equals(10, pred.threshold)
        assert.is_true(pred.op(9, 10))
        assert.is_false(pred.op(10, 10))
        assert.is_false(pred.op(11, 10))
    end)

    it("should compile '<=3' (less than or equal)", function()
        local pred = cc.compile_condition("<=3")
        assert.is_function(pred.op)
        assert.equals(3, pred.threshold)
        assert.is_true(pred.op(3, 3))
        assert.is_true(pred.op(2, 3))
        assert.is_false(pred.op(4, 3))
    end)

    it("should compile '!=1' (not equal)", function()
        local pred = cc.compile_condition("!=1")
        assert.is_function(pred.op)
        assert.equals(1, pred.threshold)
        assert.is_true(pred.op(2, 1))
        assert.is_true(pred.op(0, 1))
        assert.is_false(pred.op(1, 1))
    end)

    it("should compile '=0' (equal)", function()
        local pred = cc.compile_condition("=0")
        assert.is_function(pred.op)
        assert.equals(0, pred.threshold)
        assert.is_true(pred.op(0, 0))
        assert.is_false(pred.op(1, 0))
        assert.is_false(pred.op(-1, 0))
    end)

    it("should compile operator with negative threshold", function()
        local pred = cc.compile_condition(">-5")
        assert.is_function(pred.op)
        assert.equals(-5, pred.threshold)
        assert.is_true(pred.op(-4, -5))
        assert.is_false(pred.op(-5, -5))
        assert.is_false(pred.op(-6, -5))
    end)

    it("should compile operator with decimal threshold", function()
        local pred = cc.compile_condition(">=0.5")
        assert.is_function(pred.op)
        assert.equals(0.5, pred.threshold)
        assert.is_true(pred.op(0.5, 0.5))
        assert.is_true(pred.op(1.0, 0.5))
        assert.is_false(pred.op(0.4, 0.5))
    end)
end)

-- ============================================================
-- compile_condition() - Bare Number Tests
-- ============================================================
describe("ConditionCompiler - compile_condition() - Bare Numbers", function()
    it("should compile bare number '5' as equality check", function()
        local pred = cc.compile_condition("5")
        assert.is_function(pred.op)
        assert.equals(5, pred.threshold)
        assert.is_true(pred.op(5, 5))
        assert.is_false(pred.op(4, 5))
        assert.is_false(pred.op(6, 5))
    end)

    it("should compile bare number '0' as equality check", function()
        local pred = cc.compile_condition("0")
        assert.is_function(pred.op)
        assert.equals(0, pred.threshold)
        assert.is_true(pred.op(0, 0))
        assert.is_false(pred.op(1, 0))
    end)

    it("should compile bare negative number '-3' as equality check", function()
        local pred = cc.compile_condition("-3")
        assert.is_function(pred.op)
        assert.equals(-3, pred.threshold)
        assert.is_true(pred.op(-3, -3))
        assert.is_false(pred.op(-2, -3))
    end)

    it("should compile bare decimal number '2.5' as equality check", function()
        local pred = cc.compile_condition("2.5")
        assert.is_function(pred.op)
        assert.equals(2.5, pred.threshold)
        assert.is_true(pred.op(2.5, 2.5))
        assert.is_false(pred.op(2.4, 2.5))
    end)
end)

-- ============================================================
-- compile_condition() - Invalid Condition Fallback
-- ============================================================
describe("ConditionCompiler - compile_condition() - Invalid Fallback", function()
    it("should return always-false predicate for invalid string", function()
        local pred = cc.compile_condition("invalid")
        assert.is_function(pred.op)
        assert.equals(0, pred.threshold)
        assert.is_false(pred.op(0, 0))
        assert.is_false(pred.op(1, 0))
        assert.is_false(pred.op(999, 0))
    end)

    it("should return always-false predicate for empty string", function()
        local pred = cc.compile_condition("")
        assert.is_function(pred.op)
        assert.equals(0, pred.threshold)
        assert.is_false(pred.op(0, 0))
        assert.is_false(pred.op(1, 0))
    end)

    it("should return always-false predicate for whitespace-only string", function()
        local pred = cc.compile_condition("   ")
        assert.is_function(pred.op)
        assert.equals(0, pred.threshold)
        assert.is_false(pred.op(0, 0))
    end)

    it("should return always-false predicate for operator without number", function()
        local pred = cc.compile_condition(">")
        assert.is_function(pred.op)
        assert.equals(0, pred.threshold)
        assert.is_false(pred.op(1, 0))
    end)

    it("should return always-false predicate for operator with non-number", function()
        local pred = cc.compile_condition(">abc")
        assert.is_function(pred.op)
        assert.equals(0, pred.threshold)
        assert.is_false(pred.op(1, 0))
    end)

    it("should return always-false predicate for special characters", function()
        local pred = cc.compile_condition("@#$")
        assert.is_function(pred.op)
        assert.equals(0, pred.threshold)
        assert.is_false(pred.op(0, 0))
    end)
end)

-- ============================================================
-- compile_condition() - Edge Cases
-- ============================================================
describe("ConditionCompiler - compile_condition() - Edge Cases", function()
    it("should handle nil input by converting to string", function()
        local pred = cc.compile_condition(nil)
        assert.is_function(pred.op)
        assert.equals(0, pred.threshold)
        assert.is_false(pred.op(0, 0))
    end)

    it("should handle numeric input by converting to string", function()
        local pred = cc.compile_condition(42)
        assert.is_function(pred.op)
        assert.equals(42, pred.threshold)
        assert.is_true(pred.op(42, 42))
        assert.is_false(pred.op(41, 42))
    end)

    it("should handle boolean input by converting to string", function()
        local pred = cc.compile_condition(true)
        -- tostring(true) = "true", which is not a valid condition
        assert.is_function(pred.op)
        assert.is_false(pred.op(0, 0))
    end)

    it("should strip whitespace from condition string", function()
        local pred = cc.compile_condition("  > 3  ")
        -- After stripping: "> 3" -> ">3" won't match because space remains
        -- Actually gsub("%s", "") removes ALL whitespace: "> 3" -> ">3"
        assert.is_function(pred.op)
        assert.equals(3, pred.threshold)
        assert.is_true(pred.op(4, 3))
        assert.is_false(pred.op(3, 3))
    end)

    it("should handle operator with leading whitespace", function()
        local pred = cc.compile_condition("  !=1")
        assert.is_function(pred.op)
        assert.equals(1, pred.threshold)
        assert.is_true(pred.op(2, 1))
        assert.is_false(pred.op(1, 1))
    end)

    it("should prefer multi-char operators over single-char prefixes", function()
        -- "<=5" should match "<=" not "<"
        local pred = cc.compile_condition("<=5")
        assert.is_function(pred.op)
        assert.equals(5, pred.threshold)
        assert.is_true(pred.op(5, 5))
        assert.is_true(pred.op(4, 5))
        assert.is_false(pred.op(6, 5))
    end)

    it("should handle large numbers", function()
        local pred = cc.compile_condition(">=1000000")
        assert.is_function(pred.op)
        assert.equals(1000000, pred.threshold)
        assert.is_true(pred.op(1000000, 1000000))
        assert.is_true(pred.op(2000000, 1000000))
        assert.is_false(pred.op(999999, 1000000))
    end)

    it("should handle scientific notation threshold", function()
        local pred = cc.compile_condition(">1e2")
        assert.is_function(pred.op)
        assert.equals(100, pred.threshold)
        assert.is_true(pred.op(101, 100))
        assert.is_false(pred.op(99, 100))
    end)
end)

-- ============================================================
-- eval_condition() - Basic Tests
-- ============================================================
describe("ConditionCompiler - eval_condition()", function()
    it("should evaluate greater-than condition correctly", function()
        local pred = cc.compile_condition(">0")
        assert.is_true(cc.eval_condition(pred, 1))
        assert.is_false(cc.eval_condition(pred, 0))
        assert.is_false(cc.eval_condition(pred, -1))
    end)

    it("should evaluate equality condition correctly", function()
        local pred = cc.compile_condition("=5")
        assert.is_true(cc.eval_condition(pred, 5))
        assert.is_false(cc.eval_condition(pred, 4))
        assert.is_false(cc.eval_condition(pred, 6))
    end)

    it("should evaluate not-equal condition correctly", function()
        local pred = cc.compile_condition("!=0")
        assert.is_true(cc.eval_condition(pred, 1))
        assert.is_true(cc.eval_condition(pred, -1))
        assert.is_false(cc.eval_condition(pred, 0))
    end)

    it("should evaluate bare number equality correctly", function()
        local pred = cc.compile_condition("3")
        assert.is_true(cc.eval_condition(pred, 3))
        assert.is_false(cc.eval_condition(pred, 2))
        assert.is_false(cc.eval_condition(pred, 4))
    end)

    it("should return false for invalid condition predicate", function()
        local pred = cc.compile_condition("invalid")
        assert.is_false(cc.eval_condition(pred, 0))
        assert.is_false(cc.eval_condition(pred, 1))
        assert.is_false(cc.eval_condition(pred, 999))
    end)

    it("should error when evaluating nil value with comparison operator", function()
        local pred = cc.compile_condition(">0")
        -- nil compared to number in Lua throws an error
        local ok, err = pcall(cc.eval_condition, pred, nil)
        assert.is_false(ok)
    end)

    it("should return false when evaluating nil value with equality check", function()
        local pred = cc.compile_condition("=0")
        -- nil == 0 returns false in Lua (no error)
        assert.is_false(cc.eval_condition(pred, nil))
    end)

    it("should handle nil predicate gracefully", function()
        -- Passing nil as predicate should error or handle gracefully
        -- The module does not guard against nil predicates
        local ok, err = pcall(cc.eval_condition, nil, 0)
        assert.is_false(ok)
    end)

    it("should handle predicate with nil op", function()
        local bad_pred = { op = nil, threshold = 0 }
        local ok, err = pcall(cc.eval_condition, bad_pred, 0)
        assert.is_false(ok)
    end)
end)

-- ============================================================
-- Integration: compile + eval round-trip
-- ============================================================
describe("ConditionCompiler - Round-trip compile + eval", function()
    local test_cases = {
        { cond = ">0", val = 1, expected = true },
        { cond = ">0", val = 0, expected = false },
        { cond = ">0", val = -1, expected = false },
        { cond = ">=5", val = 5, expected = true },
        { cond = ">=5", val = 4, expected = false },
        { cond = "<10", val = 9, expected = true },
        { cond = "<10", val = 10, expected = false },
        { cond = "<=3", val = 3, expected = true },
        { cond = "<=3", val = 4, expected = false },
        { cond = "!=1", val = 1, expected = false },
        { cond = "!=1", val = 2, expected = true },
        { cond = "=0", val = 0, expected = true },
        { cond = "=0", val = 1, expected = false },
        { cond = "7", val = 7, expected = true },
        { cond = "7", val = 6, expected = false },
        { cond = "invalid", val = 0, expected = false },
        { cond = "invalid", val = 42, expected = false },
        { cond = "", val = 0, expected = false },
    }

    for _, tc in ipairs(test_cases) do
        it(string.format("compile('%s') + eval(%s) => %s", tc.cond, tc.val, tc.expected), function()
            local pred = cc.compile_condition(tc.cond)
            local result = cc.eval_condition(pred, tc.val)
            assert.equals(tc.expected, result)
        end)
    end
end)
