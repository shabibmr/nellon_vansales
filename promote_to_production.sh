#!/usr/bin/env bash
#
# Script to promote the validated test build directly to PRODUCTION on VPS.
#
# USAGE:
#   ./promote_to_production.sh
#   ./promote_to_production.sh --notes "Hotfix release"
#   ./promote_to_production.sh --dry-run
#

set -euo pipefail

# Determine repository root
repoRoot="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$repoRoot"

# Defaults
SSH_HOST="gm1"
SOURCE_PATH="/var/www/html/algo_cloud/nellon/test/app-nellon-release.apk"
TARGET_PATH="/var/www/html/algo_cloud/nellon/app-nellon-release.apk"
NOTES=""
FORCE=false
DRY_RUN=false

show_help() {
    cat <<EOF
Promote Test APK to PRODUCTION on VPS

Usage:
  ./promote_to_production.sh [options]

Options:
  -SshHost, --ssh-host <host>       SSH host alias or address (default: gm1)
  -Source, --source <path>          Source test APK path (default: /var/www/html/algo_cloud/nellon/test/app-nellon-release.apk)
  -Target, --target <path>          Target production APK path (default: /var/www/html/algo_cloud/nellon/app-nellon-release.apk)
  -Notes, --notes <notes>           Release notes for Firestore (defaults to latest git commit or existing config)
  -Force, --force                   Set force_update flag in Firestore
  -DryRun, --dry-run                Simulate promotion without modifying files or Firestore
  -h, --help                        Show this help message
EOF
}

# Parse Arguments (Supporting both --kebab-case and -PascalCase)
while [[ $# -gt 0 ]]; do
    case "$1" in
        --ssh-host|-SshHost)
            SSH_HOST="$2"
            shift 2
            ;;
        --source|-Source)
            SOURCE_PATH="$2"
            shift 2
            ;;
        --target|-Target)
            TARGET_PATH="$2"
            shift 2
            ;;
        --notes|-Notes)
            NOTES="$2"
            shift 2
            ;;
        --force|-Force)
            FORCE=true
            shift
            ;;
        --dry-run|-DryRun)
            DRY_RUN=true
            shift
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

total_sw_start=$(date +%s.%N)
script_start_ts=$(date +"%Y-%m-%d %H:%M:%S")

echo -e "\033[33m==============================================\033[0m"
echo -e "\033[33m[${script_start_ts}] Promoting Test APK to PRODUCTION on VPS...\033[0m"
echo -e "\033[33m==============================================\033[0m"

# Step 1: Copy test APK to production root on VPS
step1_sw=$(log_step_start "Copying remote APK: ${SOURCE_PATH} -> ${TARGET_PATH} on VPS...")

if [[ "$DRY_RUN" == "true" ]]; then
    echo -e "\033[35m[DRY RUN] Would execute: cp '${SOURCE_PATH}' '${TARGET_PATH}'\033[0m"
elif [[ -d "/var/www/html/algo_cloud" && ( "$SSH_HOST" == "gm1" || "$SSH_HOST" == "localhost" || "$SSH_HOST" == "127.0.0.1" ) ]]; then
    if [[ ! -f "$SOURCE_PATH" ]]; then
        echo -e "\033[31mError: Source test APK not found at ${SOURCE_PATH}\033[0m" >&2
        exit 1
    fi
    target_dir="$(dirname "$TARGET_PATH")"
    mkdir -p "$target_dir"
    cp -f "$SOURCE_PATH" "$TARGET_PATH"
    chmod 644 "$TARGET_PATH" || true
    echo -e "\033[32mCopied locally: ${SOURCE_PATH} -> ${TARGET_PATH}\033[0m"
else
    ssh "$SSH_HOST" "cp '$SOURCE_PATH' '$TARGET_PATH' && chmod 644 '$TARGET_PATH' || true"
fi
log_step_end "Copying remote APK to production" "$step1_sw"

echo -e "\n\033[32m==============================================\033[0m"
echo -e "\033[32mProduction APK is now live on VPS!\033[0m"
echo -e "\033[32m==============================================\033[0m"

# Step 2: Update Production Firestore metadata
step2_sw=$(log_step_start "Updating PRODUCTION channel version in Firebase Firestore...")

updater="${repoRoot}/scripts/update_firestore_version.js"
updater_args=("--channel=production")

# If target APK is accessible locally, pass it so the sha256 hash is computed accurately
if [[ -f "$TARGET_PATH" ]]; then
    updater_args+=("--apk=${TARGET_PATH}")
elif [[ -f "$SOURCE_PATH" ]]; then
    updater_args+=("--apk=${SOURCE_PATH}")
fi

if [[ -n "$NOTES" ]]; then
    updater_args+=("--notes=${NOTES}")
fi
if [[ "$FORCE" == "true" ]]; then
    updater_args+=("--force=true")
fi
if [[ "$DRY_RUN" == "true" ]]; then
    updater_args+=("--dry-run")
fi

if [[ -f "$updater" ]] && command -v node >/dev/null 2>&1; then
    node "$updater" "${updater_args[@]}"
else
    echo -e "\033[31mError: Firestore updater script or node runtime not found at ${updater}\033[0m" >&2
    exit 1
fi
log_step_end "Updating PRODUCTION channel version in Firestore" "$step2_sw"

total_sw_end=$(date +%s.%N)
total_elapsed=$(awk "BEGIN {printf \"%.2f\", ${total_sw_end} - ${total_sw_start}}")
total_sec_int=$(awk "BEGIN {print int(${total_elapsed})}")
total_min=$(( total_sec_int / 60 ))
total_sec=$(( total_sec_int % 60 ))
total_elapsed_formatted=$(printf "%02dm %02ds (%.2fs total)" "$total_min" "$total_sec" "$total_elapsed")
script_end_ts=$(date +"%Y-%m-%d %H:%M:%S")

echo -e "\n\033[32m==============================================\033[0m"
echo -e "\033[32m[${script_end_ts}] SUCCESS: Release is active for all production users! [Total Elapsed: ${total_elapsed_formatted}]\033[0m"
echo -e "\033[32m==============================================\033[0m"
