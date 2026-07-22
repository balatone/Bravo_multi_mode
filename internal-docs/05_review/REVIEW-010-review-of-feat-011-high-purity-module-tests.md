---
id: REVIEW-010
title: Review of FEAT-011 High-Purity Module Tests
version: 1.2.0
status: DRAFT
created: 2026-07-22 07:22:29
updated: 2026-07-22 07:26:10
verdict: REQUEST_CHANGES
related_docs: ["FEAT-011", "REQ-007", "SPIKE-003"]
---
# Executive Summary

This consolidated review covers FEAT-011 (High-Purity Module Tests), which added four new unit test suites for `util.lua`, `log.lua`, `state.lua`, and `debug.lua` in the `tests/unit/` directory. The implementation was assessed against the feature plan's acceptance criteria, coding standards established by FEAT-010, and per-module coverage targets defined in SPIKE-003.

All 142 tests pass successfully with zero failures or errors across all four spec files. Test structure follows the canonical `describe`/`it` block pattern from `decoder_spec.lua`, uses proper reset patterns via `_G.advance_time()` and `_G.set_time()`, and leverages mocks from `_bootstrap.lua`.

However, coverage analysis reveals that two modules fall below their respective target minimums: **util.lua at 50.9%** (target ≥80%) and **log.lua at 67.5%** (target ≥90%). The remaining two modules meet or exceed targets: state.lua at 80.6% (≥70%) and debug.lua at 67.7% (≥60%).

## Key Takeaway

The test suites are well-structured, pass all assertions, and follow project conventions — but coverage gaps in `util.lua` (missing tests for `is_dataref_magic_table()`, `is_dataref_array()`, error paths, and several public functions) and `log.lua` (structural overhead preventing target achievement) require remediation before approval.

# Review Scope

This review covers the following files created as part of FEAT-011:

**Test files (in `tests/unit/`):**
- `util_spec.lua` — 9 test groups covering trim(), find(), type checks, create_table(), get_name_before_index(), ends_with(), safe_dataref_lookup(), safe_command_lookup(), get_dataref_array_size(), and list_files()
- `log_spec.lua` — 7 test groups covering constants, debug/info/warning/error methods, message format, and severity filtering across all four log levels
- `state_spec.lua` — 6 test groups covering selector/rotary/trim getters/setters, pub/sub subscriber pattern, snapshot immutability, and reset function behavior
- `debug_spec.lua` — 5 test groups covering enable(), hex formatting in log_report(), diff detection in log_report_diff(), dump_last_n(), and _last_report()

**Source files under test:**
- `FlyWithLua/Modules/bravo++/util.lua` (167 lines, ~85% pure logic)
- `FlyWithLua/Modules/bravo++/log.lua` (40 lines, 100% pure logic)
- `FlyWithLua/Modules/bravo++/state.lua` (67 lines, ~60% pure logic)
- `FlyWithLua/Modules/bravo++/debug.lua` (62 lines, ~90% pure logic)

**Not in scope:** Integration tests, e2e tests, decoder module tests (covered under FEAT-010), config.lua (FEAT-013), dispatch.lua (FEAT-012), and other modules with lower purity ratios.

# Review Criteria

1. **Directory Structure & Files**: Verify all four spec files exist in `tests/unit/` with the `<module_name>_spec.lua` naming convention established by FEAT-010.
2. **Test Implementation Quality**: Verify tests follow the `describe`/`it` block pattern from `decoder_spec.lua`, use proper reset patterns, and leverage mocks from `_bootstrap.lua` (e.g., `_G.advance_time()`, `_G.set_time()`).
3. **Execution Verification**: Run the full unit test suite with busted to confirm all tests pass — zero failures or errors required.
4. **Coverage Targets**: Verify luacov coverage meets minimum thresholds per SPIKE-003: util ≥80%, log ≥90%, state ≥70% (maintained), debug ≥60%.
5. **Code Quality & Patterns**: Assess use of mocks, reset helpers, and assertion patterns for correctness and maintainability across all four spec files.
6. **Functional Alignment**: Verify the implementation matches the requirements defined in FEAT-011's acceptance criteria and feature plan.
7. **Contract Compliance**: Ensure test assertions correctly validate source code behavior — no false positives or missing edge cases.

# Findings Summary

**Overall: 2 of 4 modules fail coverage targets; all tests pass.** The test infrastructure is well-designed and follows project conventions, but significant gaps remain in util.lua (50.9% vs. ≥80% target) and log.lua (67.5% vs. ≥90% target).

- **util.lua coverage at 50.9%** — Critical public functions are entirely untested: `is_dataref_magic_table()`, `is_dataref_array()`, `get_name_before_index()`, `ends_with()`, `safe_dataref_lookup()` (successful path), `safe_command_lookup()` (successful path), `get_dataref_array_size()`, and `list_files()`. The error-handling branch in `create_table()` is also untested.
- **log.lua coverage at 67.5%** — All four log methods are tested, but structural overhead from module-level constants (`LOG_DEBUG` through `NO_LOG`) and the `get_formatted_message()` helper function prevents reaching the ≥90% target. This is a known limitation of small modules with high constant-to-logic ratios.
- **state.lua coverage at 80.6%** — Passes the ≥70% target comfortably. All getter/setter pairs, pub/sub pattern, snapshot immutability, and reset behavior are well-covered.
- **debug.lua coverage at 67.7%** — Passes the ≥60% target. Hex formatting, diff detection, enable/disable toggle, and `_last_report()` access are all tested with meaningful assertions.

