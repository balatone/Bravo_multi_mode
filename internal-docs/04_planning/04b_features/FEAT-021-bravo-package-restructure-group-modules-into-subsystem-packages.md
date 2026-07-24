---
id: FEAT-021
title: Bravo++ Package Restructure — Move dispatch files into `dispatch/` package and create `init.lua` composition root
version: 1.0.0
status: APPROVED
created: 2026-07-24 10:25:00
updated: 2026-07-24 10:45:00
related_docs: ["FEAT-016", "FEAT-017", "FEAT-018", "FEAT-019", "DSGN-001", "DSGN-002", "PLAN-006"]
---

# Feature Overview

Move the 6 existing dispatch family files into the `dispatch/` sub-package under `FlyWithLua/Modules/bravo++/` and create `bravo++/init.lua` as the composition root. This feature runs **after** FEAT-017 through FEAT-019 have extracted all new modules into their respective packages (`led/`, `input/`) or flat in the root. The dispatch move is deferred to this point because it touches `BravoMultiMode.lua` and test files that are also modified by the extraction features — running last avoids merge conflicts on shared files.

# Objectives

- Move 6 existing dispatch family files into `bravo++/dispatch/`, formalizing the existing logical family (dispatch + action_map + buttons + modes + trim + twist).
- Create `bravo++/init.lua` as the composition root that wires all modules together via dependency injection.
- Update all `require` paths in `BravoMultiMode.lua`, other modules, and tests to reflect the new dispatch package paths.
- Verify FlyWithLua's `package.path` resolves subdirectory requires correctly.

# Scope

## In Scope

- Create `bravo++/dispatch/` and move 6 existing dispatch family files into it.
- Create `bravo++/init.lua` as the composition root (populated with requires for all modules now present after FEAT-017 through FEAT-019).
- Update `BravoMultiMode.lua` to require dispatch modules from `bravo++.dispatch.*` paths.
- Update internal dispatch requires (cross-references between dispatch modules).
- Update all test files referencing dispatch modules.
- Verify `package.path` resolves subdirectory requires in FlyWithLua.
- Verify all tests pass after restructuring.

## Out of Scope

- Creating `led/` or `input/` packages — those are created by FEAT-017 and FEAT-018 respectively as part of their module extraction work.
- Extracting new modules from `BravoMultiMode.lua` — that is covered by FEAT-017 through FEAT-019.
- Changing module internal APIs or behavior.
- Standardizing export patterns — that is FEAT-020.

# Inputs to Review

Before implementation begins, review the relevant documents listed in `related_docs` and confirm any open questions.

- **DSGN-001** — Module Interface Specification: defines the 11 target modules and their cross-module data flow diagram, which established the three package groupings (`led/`, `dispatch/`, `input/`).
- **DSGN-002** — Dependency Mapping and Injection Strategy: ensures no circular dependencies are introduced by the restructure.
- **FEAT-017** — LED Engine Modularization: creates `led/` package with 5 modules. Must complete before FEAT-021.
- **FEAT-018** — High Priority Extractions: creates `input/` package with 2 modules (`rocker_switches`, `button_lifecycle`). Must complete before FEAT-021.
- **FEAT-019** — Medium Priority Extractions: adds `input_handlers` to `input/` package. Must complete before FEAT-021.
- **PLAN-006** — Release Plan: defines the overall sequencing; this feature runs after FEAT-019 and before FEAT-020.

# Implementation Tasks

1. Review DSGN-001's cross-module data flow diagram and the current state of `bravo++/` after FEAT-017 through FEAT-019 to confirm all modules are in place.
2. Create `bravo++/dispatch/` directory.
3. Move existing dispatch family files into `bravo++/dispatch/`:
   - `dispatch.lua` → `dispatch/dispatch.lua`
   - `dispatch_action_map.lua` → `dispatch/action_map.lua`
   - `dispatch_buttons.lua` → `dispatch/buttons.lua`
   - `dispatch_modes.lua` → `dispatch/modes.lua`
   - `dispatch_trim.lua` → `dispatch/trim.lua`
   - `dispatch_twist.lua` → `dispatch/twist.lua`
