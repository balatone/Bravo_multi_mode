---
id: REQ-007
title: Improve Lua Test Coverage to 80%+ and Restructure Tests into Unit, Integration, and E2E Folders
version: 1.0.0
status: APPROVED
created: 2026-07-16 17:45:54
updated: 2026-07-16 18:38:07
related_docs: []
---
# Summary

Increase FlyWithLua Bravo++ Lua module test coverage from 38.37% to ≥80% line coverage and reorganize the flat `tests/` directory into a structured hierarchy of `unit/`, `integration/`, and `e2e/` folders, each independently runnable via Busted with luacov coverage tracking.

# Business Context / Rationale

The Bravo++ project is a FlyWithLua plugin that provides hardware input mapping for Honeycomb Bravo control surfaces in X-Plane flight simulation. The codebase consists of 17 Lua source files totaling ~5,400 lines across the `FlyWithLua/Modules/bravo++/` directory and `Scripts/` folder.

**Current state is critically under-tested:**
- Overall coverage stands at **38.37%**, far below the project's quality threshold of 80%.
- Only **4 out of 11 bravo++ modules** have any test coverage: `decoder.lua` (95.65%), `state.lua` (71.43%), `log.lua` (72.73%), and `debug.lua` (29.73%).
- **Seven modules have zero coverage**: `config.lua` (527 lines), `dispatch.lua` (762 lines), `hardware.lua` (258 lines), `mapbuilder.lua` (260 lines), `plugincheck.lua` (183 lines), `ui.lua` (517 lines), and `util.lua` (167 lines) — totaling **2,068 uncovered lines**.
- The largest single module (`dispatch.lua`, 762 lines) has no tests at all. It is the "brain" of the system that maps hardware inputs to software actions including button presses, twist knobs, trim wheels, and mode cycling.

**The flat test structure prevents selective execution:** All 4 test files sit in a single `tests/` directory with no categorization by scope (unit vs integration vs end-to-end). This makes it impossible to:
- Run only fast unit tests during development
- Isolate slow E2E tests for CI pipelines
- Understand which modules are tested at what level

**Risk:** Without adequate test coverage, refactoring the dispatch module or adding new features carries a high risk of regressions. The dispatch module alone handles button action maps, twist knob mappings, mode cycling logic, trim boost calculations, and rocker switch execution — all critical flight-simulation input handling paths with zero automated verification.

# Scope

## In Scope

1. **Test reorganization**: Restructure `tests/` into three subdirectories:
   - `tests/unit/` — isolated unit tests for individual modules (no cross-module dependencies)
   - `tests/integration/` — cross-module interaction tests (e.g., decoder → state, dispatch + config)
   - `tests/e2e/` — full workflow / functional end-to-end tests simulating complete HID report cycles

2. **Coverage expansion**: Write missing unit and integration tests for all 7 uncovered modules:
   - `config.lua` — config file parsing, key validation, value validation, condition compilation/evaluation
   - `dispatch.lua` — button action maps, twist knob mappings, mode cycling, trim execution, rocker switches
   - `hardware.lua` — device lifecycle, injection queue, polling loop, subscriber dispatch
   - `mapbuilder.lua` — hierarchical map building for selection/button/knob labels and LED configs
   - `plugincheck.lua` — bridge detection logic (folder presence, process running)
   - `ui.lua` — text wrapping, layout cache, ImGui rendering helpers
   - `util.lua` — helper functions: trim, find, type checks, create_table, ends_with, safe lookups

3. **Test infrastructure**: Ensure each test category is independently runnable via Busted with luacov coverage accumulation across all categories.

4. **Existing tests migration**: Move existing `decoder_spec.lua` and related tests into the new structure (primarily unit + some e2e).

## Out of Scope

- Testing FlyWithLua host runtime itself or X-Plane plugin SDK functions
- Hardware integration testing with physical Honeycomb Bravo devices
- GUI/UI visual regression testing for ImGui rendering output
- Performance benchmarking of polling loops or dispatch latency
- Tests for aircraft-specific custom files (`custom/B58.lua`, `custom/C90B.lua`, etc.) — these are configuration data, not logic

