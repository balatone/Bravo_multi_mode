---
id: REVIEW-018
title: Review of FEAT-017 — LED Engine Modularization
version: 1.2.0
status: IN_REVIEW
created: 2026-07-24 13:01:29
updated: 2026-07-24 13:15:00
verdict: REQUEST_CHANGES
related_docs: []
---
# Executive Summary

This review covers the implementation of FEAT-017 (LED Engine Modularization), which splits the ~640-line monolithic LED engine block from `BravoMultiMode.lua` into five focused modules under `FlyWithLua/Modules/bravo++/`: `led_engine.lua`, `led_hid_bridge.lua`, `annunciator_leds.lua`, `gear_leds.lua`, and `switch_leds.lua`. The review also covers the modified composition root in `BravoMultiMode.lua` that wires all dependencies via injection.

The modularization architecture is sound: dependency injection is correctly applied, module encapsulation follows the `local M = {} ... return M` pattern, FlyWithLua string-callback integrity is preserved through the `bravo_dispatch` facade, and no new global variable pollution was introduced. However, **two blocking issues** prevent approval — `switch_leds.lua` was created based on a misinterpretation that rocker switches have physical LEDs (they do not), leading to an unnecessary module with incorrect functionality; additionally, annunciator LED_POSITIONS and ROW1_LABELS are both wrong (F-002).

## Key Takeaway

The four-module split (`led_engine`, `led_hid_bridge`, `annunciator_leds`, `gear_leds`) correctly implements dependency injection and FlyWithLua integration, but **`switch_leds.lua` must be removed entirely** — rocker switches on the Bravo hardware have no physical LEDs. The original code's switch state management serves only UI display purposes (ImGui context), not HID report generation. Annunciator LED_POSITIONS and ROW1_LABELS also need correction to match the physical layout (F-002).

# Review Scope

## In Scope
- **Four new modules**: `led_engine.lua`, `led_hid_bridge.lua`, `annunciator_leds.lua`, `gear_leds.lua` under `FlyWithLua/Modules/bravo++/`.
- **Composition root**: Modified `BravoMultiMode.lua` wiring all dependencies via injection.
- **Requirements alignment**: FEAT-017 feature spec, DSGN-001 module interface specification, DSGN-002 dependency mapping/injection strategy.
- **Lua best practices compliance**: Module organization, scoping/visibility, LED/HID communication cycle, DataRef interaction, performance constraints (from `docs/lua-best-practices.md`).

## Out of Scope
- FEAT-018 (Profiler extraction), FEAT-019 (Input Handlers / Mode Manager), FEAT-020 (Export pattern standardization).
- Integration test execution — qualitative analysis only.
- FlyWithLua host application or X-Plane integration contract changes.
- **`switch_leds.lua`**: Removed from scope after discovering rocker switches have no physical LEDs on Bravo hardware.

# Design Error Propagation Analysis

## Root Cause: Misinterpretation of `handle_rocker_switch_led_changes()`

The original monolithic code in `BravoMultiMode.lua` (commit `24cfca7`) contains a function called `handle_rocker_switch_led_changes()`. This function was **misinterpreted** by RAD-005 as managing "rocker switch LEDs" when it actually manages **switch position state for UI display purposes only**.

### Original Code Behavior
```lua
local function handle_rocker_switch_led_changes()
    for i = 1, 7 do
        local switch_label_key = "SWITCH" .. i .. "_LED"
        -- Reads dataref → stores state via dispatch.set_rocker_switch_led()
        if dispatch.get_rocker_switch_led(switch_label_key) ~= current_state_from_dataref then
            dispatch.set_rocker_switch_led(switch_label_key, current_state_from_dataref)
            led_state_modified = true  ← triggers HID update (but switch state not sent to HID)
        end
    end
end
```

The `dispatch.rocker_switch_led_states` table is consumed by:
- **UI display**: `get_led_state_for_switch()` → used in ImGui to show switch positions
- **State tracking**: Maintains current switch position for context-aware UI rendering

