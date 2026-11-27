# Exercise Library and Editor

Marble treats an exercise as a reusable definition for logging and planning. The exercise
stores how a set should be entered; each completed attempt is still stored separately as a
`SetEntry`.

## Find and manage exercises

- The exercise picker shows each exercise once: recent exercises first, then remaining
  favorites, then the rest of the library.
- Search filters as you type. When there is no exact match, **Create “Name”** opens a new
  exercise with that name already filled in.
- Open **Manage** from the picker, or **Add → Settings → Data & Backups → Exercise
  Library**, to
  search, filter by category, favorite, edit, or add exercises.

## Create an exercise

1. Name the exercise. A search in the picker carries its text into this field.
   Three suggested emoji appear below a valid new name. Tap one to select it, or tap
   the selected icon again to use the category symbol. You can save immediately.
2. For a lift logged by total weight and reps, tap **Save**. To log it differently, tap
   the current type under **Tracking** and choose a full-width row. Two Dumbbells logs
   the weight per hand. Sprint opens its plan fields, and Custom lets you choose metrics.
3. Adjust rest or the settings specific to the tracking type. **Library** holds the
   category, icon and favorite. These are optional.
4. Save the exercise to return to the library or use it immediately in the set you
   were logging. A duplicate name is flagged beside the name field.

## How suggested icons work

A phrase match gives common movements a stable set of choices. Dead Bug suggests 🐞,
and Ring Row suggests 🦍. For an unfamiliar name, the editor shows category suggestions
immediately. After typing pauses, an available Apple Intelligence model can classify the
movement on device and refine those choices. An unsupported locale, unavailable model,
or uncertain classification leaves the category choices usable. An emoji included in
the name is also offered. Editing the name preserves a selected icon. The custom keyboard
field remains in **Library → Icon & favorite → Emoji**.

Only Save writes the chosen emoji to the existing exercise record. The recommendation
does not change tracking type, muscle category, prior exercises, or the data schema.

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
