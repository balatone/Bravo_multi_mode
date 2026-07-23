---
id: FEAT-015
title: Lua Best Practices Guide
version: 1.0.0
status: DRAFT
created: 2026-07-23 12:39:06
updated: 2026-07-23 12:39:58
related_docs: ["REQ-008"]
---
# Feature Overview

This feature plans and guides the creation of a curated **Lua Best Practices Guide** tailored specifically to the Bravo Multi Mode project (`FlyWithLua/Modules/bravo++`). The guide will synthesize authoritative Lua references (Lua 5.4 Manual, MediaWiki Lua Best Practices, awesome-lua) with practical patterns observed in FlyWithLua example scripts and the specific architectural constraints of the Bravo Multi Mode codebase — including global callbacks, LED/HID communication, dataref access, and frame-rate-sensitive execution.

The guide will serve as an ongoing reference for Worker specialists during refactoring implementation (driven by REQ-008), ensuring consistent coding conventions across all Lua modules in the project.

# Objectives

Produce a high-quality, project-specific Lua Best Practices guide that:

- Synthesizes authoritative references (Lua 5.4 Manual, MediaWiki Lua Best Practices, awesome-lua) into actionable guidance for the Bravo Multi Mode codebase.
- Incorporates idiomatic patterns observed in FlyWithLua example scripts (~100+ examples covering floating windows, imgui UIs, HID feature reports, dataref access, and command registration).
- Tailors advice to the Bravo Multi Mode architecture — handling global callbacks, LED/HID communication, dataref interaction, frame-rate-sensitive execution, and modular dispatch patterns.
- Serves as a living reference document for Worker specialists during refactoring implementation of REQ-008 recommendations.

# Scope

## In Scope

- **Source Synthesis**: Consolidating best practices from three authoritative references:
  - Lua 5.4 Manual (module system, scoping, metatables, coroutines, garbage collection)
  - MediaWiki Lua Best Practices (coding conventions, anti-patterns, performance tips)
  - awesome-lua curated resources (additional patterns and anti-patterns)
- **FlyWithLua Pattern Integration**: Extracting idiomatic conventions from ~100+ FlyWithLua example scripts (`/mnt/d/X-Plane 12/Resources/plugins/FlyWithLua/Scripts (disabled)`), covering floating windows, imgui UIs, HID feature reports, dataref access patterns, and command registration.
- **Architecture-Specific Tailoring**: Adapting general Lua best practices to Bravo Multi Mode's specific constraints:
  - Handling global callbacks in FlyWithLua's string-callback execution model
  - LED/HID communication patterns (buffer → evaluate → send cycle)
  - Dataref access conventions (table vs scalar, nil guards, condition compilation)
  - Frame-rate-sensitive code (`do_every_frame` callback optimization)
  - Modular dispatch architecture (`dispatch.lua`, `dispatch_modes.lua`, etc.)
- **Guide Documentation**: Producing the final guide document with concrete examples drawn from or applicable to the existing codebase.

## Out of Scope

- Implementation or refactoring of identified issues (handled by Worker specialists in subsequent phases).
- Non-Lua code analysis (Python tooling, configuration files, documentation).
- Performance benchmarking or profiling beyond qualitative assessment.
- Changes to the FlyWithLua host application itself.

# Inputs to Review

Before drafting begins, review the following sources:

- **REQ-008** — Modular Architecture Revision and Lua Best Practices Analysis (primary requirement driving this feature).
- **Lua 5.4 Manual** (`https://www.lua.org/manual/5.4/manual.html`) — language-level best practices reference.
- **MediaWiki Lua Best Practices** (`https://www.mediawiki.org/wiki/Help:Lua/Lua_best_practice`) — coding conventions and anti-patterns.
- **awesome-lua** (`https://github.com/lewisjellis/awesome-lua`) — curated resources for additional patterns.
- **FlyWithLua Example Scripts** (~100+ scripts under `/mnt/d/X-Plane 12/Resources/plugins/FlyWithLua/Scripts (disabled)`) — practical reference implementations.
- **FlyWithLua Manual** (`/mnt/d/X-Plane 12/Resources/plugins/FlyWithLua/Documentation/FlyWithLua_Manual_en.pdf`) — host application execution model constraints.
- **Existing Bravo Multi Mode Lua modules** under `FlyWithLua/Modules/bravo++/` and main entry script `BravoMultiMode.lua`.

