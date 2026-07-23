---
id: REVIEW-016
title: Review of Bravo++ Design Phase (DSGN-001, DSGN-002, DSGN-003)
version: 1.0.0
status: APPROVED
created: 2026-07-23 20:05:43
updated: 2026-07-23 20:08:00
verdict: REQUEST_CHANGES
related_docs: ["FEAT-016", "REQ-008", "RAD-005", "DSGN-001", "DSGN-002", "DSGN-003"]
---

# Executive Summary

This review evaluates the three design documents produced for **FEAT-016 (Bravo++ Modular Architecture Design)**:

| Document | ID | Title |
|----------|-----|-------|
| Module Interface Specification | DSGN-001 | Complete public API definitions for all 11 target modules |
| Dependency Mapping & Injection Strategy | DSGN-002 | Inter-module dependency graph, circularity analysis, injection patterns |
| FlyWithLua Callback Preservation Strategy | DSGN-003 | Bridge pattern design preserving global string-callback entrypoints |

These documents were reviewed against the requirements in **REQ-008**, findings in **RAD-005** (eight severity-classified findings), and the feature plan **FEAT-016**. The review assessed technical accuracy, completeness, consistency across all three documents, adherence to architectural principles ("Injection Over Global Access", `local M = {} ... return M` pattern), and implementation readiness.

## Key Takeaway

The design is **technically sound in its overall architecture** — the module split follows single-responsibility principles, circular dependencies are properly analyzed with injection-based resolutions, and the FlyWithLua bridge strategy correctly preserves global entrypoints while eliminating forward-declaration fragility. However, there are **four documentation gaps and one inconsistency** that must be resolved before Worker specialists can implement without ambiguity. The verdict is **REQUEST_CHANGES**.

---

# Review Scope

## In Scope
- All three DSGN documents (DSGN-001, DSGN-002, DSGN-003) — full text review
- Cross-referencing against REQ-008 requirements and RAD-005 findings
- Verification that all 11 target modules are covered in the interface spec
- Analysis of dependency map completeness and circularity resolutions
- Evaluation of FlyWithLua bridge design correctness
- Consistency checks across all three documents

## Out of Scope
- Implementation code review (no refactoring has been performed yet)
- Performance benchmarking or quantitative profiling
- Non-Lua tooling or documentation infrastructure

---

# Review Criteria

1. **Technical Accuracy & Alignment**: Do the module interfaces, dependency maps, and callback strategies align with REQ-008 requirements and RAD-005 findings?
2. **Completeness**: Are all 11 target modules covered in DSGN-001? Is the dependency map comprehensive (DSGN-002)? Does the bridge design correctly address FlyWithLua's string-callback model (DSGN-003)?
3. **Consistency**: Do the three documents work together without contradictions?
4. **Adherence to Principles**: Strict "Injection Over Global Access" principle; consistent `local M = {} ... return M` pattern specification.
5. **Implementation Readiness**: Are specifications detailed enough for a Worker specialist to implement without further clarification?

---

# Findings Summary

## Overall Assessment: REQUEST_CHANGES (4 issues requiring resolution)

| # | Severity | Document(s) | Issue |
|---|----------|-------------|-------|
| 1 | **Major** | DSGN-001, DSGN-002 | `led_engine.set_sub_handlers()` referenced in composition root wiring but not defined as a public API function in the interface spec |
| 2 | **Major** | DSGN-001 | Implicit dependency on `config.eval_condition` and undefined `get_led_state_for_dataref` in annunciator/switch modules |
| 3 | **Minor** | DSGN-001, DSGN-003 | Inconsistent handling of `_G.command_once` between input_handlers module spec and dispatch_callbacks routing table |
| 4 | **Minor** | DSGN-002 | Circular dependency analysis for `input_handlers ↔ dispatch_twist` contains a logical contradiction (no actual cycle exists) |

## Positive Findings (No Changes Required)