4. Update `dispatch.lua` internal requires to use relative paths within the `dispatch/` package.
5. Update `BravoMultiMode.lua` to require dispatch modules from new paths (`bravo++.dispatch.*` instead of `bravo++.dispatch_*`).
6. Update any other modules that require dispatch modules (check all files in `bravo++/` and `bravo++/led/` and `bravo++/input/`).
7. Create `bravo++/init.lua` as the composition root, requiring all modules from their final locations.
8. Update all test files referencing moved modules:
   - `tests/unit/` — any unit tests importing dispatch modules
   - `tests/integration/dispatch_spec.lua` and `tests/integration/dispatch_integration_spec.lua`
   - `tests/integration/config_dispatch_spec.lua`
9. Verify `package.path` in FlyWithLua environment resolves `bravo++.dispatch.*` subdirectory requires.
10. Run full test suite (`busted` + `luacov`) and verify all tests pass.
11. Run `python3 toolbox/validate_docs.py` and `python3 coverage_check.py`.

# Acceptance Criteria

- The 6 dispatch files exist under `bravo++/dispatch/` with updated require paths.
- All `require("bravo++.dispatch.*")` paths resolve correctly.
- `bravo++/init.lua` exists as composition root with requires for all modules.
- All existing unit, integration, and e2e tests pass with zero failures.
- No new global variables introduced by the restructure.
- Coverage percentage maintained or improved (no regression).
- `BravoMultiMode.lua` requires dispatch modules from `bravo++.dispatch.*` paths.
- No behavioral changes — the restructure is purely organizational.

# Definition of Done

- All dispatch files moved and require paths updated.
- `bravo++/init.lua` created with all module requires.
- All tests passing (unit + integration + e2e).
- Coverage report generated and verified no regression.
- Document passes `python3 toolbox/validate_docs.py` validation.
- Review completed and status set to APPROVED.

# Dependencies / Risks

## Dependencies

- **FEAT-017** — Must complete first. Creates `led/` package with 5 modules.
- **FEAT-018** — Must complete first. Creates `input/` package with 2 modules.
- **FEAT-019** — Must complete first. Adds 1 module to `input/` package.
- **DSGN-001** — Must be APPROVED to confirm module boundaries and data flow.

## Risks

- **FlyWithLua package.path resolution** — Subdirectory requires (`bravo++.dispatch.dispatch`) may need explicit `package.path` configuration in FlyWithLua. If FWL only scans the root `bravo++/` directory, we may need to fall back to flat files with dot-notation names (e.g., `dispatch.dispatch.lua` required as `bravo++.dispatch.dispatch`). **Mitigation**: Test require resolution early; if subdirectories don't work, use flat files with dot-notation names as a fallback and document the constraint.
- **Test breakage** — Moving 6 dispatch files requires updating all test imports. **Mitigation**: Batch all path updates and verify with full test run before declaring done.
- **Shared file edits with FEAT-017/018/019** — `BravoMultiMode.lua` and some test files are modified by multiple features. **Mitigation**: By running FEAT-021 last, all other features have already landed their changes, so there is no merge conflict risk.

# Implementation Notes

## Target Directory Structure (after FEAT-017 through FEAT-021)

