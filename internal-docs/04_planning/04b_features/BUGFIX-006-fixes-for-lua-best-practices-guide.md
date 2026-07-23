---
id: BUGFIX-006
title: Fixes for Lua Best Practices Guide
version: 1.0.0
status: DRAFT
created: 2026-07-23 18:20:44
updated: 2026-07-23 18:21:31
related_docs: ["REVIEW-014"]
---
# Summary

This BUGFIX addresses all issues identified in REVIEW-014 for the Lua Best Practices Guide (`docs/lua-best-practices.md`). The review returned a `REQUEST_CHANGES` verdict with no blockers but two major and three minor findings that must be resolved before final approval. This plan outlines specific, actionable steps to correct each finding.

# Scope

## In Scope

- **Bitwise Library API Correction**: Replace all instances of `bitwise.bor()` and `bitwise.lshift()` with the correct FlyWithLua-compatible `bit.bor()` and `bit.lshift()`.
- **Forward Declaration Clarification**: Add explicit guidance on when to use forward-declared local variables vs. module export patterns (`M.init()`) for global callbacks.
- **Typo Correction in LED Engine Table**: Replace "mgmt" with "management" throughout the SRP decomposition table.
- **Coroutine Usage Note**: Add a warning section about coroutine usage in FlyWithLua's single-threaded X-Plane environment.
- **Line Number Reference Update (Optional)**: Consider replacing absolute line number references with function-name or description-based references where practical.

## Out of Scope

- Any changes to the guide's overall structure, topic coverage, or code examples beyond what REVIEW-014 explicitly flags.
- Implementation of Worker refactoring tasks triggered by this guide — those are handled in separate tasks (FEAT-017 through FEAT-020).
- Adding new topic areas not already present in the seven required sections from FEAT-015.

# Proposed Fix

The fixes target `docs/lua-best-practices.md` directly. Each finding maps to a discrete edit:

| Finding ID | Severity | Target Section(s) | Change Type |
|---|---|---|---|
| F1 — Bitwise API | Major | LED/HID Communication → Phase 3 (line ~275) | Replace `bitwise.` with `bit.` in all bitwise function calls |
| F2 — Forward Declaration Clarification | Major | Scoping & Visibility section | Add explanatory paragraph distinguishing the two patterns and their use cases |
| F3 — Typo Correction | Minor | LED Engine SRP decomposition table (Section 4) | Replace "mgmt" with "management" in all occurrences |
| F4 — Coroutine Note | Minor | Performance Considerations or new subsection | Add a brief warning about coroutine.yield() blocking X-Plane's main thread |
| F5 — Stale Line References | Observation | Throughout (lines 820–1460 references) | Replace absolute line numbers with function names/descriptions where feasible |

# Implementation Tasks

## Task 1: Bitwise Library API Correction (F1)

**Objective**: Correct all bitwise library calls from `bitwise.*` to `bit.*` throughout the guide.

**Steps**:
1. Open `docs/lua-best-practices.md`.
2. Locate line ~275 in the LED/HID Communication → Phase 3 section.
3. Replace:
   - `bitwise.bor(...)` → `bit.bor(...)`
   - `bitwise.lshift(...)` → `bit.lshift(...)`
4. Search for any other occurrences of `bitwise.` in the document and replace them with `bit.`.
5. Ensure that if a code snippet imports the module, it shows:
   ```lua
   local bit = require("bit")  -- FlyWithLua's built-in bitwise library
   ```
6. Cross-reference with actual Bravo++ source files (`FlyWithLua/Modules/bravo++/*.lua`) to confirm all examples match the `bit.*` API convention used in `decoder.lua`.

## Task 2: Forward Declaration Clarification (F2)

**Objective**: Add explicit guidance distinguishing when each callback pattern should be used.

**Steps**:
1. Locate the Scoping & Visibility section in `docs/lua-best-practices.md`.
2. Identify where both patterns are shown:
   - Pattern A: forward-declared local variables assigned to anonymous functions (for FlyWithLua string-callback entrypoints).
   - Pattern B: module-level exports via `M.init()` / `return M` (standard Lua modularization).
3. Add a new subsection or paragraph titled **"Choosing Between Patterns"** with the following guidance:

   > **When to use forward-declared locals**: Only when registering callbacks that FlyWithLua invokes by string name (e.g., `RegisterCallback("my_callback")`). The callback function must be globally resolvable at registration time, so a local variable declared before assignment is required.
   >
   > **When to use module exports (`M.init()`)**: For all other code — utility functions, configuration loaders, state managers, and any logic not directly invoked by FlyWithLua's string-callback mechanism. This pattern provides proper encapsulation via `require()`.

4. Add a brief note that the forward-declaration pattern is an exception to standard Lua module design, necessitated solely by FlyWithLua's global callback model.

## Task 3: Typo Correction in LED Engine Table (F3)

**Objective**: Correct "mgmt" → "management" for professionalism and consistency.

**Steps**:
1. Search `docs/lua-best-practices.md` for all occurrences of "mgmt".
2. Replace each instance with "management":
   - `"Core LED state + buffer mgmt"` → `"Core LED state + buffer management"`
3. Verify no other abbreviations were missed in the same table or nearby text.

