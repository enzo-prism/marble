# Exercise Library and Editor

Marble treats an exercise as a reusable definition for logging and planning. The exercise
stores how a set should be entered; each completed attempt is still stored separately as a
`SetEntry`.

## Find and manage exercises

- The exercise picker shows each exercise once: recent exercises first, then remaining
  favorites, then the rest of the library.
- Search filters as you type. When there is no exact match, **Create “Name”** opens a new
  exercise with that name already filled in.
- Open **Manage** from the picker, or **Workout → Settings → Data & Backups → Exercise
  Library**, to
  search, filter by category, favorite, edit, or add exercises.

## Create an exercise

1. Enter a name and choose a category.
2. Choose the closest tracking type: Strength, Two Dumbbells, Bodyweight, Weighted
   Bodyweight, Run, Sprint, Jump / Plyometric, Timed, or Custom.
3. Complete only the fields relevant to that type. Standard types choose safe tracking
   defaults; Custom exposes the Weight, Repetitions, Distance, and Time requirements.
4. Choose the default rest after a set.
5. Optionally open **Appearance & Advanced** to favorite the exercise, use an emoji, or
   customize the tracked fields.
6. Save. Validation appears together at the top and beside the field that needs attention.

## Exercise attributes

- Name and category.
- Category symbol or one custom emoji.
- Favorite status.
- Metric requirement for weight, repetitions, distance, and duration: off, optional, or
  required on every set.
- Total-load or one-dumbbell-per-hand weight entry.
- Preferred distance unit.
- Default rest after each set.
- Optional Sprint prescription: fixed distance, repeat count, exact or ranged target time,
  and recovery.

## Editing and deletion safety

The editor works on a draft and does not mutate the saved exercise until Save. Dismissing a
dirty draft asks before discarding it. If a tracking change can reinterpret logged sets, or
if a prescription/default change affects planned workout slots, Marble explains the impact
and asks for confirmation.

An exercise can be deleted only when it has no logged sets and no planned workout slots.
The dependency check runs both before showing the confirmation and immediately before the
delete is committed.

Saving a created or renamed exercise reindexes the library so Siri and Spotlight see the
new name immediately; deleting one removes its Spotlight entry right away rather than at
the next launch. Both paths re-register the "Log a set of …" shortcut phrase against the
current names.

Key implementation files:

- `marble/Features/Journal/ExerciseEditorDraft.swift`
- `marble/Features/Journal/ExerciseEditorView.swift`
- `marble/Features/Journal/ExercisePickerView.swift`
- `marble/Features/Journal/ManageExercisesView.swift`
- `marble/Features/Journal/ExerciseLibraryPresentation.swift`
- `marble/Intents/ExerciseEntity.swift`
- `Tests/Unit/ExerciseEditorDraftTests.swift`
- `Tests/UI/JournalFlowUITests.swift`

## Design basis

The flow follows Apple's current guidance: a concise searchable list for the library,
standard grouped Form sections for related fields, a focused modal with visible Cancel and
Save actions, inline validation, 44-point controls, Dynamic Type reflow, and Liquid Glass
limited to navigation and controls.

- [Lists and tables](https://developer.apple.com/design/human-interface-guidelines/lists-and-tables)
- [Searching](https://developer.apple.com/design/human-interface-guidelines/searching)
- [Modality](https://developer.apple.com/design/human-interface-guidelines/modality)
- [Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility)
- [Adopting Liquid Glass](https://developer.apple.com/documentation/TechnologyOverviews/adopting-liquid-glass)