```
bravo++/
├── init.lua                    # Composition root (created by FEAT-021)
├── log.lua                     # Shared utility — flat
├── util.lua                    # Shared utility — flat
├── config.lua                  # Config definitions — flat
├── state.lua                   # State management — flat
├── decoder.lua                 # Decoder pub/sub — flat
├── ui.lua                      # ImGui GUI — flat
├── mapbuilder.lua              # Button map building — flat
├── condition_compiler.lua      # Condition compilation — flat
├── profiler.lua                # Performance profiler — flat (from FEAT-018)
├── config_loader.lua           # Config loader — flat (from FEAT-018)
├── mode_manager.lua            # Mode management — flat (from FEAT-019)
├── plugincheck.lua             # Plugin validation — flat
├── debug.lua                   # Debug utilities — flat
├── hardware.lua                # Hardware interface — flat
├── preferences.cfg             # Preferences — flat
├── conf/                       # Empty config dir — unchanged
├── custom/                     # Custom aircraft configs — unchanged
│
├── led/                        # LED subsystem (5 modules from FEAT-017)
│   ├── engine.lua              # led_engine
│   ├── hid_bridge.lua          # led_hid_bridge
│   ├── annunciators.lua        # annunciator_leds
│   ├── gear.lua                # gear_leds
│   └── switches.lua            # switch_leds
│
├── dispatch/                   # Dispatch subsystem (6 existing files, moved by FEAT-021)
│   ├── dispatch.lua            # Main dispatch entrypoint
│   ├── action_map.lua          # Action → command mapping
│   ├── buttons.lua            # Button dispatch handlers
│   ├── modes.lua              # Mode dispatch handlers
│   ├── trim.lua               # Trim dispatch handlers
│   └── twist.lua              # Twist dispatch handlers
│
└── input/                      # Input handling (3 modules from FEAT-018/019)
    ├── handlers.lua            # input_handlers (from FEAT-019)
    ├── rocker_switches.lua     # rocker_switches (from FEAT-018)
    └── button_lifecycle.lua    # button_lifecycle (from FEAT-018)
```

## Require Path Changes (this feature)

| Before | After |
|--------|-------|
| `require("bravo++.dispatch")` | `require("bravo++.dispatch.dispatch")` |
| `require("bravo++.dispatch_action_map")` | `require("bravo++.dispatch.action_map")` |
| `require("bravo++.dispatch_buttons")` | `require("bravo++.dispatch.buttons")` |
| `require("bravo++.dispatch_modes")` | `require("bravo++.dispatch.modes")` |
| `require("bravo++.dispatch_trim")` | `require("bravo++.dispatch.trim")` |
| `require("bravo++.dispatch_twist")` | `require("bravo++.dispatch.twist")` |

## Require Path Changes (handled by other features)

| Before | After | Feature |
|--------|-------|---------|
| `BravoMultiMode.lua` (inline) | `require("bravo++.led.engine")` | FEAT-017 |
| `BravoMultiMode.lua` (inline) | `require("bravo++.led.hid_bridge")` | FEAT-017 |
| `BravoMultiMode.lua` (inline) | `require("bravo++.led.annunciators")` | FEAT-017 |
| `BravoMultiMode.lua` (inline) | `require("bravo++.led.gear")` | FEAT-017 |
| `BravoMultiMode.lua` (inline) | `require("bravo++.led.switches")` | FEAT-017 |
| `BravoMultiMode.lua` (inline) | `require("bravo++.input.rocker_switches")` | FEAT-018 |
| `BravoMultiMode.lua` (inline) | `require("bravo++.input.button_lifecycle")` | FEAT-018 |
| `BravoMultiMode.lua` (inline) | `require("bravo++.input.handlers")` | FEAT-019 |

## Fallback: Flat Files with Dot-Notation Names

If FlyWithLua's `package.path` does not resolve subdirectory requires, the alternative is to keep files flat but use dot-notation names:

```
bravo++/
├── dispatch.dispatch.lua       # required as bravo++.dispatch.dispatch
├── dispatch.action_map.lua     # required as bravo++.dispatch.action_map
├── led.engine.lua              # required as bravo++.led.engine
├── input.handlers.lua          # required as bravo++.input.handlers
└── ...
```

This provides the namespace benefit without subdirectory dependency. Evaluate during implementation Task 9.
