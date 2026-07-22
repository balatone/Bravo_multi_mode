---
id: REVIEW-012
title: Review of FEAT-013 implementation
version: 1.2.0
status: DRAFT
created: 2026-07-22 13:35:16
updated: 2026-07-22 13:37:13
verdict: REQUEST_CHANGES
related_docs: ["FEAT-013", "TASK-0008"]
---
# Executive Summary

This review covers the implementation of FEAT-013: Config Validation Extraction. The feature extracts pure condition compilation and evaluation logic from `config.lua` into a new standalone module `condition_compiler.lua`, while preserving backward-compatible wrapper functions in the config module. A comprehensive test suite (53 unit tests + 20 integration tests) was added, claiming effective coverage of 80.7%.

**Verdict: REQUEST_CHANGES** — The extraction is structurally sound and all six operators are correctly handled with strong test coverage. However, two issues require attention before approval: an untested public API function (`read_preferences`) that may affect coverage metrics, and a duplicated validation function (`is_valid_condition` in config.lua) that creates long-term maintenance risk.

## Key Takeaway

The pure logic extraction from `config.lua` into `condition_compiler.lua` was done correctly with proper operator precedence handling and comprehensive test coverage. The main concerns are an untested public API function and a duplicated validation helper that should be consolidated.

# Review Scope

**In scope:**
- `FlyWithLua/Modules/bravo++/config.lua` — Refactored config module (pure logic extracted, wrappers retained)
- `FlyWithLua/Modules/bravo++/condition_compiler.lua` — New pure condition compiler module
- `tests/unit/condition_compiler_spec.lua` — Unit test suite for condition_compiler (53 tests)
- `tests/integration/config_dispatch_spec.lua` — Integration test suite for config + dispatch (20 tests)

**Out of scope:**
- Other bravo++ modules not affected by this extraction
- Dispatch refactoring (FEAT-012, previously reviewed in REVIEW-011)
- E2E test infrastructure (handled in FEAT-010/FEAT-011)

# Review Criteria

- **Correctness**: All 6 operators (!=, <=, >=, <, >, =) compile and evaluate correctly.
- **Architecture / design alignment**: Pure logic extracted to a side-effect-free module; config.lua retains backward-compatible wrappers with context-aware logging.
- **Test coverage**: Unit tests cover all operators, edge cases (nil, whitespace, special chars), round-trip scenarios, and error paths. Integration tests verify delegation chain and dispatch.init() compatibility.
- **Code quality**: Clean separation of concerns, named operator functions for testability, proper fail-safe defaults.
- **Maintainability**: Operator registry pattern enables easy extension; multi-char operators checked first to prevent prefix collisions.

# Findings Summary

1. **[PASS] Pure logic extraction is correct.** `condition_compiler.lua` contains zero side effects — no logging, no file I/O, no module dependencies beyond Lua standard library. All operator comparison functions are named individually for testability and coverage tracking.
2. **[PASS] All 6 operators handled correctly.** OPERATOR_ORDER ensures multi-char operators (`!=`, `<=`, `>=`) are checked before single-char prefixes (`<`, `>`, `=`). Both modules use identical ordering, ensuring consistency between the pure module and config.lua's inline validation.
3. **[ISSUE-1] Uncovered public API: `read_preferences`.** The function is exposed via `config.read_preferences` but has zero test coverage in either unit or integration suites. This may drag effective coverage below 80%.
4. **[ISSUE-2] Duplicated validation logic.** `is_valid_condition()` in config.lua duplicates the operator parsing logic from condition_compiler. While it serves a different purpose (validation during config parsing vs compilation), the duplication creates maintenance risk if the two implementations diverge over time.

# Required Changes Before Approval

## Blockers

None identified. The implementation is functionally correct and all tests pass.

## Major Issues

- **`read_preferences` not tested**: This function is part of the public API (exposed via `config.read_preferences`) but has zero test coverage. A simple integration test that creates a temporary config file with key=value pairs, calls `read_preferences`, and verifies the returned table should be added to either `condition_compiler_spec.lua` or `config_dispatch_spec.lua`.

## Minor Issues

- **Duplicated `is_valid_condition` logic**: Consider consolidating by having `is_valid_condition()` delegate to `condition_compiler.compile_condition()`. The current inline parsing (checking OPERATOR_ORDER and tonumber) duplicates the exact same logic in condition_compiler. A future refactor could replace it with a delegation pattern that checks whether the compiled predicate is the always-false fallback. This is a low-priority suggestion since the current approach works correctly.

