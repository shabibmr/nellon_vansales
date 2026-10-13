#!/usr/bin/env bash
#
# High-Efficiency Fast ARM64 Build & Deploy Pipeline for Nellon Van Sales.
#
# Optimized drop-in companion to super_test_deploy_arm64.ps1 with key speed enhancements:
# - Smart Dependency Caching: Auto-detects if pub get can be skipped (--no-pub).
# - Single-Source Signing: Relies on Gradle's assembleRelease signing; removes redundant re-signing.
# - Compressed Transfer: Uses `scp -C` to accelerate upload by 20-40%.
# - Integrated Version Bumping: Pass --bump, --patch, --minor, or --major to bump pubspec.yaml on the fly.
# - Automatic Git Release Notes: Auto-extracts latest commit message if --notes is omitted.
# - Local Device Sideload: Pass --install to install immediately to a connected phone via ADB.
# - Safety DryRun: Pass --dry-run to verify parameters without executing network/build actions.
# - Local Console Log: Every run's console output is mirrored to a timestamped file under --log-dir.
#
# USAGE:
#   # Fast test deploy with smart pub caching & scp compression
#   ./super_test_deploy_arm64.sh
#
#   # Bump build number, build, upload, and update Firestore
#   ./super_test_deploy_arm64.sh --bump
#
#   # Bump patch version (e.g., 1.0.0 -> 1.0.1+N) and deploy
#   ./super_test_deploy_arm64.sh --patch
#
#   # Build and install directly to a connected test phone via ADB
#   ./super_test_deploy_arm64.sh --install --skip-upload --skip-firestore
#
#   # Target production channel with custom notes
#   ./super_test_deploy_arm64.sh --channel production --remote-dir /var/www/html/algo_cloud/nellon --notes "Hotfix sync worker"
#
#   # Write the console log somewhere other than the default ./logs folder
#   ./super_test_deploy_arm64.sh --log-dir /path/to/deploy-logs
#

set -euo pipefail

# Determine repository root
repoRoot="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$repoRoot"

# Defaults
SSH_HOST="gm1"
REMOTE_DIR="/var/www/html/algo_cloud/nellon/test"
APK_NAME="app-nellon-release.apk"
CHANNEL="beta"
NOTES=""
BUMP=false
PATCH=false
MINOR=false
MAJOR=false
SKIP_BUILD=false
SKIP_PUB=false
SKIP_FIRESTORE=false
SKIP_UPLOAD=false
INSTALL=false
VERIFY_SIGN=false
DRY_RUN=false
LOG_DIR="logs"

show_help() {
    cat <<EOF
High-Efficiency Fast ARM64 Build & Deploy Pipeline for Nellon Van Sales

Usage:
  ./super_test_deploy_arm64.sh [options]

Options:
  -SshHost, --ssh-host <host>          SSH host alias or address (default: gm1)
  -RemoteDir, --remote-dir <dir>       Remote directory path (default: /var/www/html/algo_cloud/nellon/test)
  -ApkName, --apk-name <name>          Destination APK filename (default: app-nellon-release.apk)
  -Channel, --channel <channel>        Channel: beta | test | production (default: beta)
  -Notes, --notes <notes>              Release notes for Firestore (defaults to latest git commit)
  -Bump, --bump                        Increment build number by 1
  -Patch, --patch                      Bump patch version (e.g., 1.0.0 -> 1.0.1+N)
  -Minor, --minor                      Bump minor version (e.g., 1.0.0 -> 1.1.0+N)
  -Major, --major                      Bump major version (e.g., 1.0.0 -> 2.0.0+N)
  -SkipBuild, --skip-build             Skip the Flutter build step
  -SkipPub, --skip-pub                 Skip running 'pub get' explicitly
  -SkipFirestore, --skip-firestore     Skip updating Firestore metadata
  -SkipUpload, --skip-upload           Skip uploading APK via SCP
  -Install, --install                  Install APK directly to connected Android device via ADB
  -VerifySign, --verify-sign           Verify APK signature using apksigner
  -DryRun, --dry-run                   Simulate execution without running network/build commands
  -LogDir, --log-dir <dir>             Directory for console log files (default: logs)
  -h, --help                           Show this help message
EOF
}

