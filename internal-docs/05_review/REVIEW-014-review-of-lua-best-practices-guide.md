---
id: REVIEW-014
title: Review of Lua Best Practices Guide
version: 1.2.0
status: IN_REVIEW
created: 2026-07-23 18:08:21
updated: 2026-07-23 18:08:57
verdict: REQUEST_CHANGES
related_docs: ["REQ-008", "FEAT-015"]
---
# Executive Summary

This review evaluates the **Lua Best Practices Guide** (`docs/lua-best-practices.md`) against FEAT-015 requirements, Lua 5.4 language standards, and FlyWithLua execution model constraints. The guide is a well-structured, project-specific reference document that successfully synthesizes authoritative sources with practical Bravo Multi Mode patterns across all seven required topic areas. It demonstrates strong understanding of FlyWithLua's global environment model, dataref access semantics, and frame-rate-sensitive execution constraints.

## Key Takeaway

The guide is technically sound, comprehensive, and well-organized — it serves as an excellent reference for Worker specialists during the modular refactoring phase. A few technical clarifications are needed around bitwise library usage in FlyWithLua's Lua 5.4 runtime before final approval.

# Review Scope

**Reviewed:** `docs/lua-best-practices.md` (the complete Lua Best Practices Guide document).
**Not Reviewed:** Implementation code changes, worker refactoring tasks, or other documentation files. The review focuses solely on the guide's technical accuracy, completeness against FEAT-015 requirements, and adherence to FlyWithLua/Lua 5.4 standards.

# Review Criteria

The following criteria were used to evaluate the guide:

- **Correctness** — Lua 5.4 syntax accuracy, FlyWithLua API correctness, proper use of dataref patterns.
- **Architecture / design alignment** — Consistency with Bravo Multi Mode modular architecture (REQ-008), module organization guidance matching actual codebase structure.
- **Completeness** — Coverage of all seven FEAT-015 topic areas: Module Organization, Scoping & Visibility, Error Handling, LED/HID Communication, DataRef Interaction, Performance Considerations, Configuration Management.
- **Code quality** — Quality and clarity of example snippets, consistency between "GOOD" and "BAD" patterns.
- **Performance** — Accuracy of performance guidance relative to FlyWithLua's `do_every_frame` execution model.
- **Security** — Proper handling of `_G` access, error wrapping for command invocations.
- **Maintainability** — Practical applicability for Worker specialists during refactoring implementation.

# Findings Summary

The guide passes the majority of review criteria with high marks. All seven required topic areas are covered with concrete examples drawn from or applicable to the Bravo Multi Mode codebase. The synthesis of Lua 5.4 standards, FlyWithLua constraints, and project-specific patterns is excellent. Three categories of issues were identified: one major issue requiring clarification (bitwise library API), two minor issues (typos/inconsistencies), and several observations for future enhancement.

# Required Changes Before Approval

## Blockers

- None identified. The guide does not contain critical errors that would prevent its use as a reference document.

## Major Issues

1. **Bitwise Library API Ambiguity** — The guide uses `bitwise.bor()` and `bitwise.lshift()` in the LED/HID Communication section (Phase 3 buffer-to-HID conversion). FlyWithLua runs Lua 5.4, which provides bitwise operations via the standard library module named `bit32` (not `bitwise`). In Lua 5.4, the correct syntax is:
   ```lua
   local bit = require("bit")  -- Lua 5.4 built-in 'bit' module
   bit.bor(data[bank], bit.lshift(1, bit - 1))
   ```
   The guide should clarify which bitwise library API FlyWithLua actually exposes and update the example code accordingly. This is a **technical accuracy issue** that could mislead developers implementing HID report assembly.

2. **Forward Declaration Pattern Inconsistency** — The Scoping section shows two different patterns for global callbacks: (a) forward-declared `local` variables assigned to anonymous functions, and (b) module-level exports via `M.init()`. While both are valid approaches, the guide should explicitly state when each pattern is appropriate. Forward declarations are needed only for FlyWithLua string-callback entrypoints that must be globally named; all other code should use the module export pattern (`local M = {} ... return M`).

## Minor Issues

