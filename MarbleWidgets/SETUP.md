# MarbleWidgets — widget extension

`MarbleWidgets` is a real WidgetKit app-extension target embedded in the `marble` app. As of
2.2 (build 41) it carries three surfaces: the rest-timer Live Activity, the Weekly Goal
widget, and a Control Center control.

## What's wired

### Rest-timer Live Activity
- `marble/Features/RestTimer/RestTimerAttributes.swift` — the shared `ActivityAttributes`.
- `marble/Features/RestTimer/RestActivityController.swift` — starts/replaces/ends the
  activity. Already called after every **interactive** set log (AddSet, "Log Again",
  duplicate in Journal + Set detail); bulk import deliberately does not trigger it. Also
  schedules the single pending **"rest complete" local notification** that alerts a
  backgrounded/locked user when the countdown hits zero — it rides on whatever notification
  authorization already exists and never prompts.
- `RestTimerLiveActivity.swift` — Lock Screen / Dynamic Island UI, including the interactive
  **`+30s`** and **`End`** buttons added in 2.2.
- App target build settings include `INFOPLIST_KEY_NSSupportsLiveActivities = YES`.

### Weekly Goal widget
- Families: `.systemSmall`, `.systemMedium`, `.accessoryCircular`, `.accessoryRectangular`,
  `.accessoryInline`; kind `"WeeklyGoalWidget"`.
- Deep links: the card opens `marble://trends`; `systemMedium` additionally carries a
  quick-log `Link` to `marble://quicklog`, which `ContentView` routes into the same
  `QuickLogCoordinator` sheet the Control Center intent reaches by notification. A `Link`
  rather than an intent `Button` on purpose — the extension never opens the store, so the
  only honest action is opening the app, and Apple asks that widget buttons do more than
  that. `systemSmall` supports exactly one tap target (`widgetURL`), so it stays
  whole-card; accessory families stay link-only.
- Smart Stack: every timeline entry carries a `TimelineEntryRelevance`, scored at the
  entry's own date by the pure `WeeklyGoalWidgetState.relevanceScore` — peaks with one
  session remaining inside a typical training window, moderate mid-week, low once the week
  is banked, zero for a stale/absent snapshot. Pure and Foundation-only so
  `WeeklyGoalWidgetStateTests` (app target) pins it; the personalised timing signal comes
  from `LogSetIntent`'s `PredictableIntent` donations instead.
- Accented rendering (tinted/clear Home Screens): the ring's progress arc and the
  quick-log capsule form the `widgetAccentable()` group; the ring track and all copy stay
  in the primary group. No images, so `widgetAccentedRenderingMode` does not apply.
  Full-colour rendering is pixel-identical.
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
  `Tests/Unit/WeeklyGoalWidgetStateTests.swift` (snapshot mapping + the Smart Stack
  relevance scoring).
- ⚠️ **There is no widget snapshot suite.** None of the five families has automated rendering
  coverage — they are verified only by the device checklist in `TESTING.md`.

## Release signing

- `Prism.marble`
- `Prism.marble.MarbleWidgets`

`.asc/ExportOptions.plist` (tracked in git) maps both bundle IDs to the two pinned profiles,
and Release signing is pinned per target in the project. Build **2.2 (47)** is the current
proof of this path (verified end to end 2026-07-23, see `RELEASE_HANDOFF.md`) — the
uploaded IPA includes the signed `MarbleWidgets.appex`, with
entitlements read back off the archive as `marble.app` →
`['L49MKXGVM4.Prism.marble', 'L49MKXGVM4.Prism.marble.shared']` and `MarbleWidgets.appex` →
`['L49MKXGVM4.Prism.marble.shared']`. Keep both profile mappings in place.

## Run
- **Live Activity:** on a device or simulator with Live Activities enabled, log a set whose
  rest is > 0. The countdown appears on the Lock Screen and in the Dynamic Island,
  dismisses as soon as Marble next executes after the rest ends, and is replaced when logging
  the next resting set. (iOS may suspend the app at expiry; `staleDate` alone does not dismiss.)
  ActivityKit's system inventory is the source of truth, so force-quitting/relaunching Marble
  must still leave at most one rest activity.
- **Weekly Goal widget: device only.** On the simulator, keychain access groups are not
  enforced and `SecItem*` can return `errSecMissingEntitlement`, so every read degrades to
  "no snapshot" and the widget renders its neutral "Open Marble" card. That is expected and
  is why CI and `make unit` stay green — it is not a bug to chase on the simulator.

## Notes
- `MarbleWidgets/PrivacyInfo.xcprivacy` — the appex needs its **own privacy manifest**
  (Apple scans each executable bundle separately; it cannot rely on
  `marble/PrivacyInfo.xcprivacy`). Declares no tracking, no collected data, and the
  UserDefaults required-reason API (`CA92.1`) that `SharedDefaults.swift` brings into the
  target.
- The Live Activity UI uses monochrome system colors to match the Marble brand. To reuse the
  app's `Theme`/`DesignTokens`, add those files to the extension's membership too (optional).
- `RestActivityController` reconciles `Activity<RestTimerAttributes>.activities` on launch and
  foreground, ends every prior timer before requesting a replacement, and immediately removes
  expired cards when Marble next runs. The `+30s` / `End` intents carry the rendering activity's ID so an obsolete
  card can never mutate a newer timer.
- `WeeklyGoalWidgetPublisher.publish` runs on scene-phase change, after every intent save
  (`AppIntentsSupport.refreshSystemSurfaces`), and after a backup restore
  (`DataManagementView`), so neither a Siri-logged set nor a restore leaves the widget
  stale any more.
- Files needing membership in *both* targets need an explicit `PBXFileReference` +
  `PBXBuildFile` + an entry in the widget's Sources phase (the `RestTimerAttributes.swift`
  precedent). They must import Foundation-only frameworks and reference no app type; app-only
  calls go inside `#if !WIDGET_EXTENSION`.
- Verify with `make unit` and `make verify-widget-plist`; see `TESTING.md` for current suite
  counts and the on-device checklist.
