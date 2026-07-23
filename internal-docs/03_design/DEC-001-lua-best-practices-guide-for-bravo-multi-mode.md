---
id: DEC-001
title: Lua Best Practices Guide for Bravo Multi Mode
version: 1.0.0
status: DRAFT
created: 2026-07-23 12:14:38
updated: 2026-07-23 12:18:46
related_docs: ["REQ-008", "RAD-005"]
---
# Lua Best Practices Guide for Bravo Multi Mode

This guide synthesizes best practices from the [Lua 5.4 Manual](https://www.lua.org/manual/5.4/manual.html), [MediaWiki Lua Best Practices](https://www.mediawiki.org/wiki/Help:Lua/Lua_best_practice), [awesome-lua](https://github.com/lewisjellis/awesome-lua) resources, and the FlyWithLua host application manual — tailored specifically to the Bravo Multi Mode project's architecture, runtime constraints, and X-Plane integration patterns.

All code examples are drawn from or applicable to the existing Bravo Multi Mode codebase. Worker specialists should reference this guide during refactoring implementation.

---

## 1. Module Organization

### 1.1 `require` Conventions

Use the full module path with `bravo++.` prefix for all internal modules:

```lua
-- GOOD — consistent, explicit paths
local util = require("bravo++.util")
local log = require("bravo++.log")
local config = require("bravo++.config")

-- AVOID — relative or implicit paths
local util = require("./util")       -- fragile across directory changes
local log = require "log"            -- ambiguous without prefix
```

### 1.2 Export Table Pattern

Use the `local M = {} ... return M` pattern consistently for all modules:

```lua
-- GOOD — clear public API surface
local M = {}

function M.function_name(param)
    -- implementation
end

M.constant_value = "read-only constant"

return M

-- AVOID — implicit globals or mixed patterns
my_function = function() ... end   -- leaks to global namespace
```

**Rationale**: FlyWithLua executes callbacks in the global environment. The `M` pattern ensures that only explicitly exported functions are accessible when a module is required, preventing accidental pollution of the global scope. This aligns with Lua 5.4's module system philosophy and matches the idiomatic patterns found in FlyWithLua example scripts like `hid_filled_feature_report_demo.lua`.

### 1.3 Namespace Management via Tables

For modules with many related functions, use nested tables for namespacing:

```lua
-- GOOD — logical grouping within a single require'd module
local M = {}

M.LED = {
    get_state = function(...) end,
    set_state = function(...) end,
}

M.HID = {
    send_report = function(...) end,
    init_device = function(...) end,
}

return M
```

### 1.4 Avoiding Global Pollution

FlyWithLua executes callback strings in the global environment. Minimize globals:

```lua
-- GOOD — keep implementation details local
local function internal_helper()
    -- ... private logic ...
end

function M.public_api()
    return internal_helper()
end

-- AVOID — functions that leak to global via FlyWithLua string callbacks
function build_bravo_gui(wnd, x, y)  -- This MUST be global for FlyWithLua
    ui.build_gui(build_ui_context())
end
```

**Key rule**: Only the minimal set of entrypoints required by FlyWithLua's string-callback mechanism (`bravo_dispatch`, `build_bravo_gui`, `on_close_floating_window`) should be global. Everything else must be local and accessed through module exports or the dispatch facade.

---

## 2. Scoping & Visibility

### 2.1 Local vs Global Variable Discipline

Always prefer `local` declarations. In Lua, `local` variables are faster (up to 30% in tight loops) because they use stack slots instead of hash table lookups:

```lua
-- GOOD — local for all internal state
local buffer = {}
local led_state_modified = false
local last_call = os.clock()

-- AVOID — implicit globals (creates global if not declared with `local`)
buffer = {}          -- BUG: creates or overwrites a global!
led_state_modified = true  -- same issue
```

### 2.2 Forward Declaration Patterns

When FlyWithLua requires a function to be global but the implementation appears later in the file, use explicit forward declarations:

```lua
-- GOOD — declare before use, assign later
local get_button_led_state
local handle_led_changes

function build_bravo_gui(wnd, x, y)  -- must be global for FlyWithLua
    return bravo_dispatch("build_bravo_gui", wnd, x, y)
end

get_button_led_state = function(button_name)  -- assignment after declaration
    -- implementation
end
```

### 2.3 Closure Best Practices with Varargs

Varargs (`...`) are NOT lexically scoped in Lua — they can only be accessed directly by the immediate enclosing function, not by nested closures:

```lua
-- GOOD — capture varargs into a local table before passing to closure
function bravo_dispatch(name, ...)
    local args = { ... }  -- capture varargs immediately
    return try_catch(function()
        fn(unpack_fn(args))  -- use captured copy inside closure
    end, "bravo_dispatch:" .. tostring(name))
end

-- AVOID — referencing `...` directly from a nested closure
function bad_example(...)
    local function inner()
        print(select(1, ...))  -- BUG: nil or wrong value!
    end
end
```

This pattern is correctly implemented in BravoMultiMode.lua's `bravo_dispatch()` function (line ~209). Worker specialists should replicate this pattern when adding new dispatch callbacks.

### 2.4 Module-Level vs Function-Level Locals

Use module-level locals for state that persists across function calls within the same module:

```lua
-- GOOD — shared mutable state at module level
local M = {}
local subscribers = {}   -- persists across all function calls in this module

function M.subscribe(event, fn)
    if not subscribers[event] then subscribers[event] = {} end
    table.insert(subscribers[event], fn)
end

return M  -- matches the pattern used in state.lua and decoder.lua
```

---

## 3. Error Handling

### 3.1 Structured Use of `pcall` / `try_catch`

Use a consistent try-catch wrapper for all FlyWithLua callback invocations:

```lua
-- GOOD — consistent error handling pattern (as used in BravoMultiMode.lua)
local function try_catch(tryBlock, source)
    local success, errorMessage = pcall(tryBlock)
    if not success then
        log.error("Caught error from " .. tostring(source) .. " : " .. tostring(errorMessage))
    end
end

dispatch_callbacks.ap_begin = function(button_name)
    return try_catch(function()
        dispatch.button_begin(button_name)
    end, "ap_begin:" .. button_name)
end
```

### 3.2 Error Logging Conventions via the `log` Module

Use the appropriate log level for different error types:

```lua
-- GOOD — match severity to impact
log.debug("Detailed diagnostic info")       -- only in debug builds
log.info("Normal operational message")       -- expected events
log.warning("Recoverable issue, continuing") -- degraded but functional
log.error("Critical failure, feature broken")  -- action required
```

### 3.3 Graceful Degradation Strategies

When a dataref or external resource may be unavailable:

```lua
-- GOOD — defensive nil checking with graceful fallback
local function handle_gear_led_changes()
    if gear == nil then
        -- Fixed-gear aircraft: all LEDs off
        for i = 1, 3 do
            set_led(green_led[i], false)
            set_led(red_led[i], false)
        end
        return
    end

    -- Normal processing with dataref access
    local gear_state = gear[0] or 0  -- nil guard on array access
    -- ... rest of logic ...
end
```

---

## 4. LED / HID Communication Patterns

### 4.1 LED State Management: Buffer → Evaluate → Send

The recommended pattern for LED state management, as used in the current codebase:

```lua
-- GOOD — three-phase LED update cycle
local buffer = {}          -- Phase 0: storage (initialized once)
local led_state_modified = false  -- dirty flag

function set_led(led_coords, state)
    if state ~= get_led(led_coords) then
        buffer[led_coords[1]][led_coords[2]] = state
        led_state_modified = true   -- Phase 1: mark dirty on change
    end
end

function send_hid_data()
    local data = {}
    for bank = 1, 4 do
        data[bank] = 0
        for bit = 1, 8 do
            if buffer[bank][bit] == true then
                data[bank] = bit.bor(data[bank], bit.lshift(1, bit - 1))
            end
        end
    end

    local bytes_written = hid_send_filled_feature_report(bravo, 0, 65, data[1], data[2], data[3], data[4])
    if bytes_written == 65 then
        led_state_modified = false  -- Phase 2: clear dirty flag on success
    end
end

function handle_led_changes()
    evaluate_all_leds()   -- calls set_led for each LED
    if led_state_modified then
        send_hid_data()
    end
end
```

This matches the pattern from FlyWithLua's `hid_filled_feature_report_demo.lua` example script, confirming it as an idiomatic approach.

### 4.2 Conditional DataRef Evaluation

When evaluating dataref conditions for LEDs:

```lua
-- GOOD — compile condition once at init time, evaluate repeatedly
local function get_led_state_for_dataref(dr_table, cond, index)
    if dr_table == nil then return false end  -- defensive nil check

    local val = dr_table[0]   -- or dr_table[index - 1] for arrays
    if val == nil then return false end

    local vnum = tonumber(val)
    if vnum ~= nil then
        return config.eval_condition(vnum, cond)
    end
    return false  -- non-numeric value cannot satisfy numeric condition
end
```

### 4.3 HID Report Assembly and Sending Conventions

From FlyWithLua's `hid_filled_feature_report_demo.lua`:

```lua
-- GOOD — assemble report data into flat array before sending
local function send_hid_data()
    local data = {}
    for bank = 1, 4 do
        data[bank] = 0
        for bit = 1, 8 do
            if buffer[bank][bit] == true then
                data[bank] = bitwise.bor(data[bank], bitwise.lshift(1, bit - 1))
            end
        end
    end

    -- Report ID (0) + 64 bytes of data = 65 total bytes
    local bytes_written = hid_send_filled_feature_report(bravo, 0, 65,
        data[1], data[2], data[3], data[4])

    if bytes_written ~= 65 then
        log.error("HID write failed: " .. tostring(bytes_written) .. " bytes")
    end
end
```

---

## 5. DataRef Interaction

### 5.1 DataRef Table Usage

FlyWithLua's `dataref_table()` returns a magic table with special properties (`reftype`, etc.):

```lua
-- GOOD — use util.is_dataref_magic_table() for type checking
local bus_voltage = dataref_table("sim/cockpit2/electrical/bus_volts")

if util.is_dataref_magic_table(bus_voltage) then
    local voltage = bus_voltage[0]  -- scalar: index 0
    if voltage and voltage > 0 then
        -- ...
    end
end
```

### 5.2 Array vs Scalar Handling

Distinguish between array datarefs (multiple indices) and scalars:

```lua
-- GOOD — check reftype to determine access pattern
local gear = dataref_table("sim/flightmodel2/gear/gear_pos")

if util.is_dataref_magic_table(gear) then
    local elemCount = util.get_dataref_array_size(gear)  -- from util.lua
    if elemCount and elemCount > 0 then
        for i = 0, elemCount - 1 do
            local val = gear[i]
            -- process each element
        end
    else
        -- Scalar access: gear[0] only
        local val = gear[0] or 0
    end
end
```

### 5.3 Safe Access Patterns with Nil Guards

Always guard dataref access in hot paths:

```lua
-- GOOD — nil guards on every dataref read
local function handle_gear_led_changes()
    if gear == nil then return end  -- early exit if not configured

    local g1 = gear[0] or 0   -- nil coalescing for safety
    local g2 = gear[1] or 0
    local g3 = gear[2] or 0

    -- Process known-safe values...
end
```

### 5.4 Condition Compilation

Use the `condition_compiler.lua` module to compile conditions once at initialization:

```lua
-- GOOD — compile condition string → function at init time (O(1) evaluation per frame)
local compiled = config.compile_condition("<9", "GEAR_LED")
-- Returns a callable that evaluates the condition against numeric values

-- Later, in hot path:
if compiled(gear[0] or 0) then
    set_led(LED_GEAR_GREEN, true)
end
```

---

## 6. Performance Considerations

### 6.1 Frame-Rate Sensitivity in `do_every_frame` Callbacks

FlyWithLua's `do_every_frame()` executes callbacks every frame (typically ~30–60 Hz). Keep these callbacks minimal:

```lua
-- GOOD — delegate heavy work to a periodic task with explicit interval
local function handle_led_changes_task()
    local t = profiler.start("handle_led_changes")
    do_more_often(handle_led_changes, "handle_led_changes", 0.25)  -- every 250ms
    profiler.stop("handle_led_changes", t)
end

do_every_frame("bravo_dispatch('handle_led_changes_task')")
```

The `do_more_often` wrapper ensures the actual work runs at most once per interval, regardless of frame rate. This is critical because X-Plane's rendering and Lua execution share resources.

### 6.2 Minimizing Allocations in Hot Paths

Avoid table allocations inside frequently-called functions:

```lua
-- GOOD — pre-compute metrics at module load time (done in ui.lua)
local symbol_metrics = {}
local function get_symbol_metrics(symbol, scale)
    local cache_key = symbol .. "_" .. tostring(scale)
    if not symbol_metrics[cache_key] then
        -- Compute once, reuse thereafter
        local w, h = imgui.CalcTextSize(symbol)
        symbol_metrics[cache_key] = {w = w, h = h}
    end
    return symbol_metrics[cache_key].w, symbol_metrics[cache_key].h
end

-- AVOID — allocating new tables on every call in hot path
local function bad_example()
    local result = {}  -- allocated every frame!
    for i = 1, #data do
        table.insert(result, process(data[i]))
    end
    return result
end
```

### 6.3 Garbage Collection Awareness

For long-running simulation sessions (hours of flight time), be mindful of:

- **String concatenation in tight loops**: Use `table.concat()` instead of repeated `..` operators.
- **Temporary table creation**: Reuse tables where possible rather than creating new ones each frame.
- **Coroutine usage**: Lua 5.4 supports coroutines, but FlyWithLua's execution model does not support yielding across frames — use them only for synchronous batch processing within a single callback invocation.

### 6.4 Profiler Integration

The project includes a built-in profiler (`profiler.lua` extraction candidate):

```lua
-- GOOD — zero-overhead when disabled, detailed stats when enabled
local PROFILER_ENABLED = false

function profiler.start(task_name)
    if not PROFILER_ENABLED then return nil end
    return os.clock()
end

function profiler.stop(task_name, start_time)
    if not PROFILER_ENABLED or not start_time then return end
    local delta = os.clock() - start_time
    -- accumulate into sorted stats table
end
```

Enable profiling during development to identify hot paths: `FlyWithLua/Bravo++/toggle_profiler` command.

---

## 7. Configuration Management

### 7.1 Multi-Step Config Detection Pattern

The Bravo Multi Mode uses a three-tier config detection strategy — follow this pattern for any new configuration loading:

```lua
-- GOOD — exact → variant → generic fallback with clear logging
local function load_aircraft_config(aircraft_dir, aircraft_name)
    local file_ok = false

    -- Step 1: Exact match (bravo_multi-mode.<name>.cfg)
    local candidate = "bravo_multi-mode." .. aircraft_name .. ".cfg"
    nav_cfg_file_full_path = aircraft_dir .. candidate
    if config.read_file(nav_cfg_file_full_path, nav_bindings) then
        log.info("Loaded exact-match config for " .. aircraft_name)
        file_ok = true
    end

    -- Step 2: Variant match (bravo_multi-mode.<name>.*.cfg)
    if not file_ok then
        local escaped_name = aircraft_name:gsub("%-", "%%-"):gsub("%.", "%%.")
        local variant_pattern = "^bravo_multi%-mode%." .. escaped_name .. "%.([^.]+)%.[cC][fF][gG]$"
        local all_files = util.list_files(aircraft_dir)
        for _, filename in ipairs(all_files) do
            if string.match(filename, variant_pattern) then
                nav_cfg_file_full_path = aircraft_dir .. filename
                if config.read_file(nav_cfg_file_full_path, nav_bindings) then
                    log.info("Loaded variant config: " .. filename)
                    file_ok = true
                    break  -- use first match (sorted alphabetically)
                end
            end
        end
    end

    -- Step 3: Generic fallback (bravo_multi-mode.cfg)
    if not file_ok then
        local candidate = "bravo_multi-mode.cfg"
        nav_cfg_file_full_path = aircraft_dir .. candidate
        config.read_file(nav_cfg_file_full_path, nav_bindings)
        log.info("Loaded generic config")
        file_ok = true  -- non-fatal: generic is acceptable fallback
    end

    return file_ok
end
```

### 7.2 Validation Context Building

Build a context table for validation functions to keep them pure and testable:

```lua
-- GOOD — pass all needed data via explicit context table
local validation_context = {
    modes = modes,
    default_selections = default_selections,
    annunciator_labels = annunciator_labels,
}

local keys_valid = config.validate_keys(nav_bindings, validation_context)
local values_valid = config.validate_values(nav_bindings, validation_context)
```

### 7.3 Preference Merging Strategy

Global preferences are loaded first; aircraft-specific configs override them:

```lua
-- GOOD — load order ensures correct precedence
config.read_preferences(general_prefs_path, nav_bindings)   -- Step 1: defaults + user prefs
config.read_file(aircraft_cfg_path, nav_bindings)           -- Step 2: overrides (same table mutated)
```

---

## 8. Command Registration

### 8.1 `create_command` Patterns for X-Plane / FlyWithLua Integration

Use the dispatch facade to route all commands through a single entrypoint:

```lua
-- GOOD — create_command with bravo_dispatch forwarding
create_command(
    "FlyWithLua/Bravo++/mode_button",
    "Bravo++ toggles MODE",
    "bravo_dispatch('cycle_mode_down')",  -- string callback (global env)
    "",                                      -- onBegin
    ""                                       -- onEnd
)

-- The global wrapper:
function bravo_dispatch(name, ...)
    local fn = dispatch_callbacks[name]
    if not fn then
        log.warning("No dispatch target for: " .. tostring(name))
        return
    end
    local args = { ... }  -- capture varargs before closure
    return try_catch(function()
        fn(unpack_fn(args))
    end, "bravo_dispatch:" .. tostring(name))
end

-- The registered handler:
dispatch_callbacks.cycle_mode_down = function()
    dispatch.cycle_mode_down()
end
```

### 8.2 DataRef-Based Command Wiring

For commands with begin/continue/end phases (e.g., momentary buttons):

```lua
create_command(
    "FlyWithLua/Bravo++/autopilot_button",
    "Bravo++ AUTOPILOT button",
    "bravo_dispatch('ap_begin', 'PLT')",   -- onBegin: press
    "bravo_dispatch('ap_continue', 'PLT')", -- onContinue: hold
    "bravo_dispatch('ap_end', 'PLT')"       -- onEnd: release
)
```

### 8.3 Callback String Conventions

- Keep callback strings short and simple — they execute in the global environment.
- Always use `bravo_dispatch()` as the single entry point for safety (try_catch + varargs capture).
- Never embed complex Lua expressions directly in callback strings.

---

## 9. FlyWithLua Integration Patterns

### 9.1 String-Callback Execution Model

FlyWithLua executes all string callbacks (`do_every_frame`, `create_command` callbacks, `float_wnd_set_imgui_builder`) **in the global environment**. This means:

- All functions referenced in callback strings must be globally accessible.
- Local variables are NOT visible to string callbacks.
- The recommended pattern is a minimal set of global entrypoints that forward to local implementations via tables.

```lua
-- GOOD — minimal globals, everything else local
function bravo_dispatch(name, ...)  -- GLOBAL: FlyWithLua entrypoint
    -- ... varargs capture + try_catch + dispatch ...
end

function build_bravo_gui(wnd, x, y)  -- GLOBAL: imgui builder callback
    return bravo_dispatch("build_bravo_gui", wnd, x, y)
end

-- All actual implementations are local functions in tables
dispatch_callbacks.build_bravo_gui = function(wnd, x, y)
    ui.build_gui(build_ui_context())
end
```

### 9.2 `do_every_frame` Semantics and Performance Implications

- `do_every_frame()` callbacks execute every X-Plane frame (~30–60 Hz).
- Each callback string is evaluated in the global environment — no local scope.
- **Critical**: Keep `do_every_frame` callbacks lightweight; delegate heavy work to periodic tasks with explicit intervals using a wrapper like `do_more_often()`.

```lua
-- GOOD — frame-level poll delegates to 4Hz task
do_every_frame("bravo_dispatch('handle_led_changes_task')")

local function handle_led_changes_task()
    do_more_often(handle_led_changes, "handle_led_changes", 0.25)
end
```

### 9.3 `do_on_exit` Cleanup Guarantees

Use `do_on_exit()` for graceful shutdown — FlyWithLua guarantees this runs when the script is unloaded:

```lua
-- GOOD — comprehensive exit cleanup with error handling
local function do_on_exit_task()
    try_catch(function()
        if bravo == nil then return end
        all_leds_off()
        send_hid_data()  -- send cleared report
        hid_close(bravo)
        bravo = nil
    end, "do_on_exit")
end

do_on_exit("bravo_dispatch('do_on_exit_task')")
```

### 9.4 Floating Window API Patterns

From FlyWithLua examples and the Bravo Multi Mode codebase:

```lua
-- GOOD — floating window with imgui builder callback
local my_floating_wnd = float_wnd_create(550, height, 1, true)
float_wnd_set_title(my_floating_wnd, "Bravo++ multi-mode")
float_wnd_set_imgui_builder(my_floating_wnd, "build_bravo_gui")
float_wnd_set_onclose(my_floating_wnd, "on_close_floating_window")

-- Position relative to screen (FlyWithLua globals)
float_wnd_set_position(my_floating_wnd, SCREEN_WIDTH * 0.25, SCREEN_HEIGHT * 0.25)
```

### 9.5 X-Plane DataRef Access Constraints Within FlyWithLua

- Datarefs may be nil during script initialization — always check before access.
- Array datarefs use `dataref_table()` with index-based access (`table[0]`, `table[1]`, etc.).
- The `reftype` property encodes array element count (low 12 bits) and data type (high bits).
- Datarefs accessed in hot paths should be cached at module load time rather than looked up each frame.

---

## 10. Anti-Patterns to Avoid

### 10.1 Global Variable Leakage

```lua
-- BAD — accidentally creates global if `local` is omitted
buffer = {}          -- pollutes global namespace
led_state_modified = true  -- same issue

-- GOOD — always use local for internal state
local buffer = {}
local led_state_modified = false
```

### 10.2 Tight Coupling Between Modules

Avoid having modules directly access each other's internals:

```lua
-- BAD — dispatch module reaches into another module's private table
function M.some_function()
    return decoder._last_report()  -- accessing internal state
end

-- GOOD — use public API or dependency injection
function M.some_function(report)
    -- report passed as parameter, not accessed from global/module scope
end
```

### 10.3 Monolithic Scripts (The Anti-Pattern This Analysis Targets)

A single script exceeding 500 lines with multiple distinct responsibilities should be split:

| Metric | Current State | Target |
|--------|--------------|--------|
| `BravoMultiMode.lua` size | 1,577 lines | < 400 lines (entrypoint only) |
| LED engine block | ~640 lines in main script | Split into 5 modules (~80–150 lines each) |
| Max module size | 524 lines (`ui.lua`) | Acceptable; keep under 600 lines |

### 10.4 Unguarded Table Access

```lua
-- BAD — no nil check before table access
local val = button_map_leds[mode][selection][button]  -- crashes if any level is nil

-- GOOD — defensive access with intermediate checks
if util.is_table(button_map_leds) and
   util.is_table(button_map_leds[mode]) and
   util.is_table(button_map_leds[mode][selection]) then
    local val = button_map_leds[mode][selection][button]
end
```

### 10.5 Missing Nil Checks on Datarefs

```lua
-- BAD — assumes dataref always has a value
local voltage = bus_voltage[0]  -- could be nil during initialization

-- GOOD — explicit nil guard
local voltage = bus_voltage and bus_voltage[0] or 0
if voltage > 0 then
    -- ... safe to use voltage ...
end
```

---

## Appendix A: Module Export Pattern Quick Reference

| Module | Pattern Used | Consistent? |
|--------|-------------|-------------|
| `log.lua` | Named local table (`local log = {}`) | Partially — no `M`, but returns named table |
| `util.lua` | Named local table (`local util = {}`) | Partially |
| `config.lua` | Named local table (`local config = {}`) | Partially |
| `dispatch.lua` | Named local table (`local dispatch = {}`) | Partially |
| `hardware.lua` | `local M = {} ... return M` | ✅ Yes |
| `decoder.lua` | `local M = {} ... return M` | ✅ Yes |
| `state.lua` | `local M = {} ... return M` | ✅ Yes |
| `debug.lua` | `local M = {} ... return M` | ✅ Yes |
| `ui.lua` | Named local table (`local ui = {}`) | Partially — no explicit export for all functions |

**Recommendation**: Standardize all modules to use the `local M = {} ... return M` pattern. This is consistent with Lua 5.4 module conventions and matches the FlyWithLua example scripts' patterns (e.g., `hid_filled_feature_report_demo.lua`).

## Appendix B: Severity Classification Reference

| Severity | Criteria | Example from Analysis |
|----------|----------|----------------------|
| **Critical** | Blocks testing, causes crashes, or violates core architecture principles | LED engine monolithic block (~640 lines) |
| **High** | Significant technical debt; could cause runtime errors in edge cases | `_G.command_once` bypassing try_catch; forward declaration fragility |
| **Medium** | Code quality issue; reduces maintainability but not correctness | Inconsistent export patterns; missing nil guards in hot paths |
| **Low** | Style/naming preference; no functional impact | Profiler placement at top of main script instead of separate module |
