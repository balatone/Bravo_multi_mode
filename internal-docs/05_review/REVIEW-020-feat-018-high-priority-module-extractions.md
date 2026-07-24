---
id: REVIEW-020
title: FEAT-018 High Priority Module Extractions
version: 1.2.0
status: APPROVED
created: 2026-07-24 15:41:31
updated: 2026-07-24 15:42:36
verdict: REQUEST_CHANGES
related_docs: ["FEAT-018"]
---
# Executive Summary

Review of FEAT-018 (High Priority Module Extractions) covering four modules extracted from `BravoMultiMode.lua`: **profiler.lua**, **config_loader.lua**, **rocker_switches.lua**, and **button_lifecycle.lua**. The implementation correctly extracts responsibility blocks into independently require'd modules with injection-based dependency wiring. One minor dead-code issue was identified in rocker_switches.lua (`_dispatch_callback_fn` is set but never used). No functional defects or behavioral regressions were found.

## Key Takeaway

FEAT-018 implementation is structurally sound and functionally correct. All four modules follow the project's module export pattern, maintain FlyWithLua callback integrity, and introduce zero global pollution. One minor cleanup item (dead code in rocker_switches.lua) should be addressed before final approval.

# Review Scope

## In Scope
- `FlyWithLua/Modules/bravo++/profiler.lua` — Performance profiler extraction
- `FlyWithLua/Modules/bravo++/config_loader.lua` — Config detection and parsing extraction
- `FlyWithLua/Modules/bravo++/rocker_switches.lua` — Rocker switch command router extraction
- `FlyWithLua/Modules/bravo++/button_lifecycle.lua` — AP button lifecycle manager extraction
- `BravoMultiMode.lua` changes (dependency wiring, removed inline code)
- Unit tests: `tests/unit/{profiler,config_loader,rocker_switches,button_lifecycle}_spec.lua`

## Out of Scope
- FEAT-017 LED engine modules (separate review cycle)
- Input handlers and mode manager extraction (FEAT-019)
- Full integration testing across all four aircraft configurations (B58, C90B, DA42, Transponder)

# Review Criteria

| Criterion | Status | Notes |
|-----------|--------|-------|
| Correctness & Logic | PASS | Behavioral parity verified via git diff comparison |
| Dependency Management | PASS | Injection-based wiring; no circular dependencies |
| Standards Compliance | PASS (with note) | Module export pattern correct; 1 luacheck warning |
| Code Quality | PASS | Clean encapsulation, proper LuaDoc annotations |
| Performance | PASS | No regressions in hot paths; zero overhead when disabled |
| Test Coverage | PASS | 35 new tests covering all public APIs and edge cases |

# Findings Summary

## [PASS] Correctness & Logic — All Four Modules
All four modules correctly extract their respective code blocks from `BravoMultiMode.lua` with preserved behavioral logic:

- **profiler.lua**: Cumulative profiler state (`_enabled`, `_log_interval`, `_tasks`, `_last_log_time`) properly encapsulated. The `start/stop/log_and_reset/toggle/is_enabled/log_task` API matches the original inline implementation exactly. Zero-overhead disabled path verified (early returns before any computation).
- **config_loader.lua**: Three-step config detection (exact → variant → generic fallback) logic preserved with identical regex patterns and file-listing behavior. `read_file`, `read_preferences`, and `build_validation_context` functions maintain original parsing semantics including quoted-string stripping, comment skipping, and indexed annunciator handling.
- **rocker_switches.lua**: Uniform loop pattern (7 switches × 2 directions = 14 commands) correctly extracted. Command naming convention (`FlyWithLua/Bravo++/rocker_switch{N}_{up|down}`) matches original exactly. Dispatch command strings (`bravo_dispatch('rocker_switch', N, 'DIR')`) preserved.
- **button_lifecycle.lua**: Three-phase lifecycle (begin/continue/end) for each AP button correctly extracted. Command naming convention and `bravo_dispatch` call patterns match the original inline loop.

