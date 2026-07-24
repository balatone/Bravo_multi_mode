---
id: BUGFIX-008
title: Remove switch_leds.lua and correct LED engine issues from REVIEW-018
version: 1.0.0
status: APPROVED
created: 2026-07-24 13:32:00
updated: 2026-07-24 13:32:00
related_docs: ["FEAT-017", "REVIEW-018"]
priority: HIGH
---

# Summary

This BUGFIX supersedes the incorrect BUGFIX-007 (which was based on a faulty review). It addresses six issues identified in `REVIEW-018-review-of-feat-017-led-engine-modularization.md`: the complete removal of the unnecessary `switch_leds.lua` module, correction of annunciator LED_POSITIONS and row labels to match physical hardware layout, alignment of `assemble_and_send()` API with DSGN-001 spec, elimination of hot-path table allocations in gear_leds.lua and led_hid_bridge.lua, pre-allocation of the report buffer at module load time, and replacement of `get_buffer()` with a shallow-copy accessor to preserve encapsulation.

# Scope

This BUGFIX modifies five Lua source files within `FlyWithLua/Modules/bravo++/` and one composition root file:
- **Delete**: `FlyWithLua/Modules/bravo++/switch_leds.lua` (entire module removed).
- **Modify**: `FlyWithLua/Modules/bravo++/annunciator_leds.lua`, `FlyWithLua/Modules/bravo++/gear_leds.lua`, `FlyWithLua/Modules/bravo++/led_hid_bridge.lua`, `FlyWithLua/Modules/bravo++/led_engine.lua`.
- **Modify**: `BravoMultiMode.lua` (composition root — remove switch_leds require, replace its dispatch state update logic with a standalone handler function in BravoMultiMode.lua).

## In Scope

1. **Removal of `switch_leds.lua`**: Delete the module entirely (the LED buffer write logic was incorrect per REVIEW-018). Replace its dispatch state update logic with a standalone handler function (`handle_rocker_switch_led_changes`) directly in `BravoMultiMode.lua`. The dispatch module's `rocker_switch_led_states` table must remain intact and continue to be populated every frame for UI display purposes.
2. **F-002 (Annunciator Mapping)**: Correct `LED_POSITIONS`, `ROW1_LABELS`, and `ROW2_LABELS` in `annunciator_leds.lua` to match the physical hardware layout — Row 1 = Bank 2, Row 2 = Bank 3.
3. **F-003 (API Signature)**: Align `led_hid_bridge.assemble_and_send()` with DSGN-001 spec by removing extra parameters and updating callers in `BravoMultiMode.lua`.
4. **BP-001/P-001 (Performance)**: Eliminate hot-path table allocations in `gear_leds.lua` by promoting constants to module scope.
5. **BP-003/P-002 (Performance)**: Pre-allocate the report buffer in `led_hid_bridge.assemble_report()` at module load time.
6. **BP-004 (Encapsulation)**: Replace `get_buffer()` with a shallow-copy `get_buffer_snapshot()` accessor in `led_engine.lua`.

## Out of Scope

- BP-002 (eval_fn nil validation) — already correctly implemented; informational only.
- P-003 (pcall overhead note) — informational only, no action needed.
- Any changes to DSGN-001/DSGN-002 architectural specifications beyond the `assemble_and_send()` signature alignment noted in F-003.
- HID byte-level parity verification across aircraft configurations (deferred as follow-up per REVIEW-018 risks).

# Proposed Fix

## Removal of switch_leds.lua — Supersedes BUGFIX-007 F-001

BUGFIX-007 incorrectly attempted to add buffer-write calls (`set_led()`) to `switch_leds.evaluate()` (its "F-001"). This was based on a misinterpretation that rocker switches have physical LEDs. **REVIEW-018 confirms the hardware reality: the Honeycomb Bravo has no physical LEDs for its 7 rocker switches.** The original code's `handle_rocker_switch_led_changes()` manages switch position state for UI display only (ImGui context via `dispatch.rocker_switch_led_states`), not HID report generation.

