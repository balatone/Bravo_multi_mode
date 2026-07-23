---
id: DSGN-002
title: Bravo++ Dependency Mapping & Injection Strategy
version: 1.0.0
status: IN_REVIEW
created: 2026-07-23 19:15:00
updated: 2026-07-23 19:15:00
related_docs: ["FEAT-016", "RAD-005", "DSGN-001"]
---

# Bravo++ Dependency Mapping & Injection Strategy

## Overview

This document provides a complete dependency graph of all modules in the Bravo++ modular architecture, identifies potential circular dependencies, and defines injection patterns to resolve them. The central principle is **Injection Over Global Access**: no module accesses FlyWithLua globals or other modules directly — instead, the composition root (BravoMultiMode.lua) wires all dependencies together at initialization time.

## Current Dependency Graph (Existing Modules)

```
bravo++.log          ← [ROOT] No dependencies
bravo++.state        ← [LEAF] Pure state module, no dependencies
bravo++.condition_compiler  ← [LEAF] Pure parsing/evaluation, no dependencies
bravo++.debug        ← requires log
bravo++.util         ← requires log
bravo++.config       ← requires util, log, condition_compiler
bravo++.dispatch_action_map  ← requires util, log
bravo++.dispatch_buttons   ← requires util, log
bravo__.dispatch_modes     ← requires util
bravo++.dispatch_trim      ← requires log
bravo++.dispatch_twist     ← requires log
bravo++.hardware             ← requires log; FlyWithLua globals: hid_read, hid_set_nonblocking
bravo++.decoder              ← requires log, debug, state, bit (LuaJIT)
bravo++.mapbuilder           ← requires util, log
bravo++.plugincheck          ← requires log
bravo++.ui                   ← requires util; receives context table at runtime (no direct module deps)

BravoMultiMode.lua  ← requires: util, log, config, ui, MapBuilder, plugincheck, hardware, decoder, state, debug, dispatch
```

## New Module Dependency Graph

### Phase 1 Modules (LED Engine Split — CRITICAL)

| Module | Direct Dependencies | Injected At Runtime | FlyWithLua Globals Needed |
|--------|-------------------|--------------------|--------------------------|
| `led_engine` | log, util | dispatch module, button_map_leds_state, default_button_labels, bus_voltage_ref | None (pure logic after injection) |
| `led_hid_bridge` | log, util | device_handle (HID), bit library reference | None — all access via injected handle |
| `annunciator_leds` | *(none)* | annunciator_bindings (compiled conditions), led_engine.set_led callback | None — receives pre-compiled dataref bindings |
| `gear_leds` | *(none)* | gear_dataref, LED_LDG_* constants, led_engine.set_led callback | None — no direct X-Plane access |
| `switch_leds` | *(none)* | switch_bindings (compiled conditions), dispatch module, led_engine.set_led callback | None — all datarefs pre-resolved by config loader |

### Phase 2 Modules (HIGH Priority)

| Module | Direct Dependencies | Injected At Runtime | FlyWithLua Globals Needed |
|--------|-------------------|--------------------|--------------------------|
| `profiler` | log | *(none)* — fully self-contained | None |
| `config_loader` | log, util | file_provider function (wraps filesystem) | None — all I/O abstracted via injection |
| `rocker_switches` | log | dispatch_callback_fn (bravo_dispatch wrapper), num_switches count | None — command creation delegated to injected fn |
| `button_lifecycle` | log | ap_buttons array, dispatch_callback_fn | None — all callbacks routed through injection |

### Phase 3 Modules (MEDIUM Priority)

| Module | Direct Dependencies | Injected At Runtime | FlyWithLua Globals Needed |
|--------|-------------------|--------------------|--------------------------|
| `input_handlers` | log | dispatch module, decoder_handler_fn | None — wraps _G.command_once in try_catch per RAD-005 Finding 3 |
| `mode_manager` | *(none)* | dispatch module, modes_array, selection_map_labels | None — all state queries routed through injected dispatch |

## Complete Dependency Matrix (All Modules)

### Import Dependencies (static require relationships)

