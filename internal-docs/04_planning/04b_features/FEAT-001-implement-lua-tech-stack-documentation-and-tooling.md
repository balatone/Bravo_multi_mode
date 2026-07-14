---
id: FEAT-001
title: Implement Lua Tech Stack Documentation and Tooling
version: 1.0.0
status: APPROVED
created: 2026-07-14 17:30:00
updated: 2026-07-14 17:41:28
related_docs: ["RAD-001"]
---
# Feature Overview

This feature addresses the critical gaps identified in **RAD-001** (Lua Environment and Toolchain Technical Investigation). The existing project documentation (`docs/tech-stack.md` and `tools.md`) contains four major inaccuracies — wrong Lua runtime version, outdated tool versions, stale Windows paths on a Linux system. Additionally, no static analysis configuration files, test infrastructure, or code coverage tooling exist despite all tools being installed in the environment.

This feature delivers: corrected authoritative documentation, centralized linting and formatting configurations, a working busted-based test suite for `decoder.lua`, and luacov integration for code coverage reporting. These are prerequisites for reliable CI/CD (REQ-002) and onboarding (REQ-003).

# Objectives

- Correct all Lua runtime version claims in documentation to reflect PUC-Rio Lua 5.4.8 (not LuaJIT/Lua 5.3).
- Replace all stale Windows paths with verified Linux-native tool paths.
- Create `.luacheckrc` at the repository root to centralize FlyWithLua global ignores, eliminating scattered inline `-- luacheck: ignore` directives across 10 modules.
- Create `stylua.toml` at the repository root to enforce consistent code formatting rules project-wide.
- Establish a `tests/` directory with initial busted spec files targeting `decoder.lua`.
- Configure luacov for coverage reporting alongside the test suite.

# Scope

## In Scope

1. **Documentation Correction**: Update `docs/tech-stack.md` and `tools.md` with verified runtime versions, tool paths, and platform information.
2. **Linting Configuration**: Create `.luacheckrc` at repository root with FlyWithLua-specific global ignores (e.g., `imgui`, `XPLMFindDataRef`, `command_once`, `logMsg`, `hid_*`).
3. **Formatting Configuration**: Create `stylua.toml` at repository root with project-wide formatting rules (column width, indent type).
4. **Testing Infrastructure Setup**:
   - Create `tests/` directory at the repository root.
   - Implement initial busted spec file: `decoder_spec.lua`.
   - Verify test execution via `busted tests/`.
5. **Code Coverage Integration**: Configure luacov (0.17.0) to instrument and report coverage for the new test suite, producing a summary of covered/uncovered lines in decoder.lua.

## Out of Scope

- Testing beyond `decoder.lua` (dispatch.lua, state.lua, etc. are deferred to subsequent features).
- CI/CD pipeline integration (handled by REQ-002).
- Lua bytecode compilation tooling (`luac`) configuration.
- Additional static analysis tools or rule sets beyond luacheck and stylua.
- Removal of existing inline `-- luacheck: ignore` directives from source files (deferred to a follow-up cleanup task after `.luacheckrc` is verified).

# Inputs to Review

Before implementation begins, review the following documents and confirm any open questions:

1. **RAD-001** — Lua Environment and Toolchain Technical Investigation (`internal-docs/02_analysis/RAD-001-lua-environment-and-toolchain-technical-investigation.md`). Contains all verified version data, tool paths, module boundaries, and gap analysis findings that drive this feature's tasks.
2. **docs/tech-stack.md** — Current (incorrect) tech stack documentation. Must be updated with corrected values from RAD-001.
3. **tools.md** — Current (incorrect) Lua tools reference. Must be updated with Linux-native paths and correct versions.
4. **FlyWithLua/Modules/bravo++/decoder.lua** — The target module for initial test implementation. Contains the most complex logic: byte-level HID report decoding, rotary encoder CW/CCW detection, selector one-hot parsing, trim wheel edge detection with debounce/deduplication.

# Implementation Tasks

## Phase 1: Documentation Correction (Prerequisite)

### Task 1.1 — Correct `docs/tech-stack.md`

