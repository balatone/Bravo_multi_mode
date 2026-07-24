---
id: BUGFIX-009
title: Remove dead code in rocker_switches and simplify config_loader.detect_config
version: 1.0.0
status: APPROVED
created: 2026-07-24 15:48:02
updated: 2026-07-24 15:52:00
related_docs: ["REVIEW-020"]
---
# Summary

This BUGFIX addresses two issues identified in **REVIEW-020** (FEAT-018 code review):

1. **Dead Code**: `rocker_switches.lua` contains an unused `_dispatch_callback_fn` variable that is set during `init()` but never accessed — flagged by luacheck as warning #17.
2. **Redundant Parameter**: `config_loader.detect_config(aircraft_name, aircraft_dir)` accepts a second parameter (`aircraft_dir`) that always shadows the internal `_aircraft_dir` fallback, which is never exercised in production code.

Both issues are low-severity cleanup items with no functional impact but should be resolved to eliminate linter warnings and reduce API complexity.

# Scope

This BUGFIX modifies only two files within the `bravo++` module directory, with corresponding test updates. No behavioral changes are introduced — both fixes are purely structural/cleanup.

Use `related_docs` in the YAML preamble to link to the bug report that this fix addresses.

## In Scope

- **rocker_switches.lua**: Remove `_dispatch_callback_fn` variable declaration (line 17), its doc comment (lines 23–24), and its assignment block (lines 30–32). Update module header comment on line 9.
- **config_loader.lua**: Simplify `detect_config()` signature from `(aircraft_name, aircraft_dir)` to `(aircraft_name)`, removing the redundant second parameter and its fallback logic (`or _aircraft_dir`).
- **BravoMultiMode.lua** (Scripts): Update the single call site of `detect_config` to pass only one argument.
- **rocker_switches_spec.lua**: Remove `dispatch_callback_fn` from test init calls where it is passed but not asserted.
- **config_loader_spec.lua**: Update tests that pass a second argument to `detect_config()` — remove the redundant parameter and add a new test verifying fallback to `_aircraft_dir`.

## Out of Scope

- Any changes to profiler.lua or button_lifecycle.lua (not flagged in REVIEW-020).
- Integration testing across all four aircraft configurations.
- Adding new public APIs or changing module export patterns.

# Proposed Fix

## Issue 1: Remove `_dispatch_callback_fn` from rocker_switches.lua

The `dispatch_callback_fn` parameter was designed as an injection point per DSGN-002 but was never wired into the implementation. The module exclusively uses `create_command_fn` for command registration, and all dispatch logic goes through string-based commands (`bravo_dispatch('rocker_switch', N, 'DIR')`).

**Action**: Remove lines 17 (variable declaration), 9 (header comment reference), 23–24 (doc comment), and 30–32 (assignment block). The `init()` function will accept only `num_switches` and `create_command_fn`.

## Issue 2: Simplify config_loader.detect_config signature

The current signature `detect_config(aircraft_name, aircraft_dir)` with fallback to `_aircraft_dir` adds complexity without benefit. In production (BravoMultiMode.lua line 173), the caller always passes `aircraft_dir` explicitly. The fallback is only exercised in tests where `nil` is passed intentionally.

**Action**: Change signature to `detect_config(aircraft_name)` and use `_aircraft_dir` directly as the directory source. Update the single call site in BravoMultiMode.lua and adjust test cases accordingly.

# Implementation Tasks

## Task 1: Remove dead `_dispatch_callback_fn` from rocker_switches.lua

**File**: `FlyWithLua/Modules/bravo++/rocker_switches.lua`

### Step 1a — Update module header comment (line 9)

**Before:**
```lua
-- Dependencies: log; injects dispatch_callback_fn.
```

**After:**
```lua
-- Dependencies: log; injects num_switches, create_command_fn.
```

### Step 1b — Remove unused variable declaration (line 17)

**Delete this line entirely:**
```lua
local _dispatch_callback_fn = nil
```

### Step 1c — Update LuaDoc comment on init() (lines 23–24)

**Before:**
```lua
---   - dispatch_callback_fn: function (name, ...) → any
---   - num_switches: integer (default 7)
```