1. All 11 target modules are comprehensively documented with function signatures, parameter types, return values, side effects, and injection points.
2. Circular dependency analysis correctly identifies and resolves all real circularities (`led_engine ↔ dispatch`, `switch_leds ↔ dispatch`, `mode_manager ↔ led_engine`).
3. The FlyWithLua bridge strategy (DSGN-003) is well-designed: exactly 3 global entrypoints preserved, bravo_dispatch behavior unchanged, transition plan clearly documented.
4. "Injection Over Global Access" principle is consistently applied across all modules — no module accesses FlyWithLua globals or other modules directly; all dependencies are injected via `init(opts)` parameters.
5. The `local M = {} ... return M` export pattern is uniformly specified for all 11 new modules, addressing RAD-005 Finding 7 (inconsistent export patterns).

---

# Required Changes Before Approval

## Blockers

**None.** No issues are truly blocking — the architecture itself is sound. The following are documentation gaps that should be resolved before implementation begins to avoid ambiguity for Worker specialists.

## Major Issues

### Issue #1: `led_engine.set_sub_handlers()` Missing from Public API (DSGN-001 + DSGN-002)

**Location**: DSGN-001 Module 1 (`led_engine`) public API table; DSGN-002 Composition Root Wiring Pseudocode.

**Problem**: The composition root wiring pseudocode in DSGN-002 calls:
```lua
led_engine.set_sub_handlers({
    on_annunciator_row1 = function() annunciator_leds.evaluate_row1(led_engine) end,
    on_annunciator_row2 = function() annunciator_leds.evaluate_row2(led_engine) end,
    on_gear = function() gear_leds.evaluate(led_engine) end,
    on_switches = function() switch_leds.evaluate(led_engine) end,
})
```

However, `set_sub_handlers()` is **not listed** in DSGN-001's public API for `led_engine`. The current spec shows `handle_led_changes(opts)` accepting sub-handler callbacks via the opts parameter:
```lua
M.handle_led_changes(opts)  -- opts contains { on_button_leds, on_gear_leds, ... }
```

This creates two possible patterns (opts-based vs. dedicated setter method), and a Worker specialist would not know which pattern to implement.

**Resolution**: Either:
- **Option A**: Add `set_sub_handlers(opts)` as an explicit public API function in DSGN-001's led_engine table, with clear documentation of its purpose (registering sub-module evaluation callbacks for use within `handle_led_changes()`).
- **Option B**: Remove the `set_sub_handlers` call from DSGN-002's wiring pseudocode and instead pass all sub-handler callbacks through a single `init(opts)` parameter or via the opts passed to `handle_led_changes()`.

**Recommendation**: Option A is cleaner — it separates initialization-time dependencies (dispatch, button_map_leds_state) from runtime callback registration (sub-module handlers), which aligns with how FlyWithLua's frame loop will invoke these callbacks.

### Issue #2: Implicit Dependencies in Annunciator and Switch LED Modules (DSGN-001)

**Location**: DSGN-001 Module 3 (`annunciator_leds`) internal function `evaluate_single_annunciator`; Module 5 (`switch_leds`) internal function `evaluate_switch`.

**Problem**: Both modules reference functions that are not defined within the module and are not listed as injection points:

- **`annunciator_leds.evaluate_single_annunciator()`** calls `config.eval_condition(compiled_predicate, value)` — but `config` is not declared as a dependency. The `eval_condition` function exists on the existing `config.lua` module (exposed at line 475), meaning this module has an implicit static dependency on `config.lua`.

- **`switch_leds.evaluate_switch()`** calls `get_led_state_for_dataref(dataref, condition_string)` — but this function does not exist in any existing module. It was a local function in the original monolithic `BravoMultiMode.lua`. The spec says it "Uses config.eval_condition() for comparison" but doesn't explain where `get_led_state_for_dataref` itself comes from.