# Functional Requirements

## FR-001: Test Folder Structure
The `tests/` directory shall be reorganized into three subdirectories (`unit/`, `integration/`, `e2e/`) with the following naming convention for spec files: `<module_name>_spec.lua`. Each category must be independently runnable via Busted.

## FR-002: Unit Tests — config.lua
Write unit tests covering all public functions of `config.lua`:
- `read_file()` — parsing key=value pairs, comment/blank line skipping, quote stripping
- `validate_keys()` — missing required keys detection, invalid key detection for each category (MODES, SELECTOR_LABELS, BUTTON_LABELS, KNOB_LABELS, SWITCH_*_BUTTON/LED, twist knob actions, LED bindings with 2-param and 3-param rules, trim/threshold configs)
- `validate_values()` — type validation for SELECTOR_LABELS (5 values), BUTTON_LABELS (8 values), KNOB_LABELS (1-2 values), SWITCH_LABELS (7 values), MODES first-value check, _LED parameter count and DataRef/index validation, numeric threshold validation (>0)
- `compile_condition()` — operator parsing for all 6 operators (!=, <=, >=, <, >, =), bare number equality, invalid condition fallback

## FR-003: Unit Tests — dispatch.lua
Write unit tests covering all public functions of `dispatch.lua`:
- `init()` — action map building from nav_bindings and context tables
- Mode cycling (`cycle_mode_up`, `cycle_mode_down`) — correct index wrapping for N modes
- CF mode toggle (`cycle_cf_mode`) — alternating outer/inner
- Switch mode toggle (`cycle_switch_mode`) — alternating up/down
- Mode select activation/deactivation
- Selector index setting with label updates and callback triggers
- Button command resolution across all 3 lookup paths (mode-level, switch-mode UP/DOWN, selection-aware)
- Button press lifecycle: `button_begin`, `button_continue` (continuous mode + long-click detection), `button_end` (single click vs. long click dispatch)
- Twist knob execution (`knob_increase`, `knob_decrease`) — priority resolution (direct > OUTER > INNER based on cf_mode)
- Rocker switch dispatch (`rocker_switch`) — binding lookup and command invocation
- Trim wheel execution (`trim_nose_up`, `trim_nose_down`) — boost window logic, clamping to [-1, 1]
- Map accessors (`get_button_is_switch_map`, `get_twist_knob_map_actions`, etc.)

## FR-004: Unit Tests — hardware.lua
Write unit tests covering all public functions of `hardware.lua`:
- `init()` — device handle setup, simulate mode toggle, error on no device/simulate
- Lifecycle (`start`, `stop`) — running state management
- Subscriber registry (`subscribe`, `unsubscribe`) — callback registration and removal
- Report injection (`inject_report` / `simulate_report`) — FIFO queue behavior, caller buffer isolation
- Polling loop (`poll`) — report draining from injection queue vs. physical device, time budget enforcement, max reports cap, error protection via pcall
- Diagnostics (`diagnostics()`) — counters for total_reports, poll_calls, last_drained, max_drained_per_frame

## FR-005: Unit Tests — mapbuilder.lua
Write unit tests covering `MapBuilder.build()`:
- Selection labels population from nav_bindings with fallback to defaults
- Button labels per selection with AUTO mode special handling (bindings only when explicit)
- Twist knob label parsing for 1-value and 2-value cases
- LED map initialization for both ALT (mode-level) and per-selection LEDs
- Condition compilation via `config.compile_condition()` within the build process

## FR-006: Unit Tests — plugincheck.lua
Write unit tests covering bridge detection logic:
- `is_bridge_folder_present()` — subfolder detection for win_x64/mac_x64 in AFC_Bridge directory
- `is_bridge_process_running()` — Windows tasklist parsing (mockable via io.popen stub)
- `should_warn()` — combined folder + process check

## FR-007: Unit Tests — ui.lua
Write unit tests covering UI helper functions:
- Text wrapping (`wrap_text_for_width`) — word splitting, line fitting within max_width
- LRU cache eviction (`evict_cache()`) — removing oldest entries when exceeding max_size (100)
- Symbol metrics pre-computation and caching

