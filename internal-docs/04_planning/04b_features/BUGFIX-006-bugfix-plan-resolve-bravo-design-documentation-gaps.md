---
id: BUGFIX-006
title: Bugfix Plan: Resolve Bravo++ Design Documentation Gaps
version: 1.0.0
status: DRAFT
created: 2026-07-23 20:15:00
updated: 2026-07-23 20:15:00
related_docs: ["REVIEW-016", "DSGN-001", "DSGN-002", "DSGN-003"]
priority: HIGH
---

# Bugfix Plan: Resolve Bravo++ Design Documentation Gaps

## Overview

This BUGFIX plan addresses all issues identified in **REVIEW-016** (Review of Bravo++ Design Phase) across the three design documents. The review verdict was `REQUEST_CHANGES` due to 4 critical/major documentation gaps that must be resolved before implementation can begin, plus 4 minor improvement recommendations.

## Issue Summary Table

| ID | Severity | Description | Target File(s) |
|----|----------|-------------|----------------|
| **C1** | CRITICAL | Hidden `config.eval_condition()` dependency in annunciator_leds and switch_leds | DSGN-001, DSGN-002 |
| **M1** | MAJOR | Undocumented `set_sub_handlers()` method in led_engine | DSGN-001, DSGN-002 |
| **M2** | MAJOR | Missing `toggle_profiler` dispatch callback entry | DSGN-003 |
| **M3** | MAJOR | `_G.command_once` wrapping inconsistency between DSGN-001 and DSGN-003 | DSGN-001, DSGN-003 |
| I1 | MINOR | `bravo_hid` reference ambiguity in DSGN-002 | DSGN-002 |
| I2 | MINOR | Profiler global entry point documentation confusion | DSGN-003 |
| I3 | MINOR | Missing performance considerations from lua-best-practices.md | DSGN-001 |
| I4 | MINOR | `get_led_state_for_dataref()` origin unclear | DSGN-001, DSGN-002 |

---

## C1: Hidden Dependency on `config.eval_condition()` — CRITICAL

**Problem**: Both `annunciator_leds` and `switch_leds` modules reference `config.eval_condition()` in their internal/private function descriptions, but neither module lists `config` or an evaluator function as a dependency or injection parameter. This violates the "Injection Over Global Access" principle that DSGN-002 and DSGN-003 both emphasize.

### Target File: DSGN-001 (Module Interface Specification)

#### Change 1a — `annunciator_leds` Module

**Location**: Module 3 (`annunciator_leds`) section, **Injection Points table**, add new row:

```markdown
| Dependency | Type | Source | Notes |
|-----------|------|--------|-------|
| annunciator_bindings | table of { dataref_table, condition_string } | Config loader (compiled) | Each entry maps an annunciator label to its X-Plane dataref and compiled condition string. Pre-compiled conditions avoid runtime parsing overhead in hot path. |
| led_engine_module.set_led | function reference | led_engine module injected at init time | Used to write evaluated states into the shared buffer. The actual dirty-flag logic lives in led_engine, keeping this module focused on evaluation only. |
+ eval_fn (NEW) | function `(dataref_table, condition_string, index?) → boolean` | Composition root — passed from config_loader after loading config.lua | Evaluator function for comparing dataref values against compiled conditions. Replaces direct `config.eval_condition()` global access. Must be non-nil at init time; reject nil with error log. |
```

**Location**: Module 3 (`annunciator_leds`) section, **Internal/Private Functions table**, update the `evaluate_single_annunciator` row:

```markdown
| Function | Purpose |
|----------|---------|
| evaluate_single_annunciator(label) | Evaluates a single annunciator's dataref against its compiled condition. Returns boolean. Handles both scalar and array datarefs with proper nil guards. Uses injected `eval_fn` for comparison (NOT direct config global access). |
```

#### Change 1b — `switch_leds` Module

**Location**: Module 5 (`switch_leds`) section, **Injection Points table**, add new row:

