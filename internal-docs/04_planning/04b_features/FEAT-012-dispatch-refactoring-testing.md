---
id: FEAT-012
title: Dispatch Refactoring & Testing
version: 1.0.0
status: APPROVED
created: 2026-07-16 19:11:53
updated: 2026-07-16 19:19:21
related_docs: ["PLAN-005", "REQ-007"]
---
# Feature Overview

This feature addresses SPIKE-003's highest-risk finding: dispatch.lua is a 762-line god object with ~85% side effects that handles button actions, twist knob execution, rocker switch commands, trim wheel logic, mode cycling, and selector management — all in one file. This feature performs targeted refactoring to split the god object into ≤300-line sub-modules while simultaneously writing integration tests for each new module. The refactoring is essential because dispatch.lua's current structure makes it impossible to achieve ≥80% test coverage without fragile integration-level mocks, and its tight coupling with FlyWithLua host functions (`_G.command_once`, `_G.command_begin`, `_G.command_end`) means any untested change carries high regression risk for pilot-facing input handling. This feature directly addresses REQ-007's FR-003 (dispatch.lua unit tests) and SPIKE-003's Finding 1 (dispatch.lua testability score of 1/5).

# Objectives

1. **Split dispatch.lua into ≤300-line sub-modules** with clear responsibility boundaries: action map builder, button command executor, twist knob executor, trim wheel executor, and mode cycling manager — each independently testable.
2. **Achieve ≥80% line coverage on the refactored dispatch modules** through integration tests covering all public functions identified in REQ-007's FR-003: action map building, mode cycling with index wrapping, CF/switch mode toggles, selector activation/deactivation, button press lifecycle (begin/continue/end), twist knob priority resolution, rocker switch dispatch, trim wheel boost logic, and map accessors.
3. **Preserve behavioral equivalence** — the main entry point (`BravoMultiMode.lua`) wiring must survive refactoring with zero functional regressions in button/knob/switch behavior.

# Scope

## In Scope

1. **Refactoring: Split dispatch.lua (762 lines) into sub-modules:**
   - **Action map builder** — Extract `_build_button_action_map` (~150 lines of nested loops building multi-dimensional tables), mode cycling logic (`cycle_mode_up`, `cycle_mode_down` with N-mode index wrapping), CF mode toggle (`cycle_cf_mode` alternating outer/inner), switch mode toggle (`cycle_switch_mode` alternating up/down).
   - **Button command executor** — `button_begin`, `button_continue` (continuous mode + long-click detection), `button_end` (single click vs. long click dispatch) with all three lookup paths: mode-level, switch-mode UP/DOWN, selection-aware resolution via `resolve_button_command`.
   - **Twist knob executor** — `knob_increase`, `knob_decrease` with priority resolution logic (direct > OUTER > INNER based on cf_mode state).
   - **Trim wheel executor** — `trim_nose_up`, `trim_nose_down` with boost window logic, clamping to [-1, 1].
   - **Mode cycling manager** — Mode select activation/deactivation (`activate_mode_select()`, `deactivate_mode_select()`), selector index setting with label updates and callback triggers.

2. **Integration tests for each sub-module:**
   - Button press lifecycle across all three dispatch paths (mode-level, switch-mode UP/DOWN, selection-aware)
   - Twist knob priority resolution in all cf_mode states (outer, inner, direct override)
   - Mode cycling boundary conditions (N-mode wrapping at index 0 and N-1)
   - Trim boost edge cases (boost window entry/exit, clamping to [-1, 1])
   - Map accessors (`get_button_is_switch_map`, `get_twist_knob_map_actions`) return correct data structures

3. **Smoke tests for main entry point wiring** — Verify that `BravoMultiMode.lua` can still initialize dispatch sub-modules and that the overall system behavior is preserved after refactoring.

## Out of Scope

- Refactoring BravoMultiMode.lua (the ~1,300-line main entry point) — this is a separate concern identified in SPIKE-003 but out of scope for this release plan.
- Testing custom aircraft modules (B58.lua, C90B.lua, DA42.lua, Transponder.lua) — explicitly excluded by REQ-007.
- Performance benchmarking of dispatch latency or command execution timing.

# Inputs to Review

1. **REQ-007** — FR-003 (Unit Tests for dispatch.lua): exhaustive list of all public functions and edge cases; Success Criteria per-module minimums (dispatch ≥80%).
2. **SPIKE-003** — Finding 1: Dispatch.lua analysis with testability score of 1/5, the god object problem description, coupling points, global state assessment (mutable local variables acting as singleton pattern), side-effect ratio (~85%); Finding 6: Code Quality Observations on dispatch.lua's nested loops and decision table complexity; Evaluation section recommending Option C (Hybrid) with targeted refactoring before testing.
3. **Existing source file**: Full text of `FlyWithLua/Modules/bravo++/dispatch.lua` (762 lines) — read in full to understand all functions, state variables, and the main entry point wiring at `BravoMultiMode.lua`.
4. **SPIKE-003 Next Steps** — Recommendation #3: "Create a separate design document for dispatch.lua splitting strategy" before any code changes begin; this feature plan serves as that design specification pending Lead approval of split boundaries.

# Implementation Tasks