## FR-008: Unit Tests — util.lua
Write unit tests covering all helper functions:
- `trim()` — whitespace stripping from both ends
- `find()` — index lookup in 1-based tables, nil for not found
- Type checks (`is_boolean`, `is_string`, `is_table`) — correct type detection
- `create_table()` — comma-separated string parsing into arrays, empty table for nil input
- `ends_with()` — suffix matching with length guard
- `safe_dataref_lookup()` / `safe_command_lookup()` — defensive argument checking (non-string rejection)

## FR-009: Integration Tests
Write integration tests covering cross-module interactions:
- Decoder → State: verify that decoder events correctly update state via `state.set_selector()`, `state.set_trim()`, and subscriber notification
- Config + Dispatch: verify dispatch.init() correctly builds action maps from parsed config bindings, including mode-level vs. selection-aware button resolution paths
- Hardware + Decoder: inject reports through hardware.inject_report(), poll the queue, verify decoder receives and processes them with correct event detection

## FR-010: E2E Tests
Write end-to-end tests simulating complete operational workflows:
- Full HID report cycle: baseline → rotary CW → selector change → trim pulse → CCW rotary (mirroring existing e2e test in `decoder_spec.lua`)
- Rapid mixed events with debouncing across all three features simultaneously
- Mode cycling workflow: switch modes, toggle CF mode, activate/deactivate mode select, verify twist knob priority resolution changes accordingly

## FR-011: Test Infrastructure
Ensure the following infrastructure is in place:
- `_bootstrap.lua` remains at `tests/_bootstrap.lua` and sets up package.path for all subdirectories
- Busted can be run independently per category:
  - `busted --helper=tests/_bootstrap.lua tests/unit/` — unit tests only
  - `busted --helper=tests/_bootstrap.lua tests/integration/` — integration tests only
  - `busted --helper=tests/_bootstrap.lua tests/e2e/` — E2E tests only
  - `busted --helper=tests/_bootstrap.lua tests/` — all tests (recursive)
- luacov coverage accumulates across all categories when run together

# Success Criteria / Acceptance Criteria

1. **Coverage ≥80%**: luacov reports ≥80% line coverage across all `FlyWithLua/Modules/bravo++/*.lua` files when running the full test suite (`busted --helper=tests/_bootstrap.lua tests/`). Per-module minimums:
   - `decoder.lua`: maintain ≥95% (already at 95.65%)
   - `state.lua`: maintain ≥70% (currently 71.43%)
   - `log.lua`: maintain ≥70% (currently 72.73%)
   - `debug.lua`: improve from ~30% to ≥60%
   - All previously uncovered modules (`config`, `dispatch`, `hardware`, `mapbuilder`, `plugincheck`, `ui`, `util`): achieve ≥80% each

2. **Folder structure exists**: `tests/unit/`, `tests/integration/`, and `tests/e2e/` directories are present with spec files following `<module_name>_spec.lua` naming convention. No `.lua` test files remain at the top level of `tests/` (except `_bootstrap.lua` and `init.lua`).

3. **Independent execution**: Each category runs successfully in isolation:
   - `busted --helper=tests/_bootstrap.lua tests/unit/` passes with zero failures
   - `busted --helper=tests/_bootstrap.lua tests/integration/` passes with zero failures
   - `busted --helper=tests/_bootstrap.lua tests/e2e/` passes with zero failures

4. **No regressions**: All existing decoder tests (699 lines in original `decoder_spec.lua`) pass after migration, including all rotary event detection, selector change handling, trim edge detection, debouncing, deduplication, state integration, diagnostics, and end-to-end HID cycle scenarios.

# Constraints / Guardrails / Dependencies

## Technical Constraints

1. **FlyWithLua host dependencies**: Several modules depend on X-Plane/FlyWithLua globals (`XPLMFindDataRef`, `dataref_table`, `imgui`, `hid_read`, `float_wnd_create`, etc.) that are unavailable in the test environment. All such calls must be mocked or stubbed. The existing `_bootstrap.lua` already provides a pattern for this via global mocking and luacov integration.

