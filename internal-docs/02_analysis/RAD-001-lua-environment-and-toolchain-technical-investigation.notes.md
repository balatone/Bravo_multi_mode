---
id: RAD-001-notes
title: Lua Environment and Toolchain Technical Investigation — Companion Notes
version: 1.0.0
status: APPROVED
created: 2026-07-14 17:18:50
updated: 2026-07-14 17:25:28
related_docs: ["RAD-001"]
---
# Companion Notes: Lua Environment and Toolchain Technical Investigation

This file contains detailed evidence, raw data, and exhaustive inventory supporting `RAD-001-lua-environment-and-toolchain-technical-investigation.md`. Refer to the main document for summary findings and recommendations.

## Module Dependency Graph (Textual)

```
BravoMultiMode.lua  [host entry point]
    ├── config.lua ──→ util.lua, log.lua
    ├── dispatch.lua → util.lua, log.lua, state.lua, config.lua
    ├── hardware.lua → log.lua
    ├── decoder.lua  → log.lua, debug.lua, state.lua, bit (Lua stdlib)
    ├── state.lua    → [none — leaf module]
    ├── ui.lua       → util.lua, imgui (FlyWithLua global)
    ├── mapbuilder.lua → util.lua, log.lua
    ├── plugincheck.lua → log.lua
    ├── debug.lua    → log.lua
    └── log.lua      → logMsg (FlyWithLua global)

custom/
    ├── B58.lua      → log.lua  [aircraft guard: Baron_58]
    ├── C90B.lua     → log.lua  [aircraft guard: C90B]
    ├── DA42.lua     → log.lua  [aircraft guards: DA42, DA62]
    └── Transponder.lua → log.lua (uses dataref_table, get — FlyWithLua globals)
```

## Raw Environment Inspection Output

### Lua Runtime
```
$ lua -v
Lua 5.4.8  Copyright (C) 1994-2025 Lua.org, PUC-Rio

$ which lua
/usr/bin/lua
```

### luac Bytecode Compiler
```
$ luac -v
Lua 5.4.8  Copyright (C) 1994-2025 Lua.org, PUC-Rio

$ which luac
/usr/bin/luac
```

### luacheck Static Analyzer
```
$ luacheck --version
Luacheck: 1.2.0
Lua: PUC-Rio Lua 5.4
Argparse: 0.7.2
LuaFileSystem: 1.9.0
LuaLanes: Not found

$ which luacheck
/usr/bin/luacheck
```

### stylua Formatter
```
$ stylua --version
stylua 2.5.2

$ which stylua
/home/eb/.cargo/bin/stylua
```

### busted Test Runner
```
$ which busted && busted --version
/usr/bin/busted
2.3.0
```

### luacov Coverage Tool
```
$ which luacov && luacov --help | head -3
/usr/bin/luacov
LuaCov 0.17.0 - coverage analyzer for Lua scripts
   Usage:
      luacov [options] [pattern...]
```

### Lua require Tests (module availability)
```
$ lua -e "require 'busted'"    → loaded without error
$ lua -e "require 'luacov'"    → loaded without error
```

## Files Inspected (Complete Inventory)

| File | Path | Purpose Verified |
|------|------|-----------------|
| `config.lua` | `FlyWithLua/Modules/bravo++/config.lua` | Config parsing, condition compilation (`>0`, `=1`) |
| `dispatch.lua` | `FlyWithLua/Modules/bravo++/dispatch.lua` | Action mapping engine (click/hold/twist/rocker) |
| `hardware.lua` | `FlyWithLua/Modules/bravo++/hardware.lua` | HID device lifecycle, non-blocking polling (~5ms budget) |
| `decoder.lua` | `FlyWithLua/Modules/bravo++/decoder.lua` | Byte-level report decoding (rotary CW/CCW, selector one-hot, trim debounce) |
| `state.lua` | `FlyWithLua/Modules/bravo++/state.lua` | Pub/sub state management (selector, rotary, trim) |
| `ui.lua` | `FlyWithLua/Modules/bravo++/ui.lua` | ImGui rendering engine with text layout cache |
| `mapbuilder.lua` | `FlyWithLua/Modules/bravo++/mapbuilder.lua` | Single-pass hierarchical map initialization |
| `plugincheck.lua` | `FlyWithLua/Modules/bravo++/plugincheck.lua` | Honeycomb Bridge conflict detection |
| `debug.lua` | `FlyWithLua/Modules/bravo++/debug.lua` | HID report diff logging (hex dump) |
| `log.lua` | `FlyWithLua/Modules/bravo++/log.lua` | Structured logging with severity levels |
| `util.lua` | `FlyWithLua/Modules/bravo++/util.lua` | Shared helpers (`trim`, `find`) |
| `BravoMultiMode.lua` | `FlyWithLua/Scripts/BravoMultiMode.lua` | Host entry point, module loader, performance profiler |

