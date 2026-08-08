# ************************************************
# link_aircraft_configs.ps1
#
# Creates symbolic links from Bravo++ config files
# (stored centrally in the conf folder) into each
# X-Plane aircraft directory so the script can find
# them at runtime without copying.
#
# Usage:
#   $env:X_PLANE_INSTALL = "D:\X-Plane 12"
#   .\link_aircraft_configs.ps1
#
# Or with an explicit path:
#   .\link_aircraft_configs.ps1 -XPlaneInstall "D:\X-Plane 12"
# ************************************************

param(
    [string]$XPlaneInstall = $env:X_PLANE_INSTALL,
    [switch]$NonInteractive
)

# ---------- Interactive prompt helper ------------
function Prompt-User($message, $choices) {
    Write-Host ""
    Write-Host $message
    Write-Host ""
    for ($i = 0; $i -lt $choices.Length; $i++) {
        Write-Host "  [$($choices[$i].Key)] $($choices[$i].Value)"
    }
    Write-Host ""

    while ($true) {
        $input = Read-Host "Select an option"
        for ($i = 0; $i -lt $choices.Length; $i++) {
            if ($input -eq $choices[$i].Key -or $input.ToLower() -eq $choices[$i].Value.ToLower()) {
                return $choices[$i].Result
            }
        }
        Write-Host "Invalid selection. Try again." -ForegroundColor Yellow
    }
}

$ErrorActionPreference = "Continue"

# ---------- Validate environment ----------------

if (-not $XPlaneInstall) {
    Write-Error "X-Plane install path is not set. Either set `$env:X_PLANE_INSTALL or pass -XPlaneInstall."
    exit 1
}

if (-not (Test-Path $XPlaneInstall)) {
    Write-Error "X-Plane install path does not exist: $XPlaneInstall"
    exit 1
}

$confDir = Join-Path $XPlaneInstall "Resources\plugins\FlyWithLua\Modules\bravo++\conf"
$aircraftDir = Join-Path $XPlaneInstall "Aircraft"

if (-not (Test-Path $confDir)) {
    Write-Error "Config directory does not exist: $confDir"
    exit 1
}

if (-not (Test-Path $aircraftDir)) {
    Write-Error "Aircraft directory does not exist: $aircraftDir"
    exit 1
}

# ---------- Configs to skip ----------------------
$skipConfigs = @(
    "bravo_multi-mode.g1000.cfg"
    "bravo_multi-mode.gns530_430.cfg"
)

# ---------- Discover config files ---------------

$allConfigs = @(Get-ChildItem -Path $confDir -Filter "bravo_multi-mode*.cfg" -File)
$configFiles = @($allConfigs | Where-Object { $_.Name -notin $skipConfigs })

if ($configFiles.Count -eq 0 -and $allConfigs.Count -eq 0) {
    Write-Warning "No bravo_multi-mode*.cfg files found in $confDir"
    exit 0
}

$skippedNames = @($skipConfigs | Where-Object { $_ -in $allConfigs.Name })
if ($skippedNames.Count -gt 0) {
    Write-Host "Skipping $($skippedNames.Count) reference config(s): $($skippedNames -join ', ')"
}

Write-Host "Found $($configFiles.Count) config file(s) to link in $confDir"

# ---------- Discover aircraft folders ------------

$aircraftInfo = @()

$folders = @(Get-ChildItem -Path $aircraftDir -Directory -Recurse)
foreach ($folder in $folders) {
    $acfFiles = @(Get-ChildItem -Path $folder.FullName -Filter "*.acf" -File -ErrorAction SilentlyContinue)
    if ($acfFiles.Count -eq 0) { continue }

    foreach ($acfFile in $acfFiles) {
        $acfName = $null
        $content = Get-Content -Path $acfFile.FullName -Raw -ErrorAction SilentlyContinue
        if ($content -and ($content -match '(?m)^P\s+acf/_name\s+(.+)$')) {
            $acfName = $Matches[1].Trim()
        }

        if (-not $acfName) {
            $acfName = [System.IO.Path]::GetFileNameWithoutExtension($acfFile.Name)
        }

        $acfBase = [System.IO.Path]::GetFileNameWithoutExtension($acfFile.Name)

        $aircraftInfo += [PSCustomObject]@{
            Folder = $folder.FullName
            Name   = $acfName
            Base   = $acfBase
        }
    }
}

Write-Host "Found $($aircraftInfo.Count) aircraft folder(s) in $aircraftDir"

# ---------- Build config list --------------------

$configs = @()
foreach ($cfg in $configFiles) {
    $id = $cfg.Name -replace "^bravo_multi-mode\.?(.*)\.cfg$", '$1'
    $parts = if ([string]::IsNullOrWhiteSpace($id)) { @() } else { @($id.Split(".")) }
    $configs += [PSCustomObject]@{
        File  = $cfg
        Name  = $cfg.Name
        Parts = $parts
    }
}

# ---------- Match configs to aircraft ------------

$linked = 0
$skipped = 0
$errCount = 0

