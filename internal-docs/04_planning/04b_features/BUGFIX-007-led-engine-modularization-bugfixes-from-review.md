---
id: BUGFIX-007
title: LED Engine Modularization Bugfixes from Review
version: 1.0.0
status: DRAFT
created: 2026-07-24 12:39:39
updated: 2026-07-24 12:39:46
related_docs: ["FEAT-017", "REVIEW-FEAT-017"]
priority: HIGH
---
# Summary

This BUGFIX addresses six issues identified during the review of FEAT-017 (LED Engine Modularization) as documented in REVIEW-FEAT-017. The issues include two functional defects that block merge approval, three performance/best-practice concerns involving hot-path table allocations and API integrity, and one encapsulation violation. All fixes target files within `FlyWithLua/Modules/bravo++/` and are scoped to the five new modularized LED engine modules plus their composition root.

# Scope

This BUGFIX modifies five Lua source files within `FlyWithLua/Modules/bravo++/` to resolve functional defects, performance issues, and best-practice violations identified in the review of FEAT-017. The fixes are additive or corrective — no architectural changes or new modules are introduced.

## In Scope

- **F-001**: Add buffer-write calls (`set_led()`) to `switch_leds.evaluate()` with proper bank/bit position mapping.
- **F-002**: Correct ROW1_LABELS / ROW2_LABELS arrays in `annunciator_leds.lua` to match physical LED positions (move OIL_LOW_PRESSURE, FUEL_LOW_PRESSURE, ANTI_ICE, STARTER_ENGAGED, APU from Row 1 to Row 2).
- **BP-001/P-001**: Promote constant arrays (`channel_indices`, `led_keys`) in `gear_leds.lua` from hot-path allocations to module-level constants.
- **BP-003/P-002**: Pre-allocate the report data table in `led_hid_bridge.assemble_report()` at module load time and reuse it across invocations.
- **F-003**: Align `assemble_and_send()` API signature with DSGN-001 spec by removing extra parameters or updating the spec accordingly.
- **BP-004**: Replace `get_buffer()` direct access in `led_hid_bridge` with a shallow-copy accessor (`get_buffer_snapshot()`) to preserve dirty-flag logic and encapsulation.

## Out of Scope

- BP-002 (eval_fn nil validation) — already correctly implemented; informational only.
- BP-005 (unused log import in gear_leds.lua) — minor cleanup, not blocking.
- P-003 (pcall overhead note) — informational only, no action needed.
- Any changes to DSGN-001/DSGN-002 architectural specifications beyond the `assemble_and_send()` signature alignment noted in F-003.

# Proposed Fix

## F-001: switch_leds.evaluate() Buffer Write
Add a `SWITCH_LED_POSITIONS` mapping table that maps each switch label to its `{bank, bit}` position in the LED engine buffer. In `evaluate()`, after determining `current_state`, look up the position and call `led_engine_module.set_led(bank, bit, current_state)` for each switch.

## F-002: Annunciator Row Label Misalignment
Reorganize ROW1_LABELS to contain only "MASTER_WARNING" and "FIRE_WARNING". Move OIL_LOW_PRESSURE, FUEL_LOW_PRESSURE, ANTI_ICE, STARTER_ENGAGED, and APU from ROW1_LABELS into ROW2_LABELS so that all labels match their physical LED bank positions as defined in LED_POSITIONS.

## BP-001/P-001: gear_leds.lua Hot-Path Allocations
Move `CHANNEL_INDICES = { 0, 1, 2 }` and the full `LED_KEYS` array (9 elements) to module-level scope so they are allocated once at load time. Reference them directly in `evaluate()` and `get_gear_state()`.

## BP-003/P-002: led_hid_bridge.lua Hot-Path Allocation
Pre-allocate `local report_data = { 0, 0, 0, 0 }` at module scope. In `assemble_report()`, reset all four elements to zero and populate the table in-place rather than creating a new table on each call.

## F-003: assemble_and_send() API Signature
Align with DSGN-001 by reverting `assemble_and_send()` to its three-parameter spec signature `(buffer_ref, default_button_labels, dispatch_module)`. Move the extra parameters (`button_map_leds_state`, `led_engine_module`) into an optional options table or remove them if not needed. Update BravoMultiMode.lua composition root accordingly.

## BP-004: get_buffer() Encapsulation Violation
Replace `M.get_buffer()` with a new `M.get_buffer_snapshot()` that returns `{ unpack(buffer) }` — a shallow copy of the internal buffer. Update `led_hid_bridge.assemble_and_send()` to call this instead of direct buffer access, preserving dirty-flag logic and encapsulation boundaries defined in DSGN-001.

