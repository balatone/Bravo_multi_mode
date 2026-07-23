---
id: FEAT-018
title: High Priority Module Extractions
version: 1.0.0
status: APPROVED
created: 2026-07-23 12:59:55
updated: 2026-07-23 13:06:00
related_docs: ["REQ-008", "PLAN-006"]
priority: HIGH
---

# Feature Overview

This feature extracts four high-priority responsibility blocks from `BravoMultiMode.lua` into focused, independently require'd modules under `FlyWithLua/Modules/bracto++/`. These extractions address the next tier of technical debt identified in RAD-005 after the CRITICAL LED engine split (FEAT-017) is complete.

The deliverable is four new modules — Profiler (`profiler.lua`), Config Loader (`config_loader.lua`), Rocker Switch Router (`rocker_switches.lua`), and Button Lifecycle Manager (`button_lifecycle.lua`) — each with a clean public API, injection-based dependencies, and verified backward compatibility across all four aircraft configurations (B58, C90B, DA42, Transponder).

# Objectives

1. **Extract `profiler.lua`** — Self-contained performance profiling block from BravoMultiMode.lua lines ~10–130 with zero external dependencies. Export start/stop/log/toggle API for runtime performance monitoring.
2. **Extract `config_loader.lua`** — Aircraft configuration detection logic (exact→variant→generic fallback) and validation context building from BravoMultiMode.lua lines ~230–380. Decouple file system access via injection parameters.
3. **Extract `rocker_switches.lua`** — Uniform rocker switch command creation loop (7 switches × UP/DOWN directions) from BravoMultiMode.lua lines ~560–620, with dispatch callback registration as an injection point.
4. **Extract `button_lifecycle.lua`** — AP button begin/continue/end lifecycle manager from BravoMultiMode.lua lines ~750–810, accepting action map and command registry parameters for decoupled initialization.

# Scope

## In Scope

- Extraction of four responsibility blocks from `BravoMultiMode.lua` into new modules under `FlyWithLua/Modules/bravo++/`.
- Definition of public APIs using the `local M = {} ... return M` export pattern with documented function signatures.
- Injection-based dependency wiring: file system access, dispatch callbacks, action maps passed as parameters rather than accessed via globals.
- Preservation of FlyWithLua string callback integration through existing dispatch facade (`bravo_dispatch`).
- Verification against pre-refactoring behavior for all four aircraft configurations (B58, C90B, DA42, Transponder).

## Out of Scope

- Extraction of Input Handlers and Mode Manager — handled by FEAT-019.
- Resolution of `_G.command_once` bypass in `dispatch_twist.lua` — handled by FEAT-019.
- Export pattern standardization across the entire codebase — handled by FEAT-020.
- LuaDoc annotation additions — handled by FEAT-020.
- Changes to FlyWithLua host application or X-Plane integration contracts.

# Inputs to Review

Before implementation begins, review:

1. **REQ-008** — Modular Architecture Revision and Lua Best Practices Analysis: Originating requirement defining the modularization mandate.
2. **PLAN-006** — Release Plan: Establishes FEAT-018 as Phase 3a (HIGH priority), sequenced after FEAT-017 completion with explicit entry/exit criteria.
3. **FEAT-016** — Bravo++ Modular Architecture Design: Module interface specifications for `profiler`, `config_loader`, `rocker_switches`, and `button_lifecycle` with dependency maps and injection point definitions.
4. **RAD-005** — Modular Architecture Analysis Report: Findings on profiler embedding, config loader extraction readiness, and module export pattern inconsistencies.
5. **Current `BravoMultiMode.lua`**: Read lines ~10–380 (Profiler + Config Loader) and lines ~560–810 (Rocker Switches + Button Lifecycle) to understand current implementation patterns.
6. **FlyWithLua Host Application Manual** (at `/mnt/d/X-Plane 12/Resources/plugins/FlyWithLua/Documentation/FlyWithLua_Manual_en.pdf`): For `do_every_frame`, dataref access, and command registration semantics.

# Implementation Tasks

## Task 1: Extract `profiler.lua` (Zero Dependencies)

1. Move the profiler block from BravoMultiMode.lua lines ~10–130 into a new module. This is self-contained with zero dependencies on other modules — it only uses Lua standard library functions (`os.clock`, string formatting).
2. Export public API: `init()`, `start()`, `stop()`, `log(message)`, `toggle()` — providing runtime performance monitoring capabilities for debugging and optimization.
3. Verify the profiler continues to work correctly when invoked via FlyWithLua callbacks (e.g., `bravo_dispatch('profiler_start')`).

## Task 2: Extract `config_loader.lua`

1. Move aircraft configuration detection logic (exact model name → variant suffix → generic fallback) and validation context building from BravoMultiMode.lua lines ~230–380 into a new module.
2. Accept file list provider function as an injection parameter to decouple from direct calls to `util.list_files()` — this improves testability and allows mock file systems in tests.
3. Export public API: `init(file_provider)`, `detect_config()`, `load_validation_context(aircraft_type)` — returning structured configuration data rather than modifying globals.

## Task 3: Extract `rocker_switches.lua`

1. Move the uniform rocker switch command creation loop (7 switches × UP/DOWN = 14 commands) from BravoMultiMode.lua lines ~560–620 into a new module.
2. Accept dispatch callback registration function as an injection point rather than directly accessing `bravo_dispatch` or global command registry — this decouples the switch router from FlyWithLua-specific integration details.
3. Export public API: `init(dispatch_registrar)`, `register_all_switches()` — registering all 14 switch commands through the injected dispatcher.

## Task 4: Extract `button_lifecycle.lua`

