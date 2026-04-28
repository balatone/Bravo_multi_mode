-- bravo++.hardware -- HID device lifecycle and communication
--
-- Responsibilities:
--   • Initialise the physical HID handle (or run in injection-only mode).
--   • Budgeted polling loop that never blocks X-Plane.
--   • Subscription dispatch for decoded reports.
--   • Minimal data-injection capability for testing without hardware.
--
-- All hid_* calls are strictly internal to this module.

-- FlyWithLua globals, declared here to silence luacheck
local hid_read = hid_read --[[@as function]] -- luacheck: ignore (global from FlyWithLua)
local hid_set_nonblocking = hid_set_nonblocking --[[@as function]] -- luacheck: ignore (global from FlyWithLua)

local log = require("bravo++.log")

local M = {}

-- ---------------------------------------------------------------------------
-- Configuration (module-level, overridable by host)
-- ---------------------------------------------------------------------------
M.packet_size = 64
M.max_reports_per_poll = 16 -- hard cap on reports per poll() call
M.max_poll_time_secs = 0.005 -- ~5 ms time budget

-- ---------------------------------------------------------------------------
-- Internal state
-- ---------------------------------------------------------------------------
local device = nil -- raw HID handle (nil in injection-only mode)
local running = false

-- Subscriber registry: id -> callback
local subscribers = {}
local next_sub_id = 1

-- Injection queue (FIFO): used by inject_report() / simulate_report()
local inject_queue = {}

-- Pre-allocated buffer reused for every hid_read call (zero-allocation goal)
local read_buffer = {}

-- Diagnostics counters
local diagnostics = {
	total_reports = 0,
	poll_calls = 0,
	last_drained = 0,
	max_drained_per_frame = 0,
}

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

--- Initialise the hardware interface.
--- @param opts table  { device_handle?, packet_size?, simulate? }
--- @return boolean
function M.init(opts)
	opts = opts or {}
	device = opts.device_handle
	M.packet_size = opts.packet_size or M.packet_size

	if not device and not opts.simulate then
		log.error("hardware.init: no device provided and simulate mode disabled")
		return false
	end

	if device then
		hid_set_nonblocking(device, 1)
	end

	-- Reset internal state
	inject_queue = {}
	diagnostics.total_reports = 0
	diagnostics.poll_calls = 0
	diagnostics.last_drained = 0
	diagnostics.max_drained_per_frame = 0

	log.info(
		"hardware.init: packet_size="
			.. M.packet_size
			.. ", device="
			.. tostring(device)
			.. ", simulate="
			.. tostring(opts.simulate)
	)
	return true
end

--- Start the polling engine.
function M.start()
	if running then
		return
	end
	running = true
	log.info("hardware: polling started")
end

--- Stop the polling engine.
function M.stop()
	running = false
	log.info("hardware: polling stopped")
end

--- Register a callback that fires for every successfully read report.
--- @param fn function  receives (report_table)
--- @return integer id  pass to unsubscribe()
function M.subscribe(fn)
	local id = next_sub_id
	subscribers[id] = fn
	next_sub_id = next_sub_id + 1
	return id
end

--- Remove a previously registered subscriber.
--- @param id integer
function M.unsubscribe(id)
	subscribers[id] = nil
end

--- Push a report table into the internal injection queue.
--- The report will be dispatched on the next poll() cycle, *before* any
--- physical HID reads.  Callers may mutate the table after this call returns.
--- @param report number[]
function M.inject_report(report)
	-- Defensive copy so the caller can reuse their buffer safely
	local n = #report
	local copy = {}
	for i = 1, n do
		copy[i] = report[i]
	end
	inject_queue[#inject_queue + 1] = copy
end

--- Alias for backwards compatibility with hid.lua consumers.
M.simulate_report = M.inject_report

--- Primary execution hook — call once per frame from the host loop.
--- @return integer number of reports processed in this call
function M.poll()
	if not running then
		return 0
	end

	local ok, drained = pcall(M._poll_task)
	if not ok then
		log.error("hardware.poll: protected-call failed — " .. tostring(drained))
		diagnostics.last_drained = 0
		return 0
	end

	diagnostics.poll_calls = diagnostics.poll_calls + 1
	diagnostics.last_drained = drained or 0
	return diagnostics.last_drained
end

--- Return a snapshot of internal diagnostics.
--- @return table
function M.diagnostics()
	return {
		total_reports = diagnostics.total_reports,
		poll_calls = diagnostics.poll_calls,
		last_drained = diagnostics.last_drained,
		max_drained_per_frame = diagnostics.max_drained_per_frame,
	}
end

-- ---------------------------------------------------------------------------
-- Internal helpers
-- ---------------------------------------------------------------------------

--- Dispatch a single report to all subscribers.
--- Errors in one subscriber do NOT abort the others (pcall per subscriber).
local function dispatch_report(report)
	for _, fn in pairs(subscribers) do
		local ok, err = pcall(fn, report)
		if not ok then
			log.error("hardware: subscriber error — " .. tostring(err))
		end
	end
end

--- Read one report from the injection queue or the physical device.
--- @return table|nil
local function read_one()
	-- Priority 1: injection queue (testing / simulation)
	if #inject_queue > 0 then
		return table.remove(inject_queue, 1)
	end

	-- Priority 2: physical HID device
	if not device then
		return nil
	end

	-- Clear the reused buffer
	for i = #read_buffer, 1, -1 do
		read_buffer[i] = nil
	end

	local n = 0
	local function collect(...)
		n = select("#", ...)
		for i = 1, n do
			read_buffer[i] = select(i, ...)
		end
	end
	collect(hid_read(device, M.packet_size))

	if n == 0 or read_buffer[1] == nil then
		return nil
	end

	-- Return the buffer reference.  Callers MUST NOT store it beyond this
	-- poll cycle (it will be reused on the next call).
	return read_buffer
end

--- The actual polling loop wrapped by pcall in M.poll().
--- @return integer drained count
function M._poll_task()
	local drained = 0
	local start_time = os.clock()
	local iter = 0
	local time_check_every = 8 -- check clock every N iterations (overhead reduction)

	while true do
		-- Hard report cap
		if M.max_reports_per_poll and drained >= M.max_reports_per_poll then
			break
		end

		-- Time budget (checked sparingly)
		if M.max_poll_time_secs and iter > 0 and (iter % time_check_every) == 0 then
			if (os.clock() - start_time) >= M.max_poll_time_secs then
				break
			end
		end

		local report = read_one()
		if not report then
			break
		end

		drained = drained + 1
		iter = iter + 1
		diagnostics.total_reports = diagnostics.total_reports + 1

		dispatch_report(report)
	end

	if drained > diagnostics.max_drained_per_frame then
		diagnostics.max_drained_per_frame = drained
	end

	return drained
end

return M
