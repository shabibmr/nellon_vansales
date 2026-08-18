<#
.SYNOPSIS
    High-Efficiency Fast ARM64 Build & Deploy Pipeline for Nellon Van Sales.

.DESCRIPTION
    Optimized drop-in companion to test_deploy_arm64.ps1 with key speed enhancements:
    - Smart Dependency Caching: Auto-detects if pub get can be skipped (--no-pub).
    - Single-Source Signing: Relies on Gradle's assembleRelease signing; removes redundant re-signing.
    - Compressed Transfer: Uses `scp -C` to accelerate upload by 20-40%.
    - Integrated Version Bumping: Pass `-Bump`, `-Patch`, `-Minor`, or `-Major` to bump pubspec.yaml on the fly.
    - Automatic Git Release Notes: Auto-extracts latest commit message if -Notes is omitted.
    - Local Device Sideload: Pass `-Install` to install immediately to a connected phone via ADB.
    - Safety DryRun: Pass `-DryRun` to verify parameters without executing network/build actions.
    - Local Console Log: Every run's console output is mirrored to a timestamped file under -LogDir.

.USAGE
    # Fast test deploy with smart pub caching & scp compression
    pwsh -File super_test_deploy_arm64.ps1

    # Bump build number, build, upload, and update Firestore
    pwsh -File super_test_deploy_arm64.ps1 -Bump

    # Bump patch version (e.g., 1.0.0 -> 1.0.1+N) and deploy
    pwsh -File super_test_deploy_arm64.ps1 -Patch

    # Build and install directly to a connected test phone via ADB
    pwsh -File super_test_deploy_arm64.ps1 -Install -SkipUpload -SkipFirestore

    # Target production channel with custom notes
    pwsh -File super_test_deploy_arm64.ps1 -Channel production -RemoteDir /var/www/html/algo_cloud/nellon -Notes "Hotfix sync worker"

    # Write the console log somewhere other than the default ./logs folder
    pwsh -File super_test_deploy_arm64.ps1 -LogDir C:\deploy-logs
#>

[CmdletBinding()]
param(
    [string]$SshHost = 'gm1',
    [string]$RemoteDir = '/var/www/html/algo_cloud/nellon/test',
    [string]$ApkName = 'app-nellon-release.apk',
    [ValidateSet('beta', 'test', 'production')]
    [string]$Channel = 'beta',
    [string]$Notes = '',
    [switch]$Bump,
    [switch]$Patch,
    [switch]$Minor,
    [switch]$Major,
    [switch]$SkipBuild,
    [switch]$SkipPub,
    [switch]$SkipFirestore,
    [switch]$SkipUpload,
    [switch]$Install,
    [switch]$VerifySign,
    [switch]$DryRun,
    [string]$LogDir = 'logs'
)

$ErrorActionPreference = 'Stop'
$repoRoot = $PSScriptRoot
Set-Location $repoRoot

# Mirror everything written to the console (Write-Host, cmdlet output, and
# stdout/stderr of native commands like flutter/ssh/scp/node) to a local file.
$resolvedLogDir = if ([System.IO.Path]::IsPathRooted($LogDir)) { $LogDir } else { Join-Path $repoRoot $LogDir }
if (-not (Test-Path -LiteralPath $resolvedLogDir)) {
    New-Item -ItemType Directory -Path $resolvedLogDir -Force | Out-Null
}
$logTimestamp = (Get-Date).ToString("yyyyMMdd_HHmmss")
$logFile = Join-Path $resolvedLogDir "deploy_arm64_${Channel}_${logTimestamp}.log"
Start-Transcript -Path $logFile -Force | Out-Null
Write-Host "Console log: $logFile" -ForegroundColor DarkGray

