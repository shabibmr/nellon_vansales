#!/usr/bin/env bash
set -euo pipefail

ANDROID_HOME="${ANDROID_HOME:-$HOME/android-sdk}"
export ANDROID_HOME

if [[ -x /opt/flutter/bin/flutter ]]; then
  export PATH="/opt/flutter/bin:${PATH}"
elif [[ -x "${HOME}/flutter/bin/flutter" ]]; then
  export PATH="${HOME}/flutter/bin:${PATH}"
else
  echo "Flutter SDK not found at /opt/flutter or ${HOME}/flutter" >&2
  exit 1
fi

export PATH="${ANDROID_HOME}/platform-tools:${PATH}"

if [[ ! -f "${ANDROID_HOME}/cmdline-tools/latest/bin/sdkmanager" ]]; then
  mkdir -p "${ANDROID_HOME}/cmdline-tools"
  tmp_dir="$(mktemp -d)"
  trap 'rm -rf "${tmp_dir}"' EXIT
  curl -fsSL https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip \
    -o "${tmp_dir}/cmdtools.zip"
  unzip -q "${tmp_dir}/cmdtools.zip" -d "${ANDROID_HOME}/cmdline-tools"
  mv "${ANDROID_HOME}/cmdline-tools/cmdline-tools" "${ANDROID_HOME}/cmdline-tools/latest"
fi

set +o pipefail
yes | "${ANDROID_HOME}/cmdline-tools/latest/bin/sdkmanager" --licenses >/dev/null 2>&1 || true
set -o pipefail

"${ANDROID_HOME}/cmdline-tools/latest/bin/sdkmanager" \
  "platform-tools" \
  "platforms;android-34" \
  "platforms;android-37.0" \
  "build-tools;34.0.0" \
  "build-tools;35.0.0"

if [[ -d "${ANDROID_HOME}/platforms/android-37.0" && ! -e "${ANDROID_HOME}/platforms/android-37" ]]; then
  ln -sfn android-37.0 "${ANDROID_HOME}/platforms/android-37"
fi

flutter config --android-sdk "${ANDROID_HOME}" --no-analytics
flutter precache --android

cd /workspace
flutter pub get
