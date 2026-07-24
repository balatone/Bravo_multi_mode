-- tests/bit.lua
-- Shim for LuaBitOp (bit) module, providing bitwise operations for testing.
-- Used when the real bit library is not available in the test environment.
-- Only provides functions actually used by decoder.lua.

local M = {}

local function check_int(a, b)
    a = math.floor(a + 0.5)
    b = math.floor(b + 0.5)
    return a, b
end

function M.band(a, b)
    a, b = check_int(a, b)
    local result = 0
    local bit_val = 1
    while a > 0 or b > 0 do
        local a_bit = a % 2
        local b_bit = b % 2
        if a_bit == 1 and b_bit == 1 then
            result = result + bit_val
        end
        a = math.floor(a / 2)
        b = math.floor(b / 2)
        bit_val = bit_val * 2
    end
    return result
end

function M.bor(a, b)
    a, b = check_int(a, b)
    local result = 0
    local bit_val = 1
    while a > 0 or b > 0 do
        local a_bit = a % 2
        local b_bit = b % 2
        if a_bit == 1 or b_bit == 1 then
            result = result + bit_val
        end
        a = math.floor(a / 2)
        b = math.floor(b / 2)
        bit_val = bit_val * 2
    end
    return result
end

function M.bxor(a, b)
    a, b = check_int(a, b)
    local result = 0
    local bit_val = 1
    while a > 0 or b > 0 do
        local a_bit = a % 2
        local b_bit = b % 2
        if a_bit ~= b_bit then
            result = result + bit_val
        end
        a = math.floor(a / 2)
        b = math.floor(b / 2)
        bit_val = bit_val * 2
    end
    return result
end

function M.lshift(a, b)
    a, b = check_int(a, b)
    return a * (2 ^ b)
end

function M.rshift(a, b)
    a, b = check_int(a, b)
    return math.floor(a / (2 ^ b))
end

function M.bnot(a)
    a = check_int(a, nil)
    return (~a) -- Lua's unary ~ works for integers
end

return M
