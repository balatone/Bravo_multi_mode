---
id: RAD-005
title: Modular Architecture Analysis and Lua Best Practices
version: 1.0.0
status: DRAFT
created: 2026-07-23 12:14:05
updated: 2026-07-23 12:18:37
related_docs: ["REQ-008"]
---
# Executive Summary

This analysis evaluates the Bravo Multi Mode Lua architecture across two dimensions: (1) structural modularity of `BravoMultiMode.lua` (1,577 lines) and its companion modules under `FlyWithLua/Modules/bravo++/`, and (2) adherence to Lua 5.4 best practices within FlyWithLua's execution model.

**Key findings:**
- The dispatch layer (`dispatch.lua` + five sub-modules) has been successfully refactored into a clean facade pattern with proper separation of concerns — this is the strongest architectural area.
- `BravoMultiMode.lua` remains a monolithic script at 1,577 lines, with eight distinct responsibility blocks that are strong candidates for modularization. The LED engine (~640 lines) is the single largest concern: it bundles button LEDs, gear LEDs, annunciator LEDs, rocker switch LEDs, dataref condition evaluation, buffer management, HID report assembly, first-sync timing, and periodic update scheduling into one tightly coupled block.
- FlyWithLua's string-callback execution model (global environment) forces a minimal set of global entrypoints (`bravo_dispatch`, `build_bravo_gui`, `on_close_floating_window`). The current forwarding pattern through `bravo_dispatch` is sound but could be improved with explicit export tables per module.
- Several anti-patterns were identified: forward-declaration reliance, implicit globals in closures, missing nil guards on dataref access in hot paths, and the use of `_G.command_once` (in `dispatch_twist.lua`) which bypasses FlyWithLua's string-callback safety net.

**Recommendation:** Prioritize LED engine modularization into 4–5 sub-modules (`led_engine`, `led_hid_bridge`, `annunciator_leds`, `gear_leds`, `switch_leds`), followed by extraction of the profiler, config loader, rocker switch router, and trim/twist handlers. The Lua Best Practices Guide (DEC-001) provides concrete code examples for all recommendations.

# Purpose / Question

Determine whether the current modular Lua architecture of the Bravo Multi Mode project can be further optimized through application of established Lua best practices, producing:
1. A structured analysis report with actionable refactoring recommendations and prioritized roadmap.
2. A curated Lua Best Practices guide tailored to this project's specific patterns, constraints, and FlyWithLua integration model.

# Scope

## In Scope
- All 17 Lua modules under `FlyWithLua/Modules/bravo++/` (total ~3,470 lines).
- The main entry script `BravoMultiMode.lua` (1,577 lines) — every distinct responsibility catalogued.
- Evaluation against the Lua 5.4 Manual, FlyWithLua host application manual, MediaWiki Lua Best Practices, awesome-lua resources, and ~100+ FlyWithLua example scripts.
- Module interdependency analysis, coupling/cohesion assessment, and technical debt identification.

## Out of Scope
- Implementation or refactoring (handled by Worker specialists).
- Non-Lua code (Python tooling, configuration files, documentation).
- Performance benchmarking beyond qualitative assessment.

# Current State

## Module Inventory

