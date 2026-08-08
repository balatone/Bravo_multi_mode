local log = require("bravo++.log")
local debug = require("bravo++.debug")
local state = require("bravo++.state")
local bit = require("bit")

local M = {}
local handlers = {}
local last_report = nil
local counters = { selector_changes = 0, rotary_events = 0, trim_events = 0 }

local function copy_report(src)
	if not src then
		return nil
	end
	local n = #src
	local dst = {}
	for i = 1, n do
		dst[i] = src[i]
	end
	return dst
end

-- Mapping constants (1-based byte indices)
local ROTARY_PULSE_BYTE = 15
local ROTARY_PULSE_CW_MASK = 0x10
local ROTARY_PULSE_CCW_MASK = 0x20
local SELECTOR_BYTE = 16
local SELECTOR_MASK = 0x1F -- lower 5 bits are one-hot for positions 1..5

-- Trim mapping: observed as toggles in SELECTOR_BYTE's bit 0x20
local TRIM_DOWN_MASK = 0x20
local TRIM_UP_MASK = 0x40 -- (may not be used on this device; placeholder)

-- Debounce / rate limiting
-- Detect Windows vs POSIX (package.config first char == directory separator)
local is_windows = (package.config and package.config:sub(1, 1) == "\\")
-- Windows tends to produce faster/denser HID report timing; prefer 0.05 there, 0.10 on others.
local DEFAULT_ROTARY_MIN_INTERVAL = is_windows and 0.015 or 0.030
local ROTARY_MIN_INTERVAL = DEFAULT_ROTARY_MIN_INTERVAL -- seconds between reported events for same knob
local SELECTOR_MIN_INTERVAL = DEFAULT_ROTARY_MIN_INTERVAL
-- Use a smaller trim interval by default so short trim pulses aren't suppressed
local DEFAULT_TRIM_MIN_INTERVAL = is_windows and 0.050 or 0.100
local TRIM_MIN_INTERVAL = DEFAULT_TRIM_MIN_INTERVAL
local DEFAULT_ROTARY_DEDUPE_WINDOW = is_windows and 0.030 or 0.080 -- seconds to dedupe same-direction duplicates
local ROTARY_DEDUPE_WINDOW = DEFAULT_ROTARY_DEDUPE_WINDOW -- seconds to dedupe same-direction duplicates
local last_rotary_time = 0
local last_selector_time = 0
local last_trim_time = 0
local last_rotary_dir = nil

-- Per-feature last-seen bytes to isolate detection from each other
local last_seen_rotary_byte = nil
local last_seen_selector_byte = nil

function M.set_handlers(tbl)
	handlers = tbl or {}
end

local function now()
	return os.clock()
end

local function find_position(n)
	if not n or n == 0 then
		return -1
	end
	local pos = 1
	local val = 1
	while bit.band(val, n) == 0 do
		val = bit.lshift(val, 1)
		pos = pos + 1
		if pos > 32 then
			return -1
		end
	end
	return pos
end

local function is_rising(prev, cur, mask)
	prev = prev or 0
	cur = cur or 0
	return (bit.band(prev, mask) == 0) and (bit.band(cur, mask) ~= 0)
end

-- Detect rotary event from explicit previous/current rotary byte values
local function detect_rotary_event_from_bytes(prev_byte, cur_byte)
	if not prev_byte then
		return nil
	end
	prev_byte = prev_byte or 0
	cur_byte = cur_byte or 0
	if is_rising(prev_byte, cur_byte, ROTARY_PULSE_CW_MASK) then
		return "cw"
	end
	if is_rising(prev_byte, cur_byte, ROTARY_PULSE_CCW_MASK) then
		return "ccw"
	end
	return nil
end

-- Detect selector change from explicit previous/current selector byte values
local function detect_selector_change_from_bytes(prev_byte, cur_byte)
	prev_byte = prev_byte or 0
	cur_byte = cur_byte or 0
	-- Wait for a rising non-zero one-hot value
	if prev_byte == 0 and cur_byte ~= 0 then
		-- ignore selector if trim bits are present in this pulse
		if bit.band(cur_byte, bit.bor(TRIM_DOWN_MASK, TRIM_UP_MASK)) ~= 0 then
			return nil
		end
		local masked = bit.band(cur_byte, SELECTOR_MASK)
		if masked == 0 then
			return nil
		end
		-- determine which bit is set (one-hot)
		local pos = find_position(masked)
		if pos < 0 then
			return nil
		end
		-- map bit position to selector index (hardware maps 0x10->pos5 -> index 1 etc.)
		local idx = 6 - pos
		return idx
	end
	return nil
