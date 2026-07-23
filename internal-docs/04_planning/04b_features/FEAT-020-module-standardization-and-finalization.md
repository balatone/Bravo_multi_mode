---
id: FEAT-020
title: Module Standardization and Finalization
version: 1.0.0
status: APPROVED
created: 2026-07-23 13:00:13
updated: 2026-07-23 13:06:00
related_docs: ["REQ-008", "PLAN-006"]
priority: LOW
---

# Feature Overview

This feature standardizes the entire modularized codebase to ensure consistent coding conventions, documentation quality, and architectural patterns across all modules. It addresses the final phase of the modular architecture revision by enforcing uniform export patterns, adding LuaDoc-style annotations for public APIs, and evaluating namespace table organization within the dispatch facade.

The deliverable is a fully standardized and annotated modular codebase where every module follows the same conventions established during previous phases (FEAT-017 through FEAT-019), with comprehensive documentation that enables future contributors to understand and extend the architecture confidently.

# Objectives

1. **Standardize Export Patterns**: Ensure all modules across `FlyWithLua/Modules/bravo++/` use the consistent `local M = {} ... return M` export pattern, replacing any remaining non-standard patterns (e.g., direct global function assignments, mixed export styles).
2. **Add LuaDoc-Style Annotations**: Add `--- @param`, `--- @return`, and `--- @type` annotations for all public APIs in newly extracted modules (`led_engine`, `led_hid_bridge`, `annunciator_leds`, `gear_leds`, `switch_leds`, `profiler`, `config_loader`, `rocker_switches`, `button_lifecycle`, `input_handlers`, `mode_manager`) to enable IDE autocomplete and static analysis.
3. **Evaluate Namespace Tables in Dispatch Facade**: Assess whether the dispatch facade (`dispatch.lua`) should adopt namespace tables (e.g., `dispatch.modes.cycle_up()`, `dispatch.inputs.trim_up()` instead of flat function names) for better API organization, and document the recommendation with pros/cons analysis.

# Scope

## In Scope

- Audit all modules under `FlyWithLua/Modules/bravo++/` for export pattern consistency and update any non-standard patterns to `local M = {} ... return M`.
- Add LuaDoc-style annotations (`--- @param`, `--- @return`) for public APIs in all 11 newly extracted modules.
- Evaluate namespace table organization within the dispatch facade (`dispatch.lua`) — assess current flat function naming, analyze pros/cons of namespaced API, and document recommendation.
- Standardize module initialization patterns: ensure all modules have a documented `init()` or equivalent startup function with consistent parameter conventions.
- Final integration verification: byte-identical HID output across all four configurations; no FlyWithLua callback breakage; no performance regression.

## Out of Scope

- Extraction of additional modules beyond the 11 defined in PLAN-006 — scope is limited to standardization and documentation of existing extracted modules.
- Changes to FlyWithLua host application or X-Plane integration contracts.
- LuaDoc annotation additions for pre-existing modules that were not part of this modularization effort (e.g., `hardware.lua`, `decoder.lua`) unless they directly interact with newly extracted modules' public APIs.

# Inputs to Review

Before implementation begins, review:

1. **REQ-008** — Modular Architecture Revision and Lua Best Practices Analysis: Originating requirement defining the modularization mandate and best practices analysis scope.
2. **PLAN-006** — Release Plan: Establishes FEAT-020 as Phase 4 (OPTIONAL priority), sequenced last after all module extractions are complete, with explicit entry/exit criteria for standardization.
3. **FEAT-015** — Lua Best Practices Guide: Provides the coding conventions reference that defines the target export patterns, scoping rules, error handling standards, and documentation expectations for this phase.
4. **FEAT-016** — Bravo++ Modular Architecture Design: Module interface specifications defining public APIs for all 11 extracted modules; dependency maps showing inter-module relationships.
5. **RAD-005** — Modular Architecture Analysis Report: Finding on inconsistent module export patterns (Finding 8) provides the baseline audit criteria for standardization.

# Implementation Tasks

## Task 1: Export Pattern Audit and Standardization

