# Fast production deploy: ARM64 release APK, then scp + Firestore.
#
# Same destination and Firestore update as build_and_deploy.ps1, but does not
# overwrite that script. Builds only android-arm64 (van phones) and never
# runs flutter clean.
#
# Usage:
#   pwsh -File build_and_deploy_arm64.ps1
#   pwsh -File build_and_deploy_arm64.ps1 -SkipPub
#   pwsh -File build_and_deploy_arm64.ps1 -SkipBuild
#   pwsh -File build_and_deploy_arm64.ps1 -Notes "ARM64-only sideload"

[CmdletBinding()]
param(
    [string]$SshHost = 'gm1',
    [string]$RemoteDir = '/var/www/html/algo_cloud/nellon',
    [string]$ApkName = 'app-nellon-release.apk',
    [string]$Notes = '',
    [switch]$SkipBuild,
    [switch]$SkipPub,
    [switch]$SkipFirestore
)

$ErrorActionPreference = 'Stop'
$repoRoot = $PSScriptRoot
Set-Location $repoRoot

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

$destination = "${SshHost}:${RemoteDir}/${ApkName}"
$remoteDirQuoted = $RemoteDir.Replace("'", "'\''")

Write-Host '==============================================' -ForegroundColor Cyan
Write-Host "Fast production deploy (ARM64)" -ForegroundColor Cyan
Write-Host "Repo: $repoRoot" -ForegroundColor Cyan
Write-Host "Target: $destination" -ForegroundColor Cyan
Write-Host '==============================================' -ForegroundColor Cyan

Write-Host "Verifying remote directory on $SshHost..." -ForegroundColor DarkGray
& ssh $SshHost "mkdir -p '$remoteDirQuoted'"
if ($LASTEXITCODE -ne 0) {
    Write-Error "ssh mkdir failed with exit code $LASTEXITCODE"
    exit $LASTEXITCODE
}

if (-not $SkipBuild) {
    $buildScript = Join-Path $repoRoot 'scripts\build_apk_arm64.ps1'
    $buildArgs = @{ ApkName = $ApkName }
    if ($SkipPub) { $buildArgs['SkipPub'] = $true }
    & $buildScript @buildArgs
    if ($LASTEXITCODE -ne 0) {
        Write-Error "ARM64 build failed with exit code $LASTEXITCODE"
        exit $LASTEXITCODE
    }
}

$apkPath = Find-ReleaseApk -Name $ApkName
if (-not $apkPath) {
    Write-Error "No release APK found under $repoRoot\build\app\outputs. Run without -SkipBuild."
    exit 1
}

Write-Host "`nFound release APK at: $apkPath" -ForegroundColor Green
Write-Host "Copying via scp to $destination..." -ForegroundColor Cyan
& scp $apkPath $destination
if ($LASTEXITCODE -ne 0) {
    Write-Error "scp transfer failed with exit code $LASTEXITCODE"
    exit $LASTEXITCODE
}

Write-Host "`nProduction APK deployed to $destination" -ForegroundColor Green

if ($SkipFirestore) {
    Write-Host 'Skipping Firestore version update (-SkipFirestore).' -ForegroundColor Yellow
    exit 0
}

$updater = Join-Path $repoRoot 'scripts\update_firestore_version.js'
$updaterArgs = @(
    '--channel=production',
    "--apk=$apkPath"
)
if ($Notes) {
    $updaterArgs += "--notes=$Notes"
}

Write-Host "`nUpdating production channel version metadata in Firestore..." -ForegroundColor Cyan
& node $updater @updaterArgs
if ($LASTEXITCODE -ne 0) {
    Write-Error "Firestore version update failed with exit code $LASTEXITCODE"
    exit $LASTEXITCODE
}
