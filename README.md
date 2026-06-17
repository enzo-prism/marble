# Marble

Local-only workout + supplements journal built with SwiftUI and SwiftData.

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
- Feature folders for Journal, Calendar, Supplements, Trends.
- Shared UI components in `marble/Components`.

## Theme + Seed Data
- Theme helpers live in `marble/Theme/Theme.swift`.
- Seed data (exercises + supplements) lives in `marble/Persistence/SeedData.swift`.