## [PASS] Dependency Management — Injection-Based Wiring
All four modules follow the injection-based dependency pattern defined in DSGN-002:

| Module | Shared Dependencies | Injected Dependencies |
|--------|-------------------|----------------------|
| profiler.lua | `bravo++.log` | None (self-contained) |
| config_loader.lua | `bravo++.log`, `bravo++.util` | `file_provider` function, `aircraft_dir` string |
| rocker_switches.lua | `bravo++.log` | `dispatch_callback_fn`, `num_switches`, `create_command_fn` |
| button_lifecycle.lua | `bravo++.log` | `ap_buttons` table, `create_command_fn` |

No circular dependencies exist. The dependency graph is acyclic: all modules depend only on shared utilities (`log`, `util`) or receive their FlyWithLua-specific integrations via injection from the composition root (BravoMultiMode.lua).

## [PASS] Standards Compliance — Module Export Pattern
All four modules correctly implement the project's module export pattern:
- `local M = {}` at module start
- Public functions attached to `M` with LuaDoc annotations (`--- @param`, `--- @return`)
- `return M` at end of file

FlyWithLua callback integration maintained through wrapper functions in BravoMultiMode.lua:
```lua
function profiler_log_task() -- luacheck: ignore (used by do_every_frame string callback)
    profiler.log_task()
end
function profiler_toggle() -- luacheck: ignore (used by create_command callback)
    profiler.toggle()
end
do_every_frame("profiler_log_task()")
create_command(..., "profiler_toggle()", ...)
```

## [MINOR ISSUE] Dead Code in rocker_switches.lua — `_dispatch_callback_fn`
**Severity**: Low | **File**: `rocker_switches.lua:17`

The `_dispatch_callback_fn` variable is set during `init()` but never accessed anywhere in the module. The luacheck linter flags this as an unused variable warning:

```
FlyWithLua/Modules/bravo++/rocker_switches.lua:17:7: variable _dispatch_callback_fn is never accessed
```

The original inline code did not use a dispatch callback function — it directly called `create_command()` with command strings. The `_dispatch_callback_fn` parameter appears to be leftover from the design phase (DSGN-002 mentions injection of dispatch callbacks) but was never wired into the implementation. The module only uses `create_command_fn` for actual command registration, making `dispatch_callback_fn` dead code.

**Recommendation**: Remove the `_dispatch_callback_fn` parameter and its storage in `init()`. If future use is anticipated, document it as a planned injection point rather than leaving silent dead code.

## [INFO] Redundant Parameter in config_loader.detect_config
The `detect_config(aircraft_name, aircraft_dir)` method accepts both an explicit `aircraft_dir` parameter and falls back to `_aircraft_dir`. In practice (BravoMultiMode.lua), the caller always passes `aircraft_dir` explicitly:

```lua
local config_result = config_loader.detect_config(aircraft_name, aircraft_dir)
```

The fallback to `_aircraft_dir` is never exercised in production code. This is not a bug but adds unnecessary complexity. Consider whether the method should accept only one parameter or if dual-parameter support serves a testing purpose (e.g., per-call directory override).

# Required Changes Before Approval

## Blockers
- None identified.

## Major Issues
- None identified.

## Minor Issues
1. **rocker_switches.lua: `_dispatch_callback_fn` dead code** — The `dispatch_callback_fn` parameter is accepted in `init()` but never used. luacheck flags this as warning #17. Remove the unused variable and its assignment, or document it as a planned injection point with an explicit TODO comment.

# Positive Findings

1. **Clean Dependency Injection**: All four modules use consistent init-time dependency injection (`opts` table pattern), making them independently testable without FlyWithLua host dependencies.
2. **Zero Global Pollution**: No new global variables introduced. All module state is encapsulated in local variables within each module file. The only globals are the intentionally-named wrapper functions for FlyWithLua callbacks (matching existing patterns).
3. **Preserved Behavioral Parity**: Git diff comparison confirms that all original logic was faithfully extracted — regex patterns, config detection order, command naming conventions, and dispatch call strings are identical to pre-refactoring code.
4. **Comprehensive Test Coverage**: 35 new unit tests across four test files cover init edge cases (nil options), disabled-state behavior, enabled-state behavior, error paths, and happy-path scenarios for all public APIs.
5. **Proper LuaDoc Annotations**: All public functions have `--- @param` and `--- @return` annotations matching the project's documentation standards. Internal helpers use `local function` with appropriate type hints.
6. **Performance-Conscious Design**: The profiler has zero overhead when disabled (early returns before any computation). Config detection runs once at startup (not in hot paths). Command registration loops run once during initialization.

