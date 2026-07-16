---
id: SPIKE-003
title: Assess Lua Codebase Testability and Maintainability for REQ-007
version: 1.0.0
status: APPROVED
created: 2026-07-16 18:42:17
updated: 2026-07-16 19:02:06
related_docs: ["REQ-007"]
---
# Executive Summary

The Bravo++ Lua codebase (15 source files, ~3,900 lines total across core modules and aircraft-specific custom scripts) is **partially ready** for systematic test coverage improvement. The modular architecture introduced in the recent refactoring — with `hardware.lua`, `decoder.lua`, `state.lua`, `dispatch.lua`, `mapbuilder.lua`, `ui.lua`, `config.lua`, `util.lua`, `log.lua`, and `debug.lua` forming a clean separation of concerns — provides a solid foundation for unit testing. The existing test infrastructure (busted + luacov with `_bootstrap.lua`) already demonstrates that modules can be isolated from the FlyWithLua host environment through global mocking (`_G.logMsg`, time mocker, `bit` shim).

However, significant challenges remain: **dispatch.lua** is a 762-line god object with tightly coupled state and direct calls to X-Plane command functions; **config.lua** (527 lines) contains complex operator/condition logic that intertwines validation with side-effect-producing DataRef lookups; several custom aircraft modules duplicate trim/cowl-flap dataref manipulation code across B58, C90B, and DA42 files; and the main entry point (`BravoMultiMode.lua`, ~1,300 lines) wires everything together in a single monolithic script with no dependency injection.

**Confidence rating: Medium.** The best-tested module (decoder, 67 tests already written) proves that good testability is achievable when modules are well-structured and dependencies can be mocked. The hardest-to-test modules (dispatch, config, ui) will require targeted refactoring before meaningful coverage gains can be made without fragile integration tests.

---

# Question / Hypothesis

**Primary question:** Is the Bravo++ Lua codebase structured in a way that supports achieving ≥80% testable line coverage through unit and integration testing alone, or does it require architectural refactoring first?

**Hypotheses tested during this spike:**
1. The modular boundary between `hardware.lua` → `decoder.lua` → `state.lua` provides clean isolation for unit testing (confirmed).
2. `dispatch.lua` is a god object that couples too many concerns, making it difficult to test in isolation (confirmed).
3. Global state and FlyWithLua host dependencies create significant mocking overhead (partially confirmed — some modules mock well, others do not).
4. The existing `_bootstrap.lua` infrastructure provides sufficient mocking primitives for most modules (confirmed for decoder; gaps exist for dispatch and config).

---

# Scope / Objectives

## In Scope
- Deep structural analysis of all 15 Lua source files under `FlyWithLua/Modules/bravo++/`.
- Assessment of module boundaries, coupling patterns, global state usage, function sizes, and error handling.
- Evaluation of separation of concerns across the codebase.
- Testability assessment: pure logic vs. side effects ratio, external dependencies, mocking feasibility.
- Maintainability assessment: naming consistency, duplication, configuration complexity, documentation quality.
- Dependency graph analysis including circular dependency detection.
- Recommendations for REQ-007 test coverage improvement strategy.

## Out of Scope
- Writing new application code or modifying existing source files.
- Performance benchmarking (though profiler code was noted).
- Security audit of the FlyWithLua sandbox escape surface.
- Analysis of Python tests in `python_tests/` directory.

---

# Methodology / Evidence

**Evidence sources reviewed:**
1. All 15 Lua source files under `FlyWithLua/Modules/bravo++/` (read in full).
2. Main entry point: `FlyWithLua/Scripts/BravoMultiMode.lua` (~1,300 lines, read key sections showing module wiring).
3. Existing test infrastructure: `tests/_bootstrap.lua`, `tests/init.lua`, `tests/bit.lua`.
4. Existing tests: `tests/decoder_spec.lua` (67 test cases across 8 describe blocks).
5. Configuration files in `FlyWithLua/Modules/bravo++/conf/` directory structure.

**Assumptions:**
- FlyWithLua host globals (`hid_read`, `hid_set_nonblocking`, `dataref_table`, `command_once`, `imgui`, etc.) are available at runtime but unavailable during CLI testing — hence the need for mocking.
- The `_G.logMsg` mock in `_bootstrap.lua` is sufficient to silence log output during tests, but other FlyWithLua globals (e.g., `create_command`, `float_wnd_create`) may require additional mocks.
- Lua 5.1 semantics apply (global `unpack`, no native bitwise operators).

---

# Findings

## Finding 1: Module-by-Module Analysis

### util.lua — Helper Functions (167 lines)

**Primary responsibility:** Utility functions for string manipulation, type checking, DataRef lookup safety, and file listing.

**Dependencies on other modules:** `bravo++.log` (for error logging in `create_table`).