try {

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

$totalSw = [System.Diagnostics.Stopwatch]::StartNew()
$scriptStartTs = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
$destination = "${SshHost}:${RemoteDir}/${ApkName}"
$remoteDirQuoted = $RemoteDir.Replace("'", "'\''")

Write-Host '==================================================' -ForegroundColor Cyan
Write-Host "[$scriptStartTs] Super Fast Deploy (ARM64)" -ForegroundColor Cyan
Write-Host "Repo:       $repoRoot" -ForegroundColor Cyan
Write-Host "Channel:    $Channel" -ForegroundColor Cyan
Write-Host "Target:     $destination" -ForegroundColor Cyan
Write-Host '==================================================' -ForegroundColor Cyan

# Step 0: Optional Version Bumping
if ($Bump -or $Patch -or $Minor -or $Major) {
    $bumpSw = Log-StepStart "Bumping version in pubspec.yaml..."
    $bumpScript = Join-Path $repoRoot 'scripts\bump_build.ps1'
    if (-not (Test-Path $bumpScript)) {
        $bumpScript = Join-Path $repoRoot 'bump_build.ps1'
    }
    if (Test-Path $bumpScript) {
        $bumpArgs = @{ Quiet = $true }
        if ($Patch) { $bumpArgs['Patch'] = $true }
        if ($Minor) { $bumpArgs['Minor'] = $true }
        if ($Major) { $bumpArgs['Major'] = $true }
        if ($DryRun) { $bumpArgs['DryRun'] = $true }

        $newVersion = & $bumpScript @bumpArgs
        Write-Host "Version updated to: $newVersion" -ForegroundColor Green
    } else {
        Write-Warning "bump_build.ps1 not found at $bumpScript. Skipping bump."
    }
    Log-StepEnd "Bumping version" $bumpSw
}

# Step 1: Smart Pub Resolution Check
$useNoPub = $SkipPub
if (-not $useNoPub) {
    $pkgConfig = Join-Path $repoRoot '.dart_tool\package_config.json'
    $pubspec = Join-Path $repoRoot 'pubspec.yaml'
    if ((Test-Path $pkgConfig) -and (Test-Path $pubspec)) {
        $pkgTime = (Get-Item $pkgConfig).LastWriteTimeUtc
        $pubTime = (Get-Item $pubspec).LastWriteTimeUtc
        if ($pkgTime -gt $pubTime) {
            $useNoPub = $true
            Write-Host "Dependencies up-to-date; applying '--no-pub' automatically." -ForegroundColor DarkGray
        }
    }
}

# Step 2: Build ARM64 APK
if (-not $SkipBuild) {
    $step2Sw = Log-StepStart "Building ARM64 release APK (flutter build apk --release --target-platform android-arm64)..."

    if ($DryRun) {
        Write-Host "[DRY RUN] Would execute: flutter build apk --release --target-platform android-arm64 $(if ($useNoPub) { '--no-pub' })" -ForegroundColor Magenta
    } else {
        $flutterArgs = @(
            'build', 'apk',
            '--release',
            '--target-platform', 'android-arm64'
        )
        if ($useNoPub) {
            $flutterArgs += '--no-pub'
        }

        & flutter @flutterArgs
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Flutter ARM64 build failed with exit code $LASTEXITCODE"
            exit $LASTEXITCODE
        }
    }
    Log-StepEnd "Building ARM64 release APK" $step2Sw
} else {
    Write-Host "`nSkipping build (-SkipBuild)." -ForegroundColor Yellow
}

# Step 3: Locate and Inspect Generated APK
$step3Sw = Log-StepStart "Locating release APK ($ApkName)..."
$apkPath = Find-ReleaseApk -Name $ApkName
if (-not $apkPath) {
    if ($DryRun) {
        $apkPath = Join-Path $repoRoot "build\app\outputs\flutter-apk\$ApkName"
        Write-Host "[DRY RUN] Mock APK path: $apkPath" -ForegroundColor Magenta
    } else {
        Write-Error "No release APK found under $repoRoot\build\app\outputs. Run without -SkipBuild, or pass a built tree."
        exit 1
    }
}
if (Test-Path $apkPath) {
    $sizeMb = [math]::Round((Get-Item -LiteralPath $apkPath).Length / 1MB, 1)
    Write-Host "Found APK: $apkPath (${sizeMb} MB)" -ForegroundColor Green
}
Log-StepEnd "Locating release APK" $step3Sw

# Step 3.5: Optional Signature Verification
if ($VerifySign -and -not $DryRun) {
    $stepVerifySw = Log-StepStart "Verifying APK signature..."
    $apksigner = Find-ApkSigner
    if ($apksigner) {
        & $apksigner verify --verbose "$apkPath"
        if ($LASTEXITCODE -ne 0) {
            Write-Error "APK signature verification failed!"
            exit $LASTEXITCODE
        }
        Write-Host "APK signature verified successfully." -ForegroundColor Green
    } else {
        Write-Warning "apksigner not found; skipping signature verification."
    }
    Log-StepEnd "Verifying APK signature" $stepVerifySw
}