1. Audit all modules under `FlyWithLua/Modules/bravo++/` to identify any non-standard export patterns (e.g., direct global function assignments, mixed export styles, missing return statements).
2. Update each module to use the consistent `local M = {} ... return M` pattern:
   - Convert inline function definitions (`function foo()`) to table methods (`M.foo = function()` or `function M.foo()`).
   - Ensure all public functions are explicitly added to the export table `M`.
   - Verify that private/internal functions remain unexported (not added to `M`).
3. Update any cross-module references that depend on old export patterns — ensure all `require` statements access functions through the module's return value (`local M = require('module_name')`) rather than globals.

## Task 2: LuaDoc Annotation Addition

1. Add LuaDoc-style annotations to public APIs in all 11 newly extracted modules:
   - `--- @param paramName type description` — document each parameter with its expected type and purpose.
   - `--- @return type description` — document return values for functions that produce output.
   - `--- @type TypeName` — add type annotations to module-level variables where appropriate (e.g., buffer tables, state objects).
2. Prioritize annotations for functions called from FlyWithLua string callbacks (`bravo_dispatch`, `build_bravo_gui`, `on_close_floating_window`) and core business logic functions (`handle_led_changes()`, `send_hid_data()`, `cycle_mode()`).
3. Use Lua 5.4 type conventions: `string`, `number`, `boolean`, `table`, `function`, `nil` — avoid non-standard types unless they represent specific dataref categories (document these clearly).

## Task 3: Dispatch Facade Namespace Evaluation

1. Analyze the current dispatch facade (`dispatch.lua`) to assess whether namespace tables would improve API organization:
   - **Current pattern**: Flat function names on export table (`dispatch.cycle_up()`, `dispatch.trim_up()`).
   - **Proposed pattern**: Namespaced sub-tables (`dispatch.modes.cycle_up()`, `dispatch.inputs.trim_up()`).
2. Document pros and cons of each approach:
   - Pros of namespaces: better API discoverability, reduced naming conflicts, clearer module boundaries, improved IDE autocomplete grouping.
   - Cons of namespaces: additional indirection overhead (negligible in Lua), more complex initialization code, potential breaking changes for existing custom modules under `bravo++/custom/`.
3. Produce a recommendation document with the preferred approach and migration plan if namespace tables are adopted.

## Task 4: Final Integration Verification

1. Run Lua syntax validation (`luac -p`) on all modified files across the entire codebase.
2. Verify byte-identical HID output for B58, C90B, DA42, and Transponder configurations using existing integration tests (FEAT-010 through FEAT-014).
3. Confirm no FlyWithLua callback breakage — all three global entrypoints (`bravo_dispatch`, `build_bravo_gui`, `on_close_floating_window`) resolve correctly.
4. Perform qualitative performance check: same function call count in hot paths, no new table allocations in `handle_led_changes()` or `send_hid_data()`.

## Task 5: Documentation Finalization

1. Update the module inventory documentation to reflect all 11 newly extracted modules with their public APIs and dependency relationships.
2. Ensure the Lua Best Practices Guide (FEAT-015) is reviewed against completed implementation and set status to APPROVED if not already approved.
3. Validate all documents via `python3 toolbox/validate_docs.py` — ensure no validation errors remain across the project's documentation suite.

# Acceptance Criteria

1. **Export Pattern Standardization Complete**: All module export patterns are standardized to `local M = {} ... return M` across the entire codebase under `FlyWithLua/Modules/bravo++/`.
2. **LuaDoc Annotations Added**: LuaDoc-style annotations (`--- @param`, `--- @return`) added for public APIs in all newly extracted modules — enabling IDE autocomplete and static analysis support.
3. **Namespace Table Evaluation Documented**: Consideration of namespace tables within dispatch facade is evaluated with documented pros/cons analysis and a clear recommendation (adopt or defer).
4. **Final Integration Verification Passes**: Byte-identical HID output across all four configurations; no FlyWithLua callback breakage; no performance regression — verified through automated integration tests and qualitative checks.

# Definition of Done

