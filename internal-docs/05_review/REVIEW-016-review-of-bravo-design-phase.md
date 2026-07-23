---
id: REVIEW-016
title: Review of Bravo++ Design Phase (DSGN-001, DSGN-002, DSGN-003)
version: 1.0.0
status: APPROVED
created: 2026-07-23 20:08:00
updated: 2026-07-23 20:08:00
verdict: REQUEST_CHANGES
related_docs: ["DSGN-001", "DSGN-002", "DSGN-003", "FEAT-016", "REQ-008", "RAD-005"]
---

# Review of Bravo++ Design Phase — DSGN-001, DSGN-002, DSGN-003

## Executive Summary

This review covers the three design documents produced for **FEAT-016 (Bravo++ Modular Architecture Design)**:

| Document | ID | Title |
|----------|-----|-------|
| Module Interface Specification | DSGN-001 | Complete public API definitions for all 11 target modules |
| Dependency Mapping & Injection Strategy | DSGN-002 | Full dependency graph, circularity analysis, composition root wiring |
| FlyWithLua Callback Preservation Strategy | DSGN-003 | Bridge pattern design, global entrypoint preservation, transition plan |

**Overall Verdict: `REQUEST_CHANGES`** — The architectural blueprint is fundamentally sound and well-aligned with REQ-008 requirements and RAD-005 findings. However, three specific issues must be resolved before implementation begins: (1) a hidden dependency on `config.eval_condition()` in two modules that lacks injection specification, (2) an undocumented internal method (`set_sub_handlers`) used by led_engine but absent from its public API table, and (3) a missing dispatch callback entry for `toggle_profiler` referenced in DSGN-003. These are documentation gaps rather than fundamental design flaws; the architecture itself is correct.

**Key Takeaway:** The three documents form a coherent, technically sound blueprint that correctly addresses all RAD-005 findings and FlyWithLua integration constraints. With minor clarifications to injection parameters and callback tables, they will be fully implementation-ready.

---

## Review Scope

### In Scope
- **DSGN-001** — Module interface specifications for all 11 target modules (led_engine, led_hid_bridge, annunciator_leds, gear_leds, switch_leds, profiler, config_loader, rocker_switches, button_lifecycle, input_handlers, mode_manager)
- **DSGN-002** — Dependency mapping, circularity analysis, injection point catalogue, composition root wiring pseudocode
- **DSGN-003** — FlyWithLua callback bridge design, global entrypoint preservation, transition plan from forward declarations

### Reference Materials Reviewed
- `REQ-008` — Modular Architecture Revision and Lua Best Practices Analysis (originating requirement)
- `RAD-005` — Modular Architecture Analysis and Lua Best Practices (analysis report with 8 findings)
- `FEAT-016` — Feature Plan defining the modular architecture design scope
- `docs/lua-best-practices.md` — Project-specific Lua best practices guide

### Not In Scope
- Implementation code review (no refactored code exists yet)
- Performance benchmarking or quantitative profiling
- Non-Lua code modifications

---

## Review Criteria and Methodology

The review was conducted against five criteria:

1. **Technical Accuracy & Alignment** — Do the designs align with REQ-008 requirements and RAD-005 findings? Specifically, does the design address forward-declaration fragility (Finding 2), `_G.command_once` bypass (Finding 3), implicit global leakage (Finding 4), missing nil guards (Finding 5), and monolithic LED engine (Finding 1)?

2. **Completeness** — Are all 11 target modules covered? Is the dependency map comprehensive with circularity resolutions? Does the bridge design correctly address FlyWithLua's string-callback model and global environment constraints?

3. **Consistency** — Do the three documents work together without contradictions? Do injection parameters match across DSGN-001 API tables, DSGN-002 wiring pseudocode, and DSGN-003 dispatch_callbacks routing table?

4. **Adherence to Principles** — Does the design strictly follow "Injection Over Global Access"? Is `local M = {} ... return M` consistently specified for all modules?

5. **Implementation Readiness** — Are specifications detailed enough that a Worker specialist could implement them without further clarification?

