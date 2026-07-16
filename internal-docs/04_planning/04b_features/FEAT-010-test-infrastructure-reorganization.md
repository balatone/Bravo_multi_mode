---
id: FEAT-010
title: Test Infrastructure Reorganization
version: 1.0.0
status: APPROVED
created: 2026-07-16 19:11:50
updated: 2026-07-16 19:19:21
related_docs: ["PLAN-005", "REQ-007"]
---
# Feature Overview

This feature establishes the foundational test infrastructure for REQ-007 by reorganizing the flat `tests/` directory into three independently runnable categories (`unit/`, `integration/`, `e2e/`) and enhancing `_bootstrap.lua` with all missing mocks identified in SPIKE-003. Without this foundation, no subsequent feature can write or execute tests reliably — every other feature depends on clean bootstrap mocks, correct package path resolution from any subdirectory depth, and a directory structure that supports Busted's recursive test discovery. This is the critical-path foundation for the entire 5-week release plan.

# Objectives

1. **Create three test subdirectories** (`tests/unit/`, `tests/integration/`, `tests/e2e/`) with proper Busted discoverability and `<module_name>_spec.lua` naming convention.
2. **Add missing mocks to `_bootstrap.lua`**: `_G.command_once`, `_G.command_begin`, `_G.command_end` (for dispatch.lua testing); `_G.dataref_table` and `_G.XPLMFindDataRef` (for config.lua validation and mapbuilder.lua LED initialization).
3. **Ensure package.path resolution** works from any subdirectory depth so `require("bravo++.xxx")` resolves identically regardless of test file location — compute parent directory dynamically rather than hardcoding relative paths.
4. **Preserve backward compatibility**: Existing invocations (`busted --helper=tests/_bootstrap.lua`) must continue to work via recursive glob; luacov coverage accumulation must be maintained using `decoder.reset()` + `state.reset()` between tests.
5. **Extend existing mocks** for all test categories: formalize `_G.advance_time()` / `_G.set_time()` as the canonical mock API across unit, integration, and e2e tests.

# Scope

## In Scope

1. **Directory creation**: Create `tests/unit/`, `tests/integration/`, `tests/e2e/` directories with README files explaining each category's purpose and execution method.
2. **Bootstrap mock additions** (per SPIKE-003 Finding 5):
   - `_G.command_once = function(...) end` — no-op stub for dispatch.lua action methods
   - `_G.command_begin = function(...) end` — no-op stub for command begin lifecycle
   - `_G.command_end = function(...) end` — no-op stub for command end lifecycle
   - `_G.dataref_table = function(...) return {} end` — returns empty table stub for mapbuilder.lua LED initialization and config.lua validation
   - `_G.XPLMFindDataRef = function(...) return nil end` — safe fallback for DataRef lookups in config.lua validation
3. **Package.path resolution**: Update `_bootstrap.lua` to compute its own parent directory dynamically (`package.loaded["bravo++"] or debug.getinfo(1, "S").source`) so `require("bravo++.xxx")` resolves from any subdirectory depth.
4. **Existing test migration**: Move existing `decoder_spec.lua` into the appropriate category (primarily `tests/unit/` with some scenarios in `tests/e2e/`). Preserve all 67 test cases and their assertions.
5. **Independent execution verification**: Confirm each category runs independently:
   - `busted --helper=tests/_bootstrap.lua tests/unit/` — passes with zero failures
   - `busted --helper=tests/_bootstrap.lua tests/integration/` — passes (empty initially, structure must be valid)
   - `busted --helper=tests/_bootstrap.lua tests/e2e/` — passes (empty initially, structure must be valid)

## Out of Scope

- Writing actual test cases for any module (handled by FEAT-011 through FEAT-014).
- Creating mock modules in `tests/mocks/` directory (deferred to individual feature implementations as needed).
- CI/CD pipeline setup for automated Lua test execution.
- Testing custom aircraft modules (`custom/B58.lua`, etc.) — explicitly excluded by REQ-007.

# Inputs to Review

1. **REQ-007** — Functional Requirements FR-001 (Test Folder Structure) and FR-011 (Test Infrastructure); Success Criteria 2–4; Technical Constraints section regarding FlyWithLua host dependencies, io.popen usage, os.clock() dependency, and package path resolution.
2. **SPIKE-003** — Finding 5 (Mocking Feasibility Assessment): Bootstrap Gap Summary listing the five specific additions needed to `_bootstrap.lua`; Mocking Strategy Recommendations in REQ-007's Notes section regarding X-Plane SDK functions, io.popen stubbing, time mocking extension, package path compatibility, and ImGui mocking.
3. **Existing test infrastructure**: `tests/_bootstrap.lua` (current mock patterns), `tests/init.lua`, `tests/bit.lua` shim, `tests/decoder_spec.lua` (67 test cases — the reference pattern for all new tests).
4. **Busted documentation** — Verify recursive directory traversal behavior and helper file loading to ensure subdirectory structure doesn't break discovery.

