---
id: FEAT-019
title: Medium Priority Module Extractions
version: 1.0.0
status: APPROVED
created: 2026-07-23 13:00:03
updated: 2026-07-24 10:07:00
related_docs: ["REQ-008", "PLAN-006", "DSGN-001", "DSGN-002", "DSGN-003"]
priority: MEDIUM
---

# Feature Overview

This feature extracts two medium-priority responsibility blocks from `BravoMultiMode.lua` into focused modules and resolves a critical command safety issue identified in RAD-005. Specifically, it consolidates trim wheel and twist knob input handlers into `input_handlers.lua`, extracts mode cycling logic into `mode_manager.lua`, and resolves the `_G.command_once` bypass anti-pattern by routing all command invocations through the dispatch module's error handling wrapper (per DSGN-002 Phase 3 module table).

These extractions address remaining monolithic code blocks that have higher inter-module coupling than the Phase 2 modules (FEAT-018) but are essential for completing the modular architecture. The feature also fixes a safety net bypass where `_G.command_once` is used directly, circumventing FlyWithLua's error handling wrapper.

# Objectives

1. **Extract `input_handlers.lua`** — Consolidate trim wheel up/down and twist knob increase/decrease handlers from BravoMultiMode.lua lines ~620–730 into a single module with dispatch callback registration as an injection point.
2. **Extract `mode_manager.lua`** — Extract mode cycling, CF mode switching, switch mode cycling, conceptual mode grouping, and selector index management from BravoMultiMode.lua lines ~410–560 into a dedicated module decoupled from UI context building.
3. **Resolve `_G.command_once` bypass in input handlers** — Replace all direct global access to `_G.command_once` within the consolidated input_handlers module with proper error handling via `try_catch` wrapper or dispatch wrapper pattern (per DSGN-002 Phase 3 table and RAD-005 Finding 3).

# Scope

## In Scope

- Extraction of Input Handlers into a consolidated module under `FlyWithLua/Modules/bravo++/`.
- Extraction of Mode Manager logic into a dedicated module under `FlyWithLua/Modules/bravo++/`.
- Resolution of the `_G.command_once` bypass anti-pattern within input handlers, replacing direct global access with dispatch module's error handling wrapper (per DSGN-002 Phase 3 table).
- Definition of public APIs using the `local M = {} ... return M` export pattern with documented function signatures.
- Injection-based dependency wiring: dispatch module, UI context building functions passed as parameters rather than accessed via globals.
- Elimination of forward-declaration anti-pattern — all FlyWithLua global entrypoints use explicit module init functions.

## Out of Scope

- Extraction of Profiler, Config Loader, Rocker Switch Router, and Button Lifecycle Manager — handled by FEAT-018.
- Export pattern standardization across the entire codebase — handled by FEAT-020.
- LuaDoc annotation additions — handled by FEAT-020.
- Changes to FlyWithLua host application or X-Plane integration contracts.

# Inputs to Review

Before implementation begins, review:

1. **REQ-008** — Modular Architecture Revision and Lua Best Practices Analysis: Originating requirement defining the modularization mandate and Lua best practices analysis scope.
2. **PLAN-006** — Release Plan: Establishes FEAT-019 as Phase 3b (MEDIUM priority), sequenced after FEAT-018 completion with explicit entry/exit criteria including `_G.command_once` resolution.
3. **FEAT-016** — Bravo++ Modular Architecture Design: Module interface specifications for `input_handlers` and `mode_manager`, dependency maps showing their relationships to dispatch infrastructure, and FlyWithLua bridge design.
4. **RAD-005** — Modular Architecture Analysis Report: Finding 3 specifically addresses the `_G.command_once` bypass anti-pattern; Findings on forward-declaration fragility (Finding 2) inform the elimination strategy for global entrypoints.
5. **Current `BravoMultiMode.lua`**: Read lines ~410–730 to understand mode cycling logic and input handler implementations, including trim wheel up/down and twist knob increase/decrease handlers — note all `_G.command_once` usages within this range that need dispatch wrapper replacement.
6. **DSGN-002 Phase 3 Module Table**: Review the `input_handlers` module's injection point specification for how `_G.command_once` bypass is resolved via try_catch wrapping in the new modular code (not in dispatch_twist.lua).

# Implementation Tasks

## Task 1: Extract `input_handlers.lua`

