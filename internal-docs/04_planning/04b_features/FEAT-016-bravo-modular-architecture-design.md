---
id: FEAT-016
title: Bravo++ Modular Architecture Design
version: 1.0.0
status: DRAFT
created: 2026-07-23 12:46:10
updated: 2026-07-23 12:48:24
related_docs: ["REQ-008", "RAD-005"]
---
# Feature Overview

This feature defines a detailed architectural design and implementation roadmap for transitioning the monolithic `BravoMultiMode.lua` (1,577 lines) into a modular, maintainable structure aligned with Lua 5.4 best practices and FlyWithLua's execution model.

The current codebase has made significant progress in modularizing the dispatch layer (`dispatch.lua` + five sub-modules), but `BravoMultiMode.lua` remains a monolithic entry script that bundles eight distinct responsibility blocks — most critically, a ~640-line LED engine that violates single-responsibility principles by bundling button LEDs, gear LEDs, annunciator LEDs, rocker switch LEDs, dataref condition evaluation, buffer management, HID report assembly, and periodic update scheduling.

This feature draws directly from the findings in `REQ-008` (Modular Architecture Revision and Lua Best Practices Analysis) and `RAD-005` (Modular Architecture Analysis and Lua Best Practices), which identified specific module extraction targets, dependency risks, anti-patterns, and a phased modularization strategy.

The deliverable is not implementation code — it is the architectural blueprint that Worker specialists will follow during incremental refactoring across four prioritized phases.

# Objectives

Define a detailed architectural design and an implementation roadmap for transitioning `BravoMultiMode.lua` into a modular, maintainable structure while preserving FlyWithLua's global callback entrypoints.

1. **Produce a comprehensive module interface specification** defining the public API (exports) for each target module: `led_engine`, `led_hid_bridge`, `annunciator_leds`, `gear_leds`, `switch_leds`, `profiler`, `config_loader`, `rocker_switches`, `button_lifecycle`, `input_handlers`, and `mode_manager`.
2. **Create a dependency mapping** that documents inter-module relationships, injection points (e.g., device handles, dataref bindings), and resolves circular dependencies before any refactoring begins.
3. **Define the FlyWithLua callback preservation strategy**: identify which global entrypoints must remain (`bravo_dispatch`, `build_bravo_gui`, `on_close_floating_window`), how they forward to modular code via export tables, and document the bridge pattern for Worker specialists.
4. **Establish a phased extraction roadmap** prioritized by technical debt impact: Phase 1 (LED engine split — CRITICAL), Phase 2 (Profiler, Config Loader, Rocker Switch Router, Button Lifecycle Manager — HIGH), Phase 3 (Input Handlers, Mode Manager — MEDIUM), Phase 4 (Export pattern standardization — OPTIONAL).
5. **Define verification criteria** for each refactoring phase to ensure backward compatibility with all aircraft configurations (B58, C90B, DA42, Transponder) and no measurable performance regression in hot paths (LED update loop at 0.25s intervals via `do_every_frame`).

# Scope

## In Scope

1. **Detailed Module Interface Definitions (APIs/Exports)**: For each target module identified in RAD-005, define the public function signatures, expected input parameters, return values, and side effects. Use the `local M = {} ... return M` export pattern as the standard across all new modules.

2. **Dependency Mapping and Resolution Strategy**: Document the complete dependency graph between existing modules (`dispatch.lua`, `config.lua`, `ui.lua`, `hardware.lua`, `decoder.lua`, etc.) and newly extracted modules. Identify injection points where module-level state (e.g., HID device handle, dataref bindings) must be passed in rather than accessed globally.

3. **FlyWithLua Global Callback Preservation Strategy**: Define how FlyWithLua's string-callback execution model (global environment) will continue to work after modularization. Document the minimal set of global entrypoints and their forwarding logic through `bravo_dispatch` or direct module exports. Address the forward-declaration anti-pattern identified in RAD-005 Finding 2 by proposing a cleaner initialization pattern using module-level init functions.

