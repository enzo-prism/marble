# Marble

Local-only workout + supplements journal built with SwiftUI and SwiftData.

## Current state (2026-06-18)

- Code baseline: `main` == `release/1.9` == **1.9 (build 20)**, pushed to `origin`.
- Live App Store: **1.8 is in review**; **no 1.9 build is on TestFlight/App Store yet**
  (1.9 upload is blocked on a pending Apple agreement + HealthKit signing).
- **`RELEASE_HANDOFF.md` is the authoritative, dated source of truth for release state** —
  read it before any release/signing work.

## Run
- Open `marble.xcodeproj` in Xcode.
- Select an iOS Simulator and run the `marble` scheme.

## Agent Entry Points
- `AGENTS.md` - coding, UI, testing, and release rules for agents.
- `RELEASE_HANDOFF.md` - current branch cleanup and App Store release handoff.
- `TESTING.md` - test suites, deterministic launch hooks, and snapshot rules.
- `ASC.md` - App Store Connect command reference for this app.

## Architecture
- SwiftUI + SwiftData, local-only storage.
- Feature folders: Journal, Calendar, Supplements, Trends, Split, Notifications, and
  Import (HealthKit + Garmin Connect) under `marble/Features/`.
- Shared UI components in `marble/Components`.
- SwiftData schema is versioned via `marble/Persistence/MarbleSchema.swift`
  (`MarbleSchemaV1` + `MarbleMigrationPlan`); the container self-recovers from a failed
  migration rather than crashing. Add a `MarbleSchemaV2` + `MigrationStage` for breaking
  model changes.
- Privacy manifest at `marble/PrivacyInfo.xcprivacy`.

## Theme + Seed Data
- Theme helpers live in `marble/Theme/Theme.swift`.
- Seed data (exercises + supplements) lives in `marble/Persistence/SeedData.swift`.

## CI
- `.github/workflows/ci.yml` runs the unit suite (`make unit`) on PRs and pushes to
  `main`/`release/**`. It needs a runner with Xcode 26.x + the iOS 26 simulator runtime.