```markdown
| Dependency | Type | Source | Notes |
|-----------|------|--------|-------|
| switch_bindings | table of { dataref_table, condition_string, optional_index } | Config loader (compiled) | Pre-compiled bindings for all 7 rocker switches. Each entry may include an optional array index (3rd element). |
| dispatch_module | table (module) | dispatch.lua module injected at init time | Required for: `get_rocker_switch_led(key)` to read current state, `set_rocker_switch_led(key, state)` to update it. |
+ eval_fn (NEW) | function `(dataref_table, condition_string, index?) → boolean` | Composition root — passed from config_loader after loading config.lua | Evaluator function for comparing dataref values against compiled conditions. Replaces direct `config.eval_condition()` global access. Must be non-nil at init time; reject nil with error log. |
| led_engine_module.set_led | function reference | led_engine module | Used to write evaluated switch states into the shared buffer. |
```

**Location**: Module 5 (`switch_leds`) section, **Internal/Private Functions table**, update the `evaluate_switch` row:

```markdown
| Function | Purpose |
|----------|---------|
| evaluate_switch(switch_label, binding) | Evaluates a single switch's dataref against its compiled condition. Handles nil guards on dataref access. Returns boolean state. Uses injected `eval_fn` for comparison (NOT direct config global access). |
```

### Target File: DSGN-002 (Dependency Mapping & Injection Strategy)

#### Change 2a — Wiring Pseudocode, Phase 1 Initialization Section

**Location**: Composition Root Wiring Pseudocode section, find the `annunciator_leds.init({...})` block and add `eval_fn`:

```lua
-- BEFORE:
annunciator_leds.init({
    annunciator_bindings = build_annunciator_bindings(nav_bindings),
})

-- AFTER (add eval_fn):
annunciator_leds.init({
    annunciator_bindings = build_annunciator_bindings(nav_bindings),
    eval_fn = config.eval_condition,  -- injected evaluator from config module
})
```

**Location**: Same section, find the `switch_leds.init({...})` block and add `eval_fn`:

```lua
-- BEFORE:
switch_leds.init({
    switch_bindings = build_switch_bindings(nav_bindings),
    dispatch_module = dispatch,
})

-- AFTER (add eval_fn):
switch_leds.init({
    switch_bindings = build_switch_bindings(nav_bindings),
    dispatch_module = dispatch,
    eval_fn = config.eval_condition,  -- injected evaluator from config module
})
```

#### Change 2b — Injection Parameter Summary Table

**Location**: "Injection Parameter Summary Table" section, update the `annunciator_leds` row:

| Module | Required Injection Parameters | Optional Injection Parameters | Default Values |
|--------|------------------------------|-------------------------------|----------------|
| `annunciator_leds` | annunciator_bindings, **eval_fn** | *(none)* | Error if bindings empty or eval_fn is nil |

Update the `switch_leds` row:

| Module | Required Injection Parameters | Optional Injection Parameters | Default Values |
|--------|------------------------------|-------------------------------|----------------|
| `switch_leds` | switch_bindings, dispatch_module, **eval_fn** | *(none)* | No-op for switches without bindings; error if eval_fn is nil |

#### Change 2c — Runtime Dependency Graph (Optional Clarification)

Add a note near the annunciator_leds and switch_leds entries in the "New Module Dependency Graph" table under Phase 1:

```markdown
| `annunciator_leds` | *(none)* | annunciator_bindings, **eval_fn**, led_engine.set_led callback | None — receives pre-compiled dataref bindings; evaluator injected via parameter |
| `switch_leds` | *(none)* | switch_bindings, dispatch_module, **eval_fn**, led_engine.set_led callback | None — all datarefs pre-resolved by config loader; evaluator injected via parameter |
```

---

## M1: Undocumented `set_sub_handlers()` Method in led_engine — MAJOR

**Problem**: DSGN-001 defines the public API for led_engine but does **not** include a `M.set_sub_handlers()` method, yet DSGN-002's wiring pseudocode calls it explicitly. Additionally, DSGN-001's `handle_led_changes(opts)` documentation mentions receiving sub-handler callbacks via opts — contradicting the separate `set_sub_handlers()` call in DSGN-002.

### Resolution: Adopt Option B (Separate init method)

This approach is cleaner and more explicit. It keeps sub-handler registration as a distinct operation from the main update loop, matching the wiring pseudocode already present in DSGN-002.

### Target File: DSGN-001 (Module Interface Specification)

#### Change 3a — Add `set_sub_handlers` to led_engine Public API

**Location**: Module 1 (`led_engine`) section, **Public API table**, insert a new row after the existing entries (before `M.get_bus_voltage()`):

