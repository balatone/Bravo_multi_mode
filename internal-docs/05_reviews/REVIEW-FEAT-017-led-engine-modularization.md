---
id: REVIEW-FEAT-017
title: Review of FEAT-017 — LED Engine Modularization
version: 1.0.0
status: REQUEST_CHANGES
created: 2026-07-24 12:35:00
reviewer: reviewer (specialist subagent)
related_docs: ["FEAT-017-led-engine-modularization.md", "DSGN-001-bravo-module-interface-specification.md", "DSGN-002-bravo-dependency-mapping-injection-strategy.md", "lua-best-practices.md"]
---

# REVIEW-FEAT-017: LED Engine Modularization — Verdict: **REQUEST_CHANGES**

## Executive Summary

The five new modules (`led_engine.lua`, `led_hid_bridge.lua`, `annunciator_leds.lua`, `gear_leds.lua`, `switch_leds.lua`) and the modified `BravoMultiMode.lua` composition root demonstrate a solid understanding of modularization principles. The dependency injection pattern is correctly applied, module encapsulation is generally well-maintained, and FlyWithLua string-callback integration is preserved through the `bravo_dispatch` facade.

However, **two functional defects** prevent approval:
1. `switch_leds.evaluate()` does not write evaluated states to the LED engine buffer (violates DSGN-001 spec).
2. Annunciator row label ordering in `annunciator_leds.lua` is inconsistent with the physical LED position mapping, which will cause annunciators to be written to incorrect bank/bit positions at runtime.

Additionally, several **best-practice and performance issues** should be addressed before merge.

---

## 1. Functional Issues (Blocking)

### F-001: `switch_leds.evaluate()` Does Not Write to LED Engine Buffer
**Severity**: HIGH
**File**: `FlyWithLua/Modules/bravo++/switch_leds.lua`, lines ~85–107

The `evaluate()` function evaluates each rocker switch's dataref condition and updates the dispatch module via `set_rocker_switch_led()`, but **never calls `led_engine_module.set_led()`** to write the evaluated state into the LED buffer. This means:
- Switch LEDs will never appear in the HID report sent by `led_hid_bridge`.
- The `_led_engine_module` parameter is accepted (for API consistency) but completely unused — a dead parameter.

**DSGN-001 Compliance**: DSGN-001 explicitly states that `M.evaluate(led_engine_module)` "calls `led_engine_module.set_led()` for the corresponding buffer position." This requirement is not met.

**Required Fix**: The function needs to know which bank/bit positions correspond to each switch LED and call `set_led()`. For example:
```lua
-- In evaluate(), after determining current_state:
local led_pos = SWITCH_LED_POSITIONS[switch_label]  -- {bank, bit} mapping needed
if led_pos then
    led_engine_module.set_led(led_pos[1], led_pos[2], current_state)
end
```

### F-002: Annunciator Row Label Ordering Mismatch with LED Positions
**Severity**: HIGH
**File**: `FlyWithLua/Modules/bravo++/annunciator_leds.lua`, lines ~38–54

The ROW1_LABELS and ROW2_LABELS arrays do not match the physical LED position mapping in LED_POSITIONS:

| Label | LED_POSITIONS bank/bit | Expected Row | In ROW1? | In ROW2? |
|-------|----------------------|--------------|----------|----------|
| MASTER_WARNING | {2, 7} | Row 1 (Bank 2) | ✅ | |
| FIRE_WARNING | {2, 8} | Row 1 (Bank 2) | ✅ | |
| OIL_LOW_PRESSURE | {3, 1} | **Row 2** (Bank 3) | ❌ Listed in ROW1 | ✅ |
| FUEL_LOW_PRESSURE | {3, 2} | **Row 2** (Bank 3) | ❌ Listed in ROW1 | ✅ |
| ANTI_ICE | {3, 3} | **Row 2** (Bank 3) | ❌ Listed in ROW1 | ✅ |
| STARTER_ENGAGED | {3, 4} | **Row 2** (Bank 3) | ❌ Listed in ROW1 | ✅ |
| APU | {3, 5} | **Row 2** (Bank 3) | ❌ Listed in ROW1 | ✅ |
| MASTER_CAUTION | {3, 6} | Row 2 (Bank 3) | | ✅ |
| VACUUM | {3, 7} | Row 2 (Bank 3) | | ✅ |
| HYD_LOW_PRESSURE | {3, 8} | Row 2 (Bank 3) | | ✅ |
| AUX_FUEL_PUMP | {4, 1} | Row 2 (Bank 4) | | ✅ |
| PARKING_BRAKE | {4, 2} | Row 2 (Bank 4) | | ✅ |
| VOLTS_LOW | {4, 3} | Row 2 (Bank 4) | | ✅ |
| DOOR | {4, 4} | Row 2 (Bank 4) | | ✅ |

