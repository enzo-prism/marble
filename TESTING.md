# Marble Testing

## Suites
- Unit tests: `MarbleTests` (logic, seed data, date grouping, contrast, workout-import
  mapping, the handwritten-scan parser/importer + a real Vision-OCR integration test, the
  `RenderMemo` cache, Strava credential resolution, and the **personal-records engine**
  `PersonalRecordsTests` — PR-badge trail, unit-normalized weight records, all-time bests,
  usual ranges, the live-PR projection, workout sessions, sprint-prescription target
  boundaries, frozen per-rep goal evaluation/persistence/orphan cleanup, V3-to-V4 migration,
  exercise-editor draft/type/validation/impact rules,
  backup/restore validation, and recovery safety). Runs in CI.
- Snapshot tests: `MarbleSnapshotTests` (SwiftUI rendering with SnapshotTesting).
- UI tests: `MarbleUITests` (end-to-end flows + screenshots).
- Accessibility audits: `MarbleUITests/AccessibilityAuditUITests` (contrast/labels/targets/clipping).

### Daily Highlights coverage

- `DailyHighlightsTests` pins the default 8:00 PM/midnight boundaries, overnight anchoring,
  equal-time validation, DST gaps/repeated hours, empty/future-day hiding, genuine PR rules,
  mixed-unit weights, matched-distance run bests, Trends filter independence, all 45 sourced
  quote records, three-unique-per-day selection, adjacent-day separation, and full-catalog
  schedule coverage.
- `TrendsSnapshotTests.testTrendsDailyHighlights` records the celebration across iPhone SE
  and iPhone 15 Pro, light/dark, and default/Accessibility XXXL text.
- `TrendsSmokeUITests.testDailyHighlightsAppearOnlyInTheCelebrationWindowAndOpenSettings`
  proves evening visibility, manual quote advancement, absence of the removed Share control,
  settings access, and daytime removal.
- The populated Trends accessibility audit runs at 9:00 PM fixture time so the section is
  included, and `DerivationPerformanceTests` guards the builder with a 5,000-entry history.

### Performance regression coverage

- `DerivationPerformanceTests` measures Trends, Daily Highlights, personal-record badges,
  Journal grouping, and the Exercise Picker against histories of 5,000–10,000 entries.
- `ExercisePickerDerivedDataTests` pins recent/favorite/all partitioning after the picker moved
  to one cached derivation pass, and `WorkoutSessionQueryTests` pins the one-active/five-completed
  fetch limits used by the Workout tab.
- `SeedDataTests.testOrphanMaintenanceRunsOncePerVersion` protects the versioned maintenance
  gate that keeps full-store orphan sweeps off routine launches.

## Suite inventory (counted from source, 2026-07-22)
- `Tests/Unit/` — **51 files, 53 classes, 460 test methods**.
- `Tests/UI/` — **17 files, 49 test methods**: **45 flow cases** plus
  `AccessibilityAuditUITests`' 4. `make ui` runs the flows and skips that audit class;
  `make audit` runs the audit cases instead.
- Counts here are derived by counting source, not by hand-editing the previous number
  forward. The long-stale "264" and "254" both came from carrying an old number through a
  docs commit.

## Latest release verification (2026-07-22, 2.2 build 45)
- `MarbleTests`: **460 passed, 0 failed** locally and in GitHub CI run `29974031009`.
  2.2 added ten suites:
  `SharedDefaultsTests`, `WeeklyGoalWidgetStateTests`, `OnboardingGateTests`,
  `PreferredWeightUnitTests`, extended `RestActivityControllerTests`,
  `AppIntentEntityTests`, `LogSetIntentTests`, `BodyMetricEntryTests`,
  `RelativeStrengthTests`, `SchemaV5MigrationTests`.
- `MarbleUITests`: **all 44 flow cases executed — 43 passed, 1 failed** (`make ui`,
  2026-07-21, after the 2.2 defect fixes). The failure is
  `AppStoreScreenshotUITests.test07TrainingCalendar` waiting on `Calendar.MonthTitle`;
  **verified pre-existing, not a 2.2 regression**: the same test fails identically on a
  clean `origin/main` worktree on this host (`UICalendarView` render timing). Re-verify the
  same way before blaming a change — `git worktree add <dir> origin/main` then
  `make only TEST=MarbleUITests/AppStoreScreenshotUITests/test07TrainingCalendar`.
