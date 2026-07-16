---
id: FEAT-014
title: Integration & E2E Test Suite
version: 1.0.0
status: APPROVED
created: 2026-07-16 19:11:57
updated: 2026-07-16 19:19:21
related_docs: ["PLAN-005", "REQ-007"]
---
# Feature Overview

This feature writes cross-module integration tests and end-to-end workflow simulations that validate the complete hardware→decoder→dispatch pipeline with mode-switching behavior. While FEAT-011 through FEAT-013 focus on individual module testing, this feature validates that all modules work together correctly — verifying subscriber notification chains, injection queue pipelines, action map construction from parsed config bindings, and full operational workflows including rapid mixed events with debouncing across multiple features simultaneously. This is the final phase of REQ-007's phased approach (Phase 3) and directly addresses FR-009 (Integration Tests), FR-010 (E2E Tests), and SPIKE-003's Finding 2 (coupling & dependency map showing hardware→decoder→state pipeline).

# Objectives

1. **Write integration tests** for cross-module interaction chains: decoder→State subscriber notification, Config+Dispatch action map construction verification, Hardware injection queue→decoder event detection pipeline.
2. **Write E2E tests** simulating complete operational workflows: full HID report cycles (baseline → rotary CW → selector change → trim pulse → CCW rotary), rapid mixed events with debouncing across all three features simultaneously, mode cycling workflow (switch modes, toggle CF mode, activate/deactivate mode select, verify twist knob priority resolution changes).
3. **Write mocked UI/Plugincheck tests**: Mocked ImGui rendering tests for `ui.lua` text wrapping and LRU cache eviction; bridge detection logic tests for `plugincheck.lua` with mocked `io.popen`.

# Scope

## In Scope