**Impact**: `evaluate_row1()` will write OIL_LOW_PRESSURE through APU to Bank 2 positions instead of their correct Bank 3 positions. This causes annunciator LEDs to light on the wrong physical indicators.

**Required Fix**: Move OIL_LOW_PRESSURE, FUEL_LOW_PRESSURE, ANTI_ICE, STARTER_ENGAGED, and APU from ROW1_LABELS to ROW2_LABELS:
```lua
local ROW1_LABELS = { "MASTER_WARNING", "FIRE_WARNING" }
local ROW2_LABELS = {
    "OIL_LOW_PRESSURE", "FUEL_LOW_PRESSURE", "ANTI_ICE",
    "STARTER_ENGAGED", "APU", "MASTER_CAUTION", "VACUUM",
    "HYD_LOW_PRESSURE", "AUX_FUEL_PUMP", "PARKING_BRAKE",
    "VOLTS_LOW", "DOOR",
}
```

### F-003: `led_hid_bridge.assemble_and_send()` API Signature Deviates from DSGN-001
**Severity**: MEDIUM
**File**: `FlyWithLua/Modules/bravo++/led_hid_bridge.lua`, lines ~82–95

DSGN-001 specifies the signature as:
```lua
M.assemble_and_send(buffer_ref, default_button_labels, dispatch_module)
```

The implementation adds two extra parameters:
```lua
M.assemble_and_send(buffer_ref, default_button_labels, dispatch_module, button_map_leds_state, led_engine_module)
```

While this is functionally more complete (it passes `button_map_leds_state` and `led_engine_module`), it creates a spec-implementation mismatch. The DSGN-001 table also shows that `assemble_and_send` should call `dispatch_module.clear_dirty()` on the led_engine module, but the implementation calls `led_engine_module.clear_dirty()` directly — which works because BravoMultiMode.lua passes `led_engine` as the fifth parameter instead of `dispatch`.

**Required Fix**: Either update DSGN-001 to match the implementation or adjust the implementation to match the spec. The current wiring in BravoMultiMode.lua passes `led_engine` (not `dispatch`) as the 5th argument, which means the function signature is effectively:
```lua
M.assemble_and_send(buffer_ref, default_button_labels, dispatch_module, button_map_leds_state, led_engine_module)
```

---

## 2. Best Practices Issues

### BP-001: `gear_leds.lua` Allocates Tables in Hot Path
**Severity**: MEDIUM
**File**: `FlyWithLua/Modules/bravo++/gear_leds.lua`, lines ~58–67

The `evaluate()` and `get_gear_state()` functions allocate new tables on every invocation:
```lua
local channel_indices = { 0, 1, 2 }   -- allocated per call
local led_keys = { ... }              -- allocated per call (9 elements)
```

Per `lua-best-practices.md`, the hot path must perform zero heap allocations. These arrays are constant and should be module-level constants:
```lua
-- Module level (allocated once at load time):
local CHANNEL_INDICES = { 0, 1, 2 }
local LED_KEYS = { "LED_LDG_N_GREEN", ... }

function M.evaluate(led_engine_module)
    -- Use CHANNEL_INDICES and LED_KEYS directly — no allocation
end
```

### BP-002: `annunciator_leds.lua` Missing eval_fn Nil Validation in init()
**Severity**: LOW
**File**: `FlyWithLua/Modules/bravo++/annunciator_leds.lua`, lines ~73–84

The `init()` function logs a warning for missing `annunciator_bindings` but does **not** log an error or reject initialization when `eval_fn` is nil. However, the code at line 62 (`return eval_fn(dataref, condition)`) will crash if `eval_fn` is nil and any annunciator evaluation occurs.

The current check (line ~80-81) does validate that `eval_fn` is required:
```lua
if not eval_fn then
    log.error("annunciator_leds: eval_fn is required")
end
```
This is correct — no action needed here. **Marking as informational only.**

### BP-003: `led_hid_bridge.lua` Allocates Table in Hot Path
**Severity**: LOW
**File**: `FlyWithLua/Modules/bravo++/led_hid_bridge.lua`, lines ~72–80

The `assemble_report()` function allocates a new table on every call:
```lua
local data = {}  -- allocated per invocation
for bank = 1, 4 do
    data[bank] = 0
end
```