**Testability score: 5/5** — Excellent testability.
- Most functions are pure logic with no side effects (`trim`, `find`, `is_dataref_magic_table`, `is_boolean`, `is_string`, `is_table`, `ends_with`, `get_name_before_index`).
- Functions that interact with the host environment (`safe_dataref_lookup`, `safe_command_lookup`) use defensive patterns and can be tested by mocking `_G.XPLMFindDataRef` / `_G.XPLMFindCommand`.
- `create_table` has a side effect (logging) but is otherwise pure.
- `list_files` uses `io.popen` which is mockable in the test environment.

**Maintainability observations:** Clean, well-documented with inline comments. Consistent naming convention (`util.function_name`). No significant duplication within this file. The `safe_dataref_lookup` and `safe_command_lookup` functions are good examples of defensive programming.

---

### log.lua — Logging Module (40 lines)

**Primary responsibility:** Structured logging with configurable severity levels, formatting timestamps with `os.clock()`.

**Dependencies on other modules:** None internally; depends on FlyWithLua global `logMsg`.

**Testability score: 5/5** — Trivially testable.
- Pure function composition: input message → formatted output string.
- The only external dependency is `_G.logMsg`, which can be mocked to capture logged messages for assertion.
- Log level filtering logic (`LOG_LEVEL >= LOG_DEBUG`) is straightforward conditional branching.

**Maintainability observations:** Minimal, focused module. Clean constant definitions at the top. No issues identified.

---

### state.lua — State Management (67 lines)

**Primary responsibility:** Centralized mutable state for selector, rotary, and trim values with pub/sub subscriber pattern.

**Dependencies on other modules:** None. Self-contained.

**Testability score: 5/5** — Excellent testability.
- All state is encapsulated in a local module table (`M`). No global mutations.
- `reset()` function provides clean state for test isolation (already used by decoder tests).
- Pub/sub pattern with `subscribe_state` and `pcall(fn, v)` per subscriber makes it easy to inject mock subscribers.
- `snapshot()` returns an immutable copy of current state.

**Maintainability observations:** Well-designed module. Clean separation between getter/setter pairs and the pub/sub mechanism. The `reset()` function is a good testing practice that should be preserved. No issues identified.

---

### debug.lua — Debug Logging for HID Reports (62 lines)

**Primary responsibility:** Conditional logging of raw HID reports and diffs for debugging purposes.

**Dependencies on other modules:** `bravo++.log`.

**Testability score: 4/5** — Highly testable with minor caveat.
- All logic is pure computation (`hex`, diff detection, formatting).
- The only side effect is calling `log.debug()`, which can be captured via mock.
- Module-level `enabled` flag and `last_report` state are accessible through public API (`enable()`, `_last_report()`).

**Maintainability observations:** Clean, focused module. Good use of local helper functions. The commented-out line (`if #diffs>0 then log.debug(...)`) suggests a TODO that was never completed — minor code smell but not impactful.

---

### config.lua — Configuration Parsing and Validation (527 lines)

**Primary responsibility:** Reading key=value configuration files, validating keys against expected schemas, parsing operator/condition strings into callable predicates, and evaluating conditions at runtime.

**Dependencies on other modules:** `bravo++.util` (for trimming, table creation, string operations).

**Testability score: 2/5** — Poor testability without refactoring.
- **Problem 1: Side effects during validation.** The `validate_values()` function calls `util.safe_dataref_lookup()` and `util.safe_command_lookup()` which invoke FlyWithLua host functions (`XPLMFindDataRef`, `XPLMFindCommand`). These cannot be tested in the CLI environment without extensive mocking.
- **Problem 2: Complex condition compilation.** The `compile_condition` function (with its operator ordering, multi-char vs single-char matching) is pure logic and testable, but it's not exposed as a standalone module-level export until after validation runs.
- **Problem 3: Large function bodies.** `validate_values()` processes many different key patterns with deeply nested conditionals — this makes it hard to write focused tests for individual validation rules without triggering cascading side effects.
- **Positive:** The operator registry (`OPERATOR_MAP`) and `compile_condition`/`eval_condition` are well-designed pure logic that could be extracted into a separate testable module.

**Maintainability observations:** This is the most complex file in the codebase by far. The validation logic mixes key existence checks, value type checking, DataRef resolution, condition parsing, and array index validation — all in one function. The `two_param_led_keys` whitelist pattern is a good approach but adds another layer of indirection. Significant duplication between similar validation branches (e.g., the repeated `_LED` key handling).

---

### decoder.lua — HID Report Decoding (264 lines)

**Primary responsibility:** Decode raw 16-byte HID reports from the Honeycomb Bravo into semantic events: rotary CW/CCW, selector position changes, and trim up/down. Implements debounce and deduplication logic.

**Dependencies on other modules:** `bravo++.log`, `bravo++.debug`, `bravo++.state`, external `bit` library (shimmed in tests).

