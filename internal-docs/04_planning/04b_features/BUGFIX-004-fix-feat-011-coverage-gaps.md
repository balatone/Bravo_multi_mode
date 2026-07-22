---
id: BUGFIX-004
title: fix-feat-011-coverage-gaps
version: 1.0.0
status: APPROVED
created: 2026-07-22 07:42:25
updated: 2026-07-22 07:53:51
related_docs: ["FEAT-011"]
---
# Summary

Remediate coverage gaps identified in REVIEW-010 to bring `util.lua` from 50.9% to ≥80% and address the structural coverage limitation in `log.lua` (67.5%, target ≥90%) by either proposing a refactor or recommending a target adjustment. This bugfix addresses two of four modules that failed their per-module coverage targets under FEAT-011.

# Scope

## In Scope

### util.lua — Missing test cases to reach ≥80% coverage
Add tests for the following functions identified as having zero or insufficient coverage in REVIEW-010:

1. **`is_dataref_magic_table(candidate_table)`** (util.lua lines 24–32)
   - Test non-table input returns `false`.
   - Test table without `reftype` field returns `false`.
   - Test table with numeric `reftype` returns `true`.
   - Test table with string `reftype` returns `false`.

2. **`is_dataref_array(dr_table)`** (util.lua lines 34–42)
   - Test array type `"8"` (integer reftype for single float).
   - Test array type `"16"` (double array).
   - Test non-array types return `false`.
   - Test empty table returns `false`.

3. **`get_name_before_index(full_mode_string)`** (util.lua line ~71)
   - Test string with trailing `_N` suffix → strips it.
   - Test string with trailing `_NN` suffix → strips it.
   - Test string without index suffix → returns unchanged.

4. **`ends_with(str, suffix)`** (util.lua lines 80–86)
   - Test matching suffix returns `true`.
   - Test non-matching suffix returns `false`.
   - Test shorter-than-suffix guard returns `false`.
   - Test exact match returns `true`.

5. **`safe_dataref_lookup()` successful path** (util.lua line ~95)
   - Test with mocked `_G.XPLMFindDataRef` returning a valid reference and `_G.dataref_table` returning expected data.

6. **`safe_command_lookup()` successful path** (util.lua line ~120)
   - Test with mocked `_G.XPLMFindCommand` returning a valid command reference.

7. **`get_dataref_array_size(dr_table)`** (util.lua lines 156–157)
   - Test table without `reftype` returns `nil`.
   - Test array with various element counts.
   - Test reftype with high bits set (low 12 bits = element count).

8. **`list_files(dir_path)`** (util.lua lines 163–166)
   - Test with mocked `io.popen` returning controlled file listing output.
   - Test platform-specific command routing (`dir /b` on Windows, `ls -1` on POSIX).

9. **`create_table()` error-handling branch** (util.lua line 56)
   - The else branch that calls `log.error()` when gmatch fails must be exercised with a string input that causes the gmatch iterator to return nil.

### log.lua — Structural coverage limitation remediation
The following lines are structural overhead and cannot be meaningfully tested without refactoring:
- Line 3: `local logMsg = logMsg` capture at module load time
- Lines 9–13: Module-level constant definitions (`LOG_DEBUG`, `LOG_INFO`, `LOG_WARNING`, `LOG_ERROR`, `NO_LOG`)
- Lines 15–17: `get_formatted_message()` helper function body

**Recommended approach**: Propose a refactor to separate constants from logic, or recommend adjusting the coverage target downward for modules under ~40 lines where constant definitions dominate line count. See "Proposed Fix" section below.

## Out of Scope

- Tests for `state.lua` and `debug.lua` — both already meet their targets (80.6% ≥ 70%, 67.7% ≥ 60%).
- Integration tests or e2e tests.
- Coverage changes to any modules other than util.lua and log.lua.

# Proposed Fix

## Part A: util.lua test additions

