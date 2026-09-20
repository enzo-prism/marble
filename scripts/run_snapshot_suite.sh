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
  "MarbleSnapshotTests/AddSetSnapshotTests/testAddSetWeightAndRepsWithHistory"
  "MarbleSnapshotTests/AddSetSnapshotTests/testAddSetRepsOnlyAddedLoadOff"
  "MarbleSnapshotTests/AddSetSnapshotTests/testAddSetRepsOnlyAddedLoadOn"
  "MarbleSnapshotTests/AddSetSnapshotTests/testAddSetDurationOnly"
  "MarbleSnapshotTests/CalendarSnapshotTests/testCalendarMonthWithMarkers"
  "MarbleSnapshotTests/CalendarSnapshotTests/testCalendarDaySheetWithEntries"
  "MarbleSnapshotTests/CalendarSnapshotTests/testCalendarDaySheetEmpty"
  "MarbleSnapshotTests/CalendarSnapshotTests/testCalendarDaySheetWithProgressMedia"
  "MarbleSnapshotTests/ComponentGallerySnapshotTests/testComponentGallery"
  "MarbleSnapshotTests/ExerciseProgressSnapshotTests/testExerciseProgressTooltip"
  "MarbleSnapshotTests/JournalSnapshotTests/testJournalEmpty"
  "MarbleSnapshotTests/JournalSnapshotTests/testJournalPopulated"
  "MarbleSnapshotTests/JournalSnapshotTests/testJournalLongName"
  "MarbleSnapshotTests/JournalSnapshotTests/testJournalExtremes"
  "MarbleSnapshotTests/JournalSnapshotTests/testDefaultAddTabVisible"
  "MarbleSnapshotTests/JournalSnapshotTests/testJournalBodyweightBest"
  "MarbleSnapshotTests/JournalSnapshotTests/testJournalRunBest"
  "MarbleSnapshotTests/LastTimeSnapshotTests/testLastTimeCardHistory"
  "MarbleSnapshotTests/LastTimeSnapshotTests/testLastTimeCardBodyweight"
  "MarbleSnapshotTests/LastTimeSnapshotTests/testLastTimeCardEmpty"
  "MarbleSnapshotTests/NotificationsSnapshotTests/testNotificationsEmpty"
  "MarbleSnapshotTests/NotificationsSnapshotTests/testNotificationsPopulated"
  "MarbleSnapshotTests/NotificationsSnapshotTests/testNotificationsMaxLimit"
  "MarbleSnapshotTests/NotificationsSnapshotTests/testNotificationEditor"
  "MarbleSnapshotTests/SplitSnapshotTests/testSplitEmpty"
  "MarbleSnapshotTests/SplitSnapshotTests/testSplitPopulated"
  "MarbleSnapshotTests/SupplementsSnapshotTests/testSupplementsEmpty"
  "MarbleSnapshotTests/SupplementsSnapshotTests/testSupplementsPopulated"
  "MarbleSnapshotTests/TrendsSnapshotTests/testTrendsEmpty"
  "MarbleSnapshotTests/TrendsSnapshotTests/testTrendsPopulated"
  "MarbleSnapshotTests/TrendsSnapshotTests/testTrendsDailyHighlights"
  "MarbleSnapshotTests/TrendsSnapshotTests/testTrendsFilteredExercise"
  "MarbleSnapshotTests/TrendsSnapshotTests/testTrendsExerciseSearch"
  "MarbleSnapshotTests/TrendsSnapshotTests/testTrendsConsistencyTooltip"
  "MarbleSnapshotTests/TrendsSnapshotTests/testTrendsVolumeTooltip"
  "MarbleSnapshotTests/TrendsSnapshotTests/testTrendsSupplementsTooltip"
  "MarbleSnapshotTests/WorkoutComposerSnapshotTests"
  "MarbleSnapshotTests/PersistenceRecoverySnapshotTests/testTemporarilyUnavailable"
  "MarbleSnapshotTests/PersistenceRecoverySnapshotTests/testDamagedStore"
  "MarbleSnapshotTests/WorkoutHistorySnapshotTests"
  # Widget families — the app's only surface outside itself. One group: these
  # render fixed-size cards, not full screens, so they are fast.
  "MarbleSnapshotTests/WeeklyGoalWidgetSnapshotTests"
)

SNAPSHOT_GROUPS_QUICK=(
  "MarbleSnapshotTests/JournalSnapshotTests/testJournalPopulated"
  "MarbleSnapshotTests/CalendarSnapshotTests/testCalendarMonthWithMarkers"
  "MarbleSnapshotTests/SplitSnapshotTests/testSplitPopulated"
  "MarbleSnapshotTests/SupplementsSnapshotTests/testSupplementsPopulated"
  "MarbleSnapshotTests/TrendsSnapshotTests/testTrendsPopulated"
  "MarbleSnapshotTests/AddSetSnapshotTests/testAddSetWeightAndReps"
  "MarbleSnapshotTests/WorkoutComposerSnapshotTests/testWorkoutComposerEmpty"
)