```
Module                          Requires
───────────────────────────────  ──────────────────────────────────────────────
log                             ← [none]
state                           ← [none]
condition_compiler              ← [none]
debug                           ← log
util                            ← log
hardware                        ← log; FlyWithLua globals: hid_read, hid_set_nonblocking
config                          ← util, log, condition_compiler
dispatch_action_map             ← util, log
dispatch_buttons                ← util, log
dispatch_modes                  ← util
dispatch_trim                   ← log
dispatch_twist                  ← log
mapbuilder                      ← util, log
plugincheck                     ← log
ui                              ← util; receives context table at runtime

# NEW modules (Phase 1)
led_engine                      ← log, util
led_hid_bridge                  ← log, util
annunciator_leds                ← [none] — pure evaluation with injected datarefs
gear_leds                       ← [none] — pure state machine with injected dataref
switch_leds                     ← [none] — pure evaluation with injected bindings

# NEW modules (Phase 2)
profiler                        ← log
config_loader                   ← util, log
rocker_switches                 ← log
button_lifecycle                ← log

# NEW modules (Phase 3)
input_handlers                  ← log
mode_manager                    ← [none] — pure state management with injected dispatch
```

### Runtime Dependency Graph (Injection-based)

```
                              Composition Root
                         (BravoMultiMode.lua / main script)
                                      │
         ┌──────────────┬─────────────┼──────────────┬──────────────┐
         ▼              ▼             ▼              ▼              ▼
    config_loader   mode_manager  input_handlers  rocker_switches  button_lifecycle
         │              │             │               │               │
         ├→ file_provider     ┌─────┴─────┐      dispatch_cb_fn   dispatch_cb_fn
         │                    │           │
         ▼                    ▼           ▼
    nav_bindings        dispatch      decoder_handler_fn
                         │
            ┌────────────┼──────────────────┐
            ▼            ▼                   ▼
     led_engine    dispatch sub-modules    mode_manager state
            │              │
            ├→ button_map  ├──► action_map (dispatch_action_map)
            │   _leds_     ├──► buttons  (dispatch_buttons)
            │   _state     ├──► modes    (dispatch_modes)
            │              ├──► trim     (dispatch_trim)
            ▼              └──► twist    (dispatch_twist)
        annunciator_leds          ▲
            │                     │
            ├→ led_engine.set_led  │
            ▼                       │
       gear_leds                    │
            │                        │
            └──→ led_engine.set_led ←┘
            │
            └──→ led_hid_bridge (device_handle, bit_lib)
                         │
                         ▼
                   Bravo HID device

        switch_leds
            │
            ├→ dispatch.get/set_rocker_switch_led
            └──→ led_engine.set_led
```

## Circular Dependency Analysis & Resolution

### Identified Potential Circularities

#### Circularity 1: `led_engine` ↔ `dispatch` (MEDIUM risk)

**Problem**:
- `led_engine` needs `dispatch.get_current_mode()` and `dispatch.get_current_selection()` to evaluate button LED states.
- `dispatch` does NOT depend on led_engine — it only manages command routing and action maps.
- However, after refactoring, the mode change handler in `mode_manager` calls back into `led_engine.prime_for_mode_change()`, creating a potential cycle if dispatch also needs to trigger LED updates.

**Resolution**:
- **Injection pattern**: `led_engine` receives `dispatch` as an injection parameter at init time — it does NOT require the dispatch module directly.
- The reverse direction (`mode_manager` → `led_engine`) is handled by passing a callback reference: `mode_manager.init({ ..., on_mode_change = led_engine.prime_for_mode_change })`.
- **No circular require()** — both modules are independent; wiring happens at composition root.

#### Circularity 2: `switch_leds` ↔ `dispatch` (LOW risk)

**Problem**:
- `switch_leds` needs `dispatch.get_rocker_switch_led()` and `dispatch.set_rocker_switch_led()` to read/write rocker switch LED states.
- `dispatch` stores rocker switch state in its own internal state table (`rocker_switch_led_states`).

**Resolution**:
- **Injection pattern**: `switch_leds.init({ dispatch_module })` — receives the dispatch module as a parameter, not via require().
- The dispatch module does NOT depend on switch_leds. It only stores and provides accessor functions for rocker switch state.
- No circular dependency exists; this is a unidirectional dependency resolved by injection.

#### Circularity 3: `mode_manager` ↔ `led_engine` (LOW risk)

**Problem**:
- `mode_manager.cycle_mode_up/down()` needs to trigger LED state priming after mode changes.
- If `mode_manager` required `led_engine`, and `led_engine` somehow needed `mode_manager`, a cycle would form.

**Resolution**:
- **Callback injection pattern**: `mode_manager.init({ ..., on_state_change = function() led_engine.prime_for_mode_change(); led_engine.clear_dirty() end })`.
- The callback is a plain Lua function — no module reference required. This breaks any potential circularity at the type system level.

#### Circularity 4: `input_handlers` ↔ `dispatch_twist` (LOW risk)