---

## Findings Summary

### Critical Issues (Must Fix Before Implementation)

#### C1: Hidden Dependency on `config.eval_condition()` in annunciator_leds and switch_leds [MAJOR]

Both DSGN-001's internal/private function tables reference `config.eval_condition()` as the evaluation mechanism, but neither module lists `config` or an evaluator function as a dependency or injection parameter.

**Evidence from DSGN-001:**
- **annunciator_leds**, Internal/Private Functions table: *"Uses config.eval_condition() for comparison."*
- **switch_leds**, Internal/Private Functions table: *"Uses config.eval_condition() for comparison."*

**Current state in codebase:** `config.lua` exposes `eval_condition` as a global variable (`config.eval_condition = eval_condition`, line 475 of config.lua), not through the standard M export pattern. In modularized code, this creates an implicit dependency on FlyWithLua's shared global environment — directly contradicting the "Injection Over Global Access" principle that DSGN-002 and DSGN-003 both emphasize.

**Required fix:** Either:
1. Add `eval_fn` (or similar) as a required injection parameter in both modules' `M.init(opts)` signatures, passed from the composition root after loading config.lua; or
2. Explicitly list `config` module as an injected dependency and document that it must be accessed via injection rather than global lookup.

**Impact:** Without this fix, Worker specialists implementing these modules would either need to access globals (violating the design principle) or guess at how evaluation should work. This is a direct contradiction with DSGN-002's "Injection Over Global Access" mandate.

---

### Major Issues (Should Fix Before Implementation)

#### M1: Undocumented `set_sub_handlers()` Method in led_engine [MAJOR]

DSGN-001 defines the public API for led_engine but does **not** include a `M.set_sub_handlers()` method, yet DSGN-002's wiring pseudocode (Composition Root section) calls it explicitly:

```lua
-- From DSGN-002 wiring pseudocode:
led_engine.set_sub_handlers({
    on_annunciator_row1 = function() annunciator_leds.evaluate_row1(led_engine) end,
    on_annunciator_row2 = function() annunciator_leds.evaluate_row2(led_engine) end,
    on_gear = function() gear_leds.evaluate(led_engine) end,
    on_switches = function() switch_leds.evaluate(led_engine) end,
})
```

Additionally, DSGN-001's `M.handle_led_changes(opts)` is documented as receiving sub-handler callbacks via `{ on_button_leds, on_gear_leds, ... }` in its opts parameter — but this contradicts the separate `set_sub_handlers()` call shown in DSGN-002.

**Required fix:** Choose one approach and document it consistently across all three documents:
- **Option A (opts-based):** Add sub-handlers to `M.handle_led_changes(opts)` as a documented parameter, remove `set_sub_handlers()` from wiring pseudocode; or
- **Option B (separate init):** Add `M.set_sub_handlers(sub_handlers_table)` to led_engine's public API table in DSGN-001 and keep the separate call in DSGN-002.

**Impact:** Worker specialists would be confused about how sub-module callbacks are wired into led_engine, potentially leading to incorrect implementation or runtime errors.

#### M2: Missing `toggle_profiler` Dispatch Callback Entry [MAJOR]

DSGN-003 states that profiler toggle and log functions should be accessible via dispatch callbacks (`"bravo_dispatch('toggle_profiler')"` and `"bravo_dispatch('profiler_log_task')"`) but the `dispatch_callbacks` routing table in DSGN-003 does **not** include entries for either of these.

**Evidence from DSGN-003:**
> *"Note: profiler_toggle() and profiler_log_task() are also global but belong to the profiler module. After extraction, they become: profiler.toggle() — called via "bravo_dispatch('toggle_profiler')" ... These remain as dispatch callbacks rather than globals because they are invoked through bravo_dispatch strings."*

But no `dispatch_callbacks.toggle_profiler` or `dispatch_callbacks.profiler_log_task` entry exists in the routing table.