**Critical note**: Simply deleting `switch_leds.lua` without preserving its dispatch state updates would break the UI display, because `switch_leds.evaluate()` is currently the **only code that writes to `dispatch.rocker_switch_led_states`**. The UI's `get_led_state_for_switch()` reads from this table.

**Required action**:
1. Delete `switch_leds.lua` entirely (the LED buffer write logic was incorrect).
2. In `BravoMultiMode.lua`, **replace the dispatch state update logic** that was in `switch_leds.evaluate()`. Create a new local function (e.g., `handle_rocker_switch_led_changes()`) that:
   - Reads each of the 7 rocker switch datarefs via their compiled conditions
   - Calls `dispatch.set_rocker_switch_led(switch_label, current_state)` to update dispatch state for UI display
   - Does **NOT** write to LED engine buffer or HID reports (no physical LEDs exist)
3. Register this function as a sub-handler in `led_engine.set_sub_handlers()` under `on_switches` (replacing the old `switch_leds.evaluate()` call).
4. Remove the `require("bravo++.switch_leds")` import, switch_leds.init() call, and led_engine_module dependency from the composition root.

The dispatch module's `rocker_switch_led_states` table must remain intact for UI use — only the LED engine integration layer is removed.

## F-002: Annunciator LED_POSITIONS and ROW1_LABELS Correction

The Bravo hardware physical layout is:

| Row | Physical Bank | Annunciators (7 each) |
|-----|--------------|----------------------|
| **Row 1** | Bank 2 | MASTER WARNING, ENGINE FIRE, LOW OIL PRESSURE, LOW FUEL PRESSURE, ANTI-ICE, STARTER ENGAGED, APU |
| **Row 2** | Bank 3 | MASTER CAUTION, VACUUM, LOW HYD PRESSURE, AUX FUEL PUMP, PARKING BRAKE, LOW VOLTS, DOOR |

Current `annunciator_leds.lua` errors:
- **LED_POSITIONS wrong**: Only maps 2 items on Bank 2 (`{2,7}`, `{2,8}`) and the rest to Bank 3. Should map all 7 Row 1 annunciators to `{2,1}`–`{2,7}` and all 7 Row 2 to `{3,1}`–`{3,7}`.
- **ROW1_LABELS incomplete**: Only contains `MASTER_WARNING`, `FIRE_WARNING`. Missing OIL_LOW_PRESSURE through APU (5 items).
- **ROW2_LABELS incorrect**: Includes items that belong on Row 1 (OIL_LOW_PRESSURE, FUEL_LOW_PRESSURE, ANTI_ICE, STARTER_ENGAGED, APU).

**Required fix**: Redefine all three constants to match the physical layout exactly.

## F-003: `assemble_and_send()` API Signature Alignment

DSGN-001 specifies signature as `(buffer_ref, default_button_labels, dispatch_module)` but implementation adds two extra params (`button_map_leds_state`, `led_engine_module`). The wiring in BravoMultiMode.lua passes `led_engine` (not `dispatch`) as the 5th argument.

**Required fix**: Revert to three-parameter signature matching DSGN-001. Remove extra parameters and update all callers in BravoMultiMode.lua.

## BP-001/P-001: Eliminate Hot-Path Allocations in gear_leds.lua

`CHANNEL_INDICES = { 0, 1, 2 }` and `LED_KEYS` array (9 elements) are allocated inside `evaluate()` and `get_gear_state()`. These should be module-level constants.

**Required fix**: Promote both to module scope after `local M = {}`. Reference them directly in hot-path functions.

## BP-003/P-002: Pre-allocate Report Buffer in led_hid_bridge.lua

`assemble_report()` creates a new table `{ 0, 0, 0, 0 }` on every call. This should be pre-allocated at module load time and reused.