foreach ($ac in $aircraftInfo) {
    $bestConfig = $null
    $bestScore = -1

    foreach ($c in $configs) {
        $parts = @($c.Parts)

        if ($parts.Count -eq 0) {
            if ($bestScore -lt 0) {
                $bestConfig = $c
                $bestScore = 0
            }
            continue
        }

        if ($parts[0].ToLower() -ne $ac.Base.ToLower()) {
            continue
        }

        $acfNameLower = $ac.Name.ToLower()
        $allVariantsMatch = $true
        for ($i = 1; $i -lt $parts.Count; $i++) {
            if ($acfNameLower -notlike "*$($parts[$i].ToLower())*") {
                $allVariantsMatch = $false
                break
            }
        }

        if ($allVariantsMatch) {
            if ($parts.Count -gt $bestScore) {
                $bestConfig = $c
                $bestScore = $parts.Count
            }
        }
    }

    if (-not $bestConfig) {
        Write-Host "  No config for $($ac.Name) - not linked" -ForegroundColor DarkGray
        $skipped++
        continue
    }

    $linkPath = Join-Path $ac.Folder $bestConfig.Name
    $shouldLink = $true

    if (Test-Path $linkPath -PathType Any) {
        if ((Get-Item $linkPath).Attributes -match "ReparsePoint") {
            $removeError = $null
            Remove-Item $linkPath -Force -ErrorVariable removeError
            if ($removeError) {
                Write-Host "Error: Failed to remove existing symlink $linkPath : $removeError" -ForegroundColor Red
                $errCount++
                $shouldLink = $false
            }
            else {
                Write-Host "  Replaced: $linkPath"
            }
        }
        else {
            $bakPath = "${linkPath}.bak"

            if (Test-Path $bakPath) {
                if ($NonInteractive) {
                    Write-Host "  Skipped: $linkPath (backup exists, non-interactive mode)" -ForegroundColor DarkGray
                    $skipped++
                    $shouldLink = $false
                }
                else {
                    $promptMsg = "Backup already exists: $($bakPath)`nAircraft: $($ac.Name)"
                    $promptChoices = @(
                        @{ Key = "Y"; Value = "Overwrite"; Result = "overwrite" }
                        @{ Key = "S"; Value = "Skip this aircraft"; Result = "skip" }
                        @{ Key = "Q"; Value = "Quit"; Result = "quit" }
                    )
                    $choice = Prompt-User -message $promptMsg -choices $promptChoices

                    if ($choice -eq "quit") {
                        Write-Host "Aborted by user." -ForegroundColor Yellow
                        exit 0
                    }
                    elseif ($choice -eq "skip") {
                        Write-Host "  Skipped: $linkPath" -ForegroundColor DarkGray
                        $skipped++
                        $shouldLink = $false
                    }
                    elseif ($choice -eq "overwrite") {
                        $copyError = $null
                        Copy-Item $linkPath $bakPath -Force -ErrorVariable copyError
                        if ($copyError) {
                            Write-Host "Error: Failed to backup $linkPath : $copyError" -ForegroundColor Red
                            $errCount++
                            $shouldLink = $false
                        }
                        else {
                            $removeError = $null
                            Remove-Item $linkPath -Force -ErrorVariable removeError
                            if ($removeError) {
                                Write-Host "Error: Failed to remove $linkPath : $removeError" -ForegroundColor Red
                                $errCount++
                                $shouldLink = $false
                            }
                            else {
                                Write-Host "  Overwrote backup: $bakPath"
                            }
                        }
                    }
                }
            }
            else {
                $copyError = $null
                Copy-Item $linkPath $bakPath -Force -ErrorVariable copyError
                if ($copyError) {
                    Write-Host "Error: Failed to backup $linkPath : $copyError" -ForegroundColor Red
                    $errCount++
                    $shouldLink = $false
                }
                else {
                    $removeError = $null
                    Remove-Item $linkPath -Force -ErrorVariable removeError
                    if ($removeError) {
                        Write-Host "Error: Failed to remove $linkPath : $removeError" -ForegroundColor Red
                        $errCount++
                        $shouldLink = $false
                    }
                    else {
                        Write-Host "  Backed up: $bakPath"
                    }
                }
            }
        }
    }

    if ($shouldLink) {
        $linkError = $null
        New-Item -ItemType SymbolicLink -Path $linkPath -Target $bestConfig.File.FullName -Force -ErrorVariable linkError | Out-Null

        if ($linkError) {
            Write-Host "Error: Failed to create symlink $linkPath : $linkError" -ForegroundColor Red
            $errCount++
        }
        else {
            Write-Host "  Linked: $($bestConfig.Name) -> $($ac.Name)"
            $linked++
        }
    }
}

# ---------- Report unmatched configs -------------

$linkedNames = @()
Get-ChildItem -Path $aircraftDir -Recurse -Filter "bravo_multi-mode*.cfg" -File -ErrorAction SilentlyContinue | ForEach-Object {
    $linkedNames += $_.Name
}

foreach ($c in $configs) {
    if ($c.Name -notin $linkedNames) {
        Write-Host "  Unlinked: $($c.Name) (no matching aircraft)" -ForegroundColor DarkGray
        $skipped++
    }
}

# ---------- Summary ------------------------------

Write-Host ""
Write-Host "=== Summary ==="
Write-Host "  Linked  : $linked"
Write-Host "  Skipped : $skipped"
Write-Host "  Errors  : $errCount"

if ($errCount -gt 0) {
    exit 1
}