4. **LED Engine Extraction Plan**: Detail the split of the ~640-line LED engine into five focused sub-modules:
   - `led_engine.lua` — core state management, buffer (`buffer[]`), `handle_led_changes()`, `all_leds_off()`
   - `led_hid_bridge.lua` — HID report assembly (`send_hid_data()`), bit manipulation, device handle injection
   - `annunciator_leds.lua` — Row 1/Row 2 annunciator evaluation with dataref condition compilation
   - `gear_leds.lua` — Landing gear LED state machine (3-channel green/red)
   - `switch_leds.lua` — Rocker switch LED per-switch condition evaluation

5. **Secondary Extraction Plans**: Detail the extraction strategy for Phase 2 modules:
   - Profiler → `profiler.lua` (self-contained, zero dependencies)
   - Config Loader → `config_loader.lua` (exact→variant→generic detection logic)
   - Rocker Switch Router → `rocker_switches.lua` (uniform command creation loop)
   - Button Lifecycle Manager → `button_lifecycle.lua` (AP button begin/continue/end registration)

6. **Implementation Roadmap**: A phased plan covering design, prototyping, incremental refactoring, and verification — with clear entry/exit criteria for each phase.

## Out of Scope

1. Implementation or refactoring code changes — these will be handled by Worker specialists following this blueprint.
2. Non-Lua code modifications (Python tooling, configuration files, documentation infrastructure).
3. Performance benchmarking beyond qualitative assessment — quantitative performance validation is deferred to verification phases.
4. Changes to the FlyWithLua host application or X-Plane integration contracts.
5. Lua Best Practices guide production — this was already delivered as part of REQ-008 deliverables (see RAD-005 companion notes).

# Inputs to Review

Before implementation begins, all Worker specialists must review the following documents:

1. **REQ-008** — Modular Architecture Revision and Lua Best Practices Analysis: The originating requirement that defined two deliverables (structured analysis report + curated Lua Best Practices guide). Key takeaways for this design feature include the responsibility catalogue of `BravoMultiMode.lua`, module inventory, dependency graph, and prioritized improvement roadmap.

2. **RAD-005** — Modular Architecture Analysis and Lua Best Practices: The detailed analysis report containing eight findings (LED engine as CRITICAL technical debt hotspot, forward-declaration fragility, `_G.command_once` bypass of safety net, implicit global leakage, missing nil guards in hot paths, config loader extraction readiness, inconsistent module export patterns, profiler embedding). Includes code-level examples and FlyWithLua example script cross-references.

3. **RAD-005-NOTES** — Companion notes with line-by-line LED engine breakdown, complete dependency matrix with import counts, and FlyWithLua manual cross-reference tables.

4. **Current Module Inventory**: All 17 Lua modules under `FlyWithLua/Modules/bravo++/` (~3,470 lines) plus the monolithic entry script (`BravoMultiMode.lua`, 1,577 lines). Worker specialists should read these files to understand current implementation patterns before beginning refactoring.

5. **FlyWithLua Host Application Manual** (at `/mnt/d/X-Plane 12/Resources/plugins/FlyWithLua/Documentation/FlyWithLua_Manual_en.pdf`): For understanding string-callback execution model, `do_every_frame` semantics, dataref access constraints, and `hid_send_filled_feature_report` API.

6. **FlyWithLua Example Scripts** (~100+ examples at `/mnt/d/X-Plane 12/Resources/plugins/FlyWithLua/Scripts (disabled)/`): Reference implementations for HID feature reports, floating window APIs, dataref access patterns, and command registration conventions.

# Implementation Tasks

The work is organized into four phases, each with entry/exit criteria. Worker specialists should treat these as sequential milestones — Phase N must be verified before Phase N+1 begins.

## Design Phase (Prerequisite)

Before any code changes, the following design artifacts must be produced:

1. **Module Interface Specification**: For each target module (`led_engine`, `led_hid_bridge`, `annunciator_leds`, `gear_leds`, `switch_leds`, `profiler`, `config_loader`, `rocker_switches`, `button_lifecycle`, `input_handlers`, `mode_manager`), define:
   - Public function signatures with parameter types and return values
   - Expected injection points (device handles, dataref bindings, config objects)
   - Side effects and FlyWithLua global dependencies (if any)
   - Internal/private functions that should remain unexported

