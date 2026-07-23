---
id: DSGN-001
title: Bravo++ Module Interface Specification
version: 1.0.0
status: APPROVED
created: 2026-07-23 19:08:00
updated: 2026-07-23 20:01:00
related_docs: ["FEAT-016", "RAD-005", "REQ-008"]
---

# Bravo++ Module Interface Specification

## Overview

This document defines the complete public API (exports) for all 11 target modules identified in FEAT-016. Each module follows the standard `local M = {} ... return M` export pattern as mandated by RAD-005 Finding 7 and Phase 4 requirements. All new modules receive their dependencies via injection parameters rather than accessing FlyWithLua globals directly — adhering to the "Injection Over Global Access" principle defined in FEAT-016. Performance constraints from `docs/lua-best-practices.md` are noted per-module and must be followed during implementation.

## Module Export Pattern (Standard)

Every module MUST conform to this structure:

```lua
local log = require("bravo++.log")
local util = require("bravo++.util")  -- if needed

local M = {}

--- Initialize the module with required dependencies.
--- @param opts table  Configuration options containing injected dependencies
function M.init(opts)
    -- initialization logic; store references in local closure variables
end

--- Public API function example.
--- @param param1 string  Description of parameter
--- @return boolean result  Return value description
function M.public_function(param1)
    if not param1 then return false end
    -- implementation using injected dependencies from init()
    return true
end

return M
```

---

## Module 1: `led_engine`

**Source**: BravoMultiMode.lua lines ~820–960, ~1430–1520 (buffer management + main update loop)
**Phase**: Phase 1 — LED Engine Split (CRITICAL)
**Dependencies**: `log`, `util`; injects: `dispatch` (for mode/selection queries and rocker switch LEDs), `button_map_leds_state`, `default_button_labels`

### Purpose
Core LED state management, buffer operations (`buffer[]`), dirty-flag tracking, and the main orchestration function that coordinates all sub-module LED evaluations.

### Public API

| Function | Parameters | Return Type | Side Effects |
|----------|-----------|-------------|--------------|
| `M.init(opts)` | `{ dispatch, button_map_leds_state, default_button_labels }` | `nil` | Initializes internal buffer (4 banks × 8 bits), sets dirty flag to false, stores injected references in closure scope. Must be called before any other function. |
| `M.set_led(bank, bit, state)` | `bank: integer`, `bit: integer`, `state: boolean` | `nil` | Writes LED state to buffer at `[bank][bit]`. Sets dirty flag (`led_state_modified = true`) if value changed from previous state. No return. |
| `M.get_led(bank, bit)` | `bank: integer`, `bit: integer` | `boolean\|nil` | Returns current LED state at `[bank][bit]`. Returns nil if bank/bit not yet initialized in buffer. |
| `M.all_off()` | *(none)* | `nil` | Resets all button LEDs to false via injected `button_map_leds_state`, clears banks 2–4 of buffer, sets all rocker switch LEDs (SWITCH1_LED through SWITCH7_LED) to false via injected dispatch. Sets dirty flag. Calls into injected dispatch for rocker switches: `dispatch.set_rocker_switch_led("SWITCH" .. i .. "_LED", false)` |
| `M.prime_for_mode_change()` | *(none)* | `nil` | Forces all button LED states in `button_map_leds_state[mode]["ALL"]` and `button_map_leds_state[mode][selection]` to false for every label in `default_button_labels`. Sets dirty flag. If no LEDs detected, falls back to `all_off()`. Used before mode/selector changes to ensure clean state evaluation. |
| `M.is_dirty()` | *(none)* | `boolean` | Returns current value of the internal dirty flag (`led_state_modified`). Read-only; does not modify state. |
| `M.clear_dirty()` | *(none)* | `nil` | Resets dirty flag to false after successful HID send. Used by `led_hid_bridge` post-send. |
| `M.handle_led_changes(opts)` | `{ bus_voltage: number, master_state_ref: table }` | `boolean` (whether any LEDs were updated) | **Main orchestration function.** Evaluates all LED sub-systems in order: button LEDs → gear LEDs → annunciator row 1 → annunciator row 2 → rocker switch LEDs. Checks bus voltage; if zero and previously powered, calls `all_off()`. Returns true if dirty flag was set during evaluation (indicating HID update needed). Calls into pre-registered sub-handler callbacks (set via `M.set_sub_handlers()` in composition root) using stored closure references. Uses `try_catch` wrapper for each sub-handler. Sub-handlers are NOT passed per-call — they are registered once at init time and invoked from closure scope. |
| `M.set_sub_handlers(sub_handlers_table)` | `{ on_annunciator_row1: function, on_annunciator_row2: function, on_gear: function, on_switches: function }` — each is a zero-arg callback that evaluates its sub-module and writes to led_engine buffer | `nil` | Stores the provided sub-handler callbacks in closure scope. These are invoked by `handle_led_changes()` during orchestration instead of being passed per-call via opts. Must be called after `M.init(opts)` but before any update loop iteration. Validates that all four callback keys are present; logs error if any key is missing. |
| `M.get_bus_voltage()` | *(none)* | `number\|nil` | Returns current bus voltage from injected dataref binding. Used by `handle_led_changes` to determine if LEDs should be powered. |

### Injection Points