Update the following sections in `docs/tech-stack.md`:

- **Section "2. Build & Orchestration Tools"**:
  - Replace `Lua 5.5 (lua55)` → **PUC-Rio Lua 5.4.8**.
  - Update path from `C:\apps\lua\lua55.exe` → `/usr/bin/lua`.
  - Replace `luac55` at `C:\apps\lua\luac55.exe` → **luac** (bundled with Lua 5.4) at `/usr/bin/luac`.

- **Section "4. Development & Analysis Tools"**:
  - Update luacheck version from `0.23.0` → **1.2.0**.
  - Update luacheck path from `C:\Util\luacheck.exe` → `/usr/bin/luacheck`.
  - Update stylua version from `2.4.1` → **2.5.2**.
  - Update stylua path from `C:\Users\eb\.local\bin\stylua.exe` → `/home/eb/.cargo/bin/stylua`.

- **Section "1. Primary Programming Languages"**:
  - Replace LuaJIT (compatible with Lua 5.3) → **PUC-Rio Lua 5.4.8**.
  - Add note: "LuaJIT is definitively absent from this environment; all bytecode and runtime are PUC-Rio 5.4.x compatible."

- **Section "6. Domain-Specific Technologies"**: No changes needed (accurate).

### Task 1.2 — Correct `tools.md`

Replace the entire tools table with verified data:

| Tool | Version | Path | Purpose |
|------|---------|------|---------|
| **lua** | 5.4.8 PUC-Rio | `/usr/bin/lua` | Interpreter/runtime (also includes `luac` compiler) |
| **luac** | 5.4.8 PUC-Rio | `/usr/bin/luac` | Lua bytecode compiler — compiles `.lua` → `.lc` |
| **luacheck** | 1.2.0 (Lua 5.4) | `/usr/bin/luacheck` | Static analysis / linter |
| **stylua** | 2.5.2 | `/home/eb/.cargo/bin/stylua` | Opinionated Lua code formatter |

Update the Usage section to reflect Linux paths:

```bash
# Run a script
lua <script.lua>

# Compile to bytecode
luac -o <output.lc> <script.lua>

# Lint for issues
luacheck <file-or-directory>

# Format code
stylua <file-or-directory>
```

### Task 1.3 — Verify Corrections

- Run `lua -v` and confirm output matches documentation: "Lua 5.4.8 Copyright (C) 1994-2025 Lua.org, PUC-Rio".
- Run `luacheck --version` and confirm: "1.2.0 (Lua 5.4)".
- Run `stylua --version` and confirm: "2.5.2".

## Phase 2: Linting Configuration

### Task 2.1 — Create `.luacheckrc` at Repository Root

Create a centralized configuration file that declares all FlyWithLua-specific globals as allowed, eliminating the need for per-file inline ignore directives. The file should be placed at `agentic-refactoring/.luacheckrc`.

**Configuration structure:**

```ini
-- .luacheckrc — Centralized luacheck configuration for Bravo++ / FlyWithLua project
-- All FlyWithLua host-provided globals are declared here to avoid scattered inline ignores.

std = "lua54"

-- Ignore tables (globals provided by the FlyWithLua NG host environment)
ignore = {
    -- UI rendering
    "imgui",
    "float_wnd_create",
    "float_wnd_destroy",
    "float_wnd_pos",
    "float_wnd_size",
    "float_wnd_show",
    "float_wnd_hide",
    "float_wnd_begin",
    "float_wnd_end",

    -- XPLM data access
    "XPLMFindDataRef",
    "dataref_table",
    "dataref_ro",
    "dataref_rw",

    -- XPLM command dispatch
    "XPLMFindCommand",
    "command_once",
    "command_begin",
    "command_end",

    -- FlyWithLua host functions
    "do_every_frame",
    "logMsg",
    "get_string",
    "set_string",
    "get_number",
    "set_number",
    "get_integer",
    "set_integer",
    "get_boolean",
    "set_boolean",

    -- HID API (Honeycomb Bravo)
    "hid_open",
    "hid_close",
    "hid_read",
    "hid_write",
    "hid_get_feature_report",
    "hid_set_feature_report",
    "hid_error",
    "hid_enumerate",

    -- X-Plane UI callbacks
    "XPLMCreateWindowEx",
    "XPLMDestroyWindow",
    "XPLMDrawWindow",
    "XPGetMouseLocationDouble",
}

-- Per-file ignores (module-specific globals not covered above)
ignore_files = {}

-- Exclude patterns — files/directories to skip during linting
exclude_files = {
    ".luacheckrc",
    "stylua.toml",
    "tests/",
}

-- Warnings configuration
warnings = {
    "unused_variable",
    "shadow",
    "missing_fields",
    "missing_returns",
    "reading_global_before_assignment",
    "writing_global",
    "trailing_whitespace",
    "empty_block",
    "not_yetimplemented",
}

-- Enable all warnings by default (no --allow-defined-to-shadow, etc.)
```

