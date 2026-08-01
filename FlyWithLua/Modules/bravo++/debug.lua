local log = require("bravo++.log")
local M = {}
local enabled = false
local last_report = nil

local function hex(b)
	return string.format("%02X", b or 0)
end

function M.enable(v)
	enabled = v
end

function M.log_report(r)
	if not enabled then
		return
	end
	local s = {}
	for i = 1, #r do
		s[#s + 1] = hex(r[i])
	end
	log.debug("HID REPORT: " .. table.concat(s, " "))
end

function M.log_report_diff(r, last)
	if not enabled then
		return
	end
	last = last or last_report
	if not last then
		M.log_report(r)
		last_report = r
		return
	end
	local diffs = {}
	for i = 1, math.max(#r, #last) do
		if (r[i] or 0) ~= (last[i] or 0) then
			diffs[#diffs + 1] = string.format("%d:%s->%s", i, hex(last[i]), hex(r[i]))
		end
	end
	-- if #diffs>0 then log.debug("HID DIFF: " .. table.concat(diffs, ", ")) end
	if #diffs == 1 then
		log.debug("HID DIFF: " .. table.concat(diffs, ", "))
	end
	last_report = r
end

function M.dump_last_n(n)
	n = n or 10
	if not last_report then
		return
	end
	for i = 1, math.min(n, #last_report) do
		log.debug(string.format("LAST[%d]=%02X", i, last_report[i]))
	end
end

M._last_report = function()
	return last_report
end

return M