**Required fix:** Add these two entries to DSGN-003's dispatch_callbacks table:
```lua
dispatch_callbacks.toggle_profiler = function()
    profiler.toggle()
end

dispatch_callbacks.profiler_log_task = function()
    profiler.log_and_reset()
end
```

**Impact:** Without these entries, the FlyWithLua string callbacks `"bravo_dispatch('toggle_profiler')"` and `"bravo_dispatch('profiler_log_task')"` would resolve to nil in dispatch_callbacks, causing silent failures with no error logging (since bravo_dispatch only logs when a target is missing).

#### M3: `_G.command_once` Wrapping Inconsistency Between DSGN-001 and DSGN-003 [MAJOR]

DSGN-001 specifies that input_handlers should resolve RAD-005 Finding 3 by wrapping all command invocations in try_catch/pcall:
> *"Fixed version — wraps _G.command_once calls in pcall/try_catch to prevent silent failures (RAD-005 Finding 3)."*

However, DSGN-003's dispatch_callbacks routing table for trim handlers still shows direct `_G.command_once` access without any wrapper:
```lua
dispatch_callbacks.trim_nose_up = function()
    pcall(function() _G.command_once(trim_dataref_up) end)
end
```

This is a partial fix (pcall present but no try_catch logging), and more importantly, it references `trim_dataref_up` as if it were a global variable — contradicting the injection principle. The datarefs should be injected or resolved through dispatch module lookups.

**Required fix:**
1. Ensure trim knob datarefs are injected into input_handlers (or accessed via dispatch module), not referenced as globals;
2. Use try_catch wrapper with proper error logging instead of bare pcall, consistent with the bravo_dispatch pattern;
3. Document that this is a transitional approach and the final implementation should route through dispatch rather than direct _G access.

**Impact:** The `_G.command_once` bypass (RAD-005 Finding 3) would not be fully resolved in the trim handlers, leaving a silent failure path in production.

---

### Minor Issues (Recommended for Improvement)

#### I1: `bravo_hid` Reference Ambiguity in DSGN-002 [MINOR]

DSGN-002's wiring pseudocode references `bravo_hid.poll()` and `bravo_hid.subscribe()`, but the dependency graph lists only `hardware.lua` (not `bravo_hid`). In BravoMultiMode.lua, `local bravo_hid = require("bravo++.hardware")` — so `bravo_hid` is a local alias for the hardware module.

**Recommendation:** Clarify in DSGN-002 that `bravo_hid` is an alias for the `hardware` module (not a separate module), and document this naming convention to avoid confusion during implementation.

#### I2: Profiler Global Entry Point Documentation [MINOR]

DSGN-003 states exactly three functions must remain global (`bravo_dispatch`, `build_bravo_gui`, `on_close_floating_window`), but then discusses profiler toggle/log as also being globals before clarifying they route through bravo_dispatch. This creates momentary confusion about whether profiler functions are truly global or dispatch-routed.

**Recommendation:** Clarify in DSGN-003 that profiler functions are **not** globals — they are invoked exclusively through `bravo_dispatch` string callbacks, consistent with the three-globals principle. Remove any language suggesting otherwise.

#### I3: Missing Performance Considerations from lua-best-practices.md [MINOR]

The project's `docs/lua-best-practices.md` emphasizes several patterns relevant to these designs but not explicitly addressed in the DSGN documents:
- **Pre-compute values at module load time** (DAG hierarchy supports this, but should be documented)
- **Avoid allocations in hot paths** — led_engine.handle_led_changes() runs every 0.25s; design should note that sub-handler callbacks must not allocate new tables per invocation
- **Debounce patterns for physical inputs** — relevant to rocker_switches and input_handlers modules

**Recommendation:** Add a "Performance Constraints" subsection to DSGN-001's module specifications, noting hot-path considerations for each module. Reference `docs/lua-best-practices.md` explicitly in the design documents' preamble.

#### I4: `get_led_state_for_dataref()` Origin Unclear [MINOR]