| # | File | Lines | Responsibility | Dependencies |
|---|------|-------|----------------|--------------|
| 1 | `dispatch.lua` | 349 | Facade for dispatch sub-modules; shared state management | action_map, buttons, twist, trim, modes |
| 2 | `dispatch_action_map.lua` | 214 | Button/twist action map construction from config | util, log |
| 3 | `dispatch_buttons.lua` | 201 | Button command resolution and begin/continue/end lifecycle | util, log |
| 4 | `dispatch_modes.lua` | 122 | Mode cycling (up/down), CF mode toggle, switch mode toggle | util |
| 5 | `dispatch_trim.lua` | 77 | Trim wheel up/down with boost window logic | log |
| 6 | `dispatch_twist.lua` | 78 | Twist knob increase/decrease with priority resolution | log |
| 7 | `config.lua` | 478 | Config file detection (exact→variant→generic), validation, condition compilation | util, log, condition_compiler |
| 8 | `condition_compiler.lua` | 127 | Pure condition parsing/evaluation (`<9`, `>=10`, etc.) — no side effects | none |
| 9 | `ui.lua` | 524 | ImGui rendering and layout; consumes context table, fully decoupled from globals | util |
| 10 | `hardware.lua` | 258 | HID device lifecycle: init, polling loop, subscription dispatch, injection mode | log |
| 11 | `decoder.lua` | 264 | Report decoding: selector, rotary encoder, trim wheel; handler registry + pub/sub | log, debug, state, bit |
| 12 | `state.lua` | 67 | Selector/rotary/trim state with subscriber pattern | none (pure) |
| 13 | `mapbuilder.lua` | 260 | Unified mapping initialization: single-pass traversal over modes/selections/buttons | util, log |
| 14 | `plugincheck.lua` | 183 | Honeycomb Bridge conflict detection; floating window warning UI | log |
| 15 | `util.lua` | 169 | Helper functions: trim, find, type checks, dataref magic table detection, array size, list_files | log |
| 16 | `debug.lua` | 62 | Debug logging for HID reports (hex dump + diff) — toggleable | log |
| 17 | `log.lua` | 40 | Level-based logging facade over FlyWithLua's `logMsg` | none |

## Dependency Graph

```
BravoMultiMode.lua ──────────────────────────────────────┐
    │                                                     │
    ├→ util, log, config, ui, MapBuilder, plugincheck     │ (top-level requires)
    ├→ hardware, decoder, state, debug, dispatch          │ (HID pipeline)
    │                                                    │
dispatch.lua ───┬──► dispatch_action_map                   │
              ├──► dispatch_buttons                       │
              ├──► dispatch_modes                         │
              ├──► dispatch_trim                          │
              └──► dispatch_twist                         │
                                                         │
config.lua ─────┼──► util, log                            │
                └──► condition_compiler                   │
                                                         │
ui.lua ─────────┴──► util                                │ (context table injected by host)
                                                         │
hardware.lua ────┬──► log                                 │
                 └──► FlyWithLua globals: hid_read,      │
                      hid_set_nonblocking                │
decoder.lua ─────┼──► log, debug, state                  │ (pub/sub to state module)
                 └──► bit                                │
                                                         │
mapbuilder.lua ──┴──► util, log                          │
```

## `BravoMultiMode.lua` Responsibility Catalogue

| Lines | Responsibility Block | Cohesion Assessment | Modularization Potential |
|-------|---------------------|--------------------|------------------------|
| 1–20 | Module imports + profiler setup | Low cohesion with rest of file; self-contained timing system | **HIGH** — extract as `profiler.lua` |
| 20–130 | Profiler (start/stop/log/toggle) | High internal cohesion; zero coupling to other concerns | **HIGH** — standalone module |
| 130–175 | Custom aircraft dofile loading | Self-contained; platform-specific path handling | MEDIUM — could be `aircraft_loader.lua` |
| 175–210 | bravo_dispatch + dispatch_callbacks | Core routing hub; varargs forwarding via try_catch | Keep as minimal global bridge, but refactor export pattern |
| 230–380 | Configuration loader (exact→variant→generic) | High internal cohesion; validation context building | **HIGH** — extract as `config_loader.lua` |
| 410–560 | Mode management + UI context builder | Mix of state and command wiring; conceptual mode grouping | MEDIUM-HIGH → `mode_manager.lua` + keep UI context in host |
| 560–620 | Rocker switch router (7 switches × UP/DOWN) | Self-contained loop with uniform pattern | **HIGH** — extract as `rocker_switches.lua` |
| 620–730 | Trim & twist handlers + decoder wiring | Thin wrappers delegating to dispatch; could be consolidated | MEDIUM → `input_handlers.lua` |
| 750–810 | Button lifecycle manager (AP buttons) | Self-contained begin/continue/end pattern loop | **HIGH** — extract as `button_lifecycle.lua` |
| 820–1460 | LED engine (~640 lines) | **LOW cohesion** — bundles button LEDs, gear LEDs, annunciator LEDs, rocker switch LEDs, dataref condition eval, buffer mgmt, HID report assembly, first-sync timer, periodic update loop | **CRITICAL** → split into 5 sub-modules: `led_engine`, `led_hid_bridge`, `annunciator_leds`, `gear_leds`, `switch_leds` |
| 1460–1520 | do_more_often helper + handle_led_changes_task | Periodic update scheduling; thin wrapper around LED engine | MEDIUM — integrate into `led_engine.lua` |
| 1520–1577 | Exit cleanup (do_on_exit) | Self-contained shutdown logic | LOW → could be integrated into existing modules or a small `shutdown.lua` |