2. **Dependency Resolution Map**: Document the complete dependency graph showing which modules depend on which, identify circular dependencies, and define injection patterns to break them. This map must be reviewed and approved before Phase 1 begins.

3. **Global Entrypoint Bridge Design**: Define how `bravo_dispatch` will forward calls to modular code after refactoring. Document the transition from the current varargs-forwarding pattern (`try_catch`) to per-module export table lookups, ensuring no FlyWithLua string callbacks break during or after migration.

## Phase 1 — LED Engine Split (CRITICAL)

Extract the ~640-line LED engine block into five focused modules:

| Task | Module | Key Actions |
|------|--------|-------------|
| 1a | `led_engine.lua` | Extract core state management (`buffer[]`, `led_state_modified`), `handle_led_changes()`, `all_leds_off()` from BravoMultiMode.lua lines ~820–960. Define export table with public API. |
| 1b | `led_hid_bridge.lua` | Extract HID report assembly (`send_hid_data()`, bit manipulation across 4 banks) from lines ~1350–1420. Accept device handle as injection parameter rather than accessing global. |
| 1c | `annunciator_leds.lua` | Extract Row 1/Row 2 annunciator LED handlers from lines ~960–1180. Accept compiled conditions from config module; remove direct dataref access. |
| 1d | `gear_leds.lua` | Extract `handle_gear_led_changes()` (3-channel green/red state machine) from lines ~1180–1270. Accept gear dataref bindings as injection parameter. |
| 1e | `switch_leds.lua` | Extract `handle_rocker_switch_led_changes()` with per-switch condition evaluation from lines ~1270–1350. Accept switch LED bindings from config. |

**Exit Criteria**: All five modules exist under `FlyWithLua/Modules/bravo++/`, are require'd by the main script, and produce identical HID output to the pre-refactoring state for all four aircraft configurations.

## Phase 2 — High Priority Extractions (HIGH)

| Task | Module | Key Actions |
|------|--------|-------------|
| 2a | `profiler.lua` | Extract profiler block from BravoMultiMode.lua lines ~10–130. Self-contained with zero dependencies on other modules. Export start/stop/log/toggle API. |
| 2b | `config_loader.lua` | Extract config detection logic (exact→variant→generic) and validation context building from lines ~230–380. Accept file list provider as parameter to decouple from `util.list_files()`. |
| 2c | `rocker_switches.lua` | Extract rocker switch command creation loop (7 switches × UP/DOWN) from lines ~560–620. Accept dispatch callback registration function as injection point. |
| 2d | `button_lifecycle.lua` | Extract AP button begin/continue/end lifecycle manager from lines ~750–810. Accept action map and command registry as parameters. |

**Exit Criteria**: Each module independently require'd by the main script, with all original functionality preserved and verified against pre-refactoring behavior for B58, C90B, DA42, and Transponder configurations.

## Phase 3 — Medium Priority Extractions (MEDIUM)

| Task | Module | Key Actions |
|------|--------|-------------|
| 3a | `input_handlers.lua` | Consolidate trim wheel up/down and twist knob increase/decrease handlers from lines ~620–730. Accept dispatch module as injection point; resolve `_G.command_once` bypass in `dispatch_twist.lua`. |
| 3b | `mode_manager.lua` | Extract mode cycling, CF mode switching, switch mode cycling, conceptual mode grouping, and selector index management from lines ~410–560. Decouple UI context building into a separate concern if needed. |

**Exit Criteria**: All original functionality preserved; `_G.command_once` issue resolved with `pcall` wrapper or dispatch wrapper pattern (per RAD-005 Finding 3).

## Phase 4 — Optional Enhancements (OPTIONAL)

| Task | Description |
|------|-------------|
| 4a | Standardize all module export patterns to `local M = {} ... return M` across the entire codebase. |
| 4b | Add LuaDoc-style annotations (`--- @param`, `--- @return`) for public APIs in newly extracted modules. |
| 4c | Consider namespace tables within the dispatch facade (`dispatch.lua`) for better API organization (e.g., `dispatch.modes.cycle_up()` instead of `dispatch_modes.cycle_up()`). |