verify_full_coverage() {
  local file class_name method identifier group scheduled
  local missing=()

  for file in "${ROOT_DIR}"/Tests/Snapshots/*SnapshotTests.swift; do
    class_name=$(sed -nE 's/.*final class ([A-Za-z0-9_]+): SnapshotTestCase.*/\1/p' "${file}" | head -n 1)
    [[ -n "${class_name}" ]] || continue

    while IFS= read -r method; do
      identifier="MarbleSnapshotTests/${class_name}/${method}"
      scheduled=false
      for group in "${SNAPSHOT_GROUPS_FULL[@]}"; do
        if [[ "${group}" == "${identifier}" || "${group}" == "MarbleSnapshotTests/${class_name}" ]]; then
          scheduled=true
          break
        fi
      done
      if [[ "${scheduled}" != true ]]; then
        missing+=("${identifier}")
      fi
    done < <(sed -nE 's/^[[:space:]]*func (test[A-Za-z0-9_]+).*/\1/p' "${file}")
  done

  if (( ${#missing[@]} > 0 )); then
    printf 'Full snapshot runner is missing source tests:\n' >&2
    printf '  %s\n' "${missing[@]}" >&2
    return 1
  fi
}

if [[ -n "${SNAPSHOT_GROUPS_OVERRIDE:-}" ]]; then
  IFS=',' read -r -a SNAPSHOT_GROUPS <<< "${SNAPSHOT_GROUPS_OVERRIDE}"
elif [[ "${SNAPSHOT_SUITE}" == "quick" ]]; then
  SNAPSHOT_GROUPS=("${SNAPSHOT_GROUPS_QUICK[@]}")
else
  verify_full_coverage
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

# Native UIKit search caches its initial font from the process-wide category.
# A child hosting-controller override cannot faithfully simulate changing that
# initial category. Launch History separately for each real simulator text size.
history_original_content_size=""
restore_history_content_size() {
  if [[ -n "${history_original_content_size}" ]]; then
    xcrun simctl ui "${sim_id}" content_size "${history_original_content_size}"
    history_original_content_size=""
  fi
}
trap 'snapshot_exit_status=$?; restore_history_content_size || snapshot_exit_status=1; exit "${snapshot_exit_status}"' EXIT

index=0
for group in "${SNAPSHOT_GROUPS[@]}"; do
  categories=("")
  if [[ "${group}" == "MarbleSnapshotTests/WorkoutHistorySnapshotTests"* ]]; then
    if [[ -z "${sim_id}" ]]; then
      echo "History snapshot isolation requires a concrete simulator ID." >&2
      exit 1
    fi
    categories=(default a11y)
  fi
  for category in "${categories[@]}"; do
    group_suffix="${category:+-${category}}"
    if [[ -n "${RELEASE_EVIDENCE_RUN_DIR:-}" ]]; then
      group_slug=$(printf '%s' "${group}" | tr '/:' '--' | tr -cd 'A-Za-z0-9._-')
      printf -v result_name '%02d-%s%s.xcresult' "${index}" "${group_slug}" "${group_suffix}"
      result_path="${RELEASE_EVIDENCE_RUN_DIR}/${RELEASE_EVIDENCE_SUITE:-snapshot}/${result_name}"
    else
      result_path="${ROOT_DIR}/TestResults/MarbleSnapshots_${index}${group_suffix}.xcresult"
    fi
    echo "Running snapshot group: ${group}${group_suffix}"
    prepare_simulator
    if [[ -n "${category}" ]]; then
      history_original_content_size=$(xcrun simctl ui "${sim_id}" content_size)
      system_category=large
      [[ "${category}" != a11y ]] || system_category=accessibility-extra-extra-extra-large
      xcrun simctl ui "${sim_id}" content_size "${system_category}"
    fi
    if [[ -n "${category}" ]]; then
      RESULT_BUNDLE_PATH="${result_path}" "${ROOT_DIR}/scripts/xcodebuild_test.sh" -only-testing:"${group}" "MARBLE_HISTORY_SNAPSHOT_CATEGORY=${category}" "$@"
    else
      RESULT_BUNDLE_PATH="${result_path}" "${ROOT_DIR}/scripts/xcodebuild_test.sh" -only-testing:"${group}" "$@"
    fi
    restore_history_content_size
    cleanup_simulator
    index=$((index + 1))
  done
done
