---
id: FEAT-017
title: LED Engine Modularization
version: 1.0.0
status: APPROVED
created: 2026-07-23 12:59:49
updated: 2026-07-24 10:07:00
related_docs: ["REQ-008", "PLAN-006", "DSGN-001", "DSGN-002", "DSGN-003"]
priority: CRITICAL
---

# Feature Overview

This feature splits the ~640-line monolithic LED engine block within `BravoMultiMode.lua` into five focused, single-responsibility modules under `FlyWithLua/Modules/bravo++/`. The current LED engine bundles six distinct concerns — button LEDs, gear LEDs, annunciator LEDs, rocker switch LEDs, buffer management, and HID report assembly — violating the single-responsibility principle and creating a CRITICAL technical debt hotspot identified in RAD-005.

The deliverable is five independently require'd modules that collectively produce byte-identical HID output to the pre-refactoring state across all four aircraft configurations (B58, C90B, DA42, Transponder), while reducing cognitive load and improving maintainability for future modifications.

# Objectives

1. **Extract `led_engine.lua`** — Core LED state management including buffer (`buffer[]`), the `handle_led_changes()` function that evaluates all LED conditions, and `all_leds_off()`. This is the central orchestrator of the LED subsystem.
2. **Extract `led_hid_bridge.lua`** — HID report assembly logic including `send_hid_data()`, bit manipulation across four banks (buttons, gear, annunciators, switches), and device handle injection for cross-module decoupling.
3. **Extract `annunciator_leds.lua`** — Row 1 and Row 2 annunciator LED evaluation handlers with dataref condition compilation support, replacing the inline conditional logic currently embedded in BravoMultiMode.lua lines ~960–1180.
4. **Extract `gear_leds.lua`** — Landing gear LED state machine implementing the three-channel green/red indicator pattern from BravoMultiMode.lua lines ~1180–1270, accepting gear dataref bindings as injection parameters.
5. **Extract `switch_leds.lua`** — Rocker switch per-switch condition evaluation for LED indicators from BravoMultiMode.lua lines ~1270–1350, decoupled from direct global access patterns.

# Scope

## In Scope

- Extraction of the complete LED engine block (~640 lines) from `BravoMultiMode.lua` into five new modules under `FlyWithLua/Modules/bravo++/`.
- Definition of public APIs for each module using the `local M = {} ... return M` export pattern.
- Injection-based dependency wiring: device handles, dataref bindings, and config objects passed as parameters rather than accessed via globals.
- Preservation of FlyWithLua string callback integration (`bravo_dispatch('handle_led_changes_task')`, etc.) through the existing dispatch facade.
- Byte-level HID output parity verification for all four aircraft configurations (B58, C90B, DA42, Transponder).

## Out of Scope

- Extraction of Profiler, Config Loader, Rocker Switch Router, and Button Lifecycle Manager — these are handled by FEAT-018.
- Extraction of Input Handlers and Mode Manager — handled by FEAT-019.
- Export pattern standardization across the entire codebase — handled by FEAT-020.
- LuaDoc annotation additions — handled by FEAT-020.
- Changes to FlyWithLua host application or X-Plane integration contracts.

# Inputs to Review

Before implementation begins, review:

1. **REQ-008** — Modular Architecture Revision and Lua Best Practices Analysis: Originating requirement defining the modularization mandate and analysis scope.
2. **PLAN-006** — Release Plan: Phased roadmap establishing FEAT-017 as Phase 2 (CRITICAL priority), with explicit entry/exit criteria for LED engine split.
3. **FEAT-016** — Bravo++ Modular Architecture Design: Module interface specifications, dependency maps, and FlyWithLua bridge design that define the target architecture for all five sub-modules.
4. **RAD-005** — Modular Architecture Analysis Report: Detailed findings including line-by-line LED engine breakdown (RAD-005-NOTES), complete dependency matrix with import counts, and FlyWithLua manual cross-references.
5. **Current `BravoMultiMode.lua`**: Read the full 1,577-line entry script to understand current implementation patterns, especially lines ~820–1420 covering the LED engine block.
6. **FlyWithLua Host Application Manual** (at `/mnt/d/X-Plane 12/Resources/plugins/FlyWithLua/Documentation/FlyWithLua_Manual_en.pdf`): For `hid_send_filled_feature_report` API, string-callback semantics, and dataref access constraints.

# Implementation Tasks

## Task 1: Analyze Current LED Engine Block

1. Read BravoMultiMode.lua lines ~820–1420 to map the complete LED engine responsibility boundary.
2. Document current function signatures, global variable usage (`buffer[]`, `led_state_modified`), and FlyWithLua callback registrations.
3. Identify all datarefs accessed within the LED engine block for injection point planning.

## Task 2: Extract `annunciator_leds.lua` (Lowest Coupling)