## Verification Gate (After Each Phase)

Before advancing to the next phase, verify:

1. All Lua syntax is valid (run `luac -p` on each modified file).
2. No new global variable pollution — all module exports use explicit export tables.
3. FlyWithLua string callbacks still resolve correctly (`bravo_dispatch`, `build_bravo_gui`, `on_close_floating_window`).
4. HID output is byte-identical to pre-refactoring state for all four aircraft configurations.
5. LED update loop performance shows no measurable regression (qualitative: same function call count, no new table allocations in hot path).
6. Existing unit tests pass; integration tests cover the refactored modules.

# Acceptance Criteria

1. **Module Interface Specification Complete**: All 11 target modules have documented public APIs with function signatures, parameter types, return values, and injection points — stored as a reference document (DEC or RAD type).
2. **Dependency Map Published**: A complete dependency graph showing all inter-module relationships is produced and reviewed, with circular dependencies resolved via injection patterns.
3. **FlyWithLua Bridge Design Documented**: The strategy for preserving global callback entrypoints (`bravo_dispatch`, `build_bravo_gui`, `on_close_floating_window`) while using local modules is documented, including the transition plan from forward-declaration pattern to explicit module init functions.
4. **Phased Extraction Roadmap Defined**: Four phases (LED Engine Split → High Priority Extractions → Medium Priority Extractions → Optional Enhancements) with clear entry/exit criteria for each phase are specified in this FEAT document and ready for Worker specialist execution.
5. **Verification Criteria Established**: A verification gate checklist is defined that covers syntax validation, global pollution checks, FlyWithLua callback resolution, HID output parity, performance regression checks, and test coverage — applicable to every refactoring phase.
6. **Backward Compatibility Guarantee**: The design explicitly ensures no changes are required in aircraft configuration files (B58, C90B, DA42, Transponder) or custom modules under `bravo++/custom/`.

# Definition of Done

1. All four refactoring phases have been implemented by Worker specialists, with each phase verified against its exit criteria before advancing to the next.
2. The LED engine has been split into five independent modules (`led_engine`, `led_hid_bridge`, `annunciator_leds`, `gear_leds`, `switch_leds`) under `FlyWithLua/Modules/bravo++/`.
3. All 17 existing modules plus all newly extracted modules use the consistent `local M = {} ... return M` export pattern (Phase 4).
4. FlyWithLua string callbacks (`bravo_dispatch`, `build_bravo_gui`, `on_close_floating_window`) resolve correctly and forward to modular code without breaking any aircraft configuration.
5. HID output is byte-identical across all four configurations (B58, C90B, DA42, Transponder) before and after refactoring — verified through integration tests.
6. No new global variable pollution introduced; all module state is encapsulated within export tables or injected via parameters.
7. `_G.command_once` bypass in `dispatch_twist.lua` resolved with proper error handling wrapper (per RAD-005 Finding 3).
8. Forward-declaration anti-pattern eliminated — all FlyWithLua global entrypoints defined using explicit module init functions rather than two-location forward declarations.
9. LuaDoc-style annotations added for public APIs in newly extracted modules.
10. All existing unit and integration tests pass; new tests cover the refactored modules.

# Dependencies / Risks

## Dependencies

1. **RAD-005 Analysis Report**: This feature's design is directly derived from RAD-005 findings, module inventory, dependency graph, and phased recommendations. Worker specialists must have RAD-005 accessible during implementation.
2. **FlyWithLua Host Application Manual**: All FlyWithLua integration patterns (string callbacks, `do_every_frame`, dataref access, HID API) must conform to the host application's documented behavior.
3. **Existing Unit/Integration Test Suite**: The test infrastructure established in FEAT-010 through FEAT-014 provides the verification baseline for all refactoring phases.

## Risks and Mitigations