Add new `describe`/`it` blocks in `tests/unit/util_spec.lua` for each uncovered function listed above. Follow the established patterns from existing tests:
- Use `_G` global mocking where needed (e.g., `_G.XPLMFindDataRef`, `_G.dataref_table`, `_G.XPLMFindCommand`).
- Restore mocks in `after_each` blocks to prevent cross-test contamination.
- Use descriptive test names following the project convention (`should ... when ...`).

## Part B: log.lua remediation — Two options

### Option 1 (Preferred): Refactor constants out of logic module

Extract constant definitions from `log.lua` into a separate configuration or constants file, reducing the line count of the logic-bearing portion and making coverage targets achievable. For example:

```lua
-- bravo++/config/constants.lua (new)
return {
    LOG_DEBUG = 4,
    LOG_INFO = 3,
    LOG_WARNING = 2,
    LOG_ERROR = 1,
    NO_LOG = 0,
}
```

Then `log.lua` would import these constants and focus purely on the logging logic. This reduces structural overhead in coverage metrics while maintaining clean separation of concerns.

### Option 2: Adjust target downward for small modules

Establish a policy that modules under ~50 lines with high constant-to-logic ratios have adjusted targets (e.g., ≥80% instead of ≥90%). Document this as a follow-up to SPIKE-003 or REQ-007. This is the quicker path but leaves the structural issue unresolved for future small modules (e.g., config.lua in FEAT-013).

**Recommendation**: Pursue Option 1 (refactor) as it addresses the root cause and prevents recurrence across future features. The refactor should be minimal — extract constants only, do not restructure the logging logic itself.

# Implementation Tasks

1. **Analyze current coverage baseline.** Run luacov on all four modules to confirm exact line counts and identify which specific lines in util.lua remain uncovered after adding tests for the functions listed above.

2. **Add `is_dataref_magic_table` tests** — 4 test cases covering non-table, no-reftype, numeric reftype (true), string reftype (false).

3. **Add `is_dataref_array` tests** — 4 test cases covering type "8", type "16", non-array types, empty table.

4. **Add `get_name_before_index` tests** — 3 test cases for _N suffix, _NN suffix, and no-suffix inputs.

5. **Add `ends_with` tests** — 4 test cases for matching suffix, non-matching suffix, shorter-than-suffix guard, exact match.

6. **Add `safe_dataref_lookup` successful path test** — Mock `_G.XPLMFindDataRef` and `_G.dataref_table`, verify return value is a table with expected content.

7. **Add `safe_command_lookup` successful path test** — Mock `_G.XPLMFindCommand`, verify it returns `true`.

8. **Add `get_dataref_array_size` tests** — 3–4 test cases covering no-reftype, various element counts, high bits set.

9. **Add `list_files` tests** — Test mocked `io.popen` output and platform-specific command routing.

10. **Exercise `create_table()` error-handling branch** — Determine if the else branch (line 56) is reachable with any valid string input, or if it requires a code change to make it testable. If unreachable, document as dead code; if reachable, add appropriate test case.

11. **Implement log.lua refactor OR target adjustment.**
    - If refactoring: Create `config/constants.lua` (or similar), extract LOG_* constants, update `log.lua` imports, ensure all dependent modules still work.
    - If adjusting targets: Update SPIKE-003 or create a follow-up document documenting the new policy for small-module coverage thresholds.

12. **Run full test suite** — Execute busted on all four spec files to confirm zero failures and verify luacov reports meet targets.

# Acceptance Criteria

- [ ] `util.lua` luacov coverage reaches ≥80% (from current 50.9%).
- [ ] All new tests for util.lua functions pass with zero failures.
- [ ] `log.lua` remediation is complete — either:
    - The module has been refactored to remove structural overhead, and coverage meets the original ≥90% target; OR
    - A documented policy adjustment has been made lowering the target for small modules (≤50 lines) with high constant-to-logic ratios.
- [ ] All 142 existing tests continue to pass — no regressions introduced.
- [ ] Test structure follows established conventions: `describe`/`it` blocks, proper reset patterns via `before_each`, mock management via `_G` globals.

