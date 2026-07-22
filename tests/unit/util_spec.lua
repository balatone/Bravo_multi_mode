-- tests/unit/util_spec.lua
-- Busted test suite for FlyWithLua/Modules/bravo++/util.lua
-- Tests util functionality in a CLI environment with mocked FlyWithLua globals.

-- util.lua requires log.lua which captures logMsg at load time
-- Clear module cache and reload with mocked logMsg
_G.logMsg = function() end
package.loaded["bravo++.log"] = nil
package.loaded["bravo++.util"] = nil
local util = require("bravo++.util")

-- ============================================================
-- trim()
-- ============================================================
describe("Util - trim()", function()
    it("should strip leading whitespace", function()
        assert.equals("hello", util.trim("   hello"))
    end)

    it("should strip trailing whitespace", function()
        assert.equals("hello", util.trim("hello   "))
    end)

    it("should strip both leading and trailing whitespace", function()
        assert.equals("hello world", util.trim("   hello world   "))
    end)

    it("should return empty string for empty input", function()
        assert.equals("", util.trim(""))
    end)

    it("should return empty string for whitespace-only input", function()
        assert.equals("", util.trim("   \t  "))
    end)

    it("should not modify string without surrounding whitespace", function()
        assert.equals("hello", util.trim("hello"))
    end)
end)

-- ============================================================
-- find()
-- ============================================================
describe("Util - find()", function()
    it("should return index of found value", function()
        assert.equals(2, util.find({"a", "b", "c"}, "b"))
    end)

    it("should return 1 for first element", function()
        assert.equals(1, util.find({"a", "b", "c"}, "a"))
    end)

    it("should return nil for not-found value", function()
        assert.is_nil(util.find({"a", "b", "c"}, "d"))
    end)

    it("should return nil for empty table", function()
        assert.is_nil(util.find({}, "a"))
    end)

    it("should find numeric values", function()
        assert.equals(3, util.find({10, 20, 30}, 30))
    end)
end)

-- ============================================================
-- is_boolean()
-- ============================================================
describe("Util - is_boolean()", function()
    it("should return true for boolean true", function()
        assert.is_true(util.is_boolean(true))
    end)

    it("should return true for boolean false", function()
        assert.is_true(util.is_boolean(false))
    end)

    it("should return false for nil", function()
        assert.is_false(util.is_boolean(nil))
    end)

    it("should return false for number", function()
        assert.is_false(util.is_boolean(42))
    end)

    it("should return false for string", function()
        assert.is_false(util.is_boolean("hello"))
    end)

    it("should return false for table", function()
        assert.is_false(util.is_boolean({}))
    end)

    it("should return false for function", function()
        assert.is_false(util.is_boolean(function() end))
    end)
end)

-- ============================================================
-- is_string()
-- ============================================================
describe("Util - is_string()", function()
    it("should return true for string", function()
        assert.is_true(util.is_string("hello"))
    end)

    it("should return true for empty string", function()
        assert.is_true(util.is_string(""))
    end)

    it("should return false for nil", function()
        assert.is_false(util.is_string(nil))
    end)

    it("should return false for number", function()
        assert.is_false(util.is_string(42))
    end)

    it("should return false for boolean", function()
        assert.is_false(util.is_string(true))
    end)

    it("should return false for table", function()
        assert.is_false(util.is_string({}))
    end)
end)

-- ============================================================
-- is_table()
-- ============================================================
describe("Util - is_table()", function()
    it("should return true for table", function()
        assert.is_true(util.is_table({}))
    end)

    it("should return true for non-empty table", function()
        assert.is_true(util.is_table({1, 2, 3}))
    end)

    it("should return false for nil", function()
        assert.is_false(util.is_table(nil))
    end)

    it("should return false for string", function()
        assert.is_false(util.is_table("hello"))
    end)

    it("should return false for number", function()
        assert.is_false(util.is_table(42))
    end)

    it("should return false for boolean", function()
        assert.is_false(util.is_table(true))
    end)
end)