| Dependency | Type | Source | Notes |
|-----------|------|--------|-------|
| `dispatch` | table (module) | Composition root | Required for: `get_current_mode()`, `get_current_selection()`, `set_rocker_switch_led(key, state)`, `get_rocker_switch_led(key)` |
| `button_map_leds_state` | table | Config loader / dispatch init | State storage for button LED on/off states per mode/selection. Read/write by engine. |
| `default_button_labels` | array of strings | Map builder | List of all physical button labels (e.g., "PLT", "IAS", "VS"). Used to iterate over buttons in `all_off()` and `prime_for_mode_change()`. |
| `bus_voltage_ref` | dataref magic table | Config loader bindings | X-Plane dataref for `sim/cockpit2/electrical/bus_volts`. Read-only. |

### Performance Constraints

> All performance guidance is sourced from `docs/lua-best-practices.md`. Modules MUST adhere to these constraints during implementation.

- **Hot Path**: This module's primary orchestration function (`handle_led_changes`) runs every 0.25s as part of the LED update loop. All sub-handler callbacks must be pre-registered via `set_sub_handlers()` and invoked from closure scope — no table allocation per call.
- **Pre-computation**: All dataref bindings and condition strings are compiled at init time by config_loader, avoiding runtime parsing overhead in hot paths.
- **Allocation Budget**: Each evaluation cycle should perform zero heap allocations beyond the dirty-flag boolean return value.

---

### Internal/Private Functions (NOT exported)

| Function | Purpose |
|----------|---------|
| `set_led_internal(bank, bit, state)` | Core buffer write with dirty-flag logic. Called by all public setters. |
| `get_led_internal(bank, bit)` | Core buffer read. Called by `M.get_led()`. |

---

## Module 2: `led_hid_bridge`

**Source**: BravoMultiMode.lua lines ~1350–1420 (HID report assembly + sending)
**Phase**: Phase 1 — LED Engine Split (CRITICAL)
**Dependencies**: `log`, `util`; injects: device handle, `bit` library reference

### Purpose
Converts the LED buffer into a bit-packed HID feature report and sends it to the Bravo device via FlyWithLua's `hid_send_filled_feature_report`. This module is responsible for bank-to-byte conversion across 4 banks (32 bits = 4 bytes).

### Public API

| Function | Parameters | Return Type | Side Effects |
|----------|-----------|-------------|--------------|
| `M.init(opts)` | `{ device_handle, bit_lib }` | `nil` | Stores injected device handle and bit library reference in closure scope. Validates that `device_handle` is a valid HID handle (non-nil). Logs error if invalid. |
| `M.assemble_and_send(buffer_ref, default_button_labels, dispatch_module)` | `buffer_ref: table`, `default_button_labels: array`, `dispatch_module: table` | `boolean` (success) | **Core function.** Reads LED buffer and button state to build 4-byte report. Bank 1 bytes come from button states via bit manipulation; banks 2–4 come directly from buffer. Calls `hid_send_filled_feature_report(device_handle, 0, 65, byte1, byte2, byte3, byte4)`. On success (bytes_written == 65), calls `dispatch_module.clear_dirty()` on the led_engine module. Logs errors for partial or failed writes. |
| `M.assemble_report(buffer_ref, default_button_labels, dispatch_module)` | Same as above but returns data only | `{ integer }` array of 4 integers (bytes) | Builds report bytes without sending. Used for testing and debug logging. Returns nil on invalid input. |

### Injection Points

| Dependency | Type | Source | Notes |
|-----------|------|--------|-------|
| `device_handle` | number (HID handle) | Composition root (`hid_open(0x294B, 0x1901)`) | Injected at init; stored in closure. Used by `hid_send_filled_feature_report`. |
| `bit_lib` | table | LuaJIT's built-in `bit` library | Passed as parameter to avoid global dependency. Provides `bor`, `lshift`. |

### Performance Constraints

> All performance guidance is sourced from `docs/lua-best-practices.md`. Modules MUST adhere to these constraints during implementation.

- **Hot Path**: This module's primary evaluation function runs every 0.25s as part of the LED update loop (or equivalent periodic interval). Sub-handler callbacks invoked by this module must NOT allocate new tables per invocation — reuse pre-allocated buffers where possible.
- **Pre-computation**: All dataref bindings and condition strings are compiled at init time by config_loader, avoiding runtime parsing overhead in hot paths.
- **Allocation Budget**: Each evaluation cycle should perform zero heap allocations beyond the dirty-flag boolean return value.

---

### Internal/Private Functions (NOT exported)

| Function | Purpose |
|----------|---------|
| `button_to_byte(button_labels, dispatch_module)` | Converts button LED states into bank-1 byte via bit.lshift and bit.bor across all buttons. |

---

## Module 3: `annunciator_leds`

**Source**: BravoMultiMode.lua lines ~960–1180 (Row 1 + Row 2 annunciator evaluation)
**Phase**: Phase 1 — LED Engine Split (CRITICAL)
**Dependencies**: injects compiled conditions; no direct dataref access

### Purpose
Evaluates 14 annunciator LEDs across two rows based on pre-compiled dataref conditions. Receives all bindings from the config loader rather than accessing globals directly.

### Public API