2. **io.popen usage**: `hardware.lua`, `plugincheck.lua`, and `util.lua` use `io.popen()` for file listing and process detection. These must be mocked in tests (e.g., by replacing `io.popen` with a stub that returns controlled output).

3. **os.clock() dependency**: Debounce logic in `decoder.lua` and dispatch timing depend on `os.clock()`. The existing `_bootstrap.lua` already provides `_G.advance_time()` and `_G.set_time()` as time mocks — these must be extended for use across all test categories.

4. **Package path resolution**: Modules use `require("bravo++.xxx")` which maps to `FlyWithLua/Modules/bravo++/xxx.lua`. The bootstrap's package.path setup must accommodate the new subdirectory structure without breaking existing require paths.

## Dependencies

1. **Busted test framework** (installed system-wide at `/usr/share/lua/5.4/busted/`) — no additional dependencies needed
2. **luacov** for coverage instrumentation — already configured and working with `_bootstrap.lua`
3. **tests/bit.lua shim** — provides bitwise operations (`band`, `bor`, `lshift`, etc.) in place of LuaBitOp; must remain accessible from all test subdirectories via package.path

## Guardrails

- Do not modify any source files under `FlyWithLua/Modules/bravo++/*.lua` or `FlyWithLua/Scripts/`. This task is strictly about adding tests and reorganizing the test directory.
- Preserve backward compatibility: existing test invocations (`busted --helper=tests/_bootstrap.lua`) must continue to work after restructuring (via recursive glob).
- Maintain luacov accumulation: use the same `decoder.reset()` + `state.reset()` pattern between tests rather than module reloading, so coverage counts accumulate correctly.

# Timing / Deadline / Trigger

- **Trigger**: This requirement is triggered by the current 38.37% coverage being well below the 80% quality threshold, and the identification of dispatch.lua (the largest module at 762 lines) as completely untested despite its critical role in input handling.
- **Sequencing**: Phase 1 — restructure test folders and migrate existing decoder tests; Phase 2 — write unit tests for uncovered modules in order of dependency: `util` → `log`/`state` (already partially covered) → `config` → `mapbuilder` → `hardware` → `dispatch` → `ui`/`plugincheck`; Phase 3 — integration and E2E tests; Phase 4 — final coverage verification.
- **Needed by**: To be determined in coordination with the Lead archetype during sprint planning.

# Notes / Assumptions

## Key Findings from Codebase Analysis

### Module Coverage Summary (from luacov.stats.out)

| Module | Lines | Covered | Uncovered | Coverage |
|--------|-------|---------|-----------|----------|
| `decoder.lua` | 264 | ~253 | 11 | **95.65%** |
| `state.lua` | 67 | 48 | 19 | **71.43%** |
| `log.lua` | 40 | 29 | 11 | **72.73%** |
| `debug.lua` | 62 | 18 | 44 | **29.73%** |
| `config.lua` | 527 | 0 | 527 | **0% (UNCOVERED)** |
| `dispatch.lua` | 762 | 0 | 762 | **0% (UNCOVERED)** |
| `hardware.lua` | 258 | 0 | 258 | **0% (UNCOVERED)** |
| `mapbuilder.lua` | 260 | 0 | 260 | **0% (UNCOVERED)** |
| `plugincheck.lua` | 183 | 0 | 183 | **0% (UNCOVERED)** |
| `ui.lua` | 517 | 0 | 517 | **0% (UNCOVERED)** |
| `util.lua` | 167 | 0 | 167 | **0% (UNCOVERED)** |

### Existing Test Analysis (`decoder_spec.lua`, 699 lines)

The existing test suite is comprehensive for the decoder module and serves as a strong reference pattern:
- Uses `make_report(byte15, byte16)` helper to construct HID reports
- Uses `_G.advance_time()` / `_G.set_time()` for time mocking via bootstrap
- Uses `decoder.reset()` + `state.reset()` between tests (preserves luacov accumulation)
- Covers: rotary CW/CCW detection, debounce suppression, dedupe window handling, selector one-hot mapping (all 5 positions), trim up/down edge detection, state integration, diagnostics counters, handler error resilience, and full E2E HID cycles

### Mocking Strategy Recommendations

