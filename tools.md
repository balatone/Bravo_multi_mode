# Lua Tools

Locally accessible Lua tooling for this project.

| Tool | Version | Path | Purpose |
|------|---------|------|---------|
| **lua55** | 5.5.0 | `C:\apps\lua\lua55.exe` | Interpreter/runtime (also includes `luac55.exe` compiler) |
| **luacheck** | 0.23.0 | `C:\Util\luacheck.exe` | Static analysis / linter (Lua 5.3 runtime) |
| **stylua** | 2.4.1 | `C:\Users\eb\.local\bin\stylua.exe` | Opinionated code formatter |

## Usage

### Run a script
```bash
C:\apps\lua\lua55.exe <script.lua>
```

### Compile to bytecode
```bash
C:\apps\lua\luac55.exe -o <output.lc> <script.lua>
```

### Lint for issues
```bash
C:\Util\luacheck.exe <file-or-directory>
```

### Format code
```bash
C:\Users\eb\.local\bin\stylua.exe <file-or-directory>
```