| Function | Parameters | Return Type | Side Effects |
|----------|-----------|-------------|--------------|
| `M.init(opts)` | `{ annunciator_bindings: table }` | `nil` | Stores injected binding data in closure scope. Expects format: `{ label = { dataref_table, condition_string }, ... }`. Validates that all entries contain valid dataref magic tables and non-empty conditions. |
| `M.evaluate_row1(led_engine_module)` | `led_engine_module: table` (with `set_led`) | `nil` | Evaluates 7 Row 1 annunciators: MASTER_WARNING, FIRE_WARNING, OIL_LOW_PRESSURE, FUEL_LOW_PRESSURE, ANTI_ICE, STARTER_ENGAGED, APU. For each, calls the internal dataref evaluator with compiled condition and writes result to LED buffer via `led_engine_module.set_led()`. Sets dirty flag implicitly through led_engine. |
| `M.evaluate_row2(led_engine_module)` | `led_engine_module: table` (with `set_led`) | `nil` | Evaluates 7 Row 2 annunciators: MASTER_CAUTION, VACUUM, HYD_LOW_PRESSURE, AUX_FUEL_PUMP, PARKING_BRAKE, VOLTS_LOW, DOOR. Same pattern as row1 — evaluates and writes to buffer via led_engine.set_led(). |
| `M.evaluate_all(led_engine_module)` | `led_engine_module: table` (with `set_led`) | `nil` | Convenience wrapper that calls both evaluate_row1 and evaluate_row2 in sequence. Used by the main LED update loop. |

### Injection Points

| Dependency | Type | Source | Notes |
|-----------|------|--------|-------|
| `annunciator_bindings` | table of { dataref_table, condition_string } | Config loader (compiled) | Each entry maps an annunciator label to its X-Plane dataref and compiled condition string. Pre-compiled conditions avoid runtime parsing overhead in hot path. |
| `led_engine_module.set_led` | function reference | led_engine module injected at init time | Used to write evaluated states into the shared buffer. The actual dirty-flag logic lives in led_engine, keeping this module focused on evaluation only. |
| eval_fn (NEW) | function `(dataref_table, condition_string, index?) → boolean` | Composition root — passed from config_loader after loading config.lua | Evaluator function for comparing dataref values against compiled conditions. Replaces direct `config.eval_condition()` global access. Must be non-nil at init time; reject nil with error log. |

### Performance Constraints

> All performance guidance is sourced from `docs/lua-best-practices.md`. Modules MUST adhere to these constraints during implementation.

- **Hot Path**: This module's primary evaluation function runs every 0.25s as part of the LED update loop (or equivalent periodic interval). Sub-handler callbacks invoked by this module must NOT allocate new tables per invocation — reuse pre-allocated buffers where possible.
- **Pre-computation**: All dataref bindings and condition strings are compiled at init time by config_loader, avoiding runtime parsing overhead in hot paths.
- **Allocation Budget**: Each evaluation cycle should perform zero heap allocations beyond the dirty-flag boolean return value.

---

### Internal/Private Functions (NOT exported)

| Function | Purpose |
|----------|---------|
| `evaluate_single_annunciator(label)` | Evaluates a single annunciator's dataref against its compiled condition. Returns boolean. Handles both scalar and array datarefs with proper nil guards. Uses injected `eval_fn` for comparison (NOT direct config global access). |

---

## Module 4: `gear_leds`

**Source**: BravoMultiMode.lua lines ~1180–1270 (3-channel green/red state machine)
**Phase**: Phase 1 — LED Engine Split (CRITICAL)
**Dependencies**: injects gear dataref binding; no direct X-Plane access

### Purpose
Interprets landing gear position datarefs as a 3-channel green/red LED state machine. Each channel produces one green and one red LED based on: deployed=green, stowed=both off, moving=red.

### Public API

| Function | Parameters | Return Type | Side Effects |
|----------|-----------|-------------|--------------|
| `M.init(opts)` | `{ gear_dataref, led_constants }` | `nil` | Stores injected gear dataref and LED position constants in closure scope. Validates that `gear_dataref` is a valid table (dataref magic table or nil for fixed-gear). |
| `M.evaluate(led_engine_module)` | `led_engine_module: table` (with `set_led`) | `nil` | **Core evaluation function.** Reads gear dataref values at indices 0, 1, 2. For each channel: interprets value (0=stowed, 1=deployed, other=moving), maps to green/red states, calls `led_engine_module.set_led()` for the corresponding LED_LDG_* constants. Handles nil/missing gear dataref by treating all channels as fixed-gear (all off). |
| `M.get_gear_state()` | *(none)* | `{ {green, red}, ... }` array of 3 pairs | Returns current interpreted gear state without writing to buffer. Useful for UI display and debugging. Returns nil if not initialized. |

### Injection Points

| Dependency | Type | Source | Notes |
|-----------|------|--------|-------|
| `gear_dataref` | dataref magic table or nil | Config loader (`nav_bindings["GEAR_DEPLOYMENT_LED"]`) | X-Plane dataref for gear position. May be nil if aircraft has fixed gear and no binding configured. |
| `led_constants` | table of {bank, bit} pairs | Composition root (from BravoMultiMode.lua constants) | Maps LED names to buffer positions: `{ LED_LDG_N_GREEN={2,3}, LED_LDG_N_RED={2,4}, ... }`. Injected so this module doesn't need to define its own constants. |
| `led_engine_module.set_led` | function reference | led_engine module | Used to write evaluated gear states into the shared buffer. |

### Performance Constraints

> All performance guidance is sourced from `docs/lua-best-practices.md`. Modules MUST adhere to these constraints during implementation.