- `AccessibilityAuditUITests` (`make audit`): **passed** against the new Settings, Onboarding
  and bodyweight surfaces on the simulator it was first run on.
- ⚠️ **The contrast audit is simulator-dependent — verify against a baseline before believing
  a failure.** On a freshly created simulator the same suite fails
  `testAccessibilityAudit_DefaultText` with *"Contrast **nearly passed** — Contrast is not high
  enough … unless font size is larger"* on the `ExercisePickerView` section headers ("Recent",
  "All Exercises"). This was proven environmental on 2026-07-21: a clean `origin/main`
  worktree fails **identically, same two labels, same simulator**, while the same commit
  passed on a different simulator minutes earlier. Real contrast is pinned by
  `ThemeContrastTests` in the unit suite, which is the authority. Reproduce a baseline the
  same way before blaming a change:
  ```sh
  git worktree add <dir> origin/main && cd <dir> && MARBLE_SIMULATOR_ID=<udid> make audit
  ```
- **Run UI tests on a dedicated simulator.** This Mac is shared with other agent sessions,
  and a second session's app running on the same simulator makes XCUITest treat it as an
  interrupting element — the symptom is a storm of "Activation point invalid" failures
  across unrelated tests plus `Wait for <other.bundle.id> to idle` in the log. Create one
  and pin it:
  ```sh
  xcrun simctl create "iPhone 17 Pro Marble CI" "iPhone 17 Pro" com.apple.CoreSimulator.SimRuntime.iOS-26-5
  MARBLE_SIMULATOR_ID=<udid> make ui
  ```
  Never `xcrun simctl shutdown all` and never `pkill CoreSimulatorService` — both destroy
  the other session's simulators (the latter wiped the whole device registry once).
- Signed **build 45** Release archive/export: passed for `Prism.marble` and
  `Prism.marble.MarbleWidgets`; App Store Connect processing is `VALID` and
  `IN_BETA_TESTING`.

### Daily Highlights monochrome redesign verification (2026-07-22, 2.2 build 45)

- The eight Daily Highlights baselines were intentionally refreshed and visually inspected:
  iPhone SE and iPhone 15 Pro, light/dark, default/Accessibility XXXL. The focused snapshot
  test passed after recording.
- The focused time-window/settings/quote interaction test passed, including manual quote
  advancement and confirmation that the removed Share surface stays absent.
- Focused Daily Highlights accessibility audits passed in light and dark appearance.
- Full `MarbleTests`: **460 passed, 0 failed**. The broader snapshot target still has the
  unrelated Add Set baseline drift documented in `work/codex-workflow-papercuts.md`.
- Signed app and widget archive/export passed; IPA SHA-256 is
  `1467d8a93e6a9c14e95faf84c5b35c81ea118f6a9cf3b0aa8fc6105959e21207`.
- App Store Connect build `685b7870-70ac-4b5c-b686-e0bd607c9c26` is `VALID` and
  `IN_BETA_TESTING` in internal all-build group `test group A`.
- **Counting caveat (resolved 2026-07-21):** count *unique* case names, not
  `Test Case ... passed/failed` lines. XCTest re-runs a case after a simulator crash, so the
  raw line count both double-counts and under-reports; an earlier run looked like "39 of 44"
  purely from that. To reconcile a run:
  ```sh
  grep -oE "Test Case '-\[MarbleUITests\.[A-Za-z]+ [a-zA-Z0-9_]+\]' (passed|failed)" <log> \
    | sort -u | wc -l    # expect 44
  ```
  Note the two original `AccessibilityAuditUITests` cases share the
  `testAccessibilityAudit_` prefix — a regex that stops at the underscore collapses them
  into one and skews the historical arithmetic.

### Daily Highlights verification (2026-07-22, 2.2 build 43)

- `DailyHighlightsTests`: 12 passed, 0 failed, including schedule/DST boundaries, genuine
  records, run-distance matching, filter independence, all 45 sourced quotes, and the full
  15-day quote cycle.
