param(
  [string]$Path = 'FlyWithLua/Scripts/BravoMultiMode.lua'
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $Path)) {
  throw "File not found: $Path"
}

# Read the file as a single string so we can do a single regex replacement.
$content = Get-Content -LiteralPath $Path -Raw

# Replace everything from "-- Autopilot button" up to (but not including) the LED HANDLING section.
$pattern = '(?s)-- Autopilot button.*?(?=\r?\n--------------------------------------\r?\n---- LED HANDLING)'

$replacement = @'
-- Autopilot panel buttons
-- FlyWithLua executes callback strings in the global environment. Keep the
-- routing functions global and route the work to locals.
function bravo_button_begin(button_name)
    return try_catch(function() start_timer(button_name) end, 'bravo_button_begin')
end

function bravo_button_continue(button_name)
    return try_catch(function() handle_continuous_mode(button_name) end, 'bravo_button_continue')
end

function bravo_button_end(button_name)
    return try_catch(function() handle_single_click_mode(button_name) end, 'bravo_button_end')
end

local ap_buttons = {
    { key = 'PLT', command = 'autopilot_button', description = 'AUTOPILOT' },
    { key = 'IAS', command = 'ias_button',        description = 'IAS' },
    { key = 'VS',  command = 'vs_button',         description = 'VS' },
    { key = 'ALT', command = 'alt_button',        description = 'ALT' },
    { key = 'REV', command = 'rev_button',        description = 'REV' },
    { key = 'APR', command = 'apr_button',        description = 'APR' },
    { key = 'NAV', command = 'nav_button',        description = 'NAV' },
    { key = 'HDG', command = 'hdg_button',        description = 'HDG' },
}

for _, b in ipairs(ap_buttons) do
    create_command(
        'FlyWithLua/Bravo++/' .. b.command,
        'Bravo++ toggles ' .. b.description .. ' button',
        string.format("bravo_button_begin('%s')", b.key),
        string.format("bravo_button_continue('%s')", b.key),
        string.format("bravo_button_end('%s')", b.key)
    )
end

'@

$new = [regex]::Replace($content, $pattern, $replacement, 1)

if ($new -eq $content) {
  throw "Pattern not found or no changes made. Pattern: $pattern"
}

# Write back as UTF-8 (PowerShell's utf8 includes BOM, which is generally fine for Lua).
Set-Content -LiteralPath $Path -Value $new -Encoding utf8

Write-Host "Step 3 applied: consolidated autopilot button handlers into bravo_button_begin/continue/end."