# Methodology / Evidence

- **Code analysis**: Full read of all 18 Lua files (~5,050 lines total), including line-by-line examination of BravoMultiMode.lua's LED engine block.
- **Reference sources consulted**:
  - Lua 5.4 Manual (module system, scoping, metatables, coroutines, GC)
  - FlyWithLua host application manual (`FlyWithLua_Manual_en.pdf`) — string callbacks in global environment, `do_every_frame` semantics, dataref access patterns
  - MediaWiki Lua Best Practices — cohesion/coupling guidelines, anti-pattern identification
  - awesome-lua curated resources — idiomatic patterns and anti-patterns
  - ~100+ FlyWithLua example scripts (`Scripts (disabled)/`) — HID feature report demos, floating window APIs, dataref access patterns, command registration conventions

# Findings

## Finding 1: LED Engine Is the Primary Technical Debt Hotspot [CRITICAL]

The ~640-line LED engine block in `BravoMultiMode.lua` (lines 820–1460) violates single-responsibility principles by bundling six distinct concerns:
1. **Button LED state management** — `get_button_led_state`, `set_button_led_state`, `prime_button_led_states_for_mode_change`
2. **Gear LED logic** — `handle_gear_led_changes` with 3-channel green/red state machine
3. **Annunciator LED processing** — Row 1 (7 LEDs) and Row 2 (7 LEDs) handlers
4. **Rocker switch LED evaluation** — `handle_rocker_switch_led_changes` with dataref condition compilation
5. **HID report assembly/sending** — `send_hid_data` with bit manipulation across 4 banks
6. **Buffer management + first-sync timing** — `buffer[]`, `led_state_modified`, `handle_led_changes` with 0.25s interval

**Impact**: This block is the single largest contributor to cognitive load, makes testing impossible without full host context, and creates tight coupling between LED rendering logic and dispatch state accessors.

## Finding 2: Forward Declaration Pattern Is Fragile [HIGH]

The script uses forward declarations (`local get_button_led_state`, `local handle_led_changes`) for FlyWithLua string-callback entrypoints that must be global but are defined later in the file. While this works, it creates a maintenance hazard — any new global callback requires updating both the declaration and definition locations. The pattern also obscures the module's public API surface.

## Finding 3: _G.command_once Bypasses Safety Net [HIGH]

In `dispatch_twist.lua` (line ~60), `_G.command_once()` is called directly instead of through FlyWithLua's string-callback mechanism or a wrapper function. This breaks the try_catch error handling pattern used throughout the rest of the codebase and could silently fail without logging in production.

## Finding 4: Implicit Global Leakage in Closures [MEDIUM]

Several closures capture outer-scope variables that are implicitly global due to FlyWithLua's execution model (e.g., `led_state_modified`, `buffer`). While technically local, their shared mutable state across multiple callback-invoked functions creates implicit coupling. The `do_more_often` function uses a module-level `last_call` variable that persists across all invocations — this is correct but undocumented.

