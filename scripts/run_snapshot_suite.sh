#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

destination=""
if destination=$("${ROOT_DIR}/scripts/sim_destination.sh" 2>/dev/null); then
  :
fi
sim_id="${destination#id=}"
if [[ "${destination}" != id=* ]]; then
  sim_id=""
fi

SNAPSHOT_GROUPS=(
  "MarbleSnapshotTests/AddSetSnapshotTests"
  "MarbleSnapshotTests/CalendarSnapshotTests"
  "MarbleSnapshotTests/ComponentGallerySnapshotTests"
  "MarbleSnapshotTests/JournalSnapshotTests"
  "MarbleSnapshotTests/SplitSnapshotTests"
  "MarbleSnapshotTests/SupplementsSnapshotTests"
  "MarbleSnapshotTests/TrendsSnapshotTests"
)

prepare_simulator() {
  if [[ -z "${sim_id}" ]]; then
    return 0
  fi
  xcrun simctl boot "${sim_id}" >/dev/null 2>&1 || true
  xcrun simctl bootstatus "${sim_id}" -b >/dev/null 2>&1 || true
}

cleanup_simulator() {
  if [[ -z "${sim_id}" ]]; then
    return 0
  fi
  xcrun simctl terminate "${sim_id}" Prism.marble >/dev/null 2>&1 || true
  xcrun simctl shutdown "${sim_id}" >/dev/null 2>&1 || true
  sleep 2
}

index=0
for group in "${SNAPSHOT_GROUPS[@]}"; do
  result_path="${ROOT_DIR}/TestResults/MarbleSnapshots_${index}.xcresult"
  echo "Running snapshot group: ${group}"
  prepare_simulator
  RESULT_BUNDLE_PATH="${result_path}" "${ROOT_DIR}/scripts/xcodebuild_test.sh" -only-testing:"${group}" "$@"
  cleanup_simulator
  index=$((index + 1))
done
