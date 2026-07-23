---
id: PLAN-006
title: Modular Architecture Revision Release Plan
version: 1.0.0
status: DRAFT
created: 2026-07-23 12:52:58
updated: 2026-07-23 12:53:05
related_docs: ["REQ-008", "FEAT-015", "FEAT-016"]
---
# Release Summary

This release plan outlines the path to fulfilling **REQ-008** (Modular Architecture Revision and Lua Best Practices Analysis) by executing the architectural design defined in **FEAT-016** (Bravo++ Modular Architecture Design) and producing the **Lua Best Practices Guide** from **FEAT-015**. The release encompasses a comprehensive modularization of the monolithic `BravoMultiMode.lua` entry script (~1,577 lines) into focused, single-responsibility modules under `FlyWithLua/Modules/bravo++/`, alongside the creation of an ongoing Best Practices reference for Worker specialists.

The target is to deliver a fully modularized codebase where all 11 new modules are extracted, verified against pre-refactoring behavior across all four aircraft configurations (B58, C90B, DA42, Transponder), and standardized with consistent export patterns and LuaDoc annotations — while preserving FlyWithLua's string-callback integration contract.

# Timebox

Proposed release window to accommodate four phased implementation stages with verification gates between each phase.

- **Start**: 2026-07-28 (following sprint kickoff)
- **End**: 2026-09-11 (end of planned cycle)
- **Duration**: 6 weeks, organized as:
  - Week 1–2: Phase 1 — LED Engine Split (CRITICAL) + verification gate
  - Week 3: Phase 2a/b — Profiler & Config Loader extractions + verification gate
  - Week 4: Phase 2c/d — Rocker Switches & Button Lifecycle extractions + verification gate
  - Week 5: Phase 3 — Medium Priority Extractions (Input Handlers, Mode Manager) + verification gate
  - Week 6: Phase 4 — Standardization & Finalization + final integration verification

*Note: The Lead agent may adjust the timebox based on resource availability and sprint capacity.*

# Release Goal

Complete the modular architecture revision and implement Lua best practices for the Bravo++ application by:

1. **Extracting 11 new modules** from the monolithic `BravoMultiMode.lua` (~1,577 lines) into focused, single-responsibility modules under `FlyWithLua/Modules/bravo++/`, reducing cognitive load and improving maintainability.
2. **Eliminating CRITICAL technical debt**: Splitting the ~640-line LED engine (the largest responsibility block violating single-responsibility principles) into five independent sub-modules.
3. **Producing a Lua Best Practices Guide** tailored to the Bravo Multi Mode project, synthesizing authoritative references with FlyWithLua-specific constraints and concrete code examples from this codebase.
4. **Standardizing module export patterns** across the entire codebase using `local M = {} ... return M`, adding LuaDoc-style annotations for public APIs.
5. **Preserving backward compatibility**: Ensuring all four aircraft configurations (B58, C90B, DA42, Transponder) continue to function identically with byte-identical HID output and no FlyWithLua string-callback breakage.

The release transforms a monolithic entry script into a well-organized modular architecture that is maintainable, testable, and extensible for future aircraft mode additions.

# Features Included

This release encompasses the following features, organized by implementation phase:

| # | Feature ID | Title | Phase | Priority |
|---|-----------|-------|-------|----------|
| 1 | **FEAT-015** | Lua Best Practices Guide | Foundation & Design (Phase 1) | HIGH |
| 2 | **FEAT-016** | Bravo++ Modular Architecture Design | Foundation & Design (Phase 1) | CRITICAL |
| 3 | **FEAT-017** *(proposed)* | LED Engine Modularization — Split the ~640-line LED engine into five focused sub-modules (`led_engine`, `led_hid_bridge`, `annunciator_leds`, `gear_leds`, `switch_leds`) | Core Refactoring (Phase 2) | CRITICAL |
| 4 | **FEAT-018** *(proposed)* | High Priority Module Extractions — Extract Profiler (`profiler.lua`), Config Loader (`config_loader.lua`), Rocker Switch Router (`rocker_switches.lua`), and Button Lifecycle Manager (`button_lifecycle.lua`) | Secondary Extractions (Phase 3) | HIGH |
| 5 | **FEAT-019** *(proposed)* | Medium Priority Module Extractions — Extract Input Handlers (`input_handlers.lua`) and Mode Manager (`mode_manager.lua`); resolve `_G.command_once` bypass in `dispatch_twist.lua` | Secondary Extractions (Phase 3) | MEDIUM |
| 6 | **FEAT-020** *(proposed)* | Module Standardization & Finalization — Standardize all export patterns to `local M = {} ... return M`, add LuaDoc-style annotations, consider namespace tables in dispatch facade | Standardization & Finalization (Phase 4) | OPTIONAL |