1. Move Row 1/Row 2 annunciator LED evaluation handlers from BravoMultiMode.lua lines ~960–1180 into a new module.
2. Accept compiled condition data (`annunciator_bindings`) and an `eval_fn` callback as injection parameters rather than accessing global state directly. The `eval_fn` parameter is a function `(dataref_table, condition_string, index?) → boolean` that replaces direct `config.eval_condition()` global access (per DSGN-001).
3. Export public API (per DSGN-001): `init({ annunciator_bindings, eval_fn })`, `evaluate_row1(led_engine_module)`, `evaluate_row2(led_engine_module)`, `evaluate_all(led_engine_module)`. This module writes LED states through `led_engine_module.set_led()` — NOT through direct buffer access.

## Task 3: Extract `gear_leds.lua`

1. Move the three-channel green/red gear LED state machine from BravoMultiMode.lua lines ~1180–1270 into a new module.
2. Accept gear dataref bindings and LED position constants as injection parameters (per DSGN-001: `gear_dataref`, `led_constants`).
3. Export public API (per DSGN-001): `init({ gear_dataref, led_constants })`, `evaluate(led_engine_module)`, `get_gear_state()`. This module writes LED states through `led_engine_module.set_led()` — NOT through direct buffer access.

## Task 4: Extract `switch_leds.lua`

1. Move rocker switch per-switch LED condition evaluation from BravoMultiMode.lua lines ~1270–1350 into a new module.
2. Accept switch LED bindings, dispatch module reference, and an `eval_fn` callback as injection parameters. The `eval_fn` parameter is a function `(dataref_table, condition_string, index?) → boolean` that replaces direct `config.eval_condition()` global access (per DSGN-001).
3. Export public API (per DSGN-001): `init({ switch_bindings, dispatch_module, eval_fn })`, `evaluate(led_engine_module)`, `get_current_states()`. This module writes LED states through `led_engine_module.set_led()` — NOT through direct buffer access.

## Task 5: Extract `led_engine.lua` (Core State Manager)

1. Move core state management including `buffer[]`, `led_state_modified`, `all_leds_off()`, `prime_for_mode_change()`, and the main `handle_led_changes()` orchestrator from BravoMultiMode.lua lines ~820–960 into a new module.
2. This module coordinates calls to the LED sub-modules via pre-registered callbacks (set through `set_sub_handlers()`). Sub-modules write to the buffer through `M.set_led()` — the buffer is **not** shared directly; it remains internal to this module.
3. Export public API (per DSGN-001): `init({ dispatch, button_map_leds_state, default_button_labels })`, `set_sub_handlers({ on_annunciator_row1, on_annunciator_row2, on_gear, on_switches })`, `set_led(bank, bit, state)`, `get_led(bank, bit)`, `all_off()`, `prime_for_mode_change()`, `is_dirty()`, `clear_dirty()`, `handle_led_changes({ bus_voltage, master_state_ref })`, `get_bus_voltage()`. The `set_sub_handlers()` method is critical — it registers callbacks at init time so the hot path performs zero table allocations per cycle.

## Task 6: Extract `led_hid_bridge.lua` (HID Report Assembly)

1. Move HID report assembly logic (`send_hid_data()`) and bit manipulation across four banks from BravoMultiMode.lua lines ~1350–1420 into a new module.
2. Accept the HID device handle and `bit` library reference as injection parameters rather than accessing globals (per DSGN-001).
3. Export public API (per DSGN-001): `init({ device_handle, bit_lib })`, `assemble_and_send(buffer_ref, default_button_labels, dispatch_module)`, `assemble_report(buffer_ref, default_button_labels, dispatch_module)`. On success, calls `led_engine.clear_dirty()` through the injected dispatch module reference.

## Task 7: Wire Dependencies in Main Script

1. Update `BravoMultiMode.lua` to require the five new modules instead of containing their inline code.
2. Establish injection wiring at the composition root (main script): pass device handles, dataref bindings, and config objects to each module's init function.
3. Verify FlyWithLua string callbacks (`bravo_dispatch('handle_led_changes_task')`, etc.) still resolve through `bravo_dispatch` → modular exports.

## Task 8: Verification Gate

1. Run Lua syntax validation (`luac -p`) on all five new modules and the modified main script.
2. Verify byte-identical HID output for B58, C90B, DA42, and Transponder configurations using existing integration tests (FEAT-010 through FEAT-014).
3. Confirm no new global variable pollution — all module state encapsulated in export tables or injected parameters.
4. Qualitative performance check: same function call count in hot path, no new table allocations in `handle_led_changes()` or `send_hid_data()`.

# Acceptance Criteria

1. **Five Modules Exist**: All five modules (`led_engine.lua`, `led_hid_bridge.lua`, `annunciator_leds.lua`, `gear_leds.lua`, `switch_leds.lua`) are created under `FlyWithLua/Modules/bravo++/` and independently require'd by the main script.
2. **Export Pattern Compliance**: Each module uses `local M = {} ... return M` with documented public APIs.
3. **HID Output Parity**: Byte-identical HID feature reports across all four aircraft configurations (B58, C90B, DA42, Transponder) before and after refactoring — verified through automated integration tests.
4. **FlyWithLua Callback Integrity**: All FlyWithLua string callbacks (`bravo_dispatch`, `build_bravo_gui`, `on_close_floating_window`) resolve correctly; no callback breakage introduced.
5. **No Global Pollution**: Zero new global variables introduced; all module state encapsulated within export tables or injected via parameters.
6. **Performance Maintained**: No measurable regression in the LED update hot path — same function call count, no new table allocations in `handle_led_changes()` or `send_hid_data()`.