This is called from `assemble_and_send()`, which runs in the hot path (every 0.25s). Per best practices, this should be pre-allocated or use a fixed-size pattern:
```lua
local M = {}
-- Pre-allocate at module load time
local report_data = { 0, 0, 0, 0 }

function M.assemble_report(...)
    -- Reset and reuse the pre-allocated table
    for bank = 1, 4 do report_data[bank] = 0 end
    -- ... populate report_data ...
    return report_data
end
```

### BP-004: `led_engine.lua` — `get_buffer()` Breaks Encapsulation
**Severity**: LOW
**File**: `FlyWithLua/Modules/bravo++/led_engine.lua`, lines ~278–283

The `M.get_buffer()` function returns the raw internal buffer table, allowing external code to read/write it directly without going through `set_led()`. This bypasses dirty-flag logic and breaks encapsulation.

DSGN-001 states: "The LED buffer is internal to led_engine.lua and is NOT shared directly with sub-modules." However, `led_hid_bridge.assemble_and_send()` needs access to the raw buffer for HID report assembly.

**Recommended Fix**: Either (a) add a dedicated `M.get_buffer_snapshot()` that returns a shallow copy, or (b) have `led_hid_bridge` use per-bit getters (`get_led(bank, bit)`). Option (a) is preferred since it's simpler and the buffer is only read during HID assembly.

### BP-005: `gear_leds.lua` Imports log but Never Uses It
**Severity**: MINOR
**File**: `FlyWithLua/Modules/bravo++/gear_leds.lua`, line 12

```lua
local log = require("bravo++.log")
-- ... no subsequent use of `log` in the file
```

This is a dead import that adds unnecessary module load overhead. Remove it or add logging for debugging purposes (e.g., when gear_dataref is nil).

---

## 3. Performance Issues

### P-001: Hot Path Table Allocations in `gear_leds.evaluate()` and `get_gear_state()`
**Severity**: MEDIUM
**File**: `FlyWithLua/Modules/bravo++/gear_leds.lua`

As noted in BP-001, both functions allocate two tables per invocation (`channel_indices` and `led_keys`). Since `evaluate()` runs every 0.25 seconds as part of the LED update loop, this creates unnecessary GC pressure over time.

**Fix**: Promote to module-level constants (see BP-001).

### P-002: Hot Path Table Allocation in `led_hid_bridge.assemble_report()`
**Severity**: LOW
**File**: `FlyWithLua/Modules/bravo++/led_hid_bridge.lua`

The `data = {}` allocation on every call to `assemble_and_send()`. While the table is small (4 elements), it still triggers GC in long-running sessions.

**Fix**: Pre-allocate at module level and reuse (see BP-003).

### P-003: `handle_button_led_changes()` Uses pcall Wrapper — Acceptable but Noted
**Severity**: INFORMATIONAL
**File**: `FlyWithLua/Modules/bravo++/led_engine.lua`, lines ~245–271

The `pcall` wrapper in `handle_led_changes()` adds a small overhead per call. This is acceptable and follows the error-handling best practices from `lua-best-practices.md`. No action needed, but worth noting that if profiling shows this as a bottleneck, it could be removed for release builds.

---

## 4. Dependency Injection Verification

| Module | Dependencies Injected? | Globals Accessed? | Notes |
|--------|----------------------|------------------|-------|
| `led_engine` | ✅ dispatch, button_map_leds_state, default_button_labels, bus_voltage_ref | ❌ None | Clean injection |
| `led_hid_bridge` | ✅ device_handle, bit_lib | ⚠️ `hid_send_filled_feature_report` (FlyWithLua global) | Expected — FlyWithLua API; guarded by luacheck directive |
| `annunciator_leds` | ✅ annunciator_bindings, eval_fn | ❌ None | Clean injection |
| `gear_leds` | ✅ gear_dataref, led_constants | ❌ None | Clean injection |
| `switch_leds` | ✅ switch_bindings, dispatch_module, eval_fn | ❌ None | Clean injection |

**Verdict**: Dependency injection is correctly implemented across all five modules. The only FlyWithLua global access is in `led_hid_bridge.lua`, which uses the standard luacheck ignore pattern for `hid_send_filled_feature_report`.

---

## 5. API Integrity Verification Against DSGN-001

