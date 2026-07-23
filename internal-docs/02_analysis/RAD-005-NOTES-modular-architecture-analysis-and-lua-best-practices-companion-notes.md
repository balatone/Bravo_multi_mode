---
id: RAD-005-NOTES
title: Modular Architecture Analysis and Lua Best Practices Companion Notes
version: 1.0.0
status: DRAFT
created: 2026-07-23 12:19:19
updated: 2026-07-23 12:28:00
related_docs: ["REQ-008", "RAD-005"]
---
# Companion Notes — RAD-005 Modular Architecture Analysis

This file contains detailed analysis data, raw evidence tables, and code snippets that support the main analysis report (RAD-005). Worker specialists should reference this for implementation details.

## A. Complete Module Dependency Matrix

### Import Dependencies (which modules require which)

| Source Module | Requires | Lines of Code |
|--------------|----------|---------------|
| `dispatch.lua` | log, dispatch_action_map, dispatch_buttons, dispatch_twist, dispatch_trim, dispatch_modes | 349 |
| `config.lua` | util, log, condition_compiler | 478 |
| `ui.lua` | util | 524 |
| `hardware.lua` | log | 258 |
| `decoder.lua` | log, debug, state, bit (LuaJIT) | 264 |
| `mapbuilder.lua` | util, log | 260 |
| `plugincheck.lua` | log | 183 |
| `dispatch_action_map.lua` | util, log | 214 |
| `dispatch_buttons.lua` | util, log | 201 |
| `dispatch_modes.lua` | util | 122 |
| `dispatch_trim.lua` | log | 77 |
| `dispatch_twist.lua` | log | 78 |
| `condition_compiler.lua` | (none) | 127 |
| `state.lua` | (none) | 67 |
| `debug.lua` | log | 62 |
| `log.lua` | (none) | 40 |
| `util.lua` | log | 169 |

### Top-Level Requires in BravoMultiMode.lua

```lua
local util = require("bravo++.util")
local log = require("bravo++.log")
local config = require("bravo++.config")
local ui = require("bravo++.ui")
local MapBuilder = require("bravo++.mapbuilder")
local plugincheck = require("bravo++.plugincheck")

local bravo_hid = require("bravo++.hardware")
local bravo_decoder = require("bravo++.decoder")
local bravo_state = require("bravo++.state")
local bravo_debug = require("bravo++.debug")
local dispatch = require("bravo++.dispatch")
```

## B. Line-by-Line LED Engine Breakdown (Lines 820–1460)

### Section 1: LED Constant Definitions (~lines 820–850)
- Defines `LED_LDG_*` constants for landing gear LEDs (3 channels × 2 colors = 6 constants)
- Defines `LED_ANC_*` constants for annunciator LEDs (row 1 + row 2 = 14 constants)
- **Assessment**: These are well-named, self-documenting constants. No changes needed.

### Section 2: Button LED State Functions (~lines 850–970)
- `get_button_led_state(button_name)` — reads from `button_map_leds_state` with two-level lookup (ALL or selection-specific)
- `set_button_led_state(button_name, state)` — writes to buffer, sets dirty flag
- **Issue**: Both functions access `dispatch.get_current_mode()` and `dispatch.get_current_selection()` directly, creating tight coupling. In a modularized version, these should be passed as parameters.

### Section 3: Buffer Management (~lines 970–1010)
- `buffer[]` — 4-bank × 8-bit LED state storage
- `get_led(led)` / `set_led(led, state)` — accessor functions with dirty-flag logic
- **Assessment**: Clean pattern. Could be extracted into its own module (`led_engine.lua`).

### Section 4: All LEDs Off + Prime Functions (~lines 1010–1120)
- `all_leds_off()` — resets all LED state to false across button, gear, annunciator, and switch banks
- `prime_button_led_states_for_mode_change()` — forces all button LEDs to a known state before evaluating new conditions
- **Issue**: These are called from mode change handlers but live in the LED engine block. They could be extracted into `led_engine.lua` as public API functions.

### Section 5: HID Report Assembly (~lines 1120–1160)
- `send_hid_data()` — converts buffer to bit-packed data, calls `hid_send_filled_feature_report`
- **Assessment**: Self-contained function with clear input/output. Ideal for extraction into `led_hid_bridge.lua`.

### Section 6: DataRef Condition Evaluation (~lines 1160–1270)
- `get_led_state_for_dataref(dr_table, cond, index)` — evaluates numeric datarefs against compiled conditions
- Handles both array and scalar datarefs with proper nil guards
- **Assessment**: Well-implemented. Could be extracted into a shared utility or remain in the LED engine as it's specifically for LED evaluation.

### Section 7: Switch/Annunciator/Gear LED Handlers (~lines 1270–1430)
- `handle_rocker_switch_led_changes()` — evaluates switch LEDs via dataref conditions
- `handle_button_led_changes()` — evaluates button LEDs via compiled conditions
- `handle_gear_led_changes()` — interprets gear position datarefs as LED states
- `get_led_state_for_annunciator(annunciator_label)` — evaluates annunciator LEDs
- Row 1 and Row 2 handler functions for annunciators

### Section 8: Main LED Update Loop (~lines 1430–1520)
- `handle_led_changes()` — orchestrates all LED evaluation, checks bus voltage, sends HID data if dirty
- `do_more_often(func, description, interval)` — periodic execution wrapper (called every 0.25s)
- First-sync delay logic (`leds_first_sync_done`, `led_first_time_delay = 4`)

## C. FlyWithLua Manual Cross-Reference Table

