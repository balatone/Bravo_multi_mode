-- ************************************************
-- Unit tests for profiler module (FEAT-018)
-- ************************************************

local profiler = require("bravo++.profiler")

describe("profiler module", function()
    before_each(function()
        profiler.init({ enabled = false, log_interval = 60 })
    end)

    describe("init", function()
        it("should accept enabled and log_interval options", function()
            profiler.init({ enabled = true, log_interval = 30 })
            assert.is_true(profiler.is_enabled())
        end)

        it("should default to disabled when no options provided", function()
            profiler.init()
            assert.is_false(profiler.is_enabled())
        end)

        it("should default to disabled when enabled not specified", function()
            profiler.init({ log_interval = 30 })
            assert.is_false(profiler.is_enabled())
        end)
    end)

    describe("start/stop", function()
        it("should return nil when disabled", function()
            profiler.init({ enabled = false })
            local result = profiler.start("test_task")
            assert.is_nil(result)
        end)

        it("should return a timestamp when enabled", function()
            profiler.init({ enabled = true })
            local result = profiler.start("test_task")
            assert.is_not_nil(result)
            assert.is_number(result)
        end)

        it("should not error when stop called with nil start_time", function()
            profiler.init({ enabled = true })
            profiler.stop("test_task", nil) -- should not error
        end)

        it("should not error when stop called while disabled", function()
            profiler.init({ enabled = false })
            profiler.stop("test_task", os.clock()) -- should not error
        end)
    end)

    describe("toggle", function()
        it("should toggle enabled state", function()
            profiler.init({ enabled = false })
            local new_state = profiler.toggle()
            assert.is_true(new_state)
            assert.is_true(profiler.is_enabled())

            new_state = profiler.toggle()
            assert.is_false(new_state)
            assert.is_false(profiler.is_enabled())
        end)
    end)

    describe("log_task", function()
        it("should return false when disabled", function()
            profiler.init({ enabled = false })
            local result = profiler.log_task()
            assert.is_false(result)
        end)

        it("should return false when interval not reached", function()
            profiler.init({ enabled = true, log_interval = 60 })
            set_time(0)
            local result = profiler.log_task()
            assert.is_false(result)
        end)

        it("should return true when interval is reached", function()
            profiler.init({ enabled = true, log_interval = 10 })
            set_time(0)
            -- Advance past the log interval
            advance_time(11)
            local result = profiler.log_task()
            assert.is_true(result)
        end)
    end)

    describe("log_and_reset", function()
        it("should not error when called with no tasks", function()
            profiler.init({ enabled = true })
            profiler.log_and_reset() -- should not error
        end)
    end)
end)