1. Consolidate trim wheel up/down and twist knob increase/decrease handlers from BravoMultiMode.lua lines ~620–730 into a new module under `FlyWithLua/Modules/bravo++/`.
2. Accept the dispatch module as an injection point rather than accessing `bravo_dispatch` or global command registry directly — this decouples input handling logic from FlyWithLua integration details, consistent with DSGN-001's `input_handlers` specification.
3. Export public API: `init({ dispatch_module, decoder_handler_fn })`, `handle_trim(v)`, `handle_twist(dir)`, `handle_decoder_event(event_type, value)` — providing direct handler methods for trim wheel and twist knob inputs (per DSGN-001). All command invocations are wrapped in try_catch with error logging per RAD-005 Finding 3.

## Task 2: Extract `mode_manager.lua`

1. Extract mode cycling logic (`cycle_mode_up`, `cycle_mode_down`), CF mode switching, switch mode cycling, conceptual mode grouping, and selector index management from BravoMultiMode.lua lines ~410–560 into a new module under `FlyWithLua/Modules/bravo++/`.
2. Decouple UI context building (GUI rendering) into a separate concern — the Mode Manager should focus on state transitions and mode tracking, while GUI updates are handled by the existing UI infrastructure through dispatch callbacks after mode changes.
3. Export public API: `init({ dispatch_module, modes_array, selection_map_labels })`, `cycle_mode_up()`, `cycle_mode_down()`, `cycle_cf_mode()`, `cycle_switch_mode()`, `activate_mode_select()`, `deactivate_mode_select()`, `set_selector_index(idx)`, `build_ui_context()`, `get_current_mode()`, `get_current_selection()` — providing a clean state management interface without direct FlyWithLua dependencies (per DSGN-001's mode_manager specification).

## Task 3: Resolve `_G.command_once` Bypass via Dispatch Wrapper

1. Identify all usages of `_G.command_once` within BravoMultiMode.lua lines ~620–730 (the input handler block) that bypass FlyWithLua's error handling wrapper (per RAD-005 Finding 3).
2. Replace direct global access with the dispatch module's try_catch-wrapped command invocation pattern — all twist knob and trim wheel commands must flow through `dispatch_module` which resolves datarefs via injection rather than globals, consistent with DSGN-001's `input_handlers` specification.
3. Ensure the fix preserves existing behavior while adding safety — no functional regression in twist knob or trim wheel operation across all aircraft configurations (B58, C90B, DA42, Transponder).

## Task 4: Apply Init-Based Registration Pattern to `input_handlers` and `mode_manager`

1. Ensure both modules (`input_handlers`, `mode_manager`) use the `M.init(opts)` pattern for dependency injection rather than forward declarations (addressing RAD-005 Finding 2), consistent with DSGN-003's bridge pattern. This task is scoped to the callback registrations specific to these two modules only — the broader forward-declaration elimination is a cross-cutting concern handled across all extraction phases (FEAT-017 through FEAT-019).
2. FlyWithLua callback registration for these modules remains in the composition root's `dispatch_callbacks` routing table as thin forwarding functions (per DSGN-003), NOT within individual modules.
3. Verify the three-phase initialization flow for these modules: require → init() with injected dependencies → dispatch_callbacks registration → FlyWithLua string callback wiring.

## Task 5: Wire Dependencies in Main Script

1. Update `BravoMultiMode.lua` to require the two new modules instead of containing their inline code.
2. Establish injection wiring at the composition root (main script): pass dispatch module, modes_array, selection_map_labels to mode_manager's init; pass dispatch_module and decoder_handler_fn to input_handlers' init — all per DSGN-001 specifications.
3. Verify FlyWithLua string callbacks (`bravo_dispatch('trim_up')`, `bravo_dispatch('cycle_mode_up')`, etc.) still resolve through `bravo_dispatch` → modular exports via the dispatch_callbacks routing table (per DSGN-003).

## Task 6: Verification Gate

1. Run Lua syntax validation (`luac -p`) on both new modules and the modified main script.
2. Verify pre-refactoring behavior for B58, C90B, DA42, and Transponder configurations using existing integration tests (FEAT-010 through FEAT-014).
3. Confirm no new global variable pollution — all module state encapsulated in export tables or injected parameters.
4. Verify `_G.command_once` bypass is fully resolved with proper error handling wrapper within input_handlers (per DSGN-002 Phase 3 table and RAD-005 Finding 3).

# Acceptance Criteria

1. **Two Modules Exist**: Both modules (`input_handlers.lua`, `mode_manager.lua`) are created under `FlyWithLua/Modules/bravo++/` and independently require'd by the main script with all original functionality preserved.
2. **Command Safety Issue Resolved**: `_G.command_once` bypass within input handlers is fully resolved with proper try_catch/dispatch wrapper error handling (per DSGN-002 Phase 3 table and RAD-005 Finding 3) — no direct global access to `_G.command_once`.
3. **Forward-Declaration Anti-Pattern Eliminated**: All FlyWithLua global entrypoints use explicit module init functions rather than two-location forward declarations.
4. **Behavioral Parity**: No regression in dispatch or mode cycling behavior for any aircraft configuration (B58, C90B, DA42, Transponder).

# Definition of Done

1. Both modules are extracted, independently require'd by the main script, and produce identical behavior to pre-refactoring state for all four aircraft configurations.
2. `_G.command_once` bypass within input handlers is resolved with proper try_catch/dispatch wrapper error handling — verified through code review and testing (per DSGN-002 Phase 3 table).
3. Forward-declaration anti-pattern eliminated across all modules; FlyWithLua global entrypoints use explicit init functions, with callback registration handled by the composition root's dispatch_callbacks routing table per DSGN-003.
4. All existing unit and integration tests pass; new integration tests cover refactored input handlers, mode manager, and command safety fix.

# Dependencies / Risks

## Dependencies

1. **FEAT-017 (LED Engine Split)**: Must complete before FEAT-019 begins — the LED engine has the highest coupling with other modules; splitting it first reduces complexity for subsequent extractions.
2. **FEAT-018 (High Priority Extractions)**: Should precede FEAT-019 — Profiler, Config Loader, Rocker Switches, and Button Lifecycle have fewer inter-module dependencies than Input Handlers and Mode Manager, which require the dispatch layer to be stable.
3. **FEAT-016 (Bravo++ Modular Architecture Design)**: Provides module interface specifications for `input_handlers` and `mode_manager`, dependency maps showing their relationships to dispatch infrastructure, and FlyWithLua bridge design.
4. **RAD-005 Analysis Report**: Finding 3 specifically addresses the `_G.command_once` bypass anti-pattern; Findings on forward-declaration fragility (Finding 2) inform the elimination strategy for global entrypoints.

## Risks and Mitigations

| Risk | Severity | Mitigation |
|------|----------|------------|
| **Mode Manager UI Coupling**: Mode cycling logic currently builds GUI context alongside state transitions. Decoupling requires careful interface design to avoid breaking FlyWithLua floating window callbacks (`build_bravo_gui`). | MEDIUM | Define a clean separation: `mode_manager.lua` handles pure state management (get/set mode, cycle), while UI rendering remains in the existing UI infrastructure and is triggered via dispatch callbacks after mode changes. |
| **Input Handler Dispatch Integration**: Trim wheel and twist knob handlers currently interact with both FlyWithLua commands and BravoMultiMode's internal dispatch system. Consolidating them requires a unified injection point that handles both concerns without creating coupling. | MEDIUM | Accept the dispatch module as an injection parameter; the dispatcher abstracts away FlyWithLua command registration details, providing a clean `register(name, callback)` interface for input handlers to use. |
| **`_G.command_once` Safety Fix Regression**: Replacing direct global access with try_catch/dispatch wrappers could change error propagation behavior if existing code relies on silent failures. | LOW | Use `try_catch` wrapper that logs errors without crashing; maintain backward-compatible default behavior while adding safety. Test trim wheel and twist knob operation across all aircraft configurations after the fix. |

# Implementation Notes

## Extraction Order Rationale

These modules have higher inter-module coupling than FEAT-018's targets (Profiler, Config Loader, Rocker Switches, Button Lifecycle) because they interact more directly with the dispatch layer and UI infrastructure. They are sequenced after FEAT-018 to ensure the dispatch facade is stable before these modules depend on it.

## Key Design Decisions

1. **Input Handler Consolidation**: Rather than keeping trim wheel handlers separate from twist knob handlers, both are consolidated into a single `input_handlers.lua` module since they share the same responsibility (mapping physical inputs to dispatch callbacks) and similar implementation patterns.
2. **Mode Manager State Management Focus**: The Mode Manager is designed as a pure state management module — it tracks current mode, handles cycling logic, and provides query methods (`get_current_mode()`, `get_mode_count()`). GUI context building is delegated back through the existing UI infrastructure via dispatch callbacks after mode changes.
3. **Dispatch Wrapper for Command Safety**: Rather than simply wrapping `_G.command_once` in a `pcall`, all command invocations within input_handlers flow through the injected dispatch module which provides consistent try_catch error handling across all command invocations (per DSGN-001's input_handlers specification). This approach is more maintainable long-term and aligns with the modular architecture's injection-based dependency pattern.

## Anti-Patterns to Avoid During Refactoring

- Do not access datarefs without nil guards in hot paths (RAD-005 Finding 5).
- Do not introduce new global variables — all module state must be encapsulated in export tables or injected parameters.
- Do not use forward declarations for new global entrypoints — replace with explicit init functions per module (addressing RAD-005 Finding 2).