**Testability score: 5/5** — Excellent testability. This is the gold standard for the codebase.
- All detection logic (`detect_rotary_event_from_bytes`, `detect_selector_change_from_bytes`, `detect_trim_event_from_bytes`) is pure function composition on input bytes → event type.
- Handler-based architecture via `set_handlers(tbl)` allows injection of mock callbacks — no global state pollution.
- Debounce timing uses a mocked `os.clock()` (already implemented in `_bootstrap.lua`).
- State integration with `state.set_selector()`, `state.set_trim()` is tested through the pub/sub pattern.
- 67 existing tests demonstrate comprehensive coverage patterns: individual event detection, debounce suppression, deduplication, direction changes, mixed events, edge cases, diagnostics, and end-to-end report cycles.

**Maintainability observations:** Well-structured with clear separation between byte-level detection functions and the high-level `on_report` dispatcher. Per-feature isolation (`last_seen_rotary_byte`, `last_seen_selector_byte`) prevents cross-contamination of detection logic. The `copy_report` function for report isolation is a good defensive pattern. Minor concern: some magic constants (0x10, 0x20, SELECTOR_MASK = 0x1F) are not named — could benefit from comments or named constants.

---

### hardware.lua — HID Device Lifecycle (258 lines)

**Primary responsibility:** Manage the physical HID device lifecycle (open/close), implement a budgeted polling loop that never blocks X-Plane, provide an injection queue for testing/simulation, and dispatch reports to subscribers.

**Dependencies on other modules:** `bravo++.log`. Depends on FlyWithLua globals (`hid_read`, `hid_set_nonblocking`).

**Testability score: 4/5** — Good testability with the injection pattern.
- The injection queue (`inject_report()`) provides a clean testing path that bypasses physical HID entirely.
- Subscriber registry (`subscribe`/`unsubscribe`) allows mock callbacks for verification.
- `poll()` wraps `_poll_task` in `pcall`, making error handling testable.
- Diagnostics counters provide observable state for assertions.
- The time budget check (`max_poll_time_secs`) uses `os.clock()`, which is already mocked.

**Maintainability observations:** Well-documented with clear responsibility boundaries stated at the top of the file. Good use of pre-allocated buffers to minimize GC pressure in the polling loop. The injection queue design is excellent for testing — it allows simulating HID reports without hardware. Minor concern: `read_buffer` reuse pattern requires callers not to retain references, which could be a source of bugs if violated.

---

### mapbuilder.lua — Unified Mapping Initialization (260 lines)

**Primary responsibility:** Perform a single hierarchical traversal over modes → selections → buttons to populate all registry tables (selection labels, button labels, twist knob labels, LED maps). Replaces deeply nested loops from the original monolithic script.

**Dependencies on other modules:** `bravo++.util`, `bravo++.config` (for `compile_condition`).

**Testability score: 3/5** — Moderately testable with some challenges.
- The main traversal logic is pure computation given a fixed set of inputs, making it theoretically testable.
- **Problem:** It calls `dataref_table_fn(binding[1])` (a FlyWithLua global) during LED map construction, which requires mocking in tests.
- **Problem:** It dynamically loads the config module via `require("bravo++.config")`, creating a tight coupling that makes it hard to test without loading the full validation pipeline.
- The helper functions (`init_selection_map_labels`, etc.) are pure and could be tested independently if extracted.

**Maintainability observations:** Significant improvement over the original monolithic approach. The single-pass traversal is elegant and avoids redundant loops. However, the `goto next_button` statement for ALT selection LED precedence is a code smell — it creates non-obvious control flow that's hard to follow. Consider refactoring to an explicit early-return pattern or state machine.

---

### plugincheck.lua — Conflict Detection (183 lines)

**Primary responsibility:** Detect the Honeycomb Bridge plugin conflict via filesystem inspection and process listing, display a warning dialog using ImGui.

**Dependencies on other modules:** `bravo++.log`. Depends on FlyWithLua globals (`RESOURCE_PATH`, `imgui`, `float_wnd_create`).

**Testability score: 2/5** — Poor testability due to host dependencies.
- **Problem:** The detection logic uses `io.popen` with platform-specific commands (`dir /b`, `ls`) and checks for specific file patterns. While `io.popen` is mockable, the filesystem-based approach makes tests fragile (depends on actual directory contents).
- **Problem:** The ImGui warning dialog code (`build_warning_gui`, `show_warning_if_needed`) requires `imgui` global and FlyWithLua window management functions — these cannot be tested in CLI without extensive mocking.
- The pure detection logic (`is_bridge_folder_present` return value) could be extracted into a testable function if separated from the UI rendering code.

**Maintainability observations:** This module violates separation of concerns by mixing conflict detection (pure business logic) with ImGui rendering (UI side effects). The `bravo_plugincheck_warning_gui` global wrapper function is required by FlyWithLua's string-callback mechanism but adds unnecessary indirection. Consider splitting into a pure detection module and a UI adapter module.

---