-- ============================================================
-- create_table()
-- ============================================================
describe("Util - create_table()", function()
    it("should return empty table for nil input", function()
        local result = util.create_table(nil)
        assert.is_table(result)
        assert.equals(0, #result)
    end)

    it("should parse single element", function()
        local result = util.create_table("hello")
        assert.equals(1, #result)
        assert.equals("hello", result[1])
    end)

    it("should parse multiple comma-separated elements", function()
        local result = util.create_table("a,b,c")
        assert.equals(3, #result)
        assert.equals("a", result[1])
        assert.equals("b", result[2])
        assert.equals("c", result[3])
    end)

    it("should trim whitespace from elements", function()
        local result = util.create_table(" a , b , c ")
        assert.equals(3, #result)
        assert.equals("a", result[1])
        assert.equals("b", result[2])
        assert.equals("c", result[3])
    end)

    it("should handle empty string", function()
        local result = util.create_table("")
        assert.equals(1, #result)
        assert.equals("", result[1])
    end)

    it("should handle blank values (spaces)", function()
        local result = util.create_table("a, ,c")
        assert.equals(3, #result)
        assert.equals("a", result[1])
        assert.equals("", result[2])
        assert.equals("c", result[3])
    end)
end)

-- ============================================================
-- get_name_before_index()
-- ============================================================
describe("Util - get_name_before_index()", function()
    it("should strip trailing _N suffix", function()
        assert.equals("MODE", util.get_name_before_index("MODE_1"))
    end)

    it("should strip trailing _NN suffix", function()
        assert.equals("MODE", util.get_name_before_index("MODE_12"))
    end)

    it("should return unchanged string without index suffix", function()
        assert.equals("MODE", util.get_name_before_index("MODE"))
    end)
end)

-- ============================================================
-- ends_with()
-- ============================================================
describe("Util - ends_with()", function()
    it("should return true for matching suffix", function()
        assert.is_true(util.ends_with("hello.lua", ".lua"))
    end)

    it("should return false for non-matching suffix", function()
        assert.is_false(util.ends_with("hello.lua", ".txt"))
    end)

    it("should return false when suffix is longer than string", function()
        assert.is_false(util.ends_with("hi", "hello"))
    end)

    it("should return true for exact match", function()
        assert.is_true(util.ends_with("hello", "hello"))
    end)
end)

-- ============================================================
-- safe_dataref_lookup()
-- ============================================================
describe("Util - safe_dataref_lookup()", function()
    it("should reject non-string argument (number)", function()
        local result = util.safe_dataref_lookup(123)
        assert.is_nil(result)
    end)

    it("should reject non-string argument (nil)", function()
        local result = util.safe_dataref_lookup(nil)
        assert.is_nil(result)
    end)

    it("should reject non-string argument (table)", function()
        local result = util.safe_dataref_lookup({})
        assert.is_nil(result)
    end)

    it("should return nil when dataref not found", function()
        -- _G.XPLMFindDataRef returns nil by default in bootstrap
        local result = util.safe_dataref_lookup("sim/test/not_found")
        assert.is_nil(result)
    end)

    it("should return dataref_table result when dataref found", function()
        _G.XPLMFindDataRef = function(name)
            if name == "sim/test/valid" then return "mock_ref" end
            return nil
        end
        _G.dataref_table = function(name)
            if name == "sim/test/valid" then return {1, 2, 3} end
            return {}
        end
        local result = util.safe_dataref_lookup("sim/test/valid")
        assert.is_table(result)
        assert.equals(3, #result)
        -- Restore mocks
        _G.XPLMFindDataRef = function(...) return nil end
        _G.dataref_table = function(...) return {} end
    end)
end)

-- ============================================================
-- safe_command_lookup()
-- ============================================================
describe("Util - safe_command_lookup()", function()
    before_each(function()
        -- Mock XPLMFindCommand which is not in bootstrap by default
        _G.XPLMFindCommand = function(...) return nil end
    end)

    after_each(function()
        _G.XPLMFindCommand = nil
    end)

    it("should reject non-string argument (number)", function()
        local result = util.safe_command_lookup(123)
        assert.is_false(result)
    end)

    it("should reject non-string argument (nil)", function()
        local result = util.safe_command_lookup(nil)
        assert.is_false(result)
    end)

    it("should reject non-string argument (table)", function()
        local result = util.safe_command_lookup({})
        assert.is_false(result)
    end)

    it("should return false when command not found", function()
        _G.XPLMFindCommand = function(...) return nil end
        local result = util.safe_command_lookup("sim/test/not_found")
        assert.is_false(result)
    end)

    it("should return true when command found", function()
        _G.XPLMFindCommand = function(name)
            if name == "sim/test/valid_cmd" then return "mock_cmd_ref" end
            return nil
        end
        local result = util.safe_command_lookup("sim/test/valid_cmd")
        assert.is_true(result)
    end)
end)

-- ============================================================
-- get_dataref_array_size()
-- ============================================================
describe("Util - get_dataref_array_size()", function()
    it("should return nil for table without reftype", function()
        assert.is_nil(util.get_dataref_array_size({}))
    end)

    it("should return element count from reftype", function()
        local dr = { reftype = 8 }
        assert.equals(8, util.get_dataref_array_size(dr))
    end)

    it("should return element count for 16-element array", function()
        local dr = { reftype = 16 }
        assert.equals(16, util.get_dataref_array_size(dr))
    end)

    it("should handle reftype with high bits set", function()
        -- reftype = 0x2000 + 4 = 8196 (type bit + 4 elements)
        local dr = { reftype = 8196 }
        assert.equals(4, util.get_dataref_array_size(dr))
    end)
end)

-- ============================================================
-- list_files()
-- ============================================================
describe("Util - list_files()", function()
    it("should return empty table when io.popen fails", function()
        local orig_popen = io.popen
        io.popen = function() return nil end
        local result = util.list_files("/nonexistent")
        assert.is_table(result)
        assert.equals(0, #result)
        io.popen = orig_popen
    end)

    it("should return file list from io.popen", function()
        local orig_popen = io.popen
        local lines = {"file1.lua", "file2.lua", "file3.lua"}
        io.popen = function(cmd)
            local idx = 0
            return {
                lines = function()
                    return function()
                        idx = idx + 1
                        return lines[idx]
                    end
                end,
                close = function() end
            }
        end
        local result = util.list_files("/some/path")
        assert.equals(3, #result)
        assert.equals("file1.lua", result[1])
        assert.equals("file2.lua", result[2])
        assert.equals("file3.lua", result[3])
        io.popen = orig_popen
    end)

    it("should trim whitespace from filenames", function()
        local orig_popen = io.popen
        local lines = {"  file1.lua  ", "file2.lua"}
        io.popen = function(cmd)
            local idx = 0
            return {
                lines = function()
                    return function()
                        idx = idx + 1
                        return lines[idx]
                    end
                end,
                close = function() end
            }
        end
        local result = util.list_files("/some/path")
        assert.equals(2, #result)
        assert.equals("file1.lua", result[1])
        io.popen = orig_popen
    end)
end)