- **Hot Path**: This module's primary evaluation function runs every 0.25s as part of the LED update loop (or equivalent periodic interval). Sub-handler callbacks invoked by this module must NOT allocate new tables per invocation — reuse pre-allocated buffers where possible.
- **Pre-computation**: All dataref bindings and condition strings are compiled at init time by config_loader, avoiding runtime parsing overhead in hot paths.
- **Allocation Budget**: Each evaluation cycle should perform zero heap allocations beyond the dirty-flag boolean return value.

---

### Internal/Private Functions (NOT exported)

| Function | Purpose |
|----------|---------|
| `interpret_channel(value)` | Maps a single gear channel value to {green, red} boolean pair. 0→{false,false}, 1→{true,false}, else→{false,true}. |

---

## Module 5: `switch_leds`

**Source**: BravoMultiMode.lua lines ~1270–1350 (rocker switch LED per-switch condition evaluation)
**Phase**: Phase 1 — LED Engine Split (CRITICAL)
**Dependencies**: injects switch LED bindings; no direct dataref access

### Purpose
Evaluates 7 rocker switch LEDs based on pre-compiled dataref conditions. Each switch has a dataref binding and condition string that determines whether the corresponding LED should be lit.

### Public API

| Function | Parameters | Return Type | Side Effects |
|----------|-----------|-------------|--------------|
| `M.init(opts)` | `{ switch_bindings: table, dispatch_module: table }` | `nil` | Stores injected switch bindings and dispatch module reference in closure scope. Expects format: `{ "SWITCH1_LED" = { dataref_table, condition_string, optional_index }, ... }`. Validates all entries have valid dataref magic tables. |
| `M.evaluate(led_engine_module)` | `led_engine_module: table` (with `set_led`) | `nil` | **Core evaluation function.** Iterates SWITCH1_LED through SWITCH7_LED. For each with a configured binding, evaluates the dataref against its compiled condition using `get_led_state_for_dataref()`. If state differs from current dispatch rocker switch LED state, updates via `dispatch.set_rocker_switch_led()` and calls `led_engine_module.set_led()` for the corresponding buffer position. Sets dirty flag through led_engine. |
| `M.get_current_states()` | *(none)* | `{ string → boolean }` map | Returns current rocker switch LED states from dispatch module without re-evaluating. Useful for UI display. |

### Injection Points

| Dependency | Type | Source | Notes |
|-----------|------|--------|-------|
| `switch_bindings` | table of { dataref_table, condition_string, optional_index } | Config loader (`nav_bindings["SWITCH" .. i .. "_LED"]`) | Pre-compiled bindings for all 7 rocker switches. Each entry may include an optional array index (3rd element). |
| `dispatch_module` | table (module) | dispatch.lua module injected at init time | Required for: `get_rocker_switch_led(key)` to read current state, `set_rocker_switch_led(key, state)` to update it. |
| eval_fn (NEW) | function `(dataref_table, condition_string, index?) → boolean` | Composition root — passed from config_loader after loading config.lua | Evaluator function for comparing dataref values against compiled conditions. Replaces direct `config.eval_condition()` global access. Must be non-nil at init time; reject nil with error log. |
| `led_engine_module.set_led` | function reference | led_engine module | Used to write evaluated switch states into the shared buffer. |

### Performance Constraints

> All performance guidance is sourced from `docs/lua-best-practices.md`. Modules MUST adhere to these constraints during implementation.

- **Hot Path**: This module's primary evaluation function runs every 0.25s as part of the LED update loop (or equivalent periodic interval). Sub-handler callbacks invoked by this module must NOT allocate new tables per invocation — reuse pre-allocated buffers where possible.
- **Pre-computation**: All dataref bindings and condition strings are compiled at init time by config_loader, avoiding runtime parsing overhead in hot paths.
- **Allocation Budget**: Each evaluation cycle should perform zero heap allocations beyond the dirty-flag boolean return value.

---

### Internal/Private Functions (NOT exported)

| Function | Purpose |
|----------|---------|
| `evaluate_switch(switch_label, binding)` | Evaluates a single switch's dataref against its compiled condition. Handles nil guards on dataref access. Returns boolean state. Uses injected `eval_fn` for comparison (NOT direct config global access). |

---

## Shared Utility Functions

The following function is extracted from BravoMultiMode.lua (line ~1187) and provided as an injected utility to modules that need dataref state evaluation:

### `get_led_state_for_dataref(dataref, condition_string, index?)`

| Property | Value |
|----------|-------|
| **Provider** | config_loader module or a dedicated `condition_compiler` utility (to be determined during implementation) |
| **Consumers** | annunciator_leds (`evaluate_single_annunciator`), switch_leds (`evaluate_switch`) |
| **Injection Method** | Passed as `eval_fn` parameter to consuming modules at init time (see C1 fix above) |
| **Purpose** | Reads the current value from a dataref magic table, applies an optional array index, and evaluates it against a compiled condition string. Returns boolean LED state. Includes nil guards for all dataref access paths. |

> **Implementation Note**: During implementation, decide whether this function lives in config_loader (as a shared utility) or is provided directly by the composition root from the original BravoMultiMode.lua logic. The injection parameter name `eval_fn` abstracts away the source — consuming modules only need to call it as a function with `(dataref_table, condition_string, index?)` arguments.

---

## Module 6: `profiler`

**Source**: BravoMultiMode.lua lines ~10–130 (performance profiler)
**Phase**: Phase 2 — High Priority Extraction
**Dependencies**: `log`; zero dependencies on other modules

### Purpose
Self-contained cumulative performance profiler with task tracking, sorted logging every N seconds, and runtime toggle support. Zero overhead when disabled.

