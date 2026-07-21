# Marble Testing

## Suites
- Unit tests: `MarbleTests` (logic, seed data, date grouping, contrast, workout-import
  mapping, the handwritten-scan parser/importer + a real Vision-OCR integration test, the
  `RenderMemo` cache, Strava credential resolution, and the **personal-records engine**
  `PersonalRecordsTests` — PR-badge trail, unit-normalized weight records, all-time bests,
  usual ranges, the live-PR projection, workout sessions, sprint-prescription target
  boundaries, frozen per-rep goal evaluation/persistence/orphan cleanup, V3-to-V4 migration,
  exercise-editor draft/type/validation/impact rules,
  backup/restore validation, and recovery safety).
  Runs in CI. Last verified locally on 2026-07-14 with Xcode 26.5 /
  iOS 26.5 simulator: **264 passed, 0 failed**.
- Snapshot tests: `MarbleSnapshotTests` (SwiftUI rendering with SnapshotTesting).
- UI tests: `MarbleUITests` (end-to-end flows + screenshots).
- Accessibility audits: `MarbleUITests/AccessibilityAuditUITests` (contrast/labels/targets/clipping).

## Latest local verification (2026-07-20, 2.2 build 41)
- `MarbleTests`: **all passed, 0 failed** (`make unit`). 2.2 added ten suites:
  `SharedDefaultsTests`, `WeeklyGoalWidgetStateTests`, `OnboardingGateTests`,
  `PreferredWeightUnitTests`, extended `RestActivityControllerTests`,
  `AppIntentEntityTests`, `LogSetIntentTests`, `BodyMetricEntryTests`,
  `RelativeStrengthTests`, `SchemaV5MigrationTests`.
- `MarbleUITests`: **43 passed, 1 failed** (`make ui`). The failure is
  `AppStoreScreenshotUITests.test07TrainingCalendar` waiting on `Calendar.MonthTitle`;
  **verified pre-existing, not a 2.2 regression**: the same test fails identically on a
  clean `origin/main` worktree on this host (`UICalendarView` render timing). Re-verify the
  same way before blaming a change — `git worktree add <dir> origin/main` then
  `make only TEST=MarbleUITests/AppStoreScreenshotUITests/test07TrainingCalendar`.
- `AccessibilityAuditUITests` (2026-07-20): **passed** against the new Settings, Onboarding,
  and bodyweight surfaces.
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

## Previous verification (2026-07-14)
- `MarbleTests`: **264 passed, 0 failed** (`make unit`), verified 2026-07-14.
  The previously recorded 254 was stale: commit `3e6d4b6` took the suite to 263 and the
  follow-up docs commit carried the old number forward. Counts here are derived from an
  actual run — do not hand-edit them forward.
- `MarbleUITests` (**verified 2026-07-12, not re-run since**): **35 flows passed, 0 failed**
  (`make ui`), including workout start/log/finish, Data management, focused Trends, plan
  logging, exercise creation/management, sprint prescription logging, and XXXL interaction
  coverage. One known Trends chart coordinate case required an immediate isolated retry and
  passed unchanged. Note `make ui` runs **36** of the 38 `Tests/UI` cases — it skips
  `AccessibilityAuditUITests`' 2 cases via `-skip-testing`, which `make audit` runs instead.
- `AccessibilityAuditUITests` (**verified 2026-07-12**): default audit passed; the iOS 26.5
  runtime skips its unsupported Dynamic Type audit, covered by dedicated XXXL tests for
  Workout, Trends, Exercise Picker, Exercise Library, and New Exercise.
- Previous-release Release migration (**verified 2026-07-12**): passed; the gate asserts the
  exercise count is unchanged across the overlay. Caveat: it asserts only `before == after`
  and never that the count is non-zero, so it passes vacuously if the base app's launch has
  not finished seeding — see `scripts/test_previous_release_migration.sh`.
- Signed build 39 Release archive/export: passed for `Prism.marble` and
  `Prism.marble.MarbleWidgets`; App Store Connect processing is `VALID` and internal state
  is `IN_BETA_TESTING`.
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
- Current phone-test build: **2.0 (38)**, build ID
  `d014fc86-cd82-4aef-95f0-53a82418028c`; `VALID` and `IN_BETA_TESTING` internally.
- ASC state checked on 2026-07-12: internal group `test group A` receives all builds;
  external beta remains unsubmitted.
- What to test on device: start and finish a workout session, log planned and repeated
  sets, review recent workouts, check weekly-goal/priority-lift/monthly-report Trends, and
  export + restore a JSON backup. Confirm the backup disclosure that media is excluded.
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