# Positive Findings

- **Clean module separation**: `condition_compiler.lua` is a pure functional module with no side effects — exactly what was required for testability and reusability.
- **Named operator functions**: Each comparison (`op_neq`, `op_leq`, etc.) has a descriptive name, making the code self-documenting and individually coverable by tests.
- **Fail-safe default**: Invalid conditions return `{ op = always_false_op, threshold = 0 }` — a graceful degradation that prevents crashes while signaling "always OFF" behavior for LEDs.
- **Context-aware logging in wrappers**: `config.compile_condition()` adds context (key name) to warning messages when invalid conditions are detected, improving debuggability without polluting the pure module.
- **Comprehensive edge case coverage**: Unit tests cover nil input, numeric/boolean coercion, whitespace stripping, scientific notation (`1e2`), large numbers, and special characters — all important for robustness in a flight simulation config system.
- **Round-trip testing**: The integration test suite includes compile→eval round-trips that verify the full pipeline works end-to-end through both modules.

# Verification Results

**Files inspected:**
1. `FlyWithLua/Modules/bravo++/config.lua` (620 lines) — Refactored with wrappers delegating to condition_compiler
2. `FlyWithLua/Modules/bravo++/condition_compiler.lua` (85 lines) — New pure module
3. `tests/unit/condition_compiler_spec.lua` (274 lines, 53 tests) — Comprehensive unit coverage
4. `tests/integration/config_dispatch_spec.lua` (190 lines, 20 tests) — Integration and delegation verification

**Checks performed:**
- [PASS] All six operators (!=, <=, >=, <, >, =) compile correctly in condition_compiler
- [PASS] Multi-char operator precedence verified (`<=5` matches `<=`, not `<`)
- [PASS] Bare number conditions compile as equality checks
- [PASS] Invalid conditions return always-false predicate
- [PASS] Edge cases: nil input, numeric/boolean coercion, whitespace handling
- [PASS] Config module wrappers delegate correctly to condition_compiler
- [PASS] Integration tests verify dispatch.init() compatibility with new structure
- [FAIL] `read_preferences` function has zero test coverage

**Test counts:** 53 unit + 20 integration = 73 total tests. Claimed effective coverage: 80.7%. All 347 tests in the full suite pass (includes previously reviewed FEAT-010 through FEAT-012).

# Risks / Follow-ups

- **Coverage gap risk**: If `read_preferences` is counted as uncovered code, effective coverage may drop below the 80% threshold. Recommend adding a simple test to close this gap.
- **Logic drift risk**: The duplicated `is_valid_condition()` in config.lua and `compile_condition()` in condition_compiler share identical parsing logic. Without automated synchronization checks, they could diverge over time. Consider extracting shared validation into a third utility module or having one delegate to the other.
- **Backward compatibility**: Exposing `config.compile_condition` and `config.eval_condition` as wrappers preserves backward compatibility for any external code that may call them directly. This is good practice but adds indirection overhead (negligible in Lua).

# Supporting Materials / Evidence

**Code paths verified:**
- `condition_compiler.compile_condition(">=5")` → `{ op = op_geq, threshold = 5 }` ✓
- `config.compile_condition(">0", "TEST_LED")` → delegates to condition_compiler with context logging ✓
- `config.eval_condition(1, pred)` → delegates to condition_compiler.eval_condition(pred, 1) ✓
- Invalid condition `"invalid"` → `{ op = always_false_op, threshold = 0 }` (always returns false) ✓

**Operator precedence verification:**
```lua
-- OPERATOR_ORDER in both files: { "!=", "<=", ">=", "<", ">", "=" }
-- This ensures multi-char operators are checked before single-char prefixes
-- e.g., "<=5" matches "<=" not "<" because "<=" appears first in the list
```

**Delegation chain verified:**
```
condition_compiler.compile_condition()  [pure, no side effects]
    ↑ delegated by
config.compile_condition(cond_str, context)  [adds logging with context]
    ↑ used by
config.validate_values() → is_valid_condition()  [inline validation during config parsing]

condition_compiler.eval_condition(pred, value)  [pure evaluation]
    ↑ delegated by
config.eval_condition(val, compiled_cond)  [wrapper for backward compatibility]
```
