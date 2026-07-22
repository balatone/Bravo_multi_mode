-- ************************************************
-- Condition Compiler Module for Bravo++
-- Pure condition compilation and evaluation logic.
-- No side effects (no logging, no file I/O).
-- ************************************************

local M = {}

-- Ordered operator list: multi-char operators first so they are checked
-- before single-char prefixes (e.g. "<=" before "<").
local OPERATOR_ORDER = { "!=", "<=", ">=", "<", ">", "=" }

-- Operator comparison functions (named for testability and coverage).
local function op_neq(v, t)
    return v ~= t
end

local function op_leq(v, t)
    return v <= t
end

local function op_geq(v, t)
    return v >= t
end

local function op_lt(v, t)
    return v < t
end

local function op_gt(v, t)
    return v > t
end

local function op_eq(v, t)
    return v == t
end

-- Operator registry: maps operator strings to comparison functions.
local OPERATOR_MAP = {
    ["!="] = op_neq,
    ["<="] = op_leq,
    [">="] = op_geq,
    ["<"] = op_lt,
    [">"] = op_gt,
    ["="] = op_eq,
}

-- Compiled predicate that always returns false (fail-safe default).
local function always_false_op()
    return false
end

--- Compiles a condition string into a callable predicate table.
--- Parses operators (!=, <=, >=, <, >, =) and bare numbers.
---
--- @param condition_string string  Condition string (e.g. ">0", "!=1", "=5", "3")
--- @return table  Predicate table { op = function, threshold = number }
---                Invalid conditions return a fail-safe predicate that always returns false.
function M.compile_condition(condition_string)
    local s = tostring(condition_string):gsub("%s", "")

    -- Try operator+threshold forms using the ordered list (multi-char before single-char)
    for _, op in ipairs(OPERATOR_ORDER) do
        if s:sub(1, #op) == op then
            local threshold = tonumber(s:sub(#op + 1))
            if threshold then
                return { op = OPERATOR_MAP[op], threshold = threshold }
            end
        end
    end

    -- Bare number -> equality check
    local bare = tonumber(s)
    if bare then
        return {
            op = op_eq,
            threshold = bare,
        }
    end

    -- Invalid condition: fail-safe that always returns false
    return {
        op = always_false_op,
        threshold = 0,
    }
end

--- Evaluates a compiled condition against a value.
--- Returns true when the condition is satisfied.
---
--- @param compiled_predicate table  Predicate from compile_condition { op, threshold }
--- @param value number|nil         Value to test against the predicate
--- @return boolean  true if condition is satisfied, false otherwise
function M.eval_condition(compiled_predicate, value)
    return compiled_predicate.op(value, compiled_predicate.threshold)
end

return M