# Implementation Tasks

1. **Research**: Review all authoritative sources (Lua 5.4 Manual, MediaWiki Lua Best Practices, awesome-lua) and FlyWithLua example scripts to extract relevant patterns and conventions.
2. **Architecture Analysis**: Analyze existing Bravo Multi Mode Lua modules (`bravo++/` directory tree and `BravoMultiMode.lua`) to identify current patterns, anti-patterns, and areas where best practices would improve code quality.
3. **Cross-Reference & Synthesis**: Map general Lua best practices against FlyWithLua's execution model constraints (global callbacks, `do_every_frame`, dataref access) to produce project-specific guidance.
4. **Drafting**: Write the guide document covering all required topic areas: Module Organization, Scoping & Visibility, Error Handling, LED/HID Communication, DataRef Interaction, Performance Considerations, and Configuration Management — with concrete examples from or applicable to the Bravo Multi Mode codebase.
5. **Review**: Validate the draft against REQ-008 acceptance criteria and ensure all topic areas are adequately covered.
6. **Finalization**: Incorporate review feedback, finalize formatting, and set status to APPROVED.

# Acceptance Criteria

- The guide document covers all seven required topic areas: Module Organization, Scoping & Visibility, Error Handling, LED/HID Communication, DataRef Interaction, Performance Considerations, and Configuration Management.
- Each topic area includes concrete examples drawn from or applicable to the Bravo Multi Mode codebase (e.g., `dispatch.lua` patterns, LED buffer management, dataref condition evaluation).
- All recommendations are cross-checked against FlyWithLua's execution model constraints (string callbacks in global environment, `do_every_frame` semantics, dataref access limitations).
- The guide synthesizes findings from all three reference sources (Lua 5.4 Manual, MediaWiki Lua Best Practices, awesome-lua) without simply reproducing them verbatim — it must be a curated, project-specific document.
- Patterns observed in FlyWithLua example scripts are explicitly referenced and incorporated where applicable.

# Definition of Done

- Guide document is complete, covering all required topic areas with concrete examples.
- Document passes validation via `python3 toolbox/validate_docs.py`.
- Status set to APPROVED after review completion.
- Related docs field populated with REQ-008 reference (`REQ-008`).

# Dependencies / Risks

- **Dependency on REQ-008**: This feature is driven by the approved requirement REQ-008. The analysis report from REQ-008 may inform best practice recommendations (e.g., anti-patterns identified during structural analysis).
- **FlyWithLua Manual Access**: Requires access to `FlyWithLua_Manual_en.pdf` at `/mnt/d/X-Plane 12/Resources/plugins/FlyWithLua/Documentation/`. Any accessibility issues here would block the FlyWithLua-specific tailoring.
- **Example Scripts Availability**: ~100+ FlyWithLua example scripts under `(disabled)` directory must be accessible for pattern extraction.
- **Risk — Over-Generalization**: There is a risk that recommendations become too generic rather than project-specific. Mitigation: every recommendation should include at least one concrete Bravo Multi Mode code reference or example.
- **Constraint — No Implementation Scope**: This feature produces documentation only; actual refactoring of the codebase belongs to Worker specialists in subsequent phases.

# Implementation Notes

- The guide should be structured as a reference document — easy to navigate and search by topic area.
- Consider using code snippets from existing Bravo Multi Mode modules (e.g., `dispatch.lua`, `led_engine.lua` patterns, `config.lua`) as illustrative examples where they demonstrate good practices, or as "before/after" comparisons for anti-patterns identified in REQ-008 analysis.
- The guide should explicitly address FlyWithLua's unique execution model: string callbacks execute in a global environment with no module isolation, which fundamentally changes how `require` and local scoping apply compared to standard Lua usage.