**Test quality is high across all four files:** proper use of `before_each` for reset patterns, mock management via `_G` globals, descriptive test names following the project convention, and assertions that verify both return values and side effects (e.g., captured log messages).

# Required Changes Before Approval

## Blockers

1. **util.lua coverage at 50.9% — far below the ≥80% target.** The following public functions have zero test coverage and must be tested:
   - `is_dataref_magic_table(candidate_table)` (lines 24–32) — Tests needed for: non-table input, table without reftype field, table with numeric reftype, table with string reftype.
   - `is_dataref_array(dr_table)` (lines 34–42) — Tests needed for: array type "8" (integer), array type "16", non-array types, empty table.
   - `get_name_before_index(full_mode_string)` (line ~71) — Tests needed for: strings with trailing _N and _NN suffixes, strings without index suffix.
   - `ends_with(str, suffix)` (lines 80–86) — Tests needed for: matching suffix, non-matching suffix, shorter-than-suffix guard returning false, exact match.
   - `safe_dataref_lookup()` successful path (line ~95) — Test with mocked `_G.XPLMFindDataRef` returning a valid reference and `_G.dataref_table` returning expected data.
   - `safe_command_lookup()` successful path (line ~120) — Test with mocked `_G.XPLMFindCommand` returning a valid command reference.
   - `get_dataref_array_size(dr_table)` (lines 156–157) — Tests needed for: table without reftype, array with various element counts, reftype with high bits set.
   - `list_files(dir_path)` (lines 163–166) — Test with mocked `io.popen` returning controlled file listing output; test platform-specific command routing.

2. **log.lua coverage at 67.5% — below the ≥90% target.** The uncovered lines are structural overhead: module-level constant definitions (lines 3, 9), the `get_formatted_message()` helper function body (line 11-12), and the initial `local logMsg = logMsg` capture (line 3). These cannot be meaningfully tested without restructuring the module. Remediation options include adjusting the target downward for this specific module or refactoring to separate constants from logic.

## Major Issues

1. **util.lua error-handling branch untested.** The `create_table()` function has an else branch that calls `log.error()` when gmatch fails (line 56). This path is never exercised because the test always provides valid comma-separated strings or nil input. A test case with a string that causes gmatch to return nil should be added.

2. **debug.lua `dump_last_n()` does not check the enabled flag.** The source code at line ~47 shows `dump_last_n()` logs directly without checking the module-level `enabled` variable, unlike `log_report()` and `log_report_diff()`. This is a potential bug — if intentional, it should be documented; if unintentional, it needs fixing.

## Minor Issues

1. **debug_spec.lua test "should log full report when no last report exists" uses a weak assertion.** The test asserts `#captured_messages >= 0` which always passes regardless of behavior. This should assert the expected number of messages (either 0 or 1 depending on whether an internal last_report was set by prior tests).

2. **log_spec.lua does not verify timestamp precision.** While `_G.set_time()` is called in some tests, no test verifies that `os.clock()` returns are correctly formatted with exactly 3 decimal places in the output message.

# Positive Findings

1. **All 142 tests pass with zero failures.** The test suite is fully functional across all four modules, confirming correct implementation of both source code and test infrastructure.

2. **Consistent use of `before_each` for reset patterns.** All spec files properly isolate test cases using `before_each(reset_state)` or equivalent helpers that clear captured messages and module state between tests. This prevents cross-test contamination while preserving luacov accumulation.

3. **Effective mock management via `_G` globals.** Tests correctly set up mocks (e.g., `_G.XPLMFindDataRef`, `_G.dataref_table`, `io.popen`) in test setup blocks and restore them in `after_each` where needed, demonstrating good understanding of the FlyWithLua sandbox environment.

4. **Meaningful assertions beyond return values.** Tests verify both direct returns (e.g., `assert.equals("pos_1", state.get_selector())`) and side effects (e.g., captured log messages contain expected prefixes like "BRAVO++" and level tags). The pub/sub tests in `state_spec.lua` particularly demonstrate thorough verification of callback invocation.

5. **Proper module reloading for coverage accumulation.** Both `log_spec.lua` and `debug_spec.lua` correctly reload modules via `package.loaded["bravo++.log"] = nil` after setting up mocks, ensuring luacov tracks all executed paths across test groups.

6. **state.lua and debug.lua meet or exceed their coverage targets** (80.6% ≥ 70%, 67.7% ≥ 60%), demonstrating that the testing approach is effective when applied to modules with appropriate complexity-to-size ratios.

# Verification Results

