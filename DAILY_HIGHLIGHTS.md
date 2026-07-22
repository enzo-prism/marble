# Daily Highlights

Daily Highlights is Marble's end-of-day celebration in Trends. It turns the work already
stored on the device into a calm, shareable recap without adding an account, server, or
background process.

## User experience

- The section is enabled by default from **8:00 PM through 11:59 PM local time**.
- It appears only when that celebration day contains at least one valid training log. It is
  absent outside the active window and on empty days.
- The clock action on the card, and **Settings → Training → Daily Highlights**, open the same
  editor. Users can disable the feature or choose a custom start and end time. An end time
  earlier than the start is intentionally treated as an overnight window; equal times are
  rejected rather than interpreted as “always on.”
- The in-app card uses Marble's normal Dynamic Type and accessibility behavior. The share
  action creates a control-free **1080 × 1350 PNG (4:5)** and hands it to the system share
  sheet. Nothing is uploaded automatically.

## What is celebrated

`DailyHighlightsBuilder` derives the recap from the full `SetEntry` history, independent of
the Trends range and exercise filter. It ranks at most three deterministic highlights and
uses one highlight per exercise:

1. Genuine strength records: a higher unit-normalized weight or a higher bodyweight rep
   count than a previous log for that exercise.
2. Run bests: a lower duration than a previous run at the same normalized distance (within
   0.5%). Different distances are never compared as a speed record.
3. Meaningful lift progress: estimated 1RM at least 2% above prior training exposure.
4. A neutral “today's work” fallback when the day deserves recognition but does not set a
   record. A first-ever exercise log is celebrated without falsely calling it a PR.

The supporting stats summarize sets, exercises, and the most relevant volume, distance,
reps, or duration. Weight comparisons normalize pounds and kilograms; dumbbell-pair display
semantics remain consistent with the rest of Marble.

## Time and privacy semantics

`DailyHighlightWindow` stores start and final-visible-minute values in `SharedDefaults`.
Occurrences are constructed with the user's autoupdating local `Calendar`, as a half-open
interval, so the default ends exactly at the next local midnight and DST gaps/repeated hours
remain usable. For an overnight custom window, the post-midnight portion belongs to the
previous celebration day.

Only workout facts needed for the recap enter the share image. Notes, body weight,
supplements, locations, and exact timestamps are excluded. The rendered PNG stays in memory
until the user invokes `ShareLink`.

## Engineering map

- `marble/Features/Trends/DailyHighlights.swift` — time-window and ranking engine.
- `marble/Features/Trends/DailyHighlightsView.swift` — in-app card and share action.
- `marble/Features/Trends/DailyHighlightShareCard.swift` — fixed 4:5 export renderer and
  `Transferable` PNG payload.
- `marble/Features/Settings/DailyHighlightsSettingsView.swift` — schedule editor.
- `Tests/Unit/DailyHighlightsTests.swift` — boundaries, DST, record truth, filter
  independence, and exact export size.
- `Tests/Snapshots/TrendsSnapshotTests.swift` — light/dark, phone-size, and Accessibility
  XXXL visual matrix.
- `Tests/UI/TrendsSmokeUITests.swift` — active/inactive window and settings flow.

The implementation follows Apple's documented `Calendar` semantics for local civil time,
`TimelineView` for periodic visibility refreshes, `ImageRenderer` for SwiftUI image output,
`Transferable` plus `ShareLink` for user-initiated sharing, and the Human Interface
Guidelines for accessibility, privacy, and activity views.

Official references:

- [Calendar](https://developer.apple.com/documentation/foundation/calendar)
- [TimelineView](https://developer.apple.com/documentation/swiftui/timelineview)
- [ImageRenderer](https://developer.apple.com/documentation/swiftui/imagerenderer)
- [ShareLink](https://developer.apple.com/documentation/swiftui/sharelink)
- [DataRepresentation](https://developer.apple.com/documentation/coretransferable/datarepresentation)
- [Collaboration and sharing](https://developer.apple.com/design/human-interface-guidelines/collaboration-and-sharing)
- [Activity views](https://developer.apple.com/design/human-interface-guidelines/activity-views)
- [Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility)
- [Privacy](https://developer.apple.com/design/human-interface-guidelines/privacy)
