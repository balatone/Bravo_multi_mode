---
id: REQ-001
title: Populate Tech Stack Documentation (Lua)
version: 1.0.0
status: APPROVED
created: 2026-07-14 16:33:55
updated: 2026-07-14 17:09:29
related_docs: []
---
# Summary

This requirement mandates the formal discovery, documentation, and cataloging of all **Lua-specific** technologies, tools, frameworks, and libraries used across the project. The output is a single authoritative reference covering Lua runtimes (5.4.8), frameworks (FlyWithLua NG, ImGui, HID API), build toolchains (`luac`), static analysis/linting utilities (`luacheck 1.2.0`, `stylua 2.5.2`), code coverage tools for Lua (e.g., `luacov`), testing frameworks (e.g., `busted`), and architectural module boundaries — enabling consistent onboarding, reproducible builds, and informed dependency management decisions.

# Business Context / Rationale

The project is a Lua-based plugin ecosystem (targeting FlyWithLua NG for flight simulation). While Python tooling exists to support the SDLC pipeline (document creation, board state transitions, subagent delegation), **Python code is not developed as part of this project** — it serves only as development workflow automation. Without a centralized, up-to-date inventory of the Lua tech stack:

- **Onboarding friction**: New contributors must reverse-engineer language versions, linter configurations, and build steps from scattered files (e.g., `execution-cycle.yaml`, `.cfg` configs).
- **Build reproducibility risk**: The project's existing documentation (`tech-stack.md`) incorrectly lists LuaJIT 5.3 as the runtime — in reality only Lua 5.4.8 is installed; there is no LuaJIT, no `luac55`, and no Windows paths. This discrepancy means build instructions are wrong and new contributors will fail to reproduce the environment.
- **Quality gate ambiguity**: Static analysis tools (`luacheck 1.2.0` on PUC-Rio Lua 5.4, `stylua 2.5.2`) are in use, but their roles (linting vs. formatting), version pinning, and integration points with the SDLC pipeline are undocumented.
- **Dependency sprawl**: The modular Lua plugin structure (`config`, `dispatch`, `hardware`, `decoder`, `state`, `ui`, `mapbuilder`, `plugincheck`, `debug`, `log`) lacks a consolidated manifest linking each module to its dependencies and purpose.

Documenting the stack eliminates guesswork, corrects the misinformation in existing docs, reduces onboarding time, and provides a baseline for future dependency audits and upgrade planning.

# Scope

## In Scope

- **Lua programming language & runtime**: Lua 5.4.8 (PUC-Rio) — version constraints, interpreter (`lua`), bytecode compiler (`luac`).
- **Frameworks & libraries**: FlyWithLua NG, ImGui, HID API — with their roles in the architecture.
- **Lua build toolchain**: `uv` for managing Python dev dependencies that support the SDLC pipeline; Lua 5.4's built-in `luac` bytecode compiler.
- **Static analysis & linting tools**: `luacheck 1.2.0` (Lua static analysis/linter on PUC-Rio Lua 5.4), `stylua 2.5.2` (opinionated Lua code formatter).
- **Code coverage tooling for Lua**: e.g., `luacov` — document how it is used or planned for use, including instrumentation and report generation workflows.
- **Testing frameworks for Lua**: e.g., `busted` — document test runner configuration, assertion libraries, mocking capabilities, and integration with the SDLC pipeline.
- **Architectural module boundaries**: The modular Lua plugin structure (`config`, `dispatch`, `hardware`, `decoder`, `state`, `ui`, `mapbuilder`, `plugincheck`, `debug`, `log`) — documenting each module's responsibility and dependencies.
- **Configuration formats**: INI-style `.cfg` files and `preferences.cfg`.

## Out of Scope

- Python application development (Python is SDLC tooling only, not a project language).
- Third-party dependency license compliance auditing (covered by a separate requirement).
- Runtime performance benchmarking or profiling tool documentation.
- Hardware-specific driver details beyond HID API abstraction layer.
- Future technology additions not yet present in the codebase at time of this document's creation.

# Functional Requirements