**Required fix**: Define `local report_data = { 0, 0, 0, 0 }` at module scope. In `assemble_report()`, reset elements in-place before populating.

## BP-004: Replace get_buffer() with Shallow-Copy Accessor

`M.get_buffer()` returns the raw internal buffer table, allowing external code to bypass dirty-flag logic. DSGN-001 states the buffer is "NOT shared directly with sub-modules."

**Required fix**: Rename `get_buffer()` to `get_buffer_snapshot()` and implement as `{ unpack(buffer) }`. Update callers in led_hid_bridge.lua accordingly.

## BP-005: Remove Unused log Import in gear_leds.lua (Minor Cleanup)

`local log = require("bravo++.log")` is imported but never used. Remove the import line.

# Implementation Tasks

### Task 1: Replace switch_leds.lua with Standalone Switch State Handler in BravoMultiMode.lua
1. In `BravoMultiMode.lua`, **add a new local function** `handle_rocker_switch_led_changes()` that replicates the dispatch state update logic from the original monolithic code:
   ```lua
   local function handle_rocker_switch_led_changes()
       for i = 1, 7 do
           local switch_label = "SWITCH" .. i .. "_LED"
           local binding = switch_led_bindings and switch_led_bindings[switch_label]
           if binding then
               local current_state = get_led_state_for_dataref(binding[1], binding[2], binding[3])
               -- Only update dispatch state for UI display — NO LED buffer writes
               if dispatch.set_rocker_switch_led then
                   dispatch.set_rocker_switch_led(switch_label, current_state)
               end
           end
       end
   end
   ```
2. Delete `FlyWithLua/Modules/bravo++/switch_leds.lua`.
3. In `BravoMultiMode.lua`, remove `local switch_leds = require("bravo++.switch_leds")`.
4. Remove the `switch_leds.init()` call from the composition root initialization block.
5. Replace the sub-handler registration: change `on_switches = function() switch_leds.evaluate() end` to `on_switches = handle_rocker_switch_led_changes`.
6. Verify that `dispatch.rocker_switch_led_states` and its consumers (`get_led_state_for_switch()` in ui.lua) remain intact for UI display purposes. The dispatch table must still be populated every frame with current switch positions.

### Task 2: Correct Annunciator LED_POSITIONS, ROW1_LABELS, ROW2_LABELS
In `FlyWithLua/Modules/bravo++/annunciator_leds.lua`:
1. Set `LED_POSITIONS` to map all 7 Row 1 annunciators to Bank 2 `{2,1}`–`{2,7}` and all 7 Row 2 to Bank 3 `{3,1}`–`{3,7}`:
   - MASTER_WARNING = {2,1}, FIRE_WARNING = {2,2}, OIL_LOW_PRESSURE = {2,3}, FUEL_LOW_PRESSURE = {2,4}, ANTI_ICE = {2,5}, STARTER_ENGAGED = {2,6}, APU = {2,7}
   - MASTER_CAUTION = {3,1}, VACUUM = {3,2}, HYD_LOW_PRESSURE = {3,3}, AUX_FUEL_PUMP = {3,4}, PARKING_BRAKE = {3,5}, VOLTS_LOW = {3,6}, DOOR = {3,7}
2. Set `ROW1_LABELS = { "MASTER_WARNING", "FIRE_WARNING", "OIL_LOW_PRESSURE", "FUEL_LOW_PRESSURE", "ANTI_ICE", "STARTER_ENGAGED", "APU" }`.
3. Set `ROW2_LABELS = { "MASTER_CAUTION", "VACUUM", "HYD_LOW_PRESSURE", "AUX_FUEL_PUMP", "PARKING_BRAKE", "VOLTS_LOW", "DOOR" }`.

### Task 3: Align assemble_and_send() API with DSGN-001
In `FlyWithLua/Modules/bravo++/led_hid_bridge.lua`:
1. Revert `assemble_and_send()` signature to `(buffer_ref, default_button_labels, dispatch_module)` — three parameters only.
2. Remove the extra `button_map_leds_state` and `led_engine_module` parameters from the function definition.
3. Update all callers in BravoMultiMode.lua to pass exactly three arguments matching the spec.