| Module | Spec Function | Implemented? | Signature Match? | Notes |
|--------|--------------|-------------|-----------------|-------|
| `led_engine` | `init(opts)` | ✅ | ⚠️ Added `bus_voltage_ref` beyond spec | Acceptable extension |
| `led_engine` | `set_sub_handlers()` | ✅ | ✅ | Matches spec exactly |
| `led_engine` | `set_led(bank, bit, state)` | ✅ | ✅ | Matches spec |
| `led_engine` | `get_led(bank, bit)` | ✅ | ✅ | Returns nil if not initialized (spec compliant) |
| `led_engine` | `all_off()` | ✅ | ✅ | Includes dispatch rocker switch handling per spec |
| `led_engine` | `prime_for_mode_change()` | ✅ | ✅ | Falls back to all_off() when no LEDs detected (per spec) |
| `led_engine` | `is_dirty()` / `clear_dirty()` | ✅ | ✅ | Matches spec |
| `led_engine` | `handle_led_changes(opts)` | ✅ | ⚠️ opts table differs from spec | Spec says `{ bus_voltage, master_state_ref }`; implementation uses `{ bus_voltage, button_map_leds, ... }`. Functionally correct but signature diverges. |
| `led_engine` | `get_bus_voltage()` | ✅ | ✅ | Matches spec |
| `led_hid_bridge` | `init(opts)` | ✅ | ✅ | Matches spec |
| `led_hid_bridge` | `assemble_and_send(...)` | ⚠️ | ❌ Extra params beyond spec | See F-003 |
| `led_hid_bridge` | `assemble_report(...)` | ✅ | ⚠️ Extra param (button_map_leds_state) | Acceptable extension for testing |
| `annunciator_leds` | `init(opts)` | ✅ | ✅ | Matches spec with eval_fn addition |
| `annunciator_leds` | `evaluate_row1()` / `evaluate_row2()` | ✅ | ✅ | Writes via set_led (per spec) |
| `annunciator_leds` | `evaluate_all()` | ✅ | ✅ | Convenience wrapper per spec |
| `gear_leds` | `init(opts)` | ✅ | ✅ | Matches spec |
| `gear_leds` | `evaluate(led_engine_module)` | ✅ | ✅ | Writes via set_led (per spec) |
| `gear_leds` | `get_gear_state()` | ✅ | ✅ | Returns array of {green, red} pairs per spec |
| `switch_leds` | `init(opts)` | ✅ | ⚠️ Added eval_fn beyond spec | Acceptable extension |
| `switch_leds` | `evaluate(led_engine_module)` | ❌ | **Does not write to buffer** | See F-001 — critical defect |
| `switch_leds` | `get_current_states()` | ✅ | ✅ | Returns map per spec |

---

## 6. FlyWithLua Callback Integrity

The following FlyWithLua string-callback entrypoints are preserved in BravoMultiMode.lua:

| Callback String | Resolution Path | Status |
|----------------|----------------|--------|
| `bravo_dispatch('handle_led_changes_task')` | bravo_dispatch → handle_led_changes → led_engine.handle_led_changes() + send_hid_data() | ✅ Preserved |
| `bravo_dispatch('build_bravo_gui')` | bravo_dispatch → ui.build_gui(build_ui_context()) with get_button_led_state from led_engine | ✅ Preserved |
| `on_close_floating_window(my_floating_wnd)` | bravo_dispatch → on_close_floating_window_impl (uses hid_close, bravo) | ✅ Preserved |
| `bravo_dispatch('refresh_selector_task')` | bravo_dispatch → refresh_selector_hid → set_current_selector → prime_button_led_states_for_mode_change + handle_led_changes | ✅ Preserved |
| `profiler_log_task()` | Direct global function call (do_every_frame) | ✅ Preserved |

**Verdict**: All FlyWithLua string callbacks resolve correctly through the dispatch facade. No breakage introduced by modularization.

---

## 7. Summary of Required Changes

### Must Fix Before Merge:
1. **F-001**: `switch_leds.evaluate()` must write evaluated states to LED engine buffer via `led_engine_module.set_led()`. Add a switch-to-position mapping table and call set_led for each switch.
2. **F-002**: Correct ROW1_LABELS / ROW2_LABELS in `annunciator_leds.lua` to match physical LED positions (move OIL_LOW_PRESSURE through APU from Row 1 to Row 2).

### Should Fix Before Merge:
3. **BP-001/BP-003**: Move constant arrays (`channel_indices`, `led_keys`) in `gear_leds.lua` and pre-allocate report buffer in `led_hid_bridge.lua` to eliminate hot-path allocations.
4. **F-003**: Align `assemble_and_send()` API signature with DSGN-001 spec (or update the spec).

### Nice-to-Have:
5. **BP-004**: Replace `get_buffer()` with a non-mutating accessor or document it as an internal-only method.
6. **BP-005**: Remove unused `log` import from `gear_leds.lua`.

---

## Final Verdict: REQUEST_CHANGES

The modularization architecture is sound and the dependency injection pattern is correctly applied across all five modules. FlyWithLua callback integrity is maintained, and no new global variable pollution was introduced. However, **two functional defects** (switch LEDs not writing to buffer, annunciator row label misalignment) must be resolved before this implementation can be approved for merge.