1. All module export patterns standardized to `local M = {} ... return M` across the entire codebase under `FlyWithLua/Modules/bravo++/`.
2. LuaDoc-style annotations added for public APIs in all 11 newly extracted modules (`led_engine`, `led_hid_bridge`, `annunciator_leds`, `gear_leds`, `switch_leds`, `profiler`, `config_loader`, `rocker_switches`, `button_lifecycle`, `input_handlers`, `mode_manager`).
3. Namespace table evaluation for dispatch facade completed with documented recommendation and migration plan (if applicable).
4. Final integration verification passes: byte-identical HID output across all four configurations; no FlyWithLua callback breakage; no performance regression.
5. All existing unit and integration tests pass; new test coverage for refactored modules exceeds baseline.
6. Lua Best Practices Guide (FEAT-015) status set to APPROVED with final review against completed implementation.

# Dependencies / Risks

## Dependencies

1. **FEAT-017 through FEAT-019**: All module extractions must be complete before standardization begins — running this phase earlier would risk rework as module APIs evolve during extraction phases.
2. **FEAT-015 (Lua Best Practices Guide)**: Provides the coding conventions reference for export patterns, scoping rules, error handling standards, and documentation expectations that guide this standardization work.
3. **Existing Test Suite (FEAT-010 through FEAT-014)**: Provides verification baseline; no phase advances without passing existing tests.

## Risks and Mitigations

| Risk | Severity | Mitigation |
|------|----------|------------|
| **Breaking Changes to Custom Modules**: Aircraft-specific custom modules under `bravo++/custom/` may depend on internal functions or export patterns that are changed during standardization. | MEDIUM | Maintain backward-compatible aliases in the main script as a migration bridge; document all breaking changes and provide an upgrade path for custom module authors. Test with any available custom configuration files before advancing each phase. |
| **Namespace Table Adoption Complexity**: If namespace tables are adopted for dispatch facade, existing code that calls `dispatch.cycle_up()` would need to be updated to `dispatch.modes.cycle_up()`, potentially affecting custom modules and requiring a coordinated migration effort. | LOW-MEDIUM | Defer namespace table adoption unless the benefits clearly outweigh the migration cost; document as a future enhancement rather than implementing in this phase. |
| **LuaDoc Annotation Inconsistency**: Adding LuaDoc annotations across 11 modules with varying API complexity could introduce inconsistencies if not carefully reviewed. | LOW | Use FEAT-015 (Lua Best Practices Guide) as the authoritative reference for annotation conventions; perform a focused code review pass specifically for documentation quality after initial annotation addition. |

# Implementation Notes

## Standardization Rationale

This phase runs last because standardizing export patterns and adding annotations before all modules are extracted would result in repeated rework — each new module extraction could introduce non-standard patterns that need to be corrected, or modify existing APIs requiring updated annotations. By running this phase after FEAT-017 through FEAT-019 complete, the codebase is stable enough for a single-pass standardization effort.

## Key Design Decisions

1. **Export Pattern Enforcement**: The `local M = {} ... return M` pattern is enforced consistently across all modules because it:
   - Makes public vs private API boundaries explicit and visible at a glance.
   - Enables IDE tools to analyze module exports for static type checking.
   - Prevents accidental global variable pollution — functions not added to `M` remain module-private.

2. **LuaDoc Annotation Scope**: Annotations are added only to newly extracted modules' public APIs (not pre-existing modules like `hardware.lua`) because:
   - The modularization effort is the primary scope of REQ-008; extending annotations to all existing modules would be out of scope and risk introducing regressions in unrelated code.
   - Pre-existing modules that interact with new modules will naturally reference their documented public APIs, providing implicit documentation through cross-references.

3. **Namespace Table Evaluation (Not Implementation)**: This feature evaluates namespace tables for the dispatch facade but does not implement them unless the analysis strongly favors adoption. The rationale is:
   - Namespace changes are a breaking change that affects all callers of `dispatch.*` functions, including custom modules under `bravo++/custom/`.
   - The evaluation produces actionable documentation (pros/cons, recommendation) rather than code changes — this allows future Lead agents to decide whether the migration effort is justified based on project priorities and resource availability.

## Anti-Patterns to Avoid During Standardization

- Do not modify module logic during standardization — only change export patterns and add annotations; functional behavior must remain unchanged.
- Do not introduce new LuaDoc types that are non-standard (e.g., `BravoConfig`, `LedBuffer`) without first defining them as custom type aliases using `--- @alias` or documenting them in the Best Practices Guide.
- Do not remove existing backward-compatible aliases during export pattern standardization — maintain migration bridges for any custom modules that may depend on old function names or global references.