### Public API

| Function | Parameters | Return Type | Side Effects |
|----------|-----------|-------------|--------------|
| `M.init(opts)` | `{ enabled: boolean, log_interval: integer }` | `nil` | Initializes profiler state. `enabled=false` by default (zero overhead). `log_interval` defaults to 60 seconds. Stores all config in closure scope. |
| `M.start(task_name)` | `task_name: string` | `number\|nil` (start timestamp) | Records start time using `os.clock()`. Returns nil if disabled. Creates task entry on first call for that name. |
| `M.stop(task_name, start_time)` | `task_name: string`, `start_time: number` | `nil` | Computes delta from start_time and accumulates into task's total_time + calls counter. No-op if disabled or start_time is nil. |
| `M.log_and_reset()` | *(none)* | `nil` | Sorts all tasks by total time descending, logs formatted stats via `log.info()`, resets `_tasks` table to empty. Logs header with interval duration. |
| `M.toggle()` | *(none)* | `boolean` (new enabled state) | Toggles profiler on/off. Returns new state. Logs status change. |
| `M.is_enabled()` | *(none)* | `boolean` | Returns current enabled state without side effects. |

### Performance Constraints

> All performance guidance is sourced from `docs/lua-best-practices.md`. Modules MUST adhere to these constraints during implementation.

- **Hot Path**: This module's primary evaluation function runs every 0.25s as part of the LED update loop (or equivalent periodic interval). Sub-handler callbacks invoked by this module must NOT allocate new tables per invocation — reuse pre-allocated buffers where possible.
- **Pre-computation**: All dataref bindings and condition strings are compiled at init time by config_loader, avoiding runtime parsing overhead in hot paths.
- **Allocation Budget**: Each evaluation cycle should perform zero heap allocations beyond the dirty-flag boolean return value.

---

### Injection Points

None. This module is fully self-contained with no external dependencies beyond `log`.

---

## Module 7: `config_loader`

**Source**: BravoMultiMode.lua lines ~230–380 (multi-step config detection + validation context building)
**Phase**: Phase 2 — High Priority Extraction
**Dependencies**: injects file system utilities; no direct X-Plane access

### Purpose
Handles multi-step configuration file detection (exact match → variant match → generic fallback), parses configuration files, builds validation contexts, and compiles dataref conditions. Self-contained with clear input/output boundaries.

### Public API

| Function | Parameters | Return Type | Side Effects |
|----------|-----------|-------------|--------------|
| `M.init(opts)` | `{ file_provider, aircraft_dir }` | `nil` | Stores injected file provider function and aircraft directory in closure scope. Validates that both are provided. |
| `M.detect_config(aircraft_name)` | `aircraft_name: string` | `{ path: string\|nil, found: boolean }` | Three-step detection: (1) exact match `bravo_multi-mode.<name>.cfg`, (2) variant match `bravo_multi-mode.<name>.*.cfg`, (3) generic fallback `bravo_multi-mode.cfg`. Uses injected file provider for existence checks and reads. Returns detected path or nil if none found. |
| `M.read_file(path, nav_bindings)` | `path: string`, `nav_bindings: table` | `boolean` (success) | Reads configuration file at given path into nav_bindings table. Returns true on success, false if file not found or parse error. Merges values into existing nav_bindings rather than replacing. |
| `M.read_preferences(path, nav_bindings)` | `path: string`, `nav_bindings: table` | `boolean` (success) | Same as read_file but for the optional global preferences file. Returns false gracefully if file doesn't exist (preferences are optional). |
| `M.compile_condition(condition_str, label)` | `condition_str: string`, `label: string` | `string\|nil` | Compiles a condition string (e.g., "<9", ">=10") into an evaluable form. Returns nil if condition is empty or malformed. Uses the config module's existing compile_condition logic. |
| `M.build_validation_context(nav_bindings)` | `nav_bindings: table` | `{ gear_dataref, switch_bindings, annunciator_bindings, button_bindings }` | Parses nav_bindings to extract structured data for all LED subsystems and other features. Returns a validation context table that can be injected into downstream modules. Handles nil/missing entries gracefully (returns empty tables or nil). |

### Injection Points

| Dependency | Type | Source | Notes |
|-----------|------|--------|-------|
| `file_provider` | function `(path) → boolean\|nil` | Composition root — wraps `util.list_files()` and file existence checks | Injected to decouple from filesystem access, enabling testing. Should return true if path exists. |

### Performance Constraints

> All performance guidance is sourced from `docs/lua-best-practices.md`. Modules MUST adhere to these constraints during implementation.

- **Hot Path**: This module's primary evaluation function runs every 0.25s as part of the LED update loop (or equivalent periodic interval). Sub-handler callbacks invoked by this module must NOT allocate new tables per invocation — reuse pre-allocated buffers where possible.
- **Pre-computation**: All dataref bindings and condition strings are compiled at init time by config_loader, avoiding runtime parsing overhead in hot paths.
- **Allocation Budget**: Each evaluation cycle should perform zero heap allocations beyond the dirty-flag boolean return value.

---

### Internal/Private Functions (NOT exported)

| Function | Purpose |
|----------|---------|
| `_variant_match(aircraft_name)` | Builds regex pattern for variant matching: `^bravo_multi%-mode%.<escaped_name>%.([^.]+)%.[cC][fF][gG]$`. Iterates directory listing to find matches. |

---

## Module 8: `rocker_switches`

