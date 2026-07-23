---
id: REQ-008
title: Modular Architecture Revision and Lua Best Practices Analysis
version: 1.0.0
status: APPROVED
created: 2026-07-23 11:11:11
updated: 2026-07-23 11:27:41
related_docs: []
---
# Summary

Investigate and assess whether the current modular Lua architecture of the Bravo Multi Mode project (under `FlyWithLua/Modules/bravo++`) can be further optimized through application of established Lua best practices, producing two deliverables: (1) a structured analysis report with actionable recommendations for architectural improvement, and (2) a curated Lua Best Practices guide tailored to this project's specific architecture, runtime constraints, and FlyWithLua integration patterns.

# Business Context / Rationale

The Bravo Multi Mode project uses a modular Lua-based architecture with multiple dispatch modules (`dispatch.lua`, `dispatch_modes.lua`, `dispatch_buttons.lua`, `dispatch_trim.lua`, `dispatch_twist.lua`, `dispatch_action_map.lua`), UI components, state management, configuration handling, and utility libraries. As the codebase grows in complexity across multiple aircraft modes (B58, C90B, DA42, Transponder), ensuring adherence to Lua best practices is critical for:

- **Maintainability**: Well-structured modules reduce cognitive load when adding new features or modifying existing behavior.
- **Performance**: Proper use of Lua's module system, garbage collection patterns, and scoping rules directly impacts runtime performance in the X-Plane flight simulation environment.
- **Reliability**: Consistent coding conventions and architectural patterns reduce bugs and make debugging more efficient.
- **Scalability**: A clean modular architecture enables easier addition of new aircraft types or modes without introducing coupling issues.

This analysis will identify architectural improvements that align with industry-standard Lua conventions, helping the project maintain high code quality as it evolves.

# Scope

## In Scope

- Comprehensive review of all Lua modules under `FlyWithLua/Modules/bravo++/` including dispatch, UI, utility, state management, configuration, logging, and hardware abstraction layers.
- **Deep analysis of the main entry script** (`FlyWithLua/Scripts/BravoMultiMode.lua`, 1577 lines) to identify responsibilities that can be extracted into dedicated modules. The following candidate areas have been identified for potential modularization:

  | Candidate Module | Current Location in BravoMultiMode.lua | Responsibility |
  |---|---|---|
  | **Profiler** (~lines 20–130) | Cumulative performance profiler with task tracking, sorted logging every 60s, toggle command | Self-contained timing system; strong candidate for extraction |
  | **Dispatch Entrypoint** (~lines 175–210) | `bravo_dispatch` global wrapper, callback registry (`dispatch_callbacks`), varargs forwarding via `try_catch` | Central routing hub; could become a proper module with explicit export table |
  | **Configuration Loader** (~lines 230–380) | Multi-step config detection (exact match → variant → generic fallback), validation context building, dataref binding parsing | Self-contained file resolution logic; strong candidate for extraction |
  | **Mode Manager** (~lines 410–560) | Mode cycling (`cycle_mode_up`/`down`), CF mode switching, switch mode cycling, conceptual mode grouping, selector index management | Mix of state and command wiring; could split into `mode_manager.lua` + `command_registry.lua` |
  | **Rocker Switch Router** (~lines 560–620) | Dynamic creation of 14 rocker switch commands (7 switches × UP/DOWN), dataref registration | Self-contained loop with uniform pattern; strong candidate for extraction |
  | **Trim & Twist Handlers** (~lines 620–730) | Trim wheel up/down, twist knob increase/decrease, decoder handler wiring | Thin wrappers delegating to dispatch; could be consolidated into a single `input_handlers.lua` module |
  | **Button Lifecycle Manager** (~lines 750–810) | AP button begin/continue/end lifecycle with per-button command registration loop | Self-contained pattern; candidate for extraction as `button_lifecycle.lua` |
  | **LED State Engine** (~lines 820–1460) | Button LEDs, gear LEDs (3-channel), annunciator LEDs (row 1 + row 2), rocker switch LEDs, dataref condition evaluation (`get_led_state_for_dataref`), LED buffer management, HID feature report assembly/sending, first-sync timer, periodic update loop with `do_more_often`, exit cleanup | **Largest concern** — ~640 lines of tightly coupled but conceptually separable responsibilities. Candidate sub-modules: `led_engine.lua` (core state + buffer), `led_hid_bridge.lua` (HID report assembly/sending), `annunciator_leds.lua`, `gear_leds.lua`, `switch_leds.lua`, `dataref_condition_evaluator.lua` |
  | **Exit Cleanup** (~lines 1520–1577) | Graceful shutdown: turn off LEDs, send cleared report, close HID device | Self-contained; could be a small `shutdown.lua` module or integrated into existing modules |

