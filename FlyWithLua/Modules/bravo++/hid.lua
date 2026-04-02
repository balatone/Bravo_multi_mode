local log = require("bravo++.log")

local M = {}
local device = nil
local subscribers = {}
local next_sub_id = 1
local running = false
local diagnostics = { total_reports = 0, last_second = 0, reports_this_second = 0, max_drained_per_frame = 0, last_report = nil }
M.packet_size = 64

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
  for id, fn in pairs(subscribers) do
    local ok, err = pcall(fn, report)
    if not ok then log.error("hid: subscriber error: " .. tostring(err)) end
  end
end

local function read_one()
  -- Read one report from device or simulation queue
  if device then
    -- hid_read can return multiple values; gather into table
    local a = { hid_read(device, M.packet_size) }
    if not a or #a == 0 or a[1] == nil then return nil end
    return a
  else
    -- simulation mode: pop from queue
    if #simulate_queue == 0 then return nil end
    return table.remove(simulate_queue, 1)
  end
end

local function drain_once()
  local drained = 0
  while true do
    local report = read_one()
    if not report then break end
    drained = drained + 1
    diagnostics.total_reports = diagnostics.total_reports + 1
    diagnostics.reports_this_second = diagnostics.reports_this_second + 1
    diagnostics.last_report = report
    dispatch_report(report)
  end
  if drained > diagnostics.max_drained_per_frame then diagnostics.max_drained_per_frame = drained end
  return drained
end

local function poll_task()
  if not running then return end
  drain_once()
end

function M.start()
  if running then return end
  running = true
  _G.bravo_hid_poll_task = function() pcall(poll_task) end
  -- register string callback for FlyWithLua
  do_every_frame("bravo_hid_poll_task")
end

function M.stop()
  running = false
  _G.bravo_hid_poll_task = nil
end

function M.diagnostics()
  return diagnostics
end

function M.simulate_report(report)
  -- push a report table (array of numbers) to the queue
  simulate_queue[#simulate_queue+1] = report
end

return M