### Custom Aircraft Scripts

| File | Guard Condition | Purpose |
|------|-----------------|---------|
| `B58.lua` | `AIRCRAFT_FILENAME == "Baron_58"` | Baron 58-specific dataref commands |
| `C90B.lua` | `AIRCRAFT_FILENAME == "C90B"` | King Air C90B-specific dataref commands |
| `DA42.lua` | `AIRCRAFT_FILENAME in {"DA42", "DA62"}` | Aerobask DA42/DA62-specific dataref commands |
| `Transponder.lua` | Always loads (latitude-based logic) | VFR transponder code auto-set for North America vs. rest of world |

## Configuration File Inventory

### Aircraft-Specific Configs (`conf/`)

| File | Target Aircraft |
|------|-----------------|
| `bravo_multi-mode.Baron_58.cfg` | Baron 58 |
| `bravo_multi-mode.C90B.cfg` | King Air C90B |
| `bravo_multi-mode.C90B.EVO.cfg` | King Air C90B EVO variant |
| `bravo_multi-mode.Cessna_172SP_G1000.cfg` | Cessna 172SP with G1000 avionics |
| `bravo_multi-mode.CirrusSF50.cfg` | Cirrus SF50 |
| `bravo_multi-mode.Cirrus SR22.cfg` | Cirrus SR22 |
| `bravo_multi-mode.DA42.cfg` | DA42 |
| `bravo_multi-mode.DA62.cfg` | DA62 |
| `bravo_multi-mode.g1000.cfg` | G1000 avionics suite |
| `bravo_multi-mode.gns530_430.cfg` | GNS 530/430 navcom |

### Global Configs

| File | Purpose |
|------|---------|
| `preferences.cfg` | Global defaults: `LONG_CLICK_THRESHOLD`, `CONTINUOUS_PRESS_THRESHOLD`, `TRIM_INCREMENT`, `TRIM_BOOST` |

## FlyWithLua NG Globals Referenced in Code

These globals are available at runtime via the FlyWithLua NG host but are absent from luacheck's analysis scope. They appear as inline ignore directives or type assertions across modules:

| Global | Used In | Purpose |
|--------|---------|---------|
| `imgui` | `ui.lua` | ImGui rendering API (float_wnd_create, text, button, etc.) |
| `logMsg` | `log.lua` | X-Plane log output function |
| `hid_read` | `hardware.lua` | HID device read operation |
| `hid_set_nonblocking` | `hardware.lua` | Set non-blocking mode on HID handle |
| `XPLMFindDataRef` | (implied) | Data reference lookup for X-Plane parameters |
| `dataref_table()` | `Transponder.lua`, implied elsewhere | Create writable data reference table |
| `command_once()`, `command_begin()`, `command_end()` | `dispatch.lua` | Execute XPLM commands |
| `RESOURCE_PATH` | `plugincheck.lua` | Path to X-Plane's resource/plugins directory |
| `AIRCRAFT_FILENAME` | Custom scripts | Current aircraft identifier string |
| `get()` | `Transponder.lua`, implied elsewhere | Read a data reference value |

## luacheck Inline Ignore Directives Found in Codebase

Scanning all 10 core modules reveals inline ignore directives scattered across multiple files:

- `dispatch.lua`: `-- luacheck: ignore 2143` (unused variable pattern)
- `hardware.lua`: Multiple `--[[@as function]] -- luacheck: ignore (global from FlyWithLua)` declarations for hid_read, hid_set_nonblocking
- `ui.lua`: `local imgui = imgui --[[@as table]] -- luacheck: ignore (global from FlyWithLua)`

These per-file directives should be consolidated into a project-level `.luacheckrc` file.