# Verification Plan

1. **Run full test suite:**
   ```bash
   busted --helper=tests/_bootstrap.lua \
          tests/unit/util_spec.lua \
          tests/unit/log_spec.lua \
          tests/unit/state_spec.lua \
          tests/unit/debug_spec.lua
   ```
   Expected: 142+ successes, 0 failures.

2. **Run coverage analysis:**
   ```bash
   # Run luacov to generate updated stats
   luacov busted --helper=tests/_bootstrap.lua tests/unit/*.lua
   cat luacov.stats.out
   ```
   Expected: util.lua ≥80%, log.lua remediation target met.

3. **Verify no regressions:** Confirm `decoder_spec.lua` (67 tests from FEAT-010) still passes alongside the new test suite.

4. **Manual inspection:** Review each newly added test case to ensure assertions are meaningful (not trivially true like `#messages >= 0`).

# Risks / Notes

- **create_table() error branch may be unreachable.** The else branch at line 56 requires gmatch to return nil, but since we always append a comma (`value_string .. ","`), the pattern `"([^,]*),"` should always match. If this branch is dead code, it should either be removed or replaced with an explicit validation check that can actually fail.
- **log.lua refactor may affect dependent modules.** Any module requiring `bravo++.log` and referencing LOG_* constants directly (e.g., `require("bravo++.log").LOG_DEBUG`) will need to be updated if constants are moved to a separate file. Audit all consumers before refactoring.
- **io.popen mocking for list_files()** requires careful mock setup since io.popen is used by the Lua runtime itself in some contexts. Ensure mocks don't interfere with other tests.
- **Coverage accumulation across test files.** luacov accumulates coverage across all spec files run in a single invocation. Tests must not reset module state in ways that prevent path execution (e.g., clearing `package.loaded` between individual test groups within the same file).

# Supporting Materials

## REVIEW-010 Coverage Gap Summary

| Module | Current % | Target | Gap | Status |
|--------|-----------|--------|-----|--------|
| util.lua | 50.9% | ≥80% | -29.1pp | FAIL — requires new tests |
| log.lua | 67.5% | ≥90% | -22.5pp | FAIL — structural issue |
| state.lua | 80.6% | ≥70% | +10.6pp | PASS |
| debug.lua | 67.7% | ≥60% | +7.7pp | PASS |

## Uncovered Functions in util.lua (from REVIEW-010)

```
Lines 24–32:   is_dataref_magic_table() — completely untested
Lines 34–42:   is_dataref_array()     — completely untested
Line ~71:      get_name_before_index() — no test cases (NOTE: tests may now exist)
Lines 80,85-86: ends_with()           — no test cases (NOTE: tests may now exist)
Line ~95:      safe_dataref_lookup()   — successful path untested (NOTE: test may now exist)
Line ~120:     safe_command_lookup()   — successful path untested (NOTE: test may now exist)
Lines 156-157: get_dataref_array_size() — completely untested
Lines 163,166: list_files()            — completely untested
Line 56:       create_table() error branch — never exercised
```

## log.lua Structural Overhead (untestable lines)

```lua
local log = logMsg                          -- line 3: module load capture
log.LOG_DEBUG = 4                           -- line 9: constant definition
log.LOG_INFO = 3                            -- line 10: constant definition
log.LOG_WARNING = 2                         -- line 11: constant definition
log.LOG_ERROR = 1                           -- line 12: constant definition
log.NO_LOG = 0                              -- line 13: constant definition

local function get_formatted_message(level, message)   -- lines 15-17: helper body
    return string.format("%.3f [BRAVO++ %s]: %s", os.clock(), level, message)
end
```

These 9 of 40 lines (22.5%) are structural overhead that cannot be tested without refactoring the module's design. The four public methods (`debug`, `info`, `warning`, `error`) and their guard conditions account for the remaining testable logic.