- `TrendsSmokeUITests.testDailyHighlightsAppearOnlyInTheCelebrationWindowAndOpenSettings`:
  passed; the card appears at 9:00 PM, advances its quote manually, has no Share control,
  disappears at noon, and opens its schedule editor.
- Focused Daily Highlights accessibility audits: light and dark both passed on iOS 26.5.
- `TrendsSnapshotTests.testTrendsDailyHighlights`: passed across iPhone SE and iPhone 15 Pro,
  light/dark, and default/Accessibility XXXL text; all eight baselines are checked in.
- `DerivationPerformanceTests`: the 5,000-entry Daily Highlights benchmark averaged 0.022
  seconds on the local simulator host.
- Full `MarbleTests`: 455 passed, 0 failed. The changed Daily Highlights snapshot matrix is
  green; the broader snapshot target still has unrelated Add Set baseline drift documented
  in `work/codex-workflow-papercuts.md`.
- Signed Release archive and App Store export passed for `Prism.marble` and
  `Prism.marble.MarbleWidgets`; App Store Connect reports build 43
  (`e77804de-5c5b-4e89-b44c-6d5adca1a19f`) `VALID` and `IN_BETA_TESTING` for the internal
  all-build group `test group A`.

## Standing caveats (carried forward)
- `AccessibilityAuditUITests`: the iOS 26.5 runtime skips its unsupported Dynamic Type audit,
  which is covered instead by dedicated XXXL tests for Workout, Trends, Exercise Picker,
  Exercise Library, and New Exercise.
- Previous-release Release migration gate: it asserts the exercise count is unchanged across
  the overlay. Caveat: it asserts only `before == after` and never that the count is non-zero,
  so it passes vacuously if the base app's launch has not finished seeding — see
  `scripts/test_previous_release_migration.sh`.
- One Trends chart-coordinate UI case has historically needed an immediate isolated retry
  after a full-suite run; it has always passed unchanged on retry.
- Feature-verification pass on the Apple Health / Watch / Garmin import path and the AI
  photo-scan pipeline. The real Vision OCR step is proven by
  `WorkoutTextRecognizerIntegrationTests`; the FoundationModels LLM parser is availability-
  gated and falls back to the deterministic parser off-device. Real Watch/Garmin Health data,
  the on-device LLM, and handwriting-OCR accuracy remain **device-only**.
- `make verify-widget-plist` confirms `MarbleWidgets/Info.plist` exists before unit/test runs.

## Continuous integration
- `.github/workflows/ci.yml` runs `make unit` (the `MarbleTests` suite) on every PR and on
  pushes to `main`/`release/**`.
- Snapshot and UI suites are intentionally **not** in CI — snapshot comparisons are
  sub-pixel sensitive to the rendering host, so run `make snapshot` / `make ui` locally.
- The workflow needs a macOS runner with Xcode 26.x + the iOS 26 simulator runtime
  (`runs-on: macos-26`); switch to a self-hosted runner if that image isn't available.

## Run
Preferred Makefile targets:
- `make quick` (unit + quick snapshots)
- `make test` (unit + snapshots)
- `make unit` (unit only)
- `make snapshot` (snapshots only)
- `make snapshot-quick` (quick snapshots only)
- `make snapshot-record` (records baselines; sets `RECORD_SNAPSHOTS=1`)
- `make ui-smoke` (fast navigation smoke)
- `make ui` (UI flow tests; excludes the separate accessibility audit so long-running
  audit sampling cannot degrade later simulator interactions)
- `make audit` (accessibility audits)
- `make only TEST='MarbleUITests/JournalFlowUITests/testAddEditDuplicateDeleteSet'`

## Phone TestFlight pass
- Current phone-test build: **2.2 (45)**, build ID
  `685b7870-70ac-4b5c-b686-e0bd607c9c26`; `VALID` and `IN_BETA_TESTING`, uploaded
  2026-07-22 at 19:21 PDT.
- Internal group `test group A` receives all builds; external beta remains unsubmitted.
- **Most of 2.2 is device-only.** Widgets, Live Activity buttons, Control Center controls,
  Siri, and Spotlight cannot be verified on the simulator — the keychain access group is not
  enforced there, so every snapshot read degrades to "no snapshot". The checklist below is
  the only coverage those surfaces get; do not sign off 2.2 without walking it.