DSGN-001 references `get_led_state_for_dataref()` as a pattern used by annunciator_leds and switch_leds, but this function currently exists only as a local in BravoMultiMode.lua (line 1187). The design documents don't specify where this function should live after modularization — likely in config_loader or condition_compiler.

**Recommendation:** Add `get_led_state_for_dataref` to the dependency injection catalogue, specifying which module provides it and how it's injected into annunciator_leds/switch_leds.

---

## Positive Findings

### P1: Excellent RAD-005 Finding Coverage [EXCELLENT]
All seven relevant RAD-005 findings are explicitly addressed in the design documents with a clear mapping table in DSGN-001:

| RAD-005 Finding | Severity | Design Resolution | Document |
|-----------------|----------|-------------------|----------|
| Finding 1: LED engine monolithic block | CRITICAL | Split into 5 focused modules | DSGN-001, DSGN-002 |
| Finding 2: Forward declaration fragility | HIGH | `M.init(opts)` injection pattern eliminates forward declarations | All three documents |
| Finding 3: `_G.command_once` bypass | HIGH | try_catch/pcall wrappers in input_handlers | DSGN-001, DSGN-003 |
| Finding 4: Implicit global leakage | MEDIUM | Closure-scoped state via init() parameters | All three documents |
| Finding 5: Missing nil guards in hot paths | MEDIUM | Defensive nil checks documented for all dataref access | DSGN-001 |
| Finding 7: Inconsistent export patterns | MEDIUM | Standard `local M = {} ... return M` across all 11 modules | All three documents |

### P2: Circular Dependency Analysis Is Thorough [EXCELLENT]
DSGN-002 identifies four potential circularities (led_engine↔dispatch, switch_leds↔dispatch, mode_manager↔led_engine, input_handlers↔dispatch_twist) and provides specific resolution strategies for each. The acyclic DAG hierarchy with 5 levels is well-reasoned and verifiable through static analysis.

### P3: FlyWithLua Bridge Design Is Correct [EXCELLENT]
DSGN-003 correctly identifies that exactly three functions must remain global due to FlyWithLua's string-callback execution model, preserves `bravo_dispatch` as the central hub (never eliminating it), and provides a clear two-phase transition plan. The bridge pattern diagram accurately represents the data flow from FlyWithLua host → bravo_dispatch → dispatch_callbacks → module methods.

### P4: Injection Over Global Access Principle Is Consistently Applied [EXCELLENT]
Every new module's dependency table explicitly lists injection parameters, and no module is specified to access FlyWithLua globals directly (except through the documented bridge pattern). The composition root wiring pseudocode in DSGN-002 demonstrates correct parameter passing for all 11 modules.

### P5: Implementation Readiness Is High [GOOD]
The combination of detailed API tables (DSGN-001), wiring pseudocode (DSGn-002), and callback routing table (DSGN-003) provides Worker specialists with a complete picture of what to implement, how modules connect, and how FlyWithLua callbacks route. The phased extraction roadmap from FEAT-016 maps cleanly onto these documents.

---

## Verification Results

### Cross-Document Consistency Checks Performed
| Check | Result | Notes |
|-------|--------|-------|
| All 11 modules present in DSGN-001 | ✓ PASS | led_engine, led_hid_bridge, annunciator_leds, gear_leds, switch_leds, profiler, config_loader, rocker_switches, button_lifecycle, input_handlers, mode_manager |
| Injection params match between DSGN-001 API tables and DSGN-002 wiring pseudocode | ✓ PASS (with noted exceptions) | C1 (eval_condition), M1 (set_sub_handlers) are inconsistencies |
| dispatch_callbacks in DSGN-003 route to correct module methods per DSGN-001 APIs | ⚠ PARTIAL | Missing toggle_profiler and profiler_log_task entries (M2) |
| No FlyWithLua global access specified for new modules | ✓ PASS | All globals accessed through bridge pattern only |
| `local M = {} ... return M` used consistently across all 11 modules | ✓ PASS | Every module spec shows this export pattern |

