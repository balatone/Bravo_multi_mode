param(
  [string]$LuaPath = "FlyWithLua/Scripts/BravoMultiMode.lua",
  [string]$OutDir = "."
)

$ErrorActionPreference = 'Stop'

if (!(Test-Path -LiteralPath $LuaPath)) {
  throw "Lua file not found: $LuaPath"
}

$text = Get-Content -LiteralPath $LuaPath -Raw

# 1) All top-level global function definitions of the form:  function name(
$funcDefRx = [regex]::new('(?m)^\s*function\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(')
$functions = $funcDefRx.Matches($text) | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique

# 2) Callback entrypoints.
# FlyWithLua evaluates callback strings in the global environment.
# We extract likely entrypoint names used by:
#   - create_command(..., "name(...)", ...)
#   - do_every_frame("name(...)"), do_every_draw(...)
#   - float_wnd_set_imgui_builder(..., "name"), float_wnd_set_onclose(..., "name")

# Generic "name(" inside a quoted string (covers create_command + do_every_frame("name()"))
$cbInvokePattern = @'
["']\s*([A-Za-z_][A-Za-z0-9_]*)\s*\(
'@
$cbInvokeRx = [regex]::new($cbInvokePattern)

$callbackNamesRaw = @()
$callbackNamesRaw += $cbInvokeRx.Matches($text) | ForEach-Object { $_.Groups[1].Value }

# float window callbacks are typically *just* the function name (no parentheses)
$floatCbPattern = @'
float_wnd_set_(?:imgui_builder|onclose|onclick)\s*\([^,]*,\s*["']\s*([A-Za-z_][A-Za-z0-9_]*)\s*["']
'@
$floatCbRx = [regex]::new($floatCbPattern)
$callbackNamesRaw += $floatCbRx.Matches($text) | ForEach-Object { $_.Groups[1].Value }

# Keep only names that are actually defined as global functions in this file.
# This removes false positives like words in log strings.
$callbackNames = $callbackNamesRaw |
  Where-Object { $functions -contains $_ } |
  Sort-Object -Unique

# 3) Candidates: global `function name` but never appear to be used as callback entrypoints
$candidates = $functions | Where-Object { $callbackNames -notcontains $_ }

$report = [ordered]@{
  LuaPath              = (Resolve-Path -LiteralPath $LuaPath).Path
  FunctionCount        = $functions.Count
  CallbackNameCount    = $callbackNames.Count
  NonCallbackFuncCount = $candidates.Count
  Functions            = $functions
  CallbackNames        = $callbackNames
  NonCallbackFunctions = $candidates
}

$OutDir = (Resolve-Path -LiteralPath $OutDir).Path
$reportPath = Join-Path $OutDir "_audit_globals.json"
$report | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $reportPath -Encoding UTF8

Write-Host "Wrote report: $reportPath"
Write-Host "Functions: $($functions.Count) | Callback entrypoints: $($callbackNames.Count) | Non-callback funcs: $($candidates.Count)"

# Also write a human-readable list for quick scanning
$txtPath = Join-Path $OutDir "_audit_globals.txt"
"Functions (defined with '^function'):" | Set-Content -LiteralPath $txtPath -Encoding UTF8
$functions | ForEach-Object { "  $_" } | Add-Content -LiteralPath $txtPath -Encoding UTF8
"" | Add-Content -LiteralPath $txtPath
"Callback entrypoints (strings / float window callbacks):" | Add-Content -LiteralPath $txtPath -Encoding UTF8
$callbackNames | ForEach-Object { "  $_" } | Add-Content -LiteralPath $txtPath -Encoding UTF8
"" | Add-Content -LiteralPath $txtPath
"Non-callback function candidates:" | Add-Content -LiteralPath $txtPath -Encoding UTF8
$candidates | ForEach-Object { "  $_" } | Add-Content -LiteralPath $txtPath -Encoding UTF8

Write-Host "Wrote list:   $txtPath"
