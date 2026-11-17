#!/usr/bin/env bash
# Print xcodebuild -only-testing flags (or class names) for one Release UI shard.
#
# Shard 1 is the classes that ran in the first 60 min of dispatch 44145967148
# (through KeyboardLayout). Shards 2 and 3 split the remaining suites so no
# UI job plus ~25% headroom needs a cap over 120 minutes. Together the shards
# are `make ui`: every MarbleUITests class except AccessibilityAuditUITests.
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
MODE=flags
SHARD=""

usage() {
  echo "Usage: scripts/release_ui_shards.sh [--classes] 1|2|3" >&2
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --classes)
      MODE=classes
      shift
      ;;
    1|2|3)
      SHARD="$1"
      shift
      ;;
    *)
      usage
      ;;
  esac
done

[[ -n "${SHARD}" ]] || usage

shard_1=(
  AddSetAccessibilityUITests
  AppIntentSystemPathUITests
  AppStoreScreenshotUITests
  CalendarFlowUITests
  DraftResumeUITests
  ImportFlowUITests
  JournalFlowUITests
  KeyboardLayoutUITests
)
shard_2=(
  LogModePickerUITests
  NativeWorkoutDeviceUITests
  NotificationsFlowUITests
  OnboardingFlowUITests
  PersistenceRecoveryUITests
  ProgressMediaUITests
  RestTimerPillUITests
  ScanFlowUITests
)
shard_3=(
  SettingsFlowUITests
  SmokeNavigationUITests
  SplitFlowUITests
  SupplementsFlowUITests
  TrendsSelectionUITests
  TrendsSmokeUITests
  WorkoutDictationDeviceUITests
  WorkoutFlowUITests
  WorkoutHistoryUITests
)

case "${SHARD}" in
  1) classes=("${shard_1[@]}") ;;
  2) classes=("${shard_2[@]}") ;;
  3) classes=("${shard_3[@]}") ;;
esac

emit() {
  local class
  if [[ "${MODE}" == classes ]]; then
    printf '%s\n' "${classes[@]}"
    return
  fi
  for class in "${classes[@]}"; do
    printf -- '-only-testing:MarbleUITests/%s ' "${class}"
  done
  printf '\n'
}

# Keep the file next to Tests/UI so a missing class fails locally, not in CI.
for class in "${classes[@]}"; do
  if [[ ! -f "${ROOT_DIR}/Tests/UI/${class}.swift" ]]; then
    echo "UI shard ${SHARD} refers to missing Tests/UI/${class}.swift" >&2
    exit 1
  fi
done

emit