```markdown
| Function | Parameters | Return Type | Side Effects |
|----------|-----------|-------------|--------------|
+ M.set_sub_handlers(sub_handlers_table) | `{ on_annunciator_row1: function, on_annunciator_row2: function, on_gear: function, on_switches: function }` — each is a zero-arg callback that evaluates its sub-module and writes to led_engine buffer | `nil` | Stores the provided sub-handler callbacks in closure scope. These are invoked by `handle_led_changes()` during orchestration instead of being passed per-call via opts. Must be called after `M.init(opts)` but before any update loop iteration. Validates that all four callback keys are present; logs error if any key is missing. |
```

#### Change 3b — Update `handle_led_changes` Documentation

**Location**: Module 1 (`led_engine`) section, **Public API table**, modify the existing `M.handle_led_changes(opts)` row:

```markdown
| Function | Parameters | Return Type | Side Effects |
|----------|-----------|-------------|--------------|
- M.handle_led_changes(opts) | `{ bus_voltage: number, master_state_ref: table }` | `boolean` (whether any LEDs were updated) | **Main orchestration function.** Evaluates all LED sub-systems in order: button LEDs → gear LEDs → annunciator row 1 → annunciator row 2 → rocker switch LEDs. Checks bus voltage; if zero and previously powered, calls `all_off()`. Returns true if dirty flag was set during evaluation (indicating HID update needed). Calls into injected sub-module handlers via callbacks passed in opts: `{ on_button_leds, on_gear_leds, on_annunciator_row1, on_annunciator_row2, on_switch_leds }`. Uses `try_catch` wrapper for each sub-handler. |
+ M.handle_led_changes(opts) | `{ bus_voltage: number, master_state_ref: table }` | `boolean` (whether any LEDs were updated) | **Main orchestration function.** Evaluates all LED sub-systems in order: button LEDs → gear LEDs → annunciator row 1 → annunciator row 2 → rocker switch LEDs. Checks bus voltage; if zero and previously powered, calls `all_off()`. Returns true if dirty flag was set during evaluation (indicating HID update needed). Calls into pre-registered sub-handler callbacks (set via `M.set_sub_handlers()` in composition root) using stored closure references. Uses `try_catch` wrapper for each sub-handler. Sub-handlers are NOT passed per-call — they are registered once at init time and invoked from closure scope. |
```

### Target File: DSGN-002 (Dependency Mapping & Injection Strategy)

#### Change 4a — Wiring Pseudocode, led_engine Initialization Section

**Location**: Composition Root Wiring Pseudocode section, the `led_engine` initialization block already has the correct structure for Option B. No changes needed to the wiring pseudocode itself since it already calls:

```lua
-- This is already correct and matches the new API in DSGN-001:
led_engine.set_sub_handlers({
    on_annunciator_row1 = function() annunciator_leds.evaluate_row1(led_engine) end,
    on_annunciator_row2 = function() annunciator_leds.evaluate_row2(led_engine) end,
    on_gear = function() gear_leds.evaluate(led_engine) end,
    on_switches = function() switch_leds.evaluate(led_engine) end,
})
```

#### Change 4b — Add Note to Injection Parameter Summary Table

**Location**: "Injection Parameter Summary Table" section, update the `led_engine` row:

| Module | Required Injection Parameters | Optional Injection Parameters | Default Values |
|--------|------------------------------|-------------------------------|----------------|
- `led_engine` | dispatch, button_map_leds_state, default_button_labels | bus_voltage_ref | nil (bus voltage defaults to 0) |
+ `led_engine` | dispatch, button_map_leds_state, default_button_labels | bus_voltage_ref, sub_handlers (via separate set_sub_handlers call) | nil (bus voltage defaults to 0); sub-handlers registered separately via M.set_sub_handlers() after init |

---

## M2: Missing `toggle_profiler` Dispatch Callback Entry — MAJOR

**Problem**: DSGN-003 states that profiler toggle and log functions should be accessible via dispatch callbacks (`"bravo_dispatch('toggle_profiler')"` and `"bravo_dispatch('profiler_log_task')"`) but the `dispatch_callbacks` routing table does **not** include entries for either of these. Without these entries, the FlyWithLua string callbacks would resolve to nil in dispatch_callbacks, causing silent failures.