## Task 4: Coroutine Usage Warning (F4)

**Objective**: Add a warning about coroutine usage in FlyWithLua's single-threaded environment.

**Steps**:
1. In `docs/lua-best-practices.md`, add a new subsection under **Performance Considerations** titled **"Coroutine Safety"**.
2. Insert the following guidance:

   > **Warning — Coroutines and X-Plane Threading**: While Lua 5.4 includes coroutine support (`coroutine.create()`, `coroutine.resume()`, `coroutine.yield()`), FlyWithLua runs on X-Plane's single main thread. Calling `coroutine.yield()` will block the entire flight simulator until the coroutine is resumed — which may never happen if no other script triggers it. **Do not use coroutines in `do_every_frame` callbacks or any code path that could be invoked during critical rendering frames.** For deferred execution, prefer FlyWithLua's built-in scheduling mechanisms (`do_every_frame`, `RegisterCallback`) instead of manual coroutine management.

3. Optionally add a cross-reference note pointing to Lua 5.4 documentation for coroutines as an informational aside (not recommended for production use in this context).

## Task 5: Stale Line Reference Update (F5) — Optional

**Objective**: Replace absolute line number references with function-name or description-based references.

**Steps**:
1. Search `docs/lua-best-practices.md` for patterns like "lines XXXX–YYYY" or "line XXX".
2. For each reference, determine the corresponding function name or section being described (e.g., "`BravoMultiMode.lua` lines 820–1460" → "`BravoMultiMode.lua` main dispatch loop").
3. Replace absolute line numbers with descriptive references:
   - Before: "See `BravoMultiMode.lua` lines 820–1460"
   - After: "See the main dispatch loop in `BravoMultiMode.lua` (approximately lines 820–1460)"
4. Add a note at the top of any section with line references stating that these are approximate and subject to change as code evolves.

# Acceptance Criteria

- [ ] All instances of `bitwise.bor()`, `bitwise.lshift()`, and similar `bitwise.*` calls in `docs/lua-best-practices.md` have been replaced with their `bit.*` equivalents.
- [ ] Code snippets that import the bitwise library show `local bit = require("bit")`.
- [ ] The Scoping & Visibility section includes explicit guidance distinguishing forward-declared locals (for FlyWithLua string-callbacks) from module exports (`M.init()`).
- [ ] All instances of "mgmt" in the LED Engine SRP decomposition table have been replaced with "management".
- [ ] A new "Coroutine Safety" subsection exists under Performance Considerations, warning against `coroutine.yield()` usage due to X-Plane's single-threaded model.
- [ ] Absolute line number references are either replaced with function-name/description-based references or annotated as approximate and subject to change.

# Verification Plan

1. **Visual Review**: Open `docs/lua-best-practices.md` in a text editor and visually verify each section against the acceptance criteria above.
2. **Search Validation**: Run `grep -n "bitwise\." docs/lua-best-practices.md` — this should return zero results after fixes are applied.
3. **Typo Check**: Run `grep -n "mgmt" docs/lua-best-practices.md` — verify no instances remain in the LED Engine table (or anywhere, if desired).
4. **Pattern Verification**: Search for "Coroutine Safety" or "coroutine.yield()" to confirm the warning section was added.
5. **Cross-Reference Check**: Compare corrected bitwise examples against actual Bravo++ source files (`FlyWithLua/Modules/bravo++/*.lua`) to ensure consistency with `decoder.lua`'s usage of `bit.*`.

# Risks / Notes

- **Risk: Over-editing Task 5**. Replacing all line number references could be time-consuming and may not add proportional value. If the Worker specialist determines this is low-value, they should flag it for the Lead to decide whether to defer or drop it.
- **Note**: All fixes are purely documentation changes — no code implementation is required. The target file `docs/lua-best-practices.md` is a reference document only.
- **Sequencing**: Tasks 1–3 are independent and can be done in any order. Task 4 (Coroutine Note) should be placed before final review to ensure it's visible during the re-review cycle.

# Supporting Materials

## Source Evidence for Bitwise API Correction

From `FlyWithLua/Modules/bravo++/decoder.lua` (confirmed source of truth):
```lua
local bit = require("bit")  -- decoder.lua, line 4
-- Usage throughout: bit.bor(), bit.lshift(), bit.band(), bit.bxor()
-- Lines 69–148 demonstrate all four bitwise operations in practice
```

FlyWithLua packages its own `bit` module (not `bitwise`). Using `require("bitwise")` will produce:
```
attempt to index global 'bitwise' (a nil value)
```

## Review-014 Key Findings Reference

| Finding | Severity | Section | Line(s) | Action |
|---|---|---|---|---|
| Bitwise API incorrect | Major | LED/HID Communication → Phase 3 | ~275 | Replace `bitwise.` with `bit.` |
| Forward declaration inconsistency | Major | Scoping & Visibility | N/A (section-level) | Add pattern-selection guidance |
| Typo "mgmt" | Minor | LED Engine SRP table | Section 4 | Replace with "management" |
| Missing coroutine note | Minor | Performance Considerations | N/A (add new subsection) | Add safety warning |
| Stale line references | Observation | Throughout | Various | Replace or annotate as approximate |
