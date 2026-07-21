# MarbleWidgets — widget extension

`MarbleWidgets` is a real WidgetKit app-extension target embedded in the `marble` app. As of
2.2 (build 41) it carries three surfaces: the rest-timer Live Activity, the Weekly Goal
widget, and a Control Center control.

## What's wired

### Rest-timer Live Activity
- `marble/Features/RestTimer/RestTimerAttributes.swift` — the shared `ActivityAttributes`.
- `marble/Features/RestTimer/RestActivityController.swift` — starts/replaces/ends the
  activity. Already called after every **interactive** set log (AddSet, "Log Again",
  duplicate in Journal + Set detail); bulk import deliberately does not trigger it.
- `RestTimerLiveActivity.swift` — Lock Screen / Dynamic Island UI, including the interactive
  **`+30s`** and **`End`** buttons added in 2.2.
- App target build settings include `INFOPLIST_KEY_NSSupportsLiveActivities = YES`.

### Weekly Goal widget
- Families: `.systemSmall`, `.systemMedium`, `.accessoryCircular`, `.accessoryRectangular`,
  `.accessoryInline`; kind `"WeeklyGoalWidget"`; deep links to `marble://trends`.
- The widget **never opens the SwiftData store.** It reads an app-published snapshot, so the
  crash-recovery path is untouched.
- Transport is the **keychain access group `L49MKXGVM4.Prism.marble.shared`** — `SharedKeychain`
  in `marble/Shared/SharedDefaults.swift`, a `kSecClassGenericPassword` item accessible
  `AfterFirstUnlockThisDeviceOnly` so Lock Screen families still render while locked.
  There is **no App Group**; do not add one back (see `AGENTS.md`).
- Shape lives in `marble/Shared/WeeklyGoalWidgetState.swift`, a member of both targets.

### Control Center
- `QuickLogControl` — a `ControlWidget` running the `openAppWhenRun` quick-log intent, so
  "Log a Set" is mappable to Control Center, the Lock Screen, and the Action button.

### Tests
- `Tests/Unit/RestActivityControllerTests.swift` (pure start/timing logic) and
  `Tests/Unit/WeeklyGoalWidgetStateTests.swift` (snapshot mapping).
- ⚠️ **There is no widget snapshot suite.** None of the five families has automated rendering
  coverage — they are verified only by the device checklist in `TESTING.md`.

## Release signing

- `Prism.marble`
- `Prism.marble.MarbleWidgets`

`.asc/ExportOptions.plist` (tracked in git) maps both bundle IDs to the two pinned profiles,
and Release signing is pinned per target in the project. Build **2.2 (41)** is the current
proof of this path — the uploaded IPA includes the signed `MarbleWidgets.appex`, with
entitlements read back off the archive as `marble.app` →
`['L49MKXGVM4.Prism.marble', 'L49MKXGVM4.Prism.marble.shared']` and `MarbleWidgets.appex` →
`['L49MKXGVM4.Prism.marble.shared']`. Keep both profile mappings in place.

## Run
- **Live Activity:** on a device or simulator with Live Activities enabled, log a set whose
  rest is > 0. The countdown appears on the Lock Screen and in the Dynamic Island,
  auto-dismisses when rest ends, and is replaced when logging the next resting set.
- **Weekly Goal widget: device only.** On the simulator, keychain access groups are not
  enforced and `SecItem*` can return `errSecMissingEntitlement`, so every read degrades to
  "no snapshot" and the widget renders its neutral "Open Marble" card. That is expected and
  is why CI and `make unit` stay green — it is not a bug to chase on the simulator.

## Notes
- The Live Activity UI uses monochrome system colors to match the Marble brand. To reuse the
  app's `Theme`/`DesignTokens`, add those files to the extension's membership too (optional).
- `RestActivityController` keeps a single active timer and ends the previous one when a new
  set is logged; `cancelRest()` powers the Live Activity's `End` button.
- **Known gap:** `WeeklyGoalWidgetPublisher.publish` runs only on scene-phase change, so a
  set logged via **Siri** — which has no scene phase — leaves the widget stale. Restoring
  from a backup has the same problem. See "Known gaps / next up" in `ROADMAP.md`.
- Files needing membership in *both* targets need an explicit `PBXFileReference` +
  `PBXBuildFile` + an entry in the widget's Sources phase (the `RestTimerAttributes.swift`
  precedent). They must import Foundation-only frameworks and reference no app type; app-only
  calls go inside `#if !WIDGET_EXTENSION`.
- Verify with `make unit` and `make verify-widget-plist`; see `TESTING.md` for current suite
  counts and the on-device checklist.