### Target File: DSGN-003 (FlyWithLua Callback Preservation Strategy)

#### Change 5a — Add Profiler Entries to dispatch_callbacks Routing Table

**Location**: The `dispatch_callbacks` routing table section (after the existing entries and before or after "Input Handler callbacks"), add these two new blocks:

```lua
-- Profiler callbacks
dispatch_callbacks.toggle_profiler = function()
    profiler.toggle()
end

dispatch_callbacks.profiler_log_task = function()
    profiler.log_and_reset()
end
```

**Placement**: Insert these entries in the routing table after `set_current_buttons_task` and before or alongside other task-based callbacks. The exact insertion point should be visually grouped with "Profiling" as a comment header:

```lua
-- Profiler callbacks (invoked via bravo_dispatch strings)
dispatch_callbacks.toggle_profiler = function()
    profiler.toggle()
end

dispatch_callbacks.profiler_log_task = function()
    profiler.log_and_reset()
end
```

#### Change 5b — Update Global Entry Points Note Section

**Location**: The "Global Entry Points — Minimal Set" section, modify the note paragraph:

```markdown
- BEFORE (remove):
> **Note**: `profiler_toggle()` and `profiler_log_task()` are also global but belong to the profiler module. After extraction, they become:
> - `profiler.toggle()` — called via `"bravo_dispatch('toggle_profiler')"`
> - `profiler.log_and_reset()` — called via `"bravo_dispatch('profiler_log_task')"`
> These remain as dispatch callbacks rather than globals because they are invoked through bravo_dispatch strings.

- AFTER (replace with):
> **Note**: The profiler module's `toggle()` and `log_and_reset()` functions are NOT global entry points. They are invoked exclusively through `bravo_dispatch` string callbacks (`"bravo_dispatch('toggle_profiler')"` and `"bravo_dispatch('profiler_log_task')"`) which route to the dispatch_callbacks table entries defined above. This is consistent with the three-globals principle — only `bravo_dispatch`, `build_bravo_gui`, and `on_close_floating_window` are global entry points.
```

---

## M3: `_G.command_once` Wrapping Inconsistency — MAJOR

**Problem**: DSGN-001 specifies that input_handlers should resolve RAD-005 Finding 3 by wrapping all command invocations in try_catch/pcall, but DSGN-003's dispatch_callbacks routing table for trim handlers still shows direct `_G.command_once` access without proper wrapper. Additionally, `trim_dataref_up` and `trim_dataref_down` are referenced as if they were global variables — contradicting the injection principle.

### Target File: DSGN-001 (Module Interface Specification)

#### Change 6a — Update input_handlers Module Documentation

**Location**: Module 10 (`input_handlers`) section, **Public API table**, modify `M.handle_twist(dir)` row:

```markdown
| Function | Parameters | Return Type | Side Effects |
|----------|-----------|-------------|--------------|
- M.handle_twist(dir) | `dir: string ("increase"\|"decrease")` | `nil` | **Fixed version** — wraps `_G.command_once` calls in pcall/try_catch to prevent silent failures (RAD-005 Finding 3). Routes twist knob increase/decrease through dispatch module's priority resolution logic. |
+ M.handle_twist(dir) | `dir: string ("increase"\|"decrease")` | `nil` | **Fixed version** — routes twist knob commands through the injected dispatch module (not direct `_G.command_once`). The dispatch module resolves trim/twist datarefs via injection rather than global access. All command invocations are wrapped in try_catch with error logging per RAD-005 Finding 3. This fully resolves the bypass anti-pattern by eliminating any direct _G reference. |
```

**Location**: Module 10 (`input_handlers`) section, **Injection Points table**, add trim dataref injection:

```markdown
| Dependency | Type | Source | Notes |
|-----------|------|--------|-------|
| dispatch_module | table (module) | dispatch.lua module | Required for: `trim_nose_up()`, `trim_nose_down()`, and all twist knob command resolution. Provides the centralized error handling via try_catch. |
+ trim_datarefs (NEW) | `{ up: dataref, down: dataref }` or function reference | Composition root — injected from config loader bindings | Trim wheel direction datarefs for direct access when dispatch module does not provide twist resolution. Used as fallback if dispatch_module.trim_nose_up/down are unavailable. Must be non-nil; reject nil with error log. |
| decoder_handler_fn | function `(event_type, value)` → any | Composition root — decoder's event routing callback | Used to wire up decoder pub/sub events to input handlers without circular dependency. |
```