### Task 4: Promote Constants to Module Scope in gear_leds.lua
In `FlyWithLua/Modules/bravo++/gear_leds.lua`:
1. After `local M = {}`, add module-level constants:
   - `local CHANNEL_INDICES = { 0, 1, 2 }`
   - `local LED_KEYS = { "LED_LDG_N_GREEN", "LED_LDG_N_RED", ... }` (all nine gear indicator keys)
2. In `evaluate()` and `get_gear_state()`, reference these constants directly instead of creating new tables.

### Task 5: Pre-allocate Report Buffer in led_hid_bridge.lua
In `FlyWithLua/Modules/bravo++/led_hid_bridge.lua`:
1. After `local M = {}`, add module-level constant: `local report_data = { 0, 0, 0, 0 }`.
2. In `assemble_report()`, reset elements in-place: `for bank = 1, 4 do report_data[bank] = 0 end`.
3. Populate `report_data` in-place and return it instead of creating a new table on each call.

### Task 6: Replace get_buffer() with Shallow-Copy Accessor
In `FlyWithLua/Modules/bravo++/led_engine.lua`:
1. Rename `M.get_buffer()` to `M.get_buffer_snapshot()`.
2. Implement as `{ unpack(buffer) }` — a shallow copy of the internal buffer table.
3. Update callers in led_hid_bridge.lua (specifically `assemble_and_send()`) to use `get_buffer_snapshot()` instead of direct buffer access or the old `get_buffer()`.

### Task 7: Remove Unused log Import in gear_leds.lua
In `FlyWithLua/Modules/bravo++/gear_leds.lua`:
1. Delete the line `local log = require("bravo++.log")` — it is imported but never used.

### Task 8: Validation & Testing
1. Run `luacheck` on all modified files to confirm no lint regressions.
2. Verify FlyWithLua integration by confirming that annunciators light correct physical indicators (bank 2 for Row 1, bank 3 for Row 2).
3. Confirm dirty-flag logic is preserved after `get_buffer_snapshot()` replacement.
4. Verify switch_leds.lua file no longer exists and BravoMultiMode.lua has no references to it.

# Acceptance Criteria

1. **switch_leds.lua removed**: The file `FlyWithLua/Modules/bravo++/switch_leds.lua` does not exist. `BravoMultiMode.lua` contains no require or initialization calls for switch_leds. A replacement handler (`handle_rocker_switch_led_changes`) in BravoMultiMode.lua updates dispatch state every frame so the UI display continues to work correctly — rocker switches show their current position in ImGui via `get_led_state_for_switch()`.
2. **F-002 Annunciator mapping correct**: All 7 Row 1 annunciators map to Bank 2 `{2,1}`–`{2,7}`, all 7 Row 2 announce to Bank 3 `{3,1}`–`{3,7}`. ROW1_LABELS and ROW2_LABELS contain exactly the right labels in correct order. Annunciators light the correct physical indicators at runtime.
3. **F-003 API signature aligned**: `assemble_and_send()` has exactly three parameters matching DSGN-001: `(buffer_ref, default_button_labels, dispatch_module)`. All callers updated accordingly.
4. **BP-001/P-001 zero allocations in gear_leds**: `gear_leds.lua` contains no table allocations inside `evaluate()` or `get_gear_state()`. Constants are defined at module scope and referenced directly.
5. **BP-003/P-002 pre-allocated buffer**: `led_hid_bridge.assemble_report()` does not allocate a new table on each invocation. A pre-allocated buffer is reused across calls.
6. **BP-004 encapsulation preserved**: No external module directly accesses the internal buffer table. Only `get_buffer_snapshot()` (shallow copy) is used by external modules for HID report assembly. Dirty-flag logic (`is_dirty()`, `clear_dirty()`) remains functional and unbroken.