**Resolution**:
- For **annunciator_leds**: Either (a) add `condition_compiler` as a static dependency (`local condition_compiler = require("bravo++.condition_compiler")`) and call `condition_compiler.eval_condition()` directly, or (b) inject an `eval_fn` parameter into the bindings table during init.
- For **switch_leds**: Define `get_led_state_for_dataref` as a private function within the module itself (it's essentially: read dataref value → pass to eval_condition). Document this clearly in the internal functions section.

## Minor Issues

### Issue #3: `_G.command_once` Handling Inconsistency (DSGN-001 vs DSGN-003)

**Location**: DSGN-001 Module 10 (`input_handlers`) — `handle_twist()` function; DSGN-003 dispatch_callbacks routing table.

**Problem**:
- **DSGN-001** specifies that `_G.command_once` calls should be wrapped in `pcall/try_catch` within the input_handlers module's private function `_handle_twist_command()`. This is correct per RAD-005 Finding 3.
- **DSGN-003** shows dispatch_callbacks entries for trim commands:
```lua
dispatch_callbacks.trim_nose_up = function()
    pcall(function() _G.command_once(trim_dataref_up) end)
end
```

This duplicates the safety wrapping — once in input_handlers (as specified) and again in the routing table. If both layers exist, there's double-wrapping which is harmless but confusing. More importantly, if `handle_twist()` in input_handlers also wraps `_G.command_once`, then the dispatch_callbacks layer should delegate to `input_handlers.handle_twist(dir)` rather than calling `_G.command_once` directly.

**Resolution**: Clarify that:
- The **dispatch_callbacks routing table** delegates to module methods (e.g., `mode_manager.cycle_mode_up()`) and does NOT contain inline implementation logic.
- For trim/twist commands, the dispatch_callbacks should call `input_handlers.handle_twist("increase")` / `handle_trim("up")`, which internally handles `_G.command_once` wrapping per RAD-005 Finding 3.
- Remove direct `_G.command_once` calls from DSGN-003's dispatch_callbacks table entries for trim/twist, replacing them with delegation to input_handlers module methods.

### Issue #4: Circular Dependency Analysis Contradiction (DSGN-002)

**Location**: DSGN-002 — "Circularity 4: `input_handlers ↔ dispatch_twist`" section.

**Problem**: The circularity description states:
> "If input_handlers required dispatch_twist directly, and dispatch_twist needed input_handlers for decoder events, a cycle would form."

However, the resolution correctly notes that input_handlers uses the **full dispatch facade**, not `dispatch_twist` directly. This means there is no actual circular dependency — only a potential one if someone were to refactor incorrectly in the future. The analysis conflates "potential risk" with "actual identified circularity," which could mislead reviewers into thinking there's a real cycle that needs resolution when there isn't one.

**Resolution**: Reclassify this as **"Potential Risk (not actual circularity)"** rather than "Circularity 4." Add a note that the unidirectional dependency (`input_handlers → dispatch` facade) is already resolved by injection, and no further action is needed. This keeps the analysis accurate without over-claiming.

---

# Positive Findings

1. **Comprehensive Module Coverage**: All 11 target modules from FEAT-016 are documented with complete public API tables including function signatures, parameter types, return values, side effects, and injection points. Internal/private functions are clearly separated from the exported interface.

2. **Correct Circular Dependency Resolution**: The three real circularities (`led_engine ↔ dispatch`, `switch_leds ↔ dispatch`, `mode_manager ↔ led_engine`) are correctly identified with appropriate resolution strategies (injection pattern for module references, callback function injection for mode changes). No actual circular `require()` calls exist in the design.

3. **FlyWithLua Bridge Design is Sound**: DSGN-003 correctly identifies that exactly 3 global entrypoints must remain (`bravo_dispatch`, `build_bravo_gui`, `on_close_floating_window`), preserves bravo_dispatch's unchanged behavior, and provides a clear transition plan from forward-declaration anti-pattern to module init functions.

4. **Injection Over Global Access Principle Consistently Applied**: Every new module receives its dependencies via injection parameters in `init(opts)`. No module accesses FlyWithLua globals or requires other modules directly. The composition root (BravoMultiMode.lua) wires everything together at initialization time.

5. **Consistent Export Pattern Specification**: All 11 modules use the standard `local M = {} ... return M` pattern, addressing RAD-005 Finding 7. Public APIs are clearly documented with LuaDoc-style annotations (`--- @param`, `--- @return`).

6. **Phase Sequencing is Logical**: The dependency hierarchy (Levels 0–5) correctly orders module initialization from leaf dependencies up to the composition root. Phase ordering (CRITICAL → HIGH → MEDIUM → OPTIONAL) aligns with RAD-005's prioritized recommendations.

7. **Verification Checklist is Comprehensive**: DSGN-003 includes a FlyWithLua integration verification checklist covering all critical paths: bravo_dispatch resolution, UI rendering, exit cleanup, LED update loop timing, rocker switch commands, AP button lifecycle, mode cycling, trim/twist handling, and HID byte parity.

---

# Verification Results

## Static Analysis Performed
- Cross-referenced all 11 module interfaces against FEAT-016's target module list — **all present**.
- Verified each module's injection points against DSGN-002's dependency matrix — **consistent** (with Issues #1 and #2 noted above).
- Checked FlyWithLua global entrypoints in DSGN-003 against the existing BravoMultiMode.lua codebase — **exactly 3 globals preserved**, matching current requirements.
- Confirmed that `bravo_hid` referenced in DSGN-003's dispatch_callbacks maps to the existing `hardware.lua` module (aliased as `local bravo_hid = require("bravo++.hardware")`), which is correct but could be documented more explicitly.

## Cross-Document Consistency Checks
| Check | Result |
|-------|--------|
| DSGN-001 modules match FEAT-016 target list | ✅ All 11 present |
| DSGN-002 dependency graph matches DSGN-001 injection points | ⚠️ Issue #1 (set_sub_handlers) |
| DSGN-003 dispatch_callbacks entries map to documented module APIs | ⚠️ Issue #3 (_G.command_once duplication) |
| All modules use `local M = {} ... return M` pattern | ✅ Consistent across all 11 |
| "Injection Over Global Access" principle applied uniformly | ✅ No direct global/module access in any new module |

---

# Risks / Follow-ups

## Resolved by This Review
- **Issue #4 (circularity contradiction)**: Low risk — the resolution is already correct; only documentation needs updating.
- **Issue #3 (_G.command_once inconsistency)**: Medium-low risk — double-wrapping is harmless but confusing for implementers. Should be clarified before Phase 1 begins.

## Requires Design Team Action Before Implementation
- **Issue #1 (set_sub_handlers missing from API)**: Must be resolved to avoid ambiguity in how sub-module callbacks are registered with led_engine. This affects the composition root wiring and all Phase 1 modules.
- **Issue #2 (implicit dependencies in annunciator/switch modules)**: Must be resolved to ensure Worker specialists know exactly which functions/modules each module depends on. Failure to address could lead to runtime errors during implementation.

## Future Considerations (Post-FEAT-016)
- DSGN-003 Phase B (optional per-module export table lookups) is a good deferred optimization — consider implementing after FEAT-016 verification passes.
- The `bravo_hid` alias for the hardware module should be documented in DSGN-002's dependency graph to avoid confusion during implementation.

---

# Supporting Materials / Evidence

## Code References Verified Against Existing Codebase

| Reference | Location in Existing Code | Status |
|-----------|--------------------------|--------|
| `config.eval_condition` | `FlyWithLua/Modules/bravo++/config.lua:475` (exposed public function) | ✅ Exists — should be injected or required explicitly by annunciator_leds |
| `condition_compiler.eval_condition` | `FlyWithLua/Modules/bravo++/condition_compiler.lua:94` (public API) | ✅ Exists — recommended injection target for annunciator_leds |
| `hardware.poll()` | `FlyWithLua/Scripts/BravoMultiMode.lua:837` (`bravo_hid.poll()`) | ✅ Maps to hardware module's poll function |
| `_G.command_once` bypass pattern | `FlyWithLua/Modules/bravo++/dispatch_twist.lua:~60` (RAD-005 Finding 3) | ⚠️ Should be wrapped in try_catch per input_handlers spec |

## DSGN Document Metadata Verification
All three documents have correct YAML preambles with proper ID naming conventions (`DSGN-XXX`), version numbers, creation dates, and cross-references to related docs (FEAT-016, REQ-008, RAD-005). Status is set to `APPROVED` in each document's preamble — this should be changed to `DRAFT` pending resolution of the issues identified in this review.