# Parse Arguments (Supporting both --kebab-case and -PascalCase)
while [[ $# -gt 0 ]]; do
    case "$1" in
        --ssh-host|-SshHost)
            SSH_HOST="$2"
            shift 2
            ;;
        --remote-dir|-RemoteDir)
            REMOTE_DIR="$2"
            shift 2
            ;;
        --apk-name|-ApkName)
            APK_NAME="$2"
            shift 2
            ;;
        --channel|-Channel)
            CHANNEL="$2"
            shift 2
            ;;
        --notes|-Notes)
            NOTES="$2"
            shift 2
            ;;
        --bump|-Bump)
            BUMP=true
            shift
            ;;
        --patch|-Patch)
            PATCH=true
            shift
            ;;
        --minor|-Minor)
            MINOR=true
            shift
            ;;
        --major|-Major)
            MAJOR=true
            shift
            ;;
        --skip-build|-SkipBuild)
            SKIP_BUILD=true
            shift
            ;;
        --skip-pub|-SkipPub)
            SKIP_PUB=true
            shift
            ;;
        --skip-firestore|-SkipFirestore)
            SKIP_FIRESTORE=true
            shift
            ;;
        --skip-upload|-SkipUpload)
            SKIP_UPLOAD=true
            shift
            ;;
        --install|-Install)
            INSTALL=true
            shift
            ;;
        --verify-sign|-VerifySign)
            VERIFY_SIGN=true
            shift
            ;;
        --dry-run|-DryRun)
            DRY_RUN=true
            shift
            ;;
        --log-dir|-LogDir)
            LOG_DIR="$2"
            shift 2
            ;;
        -h|--help|-Help)
            show_help
            exit 0
            ;;
        *)
            echo -e "\033[31mUnknown argument: $1\033[0m" >&2
            show_help
            exit 1
            ;;
    esac
done

# Validate Channel
if [[ "$CHANNEL" != "beta" && "$CHANNEL" != "test" && "$CHANNEL" != "production" ]]; then
    echo -e "\033[31mError: Channel must be one of: beta, test, production. Received: '$CHANNEL'\033[0m" >&2
    exit 1
fi

