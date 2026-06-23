# Marble Testing

## Suites
- Unit tests: `MarbleTests` (logic, seed data, date grouping, contrast, workout-import
  mapping + Strava credential resolution). Runs in CI. Last verified locally on
  2026-06-22 with XcodeBuildMCP / iOS 26.5 simulator: **109 passed, 0 failed**.
- Snapshot tests: `MarbleSnapshotTests` (SwiftUI rendering with SnapshotTesting).
- UI tests: `MarbleUITests` (end-to-end flows + screenshots).
- Accessibility audits: `MarbleUITests/AccessibilityAuditUITests` (contrast/labels/targets/clipping).

## Latest local verification (2026-06-22)
- `MarbleTests`: 109 passed, 0 failed.
- `MarbleUITests`: 27 executed, 1 expected accessibility-text skip, 0 failed.
- Snapshot subset refreshed and passed for `JournalSnapshotTests/testJournalEmpty` and
  `CalendarSnapshotTests/testCalendarMonthWithMarkers`.
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
- `make ui` (UI flow tests)
- `make audit` (accessibility audits)
- `make only TEST='MarbleUITests/JournalFlowUITests/testAddEditDuplicateDeleteSet'`

## Phone TestFlight pass
- Current phone-test build: **1.9 (25)**, build ID
  `95f6d6b1-8678-4c86-9933-96a57135ca86`.
- ASC state checked on 2026-06-22: build processing is `VALID`,
  `internalBuildState = IN_BETA_TESTING`, and internal group `test group A` has access to
  all builds.
- Tester state checked on 2026-06-22: the internal Enzo tester record is `INSTALLED` and is
  in `test group A`, so the build should appear in the TestFlight app on the signed-in phone.
- What to test on device: install/launch stability, the rest timer Live Activity/widget,
  Apple Health workout import, Garmin-via-Health labeling, journal/split logging, and the
  Strava-hidden-unless-configured posture.

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
