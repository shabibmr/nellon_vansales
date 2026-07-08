# Script to build Flutter APK in release mode and scp to remote server.
$ErrorActionPreference = "Stop"

# Define paths
$apkPath = "E:\work\nellon\build\app\outputs\apk\release\app-nellon-release.apk"
$destination = "gm1:~/uae/ap1/"

Write-Host "==============================================" -ForegroundColor Cyan
Write-Host "Building APK in release mode..." -ForegroundColor Cyan
Write-Host "==============================================" -ForegroundColor Cyan

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
    Write-Host "APK successfully deployed to $destination" -ForegroundColor Green
    Write-Host "==============================================" -ForegroundColor Green
} else {
    Write-Error "Expected APK file not found at: $apkPath"
    exit 1
}