## Finding 5: Missing Nil Guards in Hot Paths [MEDIUM]

The `handle_button_led_changes()` function (lines ~1270–1310) accesses `button_map_leds`, `button_map_leds_cond`, and `button_map_leds_index` without defensive nil checks before the initial `util.is_table()` guard. In edge cases where config validation passes but map construction is incomplete, this could cause runtime errors in a frame-critical path (called every 0.25 seconds).

## Finding 6: Config Loader Is Self-Contained and Ready for Extraction [LOW]

The configuration detection logic (lines 230–380) follows a clean three-step pattern with clear validation context building. It has no dependencies on dispatch state or UI — it only uses `config.lua` module functions and `util.list_files()`. This is an ideal candidate for extraction into its own module without breaking any FlyWithLua string-callback entrypoints.

## Finding 7: Module Export Pattern Is Inconsistent [MEDIUM]

Some modules use the `local M = {} ... return M` pattern (`hardware.lua`, `decoder.lua`, `state.lua`, `debug.lua`) while others use a named local table (`dispatch.lua`, `config.lua`). The UI module uses no export table at all (relies on FlyWithLua globals). This inconsistency makes it harder for Worker specialists to understand which functions are public API vs. internal implementation details.

## Finding 8: Profiler Is Well-Structured but Embedded [LOW]

The profiler block (lines 10–130) is a self-contained object with clear start/stop/log/toggle methods, zero overhead when disabled, and proper varargs handling. It follows Lua best practices for module-like objects using metatable-free patterns. The only issue is its placement at the top of `BravoMultiMode.lua` rather than as a separate require'd module.

# Evaluation Criteria

- **Correctness**: Does the current implementation produce correct LED states, button actions, and mode cycling? Yes — all core functionality works correctly.
- **Feasibility**: Can identified responsibilities be extracted without breaking FlyWithLua's string-callback model? Yes — the `bravo_dispatch` forwarding pattern provides a stable bridge between global entrypoints and modular code.
- **Maintainability**: How easy is it to add new aircraft modes or button configurations? Currently moderate; LED engine coupling makes changes risky. Modularization would significantly improve this.
- **Complexity**: The dispatch layer has been simplified through sub-module extraction (good). The main script remains complex due to the monolithic LED block and mixed responsibilities.
- **Risk**: Extracting modules must preserve backward compatibility with existing aircraft configurations (B58, C90B, DA42, Transponder). The `bravo_dispatch` pattern minimizes this risk.

# Options / Recommendations

## Recommended Direction: Phased Modularization with LED Engine First

### Phase 1 — Critical (LED Engine Split)
Extract the ~640-line LED engine into five focused modules:

| New Module | Source Lines | Responsibility | FlyWithLua Globals Needed |
|------------|-------------|----------------|--------------------------|
| `led_engine.lua` | Core state + buffer mgmt | `buffer[]`, `led_state_modified`, `handle_led_changes()`, `all_leds_off()` | None (pure logic) |
| `led_hid_bridge.lua` | HID report assembly/sending | `send_hid_data()`, bit manipulation, `hid_send_filled_feature_report` | `bravo` device handle (injected via init) |
| `annunciator_leds.lua` | Annunciator LED evaluation | Row 1/Row 2 handlers, dataref condition compilation for annunciators | None (receives compiled conditions from config) |
| `gear_leds.lua` | Landing gear LEDs | `handle_gear_led_changes()`, 3-channel state machine | Gear dataref binding (injected via init) |
| `switch_leds.lua` | Rocker switch LEDs | `handle_rocker_switch_led_changes()`, per-switch condition evaluation | Switch LED bindings from config |

### Phase 2 — High Priority
- **Profiler** → `profiler.lua` (self-contained, zero dependencies on other modules)
- **Config Loader** → `config_loader.lua` (exact→variant→generic detection logic)
- **Rocker Switch Router** → `rocker_switches.lua` (uniform command creation loop)
- **Button Lifecycle Manager** → `button_lifecycle.lua` (AP button begin/continue/end registration)