1. Move AP button begin/continue/end lifecycle manager from BravoMultiMode.lua lines ~750–810 into a new module. This handles the three-phase lifecycle (begin → continue → end) for AP-related buttons with proper state management.
2. Accept action map and command registry as parameters to decouple from global access patterns.
3. Export public API: `init(action_map, command_registry)`, `register_ap_button_lifecycle()` — registering begin/continue/end handlers through the injected registries.

## Task 5: Wire Dependencies in Main Script

1. Update `BravoMultiMode.lua` to require the four new modules instead of containing their inline code.
2. Establish injection wiring at the composition root (main script): pass file providers, dispatch callbacks, action maps, and command registries to each module's init function.
3. Verify FlyWithLua string callbacks (`bravo_dispatch('profiler_start')`, etc.) still resolve through `bravo_dispatch` → modular exports.

## Task 6: Verification Gate

1. Run Lua syntax validation (`luac -p`) on all four new modules and the modified main script.
2. Verify pre-refactoring behavior for B58, C90B, DA42, and Transponder configurations using existing integration tests (FEAT-010 through FEAT-014).
3. Confirm no new global variable pollution — all module state encapsulated in export tables or injected parameters.
4. Verify `bravo_dispatch` forwarding works correctly through modular exports for all four modules' FlyWithLua callbacks.

# Acceptance Criteria

1. **Four Modules Exist**: All four modules (`profiler.lua`, `config_loader.lua`, `rocker_switches.lua`, `button_lifecycle.lua`) are created under `FlyWithLua/Modules/bravo++/` and independently require'd by the main script with all original functionality preserved.
2. **Export Pattern Compliance**: Each module uses `local M = {} ... return M` with documented public APIs using consistent function signatures, parameter types, and return values.
3. **Behavioral Parity**: Verified against pre-refactoring behavior for B58, C90B, DA42, and Transponder configurations — no functional regression in any aircraft mode.
4. **FlyWithLua Callback Integrity**: No FlyWithLua string-callback breakage; `bravo_dispatch` forwarding works correctly through modular exports for all four modules.
5. **No Global Pollution**: Zero new global variables introduced; all module state encapsulated within export tables or injected via parameters.

# Definition of Done

1. All four modules are extracted, independently require'd by the main script, and produce identical behavior to pre-refactoring state for all four aircraft configurations.
2. FlyWithLua string callbacks resolve correctly through the dispatch facade without any breakage.
3. No new global variable pollution introduced; injection-based dependency wiring is consistent across all four modules.
4. All existing unit and integration tests pass; new integration tests added for each extracted module covering their specific functionality.

# Dependencies / Risks

## Dependencies

1. **FEAT-017 (LED Engine Split)**: Must complete before FEAT-018 begins — the LED engine has the highest coupling with other modules, and splitting it first reduces complexity and risk for subsequent extractions.
2. **FEAT-016 (Bravo++ Modular Architecture Design)**: Provides module interface specifications, dependency maps, and FlyWithLua bridge design that define target architecture for all four sub-modules.
3. **RAD-005 Analysis Report**: Contains findings on profiler embedding, config loader extraction readiness, and module export pattern inconsistencies — essential reference during extraction.

## Risks and Mitigations

| Risk | Severity | Mitigation |
|------|----------|------------|
| **Config Loader File System Coupling**: The config loader currently depends on `util.list_files()` for aircraft configuration detection. Extracting it requires careful injection design to avoid breaking custom module paths. | MEDIUM | Accept file provider function as injection parameter; maintain backward-compatible default that uses the existing utility in the main script's composition root. |
| **Rocker Switch Command Registration**: The switch router currently creates commands directly via FlyWithLua APIs. Decoupling requires defining a clean dispatch registrar interface without losing command registration semantics. | MEDIUM | Define `dispatch_registrar` as a simple function table with `register(name, callback)` method; the main script implements this by wrapping `bravo_dispatch`. |
| **Button Lifecycle State Management**: The AP button lifecycle manager maintains internal state across begin/continue/end phases. Ensuring this state survives module extraction without global pollution requires careful export table design. | LOW | Encapsulate all lifecycle state within the module's export table (e.g., `M._state = {}`), never exposing it as a global variable. |

# Implementation Notes

## Extraction Order Rationale

These four modules have fewer inter-module dependencies than the Input Handlers and Mode Manager (FEAT-019), making them safer to extract first. The Profiler module has zero external dependencies, making it the safest starting point. Config Loader depends on file utilities but not on other bravo++ modules. Rocker Switches and Button Lifecycle depend on dispatch infrastructure that is already modularized (`dispatch.lua` + sub-modules).

## Key Design Decisions

1. **Profiler Self-Containment**: The profiler module requires zero dependencies — it only uses Lua standard library functions. This makes it the ideal first extraction, providing immediate value (runtime performance monitoring) with minimal risk.
2. **Config Loader Injection Pattern**: File system access is abstracted via an injected `file_provider` function parameter rather than direct calls to `util.list_files()`. The main script provides a default implementation that delegates to the existing utility, maintaining backward compatibility while enabling testability.
3. **Dispatch Registrar Abstraction**: Rocker switches and Button Lifecycle receive dispatch callbacks through injection parameters (`dispatch_registrar`, `action_map`, `command_registry`) rather than accessing globals directly. This decouples module logic from FlyWithLua integration details.

## Anti-Patterns to Avoid During Refactoring

- Do not access datarefs without nil guards in hot paths (RAD-005 Finding 5).
- Do not introduce new global variables — all module state must be encapsulated in export tables or injected parameters.
- Do not use forward declarations for new global entrypoints — replace with explicit init functions per module (addressing RAD-005 Finding 2).