*Note: FEAT-017 through FEAT-020 are proposed feature IDs pending Lead agent approval and board task creation.*

# Sequencing / Dependencies

## External Dependencies

| Dependency | Type | Description |
|-----------|------|-------------|
| **REQ-008** | Blocking | The originating requirement that defines the two deliverables (analysis report + Best Practices guide). All implementation phases derive from REQ-008's findings and acceptance criteria. |
| **RAD-005** | Reference | The detailed analysis report containing eight findings, module inventory, dependency graph, and prioritized recommendations. Worker specialists must have RAD-005 accessible during all refactoring work. |

## Feature Dependencies (Internal)

The features follow a strict sequential ordering — each phase must be verified before the next begins:

```
REQ-008 ──► FEAT-015 (Best Practices Guide) ─┐
         ┌──► FEAT-016 (Architecture Design) ─┤
         │                                     ├──► FEAT-017 (LED Engine Split) ──► FEAT-018 (High Priority Extractions) ──► FEAT-019 (Medium Priority Extractions) ──► FEAT-020 (Standardization & Finalization)
         │                                     │
         └──────────────────────────────────────┘
```

### Dependency Chain Rationale

1. **FEAT-015 and FEAT-016 must complete before any implementation** — The Best Practices Guide provides the coding conventions reference for Worker specialists, while the Architecture Design defines the module interfaces, dependency maps, and phased extraction roadmap that guides all refactoring work.
2. **FEAT-017 (LED Engine Split) is a prerequisite for FEAT-018/FEAT-019** — The LED engine has the highest coupling with other modules; splitting it first reduces complexity and risk for subsequent extractions. Additionally, `led_engine` exports are referenced by multiple downstream modules.
3. **FEAT-018 (High Priority) precedes FEAT-019 (Medium Priority)** — Profiler, Config Loader, Rocker Switches, and Button Lifecycle have fewer inter-module dependencies than Input Handlers and Mode Manager, which require the dispatch layer to be stable.
4. **FEAT-020 runs last** — Standardization of export patterns and LuaDoc annotations must occur after all modules are extracted; running it earlier would risk rework as module APIs evolve during extraction phases.

## Cross-Cutting Dependencies

- **FlyWithLua Host Application Manual**: All FlyWithLua integration patterns (string callbacks, `do_every_frame`, dataref access, HID API) must conform to the host application's documented behavior throughout all phases.
- **Existing Test Suite** (FEAT-010 through FEAT-014): Provides the verification baseline for all refactoring phases; no phase advances without passing existing tests.

# Milestones & Success Criteria

## Phase 1: Foundation & Design (Weeks 1–2)

**Features**: FEAT-015 (Lua Best Practices Guide), FEAT-016 (Modular Architecture Design)

### Milestone M1.1 — Lua Best Practices Guide Approved
- **Success Criteria**:
  - The guide covers all required topic areas: Module Organization, Scoping & Visibility, Error Handling, LED/HID Communication, DataRef Interaction, Performance Considerations, Configuration Management, Command Registration, FlyWithLua Integration Patterns, and Anti-Patterns to Avoid.
  - Each topic includes concrete examples drawn from or applicable to the Bravo Multi Mode codebase.
  - All recommendations are cross-checked against FlyWithLua's execution model constraints.
  - Document passes `python3 toolbox/validate_docs.py` validation.
  - Status set to APPROVED after review completion.

