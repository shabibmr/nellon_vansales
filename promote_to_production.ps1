# Script to promote the validated test build directly to PRODUCTION.
$ErrorActionPreference = "Stop"

Write-Host "==============================================" -ForegroundColor Yellow
Write-Host "Promoting Test APK to PRODUCTION on VPS..." -ForegroundColor Yellow
Write-Host "==============================================" -ForegroundColor Yellow

# 1. Copy test APK to production root on VPS
$sourcePath = "/var/www/html/algo_cloud/nellon/test/app-nellon-release.apk"
$targetPath = "/var/www/html/algo_cloud/nellon/app-nellon-release.apk"

Write-Host "Copying remote APK: $sourcePath -> $targetPath" -ForegroundColor Cyan
& ssh gm1 "cp $sourcePath $targetPath"

if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to promote APK on VPS (exit code $LASTEXITCODE)"
    exit $LASTEXITCODE
}

Write-Host "`n==============================================" -ForegroundColor Green
Write-Host "Production APK is now live on VPS!" -ForegroundColor Green
Write-Host "==============================================" -ForegroundColor Green

# 2. Update Production Firestore metadata
Write-Host "`nUpdating PRODUCTION channel version in Firebase Firestore..." -ForegroundColor Cyan
& node scripts/update_firestore_version.js --channel=production

Write-Host "`n==============================================" -ForegroundColor Green
Write-Host "SUCCESS: Release is now active for all production users!" -ForegroundColor Green
Write-Host "==============================================" -ForegroundColor Green