# Definition of Done

1. All five modules are extracted, independently require'd by the main script, and produce identical HID output to pre-refactoring state for all four aircraft configurations.
2. FlyWithLua string callbacks resolve correctly through the dispatch facade without any breakage.
3. No new global variable pollution introduced; injection-based dependency wiring is consistent across all five modules.
4. All existing unit and integration tests pass; LED-specific integration tests cover the refactored modules.
5. Qualitative performance verification confirms no regression in the 0.25-second LED update loop (`do_every_frame`).

# Dependencies / Risks

## Dependencies

1. **FEAT-016 (Bravo++ Modular Architecture Design)**: Provides module interface specifications, dependency maps, and FlyWithLua bridge design that define target architecture for all five sub-modules.
2. **RAD-005 Analysis Report**: Contains line-by-line LED engine breakdown, complete dependency matrix with import counts, and prioritized recommendations — essential reference during extraction.
3. **Existing Test Suite (FEAT-010 through FEAT-014)**: Provides verification baseline; no phase advances without passing existing tests.

## Risks and Mitigations

| Risk | Severity | Mitigation |
|------|----------|------------|
| **FlyWithLua String-Callback Breakage**: Modularization could break FlyWithLua's string-callback resolution if global entrypoints are not preserved correctly. | HIGH | Maintain `bravo_dispatch` as the central forwarding hub; add integration tests exercising all three global callbacks after each phase. |
| **HID Output Regression**: Refactoring LED engine modules could produce different HID reports, causing incorrect LED behavior in X-Plane. | HIGH | Byte-level comparison of HID feature reports before and after refactoring for all four aircraft configurations; automated integration test using mock HID device as primary verification gate criterion. |
| **Performance Degradation in Hot Path**: The LED update loop runs every 0.25 seconds via `do_every_frame`. New function call overhead or table allocations could cause frame drops. | MEDIUM | Profile the refactored hot path against baseline; avoid string concatenation and unnecessary table allocation in `handle_led_changes()` and `send_hid_data()`. |
| **Circular Dependencies**: Extracting modules may create circular dependencies (e.g., `led_engine` needs dispatch state, dispatch needs LED state). | MEDIUM | Use injection pattern exclusively — pass required references as parameters during module initialization rather than requiring each other directly. |

# Implementation Notes

## Extraction Order Rationale

The extraction order is designed to minimize risk: start with the lowest-coupling sub-modules (annunciator LEDs, gear LEDs, switch LEDs) and work inward toward the core state manager (`led_engine`) and HID bridge (`led_hid_bridge`). This ensures that by the time the orchestrating modules are refactored, their dependencies already exist as stable interfaces.

## Key Design Decisions

1. **Encapsulated Buffer with `set_led()` API**: The LED buffer is internal to `led_engine.lua` and is **not** shared directly with sub-modules. All LED state writes flow through `led_engine.set_led(bank, bit, state)`, which handles dirty-flag logic centrally. This preserves encapsulation and ensures the dirty flag is always set correctly. Sub-modules receive a reference to the `led_engine` module (not the raw buffer) and call `set_led()` to write evaluated states.
2. **Pre-Registered Sub-Handler Callbacks**: The `led_engine.set_sub_handlers()` method registers the four LED sub-handler callbacks (annunciator row 1, annunciator row 2, gear, switches) at init time. These are stored in closure scope and invoked by `handle_led_changes()` with zero table allocation per cycle — critical for the 0.25s hot path.
3. **`eval_fn` Injection for Dataref Evaluation**: Both `annunciator_leds` and `switch_leds` receive an `eval_fn` callback (function `(dataref_table, condition_string, index?) → boolean`) as an injection parameter. This replaces direct `config.eval_condition()` global access, adhering to the injection-over-globals principle.
4. **Injection Over Globals**: Each sub-module accepts its specific dependencies (conditions, gear datarefs, switch config, eval_fn) as parameters rather than accessing globals directly. The main script acts as composition root wiring all dependencies together.
5. **Preserve `bravo_dispatch` Integration**: The FlyWithLua string callback contract is maintained — `bravo_dispatch('handle_led_changes_task')` continues to route through the existing dispatch facade, now forwarding to modular exports rather than inline functions.

## Anti-Patterns to Avoid During Refactoring

- Do not access datarefs without nil guards in hot paths (RAD-005 Finding 5).
- Do not introduce new global variables — all state must be encapsulated in export tables or injected parameters.
- Do not eliminate `bravo_dispatch` — it is a necessary FlyWithLua integration bridge.
