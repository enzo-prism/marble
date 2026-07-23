# Daily Highlights

Daily Highlights is Marble's end-of-day celebration in Trends. It turns the work already
stored on the device into a clean, screenshots-ready recap without adding an account,
server, background process, or sharing integration.

## User experience

- The section is enabled by default from **8:00 PM through 11:59 PM local time**.
- It appears only when that celebration day contains at least one valid training log. It is
  absent outside the active window and on empty days.
- The clock action on the card, and **Settings → Training → Daily Highlights**, open the same
  editor. Users can disable the feature or choose a custom start and end time. An end time
  earlier than the start is intentionally treated as an overnight window; equal times are
  rejected rather than interpreted as “always on.”
- The celebration card follows Marble's monochrome system: a solid surface, restrained gray
  border and dividers, compact date, grayscale icon treatment, and clear type hierarchy. A
  trailing result keeps the achievement immediately scannable without using gold or another
  achievement-specific accent.
- The previous export and Share button were deliberately removed. The achievement, stats,
  and motivation now own the card's visual hierarchy; users can still capture the whole
  in-app composition with the system screenshot gesture.

## Daily motivation

The app bundles **45 short public-domain quotations** with attribution, source title, and a
primary-source URL. The catalog is arranged into 15 balanced three-quote cohorts. A fixed,
versioned local-day schedule means:

- exactly three unique quotes are selected for each celebration day;
- the same local day always receives the same trio across relaunches;
- adjacent days never share a quote;
- every quote appears once before the 15-day schedule repeats; and
- an overnight window continues using the prior celebration day's trio after midnight.

The visible quote advances every 12 seconds with a short crossfade. Tapping it advances
manually and holds the chosen quote for at least one full interval, after which automatic
rotation resumes on the shared schedule. VoiceOver and Reduce Motion stop automatic
rotation, and a manual pick is then permanent; the quote remains a single adjustable
accessibility element with
its author and “quote N of 3” position. Dynamic Type wraps naturally without line limits or
text scaling. Visually, motivation is deliberately a quiet footer: secondary italic text
with a compact author and position line. It has no heading, quote icon, or pagination
ornament, keeping the day's achievements and results at the top of the hierarchy.

Every catalog entry is auditable in `DailyHighlightQuotes.swift`. Primary archives include
[Project Gutenberg](https://www.gutenberg.org/), the
[Library of Congress Frederick Douglass papers](https://www.loc.gov/resource/mss11879.21039/?sp=45),
the [Founders Online Franklin papers](https://founders.archives.gov/documents/Franklin/01-02-02-0028),
and the [Papers of Abraham Lincoln](https://papersofabrahamlincoln.org/documents/D200867).

## What is celebrated

`DailyHighlightsBuilder` derives the recap from a scoped `SetEntry` fetch — the celebration
day's entries plus the complete prior history of just that day's exercises — independent of
the Trends range and exercise filter. Record baselines stay unbounded going back in time,
so an all-time best from years ago still vetoes a false "new best" today. It ranks at most three deterministic highlights and
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

The card is derived on-device from workout facts already stored by Marble. Quotes are
bundled static content. There is no networking, analytics, persistence schema, notification,
background task, image renderer, or share payload in this feature.

## Engineering map

- `marble/Features/Trends/DailyHighlights.swift` — time-window and ranking engine.
- `marble/Features/Trends/DailyHighlightQuotes.swift` — sourced catalog and deterministic
  three-per-day schedule.
- `marble/Features/Trends/DailyHighlightQuoteRotation.swift` — pure timing rules for the
  quote rotator's hold-then-resume behavior after a manual pick.
- `marble/Features/Trends/DailyHighlightsView.swift` — monochrome celebration card and isolated
  quote rotator.
- `marble/Persistence/Queries/DailyHighlightQueries.swift` — scoped history fetch: the day's
  entries plus the prior history of only that day's exercises.
- `marble/Features/Settings/DailyHighlightsSettingsView.swift` — schedule editor.
- `Tests/Unit/DailyHighlightsTests.swift` — boundaries, DST, record truth, filter
  independence, catalog integrity, quote schedule guarantees, and rotation resume rules.
- `Tests/Unit/DailyHighlightQueriesTests.swift` — scoped fetch equivalence with the
  full-table history.
- `Tests/Snapshots/TrendsSnapshotTests.swift` — light/dark, phone-size, and Accessibility
  XXXL visual matrix.
- `Tests/UI/TrendsSmokeUITests.swift` — active/inactive window, quote interaction, removed
  sharing surface, and settings flow.

The implementation follows Apple's documented `Calendar` semantics for local civil time,
`TimelineView` for lifecycle-managed periodic updates, and the Human Interface Guidelines
for purposeful motion, color, and accessibility. Auto-advancing content stops under Reduce
Motion or VoiceOver, and important text retains black/white contrast in both appearances.

Official references:

- [Calendar](https://developer.apple.com/documentation/foundation/calendar)
- [TimelineView](https://developer.apple.com/documentation/swiftui/timelineview)
- [Color](https://developer.apple.com/design/human-interface-guidelines/color)
- [Motion](https://developer.apple.com/design/human-interface-guidelines/motion)
- [Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility)
- [Reduced Motion evaluation criteria](https://developer.apple.com/help/app-store-connect/manage-app-accessibility/reduced-motion-evaluation-criteria)
