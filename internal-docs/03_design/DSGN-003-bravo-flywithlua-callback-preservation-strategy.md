---
id: DSGN-003
title: Bravo++ FlyWithLua Callback Preservation Strategy
version: 1.0.0
status: APPROVED
created: 2026-07-23 19:20:00
updated: 2026-07-23 20:01:00
related_docs: ["FEAT-016", "RAD-005", "DSGN-001", "DSGN-002"]
---

# Bravo++ FlyWithLua Callback Preservation Strategy

## Overview

This document defines the technical design for how `bravo_dispatch` will act as a bridge between FlyWithLua's global environment and the new modular structure. It details the transition from the current varargs-forwarding pattern to explicit module export table lookups, ensuring that all FlyWithLua string callbacks continue to resolve correctly during and after refactoring.

## FlyWithLua Execution Model — Constraints

### String Callbacks Execute in Global Environment

FlyWithLua's `do_every_frame()`, `create_command()`, and `do_on_exit()` functions accept **string arguments** that are evaluated as Lua code in the **global environment**. This means:

1. Any function referenced by a string callback must exist as a global variable at the time FlyWithLua resolves it.
2. Local variables defined inside modules (via `local M = {}`) are NOT accessible from these strings.
3. The modularization MUST preserve a minimal set of global entrypoints that act as bridges to local module functions.

### Key FlyWithLua Functions Used by Bravo++

| Function | Purpose | Callback Type | Current Usage in BravoMultiMode.lua |
|----------|---------|---------------|-------------------------------------|
| `do_every_frame(string)` | Execute callback every frame | String → global function lookup | `"bravo_dispatch('handle_led_changes_task')"` etc. |
| `create_command(name, desc, onBegin, onContinue, onEnd)` | Register X-Plane custom commands | Strings for begin/continue/end callbacks | `"bravo_dispatch('cycle_mode_up')"`, `"bravo_dispatch('ap_begin', 'PLT')"` etc. |
| `do_on_exit(string)` | Execute callback on FlyWithLua unload/shutdown | String → global function lookup | `"bravo_dispatch('do_on_exit_task')"` |

### Current Pattern (Pre-Refactoring)

```lua
-- Forward declarations for locals referenced before definition
local get_button_led_state
local handle_led_changes

-- ... later in file ...

handle_led_changes = function()
    -- 60+ lines of LED evaluation logic
end

-- FlyWithLua string callbacks route through bravo_dispatch
dispatch_callbacks.handle_led_changes_task = handle_led_changes

do_every_frame("bravo_dispatch('handle_led_changes_task')")
```

**Issues with current pattern (RAD-005 Finding 2)**:
1. Forward declarations require updating two locations for each new global callback.
2. The `handle_led_changes` function is defined as a bare assignment (`handle_led_changes = ...`) rather than a proper local declaration, making it implicitly global in the file scope.
3. All LED sub-functions (gear, annunciator, switch) are tightly coupled inside this single block — no modular separation.

## Design: The Bridge Pattern

### Architecture Overview

```
FlyWithLua Host Application
    │
    ├── do_every_frame("bravo_dispatch('handle_led_changes_task')")
    ├── create_command(..., "bravo_dispatch('cycle_mode_up')", ...)
    └── do_on_exit("bravo_dispatch('do_on_exit_task')")
            │
            ▼
    ╔═══════════════════════════════╗
    ║  bravo_dispatch(name, ...)     ║  ← GLOBAL (must exist in _G)
    ║                                ║
    ║  Looks up name in             ║
    ║  dispatch_callbacks table      ║
    ║  → wraps in try_catch          ║
    ║  → forwards varargs            ║
    ╚═══════════════════════════════╝
            │
            ▼
    ╔═══════════════════════════════╗
    ║  dispatch_callbacks table      ║  ← Local to main script scope
    ║                                ║
    ║  {                             ║
    ║    handle_led_changes_task =   ║  → led_engine.handle_led_changes()
    ║      function() ... end,       ║
    ║    cycle_mode_up =             ║  → mode_manager.cycle_mode_up()
    ║      function() ... end,       ║
    ║    ap_begin =                  ║  → button_lifecycle handler
    ║      function(btn) ... end,    ║
    ║    rocker_switch =             ║  → dispatch.rocker_switch()
    ║      function(n, d) ... end,   ║
    ║    build_bravo_gui =           ║  → ui.build_gui(ctx)
    ║      function(wnd,x,y) ...end, ║
    ║    do_on_exit_task =           ║  → led_engine.all_off() + bridge.close()
    ║      function() ... end        ║
    ║  }                             ║
    ╚═══════════════════════════════╝
            │
            ▼
    ╔═══════════════════════════════╗
    ║  Modular Code (local modules)  ║
    ║                                ║
    ║  led_engine.handle_led_changes║
    ║  mode_manager.cycle_mode_up   ║
    ║  button_lifecycle handlers     ║
    ║  rocker_switches handler       ║
    ╚═══════════════════════════════╝
```