**Problem**:
- `input_handlers.handle_twist()` needs to call twist knob commands that were previously handled by dispatch_twist's internal logic.
- If input_handlers required dispatch_twist directly, and dispatch_twist needed input_handlers for decoder events, a cycle would form.

**Resolution**:
- **Injection pattern**: `input_handlers.init({ dispatch_module })` — receives the full dispatch facade, which already includes twist knob resolution via its sub-modules.
- The `_G.command_once` bypass (RAD-005 Finding 3) is resolved by wrapping in try_catch within input_handlers itself — no dependency on dispatch_twist's internal implementation needed.

### Dependency Hierarchy (Acyclic DAG)

```
Level 0 (LEAF — No dependencies):
    log, state, condition_compiler

Level 1 (Depends only on Level 0):
    debug ← log
    util ← log
    profiler ← log
    annunciator_leds ← [none]
    gear_leds ← [none]
    switch_leds ← [none]

Level 2 (Depends on Levels 0-1):
    config ← util, log, condition_compiler
    dispatch_action_map ← util, log
    dispatch_buttons ← util, log
    dispatch_modes ← util
    dispatch_trim ← log
    dispatch_twist ← log
    hardware ← log; FlyWithLua globals (not a Lua module dep)
    mapbuilder ← util, log
    plugincheck ← log
    ui ← util

Level 3 (Depends on Levels 0-2):
    led_engine ← log, util + injected dispatch
    led_hid_bridge ← log, util + injected device_handle
    config_loader ← util, log + injected file_provider
    rocker_switches ← log + injected dispatch_callback_fn
    button_lifecycle ← log + injected dispatch_callback_fn

Level 4 (Depends on Levels 0-3):
    mode_manager ← [none] + injected dispatch module
    input_handlers ← log + injected dispatch module

Level 5 (COMPOSITION ROOT — Wires everything together):
    BravoMultiMode.lua (main script)
```

## Injection Point Catalogue

### Composition Root Wiring Diagram

The composition root (BravoMultiMode.lua after refactoring) is responsible for:
1. Loading all modules via `require()`
2. Calling each module's `.init(opts)` with the correct dependencies
3. Registering dispatch callbacks that route FlyWithLua string callbacks to modular code

```lua
-- Composition Root Wiring Pseudocode (after refactoring)

-- 1. Load core modules (existing)
local util = require("bravo++.util")
local log = require("bravo++.log")
local config = require("bravo++.config")
local dispatch = require("bravo++.dispatch")

-- 2. Load new Phase 1 modules
local led_engine = require("bravo++.led_engine")
local led_hid_bridge = require("bravo++.led_hid_bridge")
local annunciator_leds = require("bravo++.annunciator_leds")
local gear_leds = require("bravo++.gear_leds")
local switch_leds = require("bravo++.switch_leds")

-- 3. Load new Phase 2 modules
local profiler = require("bravo++.profiler")
local config_loader = require("bravo++.config_loader")
local rocker_switches = require("bravo++.rocker_switches")
local button_lifecycle = require("bravo++.button_lifecycle")

-- 4. Load new Phase 3 modules
local input_handlers = require("bravo++.input_handlers")
local mode_manager = require("bravo++.mode_manager")

-- 5. Open HID device (FlyWithLua global)
local bravo = hid_open(0x294B, 0x1901)

-- 6. Initialize modules in dependency order

-- Phase 1: LED Engine Split
led_engine.init({
    dispatch = dispatch,
    button_map_leds_state = button_map_leds_state,
    default_button_labels = default_button_labels,
    bus_voltage_ref = dataref_table("sim/cockpit2/electrical/bus_volts"),
})

-- Inject sub-module callbacks into led_engine for orchestration
led_engine.set_sub_handlers({
    on_annunciator_row1 = function() annunciator_leds.evaluate_row1(led_engine) end,
    on_annunciator_row2 = function() annunciator_leds.evaluate_row2(led_engine) end,
    on_gear = function() gear_leds.evaluate(led_engine) end,
    on_switches = function() switch_leds.evaluate(led_engine) end,
})

-- HID bridge receives the device handle (injected, not global)
led_hid_bridge.init({
    device_handle = bravo,
    bit_lib = bit,  -- LuaJIT built-in
})

-- Annunciator LEDs receive pre-compiled bindings from config loader
annunciator_leds.init({
    annunciator_bindings = build_annunciator_bindings(nav_bindings),
})

-- Gear LEDs receive gear dataref and LED constants
gear_leds.init({
    gear_dataref = gear,  -- resolved from nav_bindings["GEAR_DEPLOYMENT_LED"]
    led_constants = {
        LED_LDG_N_GREEN = {2,3}, LED_LDG_N_RED = {2,4},
        LED_LDG_L_GREEN = {2,1}, LED_LDG_L_RED = {2,2},
        LED_LDG_R_GREEN = {2,5}, LED_LDG_R_RED = {2,6},
    },
})

-- Switch LEDs receive switch bindings and dispatch module
switch_leds.init({
    switch_bindings = build_switch_bindings(nav_bindings),
    dispatch_module = dispatch,
})

-- Phase 2: High Priority Extractions
profiler.init({ enabled = false, log_interval = 60 })

config_loader.init({
    file_provider = function(path) return util.file_exists(path) end,
})

rocker_switches.init({
    dispatch_callback_fn = function(name, ...) bravo_dispatch(name, ...) end,
    num_switches = 7,
})

button_lifecycle.init({
    ap_buttons = { /* from config */ },
    dispatch_callback_fn = function(name, ...) bravo_dispatch(name, ...) end,
})

-- Phase 3: Medium Priority Extractions
input_handlers.init({
    dispatch_module = dispatch,
    decoder_handler_fn = function(event_type, value)
        -- route to appropriate handler
    end,
})

mode_manager.init({
    dispatch_module = dispatch,
    modes_array = modes,
    selection_map_labels = selection_map_labels,
    on_state_change = function()
        led_engine.prime_for_mode_change()
        led_engine.clear_dirty()
    end,
})
```