# Implementation Tasks

### Task 1: F-001 — Fix switch_leds.evaluate() Buffer Write
1. Define `SWITCH_LED_POSITIONS` mapping table in `switch_leds.lua` with `{bank, bit}` entries for each switch label (e.g., `LEFT_PITOT = {1, 1}`, etc.).
2. In `evaluate()`, after computing `current_state`, look up the position: `local led_pos = SWITCH_LED_POSITIONS[switch_label]`.
3. If found, call `led_engine_module.set_led(led_pos[1], led_pos[2], current_state)`.

### Task 2: F-002 — Fix Annunciator Row Label Ordering
1. In `annunciator_leds.lua`, set `ROW1_LABELS = { "MASTER_WARNING", "FIRE_WARNING" }`.
2. Set `ROW2_LABELS` to include all remaining labels in correct order: OIL_LOW_PRESSURE, FUEL_LOW_PRESSURE, ANTI_ICE, STARTER_ENGAGED, APU, MASTER_CAUTION, VACUUM, HYD_LOW_PRESSURE, AUX_FUEL_PUMP, PARKING_BRAKE, VOLTS_LOW, DOOR.
3. Verify each label's bank/bit position in LED_POSITIONS matches its row assignment.

### Task 3: BP-001/P-001 — Eliminate Hot-Path Allocations in gear_leds.lua
1. Move `CHANNEL_INDICES = { 0, 1, 2 }` to module-level scope (after `local M = {}`).
2. Define `LED_KEYS = { "LED_LDG_N_GREEN", "LED_LDG_N_RED", ... }` at module level with all nine gear indicator keys.
3. Update `evaluate()` and `get_gear_state()` to reference these constants directly instead of creating new tables.

### Task 4: BP-003/P-002 — Pre-allocate Report Buffer in led_hid_bridge.lua
1. Define `local report_data = { 0, 0, 0, 0 }` at module scope (after `local M = {}`).
2. In `assemble_report()`, reset: `for bank = 1, 4 do report_data[bank] = 0 end`.
3. Populate `report_data` in-place and return it instead of creating a new table.

### Task 5: F-003 — Align assemble_and_send() API with DSGN-001
1. Revert `assemble_and_send()` signature to three parameters: `(buffer_ref, default_button_labels, dispatch_module)`.
2. Remove the extra `button_map_leds_state` and `led_engine_module` parameters from the function definition.
3. Update all callers (BravoMultiMode.lua composition root) to match the new signature.

### Task 6: BP-004 — Replace get_buffer() with Shallow Copy Accessor
1. In `led_engine.lua`, rename `M.get_buffer()` to `M.get_buffer_snapshot()` and implement it as `{ unpack(buffer) }` or equivalent shallow copy.
2. Update `led_hid_bridge.assemble_and_send()` to call the new accessor instead of direct buffer access.

### Task 7: Validation & Testing
1. Run luacheck on all modified files to verify no lint regressions.
2. Verify FlyWithLua integration by checking that switch LEDs appear in HID reports and annunciators light correct physical indicators.
3. Confirm dirty-flag logic is preserved (no direct buffer mutation).

# Acceptance Criteria

1. **F-001**: `switch_leds.evaluate()` calls `led_engine_module.set_led(bank, bit, state)` for every switch LED with the correct bank/bit position from a defined mapping table. Switch LEDs appear in HID reports sent by `led_hid_bridge`.
2. **F-002**: All annunciator labels in ROW1_LABELS and ROW2_LABELS match their physical LED positions as defined in LED_POSITIONS. OIL_LOW_PRESSURE through APU are in Row 2 (Bank 3), not Row 1. Annunciators light the correct physical indicators at runtime.
3. **BP-001/P-001**: `gear_leds.lua` contains no table allocations inside `evaluate()` or `get_gear_state()`. The constant arrays are defined at module scope and referenced directly.
4. **BP-003/P-002**: `led_hid_bridge.assemble_report()` does not allocate a new table on each invocation. A pre-allocated buffer is reused across calls.
5. **F-003**: `assemble_and_send()` signature matches DSGN-001 spec: `(buffer_ref, default_button_labels, dispatch_module)`. All callers are updated accordingly.
6. **BP-004**: No external module directly accesses the internal buffer table. A shallow-copy accessor (`get_buffer_snapshot()`) is used instead of `get_buffer()` for HID report assembly. Dirty-flag logic remains intact.

# Verification Plan

