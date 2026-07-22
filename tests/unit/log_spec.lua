-- tests/unit/log_spec.lua
-- Busted test suite for FlyWithLua/Modules/bravo++/log.lua
-- Tests log functionality with mocked os.clock() and logMsg.

-- Helper: capture logMsg calls
local captured_messages = {}

-- Helper: reload log module with fresh logMsg capture
-- log.lua captures logMsg at module load time via `local logMsg = logMsg`
-- so we must reload the module after setting our mock
local function reload_log()
    captured_messages = {}
    _G.logMsg = function(msg)
        table.insert(captured_messages, msg)
    end
    package.loaded["bravo++.log"] = nil
    return require("bravo++.log")
end

local log = reload_log()

-- ============================================================
-- Log Level Constants
-- ============================================================
describe("Log - Constants", function()
    it("should define LOG_ERROR as 1", function()
        assert.equals(1, log.LOG_ERROR)
    end)

    it("should define LOG_WARNING as 2", function()
        assert.equals(2, log.LOG_WARNING)
    end)

    it("should define LOG_INFO as 3", function()
        assert.equals(3, log.LOG_INFO)
    end)

    it("should define LOG_DEBUG as 4", function()
        assert.equals(4, log.LOG_DEBUG)
    end)

    it("should define NO_LOG as 0", function()
        assert.equals(0, log.NO_LOG)
    end)
end)

