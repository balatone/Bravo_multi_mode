---
id: BUGFIX-005
title: Fixes for Lua Best Practices Guide
version: 1.0.0
status: DRAFT
created: 2026-07-23 18:18:37
updated: 2026-07-23 18:19:19
related_docs: ["REVIEW-014", "FEAT-015"]
---
# Summary

This BUGFIX addresses technical issues identified in REVIEW-014 of the Lua Best Practices Guide (`docs/lua-best-practices.md`). The fixes correct a bitwise library API mismatch, clarify forward declaration patterns, fix typos, and add missing coroutine guidance to ensure the guide is accurate for FlyWithLua's Lua 5.4 runtime environment.

# Scope

## In Scope

- **Bitwise Library API Correction**: Replace all instances of `bitwise.bor()`, `bitwise.lshift()` (and related calls) with the correct `bit.bor()`, `bit.lshift()` API as used in Bravo++ codebase (`decoder.lua`).
- **Forward Declaration Clarification**: Add explicit guidance distinguishing when to use forward-declared local variables vs. module export patterns for FlyWithLua callbacks.
- **Typo Fixes**: Correct "mgmt" → "management" and other minor typos in the LED engine table and elsewhere.
- **Coroutine Note Addition**: Insert a warning note about coroutine usage risks in X-Plane's single-threaded execution model.

## Out of Scope

- Changes to `docs/lua-best-practices.md` section structure or topic coverage (all seven FEAT-015 topics remain intact).
- Replacing absolute line number references with function-name references (noted as a future enhancement in REVIEW-014 but not critical for approval).
- Any code implementation changes outside the guide document.

# Proposed Fix

The fixes are all documentation-level edits to `docs/lua-best-practices.md`. Each issue identified in REVIEW-014 will be addressed with targeted content updates:

1. **Bitwise API Correction** — A find-and-replace across the LED/HID Communication section (Phase 3, ~line 275 area) changing `bitwise.` → `bit.` for all bitwise function calls (`bor`, `lshift`, `band`, `bxor`).
2. **Forward Declaration Clarification** — Add a callout/note box in the Scoping & Visibility section explaining that forward-declared local variables are only needed when FlyWithLua requires globally named string callbacks; otherwise, use module exports via `local M = {}`.
3. **Typo Corrections** — Replace "mgmt" with "management" throughout and fix any other minor inconsistencies identified in the review.
4. **Coroutine Note** — Add a brief note (in Performance Considerations or as a new callout) warning that FlyWithLua runs on X-Plane's single main thread, so `coroutine.yield()` will block the entire simulator and should be avoided.

# Implementation Tasks

1. Open `docs/lua-best-practices.md` and locate all instances of `bitwise.` in the LED/HID Communication section (Phase 3).
2. Replace `bitwise.bor()` → `bit.bor()`, `bitwise.lshift()` → `bit.lshift()`, `bitwise.band()` → `bit.band()`, `bitwise.bxor()` → `bit.bxor()`.
3. Add a note in the Scoping & Visibility section distinguishing forward-declared local patterns (for FlyWithLua string callbacks) from module export patterns (`local M = {}`).
4. Search for "mgmt" and replace with "management" throughout the document, particularly in the LED engine table.
5. Insert a coroutine warning note — recommend placement in the Performance Considerations section or as a standalone callout near the `do_every_frame` discussion.
6. Review the entire document one final time to ensure consistency after all edits.

# Acceptance Criteria

- All instances of `bitwise.` are replaced with `bit.` and match the API used in actual Bravo++ code (`decoder.lua`).
- The forward declaration section explicitly states when each scoping pattern is appropriate (forward-declared local vs. module export).
- No typos remain; "mgmt" has been corrected to "management".
- A clear warning about coroutine usage risks exists in the guide, referencing X-Plane's single-threaded execution model.
- The document still covers all seven FEAT-015 topic areas without structural changes.

# Verification Plan

- **Manual Review**: Read through `docs/lua-best-practices.md` after each fix to verify correctness and consistency.
- **Cross-Reference with Codebase**: Verify that the corrected bitwise API (`bit.bor()`, etc.) matches actual usage in Bravo++ modules (e.g., `FlyWithLua/Modules/bravo++/decoder.lua`).
- **Reviewer Re-check**: Submit the updated guide for re-review against REVIEW-014's findings to confirm all issues are resolved.

# Risks / Notes

- The bitwise library correction is well-documented in REVIEW-014 and cross-referenced with `decoder.lua`, so risk of incorrect replacement is low.
- Adding coroutine guidance should be brief — a single callout paragraph is sufficient; no need for an extensive section.
- Forward declaration clarification must not introduce confusion: both patterns are valid, the distinction is about *when* each applies (FlyWithLua string callback requirement vs. standard module export).

# Supporting Materials

- **Bitwise API Reference**: `decoder.lua` imports via `local bit = require("bit")` and uses `bit.bor()`, `bit.lshift()`, `bit.band()`, `bit.bxor()` throughout (lines 69–148).
- **FlyWithLua Execution Model**: X-Plane runs on a single main thread; all FlyWithLua scripts share this context. Coroutine usage would block the entire simulator.
- **Review Findings**: All issues documented in REVIEW-014 (`internal-docs/05_review/REVIEW-014-review-of-lua-best-practices-guide.md`).