1. **X-Plane SDK functions**: Create a `tests/mocks/xplane.lua` module that provides stub implementations of `XPLMFindDataRef`, `dataref_table`, `XPLMFindCommand`, etc., returning controlled values or nil.
2. **io.popen**: Replace with a test-controlled stub in the bootstrap, e.g.:
   ```lua
   local original_popen = io.popen
   _G.mock_io_results = {}  -- key: command substring -> mock output string
   io.popen = function(cmd)
       for pattern, result in pairs(_G.mock_io_results) do
           if cmd:find(pattern) then
               return { lines = function() return ipairs(split(result, "\n")) end, close = function() end }
           end
       end
       return original_popen(cmd)
   end
   ```
3. **Time mocking extension**: Extend the existing `_G.advance_time()` / `_G.set_time()` utilities from `tests/_bootstrap.lua` to support absolute time setting for debounce and deduplication window testing (e.g., advancing by 25ms, 80ms) without requiring a real clock. This is already partially implemented but should be formalized as the canonical mock API in all new test files.
4. **Package path compatibility**: When tests are moved into `unit/`, `integration/`, and `e2e/` subdirectories, ensure `_bootstrap.lua` correctly prepends the parent directory to `package.path` so that `require("bravo++.xxx")` resolves identically regardless of test file location. The bootstrap should compute its own parent path dynamically rather than hardcoding relative paths.
5. **ImGui mocking**: For UI tests (`ui.lua`, 517 lines), create a minimal `tests/mocks/imgui.lua` that stubs the ImGui C API surface (e.g., `igText`, `Button`, `Checkbox`) with no-op functions or counters, allowing test code to verify layout logic without an actual OpenGL context.

# SMART Check

Use this section as a quick quality check before finalizing the requirement.

- **Specific:** Yes. The requirement targets exactly 7 uncovered modules (`config`, `dispatch`, `hardware`, `mapbuilder`, `plugincheck`, `ui`, `util`) with 11 functional requirements (FR-001 through FR-011) specifying which functions, code paths, and edge cases each test suite must cover. The folder restructure is explicitly defined as three subdirectories (`unit/`, `integration/`, `e2e/`) under `tests/` with a `<module_name>_spec.lua` naming convention.

- **Measurable:** Yes. Success is quantified by four acceptance criteria: (1) luacov reports ≥80% overall line coverage with per-module minimums (decoder ≥95%, state ≥70%, log ≥70%, debug ≥60%, all new modules ≥80%); (2) three subdirectories exist with no `.lua` test files remaining at the top level; (3) each category passes independently via `busted --helper=tests/_bootstrap.lua tests/<category>/`; (4) zero regressions on existing decoder_spec.lua tests after migration. luacov output provides machine-verifiable evidence for criterion 1.

- **Achievable:** Yes. The project already has a working test infrastructure: Busted is installed system-wide, luacov integration exists in `_bootstrap.lua`, and `decoder_spec.lua` (699 lines) demonstrates the full pattern — time mocking via `_G.advance_time()`, state reset between tests (`decoder.reset()` + `state.reset()`), HID report construction helpers, and handler error resilience testing. The seven uncovered modules are pure Lua with no native extensions; their FlyWithLua/X-Plane dependencies can be stubbed using the same global-mocking approach already proven in `_bootstrap.lua`. No new external dependencies are required.

- **Relevant:** Yes. At 38.37% coverage, the project has a critical testing gap: `dispatch.lua` (the largest module at 762 lines) handles all input-to-action mapping — button presses, twist knobs, trim execution, mode cycling — with zero automated verification. Without adequate tests, any refactoring or feature addition to this core module carries unquantified regression risk. Achieving ≥80% coverage provides a safety net for future development and enables confident CI gating on test pass rate.

- **Time-bound:** Yes. The trigger is explicit: current 38.37% coverage being well below the 80% threshold, compounded by identification of `dispatch.lua` as completely untested despite its critical role. Sequencing is defined in four phases (restructure → unit tests for uncovered modules by dependency order → integration/E2E → final verification), providing a clear execution roadmap that can be estimated and tracked during sprint planning.
