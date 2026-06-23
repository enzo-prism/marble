# Marble

A local-only workout + supplements journal for iOS, built with SwiftUI and SwiftData — and
a calm UI layer for pulling in workouts from Apple Health, Garmin, and Strava.

## What it is

- **Journal** — fast logging of sets (weight, reps, distance, duration, RPE, rest) with
  per-exercise metric profiles, plus a supplements log. **Personal-best (PR) badges**
  celebrate record sets right in the history, and the logging screen shows your current PR
  (heaviest + most reps) and usual range so you can shoot to beat it — with a live "New PR!"
  cue the moment your entry passes your best.
- **Calendar** — month view with workout-day markers, day detail, and progress photos/videos.
- **Split** — a weekly workout plan whose planned sets log into the journal in one tap.
- **Trends** — Swift Charts for consistency, volume, per-exercise progress, supplements, PRs.
- **Import** — bring workouts in from Apple Health (Apple Watch, Garmin, …) and Strava. See
  [`INTEGRATIONS.md`](INTEGRATIONS.md).
- **Rest Live Activity** — a WidgetKit extension shows between-set rest countdowns on the
  Lock Screen / Dynamic Island after interactive set logging.

Everything is stored on-device. Nothing is tracked or sent to a server (there is no server).

## Current state (2026-06-23)

- Code baseline: `main` is **1.9 (build 29)**, adding a **personal-records (PR)** feature on
  top of build 28: all-time heaviest-weight and most-reps bests per exercise, a celebratory
  trophy badge on every record-setting set in the Journal/quick-log card, and a "Personal
  best" target card + live "New PR!" cue while logging (see `marble/Components/
  PersonalRecords.swift`). `origin/release/1.9` may still point at the older 1.9 build 20
  release baseline unless explicitly updated.
- Latest TestFlight upload: **1.9 (build 29)** ships the PR feature, processed `VALID`
  (build id `e61a527f-4780-4e10-9f95-fdf0914cb0ec`) and available to the internal all-builds
  group for phone testing (build 28 — perf/iOS 26 pass, handwritten scan — remains `VALID`).
- Local verification (2026-06-23): `MarbleTests` passed **164 tests** (incl. the new
  `PersonalRecordsTests`), the `MarbleUITests` flows passed (incl. two new PR flow tests),
  and the accessibility audit passed. A feature-verification pass covered the Apple Health / Watch /
  Garmin import path and the AI photo-scan pipeline (the real Vision OCR step is proven by an
  integration test; the on-device LLM, and real Watch/Garmin/handwriting data, remain
  device-only).
- Builds 27–28 add, on top of build 26: a **performance + iOS 26 pass** (the
  Trends/Calendar/Journal screens memoize their derived data via `RenderMemo` instead of
  re-deriving on every render/scrub; all view models moved to `@Observable`;
  `SupplementEntry.takenAt` is indexed), a **handwritten workout scan** feature under
  `marble/Features/Import/Scan/` (on-device Vision OCR + a deterministic parser, optional
  on-device LLM path, wired into the Import hub), and an iOS 26 polish pass (SF Symbols
  Magic Replace on toggle icons).
- `MarbleWidgets` target is wired into the app build and its `Info.plist` is checked by
  Makefile test targets.
- Live App Store: **1.8 is WAITING_FOR_REVIEW**. There is no 1.9 App Store version record
  yet, so 1.9 is TestFlight-only until a new App Store version is created.
- **[`RELEASE_HANDOFF.md`](RELEASE_HANDOFF.md) is the authoritative, dated source of truth
  for release state** — read it before any release/signing work.

## Run

- Open `marble.xcodeproj` in Xcode (26.x; the target deploys to iOS 26.2).
- Select an iOS Simulator and run the `marble` scheme.

## Architecture

- **SwiftUI + SwiftData, local-only.** Feature folders under `marble/Features/`: `Journal`,
  `Calendar`, `Supplements`, `Trends`, `Split`, `Notifications`, and `Import`.
- **Models** (`marble/Models/`) are SwiftData `@Model` types plus a rich domain core in
  `Enums.swift` (the configurable per-exercise metric profiles).
- **Versioned schema.** `marble/Persistence/MarbleSchema.swift` declares `MarbleSchemaV1` +
  `MarbleMigrationPlan`. The container **self-recovers** from a failed migration (backs the
  old store up to `*.corrupt`, recreates, falls back to in-memory) instead of crash-looping.
  Add a `MarbleSchemaV2` + a `MigrationStage` for any breaking model change.
- **Design system** (`marble/Theme/`, `marble/Components/`) — the monochrome "Marble" brand
  with Liquid Glass confined to navigation surfaces.
- **Import** (`marble/Features/Import/`) — a small `WorkoutImportProvider` abstraction over
  Apple Health, Garmin (via Health), and Strava (official OAuth). Full design + rationale in
  [`INTEGRATIONS.md`](INTEGRATIONS.md).
- **Live Activity** (`marble/Features/RestTimer/` + `MarbleWidgets/`) — the app starts one
  rest-timer activity at a time; the widget extension renders the Lock Screen / Dynamic
  Island UI. Release archive/export signing now covers `Prism.marble.MarbleWidgets`.
- Privacy manifest at `marble/PrivacyInfo.xcprivacy`.

## Documentation map

| File | What it covers |
|---|---|
| [`INTEGRATIONS.md`](INTEGRATIONS.md) | Workout import — how each source works and **why** |
| [`AGENTS.md`](AGENTS.md) | Coding, UI, testing, and release rules for contributors/agents |
| [`RELEASE_HANDOFF.md`](RELEASE_HANDOFF.md) | Dated source of truth for release/version/signing state |
| [`TESTING.md`](TESTING.md) | Test suites, deterministic launch hooks, snapshot rules |
| [`ASC.md`](ASC.md) | App Store Connect (`asc`) command reference for this app |
| [`AdditionalDocumentation/INDEX.md`](AdditionalDocumentation/INDEX.md) | Apple framework docs to consult per UI area |

## Testing

- `make unit` — unit suite (`MarbleTests`); runs in CI.
- `make test` — unit + snapshots. `make ui` — UI flows. `make audit` — accessibility audits.
- See [`TESTING.md`](TESTING.md) for the full matrix and determinism hooks.

## CI

`.github/workflows/ci.yml` runs `make unit` on PRs and pushes to `main`/`release/**`. It
needs a runner with Xcode 26.x + the iOS 26 simulator runtime. Snapshot/UI suites are
intentionally local-only (sub-pixel sensitive to the rendering host).
