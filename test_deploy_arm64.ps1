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

function Find-ApkSigner {
    $cmd = Get-Command 'apksigner' -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }

    $sdkDirs = @()
    if (Test-Path (Join-Path $repoRoot 'android\local.properties')) {
        $props = Get-Content (Join-Path $repoRoot 'android\local.properties')
        foreach ($line in $props) {
            if ($line -match '^sdk\.dir\s*=\s*(.+)$') {
                $rawDir = $matches[1].Trim().Replace('\\', '\')
                $sdkDirs += $rawDir
            }
        }
    }
    if ($env:ANDROID_HOME) { $sdkDirs += $env:ANDROID_HOME }
    if ($env:ANDROID_SDK_ROOT) { $sdkDirs += $env:ANDROID_SDK_ROOT }
    $sdkDirs += 'E:\Android\AppData\Sdk'
    $sdkDirs += "$env:LOCALAPPDATA\Android\Sdk"

    foreach ($sdk in $sdkDirs) {
        $buildTools = Join-Path $sdk 'build-tools'
        if (Test-Path $buildTools) {
            $versions = Get-ChildItem -Directory $buildTools | Sort-Object Name -Descending
            foreach ($ver in $versions) {
                $candidateBat = Join-Path $ver.FullName 'apksigner.bat'
                if (Test-Path $candidateBat) { return $candidateBat }
                $candidateExe = Join-Path $ver.FullName 'apksigner.exe'
                if (Test-Path $candidateExe) { return $candidateExe }
                $candidateBin = Join-Path $ver.FullName 'apksigner'
                if (Test-Path $candidateBin) { return $candidateBin }
            }
        }
    }
    return $null
}

function Get-KeystoreConfig {
    $keyPropsFile = Join-Path $repoRoot 'android\key.properties'
    if (-not (Test-Path $keyPropsFile)) {
        return $null
    }
    $props = @{}
    Get-Content $keyPropsFile | ForEach-Object {
        $line = $_.Trim()
        if ($line -and -not $line.StartsWith('#') -and $line.Contains('=')) {
            $idx = $line.IndexOf('=')
            $k = $line.Substring(0, $idx).Trim()
            $v = $line.Substring($idx + 1).Trim()
            $props[$k] = $v
        }
    }
    return $props
}

# Step 3: Find release APK
$step3Sw = Log-StepStart "Locating release APK ($ApkName)..."
$apkPath = Find-ReleaseApk -Name $ApkName
if (-not $apkPath) {
    Write-Error "No release APK found under $repoRoot\build\app\outputs. Run without -SkipBuild, or pass a built tree."
    exit 1
}
Log-StepEnd "Locating release APK ($apkPath)" $step3Sw

# Step 3.5: Sign APK before copying
$stepSignSw = Log-StepStart "Signing release APK ($apkPath)..."
$keyConfig = Get-KeystoreConfig
if (-not $keyConfig) {
    Write-Warning "No android/key.properties found. Skipping explicit APK signing step."
} else {
    $storeFile = $keyConfig['storeFile']
    $keystorePath = Join-Path $repoRoot "android\$storeFile"
    if (-not (Test-Path $keystorePath)) {
        $keystorePath = Join-Path $repoRoot $storeFile
    }
    if (-not (Test-Path $keystorePath)) {
        Write-Error "Keystore file not found at '$keystorePath' (specified in key.properties)."
        exit 1
    }

    $storePass = $keyConfig['storePassword']
    $keyPass = $keyConfig['keyPassword']
    $keyAlias = $keyConfig['keyAlias']
    $apksigner = Find-ApkSigner

    if ($apksigner) {
        Write-Host "Signing with apksigner ($apksigner)..." -ForegroundColor Cyan
        & $apksigner sign --ks "$keystorePath" --ks-key-alias "$keyAlias" --ks-pass "pass:$storePass" --key-pass "pass:$keyPass" "$apkPath"
        if ($LASTEXITCODE -ne 0) {
            Write-Error "apksigner failed with exit code $LASTEXITCODE"
            exit $LASTEXITCODE
        }
        & $apksigner verify --verbose "$apkPath"
        if ($LASTEXITCODE -ne 0) {
            Write-Error "apksigner signature verification failed with exit code $LASTEXITCODE"
            exit $LASTEXITCODE
        }
        Write-Host "APK successfully signed and verified via apksigner." -ForegroundColor Green
    } else {
        $jarsignerCmd = Get-Command 'jarsigner' -ErrorAction SilentlyContinue
        if ($jarsignerCmd) {
            Write-Host "apksigner not found; signing with jarsigner ($($jarsignerCmd.Source))..." -ForegroundColor Yellow
            & $jarsignerCmd.Source -verbose -sigalg SHA256withRSA -digestalg SHA-256 -keystore "$keystorePath" -storepass "$storePass" -keypass "$keyPass" "$apkPath" "$keyAlias"
            if ($LASTEXITCODE -ne 0) {
                Write-Error "jarsigner failed with exit code $LASTEXITCODE"
                exit $LASTEXITCODE
            }
            & $jarsignerCmd.Source -verify -verbose -certs "$apkPath"
            Write-Host "APK successfully signed and verified via jarsigner." -ForegroundColor Green
        } else {
            Write-Error "Neither apksigner nor jarsigner could be located to sign the APK."
            exit 1
        }
    }
}
Log-StepEnd "Signing release APK" $stepSignSw

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