# Implementation Tasks

1. **Review inputs**: Read REQ-007 (FR-001, FR-011), SPIKE-003 (Finding 5 bootstrap gap summary and mocking recommendations), existing `tests/_bootstrap.lua`, and `tests/decoder_spec.lua` to understand current mock patterns and test structure.
2. **Create directory structure**: Create `tests/unit/`, `tests/integration/`, `tests/e2e/` directories; add a brief README.md in each explaining the category's purpose, execution command, and examples of what belongs there.
3. **Add mocks to `_bootstrap.lua`** (in order of dependency):
   - 1a. Add `_G.command_once = function(...) end` — no-op stub for dispatch.lua action methods
   - 1b. Add `_G.command_begin = function(...) end` — no-op stub for command begin lifecycle
   - 1c. Add `_G.command_end = function(...) end` — no-op stub for command end lifecycle
   - 1d. Add `_G.dataref_table = function(ref) return {} end` — returns empty table stub; add optional parameter support to accept DataRef name string
   - 1e. Add `_G.XPLMFindDataRef = function(...) return nil end` — safe fallback for config.lua validation and mapbuilder.lua LED initialization
4. **Fix package.path resolution**: Update `_bootstrap.lua` to compute its own parent directory dynamically (using `debug.getinfo(1, "S").source` or `package.loaded["bravo++"]` path) so that `require("bravo++.xxx")` resolves correctly from any subdirectory depth (`tests/unit/`, `tests/integration/`, `tests/e2e/`).
5. **Formalize time mock API**: Document `_G.advance_time()` and `_G.set_time()` as the canonical mock API in a comment block at the top of `_bootstrap.lua`; ensure they support absolute time setting for debounce/deduplication window testing (advancing by 25ms, 80ms increments).
6. **Migrate existing decoder tests**: Move `decoder_spec.lua` into `tests/unit/decoder_spec.lua`, preserving all 67 test cases and their assertions; identify which e2e scenarios from the original file should also be duplicated in `tests/e2e/`.
7. **Verify independent execution**: Run each category independently:
   - `busted --helper=tests/_bootstrap.lua tests/unit/` — must pass with zero failures (existing decoder tests)
   - `busted --helper=tests/_bootstrap.lua tests/integration/` — structure valid, no errors
   - `busted --helper=tests/_bootstrap.lua tests/e2e/` — structure valid, no errors
8. **Verify backward compatibility**: Run `busted --helper=tests/_bootstrap.lua tests/` (recursive) and confirm all existing decoder tests still pass with luacov accumulation working correctly.
9. **Add io.popen mock stub** (optional but recommended): Add a controllable `io.popen` replacement keyed by command substring pattern, as described in REQ-007's Notes section — this enables plugincheck.lua and config validation testing in later features.

# Acceptance Criteria

1. **Three subdirectories exist**: `tests/unit/`, `tests/integration/`, and `tests/e2e/` are present under `tests/`. No `.lua` test files remain at the top level of `tests/` (except `_bootstrap.lua` and `init.lua`).
2. **All required mocks present in `_bootstrap.lua`**: The following globals are mocked: `_G.command_once`, `_G.command_begin`, `_G.command_end`, `_G.dataref_table`, `_G.XPLMFindDataRef`. Each mock is functional (does not throw errors when called).
3. **Independent category execution**: All three categories run successfully in isolation with zero failures:
   - `busted --helper=tests/_bootstrap.lua tests/unit/` passes
   - `busted --helper=tests/_bootstrap.lua tests/integration/` runs without errors (may be empty)
   - `busted --helper=tests/_bootstrap.lua tests/e2e/` runs without errors (may be empty)
4. **Existing decoder tests preserved**: All 67 test cases from the original `decoder_spec.lua` pass after migration into the new directory structure, with identical assertions and behavior.
5. **Backward compatibility maintained**: `busted --helper=tests/_bootstrap.lua tests/` (recursive glob) still works and discovers all tests across subdirectories without errors.
6. **Package path resolution correct**: Tests in any subdirectory can successfully `require("bravo++.xxx")` for all modules (util, log, state, debug, config, decoder, hardware, dispatch, mapbuilder, ui, plugincheck).
7. **luacov accumulation preserved**: Coverage counts accumulate across test runs when using the reset pattern (`decoder.reset()` + `state.reset()`) between scenarios — no module reloading that would zero out coverage counters.