# Verification Plan

1. **Static Analysis**: Run `luacheck` on all modified files (`annunciator_leds.lua`, `gear_leds.lua`, `led_hid_bridge.lua`, `led_engine.lua`, `BravoMultiMode.lua`) to confirm no lint regressions.
2. **File System Check**: Verify `switch_leds.lua` has been deleted and no references remain in any project file.
3. **Switch UI Display Test**: Toggle each of the 7 rocker switches (via their datarefs) and verify that the ImGui switch labels change color appropriately — on when active, off when inactive. Confirm `dispatch.rocker_switch_led_states` is populated every frame by the replacement handler (`handle_rocker_switch_led_changes`) in BravoMultiMode.lua.
4. **F-002 Functional Test**: Trigger each annunciator individually and confirm it lights the correct physical indicator (bank 2 for Row 1, bank 3 for Row 2). Verify no annunciators light on wrong indicators.
4. **BP-001/P-001 Performance Check**: Inspect `gear_leds.lua` to confirm constant arrays are at module scope and not allocated inside hot-path functions.
5. **BP-003/P-002 Performance Check**: Inspect `led_hid_bridge.lua` to confirm report buffer is pre-allocated at module scope and reused in-place.
6. **F-003 API Integrity Test**: Verify that all callers of `assemble_and_send()` pass exactly three arguments matching the DSGN-001 spec signature.
7. **BP-004 Encapsulation Test**: Confirm only `get_buffer_snapshot()` is used by external modules for buffer access. Search codebase for any remaining direct buffer table access outside `led_engine.lua`.

# Risks / Notes

1. **switch_leds Removal Safety**: Removing the module must not break the existing switch position tracking in `dispatch.rocker_switch_led_states`, which is consumed by ImGui UI context via `get_led_state_for_switch()`. The dispatch table is currently populated ONLY by `switch_leds.evaluate()` — this BUGFIX replaces that logic with a standalone handler (`handle_rocker_switch_led_changes`) directly in BravoMultiMode.lua. If the replacement handler fails to update dispatch state, all rocker switches will appear off in the UI regardless of their actual position.
2. **F-003 API Signature Change**: Reverting `assemble_and_send()` to a three-parameter signature is a breaking change for any code that currently passes five arguments. All callers in BravoMultiMode.lua must be updated atomically in the same commit. If DSGN-001 should instead be updated to match the current implementation, coordinate with the Lead before proceeding.
3. **F-002 Physical Layout Accuracy**: The corrected LED_POSITIONS mapping must precisely match the Honeycomb Bravo hardware layout. An incorrect mapping will cause LEDs to light on wrong physical indicators. Cross-reference with any existing wiring documentation or hardware schematics if available.
4. **HID Output Parity**: Byte-level comparison of HID feature reports across all four aircraft configurations (B58, C90B, DA42, Transponder) has not been verified and should be the primary gate after these fixes are applied. This is noted as a follow-up in REVIEW-018.
5. **Sequencing**: Task 1 (switch_leds removal) and Task 2 (annunciator correction) are blocking issues that must be fixed first, as they cause functional defects at runtime. Performance fixes (Tasks 4–6) can be implemented in parallel since they do not affect correctness.

# Supporting Materials

## Relationship to BUGFIX-007

BUGFIX-008 **supersedes** BUGFIX-007. The previous bugfix was based on a faulty review that incorrectly assumed rocker switches have physical LEDs. Key corrections:

| Issue | BUGFIX-007 (Incorrect) | BUGFIX-008 (Correct per REVIEW-018) |
|-------|----------------------|-------------------------------------|
| switch_leds.lua | F-001: Add buffer-write calls to `evaluate()` | **Delete the entire module** — rocker switches have no physical LEDs |
| BravoMultiMode.lua | No changes for switch removal | Remove require, init call, and dependency wiring; add standalone `handle_rocker_switch_led_changes()` handler to preserve dispatch state updates for UI display |
| F-002 Annunciator mapping | Moved items from Row 1 to Row 2 (partial fix) | Full correction: Row 1 = Bank 2 (7 items), Row 2 = Bank 3 (7 items) with correct LED_POSITIONS for all 14 annunciators |