**Neither of these requires writing to the LED engine buffer or sending HID feature reports.** The function name "rocker_switch_led_changes" is misleading — it tracks switch *position state*, not physical LED indicators.

### Error Propagation Chain

| Document | Statement | Impact |
|----------|-----------|--------|
| **RAD-005** (Modular Architecture Analysis) | "The LED engine (~640 lines)... bundles button LEDs, gear LEDs, annunciator LEDs, **rocker switch LEDs**..." | Introduced the misconception that rocker switches have physical LEDs requiring modularization |
| **FEAT-017** (LED Engine Modularization) | Recommended splitting into 5 sub-modules including `switch_leds.lua` for "Rocker switch LEDs" | Implemented the incorrect assumption, creating unnecessary module with wrong functionality |
| **DSGN-001/002** (Module Interface Specs) | Defined public API for `switch_leds.lua` based on LED buffer writes | Codified the design error into interface specifications |

### Hardware Reality Check

The Honeycomb Bravo hardware has:
- ✅ 7 rocker switches with **no physical LEDs** — they are mechanical toggle switches only
- ✅ Button array with individual LEDs (Bank 1)
- ✅ Annunciator/gear LED indicators (Banks 2–4)

There is no hardware basis for "rocker switch LEDs" in the Bravo design. The original code's `handle_rocker_switch_led_changes()` was managing software UI state, not controlling any physical indicators.

### Required Action

**Remove `switch_leds.lua` entirely from FEAT-017 scope.** The switch position management that exists in the dispatch module (`rocker_switch_led_states`) serves only UI display purposes and should remain as-is — it does not need LED engine integration or HID report generation.

# Review Criteria

| Criterion | Standard Referenced |
|-----------|-------------------|
| **Functional Correctness** | FEAT-017 acceptance criteria, DSGN-001 public API specs for all 5 modules |
| **Lua Best Practices** | `docs/lua-best-practices.md` — module organization, scoping, LED/HID cycle, DataRef nil guards, hot-path performance |
| **Dependency Injection** | DSGN-002 injection strategy — no global access, all deps passed via init() opts |
| **API Integrity** | DSGN-001 public API signatures and behaviors match implementation |
| **FlyWithLua Callbacks** | String-callback resolution through `bravo_dispatch` facade preserved |

# Findings Summary

The review identified:
- **1 design error** (blocking) — `switch_leds.lua` created based on false premise that rocker switches have physical LEDs.
- **2 functional defects** (both blocking) — annunciator LED_POSITIONS and ROW1_LABELS are both incorrect (F-002); switch_leds.lua unnecessary.
- **4 best-practice issues** — hot-path table allocations in gear_leds and led_hid_bridge, unused import, get_buffer() breaking encapsulation.
- **3 performance concerns** — same hot-path allocations noted above plus API signature divergence from spec.

# Required Changes Before Approval

## Blockers

### F-002: Annunciator LED_POSITIONS and ROW1_LABELS Both Incorrect (HIGH) — **BLOCKER**
**File**: `FlyWithLua/Modules/bravo++/annunciator_leds.lua`
Two compounding errors exist in the original monolithic code that were inherited by the refactored module. The Bravo hardware physical layout is:

| Row | Physical Annunciators (7 each) | Correct LED_POSITIONS |
|-----|-------------------------------|----------------------|
| **Row 1** (Bank 2) | MASTER WARNING, ENGINE FIRE, LOW OIL PRESSURE, LOW FUEL PRESSURE, ANTI-ICE, STARTER ENGAGED, APU | `{2,1}`–`{2,7}` |
| **Row 2** (Bank 3) | MASTER CAUTION, VACUUM, LOW HYD PRESSURE, AUX FUEL PUMP, PARKING BRAKE, LOW VOLTS, DOOR | `{3,1}`–`{3,7}` |

