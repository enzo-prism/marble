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

SNAPSHOT_SUITE=${SNAPSHOT_SUITE:-full}

SNAPSHOT_GROUPS_FULL=(
  "MarbleSnapshotTests/AddSetSnapshotTests/testAddSetWeightAndReps"
  "MarbleSnapshotTests/AddSetSnapshotTests/testAddSetRepsOnlyAddedLoadOff"
  "MarbleSnapshotTests/AddSetSnapshotTests/testAddSetRepsOnlyAddedLoadOn"
  "MarbleSnapshotTests/AddSetSnapshotTests/testAddSetDurationOnly"
  "MarbleSnapshotTests/CalendarSnapshotTests/testCalendarMonthWithMarkers"
  "MarbleSnapshotTests/CalendarSnapshotTests/testCalendarDaySheetWithEntries"
  "MarbleSnapshotTests/CalendarSnapshotTests/testCalendarDaySheetEmpty"
  "MarbleSnapshotTests/ComponentGallerySnapshotTests/testComponentGallery"
  "MarbleSnapshotTests/ExerciseProgressSnapshotTests/testExerciseProgressTooltip"
  "MarbleSnapshotTests/JournalSnapshotTests/testJournalEmpty"
  "MarbleSnapshotTests/JournalSnapshotTests/testJournalPopulated"
  "MarbleSnapshotTests/JournalSnapshotTests/testJournalLongName"
  "MarbleSnapshotTests/JournalSnapshotTests/testJournalExtremes"
  "MarbleSnapshotTests/JournalSnapshotTests/testQuickLogVisible"
  "MarbleSnapshotTests/LastTimeSnapshotTests/testLastTimeCardHistory"
  "MarbleSnapshotTests/LastTimeSnapshotTests/testLastTimeCardBodyweight"
  "MarbleSnapshotTests/LastTimeSnapshotTests/testLastTimeCardEmpty"
  "MarbleSnapshotTests/SplitSnapshotTests/testSplitStates"
  "MarbleSnapshotTests/SupplementsSnapshotTests/testSupplementsEmpty"
  "MarbleSnapshotTests/SupplementsSnapshotTests/testSupplementsPopulated"
  "MarbleSnapshotTests/TrendsSnapshotTests/testTrendsEmpty"
  "MarbleSnapshotTests/TrendsSnapshotTests/testTrendsPopulated"
  "MarbleSnapshotTests/TrendsSnapshotTests/testTrendsFilteredExercise"
  "MarbleSnapshotTests/TrendsSnapshotTests/testTrendsSupplementsTooltip"
)

SNAPSHOT_GROUPS_QUICK=(
  "MarbleSnapshotTests/JournalSnapshotTests/testJournalPopulated"
  "MarbleSnapshotTests/CalendarSnapshotTests/testCalendarMonthWithMarkers"
  "MarbleSnapshotTests/SplitSnapshotTests/testSplitStates"
  "MarbleSnapshotTests/SupplementsSnapshotTests/testSupplementsPopulated"
  "MarbleSnapshotTests/TrendsSnapshotTests/testTrendsPopulated"
  "MarbleSnapshotTests/AddSetSnapshotTests/testAddSetWeightAndReps"
)

if [[ -n "${SNAPSHOT_GROUPS_OVERRIDE:-}" ]]; then
  IFS=',' read -r -a SNAPSHOT_GROUPS <<< "${SNAPSHOT_GROUPS_OVERRIDE}"
elif [[ "${SNAPSHOT_SUITE}" == "quick" ]]; then
  SNAPSHOT_GROUPS=("${SNAPSHOT_GROUPS_QUICK[@]}")
else
  SNAPSHOT_GROUPS=("${SNAPSHOT_GROUPS_FULL[@]}")
fi

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
