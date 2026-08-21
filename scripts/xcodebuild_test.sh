#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

SCHEME=${SCHEME:-marble}

if [[ -n "${WORKSPACE:-}" ]]; then
  PROJECT_ARGS=(-workspace "$WORKSPACE")
elif [[ -d "${ROOT_DIR}/marble.xcworkspace" ]]; then
  PROJECT_ARGS=(-workspace "${ROOT_DIR}/marble.xcworkspace")
elif [[ -n "${PROJECT:-}" ]]; then
  PROJECT_ARGS=(-project "$PROJECT")
elif [[ -d "${ROOT_DIR}/marble.xcodeproj" ]]; then
  PROJECT_ARGS=(-project "${ROOT_DIR}/marble.xcodeproj")
else
  echo "No .xcworkspace or .xcodeproj found. Set WORKSPACE or PROJECT." >&2
  exit 1
fi

DESTINATION=${DESTINATION:-$("${ROOT_DIR}/scripts/sim_destination.sh")}
DERIVED_DATA_PATH=${DERIVED_DATA_PATH:-"${ROOT_DIR}/DerivedData"}
mkdir -p "${DERIVED_DATA_PATH}"

RESULT_BUNDLE_PATH=${RESULT_BUNDLE_PATH-"${ROOT_DIR}/TestResults/Marble.xcresult"}

XCODEBUILD_CMD=(
  xcodebuild test
  "${PROJECT_ARGS[@]}"
  -scheme "$SCHEME"
  -destination "$DESTINATION"
  -configuration Debug
  -derivedDataPath "$DERIVED_DATA_PATH"
  -parallel-testing-enabled NO
  -enableCodeCoverage NO
)

# An explicitly empty path keeps focused reruns low-artifact when Xcode result
# recording is unavailable (for example after a confirmed ENOSPC). Normal runs
# still replace the single checkout-local bundle above.
if [[ -n "$RESULT_BUNDLE_PATH" ]]; then
  mkdir -p "$(dirname "${RESULT_BUNDLE_PATH}")"
  if [[ -e "${RESULT_BUNDLE_PATH}" ]]; then
    rm -rf "${RESULT_BUNDLE_PATH}"
  fi
  XCODEBUILD_CMD+=(-resultBundlePath "$RESULT_BUNDLE_PATH")
fi

XCODEBUILD_CMD+=("$@")

echo "Running: ${XCODEBUILD_CMD[*]}"

if command -v xcbeautify >/dev/null 2>&1; then
  set -o pipefail
  "${XCODEBUILD_CMD[@]}" | xcbeautify
else
  "${XCODEBUILD_CMD[@]}"
fi
