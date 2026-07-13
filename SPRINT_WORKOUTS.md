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

## Persistence and backup

`SprintPrescription` is an additive SwiftData model in `MarbleSchemaV3`. It references an
exercise by stable exercise ID rather than changing the shipped `Exercise` model checksum.
The seed/recovery path removes orphaned prescriptions, and JSON backup/restore includes them
with reference and target validation. Backups made before V3 remain decodable because the
new top-level collection is optional.

Key implementation files:

- `marble/Models/SprintPrescription.swift`
- `marble/Features/Journal/SprintPrescriptionEditorView.swift`
- `marble/Features/Journal/SprintGoalCardView.swift`
- `marble/Features/Journal/AddSetView.swift`
- `Tests/Unit/SprintPrescriptionTests.swift`