| FlyWithLua Feature | Bravo Multi Mode Usage | Compliance Assessment |
|-------------------|----------------------|---------------------|
| `do_every_frame(string)` | Used for profiler, selector refresh, HID poll, LED updates | ✅ Correct — all use short string callbacks that forward to local functions via bravo_dispatch |
| `create_command(name, desc, onBegin, onContinue, onEnd)` | Used extensively for button commands, mode cycling, trim/twist | ✅ Correct — callback strings follow the bravo_dispatch pattern |
| `do_on_exit(string)` | Used for LED cleanup and HID device close | ✅ Correct — single string callback that forwards to local function |
| `float_wnd_create(...)` + `float_wnd_set_imgui_builder` | Used for main floating window UI | ✅ Correct — imgui builder is a FlyWithLua global function |
| `dataref_table(refname)` | Used extensively for X-Plane datarefs | ⚠️ Partially correct — should always check nil before access; some hot paths lack guards |
| `hid_open(vid, pid)` | Used to open Bravo device (VID=0x294B PID=0x1901) | ✅ Correct — matches FlyWithLua HID API |
| `hid_send_filled_feature_report(handle, report_id, ...)` | Used for LED state updates | ✅ Correct — matches example script pattern exactly |
| String callbacks in global environment | bravo_dispatch forwarding pattern | ✅ Correct — minimal globals, everything else local |

## D. Lua 5.4 Manual Cross-Reference Table

| Lua 5.4 Feature | Bravo Multi Mode Usage | Compliance Assessment |
|----------------|----------------------|---------------------|
| `require()` module system | Used consistently across all bravo++ modules | ✅ Correct — proper use of local return tables |
| Local variable scoping | Predominantly used; some implicit globals in closures | ⚠️ Partially correct — forward declaration pattern is necessary but fragile |
| Metatables | Not used (FlyWithLua uses LuaJIT/Lua 5.1) | N/A — FlyWithLua runs on LuaJIT which has different metatable semantics |
| `pcall` / error handling | Used in try_catch wrapper throughout codebase | ✅ Correct — consistent pattern for graceful degradation |
| Varargs (`...`) scoping rules | Properly captured before closure in bravo_dispatch | ✅ Correct — matches the documented Lua varargs limitation |
| Garbage collection patterns | No explicit GC management (appropriate for FlyWithLua sandbox) | ✅ Acceptable — long-running simulation sessions don't require manual GC tuning |

## E. Code Snippets for Worker Specialists

### Recommended Module Export Pattern (for all new modules)

```lua
-- bravo++.my_new_module
local log = require("bravo++.log")

local M = {}

--- Initialize the module with required dependencies.
--- @param opts table  Configuration options
function M.init(opts)
    -- initialization logic
end

--- Public API function example.
--- @param param1 string  Description
--- @return boolean result  Whether operation succeeded
function M.public_function(param1)
    if not param1 then return false end
    -- implementation
    return true
end

return M
```

### Recommended LED Engine Module Structure (for Phase 1 refactoring)

```lua
-- bravo++.led_engine — Core LED state management and buffer operations
local log = require("bravo++.log")
local util = require("bravo++.util")

local M = {}

--- Initialize the LED engine with required bindings.
--- @param opts table  Configuration: {buffer_size, led_constants}
function M.init(opts)
    -- initialize buffer[], dirty flag, etc.
end

--- Set a single LED state and mark dirty if changed.
--- @param bank integer  Bank number (1-4)
--- @param bit integer   Bit position within bank (1-8)
--- @param state boolean New LED state
function M.set_led(bank, bit, state)
    -- implementation from current handle_led_changes()
end

--- Get the current LED state.
--- @param bank integer  Bank number
--- @param bit integer   Bit position
--- @return boolean|nil Current state or nil if not configured
function M.get_led(bank, bit)
    -- implementation from current get_led() function
end

--- Reset all LEDs to off state.
function M.all_off()
    -- implementation from current all_leds_off()
end

--- Mark the engine as needing an HID update.
--- @return boolean Whether any LED state has changed since last send
function M.is_dirty()
    return led_state_modified == true
end

--- Reset the dirty flag after successful HID send.
function M.clear_dirty()
    led_state_modified = false
end

return M
```

## F. Severity Classification Summary

| Issue | Severity | Module(s) Affected | Effort to Fix | Risk if Unfixed |
|-------|----------|-------------------|---------------|-----------------|
| LED engine monolithic block (~640 lines) | Critical | BravoMultiMode.lua | High (multiple modules needed) | Testing impossible; coupling prevents independent changes |
| _G.command_once bypassing try_catch | High | dispatch_twist.lua | Low (1 line change) | Silent failures in twist knob operations |
| Forward declaration fragility | High | BravoMultiMode.lua | Medium (redesign entrypoint pattern) | New global callbacks require two-location updates |
| Inconsistent export patterns | Medium | Multiple modules | Low (rename local tables to M) | Confusion for Worker specialists; inconsistent API surface |
| Missing nil guards in hot paths | Medium | BravoMultiMode.lua (LED handlers) | Low (add 2-3 nil checks each) | Potential runtime errors during config edge cases |
| Profiler embedded in main script | Low | BravoMultiMode.lua | Low (extract to separate file) | No functional impact; minor maintainability improvement |

## G. FlyWithLua Example Script References

The following example scripts from `Scripts (disabled)/` were consulted for pattern validation:

1. **hid_filled_feature_report_demo.lua** — LED buffer + HID report pattern matches BravoMultiMode exactly
2. **floating_wnd_demo.lua** — Floating window creation and imgui builder patterns match
3. **command_begin_example.lua** — Momentary button command registration pattern validated
4. **custom datarefs.lua** — Dataref access patterns for custom X-Plane datarefs
5. **DataRefAccessSpeed.lua** — Performance considerations for frequent dataref reads
