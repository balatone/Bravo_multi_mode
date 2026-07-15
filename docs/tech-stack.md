---
id: TECH-001
title: Project Technology Stack
version: 1.0.0
status: active
created: 2026-07-14 16:36:00
updated: 2026-07-14 16:45:00
related_docs: []
---

# Project Tech Stack (SSoT)

## 1. Primary Programming Languages

| Language | Version / Flavor | Usage Scope |
|----------|------------------|-------------|
| **Lua** | PUC-Rio Lua 5.4.8 | Core application logic — all FlyWithLua scripts under `FlyWithLua/` |

> **Note**: LuaJIT is definitively absent from this environment; all bytecode and runtime are PUC-Rio 5.4.x compatible.
| **Python 3** | Standard library + PyYAML, requests | Tooling & orchestration utilities in `toolbox/` |

## 2. Key Frameworks & Libraries

### Runtime / Host Environment
- **FlyWithLua NG (Next Generation Plus Edition)** — The primary runtime framework that enables Lua scripting within X-Plane 12. Provides:
  - `hid_*` functions for HID device communication
  - `XPLMFindDataRef`, `dataref_table()` for reading X-Plane simulator datarefs
  - `XPLMFindCommand`, `command_once()`, `command_begin()`, `command_end()` for issuing X-Plane commands
  - ImGui-based floating window support (`float_wnd_create`, `imgui` global)
  - `do_every_frame()` callback registration