### ui.lua — ImGui Rendering Logic (517 lines)

**Primary responsibility:** All visual rendering for the Bravo++ floating window GUI using ImGui: mode labels, selection labels, buttons with wrapped text, twist knob graphics, switch indicators, LED state coloring.

**Dependencies on other modules:** `bravo++.util`. Depends heavily on FlyWithLua global `imgui`.

**Testability score: 2/5** — Poor testability due to rendering dependencies.
- **Problem:** Every drawing function calls `imgui` methods (`Dummy`, `CalcTextSize`, `SetWindowFontScale`, `DrawList_AddCircle`, etc.) which are FlyWithLua host functions unavailable in CLI testing.
- **Partial positive:** The text wrapping logic (`wrap_text_for_width`) and font scaling binary search (`get_scaled_wrapped_text`) are pure computation that could be extracted for unit testing if separated from the ImGui calls.
- The `strip_padding` function is trivially testable (simple string substitution).

**Maintainability observations:** Well-organized with clear visual hierarchy in the code structure. The text layout cache with LRU eviction is a good performance optimization. However, the module has no public API boundary — everything is accessed through the single `build_gui(ctx)` function which requires a large context table. Consider extracting pure computation functions (text wrapping, font scaling) into their own testable module.

---

### dispatch.lua — Command and Action Mapping (762 lines) ⚠️ GOD OBJECT

**Primary responsibility:** The central "brain" of the system that maps hardware inputs to software actions: button press/release/long-press handling, twist knob increase/decrease, rocker switch commands, trim wheel with boost logic, mode cycling, selector management.

**Dependencies on other modules:** `bravo++.util`, `bravo++.log`. Depends on FlyWithLua globals (`_G.command_once`, `_G.command_begin`, `_G.command_end`).

**Testability score: 1/5** — Very poor testability without significant refactoring.
- **Problem 1: God object.** This single module handles button actions, twist knob execution, rocker switch commands, trim wheel logic, mode cycling, selector management, arrow color state, and command resolution — at least 8 distinct responsibilities crammed into one file.
- **Problem 2: Direct host function calls.** Every action method (`button_begin`, `button_continue`, `button_end`, `knob_increase`, `knob_decrease`, `rocker_switch`) directly calls `_G.command_once` / `_G.command_begin` / `_G.command_end`. These cannot be mocked without modifying the module.
- **Problem 3: Mutable global-like state.** Multiple local variables (`current_mode`, `current_selection`, `current_cf_mode`, `arrow_color`, `command_state[]`) are mutated throughout and accessed by many methods, making it hard to test individual behaviors in isolation.
- **Problem 4: Complex resolution logic.** The `resolve_button_command` function has deeply nested conditionals checking mode-level buttons, switch-mode buttons, selection-aware buttons — this is a decision table that would be better expressed as data-driven configuration.

**Maintainability observations:** This is the most problematic file in the codebase by far. At 762 lines, it's nearly double any other module. The `_build_button_action_map` function alone is ~150 lines of nested loops building a complex multi-dimensional table. The `resolve_button_command` function has 4 levels of nesting and multiple exit paths. Consider splitting into: (a) action map builder, (b) button command executor, (c) twist knob executor, (d) trim wheel executor, (e) mode cycling manager.

---

### Custom Aircraft Modules

#### B58.lua — Baron 58 Custom Commands (218 lines)
**Primary responsibility:** Rudder trim and cowl flap dataref manipulation with boost/debounce logic for the Baron 58 aircraft.
**Testability score: 2/5.** Duplicated pattern from C90B.lua with direct `dataref_table()` calls and `create_command()` registration. The debounce+boost logic is pure computation but embedded in command handlers that call FlyWithLua globals.

#### C90B.lua — King Air C90B Custom Commands (314 lines)
**Primary responsibility:** Cabin pressure, cabin pressure rate, decision height, and cabin temperature dataref manipulation with boost/debounce for the C90B aircraft.
**Testability score: 2/5.** Same pattern as B58.lua — duplicated code structure across multiple control domains (pressure, rate, height, temperature). The debounce+boost logic is identical in every handler block.

#### DA42.lua — DA42/DA62 Custom Commands (92 lines)
**Primary responsibility:** Rudder trim dataref manipulation for the Aerobask DA42 and DA62 aircraft.
**Testability score: 3/5.** Smaller scope than B58/C90B but same pattern. Only handles rudder trim, making it somewhat more focused.

#### Transponder.lua — VFR Code Auto-Setting (49 lines)
**Primary responsibility:** Automatically set VFR transponder code (1200 for North America, 7000 elsewhere) based on GPS coordinates. Toggle capability included.
**Testability score: 3/5.** The `is_in_north_america()` function is pure logic and testable if extracted from the module scope. Direct dependency on FlyWithLua globals (`get`, `dataref_table`) limits standalone testing.

---

## Finding 2: Coupling & Dependency Map

