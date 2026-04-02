local log = require("bravo++.log")
local debug = require("bravo++.debug")
local state = require("bravo++.state")

local M = {}
local handlers = {}
local last_report = nil
local counters = { selector_changes = 0, rotary_events = 0, trim_events = 0 }

function M.set_handlers(tbl)
  handlers = tbl or {}
end

-- Placeholder decode helpers. These should be updated once mapping is known.
local function detect_selector_change(report)
  -- naive: compare a candidate byte index (12) to last_report
  local idx = 12
  if not report[idx] then return nil end
  local val = report[idx]
  if last_report and last_report[idx] and last_report[idx] ~= val then
    counters.selector_changes = counters.selector_changes + 1
    return val
  end
  return nil
end

local function detect_rotary_event(report)
  -- placeholder: look for changes in byte 14
  local idx = 14
  if not report[idx] then return nil end
  if last_report and last_report[idx] and last_report[idx] ~= report[idx] then
    counters.rotary_events = counters.rotary_events + 1
    -- very naive: if new > old treat as cw, else ccw
    if report[idx] > last_report[idx] then return "cw" else return "ccw" end
  end
  return nil
end

local function detect_trim_event(report)
  -- placeholder: look for changes in byte 13
  local idx = 13
  if not report[idx] then return nil end
  if last_report and last_report[idx] and last_report[idx] ~= report[idx] then
    counters.trim_events = counters.trim_events + 1
    return report[idx]
  end
  return nil
end

function M.on_report(report)
  debug.log_report_diff(report, last_report)

  local sel = detect_selector_change(report)
  if sel then
    state.set_selector(sel)
    if handlers.on_selector_changed then pcall(handlers.on_selector_changed, sel) end
  end

  local rot = detect_rotary_event(report)
  if rot then
    if rot == "cw" then
      if handlers.on_rotary_cw then pcall(handlers.on_rotary_cw) end
    else
      if handlers.on_rotary_ccw then pcall(handlers.on_rotary_ccw) end
    end
  end

  local tr = detect_trim_event(report)
  if tr then
    state.set_trim(tr)
    if handlers.on_trim_changed then pcall(handlers.on_trim_changed, tr) end
  end

  last_report = report
end

function M.diagnostics()
  return { counters = counters, last_report = last_report }
end

return M
