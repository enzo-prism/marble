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
  "MarbleSnapshotTests/TrendsSnapshotTests/testTrendsDetails"
  "MarbleSnapshotTests/TrendsSnapshotTests/testTrendsCategoryCharts"
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

# A shard selects complete groups; History's two real content-size launches stay
# together. The default still runs every group for release evidence.
shard_count=${SNAPSHOT_SHARD_COUNT:-1}
shard_index=${SNAPSHOT_SHARD_INDEX:-0}
if [[ ! "$shard_count" =~ ^([1-9]|[1-9][0-9]|100)$ || ! "$shard_index" =~ ^(0|[1-9][0-9]?)$ ]] ||
   (( shard_index >= shard_count )); then
  echo "Invalid snapshot shard: index=$shard_index count=$shard_count" >&2
  exit 1
fi
if (( shard_count > 1 )); then
  selected_groups=()
  for group_index in "${!SNAPSHOT_GROUPS[@]}"; do
    if (( group_index % shard_count == shard_index )); then
      selected_groups+=("${SNAPSHOT_GROUPS[$group_index]}")
    fi
  done
  SNAPSHOT_GROUPS=("${selected_groups[@]}")
  echo "Snapshot shard $shard_index/$shard_count: ${#SNAPSHOT_GROUPS[@]} groups"
fi
if [[ "${SNAPSHOT_LIST_ONLY:-0}" == 1 ]]; then
  printf '%s\n' "${SNAPSHOT_GROUPS[@]}"
  exit 0
fi

prepare_simulator() {
  if [[ -z "${sim_id}" ]]; then
    return 0
  fi
  xcrun simctl boot "${sim_id}" >/dev/null 2>&1 || true
  xcrun simctl bootstatus "${sim_id}" -b >/dev/null 2>&1 || true
}

# Keep the simulator booted across groups. A full shutdown/boot pair per group
# is what stretched Release checks past four hours on d1de18b.
reset_app() {
  if [[ -z "${sim_id}" ]]; then
    return 0
  fi
  xcrun simctl terminate "${sim_id}" Prism.marble >/dev/null 2>&1 || true
}

snapshot_result_path() {
  local label="$1"
  local suffix="${2:-}"
  local slug
  slug=$(printf '%s' "${label}" | tr '/:' '--' | tr -cd 'A-Za-z0-9._-')
  if [[ -n "${RELEASE_EVIDENCE_RUN_DIR:-}" ]]; then
    printf '%s/%s/%02d-%s%s.xcresult' \
      "${RELEASE_EVIDENCE_RUN_DIR}" "${RELEASE_EVIDENCE_SUITE:-snapshot}" \
      "${index}" "${slug}" "${suffix}"
  else
    printf '%s/TestResults/MarbleSnapshots_%s%s.xcresult' \
      "${ROOT_DIR}" "${index}" "${suffix}"
  fi
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
other_groups=()
history_groups=()
for group in "${SNAPSHOT_GROUPS[@]}"; do
  if [[ "${group}" == "MarbleSnapshotTests/WorkoutHistorySnapshotTests"* ]]; then
    history_groups+=("${group}")
  else
    other_groups+=("${group}")
  fi
done

prepare_simulator

if (( ${#other_groups[@]} > 0 )); then
  result_path=$(snapshot_result_path "snapshots")
  echo "Running snapshot groups (${#other_groups[@]}): ${other_groups[*]}"
  only_flags=()
  for group in "${other_groups[@]}"; do
    only_flags+=(-only-testing:"${group}")
  done
  RESULT_BUNDLE_PATH="${result_path}" "${ROOT_DIR}/scripts/xcodebuild_test.sh" "${only_flags[@]}" "$@"
  reset_app
  index=$((index + 1))
fi

for group in "${history_groups[@]}"; do
  if [[ -z "${sim_id}" ]]; then
    echo "History snapshot isolation requires a concrete simulator ID." >&2
    exit 1
  fi
  for category in default a11y; do
    result_path=$(snapshot_result_path "${group}" "-${category}")
    echo "Running snapshot group: ${group}-${category}"
    history_original_content_size=$(xcrun simctl ui "${sim_id}" content_size)
    system_category=large
    [[ "${category}" != a11y ]] || system_category=accessibility-extra-extra-extra-large
    xcrun simctl ui "${sim_id}" content_size "${system_category}"
    RESULT_BUNDLE_PATH="${result_path}" "${ROOT_DIR}/scripts/xcodebuild_test.sh" \
      -only-testing:"${group}" "MARBLE_HISTORY_SNAPSHOT_CATEGORY=${category}" "$@"
    restore_history_content_size
    reset_app
    index=$((index + 1))
  done
done
