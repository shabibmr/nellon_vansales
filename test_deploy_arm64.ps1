# Fast test/beta deploy: ARM64 release APK, then scp + Firestore.
#
# Same flags and defaults as test_deploy.ps1. Does not overwrite that script.
# Builds only android-arm64 and never runs flutter clean.
#
# Usage:
#   pwsh -File test_deploy_arm64.ps1
#   pwsh -File test_deploy_arm64.ps1 -SkipPub
#   pwsh -File test_deploy_arm64.ps1 -SkipBuild
#   pwsh -File test_deploy_arm64.ps1 -SshHost gm1 -RemoteDir /var/www/html/algo_cloud/nellon/test

[CmdletBinding()]
param(
    [string]$SshHost = 'gm1',
    [string]$RemoteDir = '/var/www/html/algo_cloud/nellon/test',
    [string]$ApkName = 'app-nellon-release.apk',
    [ValidateSet('beta', 'test', 'production')]
    [string]$Channel = 'beta',
    [string]$Notes = '',
    [switch]$SkipBuild,
    [switch]$SkipPub,
    [switch]$SkipFirestore
)

$ErrorActionPreference = 'Stop'
$repoRoot = $PSScriptRoot
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
$destination = "${SshHost}:${RemoteDir}/${ApkName}"
$remoteDirQuoted = $RemoteDir.Replace("'", "'\''")

Write-Host '==============================================' -ForegroundColor Cyan
Write-Host "[$scriptStartTs] Fast test deploy (ARM64)" -ForegroundColor Cyan
Write-Host "Repo: $repoRoot" -ForegroundColor Cyan
Write-Host "Target: $destination" -ForegroundColor Cyan
Write-Host '==============================================' -ForegroundColor Cyan

# Step 1: Verify remote directory
$step1Sw = Log-StepStart "Verifying remote test directory on $SshHost..."
& ssh $SshHost "mkdir -p '$remoteDirQuoted'"
if ($LASTEXITCODE -ne 0) {
    Write-Error "ssh mkdir failed with exit code $LASTEXITCODE"
    exit $LASTEXITCODE
}
Log-StepEnd "Verifying remote test directory" $step1Sw

# Step 2: Build ARM64 APK
if (-not $SkipBuild) {
    $step2Sw = Log-StepStart "Building ARM64 release APK..."
    $buildScript = Join-Path $repoRoot 'scripts\build_apk_arm64.ps1'
    $buildArgs = @{ ApkName = $ApkName }
    if ($SkipPub) { $buildArgs['SkipPub'] = $true }
    & $buildScript @buildArgs
    if ($LASTEXITCODE -ne 0) {
        Write-Error "ARM64 build failed with exit code $LASTEXITCODE"
        exit $LASTEXITCODE
    }
    Log-StepEnd "Building ARM64 release APK" $step2Sw
} else {
    Write-Host "`nSkipping build (-SkipBuild)." -ForegroundColor Yellow
}

# Step 3: Find release APK
$step3Sw = Log-StepStart "Locating release APK ($ApkName)..."
$apkPath = Find-ReleaseApk -Name $ApkName
if (-not $apkPath) {
    Write-Error "No release APK found under $repoRoot\build\app\outputs. Run without -SkipBuild, or pass a built tree."
    exit 1
}
Log-StepEnd "Locating release APK ($apkPath)" $step3Sw

# Step 4: Transfer APK via scp
$step4Sw = Log-StepStart "Copying APK via scp to $destination..."
& scp $apkPath $destination
if ($LASTEXITCODE -ne 0) {
    Write-Error "scp transfer failed with exit code $LASTEXITCODE"
    exit $LASTEXITCODE
}
Log-StepEnd "Copying APK via scp to $destination" $step4Sw
Write-Host "`nTest APK deployed to $destination" -ForegroundColor Green

# Step 5: Update Firestore metadata
if ($SkipFirestore) {
    Write-Host "`nSkipping Firestore version update (-SkipFirestore)." -ForegroundColor Yellow
} else {
    $updater = Join-Path $repoRoot 'scripts\update_firestore_version.js'
    $updaterArgs = @(
        "--channel=$Channel",
        "--apk=$apkPath"
    )
    if ($Notes) {
        $updaterArgs += "--notes=$Notes"
    }

    $step5Sw = Log-StepStart "Updating $Channel channel version metadata in Firestore..."
    & node $updater @updaterArgs
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Firestore version update failed with exit code $LASTEXITCODE"
        exit $LASTEXITCODE
    }
    Log-StepEnd "Updating Firestore version metadata" $step5Sw
}

$totalSw.Stop()
$totalElapsed = $totalSw.Elapsed
$scriptEndTs = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
$totalElapsedFormatted = "{0:D2}m {1:D2}s ({2:N2}s total)" -f [int]$totalElapsed.TotalMinutes, $totalElapsed.Seconds, $totalElapsed.TotalSeconds
Write-Host "`n==============================================" -ForegroundColor Green
Write-Host "[$scriptEndTs] Fast test deploy complete! [Total Elapsed: $totalElapsedFormatted]" -ForegroundColor Green
Write-Host "==============================================" -ForegroundColor Green
