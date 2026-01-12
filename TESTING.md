# Marble Testing

## Suites
- Unit tests: `MarbleTests` (logic, seed data, date grouping, contrast).
- Snapshot tests: `MarbleSnapshotTests` (SwiftUI rendering with SnapshotTesting).
- UI tests: `MarbleUITests` (end-to-end flows + screenshots).
- Accessibility audits: `MarbleUITests/AccessibilityAuditUITests` (contrast/labels/targets/clipping).

## Run
Preferred Makefile targets:
- `make test` (unit + snapshots)
- `make snapshot` (snapshots only)
- `make snapshot-record` (records baselines; sets `RECORD_SNAPSHOTS=1`)
- `make ui` (UI flow tests)
- `make audit` (accessibility audits)
- `make only TEST='MarbleUITests/JournalFlowUITests/testAddEditDuplicateDeleteSet'`

## Snapshot baselines
- Stored by SnapshotTesting in `Tests/Snapshots/__Snapshots__`.
- Diff output appears alongside snapshots (e.g. `__diffs__` folders) when failures occur.
- Update intentionally with `make snapshot-record` and commit the new images.

## Add a new snapshot state
1. Add a new scenario in a `*SnapshotTests.swift` file under `Tests/Snapshots`.
2. If the scenario needs seeded data, add it in `Tests/Snapshots/SnapshotFixtures.swift`.
3. Use the `assertSnapshot(_:named:)` helper to run across the device/appearance/type matrix.

## Add a new UI test
1. Create a test file under `Tests/UI` and subclass `MarbleUITestCase`.
2. Use `launchApp(...)`, `navigateToTab(...)`, and `takeScreenshot(...)` helpers.
3. Every tappable element must have an accessibility identifier (see `AGENTS.md`).

## Determinism hooks
UI tests rely on these environment variables:
- `MARBLE_UI_TESTING=1`
- `MARBLE_DISABLE_ANIMATIONS=1`
- `MARBLE_RESET_DB=1`
- `MARBLE_NOW_ISO8601=<fixed date>`
- `MARBLE_FIXTURE_MODE=populated|empty`
- `MARBLE_FORCE_COLOR_SCHEME=light|dark`
- `MARBLE_FORCE_DYNAMIC_TYPE=<UIContentSizeCategory rawValue>`