The current `annunciator_leds.lua` has these errors:
- **LED_POSITIONS wrong**: MASTER_WARNING={2,7}, FIRE_WARNING={2,8} — only 2 items on Bank 2 when all 7 Row 1 annunciators should be there. OIL_LOW_PRESSURE through APU mapped to Bank 3 instead of Bank 2.
- **ROW1_LABELS incomplete**: Only contains `MASTER_WARNING`, `FIRE_WARNING` but should contain all 7 Row 1 annunciators (OIL_LOW_PRESSURE through APU are missing).
- **ROW2_LABELS incorrect**: Includes OIL_LOW_PRESSURE, FUEL_LOW_PRESSURE, ANTI_ICE, STARTER_ENGAGED, APU — these belong on Row 1, not Row 2.

**Impact**: `evaluate_row1()` writes to Bank 2 positions {2,7} and {2,8} for only 2 items (MASTER_WARNING, FIRE_WARNING), while the remaining 5 Row 1 annunciators are evaluated by `evaluate_row2()` writing to wrong bank positions — causing LEDs on completely wrong physical indicators.

**Required Fix**: Correct LED_POSITIONS to map all 7 Row 1 annunciators to Bank 2 `{2,1}`–`{2,7}`, all 7 Row 2 items to Bank 3 `{3,1}`–`{3,7}`, and fix ROW1_LABELS/ROW2_LABELS accordingly.

## Major Issues

### F-003: `led_hid_bridge.assemble_and_send()` API Signature Deviates from DSGN-001 (MEDIUM)
**File**: `FlyWithLua/Modules/bravo++/led_hid_bridge.lua`, lines ~82–95
DSGN-001 specifies signature as `(buffer_ref, default_button_labels, dispatch_module)` but implementation adds two extra params: `button_map_leds_state` and `led_engine_module`. The wiring in BravoMultiMode.lua passes `led_engine` (not `dispatch`) as the 5th argument.

**Required Fix**: Align spec with implementation or adjust implementation to match DSGN-001 signature exactly.

## Minor Issues

### BP-004: `get_buffer()` Breaks Encapsulation (LOW)
**File**: `FlyWithLua/Modules/bravo++/led_engine.lua`, lines ~278–283
Returns raw internal buffer, allowing external code to bypass dirty-flag logic. DSGN-001 states the buffer is "NOT shared directly with sub-modules."

### BP-005: Unused `log` Import in `gear_leds.lua` (MINOR)
**File**: `FlyWithLua/Modules/bravo++/gear_leds.lua`, line 12
`local log = require("bravo++.log")` is imported but never used.

# Positive Findings

- **Dependency injection correctly implemented**: All four active modules receive dependencies via init() opts — no global access patterns.
- **Module encapsulation clean**: Each module uses `local M = {} ... return M`; private state lives in closure variables; no implicit global leakage.
- **FlyWithLua callback integrity preserved**: All three string-callback entrypoints (`bravo_dispatch('handle_led_changes_task')`, `build_bravo_gui`, `on_close_floating_window`) resolve correctly through the dispatch facade.
- **Buffer encapsulation well-designed**: `led_engine.set_led()` centralizes dirty-flag logic; sub-modules write via this API rather than direct buffer access (except for the hid_bridge which needs raw data).
- **Pre-registered sub-handler callbacks**: `set_sub_handlers()` stores callbacks in closure scope, enabling zero-allocation hot path invocation.
- **Error handling with pcall**: Sub-handler invocations wrapped in pcall with error logging per best practices.

# Verification Results