### Milestone M1.2 — Architecture Design Approved
- **Success Criteria**:
  - Module Interface Specification complete for all 11 target modules with documented public APIs, function signatures, parameter types, return values, and injection points.
  - Complete Dependency Map published showing all inter-module relationships with circular dependencies resolved via injection patterns.
  - FlyWithLua Global Callback Preservation Strategy documented (preserving `bravo_dispatch`, `build_bravo_gui`, `on_close_floating_window`).
  - Phased Extraction Roadmap defined with clear entry/exit criteria for each phase.
  - Verification Gate checklist established covering syntax validation, global pollution checks, callback resolution, HID output parity, performance regression checks, and test coverage.
  - Document passes validation; status set to APPROVED.

## Phase 2: Core Refactoring — LED Engine Split (Weeks 1–2)

**Feature**: FEAT-017 (LED Engine Modularization)

### Milestone M2.1 — Five LED Sub-Modules Extracted and Verified
- **Success Criteria**:
  - All five modules exist under `FlyWithLua/Modules/bravo++/`: `led_engine.lua`, `led_hid_bridge.lua`, `annunciator_leds.lua`, `gear_leds.lua`, `switch_leds.lua`.
  - Each module uses the `local M = {} ... return M` export pattern with documented public API.
  - HID output is byte-identical to pre-refactoring state for all four aircraft configurations (B58, C90B, DA42, Transponder).
  - FlyWithLua string callbacks (`bravo_dispatch`, `build_bravo_gui`, `on_close_floating_window`) resolve correctly.
  - No new global variable pollution introduced; all module state encapsulated in export tables or injected parameters.
  - LED update loop performance shows no measurable regression (qualitative: same function call count, no new table allocations in hot path).
  - All existing unit and integration tests pass.

## Phase 3a: High Priority Extractions (Weeks 3–4)

**Feature**: FEAT-018 (High Priority Module Extractions)

### Milestone M3a — Four Modules Extracted and Verified
- **Success Criteria**:
  - All four modules exist under `FlyWithLua/Modules/bravo++/`: `profiler.lua`, `config_loader.lua`, `rocker_switches.lua`, `button_lifecycle.lua`.
  - Each module independently require'd by the main script with all original functionality preserved.
  - Verified against pre-refactoring behavior for B58, C90B, DA42, and Transponder configurations.
  - No FlyWithLua string-callback breakage; `bravo_dispatch` forwarding works correctly through modular exports.
  - All existing tests pass; new integration tests added for each extracted module.

## Phase 3b: Medium Priority Extractions (Weeks 4–5)

**Feature**: FEAT-019 (Medium Priority Module Extractions)

### Milestone M3b — Two Modules Extracted and Verified
- **Success Criteria**:
  - Both modules exist under `FlyWithLua/Modules/bravo++/`: `input_handlers.lua`, `mode_manager.lua`.
  - `_G.command_once` bypass in `dispatch_twist.lua` resolved with proper error handling wrapper (per RAD-005 Finding 3).
  - All original functionality preserved; no regression in dispatch or mode cycling behavior.
  - Forward-declaration anti-pattern eliminated — all FlyWithLua global entrypoints use explicit module init functions.
  - All existing tests pass; new integration tests cover refactored modules.

## Phase 4: Standardization & Finalization (Week 6)

**Feature**: FEAT-020 (Module Standardization and Documentation)

### Milestone M4 — Codebase Fully Standardized
- **Success Criteria**:
  - All module export patterns standardized to `local M = {} ... return M` across the entire codebase.
  - LuaDoc-style annotations (`--- @param`, `--- @return`) added for public APIs in all newly extracted modules.
  - Consideration of namespace tables within dispatch facade evaluated and documented (e.g., `dispatch.modes.cycle_up()`).
  - Final integration verification: byte-identical HID output across all four configurations; no FlyWithLua callback breakage; no performance regression.
  - All existing unit and integration tests pass; new test coverage for refactored modules exceeds baseline.
  - Best Practices Guide (FEAT-015) status set to APPROVED with final review against completed implementation.

## Final Release Gate

