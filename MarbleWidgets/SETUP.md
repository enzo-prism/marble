# MarbleWidgets — rest-timer Live Activity

The rest-timer Live Activity is now wired as a real WidgetKit app-extension target.

## What's wired
- `marble/Features/RestTimer/RestTimerAttributes.swift` — the shared `ActivityAttributes`.
- `marble/Features/RestTimer/RestActivityController.swift` — starts/replaces/ends the
  activity. Already called after every **interactive** set log (AddSet, "Log Again",
  duplicate in Journal + Set detail); bulk import deliberately does not trigger it.
- `MarbleWidgets` target — embeds `MarbleWidgets.appex` in the `marble` app.
- `RestTimerLiveActivity.swift` + `MarbleWidgetsBundle.swift` — render the Lock Screen /
  Dynamic Island UI.
- App target build settings include `INFOPLIST_KEY_NSSupportsLiveActivities = YES`.
- Unit tests: `Tests/Unit/RestActivityControllerTests.swift` (pure start/timing logic).

## Release signing

- `Prism.marble`
- `Prism.marble.MarbleWidgets`

Build `1.9 (24)` proved the current release path: App Store export options map both bundle
IDs, Release signing is pinned per target, and the uploaded IPA includes the signed
`MarbleWidgets.appex`. Keep both profile mappings in place for future TestFlight/App Store
builds.

## Run
On a device or simulator with Live Activities enabled, log a set whose rest is > 0. The
countdown appears on the Lock Screen and in the Dynamic Island, auto-dismisses when rest ends,
and is replaced when logging the next resting set.

## Notes
- The Live Activity UI uses monochrome system colors to match the Marble brand. To reuse the
  app's `Theme`/`DesignTokens`, add those files to the extension's membership too (optional).
- `RestActivityController` keeps a single active timer and ends the previous one when a new
  set is logged; `cancelRest()` is available if you later want a "skip rest" affordance.
- Verify: `xcodebuild ... -scheme marble build` compiles both targets; `MarbleTests` last
  passed locally on 2026-06-22 with 109 tests.