### bravo_dispatch — The Central Bridge

The `bravo_dispatch` function remains as the single global entrypoint. It does NOT change its fundamental behavior — it continues to receive a callback name and varargs, look up the corresponding local function in `dispatch_callbacks`, wrap execution in try_catch, and forward arguments.

**What changes**: The functions registered in `dispatch_callbacks` no longer contain inline implementation logic. Instead, they delegate to specific module export tables via injection references stored at composition root time.

```lua
-- bravo_dispatch — UNCHANGED (preserves backward compatibility)
function bravo_dispatch(name, ...)
    local fn = dispatch_callbacks[name]
    if not fn then
        log.warning("No dispatch target for: " .. tostring(name))
        return
    end

    -- NOTE: varargs are captured before closure to avoid Lua scoping issue
    local args = { ... }
    return try_catch(function()
        fn(unpack_fn(args))
    end, "bravo_dispatch:" .. tostring(name))
end
```

### dispatch_callbacks — The Routing Table

After refactoring, `dispatch_callbacks` becomes a thin routing table that maps string names to module method invocations:

```lua
-- After refactoring: dispatch_callbacks as routing table
local dispatch_callbacks = {}

-- LED Engine callbacks
dispatch_callbacks.handle_led_changes_task = function()
    led_engine.handle_led_changes({ bus_voltage_ref })
end

dispatch_callbacks.do_on_exit_task = function()
    try_catch(function()
        log.info("Bravo++ shutting down")
        if bravo then
            led_engine.all_off()
            -- Send cleared HID report via bridge module
            local success = led_hid_bridge.assemble_and_send(
                led_engine.buffer, default_button_labels, dispatch
            )
            if not success then
                log.error("Failed to send clear report on exit")
            end
            try_catch(function() hid_close(bravo) end, "hid_close_exit")
        end
    end, "do_on_exit_task")
end

-- Mode Manager callbacks
dispatch_callbacks.cycle_mode_up = function()
    mode_manager.cycle_mode_up()
end

dispatch_callbacks.cycle_mode_down = function()
    mode_manager.cycle_mode_down()
end

dispatch_callbacks.toggle_mode_select_true = function()
    mode_manager.activate_mode_select()
end

dispatch_callbacks.toggle_mode_select_false = function()
    mode_manager.deactivate_mode_select()
end

dispatch_callbacks.cycle_cf_mode = function()
    mode_manager.cycle_cf_mode()
end

dispatch_callbacks.cycle_switch_mode = function()
    mode_manager.cycle_switch_mode()
end

-- Button Lifecycle callbacks
dispatch_callbacks.ap_begin = function(button_name)
    dispatch.button_begin(button_name)
end

dispatch_callbacks.ap_continue = function(button_name)
    dispatch.button_continue(button_name)
end

dispatch_callbacks.ap_end = function(button_name)
    dispatch.button_end(button_name)
end

-- Rocker Switch callback
dispatch_callbacks.rocker_switch = function(rocker_number, dir)
    dispatch.rocker_switch(rocker_number, dir)
end

-- Input Handler callbacks (trim/twist from decoder)
dispatch_callbacks.trim_nose_up = function()
    pcall(function() _G.command_once(trim_dataref_up) end)
end

dispatch_callbacks.trim_nose_down = function()
    pcall(function() _G.command_once(trim_dataref_down) end)
end

-- UI callbacks (special: receives extra FlyWithLua parameters)
dispatch_callbacks.build_bravo_gui = function(wnd, x, y)
    local ctx = mode_manager.build_ui_context()
    ui.build_gui(ctx)
end

dispatch_callbacks.on_close_floating_window = function(my_wnd)
    ui.on_close({ hid_close_fn = hid_close, bravo = bravo })
end

-- HID poll callback (every frame)
dispatch_callbacks.bravo_hid_poll_task = function()
    bravo_hid.poll()
end

-- Selector refresh callback (every frame)
dispatch_callbacks.refresh_selector_task = function()
    local sel = bravo_state.get_selector()
    if sel and type(sel) == "number" and sel > 0 then
        mode_manager.set_selector_index(sel)
    end
end

-- Set current buttons callback (every frame)
dispatch_callbacks.set_current_buttons_task = function()
    -- Update button labels based on current mode/selection
    local mode = dispatch.get_current_mode()
    local selection = dispatch.get_current_selection()
    if selection_map_labels[mode] and selection_map_labels[mode][selection] then
        current_buttons = selection_map_labels[mode][selection]
    end
end

-- Knob decrease callback (from custom command)
dispatch_callbacks.knob_decrease = function()
    -- Route to appropriate handler based on current mode context
    dispatch.handle_knob_decrease()
end
```