### Milestone M5 — Full Release Complete
- **Success Criteria**:
  - All six features (FEAT-015 through FEAT-020) implemented and verified.
  - `BravoMultiMode.lua` reduced from ~1,577 lines to a minimal entry script that acts as the composition root and FlyWithLua bridge.
  - Complete module inventory of all newly extracted modules documented with public APIs and dependency relationships.
  - All aircraft configurations (B58, C90B, DA42, Transponder) verified functional in X-Plane integration testing.
  - Release Plan status set to COMPLETE; final validation via `python3 toolbox/validate_docs.py`.

# Risks / Constraints

## Schedule & Project Risks

| # | Risk | Severity | Impact | Mitigation Strategy |
|---|------|----------|--------|---------------------|
| R1 | **Timeline Slippage** — Phase 2 (LED Engine Split) is the most complex extraction (~640 lines, high coupling). If verification gates reveal issues requiring rework, downstream phases may slip. | HIGH | Entire release delayed by 1–3 weeks; blocks FEAT-018/FEAT-019/FEAT-020. | Build a 2-day buffer into Phase 2 timeline. Conduct early risk assessment during the Design Phase (M1.2) to identify potential LED engine extraction challenges before implementation begins. Escalate immediately if verification gate reveals unexpected issues. |
| R2 | **Scope Creep** — Additional module extractions or architectural changes identified mid-refactoring may expand scope beyond the four planned phases. | MEDIUM | Timeline extension; resource contention with other sprint work. | Strictly enforce phase boundaries defined in FEAT-016. Any new extraction targets discovered during implementation must be logged as a separate feature request and evaluated by the Lead agent before inclusion. The Design Phase (M1.2) should catch most scope items upfront via the Dependency Map review. |
| R3 | **Resource Availability** — Worker specialists may be unavailable or reassigned mid-phase, causing handoff delays and knowledge loss. | MEDIUM | Phase completion delayed; inconsistent implementation quality across phases. | Ensure thorough documentation in each phase's exit criteria (module interfaces, injection patterns, verification procedures). Require cross-review between phases so at least one specialist understands the full context before transitioning to the next phase. |
| R4 | **FlyWithLua Environment Issues** — Access to FlyWithLua Manual or example scripts may be unavailable during implementation, blocking reference-based decisions. | LOW-MEDIUM | Delayed design decisions; potential for non-idiomatic implementations. | Ensure all critical references (FlyWithLua Manual PDF, key example scripts) are copied locally at project start. The Design Phase should validate access to all required resources before any implementation begins. |

## Technical Risks

| # | Risk | Severity | Impact | Mitigation Strategy |
|---|------|----------|--------|---------------------|
| T1 | **FlyWithLua String-Callback Breakage** — Modularization could break FlyWithLua's string-callback resolution if global entrypoints are not preserved correctly. | HIGH | Regression in all aircraft configurations; potential X-Plane crashes or silent failures. | Maintain `bravo_dispatch` as the central forwarding hub throughout all phases. Add integration tests that exercise all three global callbacks (`bravo_dispatch`, `build_bravo_gui`, `on_close_floating_window`) after each phase. No phase advances without verified callback resolution. |
| T2 | **HID Output Regression** — Refactoring LED engine modules could produce different HID reports, causing incorrect LED behavior in X-Plane. | HIGH | Incorrect LED states displayed in flight simulation; user-facing defect. | Byte-level comparison of HID feature reports before and after refactoring for all four aircraft configurations. Automated integration test using mock HID device to verify report parity. This is the primary verification gate criterion for Phase 2 (FEAT-017). |
| T3 | **Performance Degradation in Hot Path** — The LED update loop runs every 0.25 seconds via `do_every_frame`. New function call overhead or table allocations could cause frame drops. | MEDIUM | Reduced simulation performance; potential user complaints about stuttering. | Profile the refactored hot path against baseline before and after each phase. Avoid string concatenation and unnecessary table allocation in `handle_led_changes()` and `send_hid_data()`. The verification gate includes qualitative performance checks (same function call count, no new allocations). |
| T4 | **Circular Dependencies** — Extracting modules may create circular dependencies (e.g., `led_engine` needs dispatch state, dispatch needs LED state). | MEDIUM | Module initialization failures; potential runtime errors. | Use injection pattern exclusively — pass required references as parameters during module initialization rather than requiring each other directly. The Dependency Map in the Design Phase must identify and resolve all circular dependencies before implementation begins. |
| T5 | **Backward Compatibility with Custom Configs** — Aircraft-specific custom modules under `bravo++/custom/` may depend on internal functions that are moved or renamed. | MEDIUM | Custom aircraft configurations break after refactoring; user-facing regression. | Maintain backward-compatible aliases in the main script as a migration bridge during Phase 2–3. Document all breaking changes and provide an upgrade path for custom module authors. Test with any available custom configuration files before advancing each phase. |
| T6 | **Forward-Declaration Fragility** — The current forward-declaration pattern means any new global callback requires updating two locations. If missed, callbacks silently fail. | MEDIUM | Silent callback failures that are difficult to debug in production. | Replace with explicit init functions in each module during Phase 3b (FEAT-019). Document the new pattern and add a linting rule or code review checklist item to catch implicit globals during implementation. |