### UI Display Preservation Note

The `switch_leds.lua` module is the **sole source** of dispatch state updates for rocker switches. Its `evaluate()` function calls `dispatch.set_rocker_switch_led()` every frame, which populates `rocker_switch_led_states`. The ImGui UI reads this table via `get_led_state_for_switch()`.

BUGFIX-008 does NOT simply delete the module — it **replaces** its dispatch state update logic with a standalone handler function (`handle_rocker_switch_led_changes`) directly in BravoMultiMode.lua. This ensures:
- ✅ Switch positions continue to be tracked for UI display (ImGui switch label colors)
- ❌ No LED buffer writes occur (no physical LEDs on switches)
- ❌ No HID report generation for switches (correct — they have no LEDs)

This is the key correction over BUGFIX-007, which tried to *add* buffer writes rather than recognizing that the entire module was built on a false premise.

## Review Reference: REVIEW-018

All six issues addressed by this BUGFIX are documented in `REVIEW-018-review-of-feat-017-led-engine-modularization.md`, which received a **REQUEST_CHANGES** verdict. The review findings are summarized below with their corresponding issue IDs:

| Issue ID | Category | Severity | File(s) | Description |
|----------|----------|----------|---------|-------------|
| switch_leds removal | Functional (Design Error) | BLOCKER | `switch_leds.lua`, `BravoMultiMode.lua` | Module created on false premise; must be deleted entirely |
| F-002 | Functional | HIGH (BLOCKER) | `annunciator_leds.lua` | LED_POSITIONS, ROW1_LABELS, ROW2_LABELS all incorrect — must match physical hardware layout |
| F-003 | API Integrity | MEDIUM | `led_hid_bridge.lua`, `BravoMultiMode.lua` | `assemble_and_send()` has extra params beyond DSGN-001 spec |
| BP-001 / P-001 | Performance/BP | MEDIUM | `gear_leds.lua` | Constant tables allocated in hot path (`evaluate()`, `get_gear_state()`) |
| BP-003 / P-002 | Performance/BP | LOW | `led_hid_bridge.lua` | Report data table allocated per call to `assemble_report()` |
| BP-004 | Best Practices | LOW | `led_engine.lua`, `led_hid_bridge.lua` | `get_buffer()` returns raw internal table, bypassing dirty-flag logic |

## Hardware Reference: Honeycomb Bravo Layout

### Rocker Switches (7 total) — No Physical LEDs
1. Pitot Heat Left
2. Master Battery Left
3. Master Alternator Left
4. Starter Right
5. Master Battery Right
6. Master Alternator Right
7. Pitot Heat Right

### Button Array (Bank 1)
- Individual LED indicators per button

### Annunciators — Row 1 (Bank 2, 7 LEDs)
MASTER WARNING → ENGINE FIRE → LOW OIL PRESSURE → LOW FUEL PRESSURE → ANTI-ICE → STARTER ENGAGED → APU

### Annunciators — Row 2 (Bank 3, 7 LEDs)
MASTER CAUTION → VACUUM → LOW HYD PRESSURE → AUX FUEL PUMP → PARKING BRAKE → LOW VOLTS → DOOR

## Related Documents

- **FEAT-017**: Original feature implementation — LED Engine Modularization (`FEAT-017-led-engine-modularization.md`)
- **REVIEW-018**: Correct review findings document with full analysis and verdict (`REVIEW-018-review-of-feat-017-led-engine-modularization.md`)
- **DSGN-001**: Module interface specification defining expected API signatures (`DSGN-001-bravo-module-interface-specification.md`)