**Location**: Module 10 (`input_handlers`) section, **Internal/Private Functions table**, update `_handle_twist_command`:

```markdown
| Function | Purpose |
|----------|---------|
- _handle_twist_command(command_name) | **Fixed version** of the original _G.command_once call. Wraps in pcall with try_catch error logging per RAD-005 Finding 3. Previously bypassed safety net; now properly logged on failure. |
+ _handle_twist_command(dataref_value) | Routes twist knob command through dispatch module's priority resolution logic using injected trim datarefs (not globals). Wraps in try_catch with proper error logging per RAD-005 Finding 3. The original `_G.command_once` bypass is fully eliminated — all command execution flows through the injection layer or dispatch facade. |
```

### Target File: DSGN-003 (FlyWithLua Callback Preservation Strategy)

#### Change 7a — Update trim handler entries in dispatch_callbacks

**Location**: The `dispatch_callbacks` routing table, find and replace the existing trim handler blocks:

```lua
-- BEFORE (remove these two blocks):
dispatch_callbacks.trim_nose_up = function()
    pcall(function() _G.command_once(trim_dataref_up) end)
end

dispatch_callbacks.trim_nose_down = function()
    pcall(function() _G.command_once(trim_dataref_down) end)
end

-- AFTER (replace with):
dispatch_callbacks.trim_nose_up = function()
    try_catch(function()
        dispatch.trim_nose_up()  -- routed through dispatch module; datarefs injected at composition root
    end, "trim_nose_up")
end

dispatch_callbacks.trim_nose_down = function()
    try_catch(function()
        dispatch.trim_nose_down()  -- routed through dispatch module; datarefs injected at composition root
    end, "trim_nose_down")
end
```

#### Change 7b — Add Clarifying Comment to trim handlers section

After the replacement entries above, add a comment block:

```lua
-- NOTE: These handlers no longer reference _G.command_once or global datarefs.
-- Trim knob commands are routed through the dispatch module's priority resolution logic.
-- The actual trim dataref values (trim_dataref_up/down) are injected into input_handlers
-- at composition root time, not accessed as globals. This fully resolves RAD-005 Finding 3.
```

---

## I1: `bravo_hid` Reference Ambiguity in DSGN-002 — MINOR

**Problem**: DSGN-002's wiring pseudocode references `bravo_hid.poll()` and `bravo_hid.subscribe()`, but the dependency graph lists only `hardware.lua` (not `bravo_hid`). In BravoMultiMode.lua, `local bravo_hid = require("bravo++.hardware")` — so `bravo_hid` is a local alias for the hardware module.

### Target File: DSGN-002 (Dependency Mapping & Injection Strategy)

#### Change 8a — Add Naming Convention Note

**Location**: In the "New Module Dependency Graph" section under Phase 3 modules, or in the wiring pseudocode area near where `bravo_hid` is referenced. Insert a clarifying note:

```markdown
> **Naming Convention Note**: The variable name `bravo_hid` used throughout this document's wiring pseudocode is an alias for the `hardware` module (`require("bravo++.hardware")`). It is NOT a separate module. This naming convention matches the existing BravoMultiMode.lua pattern where `local bravo_hid = require("bravo++.hardware")`. When implementing, use either name consistently — prefer `bravo_hid` in the main script scope for readability, but reference the actual module as `bravo++.hardware` in dependency documentation.
```

#### Change 8b — Update dispatch_callbacks entry (DSGN-003 cross-reference)

**Location**: DSGN-002's wiring pseudocode section, find the line referencing `bravo_hid.poll()`:

```lua
-- BEFORE:
dispatch_callbacks.bravo_hid_poll_task = function()
    bravo_hid.poll()
end

-- AFTER (add comment):
dispatch_callbacks.bravo_hid_poll_task = function()
    -- bravo_hid is an alias for bravo++.hardware module, not a separate module
    hardware.poll()  -- or bravo_hid.poll() — both refer to the same require("bravo++.hardware") instance
end
```

---

## I2: Profiler Global Entry Point Documentation — MINOR

