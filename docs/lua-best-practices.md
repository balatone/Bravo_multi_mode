# Lua Best Practices for Bravo Multi Mode

A curated reference guide tailored to the Bravo Multi Mode codebase (`FlyWithLua/Modules/bravo++`), synthesizing authoritative sources (Lua 5.4 Manual, MediaWiki Lua Best Practices, awesome-lua) with FlyWithLua execution model constraints and patterns observed in ~100+ example scripts.

---

## Table of Contents

1. [Module Organization](#module-organization)
2. [Scoping & Visibility](#scoping--visibility)
3. [Error Handling](#error-handling)
4. [LED/HID Communication](#ledhid-communication)
5. [DataRef Interaction](#dataref-interaction)
6. [Performance Considerations](#performance-considerations)
7. [Configuration Management](#configuration-management)

---

## Module Organization

### The `local M = {} ... return M` Export Pattern

The idiomatic Lua module pattern uses a local table as the public API surface, with all internal helpers kept truly private:

```lua
-- GOOD: Consistent export pattern (see hardware.lua, decoder.lua, state.lua)
local log = require("bravo++.log")
local M = {}

--- Initialise the hardware interface.
--- @param opts table  { device_handle?, packet_size?, simulate? }
--- @return boolean
function M.init(opts)
    -- implementation
end

-- Internal helper — not accessible outside this module
local function drain_queue() end

M.drain_queue = drain_queue  -- only expose what's needed
return M
```

**Why it matters in FlyWithLua:** FlyWithLua executes all scripts in a shared global environment. The `require()` mechanism provides the *only* isolation between modules. Without explicit export tables, every function becomes globally accessible — making refactoring dangerous and coupling implicit rather than documented.

### Single Responsibility Principle (SRP)

Each module should own exactly one concern. The ~640-line LED engine block in `BravoMultiMode.lua` (lines 820–1460) is the primary anti-pattern: it bundles six distinct responsibilities — button LEDs, gear LEDs, annunciator LEDs, rocker switch LEDs, HID report assembly, and buffer management — into one tightly coupled unit.

**Recommended decomposition:**

| Sub-module | Responsibility | Example from Bravo++ |
|------------|---------------|---------------------|
| `led_engine.lua` | Core LED state + buffer mgmt | `buffer[]`, `handle_led_changes()` |
| `led_hid_bridge.lua` | HID report assembly/sending | `send_hid_data()`, bit manipulation |
| `annunciator_leds.lua` | Annunciator LED evaluation | Row 1/Row 2 handlers, condition compilation |
| `gear_leds.lua` | Landing gear LEDs | 3-channel green/red state machine |
| `switch_leds.lua` | Rocker switch LEDs | Per-switch condition evaluation |

### Module Placement and Naming Convention

- All Bravo++ modules reside under `FlyWithLua/Modules/bravo++/`.
- Use `snake_case.lua` for filenames (e.g., `dispatch_action_map.lua`).
- Import via `require("bravo++.module_name")` — the double-dot prefix maps to the directory.
- Keep module-level constants in uppercase with underscores:

```lua
-- GOOD: Module-level constants (see state.lua, decoder.lua)
local M = {}
M.packet_size = 64
M.max_reports_per_poll = 16
M.SELECTOR_BYTE = 16
M.SELECTOR_MASK = 0x1F
return M
```

### Dependency Management

Modules should declare their dependencies at the top, in this order: standard library requires (`bit`, `os`), internal Bravo++ modules (`bravo++.log`, `bravo++.util`), then FlyWithLua globals (declared as local stubs for linting).

---

## Scoping & Visibility

### Prefer `local` Declarations

FlyWithLua executes all scripts in a **single global environment**. Every unqualified variable assignment becomes globally visible, which fundamentally changes how scoping works compared to standard Lua usage.

```lua
-- BAD: Implicit global leakage (common in closures)
function do_every_frame("handle_led_changes_task")
    led_state_modified = true  -- GLOBAL! Visible to all scripts
end

-- GOOD: Explicit local scope
local M = {}
local modified_flag = false  -- module-private state

function M.handle_led_changes()
    modified_flag = true  -- stays within this module's closure
end

return M
```

### Forward Declarations for Global Callbacks

FlyWithLua string callbacks must be globally named functions, but they often need to call local implementations. The forward-declaration pattern is the accepted approach:

```lua
-- GOOD: Forward declaration + deferred assignment (see BravoMultiMode.lua)
local get_button_led_state   -- declared at top of file
local handle_led_changes     -- declared at top of file

get_button_led_state = function(button_name)
    -- 40+ lines of implementation using local helpers
end

handle_led_changes = function()
    -- 60+ lines of implementation
end

add_macro("Get Button LED State", "get_button_led_state('AP1')")
```

**Caveat:** Forward declarations create a maintenance hazard — any new global callback requires updating both the declaration and definition locations. Document all forward-declared globals in a single header comment block:

```lua
--[[
    Global Callbacks (FlyWithLua string-callback entrypoints)
    ---@type function  local bravo_dispatch
    ---@type function  local get_button_led_state
]]
```

### Module-Level State Tables vs Individual Locals

For modules with many related state variables, prefer a single `state` table over individual locals:

```lua
-- GOOD: Centralized state (see dispatch.lua)
local M = {}
local state = {
    current_mode = nil, current_selection = nil, mode_select = false,
}

function M.cycle_mode_up()
    local index = util.find(state.modes, state.current_mode)
    state.current_mode = state.modes[(index % #state.modes) + 1]
end

return M
```

### Avoiding Implicit Coupling Through Shared Mutable State

When multiple callbacks share mutable state (e.g., `buffer[]`, `led_state_modified` in the LED engine), document the shared ownership explicitly:

```lua
-- GOOD: Explicit ownership via module pattern
local M = {}
M.buffer = {}  -- documented as public state for inter-module access

function M.update_buffer(new_states)
    -- atomic update of entire buffer
end

return M
```

---

## Error Handling

### `pcall` Wrappers for Critical Operations

FlyWithLua's string-callback model means errors in callbacks can silently fail without logging. Always wrap critical operations:

```lua
-- GOOD: pcall wrapper (see dispatch_buttons.lua)
local function _trigger_button_command(state, button_name)
    local cmds = buttons.resolve_button_command(state, button_name)
    if not cmds then return end

    local success, err = pcall(function()
        _G.command_once(cmds["ON_CLICK"])
    end)

    if not success then
        log.error("Button dispatch error for " .. button_name .. ": " .. tostring(err))
    end
end
```

### Never Bypass FlyWithLua's Safety Net

The `_G.command_once()` direct call in `dispatch_twist.lua` bypasses the try_catch error handling pattern used throughout the rest of the codebase:

```lua
-- BAD: Direct _G access, no error handling (see dispatch_twist.lua line ~60)
_G.command_once(current_action["UP"])

-- GOOD: Wrapped in pcall with logging
local success, err = pcall(function()
    _G.command_once(current_action["UP"])
end)
if not success then log.error("Twist knob command failed: " .. tostring(err)) end
```

### Defensive Nil Guards in Hot Paths

Frame-critical callbacks (e.g., `do_every_frame` at 0.25s intervals) must never crash due to nil access:

```lua
-- BAD: No nil guard before accessing potentially uninitialized dataref
local current_value = state.trim_dataref[0]  -- crashes if trim_dataref is nil!

-- GOOD: Nil-aware access with fallback (see dispatch_trim.lua)
if not state.trim_dataref then return end
local current_value = tonumber(state.trim_dataref[0]) or 0
```

### Fail-Safe Defaults for Configuration Parsing

When parsing config files, always provide a safe default rather than failing. The `condition_compiler.lua` module demonstrates this pattern: invalid conditions compile to a fail-safe predicate that always returns false instead of throwing an error.

---

## LED/HID Communication

### The Buffer → Evaluate → Send Cycle

The idiomatic FlyWithLua HID pattern (from `hid_filled_feature_report_demo.lua`) follows three distinct phases:

**Phase 1 — Maintain a Local Buffer Table:**

```lua
-- GOOD: Separate state from I/O (see hid_filled_feature_report_demo.lua)
local buffer = {}  -- local state, never directly sent to device

for bank = 1, 4 do
    buffer[bank] = {}
    for bit = 1, 8 do
        buffer[bank][bit] = false  -- default: all LEDs off
    end
end
```

**Phase 2 — Evaluate Conditions and Update Buffer:**

```lua
-- GOOD: Pure evaluation logic (see BravoMultiMode.lua LED engine)
function handle_led_changes()
    for i = 1, #button_map_leds do
        local cond = button_map_leds_cond[i]
        if cond and util.eval_condition(cond, current_value) then
            buffer[button_map_leds_index[i]] = true
        else
            buffer[button_map_leds_index[i]] = false
        end
    end
end
```

**Phase 3 — Convert Buffer to HID Report and Send:**

```lua
-- GOOD: Bit-packed conversion (see hid_filled_feature_report_demo.lua)
function send_hid_data()
    local data = {}
    for bank = 1, 4 do
        data[bank] = 0
        for bit = 1, 8 do
            if buffer[bank][bit] == true then
                data[bank] = bitwise.bor(data[bank], bitwise.lshift(1, bit - 1))
            end
        end
    end

    local bytes_written = hid_send_filled_feature_report(bravo, 0, 65,
        data[1], data[2], data[3], data[4])

    if bytes_written < 65 then
        logMsg("Partial write: " .. bytes_written .. "/65 bytes")
    end
end
```

### HID Device Lifecycle Management

Follow the pattern from `hardware.lua` for robust device handling — open with non-blocking mode, pre-allocate buffers, and respect time budgets per poll cycle.

---

## DataRef Interaction

### Three Access Patterns — Choose Wisely

FlyWithLua provides three ways to access X-Plane datarefs, with dramatically different performance characteristics (benchmarked in `DataRefAccessSpeed.lua`):

| Pattern | Syntax | Speed | Use Case |
|---------|--------|-------|----------|
| `get()`/`set()` functions | `get("sim/foo/bar")` | Slowest (~10-50ms per million accesses) | One-time reads, debugging |
| `DataRef()` function | `DataRef("QNH", "sim/weather/qnh")` | Medium | Scalar values accessed frequently |
| `dataref_table()` (magic tables) | `local t = dataref_table(...); t[0]` | Fastest (~1-5ms per million accesses) | Array datarefs, hot paths |

### Magic Tables for Array DataRefs

```lua
-- GOOD: Magic table for array access (see dispatch_trim.lua)
if not state.trim_dataref then return end
local current_value = tonumber(state.trim_dataref[0]) or 0
state.trim_dataref[0] = new_value
```

Magic tables use Lua's metatable system to transparently proxy `t[i]` reads/writes to X-Plane datarefs. The index `0` is used for scalar (non-array) datarefs.

### Detecting Magic Tables Safely

Use the utility function from `util.lua`:

```lua
-- GOOD: Type-safe magic table detection (see util.lua)
function util.is_dataref_magic_table(candidate_table)
    if type(candidate_table) ~= "table" then return false end
    if type(candidate_table.reftype) == "number" then return true end
    return false
end

-- Usage with nil guard
if util.is_dataref_magic_table(state.trim_dataref) then
    local val = state.trim_dataref[0] or 0
end
```

### Nil Guards Are Mandatory in Hot Paths

X-Plane datarefs may be `nil` during initialization, aircraft changes, or when the referenced plugin is not loaded. Always guard:

```lua
-- BAD: Crashes if trim_dataref hasn't been initialized yet
state.trim_dataref[0] = new_value  -- runtime error!

-- GOOD: Nil-aware access (see dispatch_trim.lua)
if not state.trim_dataref then return end
local current_value = tonumber(state.trim_dataref[0]) or 0
```

### Creating Custom DataRefs for Inter-Plugin Communication

FlyWithLua supports creating custom datarefs that other plugins can read/write:

```lua
-- GOOD: Custom dataref creation (see custom datarefs.lua example)
my_custom_table = create_dataref_table("FlyWithLua/my_plugin/custom_value", "Float")
my_custom_table[0] = 42.5

-- For arrays, index from zero dynamically
all_values = create_dataref_table("FlyWithLua/my_plugin/values_array", "IntArray")
for i = 0, 19 do all_values[i] = math.sqrt(i) end
```

---

## Performance Considerations

### Minimize Allocations in `do_every_frame` Callbacks

The LED update loop runs every 0.25 seconds via `do_every_frame`. Any allocation in this path triggers garbage collection pressure that can cause frame drops:

```lua
-- BAD: Allocates a new table on every invocation
function handle_led_changes()
    local changes = {}  -- NEW TABLE every call!
end

-- GOOD: Reuse pre-allocated table (see hardware.lua drain_queue pattern)
local change_list = {}  -- allocated once at module load

function handle_led_changes()
    local count = 0
    for i, v in ipairs(buffer) do
        if v ~= old_buffer[i] then
            count = count + 1
            change_list[count] = i
        end
    end

    for j = 1, count do process_change(change_list[j]) end
    for j = 1, count do change_list[j] = nil end  -- clear for next iteration
end
```

### Avoid String Concatenation in Tight Loops

Use `table.concat()` instead of repeated string concatenation:

```lua
-- BAD: O(n²) string allocation (see debug.lua for contrast)
local hex_string = ""
for i = 1, #r do hex_string = hex_string .. string.format("%02X ", r[i]) end

-- GOOD: Single table + concat (see debug.lua)
local s = {}
for i = 1, #r do s[#s + 1] = hex(r[i]) end
log.debug("HID REPORT: " .. table.concat(s, " "))
```

### Pre-Compute Values at Module Load Time

Values that don't change between invocations should be computed once during module load (see `ui.lua` for pre-computed text metrics caching).

### Time Budget Awareness

The `hardware.lua` module demonstrates time-budget awareness: ~5ms budget per poll cycle, with early exit if the limit is approached. This prevents blocking X-Plane's main thread.

### Debounce and Rate Limiting for Physical Inputs

Physical HID inputs (rotary encoders, trim wheels) can generate rapid events. Implement debouncing to avoid processing spurious signals:

```lua
-- GOOD: Debounce pattern (see decoder.lua)
local last_rotary_time = -1
local DEFAULT_ROTARY_MIN_INTERVAL = 0.030  -- seconds between same-knob events

function M.handle_rotary_event(direction)
    local now = os.clock()
    if now - last_rotary_time < DEFAULT_ROTARY_MIN_INTERVAL then return end
    last_rotary_time = now

    state.set_rotary(state.get_rotary() + (direction == "cw" and 1 or -1))
end
```

---

## Configuration Management

### The Exact → Variant → Generic Fallback Pattern

The `config.lua` module implements a robust three-tier config detection strategy:

```lua
-- GOOD: Config fallback chain (see BravoMultiMode.lua, config.lua)
local function load_config(aircraft_icao)
    local configs = {
        "bravo++/custom/" .. aircraft_icao .. ".lua",  -- exact match (B58.lua)
        "bravo++/custom/" .. get_variant_name() .. ".lua",  -- variant match (C90B.lua)
        "bravo++/config_generic.lua",  -- generic fallback
    }

    for _, path in ipairs(configs) do
        if io.open(path, "r") then return config.read_file(path, nav_bindings) end
    end

    log.warning("No configuration file found, using defaults")
    return {}
end
```

### Condition Compilation for LED States

The `condition_compiler.lua` module provides pure condition parsing and evaluation — no side effects. Supported operators (checked in order): `!=`, `<=`, `>=`, `<`, `>`, `=`. Bare numbers default to equality checks (`"5"` → `"=5"`).

```lua
-- Config file format: MASTER_WARNING_LED = ">0"  (LED on when value > 0)
local compiled_condition = condition_compiler.compile_condition(">0")
if condition_compiler.eval_condition(compiled_condition, current_value) then
    buffer[led_index] = true
end
```

### Custom Aircraft Module Extensions

The `bravo++/custom/` directory supports per-aircraft Lua modules that extend the base configuration:

```lua
-- GOOD: Custom module pattern (see custom/B58.lua, C90B.lua)
--[[
    B58.lua — Bombardier Global 5000 specific overrides

    This file is loaded after the generic config and can override any
    binding or add aircraft-specific LED conditions.
]]

nav_bindings["FIRE_WARNING"] = ">=1"  -- only when fire detected, not just caution
```

---

## Appendix: Quick Reference

### FlyWithLua Global Functions Used in Bravo++

| Function | Purpose | Module |
|----------|---------|--------|
| `add_macro(name, code)` | Register a FlyWithLua macro command | All modules |
| `do_every_frame("callback")` | Execute callback every frame (or via dispatch) | BravoMultiMode.lua |
| `hid_open(vendor, product)` | Open HID device by VID/PID | hardware.lua |
| `hid_read(handle, count)` | Read bytes from HID (non-blocking) | hardware.lua |
| `hid_send_filled_feature_report()` | Send feature report to HID device | led_hid_bridge.lua |
| `logMsg(message)` | Write to FlyWithLua log console | All modules |
| `dataref_table(path)` | Create magic table for X-Plane dataref | dispatch_trim.lua, ui.lua |

### Module Dependency Summary

```
BravoMultiMode.lua (host)
├── bravo++.util          -- type checks, string helpers
├── bravo++.log           -- level-based logging facade
├── bravo++.config        -- config file parsing + validation
│   └── bravo++.condition_compiler  -- pure condition evaluation
├── bravo++.dispatch      -- command/action mapping facade
│   ├── bravo++.dispatch_action_map
│   ├── bravo++.dispatch_buttons
│   ├── bravo++.dispatch_modes
│   ├── bravo++.dispatch_trim
│   └── bravo++.dispatch_twist
├── bravo++.hardware      -- HID device lifecycle + polling
├── bravo++.decoder       -- report decoding + pub/sub to state
├── bravo++.state         -- selector/rotary/trim state management
├── bravo++.debug         -- debug logging (toggleable)
├── bravo++.mapbuilder    -- unified mapping initialization
└── bravo++.plugincheck   -- conflict detection
```

### Anti-Pattern Checklist

- [ ] **Monolithic modules** — keep files under 300 lines; split by responsibility
- [ ] **Implicit globals** — always use `local` unless a FlyWithLua global is required
- [ ] **Direct `_G.command_once()` without pcall** — wrap all command invocations in error handling
- [ ] **Unprotected dataref access** — nil guards before every magic table read/write
- [ ] **String concatenation in loops** — use `table.concat()` with pre-built tables
- [ ] **Allocations in hot paths** — pre-allocate buffers at module load time
- [ ] **Inconsistent export patterns** — standardize on `local M = {} ... return M`