-- ============================================================
-- debug()
-- ============================================================
describe("Log - debug()", function()
    before_each(function()
        log = reload_log()
    end)

    it("should log message when LOG_LEVEL is LOG_DEBUG", function()
        log.LOG_LEVEL = log.LOG_DEBUG
        _G.set_time(1.234)
        log.debug("test debug message")
        assert.equals(1, #captured_messages)
        assert.is_not_nil(string.find(captured_messages[1], "DEBUG"))
        assert.is_not_nil(string.find(captured_messages[1], "test debug message"))
    end)

    it("should not log message when LOG_LEVEL is below LOG_DEBUG", function()
        log.LOG_LEVEL = log.LOG_INFO
        log.debug("test debug message")
        assert.equals(0, #captured_messages)
    end)

    it("should not log message when LOG_LEVEL is NO_LOG", function()
        log.LOG_LEVEL = log.NO_LOG
        log.debug("test debug message")
        assert.equals(0, #captured_messages)
    end)

    it("should include formatted timestamp in message", function()
        log.LOG_LEVEL = log.LOG_DEBUG
        _G.set_time(1.234)
        log.debug("hello")
        assert.is_not_nil(string.find(captured_messages[1], "1.234"))
    end)
end)

-- ============================================================
-- info()
-- ============================================================
describe("Log - info()", function()
    before_each(function()
        log = reload_log()
    end)

    it("should log message when LOG_LEVEL is LOG_INFO", function()
        log.LOG_LEVEL = log.LOG_INFO
        _G.set_time(2.500)
        log.info("test info message")
        assert.equals(1, #captured_messages)
        assert.is_not_nil(string.find(captured_messages[1], "INFO"))
        assert.is_not_nil(string.find(captured_messages[1], "test info message"))
    end)

    it("should log message when LOG_LEVEL is LOG_DEBUG", function()
        log.LOG_LEVEL = log.LOG_DEBUG
        log.info("test info message")
        assert.equals(1, #captured_messages)
        assert.is_not_nil(string.find(captured_messages[1], "INFO"))
    end)

    it("should not log message when LOG_LEVEL is LOG_WARNING", function()
        log.LOG_LEVEL = log.LOG_WARNING
        log.info("test info message")
        assert.equals(0, #captured_messages)
    end)

    it("should not log message when LOG_LEVEL is NO_LOG", function()
        log.LOG_LEVEL = log.NO_LOG
        log.info("test info message")
        assert.equals(0, #captured_messages)
    end)
end)

-- ============================================================
-- warning()
-- ============================================================
describe("Log - warning()", function()
    before_each(function()
        log = reload_log()
    end)

    it("should log message when LOG_LEVEL is LOG_WARNING", function()
        log.LOG_LEVEL = log.LOG_WARNING
        _G.set_time(3.000)
        log.warning("test warning message")
        assert.equals(1, #captured_messages)
        assert.is_not_nil(string.find(captured_messages[1], "WARN"))
        assert.is_not_nil(string.find(captured_messages[1], "test warning message"))
    end)

    it("should log message when LOG_LEVEL is LOG_INFO", function()
        log.LOG_LEVEL = log.LOG_INFO
        log.warning("test warning message")
        assert.equals(1, #captured_messages)
        assert.is_not_nil(string.find(captured_messages[1], "WARN"))
    end)

    it("should not log message when LOG_LEVEL is LOG_ERROR", function()
        log.LOG_LEVEL = log.LOG_ERROR
        log.warning("test warning message")
        assert.equals(0, #captured_messages)
    end)

    it("should not log message when LOG_LEVEL is NO_LOG", function()
        log.LOG_LEVEL = log.NO_LOG
        log.warning("test warning message")
        assert.equals(0, #captured_messages)
    end)
end)

-- ============================================================
-- error()
-- ============================================================
describe("Log - error()", function()
    before_each(function()
        log = reload_log()
    end)

    it("should log message when LOG_LEVEL is LOG_ERROR", function()
        log.LOG_LEVEL = log.LOG_ERROR
        _G.set_time(4.567)
        log.error("test error message")
        assert.equals(1, #captured_messages)
        assert.is_not_nil(string.find(captured_messages[1], "ERROR"))
        assert.is_not_nil(string.find(captured_messages[1], "test error message"))
    end)

    it("should log message when LOG_LEVEL is LOG_WARNING", function()
        log.LOG_LEVEL = log.LOG_WARNING
        log.error("test error message")
        assert.equals(1, #captured_messages)
        assert.is_not_nil(string.find(captured_messages[1], "ERROR"))
    end)

    it("should not log message when LOG_LEVEL is NO_LOG", function()
        log.LOG_LEVEL = log.NO_LOG
        log.error("test error message")
        assert.equals(0, #captured_messages)
    end)
end)

-- ============================================================
-- Message Format
-- ============================================================
describe("Log - Message Format", function()
    before_each(function()
        log = reload_log()
    end)

    it("should include BRAVO++ prefix", function()
        log.LOG_LEVEL = log.LOG_DEBUG
        _G.set_time(0.000)
        log.debug("test")
        assert.is_not_nil(string.find(captured_messages[1], "BRAVO++"))
    end)

    it("should format timestamp with 3 decimal places", function()
        log.LOG_LEVEL = log.LOG_DEBUG
        _G.set_time(1.234)
        log.debug("test")
        -- Format: "1.234 [BRAVO++ DEBUG]: test"
        assert.is_not_nil(string.find(captured_messages[1], "^1%.234 "))
    end)

    it("should use correct format for all levels", function()
        log.LOG_LEVEL = log.LOG_DEBUG
        _G.set_time(10.000)

        log.debug("d")
        log.info("i")
        log.warning("w")
        log.error("e")

        assert.equals(4, #captured_messages)
        assert.is_not_nil(string.find(captured_messages[1], "DEBUG"))
        assert.is_not_nil(string.find(captured_messages[2], "INFO"))
        assert.is_not_nil(string.find(captured_messages[3], "WARN"))
        assert.is_not_nil(string.find(captured_messages[4], "ERROR"))
    end)
end)

-- ============================================================
-- Severity Filtering
-- ============================================================
describe("Log - Severity Filtering", function()
    before_each(function()
        log = reload_log()
    end)

    it("should only log ERROR at LOG_ERROR level", function()
        log.LOG_LEVEL = log.LOG_ERROR
        log.debug("debug")
        log.info("info")
        log.warning("warning")
        log.error("error")
        assert.equals(1, #captured_messages)
        assert.is_not_nil(string.find(captured_messages[1], "ERROR"))
    end)

    it("should log WARNING and above at LOG_WARNING level", function()
        log.LOG_LEVEL = log.LOG_WARNING
        log.debug("debug")
        log.info("info")
        log.warning("warning")
        log.error("error")
        assert.equals(2, #captured_messages)
    end)

    it("should log INFO and above at LOG_INFO level", function()
        log.LOG_LEVEL = log.LOG_INFO
        log.debug("debug")
        log.info("info")
        log.warning("warning")
        log.error("error")
        assert.equals(3, #captured_messages)
    end)

    it("should log all levels at LOG_DEBUG level", function()
        log.LOG_LEVEL = log.LOG_DEBUG
        log.debug("debug")
        log.info("info")
        log.warning("warning")
        log.error("error")
        assert.equals(4, #captured_messages)
    end)

    it("should log nothing at NO_LOG level", function()
        log.LOG_LEVEL = log.NO_LOG
        log.debug("debug")
        log.info("info")
        log.warning("warning")
        log.error("error")
        assert.equals(0, #captured_messages)
    end)
end)
