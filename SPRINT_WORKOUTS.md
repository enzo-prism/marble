# Sprint Workouts

Marble supports reusable sprint plans ("variants") for exercises that track both distance
and duration. An exercise can hold **several plans** — "60 m speed" and "150 m tempo" on
the same Sprint exercise — and each completed sprint remains a normal `SetEntry` in the
journal, plus a tenths-precision companion record.

## Plan attributes

- Optional name ("Speed", "Tempo") shown in the logger's plan picker.
- Fixed distance and unit, such as 60 m or 150 m.
- Repetition count from 1 through 50.
- Either one target time (for example, 14.5 seconds or faster) or an inclusive target
  range (for example, 19–21.5 seconds).

**Times are tenths-precision throughout** (see `SprintTiming`): targets and recorded reps
are canonical integer tenths (14.8 s == 148), entered as decimal seconds. The shipped
whole-second `SetEntry.durationSeconds` column still stores the rounded value for every
legacy consumer. RPE and the actual recovery value are recorded on each completed set;
the default recovery lives on the exercise.

## Create or edit a sprint workout

1. Open **Manage** from the exercise picker, or open **Workout → Settings → Data & Backups →
   Exercise Library**, then add or edit an exercise.
2. Choose the explicit **Sprint** tracking type. Marble requires distance and time for every
   repetition and keeps the exercise in the Run category.
3. Set each plan's distance, number of repetitions, and either one target time or an
   inclusive target range (decimal seconds — 14.5 counts). **Add Sprint Plan** creates
   additional plans; each plan can be deleted while at least one remains.
4. Choose the default recovery after each repetition, then save.

Sprint setup is intentionally contextual: the editor hides strength-only controls and does
not show a second enable switch. Switching away from Sprint removes every plan only after
the same planned-workout safety checks used by other behavior-changing edits.

The primary (most recently used) plan's summary appears in exercise pickers, the weekly
plan, and the active Workout screen so the target is visible before logging begins.

## Log a sprint workout

Opening Add Set for a sprint exercise preselects the primary plan (a **Plan** menu on the
goal card switches between plans; switching restarts the rep count), locks the prescribed
distance, starts at Rep 1 of the planned total, and leaves actual time empty for entry.
Time is entered as decimal seconds ("14.8") or captured with the built-in **stopwatch** —
start it before the rep, stop it after, and the time fills in. Each saved repetition
records its own duration, RPE and rest. Marble evaluates the entered tenths against the
goal, starts the rest timer between repetitions, and changes the final action to Save
Final Rep.

**Save Final Rep shows the sequence rollup** — hits out of reps, best time, average, and
every rep's result — before the sheet closes.

When logging inside an active workout session, rep progress is derived from completed sets
in that session. Outside a session, the Add Set sheet tracks the current sequence locally.

After an athlete hits a plan's goal on at least 80% of scored reps in each of their last
two sessions, the goal card shows a **progression nudge** suggesting a 0.2 s tighter
target (`SprintProgression`).

## Review sprint results in Log

Every logged sprint shows its recorded distance and time plus a compact result line in the
Log (Sets) list and Quick Log preview:

- **Goal hit** uses a green checkmark and includes the saved target.
- **Goal missed** uses a red x-mark and includes the saved target.
- **Not scored** is neutral when time or distance is missing, or the recorded distance does
  not match the prescribed sprint.

The symbol and words always carry the result, so color is never the only signal. Selecting
the rep opens **Set Details**, where the Sprint Result card compares Recorded and Target,
explains the exact boundary result ("14.8s was 0.2 seconds faster…"), and identifies
whether the goal was saved when the rep was logged or recovered for an older entry.
Tenths-detailed reps edit their time as decimal seconds; editing updates the result
immediately against the same saved goal.

**Fastest-time PRs**: a rep that beats every earlier time at the same exercise and the
same distance earns a "Fastest" badge in the Journal, exactly like the weight/reps PR
trail (`PersonalRecords.sprintTimeBadges`). **Trends** gains a Sprints section — best-time
progression at the most-logged distance (gold dot on the record) and a weekly goal
hit-rate chart, both with Audio Graph descriptors.

## Persistence and backup

`SprintPrescription` is an additive SwiftData model in `MarbleSchemaV3`. It references an
exercise by stable exercise ID rather than changing the shipped `Exercise` model checksum.
`SprintGoalSnapshot` is an additive model in `MarbleSchemaV4`. It freezes the distance, target
bounds, planned rep count, and optional rep number for each logged result so later exercise
edits never rewrite history. The V4 launch backfill freezes the current prescription onto
eligible pre-V4 sprint entries and labels that provenance as recovered rather than claiming
it was known at log time.

**Schema V6** adds two additive models (same no-stage, raw-UUID pattern as V2–V5):

- `SprintVariant` — the multi-plan successor of `SprintPrescription`, with tenths targets
  and a non-unique `exerciseID`. The legacy prescription lives on as a **mirror of the
  primary variant** (`SprintVariant.syncLegacyPrescription`, rounded to whole seconds) so
  pre-V6 surfaces and backups stay truthful. A launch-time adoption sweep
  (`SprintVariant.adoptLegacyPrescriptions`, idempotent, run every launch) turns any
  legacy prescription — including ones recreated by restoring an old backup — into a
  variant.
- `SprintRepDetail` — per-rep companion to the goal snapshot: exact recorded tenths, the
  frozen tenths target, and the variant that was run. Read paths prefer it via
  `SprintGoalEvaluation.evaluate(snapshot:entry:detail:)`; pre-V6 reps keep the
  whole-second path byte-for-byte.

The seed/recovery path removes orphaned prescriptions, goal snapshots, variants, and rep
details. JSON backup/restore includes all four collections with reference and target
validation; older backups remain decodable because every post-1.0 collection is optional,
and restoring a pre-V6 backup adopts its prescriptions into variants immediately.

Key implementation files:

- `marble/Models/SprintTiming.swift` — canonical tenths arithmetic/formatting
- `marble/Models/SprintVariant.swift` — multi-plan model, adoption sweep, legacy mirror
- `marble/Models/SprintRepDetail.swift` — per-rep tenths record
- `marble/Models/SprintProgression.swift` — progression-nudge rule
- `marble/Models/SprintPrescription.swift` — legacy mirror model
- `marble/Models/SprintGoalSnapshot.swift` — frozen goals + evaluation (both domains)
- `marble/Features/Journal/SprintVariantEditorView.swift`
- `marble/Features/Journal/SprintGoalCardView.swift`
- `marble/Features/Journal/SprintSequenceSummaryView.swift`
- `marble/Components/SprintStopwatchView.swift`
- `marble/Components/SprintGoalResultView.swift`
- `marble/Features/Journal/AddSetView.swift`
- `marble/Features/Journal/JournalView.swift`
- `marble/Features/Journal/SetDetailView.swift`
- `marble/Features/Trends/SprintTrendsSection.swift`
- `Tests/Unit/SprintTimingTests.swift`
- `Tests/Unit/SprintVariantTests.swift`
- `Tests/Unit/SprintProgressionTests.swift`
- `Tests/Unit/SprintTimePRTests.swift`
- `Tests/Unit/SchemaV6MigrationTests.swift`
- `Tests/Unit/SprintPrescriptionTests.swift`
- `Tests/Unit/SprintGoalMigrationTests.swift`