end

-- Detect trim event from explicit previous/current selector byte values
local function detect_trim_event_from_bytes(prev_byte, cur_byte)
	prev_byte = prev_byte or 0
	cur_byte = cur_byte or 0
	-- Detect any change in the trim bits (XOR) to be resilient to sampling alignment
	local mask = bit.bor(TRIM_DOWN_MASK, TRIM_UP_MASK)
	local changed = bit.band(bit.bxor(prev_byte, cur_byte), mask)
	if changed == 0 then
		return nil
	end
	-- Prefer the current set bit as the direction when possible
	if bit.band(cur_byte, TRIM_DOWN_MASK) ~= 0 then
		return "down"
	end
	if bit.band(cur_byte, TRIM_UP_MASK) ~= 0 then
		return "up"
	end
	-- If neither bit is set in current (we observed a falling edge), fall back to previous state
	if bit.band(prev_byte, TRIM_DOWN_MASK) ~= 0 then
		return "down"
	end
	if bit.band(prev_byte, TRIM_UP_MASK) ~= 0 then
		return "up"
	end
	return nil
end

local currently_selected = 0

function M.on_report(report)
	-- Only log diffs when debug is enabled
	debug.log_report_diff(report, last_report)

	-- Rotary handling (use per-feature last_seen_rotary_byte)
	local cur_rot_byte = report[ROTARY_PULSE_BYTE] or 0
	local prev_rot_byte = last_seen_rotary_byte or 0
	local rot = detect_rotary_event_from_bytes(prev_rot_byte, cur_rot_byte)
	if rot then
		local t = now()
		if t - last_rotary_time >= ROTARY_MIN_INTERVAL then
			-- dedupe same-direction rapid duplicates
			if last_rotary_dir == rot and (t - last_rotary_time) < ROTARY_DEDUPE_WINDOW then
				log.debug("Decoder: rotary duplicate suppressed (same dir within dedupe window)")
			else
				last_rotary_time = t
				last_rotary_dir = rot
				counters.rotary_events = counters.rotary_events + 1
				if rot == "cw" then
					log.debug("Decoder: detected rotary CW event")
					if handlers.on_rotary_cw then
						pcall(handlers.on_rotary_cw)
					end
				else
					log.debug("Decoder: detected rotary CCW event")
					if handlers.on_rotary_ccw then
						pcall(handlers.on_rotary_ccw)
					end
				end
			end
		else
			log.debug("Decoder: rotary event suppressed by debounce")
		end
	end
	last_seen_rotary_byte = cur_rot_byte

	-- Selector & Trim handling (use per-feature last_seen_selector_byte)
	local cur_sel_byte = report[SELECTOR_BYTE] or 0
	local prev_sel_byte = last_seen_selector_byte or 0

	-- Selector handling
	local sel = detect_selector_change_from_bytes(prev_sel_byte, cur_sel_byte)
	if sel then
		local t = now()
		if currently_selected ~= sel then
			if t - last_selector_time >= SELECTOR_MIN_INTERVAL then
				currently_selected = sel
				last_selector_time = t
				counters.selector_changes = counters.selector_changes + 1
				log.debug("Decoder: selector changed => " .. tostring(sel))
				state.set_selector(sel)
				if handlers.on_selector_changed then
					pcall(handlers.on_selector_changed, sel)
				end
			else
				log.debug("Decoder: selector event suppressed by debounce")
			end
		end
	end

	-- Trim handling (edge detection + debounce)
	local tr = detect_trim_event_from_bytes(prev_sel_byte, cur_sel_byte)
	if tr then
		local t = now()
		if t - last_trim_time >= TRIM_MIN_INTERVAL then
			last_trim_time = t
			counters.trim_events = counters.trim_events + 1
			log.debug("Decoder: detected trim event => " .. tostring(tr))
			state.set_trim(tr)
			if handlers.on_trim_changed then
				pcall(handlers.on_trim_changed, tr)
			end
		else
			log.debug("Decoder: trim event suppressed by debounce")
		end
	end

	last_seen_selector_byte = cur_sel_byte

	-- Make a shallow copy of report so we don't retain the shared buffer
	last_report = copy_report(report)
end

function M.diagnostics()
	return {
		counters = counters,
		last_report = last_report,
		last_rotary_time = last_rotary_time,
		last_selector_time = last_selector_time,
		last_trim_time = last_trim_time,
		last_seen_rotary_byte = last_seen_rotary_byte,
		last_seen_selector_byte = last_seen_selector_byte,
	}
end

return M