1. **Typo in LED Engine Table** — The SRP decomposition table uses "mgmt" instead of "management" (e.g., "Core LED state + buffer mgmt"). This is a cosmetic issue but should be corrected for professionalism.
2. **Line Number References May Become Stale** — References to specific line numbers (e.g., "`BravoMultiMode.lua` lines 820–1460") will become outdated as code evolves. Consider using function names or section descriptions instead of absolute line references, or note that these are approximate and subject to change.
3. **Missing Lua 5.4 Coroutines Note** — The guide does not mention whether FlyWithLua supports coroutines (available in Lua 5.4). Since X-Plane runs on a single main thread, using `coroutine.yield()` could block the entire flight simulator. A brief note warning against coroutine usage would be helpful for Worker specialists.

# Positive Findings

1. **Excellent Project-Specific Tailoring** — Every section includes concrete code examples drawn from actual Bravo Multi Mode modules (`dispatch.lua`, `hardware.lua`, `condition_compiler.lua`, etc.). This directly addresses the FEAT-015 risk of "over-generalization" and makes the guide immediately actionable for Worker specialists.

2. **Accurate FlyWithLua Execution Model Understanding** — The guide correctly identifies that FlyWithLua executes all scripts in a shared global environment, making `require()` the only isolation mechanism. This is fundamental to understanding why scoping rules differ from standard Lua usage.

3. **Comprehensive DataRef Access Pattern Coverage** — The three-tier access pattern table (get/set → DataRef() → magic tables) with relative speed benchmarks is accurate and directly useful for developers choosing between patterns based on performance requirements.

4. **Well-Structured Anti-Pattern Checklist** — The appendix anti-pattern checklist provides a quick-reference summary that Worker specialists can use during code reviews of their own implementations.

5. **Module Dependency Diagram** — The dependency tree in the Appendix accurately reflects the actual Bravo++ module structure and serves as an excellent architectural reference.

6. **Configuration Fallback Pattern** — The exact → variant → generic fallback pattern for config loading is a robust, well-documented approach that handles aircraft-specific customization elegantly.

7. **Performance Guidance Is Actionable** — Specific recommendations (pre-allocate buffers, use `table.concat()`, time budget awareness) are concrete and directly applicable to the `do_every_frame` execution model. The debounce pattern for physical inputs is particularly useful.

# Verification Results

The following checks were performed during this review:

1. **FEAT-015 Requirements Cross-Check** — All seven required topic areas verified as present with adequate depth.
2. **Lua 5.4 Syntax Validation** — Code examples checked against Lua 5.4 language specification; bitwise library API identified as potentially incorrect for FlyWithLua's runtime.
3. **FlyWithLua Execution Model Verification** — Global callback model, `do_every_frame` semantics, and dataref access patterns verified against known FlyWithLua behavior.
4. **Code Reference Accuracy** — Module names (`dispatch.lua`, `hardware.lua`, `condition_compiler.lua`) cross-referenced with actual Bravo++ directory structure; all references confirmed accurate.
5. **Template Compliance** — Guide follows the expected document structure (sections, code blocks, tables) consistent with other project documentation.

# Risks / Follow-ups

1. **Bitwise Library Clarification Needed** — Before final approval, verify which bitwise library API FlyWithLua actually provides (`bit`, `bit32`, or a custom module). Update the LED/HID Communication section accordingly.
2. **Coroutines Guidance Gap** — Consider adding a brief note about coroutine availability in FlyWithLua and recommending against their use due to X-Plane's single-threaded execution model.
3. **Stale Line References** — Replace absolute line number references with function-name or description-based references to prevent the guide from becoming outdated as code evolves.
4. **Living Document Maintenance** — Establish a process for updating this guide when new patterns emerge during Worker refactoring implementation, ensuring it remains current throughout the project lifecycle.

# Supporting Materials / Evidence

- Reviewed against FEAT-015 feature plan (`internal-docs/04_planning/04b_features/FEAT-015-lua-best-practices-guide.md`)
- Cross-referenced with REQ-008 requirements (`internal-docs/01_requirements/REQ-008-modular-architecture-revision-and-lua-best-practices-analysis.md`)
- Verified module names against actual Bravo++ directory structure under `FlyWithLua/Modules/bravo++/`