**Problem**: DSGN-003 states exactly three functions must remain global, but then discusses profiler toggle/log as also being globals before clarifying they route through bravo_dispatch. This creates momentary confusion about whether profiler functions are truly global or dispatch-routed.

### Target File: DSGN-003 (FlyWithLua Callback Preservation Strategy)

#### Change 9a — Update the "Global Entry Points" section

**Location**: The "Global Entry Points — Minimal Set" table and surrounding text, add an explicit clarification after the three-entry table:

```markdown
### Global Entry Points — Minimal Set

After refactoring, exactly **three** functions must remain global:

| Function | Type | Purpose | Forwarding Target |
|----------|------|---------|-------------------|
| `bravo_dispatch` | function | Central routing hub for all FlyWithLua string callbacks | dispatch_callbacks[name] |
| `build_bravo_gui` | function | Floating window ImGui builder callback (receives wnd, x, y) | bravo_dispatch("build_bravo_gui", ...) |
| `on_close_floating_window` | function | Window close handler (receives wnd handle) | bravo_dispatch("on_close_floating_window", ...) |

> **Clarification**: The profiler module's functions (`profiler.toggle()` and `profiler.log_and_reset()`) are **NOT** global entry points. They are invoked exclusively through the dispatch system via `"bravo_dispatch('toggle_profiler')"` and `"bravo_dispatch('profiler_log_task')"`. Any prior language suggesting these were globals was imprecise — they route entirely through bravo_dispatch callbacks, consistent with the three-globals principle described above.
```

---

## I3: Missing Performance Considerations from lua-best-practices.md — MINOR

**Problem**: The project's `docs/lua-best-practices.md` emphasizes patterns relevant to these designs but not explicitly addressed in the DSGN documents, including pre-computation at module load time, avoiding allocations in hot paths, and debounce patterns for physical inputs.

### Target File: DSGN-001 (Module Interface Specification)

#### Change 10a — Add Performance Constraints Subsection to Each Module

**Location**: After each module's "Injection Points" section and before the "Internal/Private Functions" table, add a new subsection called **Performance Constraints**:

For **all 11 modules**, insert this standard template (adapted per-module where noted):

```markdown
### Performance Constraints

> All performance guidance is sourced from `docs/lua-best-practices.md`. Modules MUST adhere to these constraints during implementation.

- **Hot Path**: This module's primary evaluation function runs every 0.25s as part of the LED update loop (or equivalent periodic interval). Sub-handler callbacks invoked by this module must NOT allocate new tables per invocation — reuse pre-allocated buffers where possible.
- **Pre-computation**: All dataref bindings and condition strings are compiled at init time by config_loader, avoiding runtime parsing overhead in hot paths.
- **Allocation Budget**: Each evaluation cycle should perform zero heap allocations beyond the dirty-flag boolean return value.

---
```

**Module-specific additions**:

For `led_engine` (the primary hot path):
> - The main orchestration function (`handle_led_changes`) runs every 0.25s. All sub-handler callbacks must be pre-registered via `set_sub_handlers()` and invoked from closure scope — no table allocation per call.

For `rocker_switches`:
> - Physical input debounce: Command registration should not create duplicate commands on re-initialization. Guard against multiple `create_command` calls for the same command name.

For `input_handlers`:
> - Trim/twist handlers are triggered by physical rotary encoders which may generate rapid events. Consider debouncing at the decoder/pub-sub layer rather than in this module (the injected `decoder_handler_fn` should handle rate limiting).

#### Change 10b — Add Reference to lua-best-practices.md in Document Preamble

**Location**: DSGN-001's Overview section, add a reference after the existing principle statement:

```markdown
All new modules receive their dependencies via injection parameters rather than accessing FlyWithLua globals directly — adhering to the "Injection Over Global Access" principle defined in FEAT-016. Performance constraints from `docs/lua-best-practices.md` are noted per-module and must be followed during implementation.
```

---

## I4: `get_led_state_for_dataref()` Origin Unclear — MINOR

**Problem**: DSGN-001 references `get_led_state_for_dataref()` as a pattern used by annunciator_leds and switch_leds, but this function currently exists only as a local in BravoMultiMode.lua (line 1187). The design documents don't specify where this function should live after modularization.

### Target File: DSGN-001 (Module Interface Specification)

#### Change 11a — Add `get_led_state_for_dataref` to Dependency Injection Catalogue

