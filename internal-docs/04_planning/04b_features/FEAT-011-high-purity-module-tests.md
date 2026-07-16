---
id: FEAT-011
title: High-Purity Module Tests
version: 1.0.0
status: APPROVED
created: 2026-07-16 19:11:52
updated: 2026-07-16 19:19:21
related_docs: ["PLAN-005", "REQ-007"]
---
# Feature Overview

This feature writes comprehensive unit tests for the four highest-purity modules identified by SPIKE-003's side-effect analysis: `util.lua` (~85% pure logic, 167 lines), `log.lua` (100% pure, 40 lines), `state.lua` (~60% pure, 67 lines), and `debug.lua` (~90% pure, 62 lines). Together these modules total ~336 lines with an estimated ~80% pure logic ratio — the fastest path to meaningful coverage gains. These tests deliver quick percentage increases in overall project coverage while building confidence in the test infrastructure established by FEAT-010. This feature directly addresses REQ-007's FR-002 (config.lua is excluded here; it has its own feature), FR-008 (util.lua unit tests), and contributes to the per-module minimums defined in SPIKE-003's success criteria.

# Objectives

1. **Achieve ≥80% line coverage on util.lua** — Test all public functions: `trim()`, `find()`, type checks (`is_boolean`, `is_string`, `is_table`), `create_table()`, `ends_with()`, `get_name_before_index()`, `safe_dataref_lookup()` / `safe_command_lookup()` with defensive argument testing, and `list_files()` with mocked `io.popen`.
2. **Achieve ≥90% line coverage on log.lua** — Test severity level filtering (`LOG_LEVEL >= LOG_DEBUG`), timestamp formatting using the mocked `os.clock()`, message composition across all four levels (DEBUG, INFO, WARN, ERROR).
3. **Maintain ≥70% line coverage on state.lua** — Build on existing 71.43% coverage; add tests for pub/sub subscriber pattern (`subscribe_state`), snapshot immutability, `reset()` function behavior, and edge cases in getter/setter pairs.
4. **Improve debug.lua from ~30% to ≥60%** — Test hex formatting, diff detection logic between HID reports, enable/disable toggle via public API, `_last_report()` access, and conditional logging based on the module-level `enabled` flag.

# Scope

## In Scope

1. **util_spec.lua** (tests/unit/util_spec.lua):
   - `trim()`: whitespace stripping from both ends; edge cases with nil input, empty string, strings with only whitespace, mixed leading/trailing spaces
   - `find()`: index lookup in 1-based tables for present values and not-found scenarios returning nil
   - Type checks: `is_boolean`, `is_string`, `is_table` — correct type detection across Lua's type system (nil, boolean, number, string, table, function)
   - `create_table()`: comma-separated string parsing into arrays; empty table for nil input; single-element and multi-element strings
   - `ends_with()`: suffix matching with length guard (shorter string than suffix returns false); exact match and partial match cases
   - `safe_dataref_lookup()` / `safe_command_lookup()`: defensive argument checking — non-string rejection, nil handling, successful lookup paths via mocked `_G.XPLMFindDataRef` / `_G.XPLMFindCommand`
   - `list_files()`: file listing with mocked `io.popen`; platform-specific command routing (dir /b vs ls)

2. **log_spec.lua** (tests/unit/log_spec.lua):
   - Severity level filtering: messages at different levels are included/excluded based on configured LOG_LEVEL
   - Timestamp formatting using the mocked `_G.os.clock()` — verify format includes clock value and proper separators
   - Message composition for all four log levels (DEBUG, INFO, WARN, ERROR) with correct prefix formatting

3. **state_spec.lua** (tests/unit/state_spec.lua):
   - Getter/setter pairs: `get_selector()`, `set_selector()`, `get_rotary()`, `set_trim()` — verify state mutation and retrieval
   - Pub/sub subscriber pattern: `subscribe_state(callback)` registers callbacks; state changes trigger all subscribers via `pcall(fn, value)` for error isolation
   - Snapshot immutability: `snapshot()` returns a copy that is independent of subsequent state mutations
   - Reset function behavior: `reset()` restores initial values (selector=0, rotary=0, trim=0) and clears subscriber list

