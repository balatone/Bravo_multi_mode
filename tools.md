# Lua Tools

Locally accessible Lua tooling for this project.

| Tool | Version | Path | Purpose |
|------|---------|------|---------|
| **lua** | 5.4.8 PUC-Rio | `/usr/bin/lua` | Interpreter/runtime (also includes `luac` compiler) |
| **luac** | 5.4.8 PUC-Rio | `/usr/bin/luac` | Lua bytecode compiler — compiles `.lua` → `.lc` |
| **luacheck** | 1.2.0 (Lua 5.4) | `/usr/bin/luacheck` | Static analysis / linter |
| **stylua** | 2.5.2 | `/home/eb/.cargo/bin/stylua` | Opinionated Lua code formatter |

## Usage

### Run a script
```bash
lua <script.lua>
```

### Compile to bytecode
```bash
luac -o <output.lc> <script.lua>
```

### Lint for issues
```bash
luacheck <file-or-directory>
```

### Format code
```bash
stylua <file-or-directory>
```