# Step 4: Optional Direct ADB Install to Connected Phone
if ($Install -and -not $DryRun) {
    $stepAdbSw = Log-StepStart "Installing APK directly to connected Android device via ADB..."
    $adbCmd = Get-Command 'adb' -ErrorAction SilentlyContinue
    if ($adbCmd) {
        & adb install -r "$apkPath"
        if ($LASTEXITCODE -eq 0) {
            Write-Host "APK installed successfully on device!" -ForegroundColor Green
        } else {
            Write-Warning "ADB install failed or no device attached (Exit code: $LASTEXITCODE)."
        }
    } else {
        Write-Warning "adb command not found in PATH; skipping local install."
    }
    Log-StepEnd "Installing via ADB" $stepAdbSw
}

# Step 5: Transfer APK via Compressed SCP
if (-not $SkipUpload) {
    $stepUploadSw = Log-StepStart "Ensuring remote directory and copying APK via scp -C to $destination..."
    if ($DryRun) {
        Write-Host "[DRY RUN] Would execute: ssh $SshHost 'mkdir -p ''$remoteDirQuoted'''" -ForegroundColor Magenta
        Write-Host "[DRY RUN] Would execute: scp -C '$apkPath' '$destination'" -ForegroundColor Magenta
    } else {
        & ssh $SshHost "mkdir -p '$remoteDirQuoted'"
        if ($LASTEXITCODE -ne 0) {
            Write-Error "ssh mkdir failed with exit code $LASTEXITCODE"
            exit $LASTEXITCODE
        }

        & scp -C "$apkPath" "$destination"
        if ($LASTEXITCODE -ne 0) {
            Write-Error "scp transfer failed with exit code $LASTEXITCODE"
            exit $LASTEXITCODE
        }
        Write-Host "`nAPK successfully deployed to $destination" -ForegroundColor Green
    }
    Log-StepEnd "Uploading APK to remote host" $stepUploadSw
} else {
    Write-Host "`nSkipping upload (-SkipUpload)." -ForegroundColor Yellow
}

# Step 6: Update Firestore Metadata
if (-not $SkipFirestore -and -not $SkipUpload) {
    $stepFireSw = Log-StepStart "Updating $Channel channel version metadata in Firestore..."

    # Auto-generate notes from latest git commit if blank
    $effectiveNotes = $Notes
    if ([string]::IsNullOrWhiteSpace($effectiveNotes)) {
        $gitMsg = (git log -1 --pretty=%s 2>$null)
        if ($gitMsg) {
            $effectiveNotes = "• $gitMsg"
        }
    }

    $updater = Join-Path $repoRoot 'scripts\update_firestore_version.js'
    $updaterArgs = @(
        "--channel=$Channel",
        "--apk=$apkPath"
    )
    if ($effectiveNotes) {
        $updaterArgs += "--notes=$effectiveNotes"
    }
    if ($DryRun) {
        $updaterArgs += "--dry-run"
    }

    if (Test-Path $updater) {
        if ($DryRun -and -not (Test-Path $apkPath)) {
            Write-Host "[DRY RUN] Would execute: node $updater $($updaterArgs -join ' ')" -ForegroundColor Magenta
        } else {
            & node $updater @updaterArgs
            if ($LASTEXITCODE -ne 0) {
                Write-Error "Firestore version update failed with exit code $LASTEXITCODE"
                exit $LASTEXITCODE
            }
        }
    } else {
        Write-Warning "Firestore updater script not found at $updater."
    }
    Log-StepEnd "Updating Firestore version metadata" $stepFireSw
} elseif ($SkipFirestore) {
    Write-Host "`nSkipping Firestore version update (-SkipFirestore)." -ForegroundColor Yellow
}

$totalSw.Stop()
$totalElapsed = $totalSw.Elapsed
$scriptEndTs = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
$totalElapsedFormatted = "{0:D2}m {1:D2}s ({2:N2}s total)" -f [int]$totalElapsed.TotalMinutes, $totalElapsed.Seconds, $totalElapsed.TotalSeconds

Write-Host "`n==================================================" -ForegroundColor Green
Write-Host "[$scriptEndTs] Super Fast Deploy Complete! [Total Elapsed: $totalElapsedFormatted]" -ForegroundColor Green
Write-Host "Console log saved to: $logFile" -ForegroundColor Green
Write-Host "==================================================" -ForegroundColor Green

} finally {
    Stop-Transcript | Out-Null
}