### Task 2.2 — Validate `.luacheckrc`

- Run `luacheck FlyWithLua/Modules/bravo++/decoder.lua` and verify no errors related to FlyWithLua globals appear.
- Confirm that legitimate issues (e.g., unused variables) are still reported.
- Verify the file is excluded from linting by running `luacheck .luacheckrc`.

## Phase 3: Formatting Configuration

### Task 3.1 — Create `stylua.toml` at Repository Root

Create a minimal but complete formatting configuration at `agentic-refactoring/stylua.toml`:

```toml
# stylua.toml — Formatting rules for Bravo++ Lua codebase

column_width = 120
line_endings = "Unix"
indent_type = "Spaces"
indent_width = 4
quote_style = "AutoPreferDouble"
call_parentheses = "Always"
collapse_simple_statement = "Never"
```

**Rationale for each setting:**
- `column_width = 120`: Matches the existing codebase style; avoids excessive line wrapping in complex HID decoding logic.
- `line_endings = "Unix"`: Linux-native (consistent with all other project tooling).
- `indent_type = "Spaces"`, `indent_width = 4`: Standard Lua formatting convention.
- `quote_style = "AutoPreferDouble": Consistent string quoting across the codebase.
- `call_parentheses = "Always"`: Explicit parentheses for function calls — improves readability in nested expressions common in decoder.lua.
- `collapse_simple_statement = "Never"`: Preserves multi-line formatting for if/for/do blocks, matching existing style.

### Task 3.2 — Validate `stylua.toml`

- Run `stylua --check FlyWithLua/Modules/bravo++/decoder.lua` and verify no changes are reported (the file should already conform).
- If stylua reports differences, run `stylua FlyWithLua/Modules/bravo++/decoder.lua` to apply formatting.

## Phase 4: Testing Infrastructure Setup

### Task 4.1 — Create `tests/` Directory Structure

Create the test directory at the repository root:

```
agentic-refactoring/tests/
└── decoder_spec.lua
```

The `tests/` directory will be created directly under the project root (`agentic-refactoring/`). This keeps tests co-located with the source code for easy navigation.

### Task 4.2 — Implement `decoder_spec.lua`

Create an initial busted spec file targeting `decoder.lua`. The decoder module is the ideal first test target because:
1. It has clear input/output boundaries (raw byte arrays → decoded events).
2. It contains the most complex logic in the codebase (debounce, deduplication, one-hot parsing).
3. Bugs here would directly cause incorrect hardware behavior — high-risk area for regression.

**Spec file structure:**

```lua
-- tests/decoder_spec.lua
-- Busted unit tests for decoder.lua
-- Tests cover: rotary encoder CW/CCW detection, selector one-hot parsing, trim wheel edge detection with debounce/deduplication

local decoder = require("bravo++.decoder") -- Adjust path as needed based on package setup