**Location**: After Module 5 (`switch_leds`) section, add a new subsection called **Shared Utility Functions** or insert into the existing "Cross-Module Data Flow Summary" section:

```markdown
## Shared Utility Functions

The following function is extracted from BravoMultiMode.lua (line ~1187) and provided as an injected utility to modules that need dataref state evaluation:

### `get_led_state_for_dataref(dataref, condition_string, index?)`

| Property | Value |
|----------|-------|
| **Provider** | config_loader module or a dedicated `condition_compiler` utility (to be determined during implementation) |
| **Consumers** | annunciator_leds (`evaluate_single_annunciator`), switch_leds (`evaluate_switch`) |
| **Injection Method** | Passed as `eval_fn` parameter to consuming modules at init time (see C1 fix above) |
| **Purpose** | Reads the current value from a dataref magic table, applies an optional array index, and evaluates it against a compiled condition string. Returns boolean LED state. Includes nil guards for all dataref access paths. |

> **Implementation Note**: During implementation, decide whether this function lives in config_loader (as a shared utility) or is provided directly by the composition root from the original BravoMultiMode.lua logic. The injection parameter name `eval_fn` abstracts away the source — consuming modules only need to call it as a function with `(dataref_table, condition_string, index?)` arguments.
```

### Target File: DSGN-002 (Dependency Mapping & Injection Strategy)

#### Change 12a — Add to Runtime Dependency Graph Notes

**Location**: In the "Runtime Dependency Graph" section or near the annunciator_leds/switch_leds entries, add a note about `eval_fn` as a shared utility:

```markdown
> **Shared Utility**: The `get_led_state_for_dataref()` function (extracted from BravoMultiMode.lua line ~1187) is provided to annunciator_leds and switch_leds via the injected `eval_fn` parameter. Its exact module home (config_loader vs dedicated utility) will be determined during implementation, but it follows the same injection pattern — no global access required.
```

---

## Implementation Priority Order

The following order minimizes cross-document dependencies and ensures critical issues are resolved first:

| Step | Issue(s) | Target File(s) | Reason |
|------|----------|----------------|--------|
| 1 | C1 (eval_fn injection) | DSGN-001, DSGN-002 | Critical — violates core design principle; must be resolved before any module implementation |
| 2 | M1 (set_sub_handlers API) | DSGN-001, DSGN-002 | Major — affects led_engine wiring which is Phase 1 CRITICAL priority |
| 3 | M2 (profiler dispatch entries) | DSGN-003 | Major — would cause silent runtime failures if missing at implementation time |
| 4 | M3 (_G.command_once inconsistency) | DSGN-001, DSGN-003 | Major — RAD-005 Finding 3 must be fully resolved before Phase 3 implementation |
| 5 | I1 (bravo_hid naming) | DSGN-002 | Minor — clarification only; no functional impact |
| 6 | I2 (profiler globals note) | DSGN-003 | Minor — documentation clarity; can be done alongside M2 fix |
| 7 | I3 (performance constraints) | DSGN-001 | Minor — recommended improvement for implementation guidance |
| 8 | I4 (get_led_state_for_dataref origin) | DSGN-001, DSGN-002 | Minor — clarification; already addressed by C1's eval_fn injection parameter |

---

## Verification Checklist

After all fixes are applied, verify:

- [ ] All 8 issues from this BUGFIX plan have been addressed in the target files
- [ ] No references to `config.eval_condition()` remain as direct global access in DSGN-001 module descriptions (all replaced with injected `eval_fn`)
- [ ] led_engine's Public API table includes `M.set_sub_handlers(sub_handlers_table)` and its documentation is consistent with DSGN-002 wiring pseudocode
- [ ] dispatch_callbacks routing table in DSGN-003 contains entries for both `toggle_profiler` and `profiler_log_task`
- [ ] No `_G.command_once` references remain in DSGN-003's trim handler dispatch callbacks (all routed through dispatch module)
- [ ] Performance constraints subsection added to each of the 11 modules in DSGN-001
- [ ] `bravo_hid` is documented as an alias for `hardware` module, not a separate module
- [ ] Profiler functions are explicitly stated as NOT global entry points
- [ ] Run `python3 toolbox/validate_docs.py` to verify YAML preamble consistency and cross-reference integrity

---