**Source**: BravoMultiMode.lua lines ~560–620 (uniform command creation loop for 7 switches × UP/DOWN)
**Phase**: Phase 2 — High Priority Extraction
**Dependencies**: injects dispatch callback registration function; no direct FlyWithLua globals

### Purpose
Dynamically creates 14 X-Plane custom commands (7 rocker switches × UP/DOWN directions) using a uniform loop pattern. Each command routes through the bravo_dispatch entrypoint for error handling.

### Public API

| Function | Parameters | Return Type | Side Effects |
|----------|-----------|-------------|--------------|
| `M.init(opts)` | `{ dispatch_callback_fn, num_switches }` | `nil` | Stores injected callback registration function and switch count in closure scope. Validates that `dispatch_callback_fn` is a callable function. Defaults to 7 switches if not specified. |
| `M.register_all()` | *(none)* | `nil` | Creates all rocker switch commands using the uniform loop pattern. For each switch i (1–7): creates "FlyWithLua/Bravo++/rocker_switch{i}_up" and "FlyWithLua/Bravo++/rocker_switch{i}_down" commands, each calling `bravo_dispatch('rocker_switch', i, 'UP'/'DOWN')` via the injected dispatch callback function. Logs creation for debugging. |
| `M.get_command_name(switch_num, direction)` | `switch_num: integer`, `direction: string ("UP"\|"DOWN")` | `string` | Returns the X-Plane command name for a given switch and direction without creating it. Useful for testing and documentation. |

### Injection Points

| Dependency | Type | Source | Notes |
|-----------|------|--------|-------|
| `dispatch_callback_fn` | function `(name, ...)` → any | Composition root — wraps `bravo_dispatch` or dispatch module's callback registration | Used by create_command to register the string callback. Must accept a command name and varargs. |

### Performance Constraints

> All performance guidance is sourced from `docs/lua-best-practices.md`. Modules MUST adhere to these constraints during implementation.

- **Hot Path**: This module's primary evaluation function runs every 0.25s as part of the LED update loop (or equivalent periodic interval). Sub-handler callbacks invoked by this module must NOT allocate new tables per invocation — reuse pre-allocated buffers where possible.
- **Pre-computation**: All dataref bindings and condition strings are compiled at init time by config_loader, avoiding runtime parsing overhead in hot paths.
- **Allocation Budget**: Each evaluation cycle should perform zero heap allocations beyond the dirty-flag boolean return value.

---
> - Physical input debounce: Command registration should not create duplicate commands on re-initialization. Guard against multiple `create_command` calls for the same command name.

### Internal/Private Functions (NOT exported)

| Function | Purpose |
|----------|---------|
| `_create_switch_command(switch_num, direction)` | Creates a single rocker switch command with proper dataref path, description, and bravo_dispatch callback string. Called by register_all(). |

---

## Module 9: `button_lifecycle`

**Source**: BravoMultiMode.lua lines ~750–810 (AP button begin/continue/end lifecycle registration)
**Phase**: Phase 2 — High Priority Extraction
**Dependencies**: injects action map and command registry; no direct FlyWithLua globals

### Purpose
Manages the autopilot button lifecycle by registering begin/continue/end callbacks for each AP button. Each button gets three X-Plane commands that route through bravo_dispatch with error handling via try_catch.

### Public API

| Function | Parameters | Return Type | Side Effects |
|----------|-----------|-------------|--------------|
| `M.init(opts)` | `{ ap_buttons: array, dispatch_callback_fn }` | `nil` | Stores injected AP button definitions and dispatch callback function in closure scope. Validates that both are provided and non-empty. |
| `M.register_all()` | *(none)* | `nil` | Iterates through all AP buttons (e.g., PLT, IAS, VS, ALT, REV, APR, NAV, HDG) and creates three commands per button: begin, continue, end. Each command calls bravo_dispatch with the appropriate action ('ap_begin', 'ap_continue', 'ap_end') and button key. |
| `M.get_button_commands(button_key)` | `button_key: string` | `{ begin: string, continue: string, end: string }` map | Returns the three X-Plane command names for a given AP button without creating them. Useful for testing and documentation. |

### Injection Points

| Dependency | Type | Source | Notes |
|-----------|------|--------|-------|
| `ap_buttons` | array of `{ key, command, description }` | Map builder / config loader | Defines which buttons exist and their metadata. Each entry has a unique key (e.g., "PLT"), an X-Plane command name, and a human-readable description. |
| `dispatch_callback_fn` | function `(name, ...)` → any | Composition root — wraps bravo_dispatch | Used to register begin/continue/end callbacks that route through the dispatch system with try_catch error handling. |

### Performance Constraints

> All performance guidance is sourced from `docs/lua-best-practices.md`. Modules MUST adhere to these constraints during implementation.

- **Hot Path**: This module's primary evaluation function runs every 0.25s as part of the LED update loop (or equivalent periodic interval). Sub-handler callbacks invoked by this module must NOT allocate new tables per invocation — reuse pre-allocated buffers where possible.
- **Pre-computation**: All dataref bindings and condition strings are compiled at init time by config_loader, avoiding runtime parsing overhead in hot paths.
- **Allocation Budget**: Each evaluation cycle should perform zero heap allocations beyond the dirty-flag boolean return value.

---

> All command registrations are one-time operations during init(). No hot-path concerns for this module's primary function.
### Internal/Private Functions (NOT exported)