### Module Dependency Graph

```
util.lua          ← [no dependencies] (leaf node)
log.lua           ← [no Lua deps, depends on _G.logMsg] (leaf node)
state.lua         ← [no dependencies] (leaf node)
debug.lua         ← log.lua
hardware.lua      ← log.lua
decoder.lua       ← log.lua, debug.lua, state.lua, bit (external)
mapbuilder.lua    ← util.lua, config.lua
config.lua        ← util.lua
plugincheck.lua   ← log.lua (also depends on _G.RESOURCE_PATH, imgui)
ui.lua            ← util.lua (also depends on _G.imgui)
dispatch.lua      ← util.lua, log.lua (also depends on _G.command_once/begin/end)

BravoMultiMode.lua (main entry point) ← ALL modules above + custom/*.lua files
```

### Dependency Analysis

**No circular dependencies detected.** The dependency graph is a clean DAG (Directed Acyclic Graph):
- Leaf nodes: `util.lua`, `log.lua`, `state.lua` — no internal Lua module dependencies.
- Mid-level: `debug.lua`, `hardware.lua` depend only on leaf nodes.
- Upper level: `decoder.lua` depends on mid-level + state; `config.lua` and `mapbuilder.lua` are upper-mid.
- Top level: `dispatch.lua`, `ui.lua`, `plugincheck.lua` sit at the top of the hierarchy, each depending on multiple lower modules plus FlyWithLua host globals.

**God Object Concern — dispatch.lua (762 lines):** This is the most significant architectural concern. While it doesn't create a circular dependency, its sheer size and number of responsibilities make it:
1. Difficult to test in isolation (every method has side effects).
2. Hard to modify without unintended consequences (changes ripple across many behaviors).
3. A bottleneck for parallel development (multiple developers working on different button/knob/switch features would conflict).

**Tight Coupling Points:**
- `mapbuilder.lua` → `config.lua`: MapBuilder loads config at runtime via `require("bravo++.config")`, coupling the mapping initialization to validation logic.
- `BravoMultiMode.lua` (main entry): This ~1,300-line script is itself a god object that wires all modules together, manages aircraft detection, config loading, floating window creation, and frame-by-frame callback registration. It should be split into an orchestrator + module initializers.

---

## Finding 3: Global State Assessment

### _G Mutations and Shared Mutable State

| Module | Global State Pattern | Impact on Testing |
|--------|---------------------|-------------------|
| `log.lua` | Reads `_G.logMsg` (FlyWithLua global) at module load time. No mutations to _G. | Low — easy to mock via `_G.logMsg = fn`. |
| `hardware.lua` | Declares globals with type annotations (`local hid_read = hid_read`). Does NOT mutate _G. | Low — declared but not modified. |
| `plugincheck.lua` | Reads `_G.RESOURCE_PATH`, `_G.imgui`, `_G.float_wnd_create`. No mutations to _G. | Medium — these FlyWithLua globals must be mocked for any test touching this module. |
| `mapbuilder.lua` | Uses `_G.dataref_table_fn = _G.dataref_table` (declared at top). Calls it during LED map building. | High — DataRef lookups are side-effect-producing and require mocking. |
| `dispatch.lua` | References `_G.command_once`, `_G.command_begin`, `_G.command_end`. No mutations to _G but calls these globals directly in action methods. | Very high — every button/knob/switch action fires a host command, making pure unit testing impossible without monkey-patching. |
| `custom/*.lua` | Each creates commands via `_G.create_command()` and reads datarefs via `_G.dataref_table()`. Also reads `_G.AIRCRAFT_FILENAME`, `_G.MODULES_DIRECTORY`. | Very high — these modules are inherently coupled to the FlyWithLua runtime environment. |

### Singleton-like Patterns

1. **`state.lua` module table:** The `bravo++.state` module is imported once and its internal state (`selector`, `rotary`, `trim`) persists across the entire application lifecycle. This is intentional but means tests must call `reset()` between scenarios (already done in decoder tests).
2. **`dispatch.lua` local state:** Multiple mutable variables (`current_mode`, `command_state[]`, `arrow_color`) persist as module-level locals, effectively acting as a singleton pattern within the dispatch module. No reset function exists — this is a gap for testing.
3. **`ui.lua` text layout cache:** The `text_layout_cache` table grows unbounded (with LRU eviction at 100 entries). This is not testable from outside and could cause state leakage between tests if the cache persists across require calls.

### Global State Complexity Rating: HIGH

The combination of FlyWithLua host globals, module-level mutable state in dispatch.lua, and DataRef table references creates a testing environment where **no module can be tested in complete isolation**. The best approach is layered mocking (mock _G functions at the bootstrap level) combined with careful reset patterns.

---

## Finding 4: Side Effects vs Pure Logic Ratio

### Per-Module Estimates