**After:**
```lua
---   - num_switches: integer (default 7)
---   - create_command_fn: function (dataref, description, press, repeat_, release)
```

### Step 1d — Remove assignment block in init() (lines 30–32)

**Delete these lines:**
```lua
    if opts.dispatch_callback_fn and type(opts.dispatch_callback_fn) == "function" then
        _dispatch_callback_fn = opts.dispatch_callback_fn
    end
```

## Task 2: Simplify config_loader.detect_config signature

**File**: `FlyWithLua/Modules/bravo++/config_loader.lua`

### Step 2a — Update LuaDoc comment (lines 43–45)

**Before:**
```lua
--- @param aircraft_name string  Aircraft name (e.g. "C90B")
--- @param aircraft_dir string   Aircraft directory path
--- @return table  { path: string|nil, found: boolean }
function M.detect_config(aircraft_name, aircraft_dir)
    local dir = aircraft_dir or _aircraft_dir
```

**After:**
```lua
--- @param aircraft_name string  Aircraft name (e.g. "C90B")
--- @return table  { path: string|nil, found: boolean }
function M.detect_config(aircraft_name)
    local dir = _aircraft_dir
```

### Step 2b — Remove fallback logic and update error message

**Before:**
```lua
    if not dir then
        log.error("config_loader.detect_config: no aircraft directory specified")
        return { path = nil, found = false }
    end
```

**After (unchanged behavior — `_aircraft_dir` is still validated):**
```lua
    -- _aircraft_dir must be set via init() before calling detect_config.
    if not dir then
        log.error("config_loader.detect_config: aircraft directory not configured")
        return { path = nil, found = false }
    end
```

## Task 3: Update call site in BravoMultiMode.lua

**File**: `FlyWithLua/Scripts/BravoMultiMode.lua` (line ~173)

### Step 3a — Simplify the detect_config call

**Before:**
```lua
local config_result = config_loader.detect_config(aircraft_name, aircraft_dir)
```

**After:**
```lua
local config_result = config_loader.detect_config(aircraft_name)
```

## Task 4: Update unit tests

### Step 4a — rocker_switches_spec.lua

Remove `dispatch_callback_fn` from all test init calls where it is passed but not asserted. The following lines need updating:
- Line 10–13 (test "should accept dispatch_callback_fn and num_switches") → rename to "should accept num_switches and create_command_fn"
- Lines 32–35 (test "should log error when create_command_fn not set")
- Lines 40–49 (test "should create commands for all switches")

### Step 4b — config_loader_spec.lua

Update the test at line 23 ("should return not found when no aircraft directory"):

**Before:**
```lua
config_loader.init({})
local result = config_loader.detect_config("C90B", nil)
assert.is_false(result.found)
assert.is_nil(result.path)
```

**After:**
```lua
config_loader.init({})  -- no aircraft_dir set
local result = config_loader.detect_config("C90B")  -- single argument only
assert.is_false(result.found)
assert.is_nil(result.path)
```

Update the test at line 35 ("should return not found when no config files exist"):

**Before:**
```lua
local result = config_loader.detect_config("C90B", "/test/dir/")
```

**After:**
```lua
-- aircraft_dir is set via init(), detect_config uses it internally
config_loader.init({
    file_provider = function(path) return {} end,
    aircraft_dir = "/test/dir/",
})
local result = config_loader.detect_config("C90B")  -- single argument only
```

## Task 5: Verify linting passes

Run luacheck on both modified files to confirm the warning is resolved and no new warnings are introduced.

# Acceptance Criteria

1. **No luacheck warnings**: Running `luacheck FlyWithLua/Modules/bravo++/rocker_switches.lua` produces zero warnings (previously had 1 warning for `_dispatch_callback_fn`).
2. **All unit tests pass**: All 464 existing tests continue to pass, including the updated rocker_switches and config_loader test suites.
3. **Behavioral parity preserved**: The `detect_config()` function returns identical results as before — same three-step detection algorithm (exact → variant → fallback), same return format `{ path, found }`.
4. **BravoMultiMode.lua compiles cleanly**: Running `luac -p FlyWithLua/Scripts/BravoMultiMode.lua` succeeds without syntax errors.
5. **No new globals introduced**: The rocker_switches module still has zero global pollution after removing `_dispatch_callback_fn`.
6. **Call site updated**: BravoMultiMode.lua line ~173 calls `detect_config(aircraft_name)` with a single argument, matching the simplified signature.

