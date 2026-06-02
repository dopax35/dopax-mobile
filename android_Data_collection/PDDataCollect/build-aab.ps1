# =============================================================================
# DopaX (com.pdcollect.app) - Android App Bundle build script for Windows.
# Run from this directory:   .\build-aab.ps1
#
# Produces:
#   app\build\outputs\bundle\release\app-release.aab
#   app\build\outputs\mapping\release\mapping.txt
# =============================================================================

$ErrorActionPreference = "Stop"

function Invoke-GradleStep {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Label,
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    Write-Host $Label -ForegroundColor Cyan
    & .\gradlew.bat @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Gradle step failed: $($Arguments -join ' ')"
    }
}

if (-not (Test-Path ".\app\build.gradle.kts")) {
    Write-Error "Run this from the PDDataCollect directory."
}

if (-not (Test-Path ".\local.properties")) {
    Write-Error "local.properties is missing. Point sdk.dir at your Android SDK."
}

if (-not (Test-Path ".\app\keystore.properties")) {
    Write-Error "app\\keystore.properties is missing. Add local-only release signing credentials before building."
}

Invoke-GradleStep -Label "==> Cleaning previous build outputs..." -Arguments @("clean")
Invoke-GradleStep -Label "==> Running lint (release variant)..." -Arguments @(":app:lintRelease")
Invoke-GradleStep -Label "==> Running unit tests..." -Arguments @(":app:testReleaseUnitTest")
Invoke-GradleStep -Label "==> Assembling release AAB..." -Arguments @(":app:bundleRelease", "--stacktrace")

$aab = ".\app\build\outputs\bundle\release\app-release.aab"
$mapping = ".\app\build\outputs\mapping\release\mapping.txt"

if (Test-Path $aab) {
    $size = [math]::Round((Get-Item $aab).Length / 1MB, 2)
    Write-Host ""
    Write-Host "================================================================" -ForegroundColor Green
    Write-Host "  AAB built successfully" -ForegroundColor Green
    Write-Host "  Path:    $aab" -ForegroundColor Green
    Write-Host "  Size:    $size MB" -ForegroundColor Green
    if (Test-Path $mapping) {
        Write-Host "  Mapping: $mapping" -ForegroundColor Green
        Write-Host "  Upload mapping.txt to Play Console alongside the AAB." -ForegroundColor Gray
    }
    Write-Host "================================================================" -ForegroundColor Green
} else {
    Write-Error "Build did not produce an AAB. Check the Gradle output above."
}