| Module | Pure Logic % | Side Effect % | Notes |
|--------|-------------|---------------|-------|
| `util.lua` | ~85% | ~15% | Most functions are pure. Only `create_table`, `safe_dataref_lookup`, `safe_command_lookup`, and `list_files` have side effects. |
| `log.lua` | 100% | 0% | Pure function composition (formatting + level check). The only "side effect" is calling `_G.logMsg`. |
| `state.lua` | ~60% | ~40% | Getters are pure; setters have side effects (pub/sub notification, state mutation). |
| `debug.lua` | ~90% | ~10% | Diff computation is pure. Only `log.debug()` call is a side effect. |
| `config.lua` | ~35% | ~65% | Condition compilation/evaluation is pure (~40 lines), but validation functions trigger DataRef lookups, file I/O, and command existence checks. |
| `decoder.lua` | ~70% | ~30% | Detection logic (bytes → events) is pure. Handler invocation and state updates are side effects. |
| `hardware.lua` | ~45% | ~55% | Injection queue management is pure; polling loop, HID reads, and report dispatching are side effects. |
| `mapbuilder.lua` | ~50% | ~50% | Traversal logic is pure given inputs; DataRef table creation during LED map building has host-side effects. |
| `plugincheck.lua` | ~30% | ~70% | Filesystem inspection and process listing are side-effect-heavy. ImGui rendering adds more. |
| `ui.lua` | ~25% | ~75% | Text wrapping/scaling logic is pure (~80 lines), but 90% of the file is ImGui drawing calls. |
| `dispatch.lua` | ~15% | ~85% | Condition resolution in `resolve_button_command` has some pure logic, but nearly all public methods directly invoke host commands or mutate state. |
| Custom modules | ~20% | ~80% | Debounce+boost math is pure (~30 lines per file), but everything else calls `_G.create_command()` and manipulates DataRef tables. |

### Overall Codebase Estimate: **~45% pure logic, ~55% side effects**

This ratio means that achieving 80% line coverage through unit tests alone will be challenging — many lines involve host-side effects (command execution, DataRef writes, ImGui rendering) that require either integration testing or extensive mocking. The decoder module (~70% pure) and util module (~85% pure) are the easiest targets for high-coverage unit tests.

---

## Finding 5: Mocking Feasibility Assessment

### External Dependencies Matrix

| Dependency | Type | Current Mock Status | Feasibility | Gap Analysis |
|-----------|------|---------------------|-------------|--------------|
| `_G.logMsg` | FlyWithLua host function | ✅ Mocked in `_bootstrap.lua` | Trivial — simple callback replacement. | None. Already working. |
| `os.clock()` | Lua standard library | ✅ Mocked in `_bootstrap.lua` via `set_time`/`advance_time` | Trivial — global function swap. | None. Already working. |
| `bit.*` (bitwise ops) | External library | ✅ Shimmed in `tests/bit.lua` | Good — pure Lua implementation of all needed functions. | Complete coverage for decoder needs (`band`, `bor`, `bxor`, `lshift`). |
| `_G.XPLMFindDataRef` / `_G.dataref_table` | FlyWithLua host function | ❌ Not mocked | Moderate — can be added to bootstrap as table-returning stubs. | Needed by config.lua validation and mapbuilder.lua LED initialization. |
| `_G.command_once/begin/end` | FlyWithLua host command execution | ❌ Not mocked | Easy — global function replacement with no-op or call-capture mocks. | Critical gap for dispatch.lua testing. |
| `hid_read`, `hid_set_nonblocking` | FlyWithLua HID functions | ⚠️ Partially handled via injection queue in hardware.lua | Good — the injection queue bypasses physical HID entirely. | Only needed if testing hardware.lua's physical read path (not currently tested). |
| `_G.imgui` | FlyWithLua ImGui bindings | ❌ Not mocked | Hard — imgui is a large API with many methods. Would need a partial mock covering only used functions. | Blocks all ui.lua and plugincheck.lua testing. |
| `io.popen` | Lua standard library | ⚠️ Available in CLI but may behave differently than FlyWithLua sandbox | Moderate — can be mocked to return controlled output for filesystem checks. | Needed by config validation (DataRef existence), plugincheck, util.list_files. |
| `_G.create_command` | FlyWithLua command registration | ❌ Not mocked | Easy — no-op function replacement. | Blocks custom module testing. |
| `package.config` | Lua standard library | ✅ Available in CLI | N/A — works as-is for platform detection. | None. |

### Bootstrap Gap Summary

The current `_bootstrap.lua` provides excellent mocks for the decoder test suite (`logMsg`, `os.clock`, `bit`). To extend testing to other modules, the following additions are needed:
1. Mock `_G.command_once`, `_G.command_begin`, `_G.command_end` (for dispatch.lua).
2. Mock `_G.dataref_table` and `_G.XPLMFindDataRef` (for config.lua validation and mapbuilder.lua).
3. Mock `_G.create_command` (for custom modules).
4. Partial mock of `_G.imgui` with only the methods actually called by ui.lua/plugincheck.lua.
5. Optional: Mock `io.popen` for controlled filesystem testing in plugincheck.lua.