### Alignment with lua-best-practices.md Checks Performed
| Best Practice | Status | Notes |
|--------------|--------|-------|
| Module organization (SRP, `local M = {}`) | ✓ COMPLIANT | All 11 modules follow SRP and export pattern |
| Scoping & visibility (prefer local) | ✓ COMPLIANT | Closure-scoped state via init() parameters |
| Error handling (pcall/try_catch) | ⚠ PARTIAL | input_handlers has pcall but missing try_catch logging (M3) |
| LED/HID communication (buffer→evaluate→send) | ✓ COMPLIANT | led_engine → sub-modules → led_hid_bridge pattern correct |
| DataRef interaction (nil guards, magic tables) | ✓ COMPLIANT | Nil guards documented for all dataref access |
| Performance (minimize allocations in hot paths) | ⚠ NOT ADDRESSED | Should be explicitly noted as constraint (I3) |

### Alignment with REQ-008 Checks Performed
| REQ-008 Requirement | Status | Notes |
|---------------------|--------|-------|
| Module interface spec for all 11 targets | ✓ COMPLIANT | DSGN-001 covers all modules with full API tables |
| Dependency mapping with circularity resolution | ✓ COMPLIANT | DSGN-002 provides complete graph + DAG hierarchy |
| FlyWithLua bridge design preserving globals | ✓ COMPLIANT | DSGN-003 correctly identifies 3 global entrypoints |
| Phased extraction roadmap | ✓ COMPLIANT | FEAT-016 phases map to DSGN documents |

---

## Risks / Follow-ups

### Residual Risks After Changes Are Made

| Risk | Severity | Mitigation |
|------|----------|------------|
| **Hidden eval_condition dependency** (C1) could cause runtime errors if not injected properly | HIGH | Composition root must pass evaluator function during module init; add validation in M.init() to reject nil evaluators |
| **Sub-handler wiring confusion** (M1) could lead to incorrect callback registration | MEDIUM | Choose one approach (opts vs separate method) and document it as the canonical pattern for all inter-module callbacks |
| **Missing profiler dispatch entries** (M2) would cause silent failures on toggle/log commands | HIGH | Add entries before Phase 2 implementation begins; add integration test exercising both callbacks |
| **_G.command_once bypass not fully resolved** (M3) could still silently fail in production | MEDIUM | Ensure input_handlers receives trim datarefs via injection and uses try_catch with logging, matching bravo_dispatch pattern |

### Follow-up Work After Design Changes
1. Run `python3 toolbox/validate_docs.py` after updating DSGN-001 and DSGN-003 to verify YAML preamble consistency and cross-reference integrity.
2. Add a "Performance Constraints" section to each module's specification in DSGN-001, referencing `docs/lua-best-practices.md`.
3. Consider adding a companion `.notes.md` file with line-by-line mapping from BravoMultiMode.lua source lines to new module functions (similar to RAD-005-NOTES).

---

## Final Verdict: REQUEST_CHANGES

The three design documents for FEAT-016 form a **technically sound and well-structured architectural blueprint** that correctly addresses all major findings from RAD-005, adheres to the "Injection Over Global Access" principle, and provides clear guidance for Worker specialists. The FlyWithLua bridge pattern is correct, the dependency analysis is thorough, and the module interface specifications are detailed.

However, **three critical/major issues** must be resolved before implementation can begin:
1. **C1:** Hidden `config.eval_condition()` dependency in annunciator_leds and switch_leds — violates injection principle
2. **M1:** Undocumented `set_sub_handlers()` method in led_engine — creates ambiguity in wiring approach
3. **M2:** Missing `toggle_profiler` dispatch callback entry — would cause silent runtime failures

These are **documentation gaps** rather than fundamental design flaws. The underlying architecture is correct, and the fixes are straightforward additions to the existing specifications. Once these issues are resolved, this review will be upgraded to **APPROVED**.

---

*Review conducted by: system-reviewer (Worker specialist)*
*Date: 2026-07-23*
*Branch: feat/task-0014-implement-bravo-modular-architecture-design*
