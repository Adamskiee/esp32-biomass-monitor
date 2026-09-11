<#
.SYNOPSIS
Installs dependencies and creates an NTFS junction for the shared BiomassConfig library on Windows.
#>

$ErrorActionPreference = "Stop"

function Check-Exit {
    if ($LASTEXITCODE -ne 0) {
        throw "Command failed with exit code $LASTEXITCODE"
    }
}

# Verify arduino-cli is installed
if (-not (Get-Command "arduino-cli" -ErrorAction SilentlyContinue)) {
    throw "arduino-cli is not installed or not in your PATH. Please install it."
}

Write-Host "Installing ESP32 Core..."
arduino-cli core update-index --additional-urls https://raw.githubusercontent.com/espressif/arduino-esp32/gh-pages/package_esp32_index.json
Check-Exit
arduino-cli core install esp32:esp32@3.0.4 --additional-urls https://raw.githubusercontent.com/espressif/arduino-esp32/gh-pages/package_esp32_index.json
Check-Exit

Write-Host "Installing Libraries..."
arduino-cli lib install "Adafruit PM25 AQI Sensor@2.0.0" "DHT sensor library@1.4.7" "Adafruit Unified Sensor" "MAX6675 library@1.1.2" "ArduinoJson" "Async TCP" "ESP Async WebServer"
Check-Exit

$SecretsPath = "$PSScriptRoot\main\Secrets.h"
$SecretsExamplePath = "$PSScriptRoot\main\Secrets.h.example"
if (-not (Test-Path $SecretsPath) -and (Test-Path $SecretsExamplePath)) {
    Copy-Item $SecretsExamplePath $SecretsPath
    Write-Host "Created Secrets.h from example"
}

$SourceDir = "$PSScriptRoot\shared\BiomassConfig"
if (-not (Test-Path $SourceDir)) {
    throw "Source library directory not found at $SourceDir"
}

$SketchbookDir = $null
try {
    $JsonConfig = arduino-cli config dump --format json 2>$null | ConvertFrom-Json
    $SketchbookDir = $JsonConfig.directories.user
} catch {
    Write-Host "Failed to parse arduino-cli config dump."
}

if ([string]::IsNullOrWhiteSpace($SketchbookDir)) {
    $SketchbookDir = "$env:USERPROFILE\Documents\Arduino"
    Write-Host "Could not parse sketchbook from config. Using default: $SketchbookDir"
}

$LibsDir = "$SketchbookDir\libraries"
if (-not (Test-Path $LibsDir)) {
    New-Item -ItemType Directory -Path $LibsDir | Out-Null
}

$Dest = "$LibsDir\BiomassConfig"
Write-Host "Linking BiomassConfig to $Dest..."

# Safe Junction replacement logic (works even if junction is broken)
$item = Get-Item $Dest -Force -ErrorAction SilentlyContinue
$isJunction = ($null -ne $item) -and ($item.Attributes -match "ReparsePoint")

if ($null -ne $item) {
    if ($isJunction) {
        # PS5.1 Remove-Item deletes target files. Use cmd rmdir instead for safety.
        cmd.exe /c "rmdir `"$Dest`""
    } else {
        Write-Host "Removing existing non-junction library directory..."
        Remove-Item -Recurse -Force $Dest
    }
}

New-Item -ItemType Junction -Path $Dest -Target $SourceDir -Force | Out-Null
Write-Host "Done."