## Constraints

| Constraint | Description |
|-----------|-------------|
| **Lua 5.4 Runtime** | All implementations must target Lua 5.4 runtime compatibility as specified by FlyWithLua. No use of features outside the Lua 5.4 specification. |
| **Backward Compatibility** | Architectural improvements must not break existing X-Plane integration points or aircraft configuration files (B58, C90B, DA42, Transponder). |
| **FlyWithLua Global Callback Contract** | The three global entrypoints (`bravo_dispatch`, `build_bravo_gui`, `on_close_floating_window`) must remain accessible as FlyWithLua string callbacks throughout all phases. Eliminating them is out of scope and would require a separate migration effort. |
| **No Implementation During Analysis** | REQ-008 covers analysis only; implementation belongs to Worker specialists. This Release Plan bridges the gap between analysis (REQ-008) and implementation (FEAT-017 through FEAT-020). |
| **Branch Isolation** | All work must be performed on the `agentic-refactoring` integration branch. No changes should be merged to main/master until all phases pass final verification gate. |

# Success Criteria

The Release Plan is considered successfully fulfilled when **all** of the following conditions are met:

1. **All Six Features Implemented**: FEAT-015 (Lua Best Practices Guide), FEAT-016 (Modular Architecture Design), FEAT-017 (LED Engine Modularization), FEAT-018 (High Priority Extractions), FEAT-019 (Medium Priority Extractions), and FEAT-020 (Module Standardization & Finalization) are each verified against their respective exit criteria.

2. **Modular Architecture Achieved**: `BravoMultiMode.lua` is reduced from ~1,577 lines to a minimal entry script (~100–200 lines) that acts as the FlyWithLua bridge and composition root. All 11 new modules exist under `FlyWithLua/Modules/bravo++/` with documented public APIs.

3. **HID Output Parity**: Byte-identical HID feature reports across all four aircraft configurations (B58, C90B, DA42, Transponder) before and after refactoring — verified through automated integration tests.

4. **FlyWithLua Integration Preserved**: All three global string callbacks (`bravo_dispatch`, `build_bravo_gui`, `on_close_floating_window`) resolve correctly and forward to modular code without breaking any aircraft configuration.

5. **No Global Pollution**: Zero new global variables introduced; all module state encapsulated within export tables or injected via parameters. The `_G.command_once` bypass in `dispatch_twist.lua` is resolved with proper error handling (per RAD-005 Finding 3).

6. **Performance Maintained**: No measurable performance regression in the LED update hot path — same function call count, no new table allocations in `handle_led_changes()` or `send_hid_data()`.

7. **Best Practices Guide Approved**: FEAT-015 Lua Best Practices Guide covers all required topic areas with concrete code examples and is approved after review.

8. **Test Coverage Maintained**: All existing unit and integration tests pass; new test coverage added for each extracted module, exceeding the pre-refactoring baseline.

9. **Documentation Complete**: Module Interface Specification, Dependency Map, FlyWithLua Bridge Design, and LuaDoc annotations are all produced and reviewed. The Release Plan itself is validated via `python3 toolbox/validate_docs.py`.

# Revision Notes

Use this section for release-plan updates, additions, or sequencing changes as new features are introduced.