1. **Integration tests** (`tests/integration/`):
   - **Decoder→State integration**: Verify that decoder events correctly update state via `state.set_selector()` and `state.set_trim()`, and that subscriber notification fires with correct values via the pub/sub pattern. Test that multiple subscribers receive notifications in order and that pcall error isolation prevents one failing subscriber from blocking others.
   - **Config+Dispatch integration**: Verify dispatch.init() correctly builds action maps from parsed config bindings, including mode-level vs. switch-mode UP/DOWN button resolution paths and selection-aware button lookup. Validate that compiled conditions (from FEAT-013's condition compiler) are consumed correctly by the dispatch module.
   - **Hardware+Decoder integration**: Inject reports through `hardware.inject_report()`, poll the queue, verify decoder receives and processes them with correct event detection. Test FIFO queue behavior: multiple injected reports are drained in order during polling; max_reports_per_poll cap is enforced; time budget enforcement prevents blocking X-Plane.

2. **E2E tests** (`tests/e2e/`):
   - **Full HID report cycle**: Simulate the exact sequence from REQ-007's FR-010: baseline → rotary CW event → selector position change → trim pulse → CCW rotary event, mirroring the existing e2e test in `decoder_spec.lua`. Verify state transitions at each step and that debouncing/deduplication suppresses spurious events.
   - **Rapid mixed events with debouncing**: Inject a burst of rapid HID reports containing all three feature types (rotary CW/CCW, selector changes, trim pulses) simultaneously; verify debounce logic correctly suppresses duplicate detections within the configured window and that deduplication prevents redundant state updates.
   - **Mode cycling workflow**: Switch modes via switch input, toggle CF mode between outer/inner, activate/deactivate mode select, then verify twist knob priority resolution changes accordingly (direct > OUTER > INNER based on current cf_mode). Verify selector index updates propagate correctly through label callbacks and that all subscribers receive state change notifications.

3. **UI/Plugincheck tests** (`tests/unit/ui_spec.lua` + `tests/unit/plugincheck_spec.lua`):
   - **ui.lua text wrapping**: Test `wrap_text_for_width()` with various input strings — word splitting, line fitting within max_width, handling of single words longer than max_width (truncate or wrap to next line). Verify LRU cache eviction: add more than 100 entries and verify oldest entries are evicted.
   - **plugincheck bridge detection**: Test `is_bridge_folder_present()` with mocked filesystem output; test `is_bridge_process_running()` with mocked `io.popen` returning controlled process listing output for Windows (`tasklist`) and macOS/Linux (process listing); test `should_warn()` combined logic.

## Out of Scope

- Testing custom aircraft modules (B58.lua, C90B.lua, DA42.lua, Transponder.lua) — explicitly excluded by REQ-007.
- Visual regression testing for ImGui rendering output — not feasible in CLI environment; accept that full UI integration requires FlyWithLua runtime.
- Performance benchmarking of polling loops or dispatch latency.

# Inputs to Review

1. **REQ-007** — FR-009 (Integration Tests): decoder→State, config+dispatch, hardware+decoder interaction specifications; FR-010 (E2E Tests): full HID report cycle, rapid mixed events with debouncing, mode cycling workflow; Success Criteria 3 and 4.
2. **SPIKE-003** — Finding 2: Coupling & Dependency Map showing the hardware→decoder→state pipeline; Finding 5: Mocking Feasibility Assessment for imgui (partial mock covering only used functions), io.popen (controlled output); Evaluation section recommending Option C (Hybrid) with integration tests for remaining modules.
3. **Existing decoder_spec.lua** — The existing e2e test in `decoder_spec.lua` provides the reference pattern for full HID report cycle simulation; study its structure and replicate the approach for broader pipeline testing.
4. **FEAT-012 (Dispatch Refactoring)**: Must be complete before this feature can write integration tests against refactored dispatch sub-modules — verify new module boundaries are stable.

# Implementation Tasks

1. **Review inputs**: Read REQ-007 FR-009/FR-010, SPIKE-003 Finding 2 (dependency map) and Finding 5 (mocking feasibility), existing decoder_spec.lua e2e test pattern, and FEAT-012's dispatch sub-module boundaries.
2. **Write integration tests** (`tests/integration/dispatch_integration_spec.lua`):
   - Test decoder→State: inject a known HID report via `decoder.on_report()`, verify state is updated correctly (selector position, trim value), verify subscriber callbacks fire with correct values
   - Test Config+Dispatch: create mock config data, call dispatch.init(), verify action maps contain expected button commands for each mode/selection path; test condition compiler integration by verifying compiled predicates resolve correctly in button resolution
   - Test Hardware→Decoder: inject reports via `hardware.inject_report()`, poll queue with `hardware.poll()`, verify decoder handlers receive correct events from the injected reports
3. **Write E2E tests** (`tests/e2e/workflow_spec.lua`):
   - Full HID report cycle: construct baseline report, then sequential CW rotary → selector change → trim pulse → CCW rotary; use `_G.advance_time()` to control timing for debounce/deduplication windows; verify state transitions at each step
   - Rapid mixed events: inject 20+ reports in rapid succession (using advance_time with small increments) containing all three feature types; verify debounce suppresses duplicates and deduplication prevents redundant updates
   - Mode cycling workflow: switch modes via input, toggle CF mode, activate/deactivate mode select, then test twist knob priority resolution changes — verify that the correct action is dispatched based on current cf_mode state (direct > OUTER > INNER)
4. **Write UI tests** (`tests/unit/ui_spec.lua`):
   - Create minimal `tests/mocks/imgui.lua` stubbing only methods used by ui.lua/plugincheck.lua: `Dummy`, `CalcTextSize`, `SetWindowFontScale`, `DrawList_AddCircle`, `PushStyleColor`, `PopStyleColor`, `TextColor`, `Button`, `Checkbox`, `TextUnformatted`, `SameLine`, `Spacing`, `Separator`
   - Test `wrap_text_for_width()` — word splitting, line fitting within max_width, single-word overflow handling
   - Test LRU cache eviction: add >100 entries to text_layout_cache, verify oldest entries are evicted when exceeding max_size of 100
5. **Write Plugincheck tests** (`tests/unit/plugincheck_spec.lua`):
   - Mock `io.popen` with controlled output for bridge folder detection (win_x64/mac_x64 subfolder presence) and process listing (Windows tasklist parsing, Unix ps/grep patterns)
   - Test `is_bridge_folder_present()` — return true when expected folders exist in mock output, false otherwise
   - Test `is_bridge_process_running()` — parse mock process list to detect Bridge.exe or bridge process; verify platform-specific command routing
   - Test `should_warn()` — combined logic: warn only when both folder present AND process running (or whichever combination matches the actual implementation)
6. **Run all tests**: Execute full suite (`busted --helper=tests/_bootstrap.lua tests/`) and each category independently to verify zero failures across integration, e2e, and UI/plugincheck unit tests.

# Acceptance Criteria

1. **Integration test coverage**: All three cross-module interaction chains are tested: decoder→State subscriber notification (at least 3 test cases), Config+Dispatch action map construction (at least 4 test cases), Hardware injection queue→decoder event detection (at least 3 test cases).
2. **E2E workflow tests pass**: Full HID report cycle, rapid mixed events with debouncing, and mode cycling workflow all execute successfully with zero failures; state transitions at each step are verified via assertions on `state.get_selector()`, `state.get_trim()`, and subscriber callback values.
3. **UI/Plugincheck tests pass**: ui.lua text wrapping and LRU cache eviction tested with mocked imgui; plugincheck bridge detection logic tested with mocked io.popen — all zero failures.
4. **Independent category execution**: All three categories run successfully in isolation: `busted --helper=tests/_bootstrap.lua tests/integration/` passes, `busted --helper=tests/_bootstrap.lua tests/e2e/` passes, and unit-level UI/plugincheck tests pass via `busted --helper=tests/_bootstrap.lua tests/unit/`.

# Definition of Done

1. All 4 acceptance criteria verified (see Acceptance Criteria section).
2. luacov reports ≥80% line coverage on ui.lua and plugincheck.lua (previously uncovered modules per REQ-007 Success Criteria).
3. No regressions in any existing tests — all decoder_spec.lua cases, FEAT-011 unit tests, FEAT-012 dispatch integration tests, and FEAT-013 condition compiler tests pass alongside new integration/E2E/UI/plugincheck tests.
4. luacov accumulation verified: coverage counts accumulate correctly across all test categories when running `busted --helper=tests/_bootstrap.lua tests/` (recursive).

# Dependencies / Risks

## Dependencies

| # | Dependency | Type | Notes |
|---|-----------|------|-------|
| D1 | FEAT-010 (Test Infrastructure Reorganization) | Upstream | All bootstrap mocks, directory structure, and package.path resolution must be complete. |
| D2 | FEAT-012 (Dispatch Refactoring & Testing) | Upstream | Dispatch sub-module boundaries must be finalized before integration tests can reference the new module structure. |
| D3 | FEAT-013 (Config Validation Extraction) | Parallel but recommended | Condition compiler extraction should be complete so integration tests can verify dispatch.init() consumes compiled conditions correctly. |

## Risks

| # | Risk | Severity | Mitigation |
|---|------|----------|------------|
| R1 | **ImGui mocking complexity** — ui.lua calls numerous ImGui methods (`Dummy`, `CalcTextSize`, `SetWindowFontScale`, `DrawList_AddCircle`) that are unavailable in CLI without a partial mock covering only used functions. Creating an incomplete mock could cause silent failures where tests pass but real rendering would fail. | MEDIUM | Create a minimal stub module listing ONLY the specific imgui methods actually called by ui.lua and plugincheck.lua (identified via source code review). Add comments noting that full UI integration testing requires FlyWithLua runtime; accept this as a known limitation. Focus tests on pure computation paths (text wrapping, LRU cache eviction) rather than rendering assertions. |
| R2 | **io.popen mock interfering with legitimate operations** — Mocking `io.popen` globally for plugincheck.lua testing could break other tests that legitimately need filesystem access (e.g., if any test needs to read config files). | LOW-MEDIUM | Use a controllable stub keyed by command substring pattern rather than a blanket replacement; allow fallback to original `io.popen` for unmatched commands. This is already recommended in FEAT-010's Implementation Notes as the canonical mock pattern. |
| R3 | **E2E test fragility due to timing dependencies** — Debounce and deduplication windows depend on precise timing (`os.clock()` values). Tests that advance time by incorrect amounts could produce flaky results (sometimes passing, sometimes failing based on execution speed). | MEDIUM | Use `_G.set_time()` for absolute time setting rather than relative increments where precision matters; document the exact clock values used in each test case; run E2E tests multiple times to verify consistency. The existing decoder_spec.lua already demonstrates this pattern successfully with 67 passing cases. |
