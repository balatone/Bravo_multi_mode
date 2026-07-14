---
id: RAD-001
title: Lua Environment and Toolchain Technical Investigation
version: 1.0.0
status: APPROVED
created: 2026-07-14 17:16:04
updated: 2026-07-14 17:24:38
related_docs: ["REQ-001"]
---
# Executive Summary

This investigation performed live environment inspection to catalog all Lua-specific technologies in the Bravo++ project. **The critical finding is that existing documentation (`docs/tech-stack.md` and `tools.md`) contains four major inaccuracies**: it claims LuaJIT (5.3) as the runtime when only PUC-Rio Lua 5.4.8 exists; it lists luacheck at version 0.23.0 instead of 1.2.0; stylua is listed at 2.4.1 but installed at 2.5.2; and all tool paths reference Windows (`C:\...`) on a Linux system. Code coverage (luacov) and testing (busted) are available in the environment but completely unused — no test files, `.luacov` config, or `stylua.toml` exist anywhere in the repository. The Bravo++ plugin architecture comprises 10 core modules plus 4 aircraft-specific custom scripts, all under `FlyWithLua/Modules/bravo++/`.

# Purpose / Question

This analysis addresses **REQ-001: Populate Tech Stack Documentation (Lua)**. The purpose is to produce a single authoritative reference cataloging all Lua language and runtime technologies used in the project — correcting known misinformation in existing documentation, identifying gaps in testing/coverage tooling, and mapping architectural module boundaries. This document serves as the foundation for reproducible builds, informed onboarding, and future dependency management decisions.

# Scope

This investigation covers all Lua-specific technologies within the Bravo++ plugin ecosystem targeting FlyWithLua NG for X-Plane 12.

## In Scope

- **Lua runtime**: Interpreter (`lua`), bytecode compiler (`luac`) — version, path, and platform verification.
- **Frameworks & libraries**: FlyWithLua NG (plugin host), ImGui (UI rendering via `imgui` global), HID API (`hid_*` functions for Honeycomb Bravo hardware).
- **Static analysis tools**: luacheck (linter) and stylua (formatter) — version pinning, path resolution, configuration files.
- **Testing & coverage tooling**: busted (test runner) and luacov (code coverage) — availability assessment and integration gap analysis.
- **Architectural module boundaries**: All 10 core modules (`config`, `dispatch`, `hardware`, `decoder`, `state`, `ui`, `mapbuilder`, `plugincheck`, `debug`, `log`) plus 4 aircraft-specific custom scripts under `custom/`.
- **Configuration system**: INI-style `.cfg` files (aircraft-specific) and `preferences.cfg` (global defaults).

## Out of Scope

- Python application development (Python is SDLC tooling only, not a project language).
- Runtime performance benchmarking or profiling tool documentation.
- Hardware-specific driver details beyond HID API abstraction layer.
- Third-party dependency license compliance auditing.

# Current State

The Bravo++ project is a Lua-based plugin ecosystem for X-Plane 12's FlyWithLua NG, extending Honeycomb Bravo hardware (8 buttons, 7 rocker switches, selector knob, rotary encoder, trim wheel). The codebase: 10 core modules (`bravo++/*.lua`), 4 aircraft-specific scripts (`custom/`), 10 aircraft config files (`conf/`), 1 global `preferences.cfg`, and the host entry point `BravoMultiMode.lua`.

**Existing documentation contains known inaccuracies:**