| Function | Purpose |
|----------|---------|
| `_register_button(button_entry)` | Creates all three lifecycle commands for a single AP button: begin, continue, end. Each wraps the bravo_dispatch call in a string that includes the button key as an argument. |

---

## Module 10: `input_handlers`

**Source**: BravoMultiMode.lua lines ~620–730 (trim wheel up/down + twist knob increase/decrease handlers)
**Phase**: Phase 3 — Medium Priority Extraction
**Dependencies**: injects dispatch module; resolves `_G.command_once` bypass

### Purpose
Consolidates trim wheel and twist knob input handling into a single focused module. Resolves the `_G.command_once` bypass anti-pattern identified in RAD-005 Finding 3 by wrapping all command invocations in try_catch or dispatch wrappers.

### Public API

| Function | Parameters | Return Type | Side Effects |
|----------|-----------|-------------|--------------|
| `M.init(opts)` | `{ dispatch_module, decoder_handler_fn }` | `nil` | Stores injected dispatch module and decoder handler function in closure scope. Validates that both are provided. |
| `M.handle_trim(v)` | `v: string ("up"\|"down")` | `nil` | Handles trim wheel direction changes. Routes to `dispatch.trim_nose_up()` or `dispatch.trim_nose_down()` via try_catch wrapper. Logs unknown values at debug level. |
| `M.handle_twist(dir)` | `dir: string ("increase"\|"decrease")` | `nil` | **Fixed version** — routes twist knob commands through the injected dispatch module (not direct `_G.command_once`). The dispatch module resolves trim/twist datarefs via injection rather than global access. All command invocations are wrapped in try_catch with error logging per RAD-005 Finding 3. This fully resolves the bypass anti-pattern by eliminating any direct _G reference. |
| `M.handle_decoder_event(event_type, value)` | `event_type: string`, `value: any` | `nil` | Generic decoder event handler that routes events to appropriate sub-handlers based on event type (trim_change, selector, rotary_encoder). Uses injected dispatch for mode-specific actions. |

### Injection Points

| Dependency | Type | Source | Notes |
|-----------|------|--------|-------|
| `dispatch_module` | table (module) | dispatch.lua module | Required for: `trim_nose_up()`, `trim_nose_down()`, and all twist knob command resolution. Provides the centralized error handling via try_catch. |
| trim_datarefs (NEW) | `{ up: dataref, down: dataref }` or function reference | Composition root — injected from config loader bindings | Trim wheel direction datarefs for direct access when dispatch module does not provide twist resolution. Used as fallback if dispatch_module.trim_nose_up/down are unavailable. Must be non-nil; reject nil with error log. |
| `decoder_handler_fn` | function `(event_type, value)` → any | Composition root — decoder's event routing callback | Used to wire up decoder pub/sub events to input handlers without circular dependency. |

### Performance Constraints

> All performance guidance is sourced from `docs/lua-best-practices.md`. Modules MUST adhere to these constraints during implementation.

- **Hot Path**: This module's primary evaluation function runs every 0.25s as part of the LED update loop (or equivalent periodic interval). Sub-handler callbacks invoked by this module must NOT allocate new tables per invocation — reuse pre-allocated buffers where possible.
- **Pre-computation**: All dataref bindings and condition strings are compiled at init time by config_loader, avoiding runtime parsing overhead in hot paths.
- **Allocation Budget**: Each evaluation cycle should perform zero heap allocations beyond the dirty-flag boolean return value.

---
> - Trim/twist handlers are triggered by physical rotary encoders which may generate rapid events. Consider debouncing at the decoder/pub-sub layer rather than in this module (the injected `decoder_handler_fn` should handle rate limiting).
### Internal/Private Functions (NOT exported)

| Function | Purpose |
|----------|---------|
| `_handle_twist_command(dataref_value)` | Routes twist knob command through dispatch module's priority resolution logic using injected trim datarefs (not globals). Wraps in try_catch with proper error logging per RAD-005 Finding 3. The original `_G.command_once` bypass is fully eliminated — all command execution flows through the injection layer or dispatch facade. |

---

## Module 11: `mode_manager`

**Source**: BravoMultiMode.lua lines ~410–560 (mode cycling, CF mode switching, switch mode cycling, conceptual grouping)
**Phase**: Phase 3 — Medium Priority Extraction
**Dependencies**: injects dispatch module and UI context builder; decouples from FlyWithLua globals

### Purpose
Manages all mode-related state transitions: mode cycling (up/down), CF (inner/outer) mode switching, switch mode cycling (up/down), conceptual mode grouping, and selector index management. Decouples the UI context building logic into a separate concern.

### Public API