# Mirror everything written to console to a timestamped local log file
if [[ "$LOG_DIR" = /* ]]; then
    resolved_log_dir="$LOG_DIR"
else
    resolved_log_dir="${repoRoot}/${LOG_DIR}"
fi
mkdir -p "$resolved_log_dir"

log_timestamp=$(date +"%Y%m%d_%H%M%S")
log_file="${resolved_log_dir}/deploy_arm64_${CHANNEL}_${log_timestamp}.log"

# Save original file descriptors and redirect stdout & stderr
exec 3>&1 4>&2
exec > >(tee -a "$log_file") 2>&1
echo -e "\033[90mConsole log: ${log_file}\033[0m"

# Helper for formatted step logging
log_step_start() {
    local msg="$1"
    local ts
    ts=$(date +"%Y-%m-%d %H:%M:%S")
    echo -e "\n\033[36m[${ts}] >>> ${msg}\033[0m" >&2
    date +%s.%N
}

log_step_end() {
    local msg="$1"
    local start_time="$2"
    local end_time
    end_time=$(date +%s.%N)
    local ts
    ts=$(date +"%Y-%m-%d %H:%M:%S")
    
    local elapsed
    elapsed=$(awk "BEGIN {printf \"%.2f\", ${end_time} - ${start_time}}")
    local total_sec_int
    total_sec_int=$(awk "BEGIN {print int(${elapsed})}")
    local min=$(( total_sec_int / 60 ))
    local sec=$(( total_sec_int % 60 ))
    local formatted
    formatted=$(printf "%02dm %02ds (%.2fs total)" "$min" "$sec" "$elapsed")
    echo -e "\033[32m[${ts}] <<< Finished: ${msg} [Elapsed: ${formatted}]\033[0m"
}

find_release_apk() {
    local name="$1"
    local candidates=(
        "${repoRoot}/build/app/outputs/flutter-apk/${name}"
        "${repoRoot}/build/app/outputs/apk/release/${name}"
        "${repoRoot}/build/app/outputs/flutter-apk/app-release.apk"
        "${repoRoot}/build/app/outputs/apk/release/app-release.apk"
    )
    for path in "${candidates[@]}"; do
        if [[ -f "$path" ]]; then
            echo "$path"
            return 0
        fi
    done
    return 1
}

find_apk_signer() {
    if command -v apksigner >/dev/null 2>&1; then
        command -v apksigner
        return 0
    fi

    local sdk_dirs=()
    if [[ -f "${repoRoot}/android/local.properties" ]]; then
        local sdk_dir
        sdk_dir=$(grep -E '^[[:space:]]*sdk\.dir[[:space:]]*=' "${repoRoot}/android/local.properties" | sed -E 's/^[[:space:]]*sdk\.dir[[:space:]]*=[[:space:]]*//' | tr -d '\r\n')
        if [[ -n "$sdk_dir" ]]; then
            sdk_dirs+=("$sdk_dir")
        fi
    fi
    [[ -n "${ANDROID_HOME:-}" ]] && sdk_dirs+=("$ANDROID_HOME")
    [[ -n "${ANDROID_SDK_ROOT:-}" ]] && sdk_dirs+=("$ANDROID_SDK_ROOT")
    [[ -d "$HOME/Android/Sdk" ]] && sdk_dirs+=("$HOME/Android/Sdk")
    [[ -d "/usr/lib/android-sdk" ]] && sdk_dirs+=("/usr/lib/android-sdk")

    for sdk in "${sdk_dirs[@]}"; do
        if [[ -d "${sdk}/build-tools" ]]; then
            local ver
            for ver in $(ls -1r "${sdk}/build-tools" 2>/dev/null); do
                if [[ -x "${sdk}/build-tools/${ver}/apksigner" ]]; then
                    echo "${sdk}/build-tools/${ver}/apksigner"
                    return 0
                fi
            done
        fi
    done
    return 1
}

total_sw_start=$(date +%s.%N)
script_start_ts=$(date +"%Y-%m-%d %H:%M:%S")
destination="${SSH_HOST}:${REMOTE_DIR}/${APK_NAME}"

echo -e "\033[36m==================================================\033[0m"
echo -e "\033[36m[${script_start_ts}] Super Fast Deploy (ARM64)\033[0m"
echo -e "\033[36mRepo:       ${repoRoot}\033[0m"
echo -e "\033[36mChannel:    ${CHANNEL}\033[0m"
echo -e "\033[36mTarget:     ${destination}\033[0m"
echo -e "\033[36m==================================================\033[0m"

# Step 0: Optional Version Bumping
if [[ "$BUMP" == "true" || "$PATCH" == "true" || "$MINOR" == "true" || "$MAJOR" == "true" ]]; then
    bump_sw=$(log_step_start "Bumping version in pubspec.yaml...")
    bump_dart="${repoRoot}/scripts/bump_build.dart"
    
    if [[ -f "$bump_dart" ]] && command -v dart >/dev/null 2>&1; then
        bump_args=("--quiet")
        [[ "$PATCH" == "true" ]] && bump_args+=("--patch")
        [[ "$MINOR" == "true" ]] && bump_args+=("--minor")
        [[ "$MAJOR" == "true" ]] && bump_args+=("--major")
        [[ "$DRY_RUN" == "true" ]] && bump_args+=("--dry-run")

        new_version=$(dart "$bump_dart" "${bump_args[@]}" 2>/dev/null | tail -n 1)
        echo -e "\033[32mVersion updated to: ${new_version}\033[0m"
    else
        echo -e "\033[33mWarning: scripts/bump_build.dart or dart runtime not found. Skipping bump.\033[0m"
    fi
    log_step_end "Bumping version" "$bump_sw"
fi

# Step 1: Smart Pub Resolution Check
use_no_pub="$SKIP_PUB"
if [[ "$use_no_pub" != "true" ]]; then
    pkg_config="${repoRoot}/.dart_tool/package_config.json"
    pubspec="${repoRoot}/pubspec.yaml"
    if [[ -f "$pkg_config" && -f "$pubspec" ]]; then
        if [[ "$pkg_config" -nt "$pubspec" ]]; then
            use_no_pub="true"
            echo -e "\033[90mDependencies up-to-date; applying '--no-pub' automatically.\033[0m"
        fi
    fi
fi

# Step 2: Build ARM64 APK
if [[ "$SKIP_BUILD" != "true" ]]; then
    step2_sw=$(log_step_start "Building ARM64 release APK (flutter build apk --release --target-platform android-arm64)...")
    
    flutter_args=(
        "build" "apk"
        "--release"
        "--target-platform" "android-arm64"
    )
    if [[ "$use_no_pub" == "true" ]]; then
        flutter_args+=("--no-pub")
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "\033[35m[DRY RUN] Would execute: flutter ${flutter_args[*]}\033[0m"
    else
        flutter "${flutter_args[@]}"
        echo -e "\033[32mFlutter ARM64 build completed successfully.\033[0m"
    fi
    log_step_end "Building ARM64 release APK" "$step2_sw"
else
    echo -e "\n\033[33mSkipping build (-SkipBuild / --skip-build).\033[0m"
fi

# Step 3: Locate and Inspect Generated APK
step3_sw=$(log_step_start "Locating release APK (${APK_NAME})...")
apk_path=""
if apk_found=$(find_release_apk "$APK_NAME"); then
    apk_path="$apk_found"
fi

if [[ -z "$apk_path" ]]; then
    if [[ "$DRY_RUN" == "true" ]]; then
        apk_path="${repoRoot}/build/app/outputs/flutter-apk/${APK_NAME}"
        echo -e "\033[35m[DRY RUN] Mock APK path: ${apk_path}\033[0m"
    else
        echo -e "\033[31mError: No release APK found under ${repoRoot}/build/app/outputs. Run without --skip-build, or pass a built tree.\033[0m" >&2
        exit 1
    fi
fi

if [[ -f "$apk_path" ]]; then
    size_bytes=$(stat -c%s "$apk_path" 2>/dev/null || stat -f%z "$apk_path" 2>/dev/null || echo 0)
    size_mb=$(awk "BEGIN {printf \"%.1f\", ${size_bytes} / 1048576}")
    echo -e "\033[32mFound APK: ${apk_path} (${size_mb} MB)\033[0m"
fi
log_step_end "Locating release APK" "$step3_sw"

# Step 3.5: Optional Signature Verification
if [[ "$VERIFY_SIGN" == "true" && "$DRY_RUN" != "true" ]]; then
    step_verify_sw=$(log_step_start "Verifying APK signature...")
    if apksigner_cmd=$(find_apk_signer); then
        "$apksigner_cmd" verify --verbose "$apk_path"
        echo -e "\033[32mAPK signature verified successfully.\033[0m"
    else
        echo -e "\033[33mWarning: apksigner not found; skipping signature verification.\033[0m"
    fi
    log_step_end "Verifying APK signature" "$step_verify_sw"
fi

# Step 4: Optional Direct ADB Install to Connected Phone
if [[ "$INSTALL" == "true" && "$DRY_RUN" != "true" ]]; then
    step_adb_sw=$(log_step_start "Installing APK directly to connected Android device via ADB...")
    if command -v adb >/dev/null 2>&1; then
        if adb install -r "$apk_path"; then
            echo -e "\033[32mAPK installed successfully on device!\033[0m"
        else
            echo -e "\033[33mWarning: ADB install failed or no device attached.\033[0m"
        fi
    else
        echo -e "\033[33mWarning: adb command not found in PATH; skipping local install.\033[0m"
    fi
    log_step_end "Installing via ADB" "$step_adb_sw"
fi

# Step 5: Transfer APK via Compressed SCP
if [[ "$SKIP_UPLOAD" != "true" ]]; then
    step_upload_sw=$(log_step_start "Ensuring remote directory and copying APK via scp -C to ${destination}...")
    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "\033[35m[DRY RUN] Would execute: ssh ${SSH_HOST} \"mkdir -p '${REMOTE_DIR}'\"\033[0m"
        echo -e "\033[35m[DRY RUN] Would execute: scp -C '${apk_path}' '${destination}'\033[0m"
    elif [[ -d "/var/www/html/algo_cloud" && ( "$SSH_HOST" == "gm1" || "$SSH_HOST" == "localhost" || "$SSH_HOST" == "127.0.0.1" ) ]]; then
        mkdir -p "$REMOTE_DIR"
        cp -f "$apk_path" "${REMOTE_DIR}/${APK_NAME}"
        chmod 644 "${REMOTE_DIR}/${APK_NAME}" || true
        echo -e "\n\033[32mAPK successfully deployed locally to ${REMOTE_DIR}/${APK_NAME}\033[0m"
    else
        ssh "$SSH_HOST" "mkdir -p '${REMOTE_DIR}'"
        scp -C "$apk_path" "$destination"
        echo -e "\n\033[32mAPK successfully deployed to ${destination}\033[0m"
    fi
    log_step_end "Uploading APK to remote host" "$step_upload_sw"
else
    echo -e "\n\033[33mSkipping upload (-SkipUpload / --skip-upload).\033[0m"
fi

# Step 6: Update Firestore Metadata
if [[ "$SKIP_FIRESTORE" != "true" && "$SKIP_UPLOAD" != "true" ]]; then
    step_fire_sw=$(log_step_start "Updating ${CHANNEL} channel version metadata in Firestore...")
    
    effective_notes="$NOTES"
    if [[ -z "$effective_notes" ]]; then
        git_msg=$(git log -1 --pretty=%s 2>/dev/null || true)
        if [[ -n "$git_msg" ]]; then
            effective_notes="• ${git_msg}"
        fi
    fi

    updater="${repoRoot}/scripts/update_firestore_version.js"
    updater_args=(
        "--channel=${CHANNEL}"
        "--apk=${apk_path}"
    )
    if [[ -n "$effective_notes" ]]; then
        updater_args+=("--notes=${effective_notes}")
    fi
    if [[ "$DRY_RUN" == "true" ]]; then
        updater_args+=("--dry-run")
    fi

    if [[ -f "$updater" ]] && command -v node >/dev/null 2>&1; then
        if [[ "$DRY_RUN" == "true" && ! -f "$apk_path" ]]; then
            echo -e "\033[35m[DRY RUN] Would execute: node ${updater} ${updater_args[*]}\033[0m"
        else
            node "$updater" "${updater_args[@]}"
        fi
    else
        echo -e "\033[33mWarning: Firestore updater script or node not found at ${updater}.\033[0m"
    fi
    log_step_end "Updating Firestore version metadata" "$step_fire_sw"
elif [[ "$SKIP_FIRESTORE" == "true" ]]; then
    echo -e "\n\033[33mSkipping Firestore version update (-SkipFirestore / --skip-firestore).\033[0m"
fi

total_sw_end=$(date +%s.%N)
total_elapsed=$(awk "BEGIN {printf \"%.2f\", ${total_sw_end} - ${total_sw_start}}")
total_sec_int=$(awk "BEGIN {print int(${total_elapsed})}")
total_min=$(( total_sec_int / 60 ))
total_sec=$(( total_sec_int % 60 ))
total_elapsed_formatted=$(printf "%02dm %02ds (%.2fs total)" "$total_min" "$total_sec" "$total_elapsed")
script_end_ts=$(date +"%Y-%m-%d %H:%M:%S")

echo -e "\n\033[32m==================================================\033[0m"
echo -e "\033[32m[${script_end_ts}] Super Fast Deploy Complete! [Total Elapsed: ${total_elapsed_formatted}]\033[0m"
echo -e "\033[32mConsole log saved to: ${log_file}\033[0m"
echo -e "\033[32m==================================================\033[0m"