- Assessment against the official [Lua 5.4 Manual](https://www.lua.org/manual/5.4/manual.html) for language-level best practices (module system, scoping, metatables, coroutines, garbage collection).
- **Assessment against the FlyWithLua host application manual** (`/mnt/d/X-Plane 12/Resources/plugins/FlyWithLua/Documentation/FlyWithLua_Manual_en.pdf`) to ensure all recommendations are compatible with FlyWithLua's execution model (string callbacks in global environment, `do_every_frame`, `create_command`, dataref access patterns).
- **Review of FlyWithLua example scripts** (`/mnt/d/X-Plane 12/Resources/plugins/FlyWithLua/Scripts (disabled)`) — a collection of ~100+ practical examples demonstrating idiomatic usage of FlyWithLua features including floating windows, imgui UIs, HID feature reports, dataref access patterns, command registration, and custom datarefs. These serve as concrete reference implementations for the Best Practices guide.
- Evaluation using community best practice guidelines from [MediaWiki Lua Best Practices](https://www.mediawiki.org/wiki/Help:Lua/Lua_best_practice).
- Reference to curated quality resources from [awesome-lua](https://github.com/lewisjellis/awesome-lua) for additional patterns and anti-patterns.
- Analysis of module interdependencies, coupling, cohesion, and separation of concerns across the modular architecture.
- Identification of refactoring opportunities with prioritized recommendations (critical, high, medium, low).
- **Production of a curated Lua Best Practices guide** specific to the Bravo Multi Mode project, synthesizing findings from all three reference sources and tailoring them to this codebase's architecture. This document will serve as an ongoing reference for Worker specialists during refactoring implementation.

## Out of Scope

- Implementation or refactoring of identified issues (handled by Worker specialists in subsequent phases).
- Non-Lua code analysis (Python tooling, configuration files, documentation).
- Performance benchmarking or profiling beyond qualitative assessment.
- Changes to the FlyWithLua host application itself.

# Functional Requirements

1. Produce a complete inventory of all Lua modules in `FlyWithLua/Modules/bravo++/` with their dependencies and responsibilities.
2. **Perform deep structural analysis of `BravoMultiMode.lua`** (1577 lines) to identify every distinct responsibility, assess its cohesion relative to the modular architecture, and determine which responsibilities can be extracted into dedicated modules without breaking FlyWithLua's string-callback execution model.
3. Evaluate each module against the official [Lua 5.4 Manual](https://www.lua.org/manual/5.4/manual.html) for compliance with language-level best practices including proper use of `require`, local scoping, metatables, and garbage collection patterns — **and cross-check all findings against the FlyWithLua host application manual** to ensure compatibility with FlyWithLua's execution model (string callbacks in global environment, `do_every_frame` semantics, dataref access constraints).
4. Cross-reference implementation patterns from the FlyWithLua example scripts (`/mnt/d/X-Plane 12/Resources/plugins/FlyWithLua/Scripts (disabled)`) to identify idiomatic conventions for floating windows, imgui UIs, HID feature reports, command registration, and dataref access — using these examples as reference implementations when evaluating the Bravo Multi Mode codebase's patterns.
4. Assess architectural cohesion and coupling using guidelines from [MediaWiki Lua Best Practices](https://www.mediawiki.org/wiki/Help:Lua/Lua_best_practice), identifying modules that violate single-responsibility principles or exhibit excessive interdependency. Specifically evaluate whether the LED engine (~640 lines) should be split into sub-modules (core state, HID bridge, annunciators, gear lights, switch LEDs).
5. Cross-reference findings with curated resources from [awesome-lua](https://github.com/lewisjellis/awesome-lua) to identify additional anti-patterns, optimization opportunities, and idiomatic Lua usage issues.
6. Classify all identified issues by severity (critical, high, medium, low) and provide concrete refactoring recommendations with code-level examples where applicable.
7. Produce a structured analysis report documenting findings, including dependency maps, architectural alignment assessment, technical debt hotspots, and prioritized improvement roadmap — with specific guidance on how to restructure `BravoMultiMode.lua` into smaller, focused modules while preserving FlyWithLua's global string-callback entrypoints.
8. **Produce a curated Lua Best Practices guide** for the Bravo Multi Mode project that synthesizes findings from all three reference sources ([Lua 5.4 Manual](https://www.lua.org/manual/5.4/manual.html), [MediaWiki Lua Best Practices](https://www.mediawiki.org/wiki/Help:Lua/Lua_best_practice), [awesome-lua](https://github.com/lewisjellis/awesome-lua)) and tailors them to this codebase's specific patterns, constraints, and architecture. The guide must cover the following topics with concrete examples drawn from or applicable to the existing codebase:

   | Topic Area | Coverage |
   |---|---|
   | **Module Organization** | `require` conventions, export table patterns, namespace management via tables, avoiding global pollution (relevant given FlyWithLua's string-callback execution model) |
   | **Scoping & Visibility** | Local vs global variable discipline, forward declaration patterns (as used for `get_button_led_state`, `handle_led_changes`), closure best practices with varargs (`...`) |
   | **Error Handling** | Structured use of `pcall`/`try_catch` wrappers, error logging conventions via the `log` module, graceful degradation strategies |
   | **LED/HID Communication** | LED state management patterns (buffer → evaluate → send), conditional dataref evaluation (`get_led_state_for_dataref`), HID report assembly and sending conventions |
   | **DataRef Interaction** | Dataref table usage, array vs scalar handling, condition compilation (`config.compile_condition`), safe access patterns with nil guards |
   | **Performance Considerations** | Frame-rate sensitivity in `do_every_frame` callbacks, profiler integration, minimizing allocations in hot paths, garbage collection awareness for long-running simulation sessions |
   | **Configuration Management** | Multi-step config detection (exact → variant → fallback), validation context building, preference merging strategy |
   | **Command Registration** | `create_command` patterns for X-Plane/FlyWithLua integration, dataref-based command wiring, callback string conventions |
   | **FlyWithLua Integration Patterns** | String-callback execution model (global environment), `do_every_frame` semantics and performance implications, `do_on_exit` cleanup guarantees, floating window API (`float_wnd_create`, `float_wnd_set_imgui_builder`), X-Plane dataref access constraints within FlyWithLua context — sourced from the [FlyWithLua Manual](/mnt/d/X-Plane%2012/Resources/plugins/FlyWithLua/Documentation/FlyWithLua_Manual_en.pdf) and validated against idiomatic patterns in the ~100+ example scripts (`Scripts (disabled)/`). |
   | **Anti-Patterns to Avoid** | Global variable leakage, tight coupling between modules, monolithic scripts (the anti-pattern this analysis targets), unguarded table access, missing nil checks on datarefs |

# Success Criteria / Acceptance Criteria

- All Lua modules under `FlyWithLua/Modules/bravo++/` have been reviewed against all four reference sources plus the FlyWithLua example scripts: [Lua 5.4 Manual](https://www.lua.org/manual/5.4/manual.html), FlyWithLua host application manual (`FlyWithLua_Manual_en.pdf`), [MediaWiki Lua Best Practices](https://www.mediawiki.org/wiki/Help:Lua/Lua_best_practice), [awesome-lua](https://github.com/lewisjellis/awesome-lua), and the FlyWithLua example scripts directory (~100+ examples).
- **The main script `BravoMultiMode.lua` has been fully analyzed** with every distinct responsibility catalogued and assessed for modularization potential.
- A comprehensive analysis report has been produced documenting all findings with severity classifications and actionable recommendations.
- Dependency mapping between modules is complete and accurately reflects current inter-module relationships, including the wiring patterns used in `BravoMultiMode.lua`.
- Technical debt hotspots are identified with specific code locations and improvement suggestions — particularly noting the ~640-line LED engine as a high-priority modularization target.
- The report includes a prioritized roadmap for architectural improvements, clearly distinguishing critical fixes from optional enhancements, **with concrete module extraction proposals for `BravoMultiMode.lua` responsibilities** (e.g., profiler → `profiler.lua`, config loader → `config_loader.lua`, LED engine split into sub-modules).
- **A curated Lua Best Practices guide has been produced as a standalone deliverable**, covering all eight topic areas listed in Functional Requirement #8, with concrete code examples drawn from or applicable to the existing Bravo Multi Mode codebase. The guide must be actionable by Worker specialists during refactoring implementation and serve as an ongoing reference document for future development.

# Constraints / Guardrails / Dependencies

- All analysis must target Lua 5.4 runtime compatibility as specified by the FlyWithLua host application.
- Any recommended architectural changes must maintain backward compatibility with existing X-Plane integration points.
- The analysis is constrained to the current codebase state on the `agentic-refactoring` integration branch.
- Implementation of findings will be handled separately by Worker specialists; this requirement covers analysis and specification only.
- External dependencies: [Lua 5.4 Manual](https://www.lua.org/manual/5.4/manual.html), FlyWithLua host application manual (`FlyWithLua_Manual_en.pdf` at `/mnt/d/X-Plane 12/Resources/plugins/FlyWithLua/Documentation/`), FlyWithLua example scripts (~100+ examples at `/mnt/d/X-Plane 12/Resources/plugins/FlyWithLua/Scripts (disabled)/`), [MediaWiki Lua Best Practices](https://www.mediawiki.org/wiki/Help:Lua/Lua_best_practice), [awesome-lua](https://github.com/lewisjellis/awesome-lua).

# Timing / Deadline / Trigger

- **Trigger**: Initiated as part of the agentic-refactoring integration branch workflow to proactively assess architectural quality before further feature development.
- **Sequencing**: This analysis must complete before any refactoring tasks are created or assigned to Worker specialists.
- **Delivery window**: Analysis findings should be actionable within the current sprint cycle for prioritization by the Lead agent.

# Notes / Assumptions

- The project uses Lua 5.4 via the FlyWithLua host application for X-Plane flight simulation; all recommendations must target this runtime version specifically and be cross-checked against the [FlyWithLua Manual](/mnt/d/X-Plane%2012/Resources/plugins/FlyWithLua/Documentation/FlyWithLua_Manual_en.pdf) for platform-specific constraints.
- The FlyWithLua example scripts directory (`/mnt/d/X-Plane 12/Resources/plugins/FlyWithLua/Scripts (disabled)/`) contains ~100+ practical examples that serve as reference implementations for idiomatic FlyWithLua usage patterns including floating windows, imgui UIs, HID feature reports, dataref access, and command registration. These should be consulted when evaluating existing code patterns and producing the Best Practices guide.
- Backward compatibility is a priority — architectural improvements should not break existing aircraft mode configurations (B58, C90B, DA42, Transponder).
- The modular architecture currently uses Lua's `require` mechanism and local module exports; the analysis will assess whether alternative patterns (e.g., namespaces via tables) would provide better organization.
- Performance implications such as latency in dispatch handling, throughput of state updates, and resource utilization during flight simulation sessions should be considered when evaluating architectural changes.
- **FlyWithLua executes callback strings in the global environment** — any modularization of `BravoMultiMode.lua` must preserve a minimal set of global entrypoints (e.g., `bravo_dispatch`, `build_bravo_gui`, `on_close_floating_window`) that FlyWithLua's string callbacks can invoke. The analysis should evaluate whether the current pattern of forwarding through `bravo_dispatch` is itself a candidate for improvement or if it represents an acceptable bridge between global and modular code.
- **The LED engine (~640 lines) is the single largest responsibility block** in `BravoMultiMode.lua`, encompassing button LEDs, gear LEDs, annunciator LEDs, rocker switch LEDs, dataref condition evaluation, buffer management, HID report assembly, and periodic update scheduling. This should be treated as a primary modularization target.
- **The Lua Best Practices guide is intended to live alongside the codebase** (e.g., in `docs/` or `FlyWithLua/docs/`) so that Worker specialists can reference it during refactoring implementation without needing to consult external sources. It must use concrete examples from this project's existing modules and scripts rather than generic advice.

# SMART Check

- **Specific:** The requirement clearly defines two deliverables: (1) a structured analysis report covering Lua modules under `FlyWithLua/Modules/bravo++` and deep analysis of `BravoMultiMode.lua`, with prioritized recommendations including module extraction proposals; and (2) a curated Lua Best Practices guide tailored to this project's architecture, runtime constraints, and FlyWithLua integration patterns — informed by five reference sources.
- **Measurable:** Success is verifiable through completion of module inventory, `BravoMultiMode.lua` responsibility cataloguing, dependency mapping, severity-classified findings, the analysis report with actionable roadmap items, and a standalone Best Practices guide covering all ten specified topic areas (including FlyWithLua integration patterns) with concrete code examples from this project and reference implementations drawn from the ~100+ example scripts.
- **Achievable:** The codebase is accessible on the current branch; all three reference sources are publicly available online for consultation during analysis. The 1577-line main script is fully readable and its responsibilities can be systematically catalogued. Both deliverables are within scope of an analyst's research output.
- **Relevant:** This directly supports the project's goal of maintaining high-quality, maintainable Lua architecture as part of the agentic-refactoring initiative — particularly critical given that `BravoMultiMode.lua` contains ~640 lines of tightly coupled LED logic alongside other distinct concerns. The Best Practices guide will serve as an ongoing reference for Worker specialists during refactoring implementation.
- **Time-bound:** Triggered by the integration branch workflow with delivery expected within the current sprint cycle for prioritization before refactoring tasks are created.
