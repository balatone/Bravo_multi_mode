local log = require("bravo++.log")

local M = {}
local device = nil
local subscribers = {}
local next_sub_id = 1
local running = false
local diagnostics = { total_reports = 0, last_second = 0, reports_this_second = 0, max_drained_per_frame = 0, last_report = nil }
M.packet_size = 64

-- Poll limits to avoid blocking X-Plane
M.max_reports_per_poll = 16          -- maximum reports to drain in one poll() (conservative default)
M.max_poll_time_secs = 0.005         -- maximum seconds to spend in one poll (conservative: ~5ms)

-- Simulation hook (set by simulate mode)
local simulate_queue = nil

function M.init(opts)
  device = opts and opts.device_handle
  M.packet_size = (opts and opts.packet_size) or M.packet_size
  if not device and not opts.simulate then
    log.error("hid.init: no device provided")
    return false
  end
  if device then hid_set_nonblocking(device, 1) end
  simulate_queue = {}
  return true
end

function M.subscribe(fn)
  local id = next_sub_id
  subscribers[id] = fn
  next_sub_id = next_sub_id + 1
  return id
end

function M.unsubscribe(id)
  subscribers[id] = nil
end

local function dispatch_report(report)
  -- Performance: avoid pcall inside the hot path. Subscribers are trusted internal handlers.
  for id, fn in pairs(subscribers) do
    fn(report)
  end
end

local read_buffer = {}
local function read_one()
  -- Read one report from device or simulation queue
  if device then
    -- hid_read can return multiple values; gather into table
    -- Reuse a shared buffer to avoid allocating a new table on each read
    for i = #read_buffer, 1, -1 do read_buffer[i] = nil end
    local n = 0
    -- Collect multiple return values from hid_read()
    local function collect(...) n = select('#', ...); for i = 1, n do read_buffer[i] = select(i, ...) end end
    collect(hid_read(device, M.packet_size))
    if n == 0 or read_buffer[1] == nil then return nil end
    -- return a shallow copy reference to the buffer; callers should not hold it
    return read_buffer
  else
    -- simulation mode: pop from queue
    if #simulate_queue == 0 then return nil end
    return table.remove(simulate_queue, 1)
  end
end

local function drain_once()
  local drained = 0
  local start_time = os.clock()
  local iter = 0
  local time_check_every = 8 -- only check os.clock every N reports to reduce overhead
  while true do
    -- enforce limits to avoid blocking X-Plane
    if M.max_reports_per_poll and drained >= M.max_reports_per_poll then
      break
    end

    -- Check time budget only every time_check_every iterations
    if M.max_poll_time_secs and (iter % time_check_every) == 0 then
      if (os.clock() - start_time) >= M.max_poll_time_secs then
        break
      end
    end

    local report = read_one()
    if not report then break end
    drained = drained + 1
    iter = iter + 1
    diagnostics.total_reports = diagnostics.total_reports + 1
    diagnostics.reports_this_second = diagnostics.reports_this_second + 1
    diagnostics.last_report = report
    dispatch_report(report)
  end
  if drained > diagnostics.max_drained_per_frame then diagnostics.max_drained_per_frame = drained end
  return drained
end

local function poll_task()
  if not running then return 0 end
  return drain_once()
end

-- Expose a poll function so the host script can register it with bravo_dispatch.
function M.poll()
  local ok, drained = pcall(poll_task)
  if not ok then
    log.error('bravo_hid.poll: error calling poll_task: ' .. tostring(drained))
    return 0
  end
  diagnostics.poll_calls = (diagnostics.poll_calls or 0) + 1
  diagnostics.last_drained = drained or 0
  if diagnostics.last_drained and diagnostics.last_drained > 0 then
    log.debug('bravo_hid.poll: drained ' .. tostring(diagnostics.last_drained) .. ' report(s)')
  end
  return diagnostics.last_drained
end

function M.start()
  if running then return end
  running = true
  -- Don't register a do_every_frame callback here. The main script will register
  -- the poll function via bravo_dispatch to ensure it uses the same dispatch table and
  -- avoids FlyWithLua storage issues.
end

function M.stop()
  running = false
end

function M.diagnostics()
  return diagnostics
end

function M.simulate_report(report)
  -- push a report table (array of numbers) to the queue
  simulate_queue[#simulate_queue+1] = report
end

return M
