# Fast release APK: ARM64 only, no flutter clean, no build_runner.
#
# Van phones are arm64-v8a. The old `flutter build apk --release` compiles
# three ABIs (armeabi-v7a + arm64-v8a + x86_64). This script builds one.
#
# Usage:
#   pwsh -File scripts/build_apk_arm64.ps1
#   pwsh -File scripts/build_apk_arm64.ps1 -SkipPub
#   pwsh -File scripts/build_apk_arm64.ps1 -ApkName app-nellon-release.apk
#
# Does not replace build_and_deploy.ps1 or test_deploy.ps1.

[CmdletBinding()]
param(
    [string]$ApkName = 'app-nellon-release.apk',
    [switch]$SkipPub
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $repoRoot

function Log-StepStart {
    param([string]$Message)
    $ts = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    Write-Host "`n[$ts] >>> $Message" -ForegroundColor Cyan
    return [System.Diagnostics.Stopwatch]::StartNew()
}

function Log-StepEnd {
    param(
        [string]$Message,
        [System.Diagnostics.Stopwatch]$Stopwatch
    )
    $Stopwatch.Stop()
    $ts = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $elapsed = $Stopwatch.Elapsed
    $elapsedFormatted = "{0:D2}m {1:D2}s ({2:N2}s total)" -f [int]$elapsed.TotalMinutes, $elapsed.Seconds, $elapsed.TotalSeconds
    Write-Host "[$ts] <<< Finished: $Message [Elapsed: $elapsedFormatted]" -ForegroundColor Green
}

function Find-ReleaseApk {
    param([string]$Name)

    $candidates = @(
        (Join-Path $repoRoot "build\app\outputs\flutter-apk\$Name"),
        (Join-Path $repoRoot "build\app\outputs\apk\release\$Name"),
        (Join-Path $repoRoot 'build\app\outputs\flutter-apk\app-release.apk'),
        (Join-Path $repoRoot 'build\app\outputs\apk\release\app-release.apk')
    )
    foreach ($path in $candidates) {
        if (Test-Path -LiteralPath $path) {
            return (Resolve-Path -LiteralPath $path).Path
        }
    }
    return $null
}

$totalSw = [System.Diagnostics.Stopwatch]::StartNew()
$scriptStartTs = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")

Write-Host '==============================================' -ForegroundColor Cyan
Write-Host "[$scriptStartTs] Fast ARM64 release build (no clean)" -ForegroundColor Cyan
Write-Host "Repo: $repoRoot" -ForegroundColor Cyan
Write-Host '==============================================' -ForegroundColor Cyan

$flutterArgs = @(
    'build', 'apk',
    '--release',
    '--target-platform', 'android-arm64'
)
if ($SkipPub) {
    $flutterArgs += '--no-pub'
}

# Step 1: Execute Flutter build
$step1Sw = Log-StepStart "Executing 'flutter $($flutterArgs -join ' ')'..."
& flutter @flutterArgs
if ($LASTEXITCODE -ne 0) {
    Write-Error "Flutter ARM64 build failed with exit code $LASTEXITCODE"
    exit $LASTEXITCODE
}
Log-StepEnd "Flutter ARM64 build" $step1Sw

# Step 2: Locate and inspect generated APK
$step2Sw = Log-StepStart "Verifying generated release APK ($ApkName)..."
$apkPath = Find-ReleaseApk -Name $ApkName
if (-not $apkPath) {
    Write-Error "No release APK found under $repoRoot\build\app\outputs after ARM64 build."
    exit 1
}
$sizeMb = [math]::Round((Get-Item -LiteralPath $apkPath).Length / 1MB, 1)
Log-StepEnd "Verifying generated release APK" $step2Sw

$totalSw.Stop()
$totalElapsed = $totalSw.Elapsed
$scriptEndTs = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
$totalElapsedFormatted = "{0:D2}m {1:D2}s ({2:N2}s total)" -f [int]$totalElapsed.TotalMinutes, $totalElapsed.Seconds, $totalElapsed.TotalSeconds

Write-Host "`nARM64 APK: $apkPath" -ForegroundColor Green
Write-Host "Size: ${sizeMb} MB" -ForegroundColor Green
Write-Host "[$scriptEndTs] Build completed! [Total Elapsed: $totalElapsedFormatted]" -ForegroundColor Green