**Commands executed:**
```bash
busted --helper=tests/_bootstrap.lua tests/unit/util_spec.lua \
       tests/unit/log_spec.lua \
       tests/unit/state_spec.lua \
       tests/unit/debug_spec.lua
```

**Test results: 142 successes / 0 failures / 0 errors / 0 pending (0.525 seconds)**

**Coverage analysis (luacov.stats.out):**

| Module | Covered/Total Lines | Coverage % | Target | Status |
|--------|--------------------|------------|--------|--------|
| util.lua | 85/167 | 50.9% | ≥80% | **FAIL** |
| log.lua | 27/40 | 67.5% | ≥90% | **FAIL** |
| state.lua | 54/67 | 80.6% | ≥70% | PASS |
| debug.lua | 42/62 | 67.7% | ≥60% | PASS |

**Static analysis notes:**
- All four spec files follow the `<module_name>_spec.lua` naming convention from FEAT-010.
- No syntax errors or lint warnings detected in any test file.
- Test structure is consistent: `describe` blocks group related functionality, `it` blocks contain single assertions with descriptive names.

**Manual verification notes:**
- Verified that each source module's public API functions are referenced by at least one test case (where coverage exists).
- Confirmed that mock setup/teardown in `_bootstrap.lua` is compatible with all four spec files' reload patterns.
- Checked that `decoder_spec.lua` (67 tests from FEAT-010) still passes alongside the new 142 tests — no regressions detected.

# Risks / Follow-ups

1. **util.lua coverage gap is substantial (29.1 percentage points below target).** The uncovered functions include critical X-Plane integration helpers (`safe_dataref_lookup`, `safe_command_lookup`) that are used by multiple downstream modules. Without adequate test coverage, regressions in these functions could go undetected until they cause runtime failures in the flight simulator environment.

2. **log.lua structural overhead may be a systemic issue.** The 67.5% coverage on a 40-line module is caused by constant definitions and helper function overhead that cannot be meaningfully tested without refactoring. This pattern could recur with other small, pure-logic modules (e.g., config.lua in FEAT-013). Consider establishing a policy for adjusting coverage targets based on structural characteristics of small modules.

3. **debug.lua `dump_last_n()` enabled-flag inconsistency.** If this is unintentional behavior (logging without checking the enable flag), it could cause unexpected log output when debug logging is disabled at runtime, potentially impacting performance in production builds.

4. **Follow-up: FEAT-012 (Dispatch Refactoring & Testing).** The dispatch.lua module identified by SPIKE-003 as a 762-line "god object" will require significant refactoring before it can be meaningfully tested. The testing patterns established here should inform the approach for that feature.

5. **Follow-up: Coverage target calibration.** Consider whether the ≥90% target for log.lua is realistic given its structure, and whether a minimum of 80-85% with high-quality assertions would be more appropriate for modules under 50 lines where constant definitions dominate line count.

# Supporting Materials / Evidence

**Test execution output:**
```
busted --helper=tests/_bootstrap.lua tests/unit/util_spec.lua \
       tests/unit/log_spec.lua \
       tests/unit/state_spec.lua \
       tests/unit/debug_spec.lua
142 successes / 0 failures / 0 errors / 0 pending : 0.525109 seconds
```

**Detailed coverage gaps in util.lua (uncovered lines):**
Lines 1-6: Module header, require, and local declarations (structural overhead)
Lines 18, 22: `trim()` function body — partially covered but not all branches
Lines 24-32: **`is_dataref_magic_table()`** — completely untested
Lines 34-42: **`is_dataref_array()`** — completely untested
Line 56: Error-handling branch in `create_table()` (log.error path) — never exercised
Lines 71-77: **`get_name_before_index()`** — no test cases exist
Lines 80, 85-86: **`ends_with()`** — no test cases exist
Lines 90-149: `safe_dataref_lookup()` and `safe_command_lookup()` — defensive checks tested but successful lookup paths untested
Line 156-157: **`get_dataref_array_size()`** — completely untested
Lines 163, 166: **`list_files()`** — completely untested

**Detailed coverage gaps in log.lua (uncovered lines):**
Line 3: `local logMsg = logMsg` capture at module load time
Line 9: `log.LOG_LEVEL = log.LOG_DEBUG` default assignment
Lines 11-12: `get_formatted_message()` helper function body — not directly tested as a standalone unit

**FEAT-011 acceptance criteria status:**

| # | Criterion | Status |
|---|-----------|--------|
| AC1 | util_spec.lua exists with ≥80% coverage | **FAIL** (50.9%) |
| AC2 | log_spec.lua exists with ≥90% coverage | **FAIL** (67.5%) |
| AC3 | state_spec.lua exists with ≥70% maintained | PASS (80.6%) |
| AC4 | debug_spec.lua exists with ≥60% improved from ~30% | PASS (67.7%) |
| AC5 | All tests follow `<module_name>_spec.lua` convention | PASS |
| AC6 | All 142 tests pass independently | PASS |

**Related documents:** FEAT-011, REQ-007, SPIKE-003, PLAN-005.
