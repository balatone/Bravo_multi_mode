---
id: PLAN-005
title: Release Plan — Lua Test Coverage & Infrastructure Improvements
version: 1.0.0
status: APPROVED
created: 2026-07-16 19:04:13
updated: 2026-07-16 19:19:21
related_docs: ["REQ-007", "SPIKE-003", "FEAT-010", "FEAT-011", "FEAT-012", "FEAT-013", "FEAT-014"]
---
# Release Summary

This release delivers a comprehensive test infrastructure overhaul for the Bravo++ FlyWithLua plugin, targeting an increase in Lua module test coverage from 38.37% to ≥80%. The release encompasses five discrete features spanning test reorganization, unit testing of high-purity modules, refactoring and testing of the dispatch.lua god object (762 lines), extraction of config validation logic, and a full integration/E2E test suite. Spanning 5 weeks across three phases, this plan maps REQ-007's eleven functional requirements into actionable work packages while addressing SPIKE-003's architectural findings — notably the hybrid strategy of testing easy modules first while planning refactoring for dispatch/config/ui in parallel.

# Timebox

- Start: 2026-07-20 (Monday, following sprint planning)
- End: 2026-08-21 (Friday, end of Week 5)
- Duration: 5 weeks / 3 phases

# Release Goal

Achieve ≥80% line coverage across all `FlyWithLua/Modules/bravo++/*.lua` source files while restructuring the test directory from a flat layout into three independently runnable categories (`unit/`, `integration/`, `e2e/`). The release must deliver: (1) zero-regression migration of existing decoder tests, (2) comprehensive unit tests for all seven previously uncovered modules (config, dispatch, hardware, mapbuilder, plugincheck, ui, util), (3) targeted refactoring of the dispatch.lua god object into ≤300-line sub-modules to improve testability and maintainability, (4) extraction of pure config validation logic from side-effect-producing DataRef lookups, and (5) integration/E2E tests validating the full hardware→decoder→dispatch pipeline with mode-switching workflows. The business value is a safety net for future development — at 38% coverage, any refactoring or feature addition to dispatch.lua (the system's input-to-action "brain") carries unquantified regression risk; ≥80% coverage eliminates this blind spot and enables confident CI gating on test pass rate.

# Features Included

## FEAT-010: Test Infrastructure Reorganization

**Scope:** Restructure the flat `tests/` directory into three subdirectories (`unit/`, `integration/`, `e2e/`) with `<module_name>_spec.lua` naming convention. Enhance `_bootstrap.lua` with missing mocks identified in SPIKE-003:
- Mock `_G.command_once`, `_G.command_begin`, `_G.command_end` (critical for dispatch.lua testing)
- Mock `_G.dataref_table` and `_G.XPLMFindDataRef` (needed by config.lua validation and mapbuilder.lua LED initialization)
- Extend existing mocks (`_G.logMsg`, `os.clock()` via `advance_time`/`set_time`) to support all test categories
- Ensure `package.path` resolution works from any subdirectory depth so `require("bravo++.xxx")` resolves identically regardless of test file location

**Dependencies:** None (foundation feature — must complete before other features can fully execute)

**Estimated effort:** 1 week (Weeks 1–2, parallel with FEAT-011)

## FEAT-011: High-Purity Module Tests

**Scope:** Write unit tests for the four highest-purity modules identified in SPIKE-003's side-effect analysis:
- **util.lua** (~85% pure logic, 167 lines): `trim()`, `find()`, type checks (`is_boolean`, `is_string`, `is_table`), `create_table()`, `ends_with()`, `safe_dataref_lookup()` / `safe_command_lookup()` with defensive argument testing
- **log.lua** (100% pure, 40 lines): Severity level filtering, timestamp formatting via `os.clock()`, message composition
- **state.lua** (~60% pure, 67 lines): Getter/setter pairs, pub/sub subscriber pattern (`subscribe_state`), snapshot immutability, reset function behavior
- **debug.lua** (~90% pure, 62 lines): Hex formatting, diff detection logic, enable/disable toggle, `_last_report()` access

**Dependencies:** FEAT-010 (bootstrap mocks must be in place)

**Estimated effort:** 1 week (Weeks 1–2, parallel with FEAT-010)

## FEAT-012: Dispatch Refactoring & Testing

**Scope:** Split dispatch.lua's 762-line god object into smaller, testable modules per SPIKE-003 recommendation:
- **Action map builder**: Extract `_build_button_action_map` (~150 lines) and mode cycling logic (`cycle_mode_up`, `cycle_mode_down`, `cycle_cf_mode`, `cycle_switch_mode`)
- **Button command executor**: `button_begin`, `button_continue`, `button_end` with single-click vs. long-click dispatch, continuous mode handling
- **Twist knob executor**: `knob_increase`, `knob_decrease` with priority resolution (direct > OUTER > INNER based on cf_mode)
- **Trim wheel executor**: `trim_nose_up`, `trim_nose_down` with boost window logic and clamping to [-1, 1]
- **Mode cycling manager**: Mode select activation/deactivation, selector index setting with label updates

Each sub-module must be ≤300 lines. Write integration tests covering: button press lifecycle across all three dispatch paths, twist knob priority resolution in all cf_mode states, mode cycling boundary conditions (N-mode wrapping), trim boost edge cases.

**Dependencies:** FEAT-010 (bootstrap mocks for `_G.command_once/begin/end`); FEAT-011 (util.lua tests provide confidence for shared helper usage)

**Estimated effort:** 1.5 weeks (Weeks 3–4, parallel with FEAT-013)

## FEAT-013: Config Validation Extraction

**Scope:** Extract pure condition compilation logic from config.lua's side-effect-heavy validation pipeline:
- Create a dedicated `condition_compiler` module containing `compile_condition()` and `eval_condition()` — these are the only truly testable parts of config.lua (~40 lines, 100% pure)
- Isolate `validate_keys()` (key existence/type checks) from `validate_values()` (which triggers DataRef lookups via `safe_dataref_lookup`/`safe_command_lookup`)
- Write unit tests for the condition compiler covering all 6 operators (`!=`, `<=`, `>=`, `<`, `>`, `=`), bare number equality, and invalid-condition fallback behavior
- Write integration tests verifying dispatch.init() correctly builds action maps from parsed config bindings

**Dependencies:** FEAT-010 (bootstrap mocks for `_G.XPLMFindDataRef`/`_G.dataref_table`)

**Estimated effort:** 1 week (Weeks 3–4, parallel with FEAT-012)

## FEAT-014: Integration & E2E Test Suite

**Scope:** Write cross-module integration tests and end-to-end workflow simulations:
- **Integration**: Decoder→State subscriber notification chain; Config+Dispatch action map construction verification; Hardware injection queue → decoder event detection pipeline
- **E2E**: Full HID report cycle (baseline → rotary CW → selector change → trim pulse → CCW rotary); rapid mixed events with debouncing across all three features simultaneously; mode cycling workflow (switch modes, toggle CF mode, activate/deactivate mode select, verify twist knob priority resolution changes)
- **UI/Plugincheck**: Mocked ImGui rendering tests for `ui.lua` text wrapping and LRU cache eviction; bridge detection logic tests for `plugincheck.lua` with mocked `io.popen`

**Dependencies:** FEAT-010 (all mocks), FEAT-012 (dispatch refactoring must be complete to test new module boundaries)

**Estimated effort:** 1 week (Week 5, after FEAT-012 and FEAT-013 completion)

# Sequencing / Dependencies

## Delivery Phases

### Phase 1 — Quick Wins (Weeks 1–2): FEAT-010 + FEAT-011

**Rationale:** SPIKE-003's hybrid strategy recommends building momentum with high-purity modules first. Util.lua (~85% pure), log.lua (100% pure), state.lua, and debug.lua require minimal mocking effort and deliver the fastest coverage percentage gains. Simultaneously, FEAT-010 establishes the test infrastructure foundation — bootstrap mocks, directory structure, and package path resolution — that all subsequent features depend on.

**Dependencies:** None between Phase 1 features (they run in parallel). Both feed into Phase 2.

### Phase 2 — Hard Modules Refactoring & Testing (Weeks 3–4): FEAT-012 + FEAT-013

**Rationale:** The two most architecturally challenging modules are dispatch.lua (762-line god object, ~85% side effects) and config.lua (side-effect-heavy validation). SPIKE-003 recommends targeted refactoring before testing begins for both. These features run in parallel because they target different source files but share the bootstrap mock foundation from Phase 1.

**Dependencies:** Both depend on FEAT-010 completion. FEAT-013's condition compiler extraction is independent of FEAT-012's dispatch split, enabling true parallel execution.

### Phase 3 — Integration & E2E Validation (Week 5): FEAT-014

**Rationale:** Cross-module integration tests require all refactored modules to be in place and tested individually before validating end-to-end workflows. The hardware→decoder→dispatch pipeline, mode-switching scenarios, and UI/plugincheck mocked tests can only be written after Phase 2 deliverables are stable.

**Dependencies:** Depends on FEAT-010 (all mocks), FEAT-012 (dispatch module boundaries must be finalized), and FEAT-013 (config validation extraction).

## Dependency Graph

```
FEAT-010 ──────────────┬──→ FEAT-011
                        │
                        ├──→ FEAT-012 ──→ FEAT-014
                        │       ↑
                        ├──→ FEAT-013 ──┘
```

FEAT-010 is the critical path foundation. Phase 2 features (FEAT-012, FEAT-013) are parallelizable and feed into Phase 3's integration tests.

# Milestones

| # | Milestone | Target Date | Deliverable |
|---|-----------|-------------|-------------|
| M1 | Test Infrastructure Ready | Week 2, Day 5 (2026-07-31) | `tests/unit/`, `tests/integration/`, `tests/e2e/` directories exist; `_bootstrap.lua` has all required mocks (`command_once/begin/end`, `dataref_table`, `XPLMFindDataRef`); each category runs independently via Busted with zero failures on existing decoder tests |
| M2 | High-Purity Coverage Complete | Week 2, Day 5 (2026-07-31) | util.lua ≥80%, log.lua ≥90%, state.lua ≥70% maintained, debug.lua ≥60%; all unit specs follow `<module_name>_spec.lua` naming convention; luacov reports show measurable coverage gains from Phase 1 modules |
| M3 | Dispatch Refactoring Complete | Week 4, Day 5 (2026-08-14) | dispatch.lua split into ≤300-line sub-modules; all integration tests for button lifecycle, twist knob priority, mode cycling wrapping pass; no behavioral regressions in main entry point wiring |
| M4 | Config Validation Extracted | Week 4, Day 5 (2026-08-14) | `condition_compiler` module with tested `compile_condition()` and `eval_condition()` covering all 6 operators; config validation tests pass; dispatch.init() integration verified against refactored config |
| M5 | Integration & E2E Suite Complete | Week 5, Day 5 (2026-08-21) | All cross-module integration tests pass; full HID cycle and mode-switching E2E scenarios pass; ui.lua mocked ImGui tests pass; plugincheck bridge detection tests pass with mocked `io.popen` |
| M6 | Final Coverage Verification | Week 5, Day 5 (2026-08-21) | luacov reports ≥80% overall coverage; per-module minimums met (decoder ≥95%, state ≥70%, log ≥70%, debug ≥60%, all new modules ≥80%); no regressions on any existing test |

# Risks / Constraints

## Technical Risks

| # | Risk | Severity | Mitigation |
|---|------|----------|------------|
| R1 | **dispatch.lua refactoring introduces regressions** — Splitting the 762-line god object without breaking main entry point wiring could alter button/knob/switch behavior that directly affects pilot operation. | HIGH | SPIKE-003 recommends comprehensive integration tests *before* merging any dispatch refactor. Phase 2 must deliver passing integration tests for all dispatch sub-modules before FEAT-014 begins. The Lead should review the split boundaries (action map builder, button executor, twist knob executor, trim wheel executor, mode cycling manager) before implementation starts. |
| R2 | **Config validation side effects during testing** — `validate_values()` calls `safe_dataref_lookup()` and `safe_dataref_command_lookup()` which invoke FlyWithLua host functions (`XPLMFindDataRef`, `XPLMFindCommand`). These cannot be fully mocked without extensive stubbing of every possible key pattern. | MEDIUM | Extract the pure condition compilation logic into a separate module (FEAT-013). Test validation separately with controlled mock returns for DataRef/command existence checks. Do not attempt to test the full validation pipeline in CLI — accept that some validation paths require FlyWithLua runtime integration testing. |
| R3 | **ImGui mocking complexity** — ui.lua (517 lines) and plugincheck.lua call numerous ImGui methods (`Dummy`, `CalcTextSize`, `SetWindowFontScale`, `DrawList_AddCircle`) that are unavailable in CLI without a partial mock covering only used functions. | MEDIUM | Create a minimal `tests/mocks/imgui.lua` stubbing only the specific imgui methods actually called by ui.lua and plugincheck.lua. Focus FEAT-014's UI tests on pure computation paths (text wrapping, LRU cache eviction) rather than rendering assertions. Accept that full ImGui integration testing requires FlyWithLua runtime. |
| R4 | **io.popen behavior differences** — `plugincheck.lua` uses platform-specific commands (`dir /b`, `ls`) via `io.popen`. CLI behavior may differ from the FlyWithLua sandbox environment, making tests fragile. | LOW-MEDIUM | Mock `io.popen` at the bootstrap level with controlled output keyed by command substring pattern (as recommended in REQ-007's Notes section). Test detection logic against mock outputs rather than real filesystem state. |
| R5 | **Test rewrite after refactoring** — Writing tests for dispatch.lua or config.lua before refactoring may result in wasted effort if the public API changes during FEAT-012/FEAT-013. | MEDIUM | Follow SPIKE-003's hybrid strategy: do NOT write unit tests for dispatch/config until after their refactored module boundaries are defined and approved. Write integration-level smoke tests only to validate that the main entry point wiring survives refactoring. |

## Constraints

| # | Constraint | Impact |
|---|-----------|--------|
| C1 | **FlyWithLua sandbox limitations** — Globals like `do_every_frame`, `create_command` cannot be meaningfully mocked in CLI; they require actual X-Plane/FlyWithLua runtime for integration testing. | Custom aircraft modules (B58, C90B, DA42, Transponder) are out of scope per REQ-007's explicit exclusion list. |
| C2 | **No existing CI/CD pipeline** — The busted test suite has no automated execution in the project's development workflow. Coverage regressions won't be caught automatically during this release. | Recommend establishing GitHub Actions or similar for Lua test execution as a post-release follow-up item (not within PLAN-005 scope). |
| C3 | **Coverage accumulation requirement** — luacov coverage counts must accumulate across all test categories. Tests must use `decoder.reset()` + `state.reset()` between scenarios rather than module reloading. | All new tests must follow the existing reset pattern; bootstrap must ensure no state leakage between test runs. |
| C4 | **Source file modification restriction** — REQ-007 explicitly forbids modifying source files under `FlyWithLua/Modules/bravo++/*.lua` or `FlyWithLua/Scripts/`. The dispatch.lua refactoring (FEAT-012) is a planned exception that requires Lead approval before implementation. | This plan's FEAT-012 represents the only authorized deviation from this constraint, contingent on Lead review of the split boundaries. |
| C5 | **Backward compatibility** — Existing test invocations (`busted --helper=tests/_bootstrap.lua`) must continue to work after restructuring via recursive glob. | `_bootstrap.lua`'s `package.path` setup and Busted's recursive directory traversal must both be preserved or enhanced, not replaced. |

## Dependencies on External Factors

- **Busted test framework** (installed at `/usr/share/lua/5.4/busted/`) — no additional dependencies needed
- **luacov** for coverage instrumentation — already configured and working with `_bootstrap.lua`
- **tests/bit.lua shim** — provides bitwise operations in place of LuaBitOp; must remain accessible from all test subdirectories via `package.path`

# Success Criteria

The release is considered **COMPLETE** when ALL of the following criteria are met:

### Coverage Metrics (Machine-verifiable via luacov)

1. **≥80% overall line coverage**: `busted --helper=tests/_bootstrap.lua tests/` reports ≥80% across all `FlyWithLua/Modules/bravo++/*.lua` files when analyzed by luacov.
2. **Per-module minimums maintained or exceeded**:
   - `decoder.lua`: maintain ≥95% (currently 95.65%)
   - `state.lua`: maintain ≥70% (currently 71.43%)
   - `log.lua`: maintain ≥70% (currently 72.73%)
   - `debug.lua`: improve from ~30% to ≥60%
   - All previously uncovered modules (`config`, `dispatch`, `hardware`, `mapbuilder`, `plugincheck`, `ui`, `util`): achieve ≥80% each

### Structural Criteria (Verifiable via filesystem inspection)

3. **Three test directories exist**: `tests/unit/`, `tests/integration/`, and `tests/e2e/` are present with spec files following `<module_name>_spec.lua` naming convention.
4. **No stray `.lua` test files** remain at the top level of `tests/` (except `_bootstrap.lua` and `init.lua`).

### Execution Criteria (Verifiable via Busted exit codes)

5. **Independent category execution**: Each category runs successfully in isolation:
   - `busted --helper=tests/_bootstrap.lua tests/unit/` — passes with zero failures
   - `busted --helper=tests/_bootstrap.lua tests/integration/` — passes with zero failures
   - `busted --helper=tests/_bootstrap.lua tests/e2e/` — passes with zero failures

### Regression Criteria (Verifiable via test comparison)

6. **Zero regressions**: All existing decoder_spec.lua tests (67 test cases covering rotary events, selector changes, trim edge detection, debounce suppression, deduplication, state integration, diagnostics, and full E2E HID cycles) pass after migration into the new directory structure.
7. **No behavioral change in main entry point**: `BravoMultiMode.lua` wiring survives dispatch refactoring (FEAT-012) with no functional regressions — verified by FEAT-014 integration tests covering hardware→decoder→dispatch pipeline and mode-switching workflows.

### Refactoring Criteria (Verifiable via code inspection)

8. **dispatch.lua split complete**: No individual module resulting from the dispatch refactoring exceeds 300 lines, with clear responsibility boundaries between action map builder, button executor, twist knob executor, trim wheel executor, and mode cycling manager.
9. **Condition compiler extracted**: `compile_condition()` and `eval_condition()` exist in a dedicated testable module (FEAT-013), separate from config.lua's side-effect-producing validation logic.

### Acceptance Gate

All 9 criteria must be satisfied before the Lead can approve this release plan as complete. The final luacov report at M6 serves as the primary acceptance gate — if coverage falls below 80% after all features are delivered, the Lead may reject and require additional test writing in a follow-up cycle.

# Resource Requirements

| Role | Responsibility | Allocation |
|------|---------------|------------|
| **Lead** (Archetype) | Review and approve dispatch.lua split boundaries before FEAT-012 implementation; gate promotions between DRAFT → IN_REVIEW → APPROVED status; final acceptance of all 9 success criteria at M6 | ~2 hours total (review gates at M1, M3/M4, M5/M6) |
| **Technical Analyst** | Deep-dive analysis of dispatch.lua sub-module boundaries and config.lua validation extraction strategy; produce design specifications for FEAT-012/FEAT-013 refactoring before implementation begins | ~8 hours (Weeks 1–2, parallel with FEAT-010) |
| **Engineer(s)** — Test Infrastructure | Implement FEAT-010: directory reorganization, `_bootstrap.lua` mock extensions, package path resolution fixes | ~3 days (Week 1) |
| **Engineer(s)** — Unit Tests | Write unit tests for high-purity modules in FEAT-011; write integration/E2E tests in FEAT-014 | ~4 days combined across Weeks 1–5 |
| **Engineer(s)** — Refactoring | Execute dispatch.lua split (FEAT-012) and config validation extraction (FEAT-013); ensure main entry point wiring survives refactoring | ~5 days (Weeks 3–4) |

**Total estimated effort:** ~23 engineer-hours + analyst time, spread across the 5-week timeline.

# Revision Notes

Use this section for release-plan updates, additions, or sequencing changes as new features are introduced.
