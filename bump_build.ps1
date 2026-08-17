<#
.SYNOPSIS
    Bumps the build number (and optionally semantic version) in pubspec.yaml.

.DESCRIPTION
    Reads pubspec.yaml, parses the `version: x.y.z+build` string, and increments
    the build number by default. Also supports setting specific build numbers,
    bumping major/minor/patch versions, or setting explicit versions.

.PARAMETER Increment
    Number to add to the current build number (default: 1).

.PARAMETER BuildNumber
    Explicitly set the build number to this value instead of incrementing.

.PARAMETER Version
    Explicitly set the semantic version string (e.g., "1.2.0").

.PARAMETER Patch
    Increment the patch version (e.g., 1.0.0 -> 1.0.1) while bumping build number.

.PARAMETER Minor
    Increment the minor version (e.g., 1.0.0 -> 1.1.0) and reset patch to 0.

.PARAMETER Major
    Increment the major version (e.g., 1.0.0 -> 2.0.0) and reset minor/patch to 0.

.PARAMETER PubspecPath
    Custom path to pubspec.yaml (defaults to pubspec.yaml in repo root).

.PARAMETER DryRun
    Show what changes would be made without saving to the file.

.PARAMETER Quiet
    Only output the new version string (e.g., "1.0.0+7"), ideal for scripting/pipelines.

.EXAMPLE
    .\bump_build.ps1
    # Bumps 1.0.0+6 to 1.0.0+7

.EXAMPLE
    .\bump_build.ps1 -BuildNumber 10
    # Sets version to 1.0.0+10

.EXAMPLE
    .\bump_build.ps1 -Patch
    # Bumps 1.0.0+6 to 1.0.1+7

.EXAMPLE
    .\bump_build.ps1 -Minor
    # Bumps 1.0.0+6 to 1.1.0+7

.EXAMPLE
    .\bump_build.ps1 -Version "2.0.0"
    # Sets version to 2.0.0+7
#>

[CmdletBinding()]
param(
    [int]$Increment = 1,
    [Nullable[int]]$BuildNumber = $null,
    [string]$Version = $null,
    [switch]$Patch,
    [switch]$Minor,
    [switch]$Major,
    [string]$PubspecPath = "",
    [switch]$DryRun,
    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'

# Determine pubspec.yaml location
if ([string]::IsNullOrWhiteSpace($PubspecPath)) {
    # Check script root directory first
    $candidate = Join-Path $PSScriptRoot "pubspec.yaml"
    if (Test-Path -LiteralPath $candidate) {
        $PubspecPath = $candidate
    } else {
        # Check parent directory (in case script is run from scripts/ folder)
        $parentCandidate = Join-Path (Join-Path $PSScriptRoot "..") "pubspec.yaml"
        if (Test-Path -LiteralPath $parentCandidate) {
            $PubspecPath = $parentCandidate
        } else {
            # Check current working directory
            $PubspecPath = Join-Path (Get-Location) "pubspec.yaml"
        }
    }
}

if (-not (Test-Path -LiteralPath $PubspecPath)) {
    Write-Error "Could not find pubspec.yaml at '$PubspecPath'."
    exit 1
}

$fullPath = (Resolve-Path -LiteralPath $PubspecPath).Path
$content = [System.IO.File]::ReadAllText($fullPath, [System.Text.Encoding]::UTF8)

# Regex to find: version: 1.0.0+6 (with optional comments or whitespace)
$pattern = '(?m)^(?<prefix>\s*version:\s*)(?<semver>[0-9]+\.[0-9]+(?:\.[0-9]+)?(?:-[0-9A-Za-z\.-]+)?)(?:\+(?<build>\d+))?(?<suffix>.*)$'
$match = [regex]::Match($content, $pattern)

if (-not $match.Success) {
    # Fallback to broader match if non-standard
    $pattern = '(?m)^(?<prefix>\s*version:\s*)(?<semver>[^\s\+#]+)(?:\+(?<build>\d+))?(?<suffix>.*)$'
    $match = [regex]::Match($content, $pattern)
}

if (-not $match.Success) {
    Write-Error "Could not find a valid 'version:' declaration in $fullPath."
    exit 1
}

$currentSemVer = $match.Groups['semver'].Value
$rawBuild = $match.Groups['build'].Value
$currentBuild = if ([string]::IsNullOrEmpty($rawBuild)) { 0 } else { [int]$rawBuild }
$prefix = $match.Groups['prefix'].Value
$suffix = $match.Groups['suffix'].Value

$oldVersionFull = if ([string]::IsNullOrEmpty($rawBuild)) { $currentSemVer } else { "$currentSemVer+$currentBuild" }

# Determine new SemVer
$newSemVer = $currentSemVer
if (-not [string]::IsNullOrEmpty($Version)) {
    $newSemVer = $Version.Trim()
} elseif ($Major -or $Minor -or $Patch) {
    if ($currentSemVer -match '^(\d+)\.(\d+)(?:\.(\d+))?(.*)$') {
        $maj = [int]$matches[1]
        $min = [int]$matches[2]
        $pat = if ($matches[3]) { [int]$matches[3] } else { 0 }
        
        if ($Major) {
            $maj += 1
            $min = 0
            $pat = 0
        } elseif ($Minor) {
            $min += 1
            $pat = 0
        } elseif ($Patch) {
            $pat += 1
        }
        $newSemVer = "$maj.$min.$pat"
    } else {
        Write-Warning "Current version '$currentSemVer' is not in standard X.Y.Z format. Skipping semantic version bump."
    }
}

# Determine new BuildNumber
$newBuild = if ($BuildNumber.HasValue) {
    $BuildNumber.Value
} else {
    $currentBuild + $Increment
}

$newVersionFull = "$newSemVer+$newBuild"
$replacementLine = "${prefix}${newVersionFull}${suffix}"

if ($Quiet) {
    if (-not $DryRun) {
        $newContent = [regex]::Replace($content, $pattern, [System.Text.RegularExpressions.MatchEvaluator]{
            param($m)
            return $replacementLine
        }, 1)
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($fullPath, $newContent, $utf8NoBom)
    }
    Write-Output $newVersionFull
    exit 0
}

Write-Host "==============================================" -ForegroundColor Cyan
Write-Host "Pubspec Version & Build Bumper" -ForegroundColor Cyan
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host "File:         $fullPath"
Write-Host "Current:      $oldVersionFull" -ForegroundColor Yellow
Write-Host "New Version:  $newVersionFull" -ForegroundColor Green

if ($DryRun) {
    Write-Host "`n[DRY RUN] No changes were written to pubspec.yaml." -ForegroundColor Magenta
} else {
    $newContent = [regex]::Replace($content, $pattern, [System.Text.RegularExpressions.MatchEvaluator]{
        param($m)
        return $replacementLine
    }, 1)
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($fullPath, $newContent, $utf8NoBom)
    Write-Host "`n[✓] Successfully updated pubspec.yaml to version: $newVersionFull" -ForegroundColor Green
}