# Definition of Done

1. All 7 acceptance criteria verified (see Acceptance Criteria section).
2. `tests/unit/decoder_spec.lua` passes all original 67 test cases with zero failures.
3. `_bootstrap.lua` contains all required mocks and is documented with comments explaining each mock's purpose and the modules that depend on it.
4. README files exist in each subdirectory (`unit/`, `integration/`, `e2e/`) describing: category purpose, execution command, naming convention, and examples of what belongs there.
5. No regressions introduced — existing test invocations work identically to pre-refactoring behavior.
6. luacov coverage report from `busted --helper=tests/_bootstrap.lua tests/unit/` shows decoder.lua at ≥95% (maintaining the existing 95.65%).

# Dependencies / Risks

## Dependencies

| # | Dependency | Type | Notes |
|---|-----------|------|-------|
| D1 | None (foundation feature) | — | This is the critical-path foundation; no upstream dependencies. All other features depend on it. |
| D2 | Busted test framework installed at `/usr/share/lua/5.4/busted/` | External | No additional installation needed; verify version compatibility with recursive directory traversal. |
| D3 | luacov configured for coverage instrumentation | External | Already working with current `_bootstrap.lua`; must continue to work after mock additions and package.path changes. |

## Risks

| # | Risk | Severity | Mitigation |
|---|------|----------|------------|
| R1 | **Breaking existing decoder tests during migration** — Moving `decoder_spec.lua` into subdirectories could break require paths or test assertions if `_bootstrap.lua` package.path changes are incorrect. | HIGH | Run full regression suite (`busted --helper=tests/_bootstrap.lua tests/unit/`) after every change; keep a backup of the original file until all 67 tests pass in new location. |
| R2 | **Mock conflicts with FlyWithLua runtime** — Adding no-op mocks to `_G.command_once` etc. could interfere if any test accidentally runs in the actual FlyWithLua environment where these globals have real implementations. | LOW | Mocks should be idempotent (replacing a function with itself is harmless); add comments noting that mocks are CLI-specific and will be overridden at runtime by FlyWithLua. |
| R3 | **io.popen mock interfering with legitimate file operations** — If `io.popen` is replaced globally, it could break tests that legitimately need to read filesystem state (e.g., testing actual directory contents). | MEDIUM | Use a controllable stub keyed by command substring pattern rather than a blanket replacement; allow fallback to original `io.popen` for unmatched commands. |
| R4 | **Busted recursive traversal behavior differs from expected** — Busted may not recursively discover `.lua` files in subdirectories without explicit configuration, causing tests to be silently skipped. | MEDIUM | Test each category independently before declaring the feature complete; verify test count matches expectations (67 decoder tests should appear in unit/). |

# Implementation Notes

- **Mock ordering matters**: Add mocks to `_bootstrap.lua` before any module requires are executed. The existing pattern of mocking globals at bootstrap load time must be preserved — new mocks should follow the same structure as existing ones (`_G.logMsg`, `os.clock()` mock).
- **Package.path computation**: Use `debug.getinfo(1, "S").source` to find `_bootstrap.lua`'s own location relative to the project root. This is more robust than hardcoding `"../FlyWithLua/Modules"` because it works regardless of where Busted is invoked from (project root vs. tests directory).
- **io.popen mock pattern** (from REQ-007 Notes): Store controlled results in `_G.mock_io_results` keyed by command substring; iterate through patterns on each `io.popen` call and return a table with `lines()` and `close()` methods for matched commands, falling back to original `io.popen` for unmatched ones.
- **Time mock formalization**: The existing `_G.advance_time()` / `_G.set_time()` should be documented as the canonical API. All new test files (FEAT-011 through FEAT-014) must use these rather than introducing their own time mocking patterns. This ensures consistency across all test categories and prevents luacov accumulation issues from module reloading.
- **decoder_spec.lua migration**: The original file has 67 tests across 8 describe blocks. Most belong in `tests/unit/` (individual event detection, debounce suppression, deduplication). E2E scenarios (full HID report cycles) should be duplicated or moved to `tests/e2e/` while keeping the unit-level tests in place for fast iteration during development.
- **README files**: Each subdirectory README should include: (1) purpose of the category, (2) how to run it (`busted --helper=tests/_bootstrap.lua tests/<category>/`), (3) naming convention (`<module_name>_spec.lua`), (4) examples of what belongs there.