### UI Layer
- **ImGui** (via FlyWithLua's built-in bindings) — All GUI rendering in `bravo++.ui.lua`. Custom text wrapping, binary-search font scaling with LRU cache eviction, and custom button/knob drawing.

### Hardware Abstraction
- **HID API** — Direct USB HID communication to Honeycomb Bravo hardware (VID: 0x294B, PID: 0x1901). Implemented in `bravo++.hardware.lua` with budgeted polling loops (~5ms time budget per poll), injection queue for testing/simulation, and subscriber dispatch pattern.

### Bitwise Operations
- **Lua `bit` module** — Used extensively in `bravo++.decoder.lua` for parsing raw HID reports (bit masking, shifting, XOR operations on byte-level data).

## 3. Build & Orchestration Tools

| Tool | Purpose | Details |
|------|---------|---------|
| **uv** | Python package manager / runner | Used to execute toolbox scripts (`uv run toolbox/...`) and manage dependencies |
| **git** | Version control | Board state transitions commit changes; execution cycle commits approved features |
| **PUC-Rio Lua 5.4.8** | Lua interpreter/runtime | `/usr/bin/lua` — for running/debugging scripts locally |
| **luac** | Lua bytecode compiler | `/usr/bin/luac` — compiles `.lua` → `.lc` bytecode (bundled with Lua 5.4) |

### Custom SDLC Orchestration Framework (YAML-based)
- **execution-cycle.yaml** — Orchestrates the full implementation lifecycle: IMPLEMENTING → TESTING → REVIEWING → DONE with automated BUGFIX re-review loops
- **implement-feat.yaml / review-feat.yaml** — Sub-recipes for delegated feature implementation and code review
- **board_utils.py** — Kanban board state management (TO-DO, ANALYSING, DESIGNING, PLANNING, IMPLEMENTING, TESTING, REVIEWING, DONE) with YAML task files in `.board/`

## 4. Development & Analysis Tools (`toolbox/`)

| Script | Purpose |
|--------|---------|
| **doc_utils.py** | Document lifecycle management — CREATE and UPDATE operations for RAD/SPIKE/DSGN/REQ/BUG/FEAT/etc. documents with YAML preamble handling, auto-incremented IDs, and template rendering |
| **validate_docs.py** | Documentation validation — checks YAML preambles, mandatory fields, status lifecycles, verdicts, priorities, and `related_docs` integrity across all document types |
| **board_utils.py** | Kanban board operations — task transitions, logging, metadata management with git integration |
| **discover_subagents.py** | Rolecast API client for discovering available specialist subagents by role (worker/analyst/reviewer) |
| **get_delegation_params.py** | Generates delegation parameters (provider, model, extensions, max_turns) based on specialist ID and task complexity |
| **init_workspace.py** | Workspace scaffolding — creates the full directory structure (`internal-docs/*`, `.board/*`, `logs/`), document templates, and tech-stack placeholder |
| **get_identity_block.py** | Generates `[IDENTITY INGESTION]` blocks for subagent delegation based on model IDs (format: `role:<archetype>:<specialist-id>`) |

### Static Analysis & Formatting Tools
- **luacheck 1.2.0** — Lua static analysis/linter (`/usr/bin/luacheck`). Used with `.luacheckrc` for FlyWithLua globals (e.g., `XPLMFindDataRef`, `imgui`, `command_once`)
- **stylua 2.5.2** — Opinionated Lua code formatter (`/home/eb/.cargo/bin/stylua`)

## 5. Architecture & Configuration Technologies

### Application Architecture (Bravo++ Plugin)
The main application is a modular FlyWithLua script with clean separation of concerns:

| Module | Responsibility |
|--------|---------------|
| `config.lua` | Config file parsing, key validation, LED condition compilation (`>0`, `=1`, etc.) |
| `dispatch.lua` | Action mapping engine — button click/hold/long-press/twist knob/rocker switch execution with XPLM command dispatch |
| `hardware.lua` | HID device lifecycle — non-blocking polling loop, injection queue for testing/simulation, subscriber pattern |
| `decoder.lua` | Raw byte-level HID report decoding — rotary encoder CW/CCW detection, selector position one-hot parsing, trim wheel edge detection with debounce/deduplication |
| `state.lua` | Pub/sub state management (selector, rotary, trim) |
| `ui.lua` | ImGui rendering engine with text layout cache, binary-search font scaling, custom button/knob drawing |
| `mapbuilder.lua` | Single-pass hierarchical map initialization for all UI mappings |
| `plugincheck.lua` | Honeycomb Bridge conflict detection (folder presence + process running check) with ImGui warning dialog |
| `debug.lua` | HID report diff logging utility |
| `log.lua` | Structured logging with timestamp and severity levels |

### Configuration System
- **Key=value config files** — INI-style format for aircraft-specific configurations (`bravo_multi-mode.<aircraft>.cfg`)
- **preferences.cfg** — Global defaults (LONG_CLICK_THRESHOLD, CONTINUOUS_PRESS_THRESHOLD, TRIM_INCREMENT, TRIM_BOOST)
- **Config validation pipeline** — Two-phase: key existence/type validation → value structure/semantics validation including DataRef existence checks

### Document Management System
The project implements a formal SDLC documentation system with:
- **12 document types**: REQ, BUG, RAD, SPIKE, DSGN, DEC, PLAN, FEAT, BUGFIX, REVIEW, RETRO
- **Strict naming convention**: `[PREFIX]-[ID]-[description].md` (e.g., `RAD-001-user-story-breakdown.md`)
- **YAML preamble** with mandatory fields: id, title, version, status, created, updated, related_docs
- **Lifecycle statuses**: DRAFT → IN_REVIEW → APPROVED → SUPERSEDED/DEPRECATED → ARCHIVED
- **Review verdicts**: APPROVED, CONDITIONAL_APPROVAL, REQUEST_CHANGES, REJECTED

## 6. Domain-Specific Technologies

| Technology | Description |
|------------|-------------|
| **X-Plane 12** | Flight simulator platform (target environment) |
| **DataRefs** | X-Plane's data access system — read/write cockpit parameters (e.g., `sim/autopilot/altitude_up`, `sim/GPS/g1000n1_com_outer_up`) |
| **XPLM Commands** | X-Plane command system for triggering actions (e.g., `FlyWithLua/Bravo++/cycle_mode_up`) |
| **Honeycomb Bravo Hardware** | Physical hardware target — 8 buttons, 7 rocker switches, left selector knob, right rotary encoder, trim wheel. VID:0x294B PID:0x1901 |
| **FlyWithLua NG** | Lua scripting engine for X-Plane 12 (NG = Next Generation) |

## Summary

This is a **Lua-based desktop plugin** for the X-Plane 12 flight simulator that extends Honeycomb Bravo hardware functionality. The project combines:

1. A **mature Lua application** (~3,000+ lines across 9 modules) with sophisticated HID decoding, ImGui rendering, and configuration validation
2. A **Python-based orchestration layer** for SDLC management (document creation, board state transitions, subagent delegation via Rolecast API)
3. A **formal documentation system** with strict naming conventions, lifecycle states, and automated validation