describe("Decoder Module", function()

    describe("Rotary Encoder Detection", function()
        it("should detect clockwise rotation from byte sequence", function()
            -- Test CW detection logic with known byte patterns
            -- Expected: encoder event type = CW, delta = +1
        end)

        it("should detect counter-clockwise rotation from byte sequence", function()
            -- Test CCW detection logic with known byte patterns
            -- Expected: encoder event type = CCW, delta = -1
        end)

        it("should ignore no-change states", function()
            -- Feed repeated identical bytes; expect zero events emitted
        end)
    end)

    describe("Selector Position Parsing", function()
        it("should parse one-hot encoded selector positions correctly", function()
            -- Test each of the 7 possible one-hot bit patterns maps to correct position (0-6)
        end)

        it("should handle invalid/ambiguous one-hot states gracefully", function()
            -- Feed bytes with no bits set or multiple bits set; expect nil or error handling
        end)
    end)

    describe("Trim Wheel Edge Detection", function()
        it("should detect trim wheel edge transitions (up/down)", function()
            -- Test edge detection from consecutive byte states
        end)

        it("should debounce rapid transitions and prevent duplicate events", function()
            -- Feed high-frequency toggling bytes; expect only one event per valid transition
        end)

        it("should deduplicate repeated trim wheel presses within the debounce window", function()
            -- Verify that rapid re-presses are suppressed during the debounce period
        end)
    end)

    describe("HID Report Decoding Pipeline", function()
        it("should decode a complete HID report byte array into structured events", function()
            -- Integration test: feed full 8-byte HID report, verify all fields decoded correctly
        end)

        it("should handle malformed or truncated reports without crashing", function()
            -- Feed partial/invalid data; expect graceful handling (nil returns or safe defaults)
        end)
    end)

end)
```

**Implementation notes:**
- The spec file must be able to `require` the decoder module. Depending on how FlyWithLua's `require` system works, this may need a custom loader setup in the test bootstrap (e.g., adjusting `package.path`).
- If direct `require` is not feasible due to FlyWithLua host dependencies (HID device, XPLM), tests should use **dependency injection** or **mocking**: create wrapper functions that accept byte arrays as parameters rather than reading from hardware.
- Use busted's `before_each` / `after_each` hooks for test isolation where needed.

### Task 4.3 — Verify Test Execution

- Run `busted tests/decoder_spec.lua` and verify all tests pass (or fail with expected errors if the decoder module requires host environment setup).
- If direct testing is blocked by FlyWithLua dependencies, create a standalone test harness that extracts the pure decoding logic into testable functions.

## Phase 5: Code Coverage Integration

### Task 5.1 — Configure luacov

Create a minimal `.luacov` configuration file at the repository root (`agentic-refactoring/.luacov`):

```lua
-- .luacov — Luacov coverage configuration for Bravo++ project

stats_file = ".luacov.stats.out"
summary_file = ".luacov.report.out"

-- Paths to instrument (relative to repo root)
source_paths = {
    "FlyWithLua/Modules/bravo++/",
}