1. **Review inputs and propose split boundaries**: Read dispatch.lua (762 lines) in full, identify all functions and state variables, draft the proposed module split with responsibility boundaries for each sub-module. Present to Lead for review before implementation begins.
2. **Create refactored module structure** (pending Lead approval of boundaries):
   - 2a. Create `dispatch_action_map.lua` — action map builder (`_build_button_action_map`) and mode cycling logic
   - 2b. Create `dispatch_buttons.lua` — button command executor (`button_begin`, `button_continue`, `button_end`, `resolve_button_command`)
   - 2c. Create `dispatch_twist.lua` — twist knob executor (`knob_increase`, `knob_decrease`) with priority resolution
   - 2d. Create `dispatch_trim.lua` — trim wheel executor (`trim_nose_up`, `trim_nose_down`) with boost logic and clamping
   - 2e. Create `dispatch_modes.lua` — mode cycling manager (activation/deactivation, selector index setting)
3. **Migrate state management**: Move mutable local variables from the original dispatch module into appropriate sub-module tables or a shared context table that all sub-modules can access without circular dependencies. Ensure no new global mutations are introduced.
4. **Update BravoMultiMode.lua wiring**: Modify the main entry point to import and initialize the refactored sub-modules instead of the single dispatch module; verify all function calls still resolve correctly.
5. **Write integration tests** (tests/integration/dispatch_spec.lua):
   - Test action map building: verify `_build_button_action_map` produces correct multi-dimensional tables from config bindings for mode-level, switch-mode UP/DOWN, and selection-aware paths
   - Test button lifecycle: `button_begin` resolves command via all three lookup paths; `button_continue` handles continuous mode + long-click detection correctly; `button_end` dispatches single click vs. long click based on elapsed time
   - Test twist knob priority: verify priority resolution (direct > OUTER > INNER) works correctly in each cf_mode state
   - Test mode cycling wrapping: `cycle_mode_up` and `cycle_mode_down` wrap indices correctly at boundaries for N-mode configurations
   - Test trim boost edge cases: boost window entry/exit, clamping to [-1, 1], no-boost behavior when outside boost window
6. **Run tests**: Execute integration test suite; all dispatch sub-module tests must pass with zero failures.
7. **Verify behavioral equivalence**: Run FEAT-014's hardware→decoder→dispatch pipeline smoke tests (or equivalent) to confirm main entry point wiring survives refactoring with no functional regressions.

# Acceptance Criteria

1. **No module exceeds 300 lines**: Each resulting dispatch sub-module (`dispatch_action_map.lua`, `dispatch_buttons.lua`, `dispatch_twist.lua`, `dispatch_trim.lua`, `dispatch_modes.lua`) is ≤300 lines of code.
2. **≥80% line coverage on refactored dispatch modules**: luacov reports ≥80% across all dispatch sub-modules when running the integration test suite.
3. **All public functions tested**: Every function identified in REQ-007's FR-003 has at least one corresponding integration test: action map building, mode cycling wrapping, CF/switch mode toggles, selector activation/deactivation, button press lifecycle (begin/continue/end), twist knob priority resolution, rocker switch dispatch, trim boost logic, and map accessors.
4. **No behavioral regressions**: The main entry point (`BravoMultiMode.lua`) wiring survives refactoring; all existing system behaviors for button/knob/switch input handling are preserved as verified by FEAT-014 integration tests or equivalent smoke tests.

# Definition of Done

1. All 4 acceptance criteria verified (see Acceptance Criteria section).
2. Lead has reviewed and approved the proposed module split boundaries before implementation begins.
3. luacov reports ≥80% line coverage on all dispatch sub-modules combined.
4. No regressions in existing decoder tests or other feature tests — all pass alongside new dispatch integration tests.
5. `BravoMultiMode.lua` updated to import refactored sub-modules; main entry point initialization completes without errors.

# Dependencies / Risks

## Dependencies

| # | Dependency | Type | Notes |
|---|-----------|------|-------|
| D1 | FEAT-010 (Test Infrastructure Reorganization) | Upstream | Bootstrap mocks for `_G.command_once`, `_G.command_begin`, `_G.command_end` must be in place before dispatch testing can proceed. |
| D2 | FEAT-002 equivalent (FEAT-011 — High-Purity Module Tests) | Parallel | util.lua tests provide confidence that shared helper functions used by dispatch sub-modules work correctly; not strictly blocking but recommended to run in parallel. |

## Risks

| # | Risk | Severity | Mitigation |
|---|------|----------|------------|
| R1 | **Refactoring introduces behavioral regressions** — Splitting the 762-line god object without breaking main entry point wiring could alter button/knob/switch behavior that directly affects pilot operation. This is SPIKE-003's highest-rated risk (R1). | HIGH | Lead must review and approve split boundaries before implementation begins. Integration tests for all dispatch sub-modules must pass BEFORE any refactoring changes are merged. Smoke test the main entry point wiring after each sub-module migration, not just at the end. |
| R2 | **State variable migration complexity** — Multiple mutable local variables (`current_mode`, `command_state[]`, `arrow_color`) persist as module-level locals in dispatch.lua with no reset function; migrating these to a shared context table across sub-modules risks introducing state leakage or race conditions. | MEDIUM | Design the shared context table carefully: all sub-modules access it through getter/setter functions rather than direct field access, enabling future reset functionality and making state mutations explicit and auditable. |
| R3 | **Over-splitting** — Creating too many tiny modules could make debugging harder (call chains span 5+ files) without meaningful testability gains. | LOW-MEDIUM | Keep the split to exactly 5 sub-modules as proposed; each must have a clear, single responsibility and be independently testable with at least 10 meaningful integration tests. If any module has fewer than 5 public functions, reconsider whether it should be merged into another. |