### 2.2 payload (what's new on this build)
- **Daily Highlights** — after logging today, open Trends during the default 8:00 PM–11:59 PM
  window. Confirm the card shows only truthful progress from that day, uses the clean
  monochrome hierarchy, cycles among three quotes, and has no Share button. Confirm Settings →
  Training → Daily Highlights changes the window, then check a custom window that crosses
  midnight.
- **Log Again best cue** — confirm weighted exercises show the heaviest prior weight, runs
  show the fastest time at the same distance, and bodyweight exercises show the most reps.
- **Weekly Goal widget** — add it in all five families: Home Screen small and medium, and
  Lock Screen circular, rectangular, and inline. Check each shows real progress, not the
  neutral "Open Marble" placeholder. **Lock the phone and confirm the Lock Screen families
  still render** — the snapshot is stored `AfterFirstUnlockThisDeviceOnly`, so this is the
  one check that proves the accessibility level is right. Tap through and confirm the
  `marble://trends` deep link lands on Trends.
  - Known gap to expect: logging a set **via Siri** does not refresh the widget (see
    ROADMAP "Known gaps"). Log via Siri, then confirm the widget is stale — that is current
    behaviour, not a new bug.
- **Rest timer Live Activity** — log a set with rest > 0, then use the **`+30s`** and
  **`End`** buttons on both the Lock Screen and the Dynamic Island expanded view. Confirm
  `+30s` actually extends the countdown and `End` dismisses the activity. Then verify the
  single-timer invariant on a physical device:
  1. Let a rest reach `0:00`, then activate Marble; its card must disappear rather than remain
     stacked. iOS does not guarantee app execution at the exact background expiry moment.
  2. Log several sets back to back; only the newest rest may be visible.
  3. Force-quit and relaunch during a rest; at most one timer survives and `+30s` / `End`
     still operate on that exact card.
  4. Background Marble past expiry, reopen it, and confirm no expired cards remain.
- **Control Center** — add the "Log a Set" control in Control Center, and confirm it opens
  Marble to quick log. Also try it from the Lock Screen and the Action button.
- **Onboarding** — install fresh (delete the app first) and walk all three pages: what
  Marble is, weekly goal, default weight unit. Confirm the chosen unit is what Add Set
  defaults to. Then confirm an **upgrading** user never sees onboarding.
- **Settings** — open Workout → Settings and exercise every row: units, weekly goal,
  notifications, Health auto-import and session-export toggles, Data & Backups, privacy
  explainer, version footer. Confirm the Import screen's toggles and the Settings toggles
  stay in sync (same `@AppStorage` keys).
- **Siri & Spotlight** — say "Log a set in Marble", and try the parameterized form with an
  exercise name. Search an exercise name in Spotlight and confirm it appears and opens.
  Try start-workout and finish-workout phrases. Confirm a dumbbell-pair exercise logged via
  intent records the same weight the in-app form would.
- **Bodyweight + DOTS** — enable Health bodyweight import and confirm entries arrive
  deduplicated; add a manual weigh-in; check the Trends bodyweight chart and the DOTS line
  on the e1RM section. Confirm the men/women coefficient picker in the Log Weight sheet
  changes the score.
  - Known gaps to expect: a bodyweight entry **cannot be edited or deleted** once saved, and
    the DOTS coefficient picker exists **only** in the Log Weight sheet — a user whose
    weigh-ins all arrive from Health never sees it.
- **Restore from backup** — restore a JSON backup and confirm the data lands. Known gap:
  the widget does not refresh after a restore.

### Carried-forward regression pass (2.1 payload)
- Start and finish a workout session, log planned and repeated sets, review recent workouts,
  check weekly-goal/priority-lift/monthly-report Trends, and export + restore a JSON backup.
  Confirm the backup disclosure that media is excluded. Note `BodyMetricEntry` is **not yet
  included in backups** — a restore will not carry bodyweight history.