-- Files/directories to exclude from coverage reporting
exclude_files = {
    "^tests/",
    "^internal-docs/",
    "^toolbox/",
    "^docs/",
    "%.luacheckrc$",
    "stylua%.toml$",
}
```

### Task 5.2 — Integrate luacov with Test Execution

Create a convenience script or documented command sequence for running tests with coverage:

**Option A — Shell alias / Makefile target:**
```bash
# Run busted tests with luacov instrumentation
luacov busted tests/decoder_spec.lua
```

**Option B — Wrapper script `run-tests.sh`:**
```bash
#!/bin/bash
set -e
cd "$(dirname "$0")"
luacov busted tests/decoder_spec.lua
echo "Coverage report available at .luacov.report.out"
cat .luacov.report.out
```

### Task 5.3 — Verify Coverage Output

- Run the test suite with luacov enabled and verify:
  - `.luacov.stats.out` is generated (raw coverage data).
  - `.luacov.report.out` contains a human-readable summary showing covered/uncovered lines per file.
  - `decoder.lua` shows meaningful line coverage (>0% for tested functions, <100% for untested paths — confirming the tool works correctly).

# Acceptance Criteria

- [ ] **AC-1**: `docs/tech-stack.md` reflects PUC-Rio Lua 5.4.8 (not LuaJIT), luacheck 1.2.0, stylua 2.5.2, and all Linux-native paths (`/usr/bin/lua`, `/usr/bin/luac`, `/usr/bin/luacheck`, `/home/eb/.cargo/bin/stylua`).
- [ ] **AC-2**: `tools.md` contains the corrected tools table with verified versions and Linux paths; usage examples use correct commands.
- [ ] **AC-3**: `.luacheckrc` exists at repository root, declares all FlyWithLua globals as allowed, sets Lua 5.4 standard library, and excludes test/config files from linting.
- [ ] **AC-4**: `stylua.toml` exists at repository root with column_width=120, Unix line endings, 4-space indent, and AutoPreferDouble quote style. Running `stylua --check` on existing code produces no diffs.
- [ ] **AC-5**: A `tests/` directory exists at the repository root containing at least one spec file (`decoder_spec.lua`).
- [ ] **AC-6**: Busted can execute the test suite successfully: `busted tests/` completes without errors.
- [ ] **AC-7**: luacov configuration (`.luacov`) exists and produces coverage reports when run alongside the busted test suite.
- [ ] **AC-8**: Coverage report shows non-trivial line coverage for `decoder.lua`, confirming instrumentation is working.

# Definition of Done

- All acceptance criteria verified as complete.
- Documentation corrections cross-checked against live environment (`lua -v`, `luacheck --version`, `stylua --version`).
- `.luacheckrc` validated: runs on all 10 core modules without false-positive global errors; legitimate issues still reported.
- `stylua.toml` validated: existing codebase passes `--check` with zero formatting changes needed.
- Test suite executes cleanly under busted with no runtime errors.
- luacov coverage report generated and reviewed for correctness.
- All new files committed to version control with descriptive commit messages.

# Dependencies / Risks

| Dependency | Description | Mitigation |
|------------|-------------|------------|
| **RAD-001 must be APPROVED** | This feature's tasks are derived directly from RAD-001 findings and recommendations. | Confirm RAD-001 status is `APPROVED` before starting implementation (it currently is). |
| **busted 2.3.0 installed system-wide** | Test framework availability at `/usr/bin/busted`. | Already confirmed present; no additional installation needed. |
| **luacov 0.17.0 available** | Coverage tool must be loadable via `require 'luacov'`. | Already confirmed in RAD-001 findings (F4). |

| Risk | Severity | Mitigation |
|------|----------|------------|
| **decoder.lua requires FlyWithLua host environment to run** — Direct `require` may fail outside X-Plane. | High | Extract pure decoding functions into a testable module; use dependency injection or create mock wrappers for hardware/XPLM dependencies. |
| **Inline luacheck ignore directives conflict with `.luacheckrc` globals** — Existing per-file ignores may cause duplicate warnings. | Medium | After `.luacheckrc` is verified, perform a follow-up pass to remove redundant inline `-- luacheck: ignore` comments from source files. |
| **luacov instrumentation overhead in production** — Coverage tracking adds runtime cost unsuitable for flight simulation. | Medium | luacov only active during development/testing; never instrumented in production FlyWithLua builds. Document this separation clearly. |

# Implementation Notes

- **Sequencing**: Tasks 1.x (documentation correction) should be completed first, as they are prerequisites for all downstream work per REQ-001's success criteria.
- **Package path considerations**: Since the project uses FlyWithLua NG's custom `require` system rather than standard Lua package paths, test files may need a bootstrap that sets up `package.path` to point at `FlyWithLua/Modules/bravo++/`. Consider adding a `tests/init.lua` or using busted's configuration file (`busted.yml`) for this setup.
- **Standalone decoder testing**: If the full decoder module cannot be loaded in isolation, create a minimal testable subset that exposes only the pure decoding functions (byte → event conversion) without hardware/XPLM dependencies. This is preferable to mocking the entire FlyWithLua host environment.
- **luacov + busted integration**: The standard approach is `luacov busted <spec.lua>`, which instruments all files loaded during test execution and writes coverage stats afterward. Verify this works with the system-installed versions (busted 2.3.0, luacov 0.17.0).
- **File placement**: All new configuration files (`.luacheckrc`, `stylua.toml`, `.luacov`) go at the repository root (`agentic-refactoring/`), not inside `FlyWithLua/Modules/bravo++/`. This keeps tooling separate from application code.