### Global Entry Points — Minimal Set

After refactoring, exactly **three** functions must remain global:

| Function | Type | Purpose | Forwarding Target |
|----------|------|---------|-------------------|
| `bravo_dispatch` | function | Central routing hub for all FlyWithLua string callbacks | dispatch_callbacks[name] |
| `build_bravo_gui` | function | Floating window ImGui builder callback (receives wnd, x, y) | bravo_dispatch("build_bravo_gui", ...) |
| `on_close_floating_window` | function | Window close handler (receives wnd handle) | bravo_dispatch("on_close_floating_window", ...) |

**Note**: `profiler_toggle()` and `profiler_log_task()` are also global but belong to the profiler module. After extraction, they become:
- `profiler.toggle()` — called via `"bravo_dispatch('toggle_profiler')"`
- `profiler.log_and_reset()` — called via `"bravo_dispatch('profiler_log_task')"`

These remain as dispatch callbacks rather than globals because they are invoked through bravo_dispatch strings.

### Transition Plan: From Forward Declarations to Module Init Functions

#### Phase 0 (Current State) — Before Refactoring

```lua
-- BravoMultiMode.lua (current, monolithic)

local get_button_led_state      -- forward declaration
local handle_led_changes         -- forward declaration

-- ... 1500+ lines of inline code ...

get_button_led_state = function(button_name)   -- bare assignment (implicit global in file scope)
    -- 40+ lines
end

handle_led_changes = function()                 -- bare assignment (implicit global in file scope)
    -- 60+ lines
end

function build_bravo_gui(wnd, x, y)            -- GLOBAL (FlyWithLua callback)
    return bravo_dispatch("build_bravo_gui", wnd, x, y)
end

function on_close_floating_window(my_wnd)       -- GLOBAL (FlyWithLua callback)
    return bravo_dispatch("on_close_floating_window", my_wnd)
end
```

**Problems**: Forward declarations scattered across the file; bare assignments pollute file scope; all logic inline.

#### Phase 1 (After Refactoring) — With Modules