| Function | Parameters | Return Type | Side Effects |
|----------|-----------|-------------|--------------|
| `M.init(opts)` | `{ dispatch_module, modes_array, selection_map_labels }` | `nil` | Stores injected mode definitions and dispatch module in closure scope. Initializes internal state: selector_index (starts at 1), conceptual_mode_order, mode_group_info. Validates that all required inputs are provided. |
| `M.cycle_mode_up()` | *(none)* | `nil` | Cycles current mode up through the modes array. Calls into dispatch for actual mode change, then triggers LED state priming and dirty flag update via injected led_engine reference (if provided). |
| `M.cycle_mode_down()` | *(none)* | `nil` | Cycles current mode down through the modes array. Same pattern as cycle_up but in reverse direction. |
| `M.cycle_cf_mode()` | *(none)* | `nil` | Toggles between "outer" and "inner" CF mode via dispatch module's `cycle_cf_mode()`. No LED state changes needed for this operation. |
| `M.cycle_switch_mode()` | *(none)* | `nil` | Toggles between "up" and "down" switch mode via dispatch module's `cycle_switch_mode()`. No LED state changes needed. |
| `M.activate_mode_select()` | *(none)* | `nil` | Activates mode selection overlay via dispatch module's `activate_mode_select()`. Used for momentary button press (toggle_mode_select). |
| `M.deactivate_mode_select()` | *(none)* | `nil` | Deactivates mode selection overlay. Paired with activate_mode_select for begin/end lifecycle. |
| `M.set_selector_index(idx, on_change_fn)` | `idx: integer`, `on_change_fn: function\|nil` | `nil` | Sets the local selector index and optionally triggers a callback when changed. The callback typically primes LED states and marks dirty flag. Used by refresh_selector_task from decoder state updates. |
| `M.build_ui_context()` | *(none)* | `table` | Builds the context table consumed by ui.lua's build_gui function. Returns current mode, selection, CF mode, switch mode, conceptual mode order, mode group info with current indices, button labels, and helper functions (get_button_led_state, get_rocker_switch_led). Decoupled from FlyWithLua globals — all data comes from injected dispatch module. |
| `M.get_current_mode()` | *(none)* | `string\|nil` | Returns the currently active mode name. Read-only accessor. |
| `M.get_current_selection()` | *(none)* | `string\|nil` | Returns the current selection within the active mode. Read-only accessor. |

### Injection Points

| Dependency | Type | Source | Notes |
|-----------|------|--------|-------|
| `dispatch_module` | table (module) | dispatch.lua module | Required for: all state queries and mutations (`get_current_mode`, `cycle_mode_up/down`, `cycle_cf_mode`, etc.). Also provides rocker switch LED access. |
| `modes_array` | array of strings | Map builder / config loader | Complete list of mode names in display order (e.g., "AUTO_1", "MANUAL_2"). Used for cycling logic and conceptual grouping. |
| `selection_map_labels` | table | Map builder | Maps modes to their available selections. Used by build_ui_context() for UI rendering. |

### Performance Constraints

> All performance guidance is sourced from `docs/lua-best-practices.md`. Modules MUST adhere to these constraints during implementation.

- **Hot Path**: This module's primary evaluation function runs every 0.25s as part of the LED update loop (or equivalent periodic interval). Sub-handler callbacks invoked by this module must NOT allocate new tables per invocation — reuse pre-allocated buffers where possible.
- **Pre-computation**: All dataref bindings and condition strings are compiled at init time by config_loader, avoiding runtime parsing overhead in hot paths.
- **Allocation Budget**: Each evaluation cycle should perform zero heap allocations beyond the dirty-flag boolean return value.

---
### Internal/Private Functions (NOT exported)

| Function | Purpose |
|----------|---------|
| `_build_conceptual_mode_order()` | Extracts unique conceptual names from modes array by stripping numeric suffixes (e.g., "AUTO" from "AUTO_1"). Maintains insertion order. Called during init(). |
| `_build_mode_group_info(conceptual_names)` | Maps each conceptual name to its count of concrete modes. Used for UI grouping display. Called during init(). |

---

## Cross-Module Data Flow Summary

```
Config Loader ──→ nav_bindings table
                    │
                    ├──→ Switch LEDs (switch_bindings)
                    ├──→ Annunciator LEDs (annunciator_bindings)
                    ├──→ Gear LEDs (gear_dataref)
                    └──→ Button LEDs (button_map_leds_state, button_map_leds, etc.)

Mode Manager ──→ dispatch_module.state (current_mode, current_selection)
                    │
                    └──→ LED Engine (triggers evaluation on mode change)

LED Engine ──→ orchestrates all sub-modules:
    ├── Button LEDs → via dispatch.get_current_mode()/get_current_selection()
    ├── Gear LEDs → via injected gear dataref
    ├── Annunciator Row 1/2 → via pre-compiled conditions
    ├── Switch LEDs → via dispatch rocker switch API
    └── HID Bridge → sends buffer to Bravo device

HID Bridge ←─ receives dirty flag from LED Engine
    │
    └──→ Bravo device (via injected handle)
```

## Verification Against RAD-005 Findings

| Finding | How This Spec Addresses It |
|---------|---------------------------|
| **Finding 1**: LED engine monolithic block [CRITICAL] | Split into 5 focused modules: led_engine, led_hid_bridge, annunciator_leds, gear_leds, switch_leds — each with single responsibility and explicit injection points. |
| **Finding 2**: Forward declaration fragility [HIGH] | All new modules use `M.init(opts)` pattern for dependency injection instead of forward-declared globals. No two-location updates needed. |
| **Finding 3**: `_G.command_once` bypass [HIGH] | input_handlers module wraps all command invocations in try_catch/pcall wrappers, resolving the safety net bypass. |
| **Finding 4**: Implicit global leakage [MEDIUM] | All module state is encapsulated in closure variables set during init(). No implicit globals shared across modules — dependencies are explicit injection parameters. |
| **Finding 5**: Missing nil guards in hot paths [MEDIUM] | All dataref access functions include defensive nil checks before evaluation. The `get_led_state_for_dataref` pattern from the original code is preserved and enhanced with additional guards. |
| **Finding 7**: Inconsistent export patterns [MEDIUM] | All 11 modules use the standard `local M = {} ... return M` pattern consistently. Public APIs are clearly documented in this specification table. |