1. **The system must produce a single, version-controlled markdown document** that catalogs every Lua language and runtime used by the project, including exact versions (Lua 5.4.8 — **not** LuaJIT).
2. **The system must identify and describe all Lua frameworks and libraries**, specifying their purpose within the architecture (e.g., FlyWithLua NG — plugin host; ImGui — UI rendering; HID API — hardware input abstraction).
3. **The system must document the Lua build toolchain**, including `luac` for bytecode compilation (not `luac55`) and any SDLC automation tools used to invoke it.
4. **The system must catalog all Lua static analysis and linting tools** with their versions (`luacheck 1.2.0`, `stylua 2.5.2`) and describe each tool's role — distinguishing between linting, formatting, and code quality enforcement.
5. **The system must document Lua code coverage tooling** (e.g., `luacov`), including how instrumentation is configured, how coverage data is collected/reported, and its integration with the SDLC pipeline.
6. **The system must document Lua testing frameworks** (e.g., `busted`), including test runner configuration, assertion libraries, mocking capabilities, and integration with the SDLC pipeline.
7. **The system must document the Python dev toolchain** only insofar as it supports the SDLC pipeline (e.g., `uv` for dependency management of development utilities), without treating Python as a project language being developed.
8. **The system must map architectural module boundaries**, documenting the purpose and responsibilities of each Lua plugin subdirectory (`config`, `dispatch`, `hardware`, `decoder`, `state`, `ui`, `mapbuilder`, `plugincheck`, `debug`, `log`).
9. **The system must describe configuration file formats** used by the project (INI-style `.cfg`, `preferences.cfg`) and their roles within the plugin architecture.

# Success Criteria / Acceptance Criteria

- The populated requirement document contains entries for every technology category listed in "In Scope" with no blank or placeholder sections.
- Each tool/framework/library entry includes at minimum: name, version (where applicable), purpose/role, and location within the repository.
- **The Lua runtime is correctly documented as Lua 5.4.8 — not LuaJIT.** This corrects a critical error in `tech-stack.md`.
- The architectural module map covers all 10+ Lua plugin subdirectories identified during analysis.
- Static analysis tools are explicitly distinguished by role (linting vs. formatting) with pinned versions.
- Code coverage (`luacov`) and testing (`busted`) tooling is documented even if currently unused — marked as "not yet integrated" rather than omitted entirely from the inventory.
- Python tooling is documented only as SDLC support utilities, not as a project development language.
- The document is reviewed and approved by at least one senior contributor or tech lead before status transitions from `DRAFT` to `ACTIVE`.

# Constraints / Guardrails / Dependencies

- **Constraint**: All version information must reflect the *current* state of the repository as of the documentation date; stale entries are a defect.
- **Constraint**: The document must remain in Markdown format and live under `internal-docs/01_requirements/` to maintain consistency with the project's SDLC directory structure.
- **Dependency**: Accurate version pinning requires runtime inspection (`lua -v`, `luacheck --version`, etc.) — no reliance on existing documentation files which are known to be incorrect.
- **Constraint**: The document is a living artifact — any tech stack change must trigger an update within the same development cycle.
- **Dependency**: This requirement feeds into downstream requirements for CI/CD pipeline configuration and onboarding documentation (REQ-002, REQ-003).

# Timing / Deadline / Trigger

- Needed by: 2026-07-21 (within one week of this requirement's creation)
- Trigger: This requirement is activated upon project kickoff for the refactor initiative and must be completed before any new module development begins.
- Review cadence: Re-evaluated at each SDLC cycle boundary or whenever a dependency version change occurs.

# Notes / Assumptions

- The technical analysis was performed on the repository state as of 2026-07-14; subsequent commits may introduce new tools or remove deprecated ones.
- **Critical correction**: `tech-stack.md` and `tools.md` contain incorrect information (LuaJIT, wrong luacheck/stylua versions, Windows paths). This requirement must explicitly correct those errors. Neither file should be used as a source of truth for analysis — all tool discovery must come from live environment inspection (`which`, version flags).
- Python is **not** a project language in this scope. It exists solely to support the SDLC pipeline (document creation, board state transitions, subagent delegation via Rolecast API). Its tools are documented only as development workflow utilities.
- The 12 document types in the SDLC system have not been enumerated here; a separate requirement (or appendix) should list them for completeness.

# SMART Check

- **Specific:** Yes — the requirement explicitly enumerates all Lua technology categories to document (languages/runtimes, frameworks, build tools, linters with correct versions, code coverage and testing tooling, architecture modules) and defines the output format (single version-controlled markdown file).
- **Measurable:** Yes — success is verifiable by checking that every "In Scope" category has populated entries with name, version, purpose, and location; no blank sections remain; Lua runtime is correctly identified as 5.4.8 not LuaJIT.
- **Achievable:** Yes — all technologies are already present in the repository and can be discovered via live environment inspection (`which`, `--version` flags). No external procurement or installation is required. Existing documentation files are explicitly excluded as sources due to known inaccuracies.
- **Relevant:** Yes — directly addresses onboarding friction, build reproducibility risk (correcting LuaJIT misidentification), and quality gate ambiguity identified during the initial technical assessment. Serves as a foundational artifact for all subsequent SDLC requirements.
- **Time-bound:** Yes — deadline of 2026-07-21 (one week from creation), triggered by refactor initiative kickoff, with ongoing maintenance gated to each development cycle boundary.
