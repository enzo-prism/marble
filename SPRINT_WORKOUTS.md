# Sprint Workouts

Marble supports reusable sprint prescriptions for exercises that track both distance and
duration. A prescription keeps the intended workout attached to the exercise while each
completed sprint remains a normal `SetEntry` in the journal.

## Prescription attributes

- Fixed distance and unit, such as 60 m or 150 m.
- Repetition count from 1 through 50.
- Either one target time (for example, 19 seconds or faster) or an inclusive target range
  (for example, 19–21 seconds).
- Default recovery time after each repetition.

Target times currently use Marble's existing whole-second duration precision. RPE and the
actual recovery value are recorded on each completed set rather than on the prescription.

## Create or edit a sprint workout

1. Open **Manage** from the exercise picker, or open **Workout → Data & Backups → Exercise
   Library**, then add or edit an exercise.
2. Choose the explicit **Sprint** tracking type. Marble requires distance and time for every
   repetition and keeps the exercise in the Run category.
3. Set the distance, number of repetitions, and either one target time or an inclusive target
   range.
4. Choose the default recovery after each repetition, then save.

Sprint setup is intentionally contextual: the editor hides strength-only controls and does
not show a second enable switch. Switching away from Sprint removes the prescription only
after the same planned-workout safety checks used by other behavior-changing edits.

The prescription summary appears in exercise pickers, the weekly plan, and the active
Workout screen so the target is visible before logging begins.

## Log a sprint workout

Opening Add Set for a sprint exercise locks the prescribed distance, starts at Rep 1 of the
planned total, and leaves actual time empty for entry. Each saved repetition records its own
duration, RPE and rest. Marble evaluates the entered time against the goal, starts the rest
timer between repetitions, and changes the final action to Save Final Rep.

When logging inside an active workout session, rep progress is derived from completed sets in
that session. Outside a session, the Add Set sheet tracks the current sequence locally.

## Review sprint results in Journal

Every logged sprint shows its recorded distance and time plus a compact result line in the
Journal and Quick Log preview:

- **Goal hit** uses a green checkmark and includes the saved target.
- **Goal missed** uses a red x-mark and includes the saved target.
- **Not scored** is neutral when time or distance is missing, or the recorded distance does
  not match the prescribed sprint.

The symbol and words always carry the result, so color is never the only signal. Selecting
the rep opens **Set Details**, where the Sprint Result card compares Recorded and Target,
explains the exact boundary result, and identifies whether the goal was saved when the rep
was logged or recovered for an older entry. Editing the recorded time or distance updates the
result immediately against the same saved goal.

## Persistence and backup

`SprintPrescription` is an additive SwiftData model in `MarbleSchemaV3`. It references an
exercise by stable exercise ID rather than changing the shipped `Exercise` model checksum.
`SprintGoalSnapshot` is an additive model in `MarbleSchemaV4`. It freezes the distance, target
bounds, planned rep count, and optional rep number for each logged result so later exercise
edits never rewrite history. The V4 launch backfill freezes the current prescription onto
eligible pre-V4 sprint entries and labels that provenance as recovered rather than claiming
it was known at log time.

The seed/recovery path removes orphaned prescriptions and goal snapshots. JSON backup/restore
includes both collections with reference and target validation; older backups remain
decodable because both top-level collections are optional.

Key implementation files:

- `marble/Models/SprintPrescription.swift`
- `marble/Models/SprintGoalSnapshot.swift`
- `marble/Features/Journal/SprintPrescriptionEditorView.swift`
- `marble/Features/Journal/SprintGoalCardView.swift`
- `marble/Components/SprintGoalResultView.swift`
- `marble/Features/Journal/AddSetView.swift`
- `marble/Features/Journal/JournalView.swift`
- `marble/Features/Journal/SetDetailView.swift`
- `Tests/Unit/SprintPrescriptionTests.swift`
- `Tests/Unit/SprintGoalMigrationTests.swift`