4. **debug_spec.lua** (tests/unit/debug_spec.lua):
   - Hex formatting: convert byte arrays to hex strings for HID report logging
   - Diff detection logic: compare two reports and identify changed bytes; format diffs as readable strings
   - Enable/disable toggle: `enable()` sets module-level flag; disabled state skips all log calls
   - `_last_report()`: verify the function returns the most recent stored report

## Out of Scope

- Testing config.lua (covered by FEAT-013 — Config Validation Extraction)
- Testing dispatch.lua (covered by FEAT-012 — Dispatch Refactoring & Testing)
- Testing hardware.lua, mapbuilder.lua, plugincheck.lua, ui.lua (these have lower purity ratios and are covered in later features or require refactoring first per SPIKE-003's hybrid strategy)
- Integration tests between these modules (covered by FEAT-014 — Integration & E2E Test Suite)

# Inputs to Review

1. **REQ-007** — FR-008 (Unit Tests for util.lua): exhaustive list of functions and edge cases; Success Criteria per-module minimums (util ≥80%, log maintain ≥70% → target 90%, debug improve from ~30% to ≥60%).
2. **SPIKE-003** — Finding 1: Module-by-Module Analysis for util.lua, log.lua, state.lua, and debug.lua; Testability scores (5/5, 5/5, 5/5, 4/5 respectively); Side Effects vs Pure Logic Ratio table showing ~85%, 100%, ~60%, ~90% pure logic.
3. **Existing decoder_spec.lua** — Reference pattern for test structure: `describe` / `it` blocks, helper functions (`make_report`, `_G.advance_time()`), reset patterns (`decoder.reset()` + `state.reset()`).
4. **Current source files**: Read full text of util.lua (167 lines), log.lua (40 lines), state.lua (67 lines), debug.lua (62 lines) to identify all public functions, edge cases, and internal helper functions that may need indirect testing.

# Implementation Tasks

1. **Review inputs**: Read REQ-007 FR-008, SPIKE-003 Finding 1 for the four target modules, existing decoder_spec.lua pattern, and full source files of util.lua, log.lua, state.lua, debug.lua.
2. **Write util_spec.lua** (tests/unit/util_spec.lua):
   - Test `trim()` with at least 5 test cases: leading spaces, trailing spaces, both ends, empty string, nil input
   - Test `find()` with at least 3 test cases: found value, not-found returning nil, table with nil elements
   - Test type checks (`is_boolean`, `is_string`, `is_table`) — verify correct classification for each Lua type (nil, boolean, number, string, table)
   - Test `create_table()` with at least 4 test cases: comma-separated multi-element, single element, empty string, nil input returning empty table
   - Test `ends_with()` with at least 3 test cases: matching suffix, non-matching suffix, shorter-than-suffix guard
   - Test `safe_dataref_lookup()` / `safe_command_lookup()`: mock `_G.XPLMFindDataRef` and `_G.XPLMFindCommand`; verify defensive argument checking rejects non-string inputs; verify successful lookup returns expected values
   - Test `list_files()` with mocked `io.popen` returning controlled file listing output
3. **Write log_spec.lua** (tests/unit/log_spec.lua):
   - Test severity filtering: set LOG_LEVEL to different values and verify messages at each level are included or excluded correctly
   - Test timestamp formatting: mock `_G.os.clock()` with known values; verify formatted output includes clock value in expected format
   - Test all four log levels (DEBUG, INFO, WARN, ERROR) produce correct prefix format (`[LEVEL]`)
4. **Write state_spec.lua** (tests/unit/state_spec.lua):
   - Test getter/setter pairs: set selector to various values and verify get returns them; same for trim
   - Test pub/sub: register multiple subscribers via `subscribe_state()`, call `set_selector()` or `set_trim()`, verify all callbacks are invoked with correct value via pcall error isolation
   - Test snapshot immutability: take snapshot, mutate state, verify snapshot is unchanged
   - Test reset function: set various non-zero values, call `reset()`, verify all return to initial values (0) and subscriber list is cleared
5. **Write debug_spec.lua** (tests/unit/debug_spec.lua):
   - Test hex formatting: convert byte arrays of known values to expected hex strings
   - Test diff detection: create two reports with known differences, verify diffs array contains correct changed bytes formatted as readable strings
   - Test enable/disable toggle: call `enable()`, verify subsequent log calls are made; disable and verify they are skipped
   - Test `_last_report()`: store a report via the internal mechanism, verify `_last_report()` returns it correctly
6. **Run tests**: Execute `busted --helper=tests/_bootstrap.lua tests/unit/` — all new spec files must pass with zero failures.
7. **Verify coverage**: Run luacov and verify per-module minimums: util ≥80%, log ≥90%, state ≥70% maintained, debug ≥60%.

# Acceptance Criteria

1. **util_spec.lua exists** in `tests/unit/` and covers all public functions of util.lua with at least 20 test cases total; luacov reports ≥80% line coverage on util.lua.
2. **log_spec.lua exists** in `tests/unit/` and covers severity filtering, timestamp formatting, and message composition across all four log levels; luacov reports ≥90% line coverage on log.lua.
3. **state_spec.lua exists** in `tests/unit/` and covers getter/setter pairs, pub/sub subscriber pattern, snapshot immutability, and reset function behavior; luacov maintains ≥70% line coverage on state.lua (no regression from existing 71.43%).
4. **debug_spec.lua exists** in `tests/unit/` and covers hex formatting, diff detection, enable/disable toggle, and `_last_report()` access; luacov reports ≥60% line coverage on debug.lua (improved from ~30%).
5. All new test files follow the `<module_name>_spec.lua` naming convention established in FEAT-010.
6. All tests pass with zero failures when run independently (`busted --helper=tests/_bootstrap.lua tests/unit/`).

# Definition of Done

1. All 6 acceptance criteria verified (see Acceptance Criteria section).
2. luacov reports show measurable coverage gains: util ≥80%, log ≥90%, state ≥70% maintained, debug ≥60%.
3. No regressions on existing decoder_spec.lua tests — all 67 original test cases still pass alongside new unit tests.
4. All test files use the canonical mock API (`_G.advance_time()`, `_G.set_time()`) for time mocking rather than introducing custom patterns.
5. Tests follow the reset pattern (`decoder.reset()` + `state.reset()`) between scenarios to preserve luacov accumulation across all test runs.

# Dependencies / Risks

## Dependencies

| # | Dependency | Type | Notes |
|---|-----------|------|-------|
| D1 | FEAT-010 (Test Infrastructure Reorganization) | Upstream | Must complete before this feature — bootstrap mocks, directory structure, and package.path resolution are prerequisites. |
| D2 | Existing decoder_spec.lua pattern | Reference | The 67-test reference pattern in decoder_spec.lua defines the test structure convention for all new unit tests. |

## Risks

| # | Risk | Severity | Mitigation |
|---|------|----------|------------|
| R1 | **safe_dataref_lookup / safe_command_lookup require extensive mocking** — These functions call `_G.XPLMFindDataRef` and `_G.XPLMFindCommand`; testing them requires setting up controlled mock return values for every DataRef/command name that might be looked up. | MEDIUM | Mock at the global level in _bootstrap.lua (added by FEAT-010); write tests that verify defensive argument checking rejects non-string inputs, and test successful paths with predictable mock returns. Don't attempt to exhaustively test every possible DataRef lookup — focus on the function's defensive behavior. |
| R2 | **log.lua coverage may be artificially high** — With only 40 lines and simple formatting logic, achieving ≥90% coverage is straightforward but doesn't reflect real complexity. The value is in establishing a testing pattern rather than pushing for maximum percentage. | LOW | Accept that log.lua's high coverage is expected; focus effort on util.lua (167 lines) where the most test cases will be needed. |
| R3 | **state.lua subscriber callback errors** — The pub/sub pattern uses `pcall(fn, value)` per subscriber for error isolation. Testing this requires deliberately introducing failing callbacks to verify pcall catches them without crashing the state system. | LOW-MEDIUM | Write explicit tests that register a failing callback (one that throws) and verify subsequent subscribers still execute; verify the state module doesn't crash when a subscriber errors. |