| Risk | Severity | Mitigation |
|------|----------|------------|
| **FlyWithLua String-Callback Breakage**: Modularization could break FlyWithLua's string-callback resolution if global entrypoints are not preserved correctly. | HIGH | Maintain `bravo_dispatch` as the central forwarding hub; add integration tests that exercise all three global callbacks (`bravo_dispatch`, `build_bravo_gui`, `on_close_floating_window`) after each phase. |
| **HID Output Regression**: Refactoring LED engine modules could produce different HID reports, causing incorrect LED behavior in X-Plane. | HIGH | Byte-level comparison of HID feature reports before and after refactoring for all four aircraft configurations; automated integration test using mock HID device. |
| **Performance Degradation in Hot Path**: The LED update loop runs every 0.25 seconds via `do_every_frame`. New function call overhead or table allocations could cause frame drops. | MEDIUM | Profile the refactored hot path against baseline; avoid string concatenation and unnecessary table allocation in `handle_led_changes()` and `send_hid_data()`. |
| **Circular Dependencies**: Extracting modules may create circular dependencies (e.g., `led_engine` needs dispatch state, dispatch needs LED state). | MEDIUM | Use injection pattern — pass required references as parameters during module initialization rather than requiring each other directly. Define a clear dependency hierarchy. |
| **Backward Compatibility with Custom Configs**: Aircraft-specific custom modules under `bravo++/custom/` may depend on internal functions that are moved or renamed. | MEDIUM | Maintain backward-compatible aliases in the main script as a migration bridge; document all breaking changes and provide upgrade path for custom module authors. |
| **Forward-Declaration Fragility**: The current forward-declaration pattern (RAD-005 Finding 2) means any new global callback requires updating two locations. If missed, callbacks silently fail. | MEDIUM | Replace with explicit init functions in each module; document the new pattern and add a linting rule to catch implicit globals. |

# Implementation Notes

## Key Design Decisions

1. **Preserve `bravo_dispatch` as Central Hub**: Rather than eliminating the current varargs-forwarding pattern through `bravo_dispatch`, this design keeps it as a stable bridge between FlyWithLua's global environment and modular code. This minimizes risk during migration — existing string callbacks continue to work without modification.

2. **Injection Over Global Access**: New modules should receive their dependencies (device handles, dataref bindings, config objects) via injection parameters rather than accessing globals directly. This improves testability and reduces coupling. The main script acts as the composition root that wires all dependencies together.

3. **LED Engine Split Rationale**: RAD-005 identified the LED engine (~640 lines) as a CRITICAL technical debt hotspot with low cohesion — it bundles six distinct concerns (button LEDs, gear LEDs, annunciator LEDs, rocker switch LEDs, HID report assembly, buffer management). The five-module split (`led_engine`, `led_hid_bridge`, `annunciator_leds`, `gear_leds`, `switch_leds`) follows the single-responsibility principle while maintaining clear data flow: each sub-module evaluates LED state → writes to shared buffer → `led_hid_bridge` assembles and sends.

4. **Phase Sequencing**: Phases are ordered by technical debt impact (CRITICAL → HIGH → MEDIUM → OPTIONAL). Phase 1 (LED engine) must complete before others because it addresses the largest code block with the most coupling, making subsequent extractions easier and safer.

## Anti-Patterns to Avoid During Refactoring

- **Do not eliminate `bravo_dispatch`** — it is a necessary FlyWithLua integration bridge.
- **Do not use forward declarations for new global entrypoints** — replace with explicit init functions per module (addressing RAD-005 Finding 2).
- **Do not access datarefs without nil guards in hot paths** — the `handle_button_led_changes()` function's missing nil checks on `button_map_leds`/`button_map_leds_cond`/`button_map_leds_index` must be addressed (RAD-005 Finding 5).
- **Do not introduce new global variables** — all module state should be encapsulated in export tables or injected parameters.

## FlyWithLua Integration Notes

- String callbacks execute in the **global environment**, so any function referenced by a string callback name must exist as a global at the time FlyWithLua resolves it.
- `do_every_frame` runs every frame — keep logic inside these callbacks minimal and avoid allocations. The LED update loop's 0.25-second interval via `bravo_dispatch('handle_led_changes_task')` is already an optimization over per-frame execution.
- `do_on_exit` provides cleanup guarantees — exit handlers should be idempotent since FlyWithLua may call them multiple times during shutdown.
