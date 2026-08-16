# Script to promote the validated test build directly to PRODUCTION.
$ErrorActionPreference = "Stop"

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

$totalSw = [System.Diagnostics.Stopwatch]::StartNew()
$scriptStartTs = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")

Write-Host "==============================================" -ForegroundColor Yellow
Write-Host "[$scriptStartTs] Promoting Test APK to PRODUCTION on VPS..." -ForegroundColor Yellow
Write-Host "==============================================" -ForegroundColor Yellow

# Step 1: Copy test APK to production root on VPS
$sourcePath = "/var/www/html/algo_cloud/nellon/test/app-nellon-release.apk"
$targetPath = "/var/www/html/algo_cloud/nellon/app-nellon-release.apk"

$step1Sw = Log-StepStart "Copying remote APK: $sourcePath -> $targetPath on VPS..."
& ssh gm1 "cp $sourcePath $targetPath"

if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to promote APK on VPS (exit code $LASTEXITCODE)"
    exit $LASTEXITCODE
}
Log-StepEnd "Copying remote APK to production" $step1Sw

Write-Host "`n==============================================" -ForegroundColor Green
Write-Host "Production APK is now live on VPS!" -ForegroundColor Green
Write-Host "==============================================" -ForegroundColor Green

# Step 2: Update Production Firestore metadata
$step2Sw = Log-StepStart "Updating PRODUCTION channel version in Firebase Firestore..."
& node scripts/update_firestore_version.js --channel=production
if ($LASTEXITCODE -ne 0) {
    Write-Error "Firestore version update failed with exit code $LASTEXITCODE"
    exit $LASTEXITCODE
}
Log-StepEnd "Updating PRODUCTION channel version in Firestore" $step2Sw

$totalSw.Stop()
$totalElapsed = $totalSw.Elapsed
$scriptEndTs = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
$totalElapsedFormatted = "{0:D2}m {1:D2}s ({2:N2}s total)" -f [int]$totalElapsed.TotalMinutes, $totalElapsed.Seconds, $totalElapsed.TotalSeconds

Write-Host "`n==============================================" -ForegroundColor Green
Write-Host "[$scriptEndTs] SUCCESS: Release is active for all production users! [Total Elapsed: $totalElapsedFormatted]" -ForegroundColor Green
Write-Host "==============================================" -ForegroundColor Green