| Check | Method | Result |
|-------|--------|--------|
| Module existence and placement | File system inspection under `FlyWithLua/Modules/bravo++/` | ✅ 4 modules present (switch_leds.lua removed from scope) |
| Export pattern compliance (`local M = {} ... return M`) | Source code review of all 4 active files | ✅ Compliant across all modules |
| No implicit global leakage | Scanned for unqualified assignments outside `M.` methods | ✅ Clean — only FlyWithLua globals via luacheck ignore in hid_bridge |
| Dependency injection completeness | Compared init() opts against DSGN-001 injection point tables | ✅ All required deps injected; eval_fn correctly passed to annunciator/gear modules |
| Public API vs DSGN-001 spec alignment | Side-by-side comparison of each module's exported functions with DSGN-001 tables | ⚠️ 2 deviations (F-003 signature, F-002 LED_POSITIONS/ROW1_LABELS incorrect) |
| FlyWithLua string-callback resolution | Traced callback strings through bravo_dispatch to implementations | ✅ All callbacks resolve correctly |
| Hot-path allocation analysis | Inspected evaluate() and handle_led_changes() for table/string allocations per invocation | ⚠️ 2 allocations found in gear_leds and led_hid_bridge (BP-001, BP-003) |

# Risks / Follow-ups

- **HID output parity**: Byte-level comparison of HID feature reports across all four aircraft configurations (B58, C90B, DA42, Transponder) has not been verified. This should be the primary gate after removing `switch_leds.lua` and correcting F-002 (annunciator LED_POSITIONS/ROW1_LABELS).
- **Switch state management preservation**: Ensure that removing `switch_leds.lua` does not break the existing switch position tracking in `dispatch.rocker_switch_led_states`, which is used by ImGui UI context for displaying switch positions.
- **Performance regression baseline**: After fixes, profile the hot path (handle_led_changes + assemble_and_send) against pre-refactoring baseline to confirm no measurable regression in the 0.25s LED update loop.

# Supporting Materials / Evidence

## Module Dependency Injection Verification Matrix

| Module | Dependencies Injected? | Globals Accessed? |
|--------|----------------------|------------------|
| `led_engine` | ✅ dispatch, button_map_leds_state, default_button_labels, bus_voltage_ref | ❌ None |
| `led_hid_bridge` | ✅ device_handle, bit_lib | ⚠️ `hid_send_filled_feature_report` (FlyWithLua global; guarded by luacheck ignore) |
| `annunciator_leds` | ✅ annunciator_bindings, eval_fn | ❌ None |
| `gear_leds` | ✅ gear_dataref, led_constants | ❌ None |

## FlyWithLua Callback Resolution Map

| Callback String | Resolution Path | Status |
|----------------|----------------|--------|
| `bravo_dispatch('handle_led_changes_task')` | bravo_dispatch → handle_led_changes → led_engine.handle_led_changes() + send_hid_data() | ✅ Preserved |
| `build_bravo_gui(wnd, x, y)` | bravo_dispatch → ui.build_gui(build_ui_context()) with get_button_led_state from led_engine | ✅ Preserved |
| `on_close_floating_window(my_floating_wnd)` | bravo_dispatch → on_close_floating_window_impl (uses hid_close, bravo) | ✅ Preserved |

## API Integrity Comparison Against DSGN-001

| Module | Spec Function | Implemented? | Signature Match? | Notes |
|--------|--------------|-------------|-----------------|-------|
| `led_engine` | init(opts), set_sub_handlers(), set_led, get_led, all_off, prime_for_mode_change, is_dirty, clear_dirty, handle_led_changes, get_bus_voltage | ✅ All present | ⚠️ handle_led_changes opts table differs from spec (adds button_map_leds fields) | Functionally correct |
| `led_hid_bridge` | init(), assemble_and_send(), assemble_report() | ✅ All present | ❌ Extra params beyond DSGN-001 spec | See F-003 |
| `annunciator_leds` | init(), evaluate_row1, evaluate_row2, evaluate_all | ✅ All present | ❌ LED_POSITIONS and ROW1_LABELS incorrect (F-002) | Blocking defect |
| `gear_leds` | init(), evaluate, get_gear_state | ✅ All present | ✅ Matches spec | Clean |
