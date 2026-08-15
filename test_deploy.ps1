# Script to build Flutter APK in release mode and deploy to the isolated TEST folder.
$ErrorActionPreference = "Stop"

# Define paths
$apkPath = "E:\work\nellon\build\app\outputs\apk\release\app-nellon-release.apk"
$destination = "gm1:/var/www/html/algo_cloud/nellon/test/app-nellon-release.apk"

Write-Host "==============================================" -ForegroundColor Cyan
Write-Host "Building Test APK in release mode..." -ForegroundColor Cyan
Write-Host "==============================================" -ForegroundColor Cyan

# Ensure test folder exists on VPS
Write-Host "Verifying remote test directory on gm1..." -ForegroundColor DarkGray
& ssh gm1 "mkdir -p /var/www/html/algo_cloud/nellon/test"

# Run Flutter build apk --release
& flutter build apk --release

if ($LASTEXITCODE -ne 0) {
    Write-Error "Flutter build failed with exit code $LASTEXITCODE"
    exit $LASTEXITCODE
}

Write-Host "`n==============================================" -ForegroundColor Green
Write-Host "Flutter build completed successfully." -ForegroundColor Green
Write-Host "==============================================" -ForegroundColor Green

# Verify APK exists
if (Test-Path -Path $apkPath) {
    Write-Host "`nFound release APK at: $apkPath" -ForegroundColor Green
    Write-Host "Preparing to copy APK via scp to $destination..." -ForegroundColor Cyan
    
    # Run scp command
    & scp $apkPath $destination
    
    if ($LASTEXITCODE -ne 0) {
        Write-Error "scp transfer failed with exit code $LASTEXITCODE"
        exit $LASTEXITCODE
    }
    
    Write-Host "`n==============================================" -ForegroundColor Green
    Write-Host "Test APK successfully deployed to $destination" -ForegroundColor Green
    Write-Host "==============================================" -ForegroundColor Green

    # Automatically update BETA version metadata in Firestore
    Write-Host "`nUpdating BETA channel version metadata in Firebase Firestore..." -ForegroundColor Cyan
    & node scripts/update_firestore_version.js --channel=beta
} else {
    Write-Error "Expected APK file not found at: $apkPath"
    exit 1
}