# Verification Results

| Check | Result | Details |
|-------|--------|---------|
| `luac -p` syntax validation | PASS | All four modules compile without errors |
| `luacheck` linting (all 24 bravo++ modules) | PASS (1 warning) | Only warning: `_dispatch_callback_fn` unused in rocker_switches.lua — not an error |
| Git diff behavioral comparison | PASS | All original logic preserved; no semantic changes |
| Module export pattern (`local M = {} ... return M`) | PASS | All four modules follow the standard pattern |
| Dependency injection consistency | PASS | All modules use `init(opts)` with typed parameter validation |
| Unit test execution (35 new tests) | PASS | 464 total tests passing, 0 failures |
| FlyWithLua callback integration | PASS | Wrapper functions maintain string-callback compatibility |

# Risks / Follow-ups

1. **Dead Code Cleanup**: The `_dispatch_callback_fn` in rocker_switches.lua should be removed or documented to prevent confusion for future contributors. This is a low-severity issue that does not block approval but should be addressed in the next maintenance cycle.
2. **Config Loader Parameter Redundancy**: Consider simplifying `detect_config()` to accept only one directory parameter, or document why dual-parameter support exists (testing convenience vs. production use).
3. **Integration Testing Gap**: This review did not verify behavior across all four aircraft configurations (B58, C90B, DA42, Transponder) in a live X-Plane environment. The existing unit tests cover logic paths but not hardware-specific integration. Recommend integration testing before merging to main.
4. **FEAT-018 Plan vs Implementation**: The FEAT-018 feature plan mentions `compile_condition` as part of config_loader's public API, but this function remains in the old `config.lua` module (which handles validation and condition compilation). This appears intentional — `config_loader` focuses on file detection/parsing while `config` handles validation. No action needed; just noting for documentation clarity.

# Supporting Materials / Evidence

## Code Comparison: profiler.lua
The extracted module preserves all original functionality:
- Original inline state: `PROFILER_ENABLED`, `profiler._tasks`, `profiler._last_log_time`, `profiler._log_interval` → Now encapsulated as local variables `_enabled`, `_tasks`, `_last_log_time`, `_log_interval`
- Original functions: `profiler.start/stop/log_and_reset/toggle` → Now methods on the module table with identical logic

## Code Comparison: config_loader.lua
The three-step detection algorithm is preserved exactly:
1. Exact match: `"bravo_multi-mode." .. aircraft_name .. ".cfg"`
2. Variant match: Regex `^bravo_multi%-mode%.` + escaped name + `%.[^.]+%. [cC][fF][gG]$`
3. Generic fallback: `"bravo_multi-mode.cfg"`

The file_provider injection replaces direct `util.list_files()` calls, enabling testability with mock filesystems.

## Code Comparison: rocker_switches.lua vs button_lifecycle.lua
Both modules follow the same pattern of accepting `create_command_fn` as an injected dependency rather than directly calling FlyWithLua's global `create_command()`. This decouples command registration from the host environment and enables testing without X-Plane/FlyWithLua.

## luacheck Output (all bravo++ modules)
```
Total: 1 warning / 0 errors in 24 files
Warning: rocker_switches.lua:17:7 — variable _dispatch_callback_fn is never accessed
```

## Git Diff Summary
- `BravoMultiMode.lua`: -192 lines (removed inline code), +44 lines (require/init calls) = net -148 lines
- Four new modules: +991 total lines across profiler, config_loader, rocker_switches, button_lifecycle
- Four test files: +365 total lines of unit tests