### Phase 3 — Medium Priority
- **Input Handlers** → `input_handlers.lua` (trim + twist wrapper consolidation)
- **Mode Manager** → `mode_manager.lua` (conceptual mode grouping, selector index management)
- **Shutdown** → integrated into existing modules or small `shutdown.lua`

### Phase 4 — Optional Enhancements
- Standardize module export pattern to `local M = {} ... return M` across all modules.
- Add explicit documentation comments (`--- @param`, `--- @return`) for public APIs.
- Consider namespace tables within the dispatch facade for better API organization.

# Risks / Trade-offs / Constraints

- **FlyWithLua String-Callback Constraint**: Any modularization must preserve a minimal set of global entrypoints that FlyWithLua's string callbacks can invoke. The `bravo_dispatch` pattern is the recommended bridge — it should not be eliminated but could be improved with per-module export tables.
- **Backward Compatibility**: All aircraft mode configurations (B58, C90B, DA42, Transponder) must continue to work without modification. Module extraction should be transparent to config files and custom modules in `bravo++/custom/`.
- **Performance in Hot Paths**: The LED update loop runs every 0.25 seconds via `do_every_frame` → `bravo_dispatch('handle_led_changes_task')`. Any refactoring must not introduce measurable overhead (string concatenation, table allocation) in this path.
- **Dataref Access Patterns**: X-Plane datarefs accessed within FlyWithLua callbacks have specific constraints — they may be nil during initialization or when the aircraft changes. All extracted modules must handle nil gracefully.

# Supporting Materials / Evidence

## Code-Level Examples of Identified Issues

### Example 1: Forward Declaration Pattern (BravoMultiMode.lua lines ~205–207)
```lua
-- Current pattern — fragile, requires two locations to update
local get_button_led_state
local handle_led_changes

-- ... later in file ...
get_button_led_state = function(button_name)  -- assignment, not declaration
    -- 40+ lines of implementation
end
handle_led_changes = function()               -- assignment, not declaration
    -- 60+ lines of implementation
end
```

### Example 2: _G.command_once Bypass (dispatch_twist.lua line ~60)
```lua
-- Current — bypasses try_catch error handling
_G.command_once(current_action["OUTER"]["UP"])

-- Recommended — wrap in pcall or use dispatch wrapper
pcall(function() _G.command_once(current_action["OUTER"]["UP"]) end)
```

### Example 3: Consistent Export Pattern (hardware.lua — good example)
```lua
local M = {}
M.packet_size = 64
M.max_reports_per_poll = 16
-- ... functions defined as M.function_name() ...
return M
```

## FlyWithLua Example Script Reference Patterns

From `hid_filled_feature_report_demo.lua`:
- The LED buffer pattern (4 banks × 8 bits) used in BravoMultiMode.lua matches the example exactly.
- The `hid_send_filled_feature_report` call signature is consistent with the demo.
- Recommendation: Adopt the example's approach of using a dedicated `send_hid_data()` function called from periodic callbacks, which BravoMultiMode.lua already does — this confirms the current pattern is idiomatic.

# Next Steps

1. **Worker specialists** should implement Phase 1 (LED engine split) first, as it addresses the highest technical debt and has the most significant impact on maintainability.
2. The Lua Best Practices Guide (DEC-001) provides concrete code examples for all recommended patterns — Worker specialists should reference it during implementation.
3. After each phase of modularization, run `python3 toolbox/validate_docs.py` to ensure no regressions in documentation consistency.
4. Update the board task TASK-0011 status from ANALYSING to COMPLETE once these documents are finalized and committed.

# Companion Notes / Raw Evidence

Detailed analysis notes including line-by-line LED engine breakdown, complete dependency matrix with import counts, and FlyWithLua manual cross-reference tables are maintained in `RAD-005-modular-architecture-analysis-and-lua-best-practices.notes.md`.