---

## Finding 6: Code Quality Observations

### Naming Consistency
- **Strengths:** Module-level exports use consistent naming (`bravo++.module_name`). Function names are descriptive and follow camelCase convention (`detect_rotary_event_from_bytes`, `compile_condition`). Constants use UPPER_SNAKE_CASE.
- **Weaknesses:** Inconsistent module variable naming: some modules use `local M = {}` (state.lua, hardware.lua), others use `local util = {}` or `local dispatch = {}`. The main entry point uses both patterns inconsistently.

### Duplication Across Files
- **Critical duplication:** The debounce+boost dataref manipulation pattern is copied verbatim across B58.lua, C90B.lua (4 control domains), and DA42.lua. Each handler function follows the exact same structure: read current value → check time diff → apply increment with boost if recent → clamp to min/max → write back. This should be extracted into a shared utility function in `util.lua` or a new `trim_utils.lua`.
- **Moderate duplication:** The `is_windows` platform detection pattern (`package.config:sub(1, 1) == "\\"`) appears in config.lua, decoder.lua, dispatch.lua, plugincheck.lua, and hardware.lua. This should be centralized in util.lua as `util.is_windows()`.

### Error Handling Patterns
- **Strengths:** Consistent use of `pcall` for error isolation (decoder handlers, hardware poll loop, main entry point's `try_catch`). Defensive nil checks throughout (`if not device then return false end`, etc.).
- **Weaknesses:** No structured error types or error codes — errors are communicated as string messages. The `compile_condition` function silently defaults to a "always-false" condition on invalid input rather than throwing, which could mask configuration errors at runtime.

### Configuration Complexity
- The config system supports 4+ levels of key hierarchy (mode → selection → button → UP/DOWN), multiple operator types (`!=`, `<=`, `>=`, `<`, `>`, `=`), and array DataRef indexing. This is powerful but creates a steep learning curve for new contributors.
- The validation logic in config.lua has 12+ different key patterns to handle, each with its own rules (e.g., SELECTOR_LABELS must have exactly 5 values, BUTTON_LABELS must have exactly 8). Adding new key types requires modifying the large `validate_values` function.

### Documentation Quality
- **Strengths:** Module-level docstrings describe responsibilities clearly (`bravo++.dispatch - Command and Action Mapping Module`). The MapBuilder module has a detailed header comment explaining its purpose. Inline comments explain non-obvious logic (e.g., why trim bits are checked before selector).
- **Weaknesses:** No API documentation for public functions (no `--- @param` / `--- @return` annotations except in a few places). The custom modules have minimal documentation beyond the aircraft name header.

---

# Evaluation / Options

## Testing Strategy Options Considered

### Option A: Test as-Is with Extensive Mocking
Write tests against the current codebase without any refactoring, using increasingly elaborate mocks for FlyWithLua globals and dispatch-side effects.

**Pros:** No code changes required; immediate progress on coverage numbers.
**Cons:** Tests will be fragile (tightly coupled to implementation details), slow to write (extensive mocking per test), and high-maintenance (any refactor breaks many tests). Coverage gains will plateau at ~50-60% because ui.lua, dispatch.lua action methods, and custom modules are nearly impossible to test without integration-level mocks.

### Option B: Targeted Refactoring + Testing
Perform focused refactoring on the highest-value targets (dispatch god object split, config validation extraction, duplication elimination), then write tests against the cleaned-up code.

**Pros:** Tests will be more stable and easier to write; maintainability improves alongside coverage; hardest-to-test modules become testable through better design.
**Cons:** Requires additional effort before meaningful coverage gains; risk of over-engineering if refactoring scope is not carefully bounded.

### Option C: Hybrid — Test Easy Modules First, Refactor in Parallel
Start with high-purity modules (util, log, state, debug) to build test infrastructure momentum and achieve quick coverage wins on the 40-50% that's easily reachable. Simultaneously plan refactoring for dispatch/config/ui while writing tests for decoder (already done).

**Pros:** Delivers incremental value; builds team confidence with early wins; allows time to design refactoring carefully.
**Cons:** Requires careful planning to avoid testing code that will be refactored soon (wasted effort); may need to rewrite some tests after refactoring.

## Preferred Direction: Option C (Hybrid)

The evidence strongly supports a hybrid approach:
1. **Immediate wins:** util.lua (~85% pure), log.lua (100% pure), state.lua, debug.lua can achieve 90%+ coverage with minimal mocking effort. These are low-risk and deliver quick percentage gains.
2. **Parallel refactoring planning:** dispatch.lua should be split into smaller modules before testing begins — this is the single highest-ROI refactoring for testability. config.lua's condition compilation logic should be extracted to a separate module.
3. **Integration tests for remaining modules:** ui.lua, plugincheck.lua, and custom modules will require integration-level testing (mocking imgui or using FlyWithLua's actual runtime). These can achieve coverage but at higher maintenance cost.

---

# Risks / Constraints / Open Questions

## Risks
1. **dispatch.lua refactoring is high-risk.** Splitting a 762-line god object without breaking the main entry point wiring could introduce regressions in button/knob/switch behavior that directly affect pilot operation. Any refactoring must be accompanied by comprehensive integration tests before merging.
2. **Config validation side effects during testing.** The `validate_values` function's DataRef lookups cannot be fully mocked — they require either a full FlyWithLua environment or careful stubbing of the return values for every possible key pattern tested.
3. **Test infrastructure fragility.** The current `_bootstrap.lua` mocks are CLI-specific and may not work if the test runner changes (e.g., from busted to another framework).

## Constraints
1. **FlyWithLua sandbox limitations.** Some FlyWithLua globals (`do_every_frame`, `create_command`) cannot be meaningfully mocked in a CLI environment — they require actual X-Plane/FlyWithLua runtime for integration testing.
2. **No existing CI/CD pipeline for Lua tests.** The busted test suite exists but has no automated execution in the project's development workflow. This means coverage regressions won't be caught automatically.
3. **Aircraft-specific custom modules are tightly coupled to AIRCRAFT_FILENAME and AIRCRAFT_PATH globals**, making them impossible to test without setting these globals or extracting their logic into aircraft-agnostic functions.

## Open Questions
1. What is the expected testing framework for REQ-007? The current setup uses busted, but has this been validated as suitable for the team's workflow?
2. Should integration tests that require actual FlyWithLua/X-Plane runtime be included in the 80% coverage target, or should they be excluded from unit test metrics?
3. Is there a plan to add CI/CD automation for Lua testing (e.g., GitHub Actions running busted on every PR)?

---

# Supporting Materials / Evidence

## Code Paths Reviewed
- All 15 Lua source files in `FlyWithLua/Modules/bravo++/` (full text read).
- Main entry point: `FlyWithLua/Scripts/BravoMultiMode.lua` (~1,300 lines, key sections read showing module wiring at lines 100-500+).
- Test infrastructure: `tests/_bootstrap.lua`, `tests/init.lua`, `tests/bit.lua`.
- Existing tests: `tests/decoder_spec.lua` (67 test cases across 8 describe blocks covering rotary events, selector events, trim events, state integration, diagnostics, handler configuration, end-to-end HID cycles, and edge cases).

## Dependency Graph Summary
```
util ──→ log ──→ debug ──→ decoder ──→ state
config ──→ mapbuilder
hardware ──→ (polling loop feeds decoder via handlers)
dispatch ←── util + log + [host globals: command_once/begin/end]
ui ←── util + [host global: imgui]
plugincheck ←── log + [host globals: RESOURCE_PATH, imgui, float_wnd_create]

All modules wired together in BravoMultiMode.lua (main entry point)
Custom aircraft modules (B58, C90B, DA42, Transponder) loaded via dofile() at startup.
```

## Existing Test Coverage Baseline
- **decoder_spec.lua:** 67 tests covering decoder.lua and state.lua integration. This is the only Lua test file in existence.
- **Coverage tooling:** luacov configured for coverage instrumentation (referenced in `_bootstrap.lua`).
- **Test framework:** busted with helper/bootstrap pattern (`--helper tests/_bootstrap.lua`).

---

# Next Steps

1. **Immediate (before REQ-007 begins):** Add missing mocks to `_bootstrap.lua` — specifically `_G.command_once`, `_G.command_begin`, `_G.command_end`, and a stub for `_G.dataref_table`. This unlocks testing of dispatch.lua and config.lua validation logic.
2. **Parallel track:** Begin writing tests for the highest-purity modules first: util.lua (167 lines, ~85% pure), log.lua (40 lines, 100% pure), state.lua (67 lines, well-structured with reset function). These can achieve high coverage quickly and build test infrastructure momentum.
3. **Refactoring planning:** Create a separate design document for dispatch.lua splitting strategy — define the boundaries between button executor, twist knob executor, trim wheel executor, mode cycling manager, and command resolver modules. This should be reviewed before any code changes begin.
4. **Duplication elimination:** Extract the debounce+boost dataref manipulation pattern from custom/*.lua files into a shared utility function in util.lua or a new module. This reduces ~600 lines of duplicated code to a single reusable function.
5. **CI/CD setup:** Establish automated Lua test execution (busted + luacov) in the project's CI pipeline to prevent coverage regressions and provide real-time feedback during REQ-007 development.

---

# Companion Notes / Raw Evidence

Detailed investigation notes, raw data tables, function-level analysis, and exhaustive evidence are stored separately for reference. The main SPIKE document above captures the question, methodology, findings, evaluation, and recommendation only.