- Sprint pass: create a 150 m sprint exercise with 4 repetitions, test a 19-second target
  and a 19–21-second range, log all four reps with RPE and recovery, confirm goal feedback
  at both range boundaries, and verify the final rep closes the sequence without a fifth
  accidental repetition. Confirm Journal previews show target + check/x-mark + hit/miss text,
  then open Set Details and verify Recorded, Target, the boundary explanation, and saved-goal
  provenance. Reopen the exercise and confirm its prescription persisted; changing it must
  not change the result on an already logged rep.
- Exercise-library pass: verify duplicate-free recent/favorite/all ordering, create from a
  partial search, filter by category, edit appearance through Advanced, confirm dirty-draft
  protection, verify history/planned-workout impact prompts, and confirm used exercises
  cannot be deleted.

Simulator prerequisite:
- The Make targets use `scripts/sim_destination.sh` to find an iPhone simulator.
- If it reports no available iPhone simulator, install the required iOS platform in Xcode
  before debugging test failures. CLI equivalent on Xcode 26:
  `xcodebuild -downloadPlatform iOS`.

Snapshot selection overrides:
- `SNAPSHOT_SUITE=quick|full` (default `full`)
- `SNAPSHOT_GROUPS_OVERRIDE` (comma-separated list of snapshot test identifiers)

## Snapshot baselines
- Stored by SnapshotTesting in `Tests/Snapshots/__Snapshots__`.
- Diff output appears alongside snapshots (e.g. `__diffs__` folders) when failures occur.
- Update intentionally with `make snapshot-record` and commit the new images.
- Snapshot suite runs in small groups to avoid simulator flakiness; results land in `TestResults/MarbleSnapshots_*.xcresult`.
- Snapshot runs log each variant as a separate test activity for faster diagnosis.

## Add a new snapshot state
1. Add a new scenario in a `*SnapshotTests.swift` file under `Tests/Snapshots`.
2. If the scenario needs seeded data, add it in `Tests/Snapshots/SnapshotFixtures.swift`.
3. Use the `assertSnapshot(_:named:)` helper to run across the device/appearance/type matrix.

## Add a new UI test
1. Create a test file under `Tests/UI` and subclass `MarbleUITestCase`.
2. Use `launchApp(...)`, `navigateToTab(...)`, and `takeScreenshot(...)` helpers.
3. Every tappable element must have an accessibility identifier (see `AGENTS.md`).

## Failure artifacts
- UI test failures attach a screenshot and UI hierarchy (`app.debugDescription`).
- Snapshot failures are grouped per device/appearance/type variant in test logs.

## Determinism hooks
UI tests rely on these environment variables:
- `MARBLE_UI_TESTING=1`
- `MARBLE_DISABLE_ANIMATIONS=1`
- `MARBLE_RESET_DB=1`
- `MARBLE_NOW_ISO8601=<fixed date>`
- `MARBLE_FIXTURE_MODE=populated|empty`
- `MARBLE_FORCE_COLOR_SCHEME=light|dark`
- `MARBLE_FORCE_DYNAMIC_TYPE=<UIContentSizeCategory rawValue>`
- `MARBLE_ENABLE_REST_PILL=1` — opt back in to the tab-bar rest pill (hidden by
  default under UI testing so it can't overlay unrelated flows). The pill's
  countdown runs on the wall clock, so pass a *real* `MARBLE_NOW_ISO8601` when
  using it (see `RestTimerPillUITests`).
- `MARBLE_FORCE_ONBOARDING=1` — forces the onboarding flow regardless of the
  `didCompleteOnboarding` gate (`TestHooks.forceOnboarding` → `OnboardingGate`).
  ⚠️ **The hook is implemented in the app but has zero references in `Tests/`** — the
  onboarding UI test the roadmap called for was never written. Onboarding is currently
  covered only by the manual device checklist above.

## Known test gaps
Recorded honestly so nobody assumes coverage that isn't there. Tracked in `ROADMAP.md`
under **Known gaps / next up**:
- No onboarding UI test (`MARBLE_FORCE_ONBOARDING` is unused — see above).
- No Settings smoke test, despite Settings being a new 2.2 surface.
- No widget snapshot suite; `WeeklyGoalWidget`'s five families are unverified by any
  automated test.
- No V4→V5 case in `PersistenceRecoveryTests`, even though V5 is the shipping schema.
