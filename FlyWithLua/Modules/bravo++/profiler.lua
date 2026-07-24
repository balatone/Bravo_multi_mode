-- ************************************************
-- Performance Profiler Module for Bravo++
-- ************************************************
-- Self-contained cumulative performance profiler with task tracking,
-- sorted logging every N seconds, and runtime toggle support.
-- Zero overhead when disabled.
--
-- Extracted from BravoMultiMode.lua (FEAT-018, Phase 2).
-- Dependencies: log (for output); zero dependencies on other bravo++ modules.
-- ************************************************

local log = require("bravo++.log")

local M = {}

-- Internal state (encapsulated, never exposed as globals)
local _enabled = false
local _log_interval = 60
local _tasks = {}
local _last_log_time = os.clock()

--- Initialize the profiler with configuration options.
--- @param opts table  Configuration options
---   - enabled: boolean (default false)
---   - log_interval: integer seconds (default 60)
function M.init(opts)
    if not opts then
        return
    end
    if type(opts.enabled) == "boolean" then
        _enabled = opts.enabled
    end
    if type(opts.log_interval) == "number" and opts.log_interval > 0 then
        _log_interval = opts.log_interval
    end
    _tasks = {}
    _last_log_time = os.clock()
end

--- Start timing a specific task.
--- @param task_name string  Name of the task to time
--- @return number|nil  Start timestamp (nil if disabled)
function M.start(task_name)
    if not _enabled then
        return nil
    end
    if not _tasks[task_name] then
        _tasks[task_name] = { total_time = 0, calls = 0 }
    end
    return os.clock()
end

--- Stop timing and record the delta for the task.
--- @param task_name string  Name of the task
--- @param start_time number|nil  Start timestamp from M.start()
function M.stop(task_name, start_time)
    if not _enabled or not start_time then
        return
    end
    if _tasks[task_name] then
        local delta = os.clock() - start_time
        _tasks[task_name].total_time = _tasks[task_name].total_time + delta
        _tasks[task_name].calls = _tasks[task_name].calls + 1
    end
end

--- Log all accumulated stats and reset the counters.
function M.log_and_reset()
    log.info("======================================================")
    log.info("BRAVO++ PERFORMANCE PROFILER (Last " .. _log_interval .. "s)")
    log.info("------------------------------------------------------")

    -- Sort tasks by total time descending for easier analysis
    local sorted_tasks = {}
    for name, stats in pairs(_tasks) do
        table.insert(sorted_tasks, { name = name, stats = stats })
    end
    table.sort(sorted_tasks, function(a, b)
        return a.stats.total_time > b.stats.total_time
    end)

    for _, entry in ipairs(sorted_tasks) do
        local name = entry.name
        local stats = entry.stats
        local avg = (stats.calls > 0) and (stats.total_time / stats.calls) or 0
        log.info(
            string.format(
                "Task: %-30s | Calls: %5d | Total: %.4fs | Avg: %.6fs",
                name,
                stats.calls,
                stats.total_time,
                avg
            )
        )
    end

    log.info("======================================================")

    -- Reset for next interval
    _tasks = {}
end

--- Periodic logging task (called every frame via FlyWithLua string callback).
--- Logs accumulated stats at the configured interval and resets counters.
--- Returns true if a log was performed, false otherwise.
function M.log_task()
    if not _enabled then
        return false
    end
    local now = os.clock()
    if (now - _last_log_time) >= _log_interval then
        M.log_and_reset()
        _last_log_time = now
        return true
    end
    return false
end

--- Toggle profiling on/off at runtime.
--- @return boolean  New enabled state
function M.toggle()
    _enabled = not _enabled
    log.info("Profiling " .. (_enabled and "ENABLED" or "DISABLED"))
    return _enabled
end

--- Check if the profiler is currently enabled.
--- @return boolean  Current enabled state
function M.is_enabled()
    return _enabled
end

return M