```lua
-- BravoMultiMode.lua (refactored, modular)

-- 1. Load modules via require()
local led_engine = require("bravo++.led_engine")
local led_hid_bridge = require("bravo++.led_hid_bridge")
local annunciator_leds = require("bravo++.annunciator_leds")
local gear_leds = require("bravo++.gear_leds")
local switch_leds = require("bravo++.switch_leds")
local mode_manager = require("bravo++.mode_manager")
local profiler = require("bravo++.profiler")

-- 2. Initialize modules with injected dependencies (composition root)
led_engine.init({ dispatch = dispatch, button_map_leds_state = ..., default_button_labels = ... })
annunciator_leds.init({ annunciator_bindings = ... })
gear_leds.init({ gear_dataref = gear, led_constants = {...} })
switch_leds.init({ switch_bindings = ..., dispatch_module = dispatch })
mode_manager.init({ dispatch_module = dispatch, modes_array = modes, selection_map_labels = ... })

-- 3. Register routing table entries (no inline logic)
dispatch_callbacks.handle_led_changes_task = function()
    led_engine.handle_led_changes({ bus_voltage_ref })
end

dispatch_callbacks.cycle_mode_up = function()
    mode_manager.cycle_mode_up()
end

-- No forward declarations needed — modules are initialized before callbacks are registered.

-- 4. Minimal global entrypoints (FlyWithLua string callback bridge)
function build_bravo_gui(wnd, x, y)
    return bravo_dispatch("build_bravo_gui", wnd, x, y)
end

function on_close_floating_window(my_wnd)
    return bravo_dispatch("on_close_floating_window", my_wnd)
end
```

**Benefits**: No forward declarations; all module state encapsulated in closure variables set during init(); clear separation between bridge (global entrypoints), routing table (dispatch_callbacks), and modular logic (export tables).

## Transition from Varargs-Forwarding to Export Table Lookups

### Current Pattern: Inline Logic in dispatch_callbacks

```lua
-- Before: Each callback contains full implementation logic inline
dispatch_callbacks.cycle_mode_up = function()
    return try_catch(function()
        dispatch.cycle_mode_up()
        prime_button_led_states_for_mode_change()  -- local function from same file
        led_state_modified = true                   -- shared local variable
        handle_led_changes()                        -- forward-declared local function
    end, "cycle_mode_up")
end

-- Problem: This callback is tightly coupled to BravoMultiMode.lua's internal state.
```

### New Pattern: Module Export Table Lookup via Routing Table

```lua
-- After: Callback delegates to module method; routing table is thin
dispatch_callbacks.cycle_mode_up = function()
    mode_manager.cycle_mode_up()  -- module handles its own side effects internally
end

-- The led_engine module manages its own dirty flag and buffer state.
-- The mode_manager module knows how to trigger LED updates after mode changes (via injection).
```

### Migration Strategy: Two-Phase Approach

#### Phase A — Preserve Current bravo_dispatch Behavior

1. Keep `bravo_dispatch` function exactly as-is (no signature or behavior change).
2. Move all inline callback implementations into their respective modules' export tables.
3. Update dispatch_callbacks entries to be thin forwarding functions that call module methods.
4. **Verification**: Run integration tests — all string callbacks must resolve and execute identically.

#### Phase B — Optional: Per-Module Export Table Lookups (Future Enhancement)

After the initial refactoring is verified, consider a secondary optimization where each module maintains its own export table lookup for frequently-called functions, reducing dispatch_callbacks size:

```lua
-- Future optional pattern (NOT required for FEAT-016):
local led_engine_cb = led_engine.handle_led_changes  -- direct reference to module method

dispatch_callbacks.handle_led_changes_task = function()
    try_catch(led_engine_cb, "handle_led_changes_task")
end
```

This reduces the indirection layer by one hop but is optional and deferred to Phase 4.

## FlyWithLua Integration Verification Checklist

For each refactoring phase, verify:

| Check | Method | Pass Criteria |
|-------|--------|---------------|
| `bravo_dispatch` resolves globally | Load script in X-Plane; check log for "No dispatch target" warnings | No warnings for any registered callback name |
| `build_bravo_gui` renders UI | Open floating window in X-Plane | ImGui builder renders correctly with current mode/selection data |
| `on_close_floating_window` cleans up | Close floating window or unload FlyWithLua script | LEDs turn off; HID device closes cleanly; no error logs |
| LED update loop runs at 0.25s interval | Check profiler output for "handle_led_changes" task timing | Interval between calls ≈ 0.25 seconds (±1 frame) |
| All rocker switch commands work | Toggle each of 7 switches × UP/DOWN in X-Plane | dispatch.rocker_switch() called with correct parameters; no errors |
| AP button lifecycle works | Press/release each AP button | begin/continue/end callbacks fire correctly; try_catch logs any failures |
| Mode cycling works | Press MODE button or cycle command | Modes advance through all entries; LED states update for new mode |
| Trim wheel and twist knob work | Rotate trim/twist in X-Plane | Commands execute without silent failures (RAD-005 Finding 3 resolved) |
| HID output is byte-identical | Compare feature report bytes before/after refactoring | All 4 banks × 8 bits match for all aircraft configurations |

## Risk Mitigation: String Callback Breakage

### Risk: Modularization breaks FlyWithLua string-callback resolution

**Cause**: If a function referenced by a string callback is not global, FlyWithLua's `loadstring()` evaluation will fail with "attempt to call a nil value" or similar.

**Mitigations**:
1. **Minimal globals only**: Exactly 3 functions remain global (`bravo_dispatch`, `build_bravo_gui`, `on_close_floating_window`). All others route through bravo_dispatch.
2. **Integration tests after each phase**: Run the script in X-Plane with all string callbacks exercised (every frame callback, every command callback, exit callback).
3. **Error logging**: bravo_dispatch's try_catch wrapper logs any failures with source identification, making it easy to trace broken callbacks.
4. **No elimination of bravo_dispatch**: The bridge pattern is preserved throughout — never removed or replaced during refactoring.

### Risk: Forward-declaration fragility persists in new modules

**Cause**: If a module defines a FlyWithLua callback function before its implementation (due to file ordering), the same two-location update problem reappears.

**Mitigation**: All new modules use `M.init(opts)` for dependency injection rather than forward declarations. The composition root initializes all modules and registers callbacks in a single, sequential pass — no circular initialization needed because dependencies are injected as parameters, not required at load time.

## Dataref Access Safety in Modularized Code

### RAD-005 Finding 5: Missing Nil Guards in Hot Paths

The original `handle_button_led_changes()` function accesses `button_map_leds`, `button_map_leds_cond`, and `button_map_leds_index` without defensive nil checks before the initial `util.is_table()` guard. In modularized code, this is addressed by:

1. **Config loader validation**: The config_loader module validates all dataref bindings during initialization and logs warnings for missing or malformed entries.
2. **Module-level nil guards**: Each LED sub-module's evaluation function includes defensive checks before accessing any injected dataref table:
   ```lua
   local function evaluate_single(dataref, condition, index)
       if not util.is_dataref_magic_table(dataref) then return false end  -- guard
       -- ... safe access follows
   end
   ```
3. **try_catch wrapping**: All LED evaluation functions are wrapped in try_catch within the main `handle_led_changes()` orchestration, so any unexpected nil access is caught and logged without crashing the update loop.

## Summary: What Changes vs. What Stays the Same

| Aspect | Before Refactoring | After Refactoring |
|--------|-------------------|-------------------|
| Global entrypoints | 3 functions + forward-declared locals | Exactly 3 functions (bravo_dispatch, build_bravo_gui, on_close_floating_window) |
| bravo_dispatch behavior | Unchanged — still routes via dispatch_callbacks table | **Unchanged** — same signature, same try_catch wrapping, same varargs forwarding |
| dispatch_callbacks content | Inline implementation logic (~20 functions with 10-60 lines each) | Thin forwarding functions (1-3 lines each) that call module methods |
| LED engine code | ~640 lines in BravoMultiMode.lua inline | Split across 5 modules; main script contains only initialization + callback routing |
| Forward declarations | Required for FlyWithLua callbacks defined after use | **Eliminated** — init() pattern ensures all dependencies available before registration |
| Module coupling | High (all LED logic shares file-scope locals) | Low (modules communicate via injected parameters and callback references) |
| Testability | Impossible without full host context | Each module testable in isolation with mock injection parameters |