1. **Static Analysis**: Run `luacheck` on all six modified files (`switch_leds.lua`, `annunciator_leds.lua`, `gear_leds.lua`, `led_hid_bridge.lua`, `led_engine.lua`, `BravoMultiMode.lua`) to confirm no lint regressions.
2. **F-001 Functional Test**: Simulate switch state changes and verify that HID reports contain the expected LED states at the correct bank/bit positions. Confirm `_led_engine_module` parameter is now actively used in `switch_leds.evaluate()`.
3. **F-002 Functional Test**: Trigger each annunciator individually and confirm it lights the correct physical indicator (bank 2 for MASTER_WARNING/FIRE_WARNING, bank 3 for OIL_LOW_PRESSURE through APU, bank 4 for remaining). Verify no annunciators light on wrong indicators.
4. **BP-001/P-001 Performance Test**: Profile `gear_leds.evaluate()` over a sustained period (e.g., 60 seconds at 4 Hz) and confirm zero heap allocations from the function body using luajit's debug hooks or similar profiling tool.
5. **BP-003/P-002 Performance Test**: Profile `led_hid_bridge.assemble_report()` over a sustained period and confirm no per-call table allocation. The pre-allocated buffer should be reused.
6. **F-003 API Integrity Test**: Verify that all callers of `assemble_and_send()` pass exactly three arguments matching the DSGN-001 spec signature. Confirm BravoMultiMode.lua composition root is updated.
7. **BP-004 Encapsulation Test**: Search codebase for any remaining direct access to `led_engine` buffer table outside of `led_engine.lua`. Confirm only `get_buffer_snapshot()` (or equivalent) is used by external modules. Verify dirty-flag logic (`is_dirty()`, `clear_dirty()`) remains functional and unbroken.

# Risks / Notes

1. **F-001 — Switch Position Mapping**: The `SWITCH_LED_POSITIONS` table must be carefully defined to match the physical switch-to-LED wiring. An incorrect mapping will cause LEDs to light on wrong positions, similar to the F-002 annunciator issue. Cross-reference with BravoMultiMode.lua composition root where switches are initialized.
2. **F-003 — API Signature Change**: Reverting `assemble_and_send()` to a three-parameter signature is a breaking change for any code that currently passes five arguments. All callers must be updated atomically in the same commit. If DSGN-001 should instead be updated to match the current implementation, coordinate with the Lead before proceeding.
3. **BP-004 — Buffer Snapshot Copy**: The shallow copy returned by `get_buffer_snapshot()` is a new table on each call. While this preserves encapsulation, it does introduce a small allocation per HID report cycle. This trade-off (encapsulation vs. zero-allocation) favors safety and spec compliance given the low frequency of buffer reads (only during HID assembly).
4. **Sequencing**: F-001 and F-002 are blocking issues that must be fixed first, as they cause functional defects at runtime. Performance fixes (BP-001/P-001, BP-003/P-002) can be implemented in parallel since they do not affect correctness.

# Supporting Materials

## Review Reference: REVIEW-FEAT-017

All six issues addressed by this BUGFIX are documented in the review of FEAT-017 (`REVIEW-FEAT-017-led-engine-modularization.md`), which received a **REQUEST_CHANGES** verdict. The review findings are summarized below with their corresponding issue IDs:

| Issue ID | Category | Severity | File | Description |
|----------|----------|----------|------|-------------|
| F-001 | Functional | HIGH | `switch_leds.lua` | `evaluate()` does not write to LED buffer via `set_led()` |
| F-002 | Functional | HIGH | `annunciator_leds.lua` | ROW1/ROW2 label arrays misaligned with physical LED positions |
| BP-001 / P-001 | Performance/BP | MEDIUM | `gear_leds.lua` | Constant tables allocated in hot path (`evaluate()`, `get_gear_state()`) |
| BP-003 / P-002 | Performance/BP | LOW | `led_hid_bridge.lua` | Report data table allocated per call to `assemble_report()` |
| F-003 | API Integrity | MEDIUM | `led_hid_bridge.lua`, `BravoMultiMode.lua` | `assemble_and_send()` signature has extra params beyond DSGN-001 spec |
| BP-004 | Best Practices | LOW | `led_engine.lua` | `get_buffer()` returns raw internal table, bypassing dirty-flag logic |

## Related Documents

- **FEAT-017**: Original feature implementation — LED Engine Modularization (`FEAT-017-led-engine-modularization.md`)
- **REVIEW-FEAT-017**: Review findings document with full analysis and verdict (`REVIEW-FEAT-017-led-engine-modularization.md`)
- **DSGN-001**: Module interface specification defining expected API signatures (`DSGN-001-bravo-module-interface-specification.md`)
