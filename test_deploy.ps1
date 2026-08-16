# Build a release APK from this repo and deploy it to the VPS test folder.
#
# Paths are relative to this script, so it works from any clone (nellon, nell_2, …).
# Override host / remote dir / APK name / channel when needed:
#   pwsh -File test_deploy.ps1
#   pwsh -File test_deploy.ps1 -SshHost gm1 -RemoteDir /var/www/html/algo_cloud/nellon/test
#   pwsh -File test_deploy.ps1 -SkipBuild

[CmdletBinding()]
param(
    [string]$SshHost = 'gm1',
    [string]$RemoteDir = '/var/www/html/algo_cloud/nellon/test',
    [string]$ApkName = 'app-nellon-release.apk',
    [ValidateSet('beta', 'test', 'production')]
    [string]$Channel = 'beta',
    [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'
$repoRoot = $PSScriptRoot
Set-Location $repoRoot

function Find-ReleaseApk {
    param([string]$Name)

    $candidates = @(
        (Join-Path $repoRoot "build\app\outputs\apk\release\$Name"),
        (Join-Path $repoRoot "build\app\outputs\flutter-apk\$Name"),
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
Write-Host "Repo: $repoRoot" -ForegroundColor Cyan
Write-Host "Target: $destination" -ForegroundColor Cyan
Write-Host '==============================================' -ForegroundColor Cyan

Write-Host "Verifying remote test directory on $SshHost..." -ForegroundColor DarkGray
& ssh $SshHost "mkdir -p '$remoteDirQuoted'"
if ($LASTEXITCODE -ne 0) {
    Write-Error "ssh mkdir failed with exit code $LASTEXITCODE"
    exit $LASTEXITCODE
}

if (-not $SkipBuild) {
    Write-Host 'Building Test APK in release mode...' -ForegroundColor Cyan
    & flutter build apk --release
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Flutter build failed with exit code $LASTEXITCODE"
        exit $LASTEXITCODE
    }
    Write-Host "`nFlutter build completed successfully." -ForegroundColor Green
}

$apkPath = Find-ReleaseApk -Name $ApkName
if (-not $apkPath) {
    Write-Error "No release APK found under $repoRoot\build\app\outputs. Run without -SkipBuild, or pass a built tree."
    exit 1
}

Write-Host "`nFound release APK at: $apkPath" -ForegroundColor Green
Write-Host "Copying via scp to $destination..." -ForegroundColor Cyan
& scp $apkPath $destination
if ($LASTEXITCODE -ne 0) {
    Write-Error "scp transfer failed with exit code $LASTEXITCODE"
    exit $LASTEXITCODE
}

Write-Host "`nTest APK deployed to $destination" -ForegroundColor Green

$updater = Join-Path $repoRoot 'scripts\update_firestore_version.js'
Write-Host "`nUpdating $Channel channel version metadata in Firestore..." -ForegroundColor Cyan
& node $updater "--channel=$Channel" "--apk=$apkPath"
if ($LASTEXITCODE -ne 0) {
    Write-Error "Firestore version update failed with exit code $LASTEXITCODE"
    exit $LASTEXITCODE
}