# Verification Plan

## Step 1: Syntax Validation

```bash
luac -p FlyWithLua/Modules/bravo++/rocker_switches.lua
luac -p FlyWithLua/Modules/bravo++/config_loader.lua
luac -p FlyWithLua/Scripts/BravoMultiMode.lua
```

All three must compile without errors.

## Step 2: Linting

```bash
# Verify the specific warning is gone
luacheck FlyWithLua/Modules/bravo++/rocker_switches.lua

# Full project lint — expect zero warnings (previously had 1)
luacheck FlyWithLua/Modules/bravo++/
```

Expected: `Total: 0 warnings / 0 errors in N files`

## Step 3: Unit Tests

Run the full test suite via busted:

```bash
busted tests/unit/rocker_switches_spec.lua
busted tests/unit/config_loader_spec.lua
```

Then run all unit tests to confirm no regressions:

```bash
busted tests/unit/
```

Expected: All 464 tests pass, 0 failures.

## Step 4: Integration Check (if applicable)

If the project has integration test targets:

```bash
busted tests/integration/
```

Verify no regressions in config loading across aircraft configurations.

## Manual Checks

1. Verify that `rocker_switches.lua` header comment on line 9 no longer mentions `dispatch_callback_fn`.
2. Verify that `_dispatch_callback_fn` does not appear anywhere in `rocker_switches.lua`.
3. Verify that `detect_config()` is called with exactly one argument at the BravoMultiMode.lua call site (line ~173).
4. Run `grep -r "dispatch_callback_fn" FlyWithLua/Modules/bravo++/` — should return no results.

# Risks / Notes

1. **config_loader.detect_config signature change**: Changing from `(aircraft_name, aircraft_dir)` to `(aircraft_name)` is a breaking API change for any external callers or test code that passes the second argument. Since this module is only called internally by BravoMultiMode.lua (one call site), risk is minimal — but all test files must be updated simultaneously.

2. **_dispatch_callback_fn removal**: The luacheck warning (#17) was already flagged in REVIEW-020 as a low-severity issue. No functional behavior depends on this variable being present, so removal carries zero regression risk.

3. **Test compatibility**: The rocker_switches_spec.lua tests currently pass `dispatch_callback_fn` to init() even though it is never used by the module. Removing it from test calls will simplify the test code and make the intent clearer — no behavioral change in the assertions themselves.

4. **Sequencing**: Both fixes are independent of each other and can be implemented in any order. However, both should be committed together to avoid intermediate states where one fix is applied but not the other.

# Supporting Materials

## REVIEW-020 References

| Finding | Severity | File | Line(s) | luacheck Code |
|---------|----------|------|---------|---------------|
| Dead code: `_dispatch_callback_fn` never accessed | Low (MINOR ISSUE) | `rocker_switches.lua` | 17, 30–32 | W17 (unused_variable) |
| Redundant parameter in `detect_config()` | Info | `config_loader.lua` | 46–47 | N/A — design observation |

## luacheck Output (pre-fix)

```
Total: 1 warning / 0 errors in 24 files
Warning: rocker_switches.lua:17:7 — variable _dispatch_callback_fn is never accessed
```

## Call Site Reference

**BravoMultiMode.lua line ~173:**
```lua
local config_result = config_loader.detect_config(aircraft_name, aircraft_dir)
```

This is the only production call site for `detect_config()`. The `aircraft_dir` variable is defined earlier in the same function scope and always contains a valid path.

## Test Coverage Summary

| Module | Tests | Lines Covered |
|--------|-------|---------------|
| rocker_switches_spec.lua | 8 tests | init(), register_all(), get_command_name() |
| config_loader_spec.lua | ~12 tests | detect_config(), read_file(), read_preferences(), build_validation_context() |

## Git Context

- **Parent commit**: FEAT-018 implementation (module extractions from BravoMultiMode.lua)
- **Review document**: REVIEW-020-feat-018-high-priority-module-extractions.md