### Injection Parameter Summary Table

| Module | Required Injection Parameters | Optional Injection Parameters | Default Values |
|--------|------------------------------|-------------------------------|----------------|
| `led_engine` | dispatch, button_map_leds_state, default_button_labels | bus_voltage_ref | nil (bus voltage defaults to 0) |
| `led_hid_bridge` | device_handle, bit_lib | *(none)* | Error on missing required params |
| `annunciator_leds` | annunciator_bindings | *(none)* | Error if bindings empty |
| `gear_leds` | gear_dataref, led_constants | *(none)* | Fixed-gear behavior if gear_dataref is nil |
| `switch_leds` | switch_bindings, dispatch_module | *(none)* | No-op for switches without bindings |
| `profiler` | *(none — self-contained)* | enabled (bool), log_interval (int) | enabled=false, interval=60s |
| `config_loader` | file_provider function | aircraft_dir string | nil (uses MODULES_DIRECTORY constant) |
| `rocker_switches` | dispatch_callback_fn | num_switches (int) | 7 switches |
| `button_lifecycle` | ap_buttons array, dispatch_callback_fn | *(none)* | Error if either missing |
| `input_handlers` | dispatch_module, decoder_handler_fn | *(none)* | Error if either missing |
| `mode_manager` | dispatch_module, modes_array, selection_map_labels | on_state_change callback | nil (no action on state change) |

## FlyWithLua Global Entry Points — What Must Remain Global

The following functions MUST remain as global variables because FlyWithLua's string-callback execution model resolves them in the global environment:

| Function | Module | Forwarding Target | Notes |
|----------|--------|-------------------|-------|
| `bravo_dispatch` | Main script (bridge) | dispatch_callbacks table → modular code | Central hub; receives name + varargs, looks up callback, executes with try_catch |
| `build_bravo_gui` | Main script (bridge) | dispatch_callbacks.build_bravo_gui → ui.build_gui() | Receives wnd, x, y from FlyWithLua float_wnd_set_imgui_builder |
| `on_close_floating_window` | Main script (bridge) | dispatch_callbacks.on_close_floating_window → ui.on_close() | Receives wnd handle for cleanup |

All other functions are called indirectly through bravo_dispatch and do NOT need to be global. This eliminates the forward-declaration anti-pattern identified in RAD-005 Finding 2.

## Risk Assessment: Circular Dependencies

| Potential Cycle | Severity | Resolution Strategy | Verification Method |
|----------------|----------|--------------------|---------------------|
| led_engine ↔ dispatch | MEDIUM | Injection pattern — no require() between them; wiring at composition root | Static analysis: verify no `require("bravo++.dispatch")` inside led_engine.lua |
| switch_leds ↔ dispatch | LOW | Same injection pattern as above | Verify dispatch is passed as parameter, not required |
| mode_manager ↔ led_engine | LOW | Callback function injection — plain Lua closure, no module reference | Verify on_state_change is a function, not a module reference |
| input_handlers ↔ dispatch_twist | LOW | Input handlers use dispatch facade (not dispatch_twist directly) | Verify only dispatch.lua is injected, not sub-modules |