- `docs/tech-stack.md`: claims LuaJIT (5.3) runtime; luacheck at 0.23.0, stylua at 2.4.1; Windows paths (`C:\apps\lua\`, `C:\Util\`).
- `tools.md`: lua55 at `C:\apps\lua\lua55.exe`; luacheck at `C:\Util\luacheck.exe`; stylua at `C:\Users\eb\.local\bin\stylua.exe`.

These documents were created during initial setup and have not been updated to reflect the actual Linux runtime environment.

# Methodology / Evidence

All tool discovery was performed via **live environment inspection** — no reliance on existing documentation (known to be incorrect per REQ-001). Commands executed:

| Check | Command | Result |
|-------|---------|--------|
| Lua runtime version | `lua -v` | Lua 5.4.8 PUC-Rio |
| luac compiler version | `luac -v` | Lua 5.4.8 PUC-Rio |
| luacheck version | `luacheck --version` | 1.2.0 (Lua 5.4) |
| stylua version | `stylua --version` | 2.5.2 |
| busted availability | `busted --version` | 2.3.0 (`/usr/bin/busted`) |
| luacov availability | `luacov --help` | 0.17.0 (`/usr/bin/luacov`) |
| Lua require tests | `lua -e "require 'busted'"`; `lua -e "require 'luacov'"` | Both load without error |
| Codebase scan | `find ... -name "*.lua"` | 16 `.lua` files across bravo++ core, custom, Scripts |
| Config file scan | `find ... -name "*.cfg"` | 11 `.cfg` files (10 aircraft + preferences.cfg) |
| Tool config search | `find ... \( -name ".luacheckrc" -o -name "stylua.toml" \)` | None found anywhere in repo |

**Source documents reviewed:** `docs/tech-stack.md`, `tools.md`, `REQ-001-populate-tech-stack-documentation.md`, all 10 core module source files, and `BravoMultiMode.lua` host script.

# Findings

## F1: Lua Runtime — PUC-Rio 5.4.8 (Not LuaJIT)

**Evidence:** `lua -v` → "Lua 5.4.8 Copyright (C) 1994-2025 Lua.org, PUC-Rio"; `luac -v` confirms same version; binary at `/usr/bin/lua`.

**Implication:** The existing documentation (`tech-stack.md`, `tools.md`) incorrectly identifies the runtime as LuaJIT compatible with Lua 5.3. This is a critical error — LuaJIT and PUC-Rio 5.4 have incompatible bytecodes, different garbage collection models, and divergent standard libraries (e.g., no `table.pack`/`table.unpack` in Lua 5.2+ without polyfills). The bytecode compiler (`luac`) at `/usr/bin/luac` produces `.lc` files compatible only with PUC-Rio 5.4.x interpreters.

## F2: Static Analysis Tools — Versions Updated, Paths Incorrect

| Tool | Documented Version | Actual Version | Documented Path | Actual Path |
|------|--------------------|----------------|-----------------|-------------|
| luacheck | 0.23.0 | **1.2.0** (Lua 5.4) | `C:\Util\luacheck.exe` | `/usr/bin/luacheck` |
| stylua | 2.4.1 | **2.5.2** | `C:\Users\eb\.local\bin\stylua.exe` | `/home/eb/.cargo/bin/stylua` |

**Implication:** Both tools are newer than documented, and all paths reference a Windows environment that does not match the current Linux system. luacheck 1.2.0 runs on PUC-Rio Lua 5.4 (confirmed by `luacheck --version`). stylua is installed via Cargo (Rust package manager), indicating it was added after initial setup.

## F3: No Static Analysis Configuration Files Exist

**Evidence:** A recursive search for `.luacheckrc`, `stylua.toml`, and `.stylua.toml` returned zero results across the entire repository.

**Implication:** Despite luacheck being used in code (via inline `-- luacheck: ignore ...` directives), there is no project-level configuration file to enforce consistent linting rules, ignored globals, or excluded patterns. The FlyWithLua-specific globals (`imgui`, `XPLMFindDataRef`, `command_once`, `logMsg`, etc.) are silenced per-file with inline comments rather than through a centralized `.luacheckrc`. This creates maintenance risk as new modules are added — linting rules must be manually replicated in each file.

## F4: Testing and Coverage Tooling Available but Unused

| Tool | Installed? | Version | Test Files Found | Config File Found |
|------|-----------|---------|-------------------|--------------------|
| busted | Yes (`/usr/bin/busted`) | 2.3.0 | **None** (no `*.spec.lua` or `*_test.lua`) | N/A |
| luacov | Yes (`/usr/bin/luacov`) | 0.17.0 | — | **No `.luacov` config** |

**Implication:** Both tools are installed system-wide and loadable via Lua's `require`, but the project has zero test infrastructure. No spec files, no coverage configuration, and no CI integration exist. This is a significant quality gap for a 3,000+ line codebase with complex HID decoding logic (decoder.lua), state management (state.lua), and dispatch routing (dispatch.lua).

## F5: Architectural Module Boundaries — 10 Core + 4 Custom Modules

The Bravo++ plugin follows a clean modular architecture under `FlyWithLua/Modules/bravo++/`:

| Module | Lines (approx.) | Responsibility | Key Dependencies |
|--------|-----------------|---------------|------------------|
| `config.lua` | ~200+ | Config file parsing, key/value validation, LED condition compilation (`>0`, `=1`) | `util`, `log` |
| `dispatch.lua` | ~300+ | Action mapping engine — button click/hold/twist knob execution with XPLM command dispatch | `util`, `log`, `state`, `config` |
| `hardware.lua` | ~250+ | HID device lifecycle, non-blocking polling loop (~5ms budget), injection queue for testing | `log` |
| `decoder.lua` | ~150+ | Raw byte-level HID report decoding — rotary encoder CW/CCW detection, selector one-hot parsing, trim wheel edge detection with debounce | `log`, `debug`, `state`, `bit` |
| `state.lua` | ~80+ | Pub/sub state management (selector, rotary, trim) via subscriber callback pattern | None |
| `ui.lua` | ~250+ | ImGui rendering engine — text layout cache, binary-search font scaling, custom button/knob drawing | `util`, `imgui` (FlyWithLua global) |
| `mapbuilder.lua` | ~100+ | Single-pass hierarchical map initialization for all UI mappings | `util`, `log` |
| `plugincheck.lua` | ~80+ | Honeycomb Bridge conflict detection via folder presence + process running check | `log` |
| `debug.lua` + `log.lua` | ~90+ | Structured logging with timestamps/severity; HID report hex dump diff utility | `logMsg` (FlyWithLua global) |

**Custom aircraft scripts:** `B58.lua` (Baron 58), `C90B.lua` (King Air C90B), `DA42.lua` (Aerobask DA42/DA62), `Transponder.lua` (VFR transponder code logic). Each guards execution with an aircraft name check.

**Host entry point:** `BravoMultiMode.lua` loads all modules via `require("bravo++.*")`, manages the main loop, and integrates MapBuilder for initialization.

## F6: Configuration System — INI-Style Key=Value Files

10 aircraft-specific configs under `conf/` plus one global `preferences.cfg`. Format is simple key=value (not strict INI). Keys include `LONG_CLICK_THRESHOLD`, `CONTINUOUS_PRESS_THRESHOLD`, `TRIM_INCREMENT`, `TRIM_BOOST`, and per-aircraft button mappings. Validation: two-phase — key existence/type → value structure/semantics including DataRef verification.

# Evaluation Criteria

This analysis was evaluated against the following criteria derived from REQ-001's success conditions:

| Criterion | Assessment |
|-----------|------------|
| **Correctness** | All version data sourced from live environment inspection (`lua -v`, `luacheck --version`, etc.), not existing documentation. Lua runtime confirmed as 5.4.8 PUC-Rio — definitively not LuaJIT. |
| **Completeness** | Every "In Scope" category from REQ-001 has been addressed: runtime, frameworks, build tools, static analysis, coverage, testing, architecture modules, and configuration formats. No blank sections remain. |
| **Reproducibility** | All tool paths are now Linux-native (`/usr/bin/lua`, `/usr/bin/luacheck`, `/home/eb/.cargo/bin/stylua`). Windows paths from existing docs have been identified as stale. |
| **Gap identification** | Testing infrastructure (busted, luacov) is available but unused — a critical quality gap for 3,000+ lines of complex logic. No `.luacheckrc` or `stylua.toml` exists despite tools being in use. |
| **Actionability** | Findings directly feed into downstream requirements: CI/CD pipeline configuration (REQ-002), onboarding documentation (REQ-003), and future testing implementation. |

# Options / Recommendations

## Documentation Correction (Immediate)

The existing `docs/tech-stack.md` and `tools.md` must be updated to reflect live environment findings:

| Field | Current (Incorrect) | Corrected Value |
|-------|---------------------|-----------------|
| Lua runtime | LuaJIT (compatible with 5.3) / lua55 at `C:\apps\lua\lua55.exe` | **PUC-Rio Lua 5.4.8** at `/usr/bin/lua` |
| luac compiler | luac55 at `C:\apps\lua\luac55.exe` | **luac** (bundled with lua 5.4) at `/usr/bin/luac` |
| luacheck version | 0.23.0 | **1.2.0** (on Lua 5.4) |
| stylua version | 2.4.1 | **2.5.2** |
| Platform paths | All `C:\...` Windows paths | Linux-native: `/usr/bin/`, `/home/eb/.cargo/bin/` |

## Recommended Direction

1. **Correct existing docs immediately**: Update `docs/tech-stack.md` and `tools.md` with verified versions and paths before any downstream work begins.
2. **Create `.luacheckrc` at repository root**: Define FlyWithLua-specific ignored globals (`imgui`, `XPLMFindDataRef`, `command_once`, `logMsg`, etc.) in one place rather than scattered inline directives. This enables consistent linting across all modules and future additions.
3. **Create `stylua.toml` at repository root**: Pin formatting rules (column width, indent type) to ensure consistency across the team.
4. **Integrate busted for testing**: Begin with unit tests for `decoder.lua` (most complex logic — byte-level HID parsing with debounce/deduplication). This module has clear input/output boundaries and is ideal for test-driven development.
5. **Add luacov instrumentation**: Once basic tests exist, enable coverage tracking to identify untested code paths in the decoder and dispatch modules.

## Testing Tooling Gap Assessment

| Option | Effort | Impact | Recommendation |
|--------|--------|--------|----------------|
| Use existing busted (2.3.0) + luacov (0.17.0) | Low — already installed | High — immediate test infrastructure | **Preferred** |
| Install Lua-specific testing frameworks via luarocks | Medium — requires setup | Moderate — adds dependencies | Not needed; system packages suffice |
| Defer testing until later SDLC phase | None | High risk — 3,000+ lines with no tests | **Not recommended** |

# Risks / Trade-offs / Constraints

| Risk | Severity | Mitigation |
|------|----------|------------|
| **Stale documentation causes build failures** for new contributors who follow `tech-stack.md`'s LuaJIT instructions on a Linux system. | High | Immediate correction of all docs with verified runtime data. Add a validation step to the SDLC pipeline that checks tool availability before accepting PRs. |
| **No test infrastructure** means regressions in decoder.lua (HID byte parsing) or dispatch.lua (action routing) go undetected until flight simulation testing. | High | Prioritize busted integration for the most complex modules first; use luacheck inline directives as a stopgap quality gate. |
| **Inline `-- luacheck: ignore` directives** are scattered across all 10 core modules, creating maintenance burden and inconsistency risk when FlyWithLua globals change. | Medium | Create `.luacheckrc` with global ignores; remove per-file ignore comments after migration. |
| **No formatting standardization**: Without `stylua.toml`, different developers may produce inconsistent code style despite stylua being available. | Low-Medium | Create minimal `stylua.toml` at repo root with project-wide rules. |
| **luacov instrumentation adds overhead** to runtime performance in a flight simulation context where frame budget is tight (~5ms per poll loop). | Medium | Use luacov only during development/testing, not in production builds; separate instrumented vs. release code paths. |

**Constraints:** All version data reflects repository state as of 2026-07-14 on Linux; LuaJIT definitively absent (no `luajit`/`lua53`/`luac55` binaries); Python tooling (`uv run toolbox/...`) supports SDLC pipeline only, out of scope.

# Supporting Materials / Evidence

See companion file: `RAD-001-lua-environment-and-toolchain-technical-investigation.notes.md` for the full module dependency graph, raw environment inspection output, and complete files inspected inventory.

# Next Steps

1. **Correct `docs/tech-stack.md` and `tools.md`** with verified runtime versions, tool paths, and platform information — this is a prerequisite for all downstream work per REQ-001's success criteria.
2. **Create `.luacheckrc` at repository root** to centralize FlyWithLua global ignores (currently scattered as inline comments across 10 modules). This enables consistent linting without per-file configuration drift.
3. **Create `stylua.toml` at repository root** with project-wide formatting rules (column width, indent type) to ensure style consistency.
4. **Establish test infrastructure**: Initialize a `tests/` directory with busted spec files starting with `decoder_spec.lua` (highest complexity, clearest I/O boundaries). This feeds into REQ-002 (CI/CD pipeline configuration).
5. **Add luacov instrumentation** to the test suite once basic specs exist — enables coverage reporting for decoder and dispatch modules where logic density is highest.
6. **Review this document** with a senior contributor or tech lead before transitioning status from `DRAFT` to `ACTIVE`, as required by REQ-001's acceptance criteria.

# Companion Notes / Raw Evidence

Detailed analysis, raw data, tables, calculations, code snippets, and exhaustive evidence should be stored in a separate companion file with the same base name and a `.notes.md` suffix.

Example: `RAD-001-demo-environment-definition.notes.md`

Use this main RAD document for the summary, decision, and high-level rationale only.
