# Marble

A local-only workout + supplements journal for iOS, built with SwiftUI and SwiftData — and
a calm UI layer for pulling in workouts from Apple Health, Garmin, and Strava.

## What it is

- **Journal** — fast logging of sets (weight, reps, distance, duration, RPE, rest) with
  per-exercise metric profiles, plus a supplements log. **Personal-best (PR) badges**
  celebrate record sets right in the history, and the logging screen shows your current PR
  (heaviest + most reps) and usual range so you can shoot to beat it — with a live "New PR!"
  cue the moment your entry passes your best.
- **Exercise library** — a searchable, category-filterable home for creating, favoriting,
  and safely editing reusable exercises. Explicit tracking types keep standard setup short,
  while Custom exposes every metric requirement. See
  [`EXERCISE_LIBRARY.md`](EXERCISE_LIBRARY.md).
- **Calendar** — month view with workout-day markers, day detail, and progress photos/videos.
- **Workout** — start and finish timed workout sessions, log planned sets in one tap, and
  review recent sessions; the weekly split remains the editable plan behind the tab.
- **Sprint workouts** — create reusable distance prescriptions with a repetition count,
  exact or ranged target time, and recovery; log every sprint with actual time, RPE, rest,
  rep progress, and immediate goal feedback. Journal previews show an accessible green hit,
  red miss, or neutral unscored state; details explain the saved target and exact result.
  See [`SPRINT_WORKOUTS.md`](SPRINT_WORKOUTS.md).
- **Trends** — a focused weekly goal, priority lift, and monthly report first; detailed
  consistency, volume, per-exercise, supplement, and PR charts remain one tap away. From
  8:00 PM through 11:59 PM by default, **Daily Highlights** celebrates that day's genuine
  PRs and progress in a clean monochrome card with three rotating daily quotes;
  the window is customizable and the feature remains entirely on-device.
  See [`DAILY_HIGHLIGHTS.md`](DAILY_HIGHLIGHTS.md).
- **Data safety** — export and restore exercises, sets, supplements, sessions, and plans as
  JSON. Progress photos and videos remain on-device and are intentionally excluded.
- **Import** — bring workouts in from Apple Health (Apple Watch, Garmin, …) and Strava. See
  [`INTEGRATIONS.md`](INTEGRATIONS.md).
- **Rest timer** — after interactive set logging, a tab-bar pill counts the rest down inside
  the app (iOS 26 bottom accessory, with an End button), while a WidgetKit Live Activity
  mirrors it on the Lock Screen / Dynamic Island.

Everything is stored on-device. Nothing is tracked or sent to a server (there is no server).

## Current state (2026-07-22)

- **Live on the App Store: 2.1 (build 40)**, released 2026-07-21 (`READY_FOR_SALE` in the
  App Store Connect API).
  It carries builds 35–39 — workout sessions, sprint prescriptions, the Exercise Library
  redesign, and JSON backups. No phased release was configured, so it went to 100% at once.
- **On TestFlight: 2.2 (build 44)** — `VALID` and `IN_BETA_TESTING`, uploaded 2026-07-22
  (build id `9874c20b-d418-469b-9539-2bbe5c41118d`) to the all-build internal group
  `test group A`. **Not yet submitted to App Review.** Build 44 keeps the build-43 Daily
  Highlights design, single-Live-Activity timer invariant, and Log Again personal-best
  context while reducing repeated Trends derivation, Exercise Picker work, launch maintenance,
  workout-session fetches, and whole-screen timer invalidation. 2.2 is the "ambient" release,
  which closes the gap between how much Marble knows
  and how little of it is reachable from outside the app:
  - **Weekly Goal widget** — Home Screen (small/medium) and Lock Screen (circular/rectangular/
    inline), fed by a snapshot the app publishes into a shared keychain access group
    (`SharedKeychain`). The widget never opens the SwiftData store, so the crash-recovery
    path is untouched.
  - **Interactive rest timer** — `+30s` / `End` buttons on the Lock Screen and Dynamic Island,
    plus a **Control Center** "Log a Set" control.
  - **Onboarding** (what Marble is, weekly goal, default weight unit) and a real **Settings**
    screen; Data & Backups now lives one level in, under Settings.
  - **Siri & Spotlight** — `ExerciseEntity` (`AppEntity` + `IndexedEntity`), a parameterized
    `LogSetIntent`, and start/finish workout intents.
  - **Bodyweight** — `BodyMetricEntry` (schema **V5**, additive), Apple Health bodyweight
    import, a bodyweight trend, and DOTS relative strength.
- **✅ The App Group archiving blocker is resolved (2026-07-21)** — see
  [`RELEASE_HANDOFF.md`](RELEASE_HANDOFF.md). The widget snapshot moved to a keychain access
  group (`L49MKXGVM4.Prism.marble.shared`) that the existing App Store profiles already grant,
  so **no portal capability and no profile regeneration are needed**.
- **Known gaps:** several 2.2 surfaces are defined but not fully wired (TipKit tips never
  present, Siri-logged sets don't refresh the widget, bodyweight entries can't be edited or
  deleted). See **Known gaps / next up** in [`ROADMAP.md`](ROADMAP.md) before promising any
  of them works.
- **[`RELEASE_HANDOFF.md`](RELEASE_HANDOFF.md) is the authoritative, dated source of truth
  for release state** — read it before any release/signing work.

### Release history

- **2.1 (build 39)** surfaced sprint goals in the Journal: every rep shows its saved exact or
  ranged target with accessible green-hit / red-miss / neutral-unscored feedback, and Set
  Details compares the recorded result against the frozen per-rep goal and explains the
  outcome. Additive `MarbleSchemaV4` plus legacy-backfill provenance, backup/restore
  validation, and duplicate/undo/intent support preserve history when an exercise goal
  changes.
- **2.1 (build 38)** redesigned exercise creation and management end to end: a searchable,
  category-filterable Exercise Library; explicit tracking types; contextual fields; safe
  draft editing; duplicate-name validation; unsaved-change protection; history/planned-plan
  impact warnings; and guarded deletion. Sprint setup became a direct type with distance,
  repeats, exact/ranged target time, and one recovery control.
- **2.1 (build 37)** added reusable sprint prescriptions: fixed distance and
  repeats, exact or ranged whole-second target times, prescribed recovery, per-rep RPE/rest
  logging, goal feedback, plan/picker summaries, JSON backup/restore, and additive V3
  persistence.
- **2.1 (build 36)** fixed the build-35 launch crash for existing users by removing a
  redundant SwiftData stage and letting the additive `WorkoutSession` schema migrate
  automatically. **Adding a `MigrationStage` for an additive change is what caused that
  crash** — see `AGENTS.md`. It retains first-class session history, the session-led Workout
  tab, focused Trends, JSON backup/restore, safer recovery, and visible save failures.
- **1.9 (build 33)** added **lifter-focused analytics** to Trends: an estimated-1RM
  progression chart per exercise (Epley, sets ≤12 reps, unit-normalized — with the
  all-time best marked), sets per muscle group with weekly averages (RP volume-landmark
  style), rep-range distribution (1–5 / 6–12 / 13+), and an Effort chart (average RPE per
  day/week — the fatigue/adaptation cue). Pure engine in
  `marble/Features/Trends/LifterAnalytics.swift`; also fixes lift-bests comparing weights
  across units without normalizing. Unit suite is **193 tests**.
- **1.9 (build 32)** is a **performance pass for all supported iPhones** (A13 floor): the
  Trends queries are finally range-scoped (`TrendsView` shell + `TrendsContentView`
  rebuilding `@Query` predicates per range — the documented dynamic-query pattern); the
  calendar day-sheet's media query is day-scoped at init; Journal/Trends/Calendar/
  Supplements memo signatures use one-row `updatedAt` probes (`LatestUpdateQueries`,
  new indexes on `SetEntry`/`SupplementEntry`/`ProgressMediaAttachment`) instead of
  walking every row per frame; Supplements grouping is memoized like Journal. Proven
  behavior-preserving by an equivalence test; three `measure()` benchmarks guard the
  hot derivations at 5k-row scale. Unit suite is **182 tests**.
- **1.9 (build 31)** overhauls the **workout import** feature end-to-end: structured
  workout detail (kind, origin, source app, device, distance, duration, calories, avg/max
  heart rate, elevation, indoor/outdoor) captured on the `ImportedWorkout` ledger with
  every journal entry linked back (`SetEntry.importedWorkout`); a read-only workout detail
  sheet with a live heart-rate sparkline (Swift Charts + `HKStatisticsCollectionQuery`);
  optional **auto-import** of new Apple Health workouts on every app-open (incremental
  `HKAnchoredObjectQuery` with a persisted anchor, `HealthAutoImportService`); honest
  read-authorization UX (`getRequestStatusForAuthorization` — the old build misread the
  write-side sharing status); an expanded activity-type mapping (rowing/HIIT/elliptical/
  sports/multisport); Garmin bridge status + step-by-step setup + `gcm-ciq://` deep link;
  an import history section; and provenance badges on imported sets in the journal. See
  [`INTEGRATIONS.md`](INTEGRATIONS.md).
- **1.9 (build 30)** was an iOS 26 design/UX polish pass: an in-app **rest-timer pill**
  (tab-bar bottom accessory with live countdown + End button — the rest timer finally has an
  in-app surface; the Lock Screen Live Activity mirrors it), an Import-sheet zoom morph from
  its toolbar button, `ToolbarSpacer` grouping so the primary "+" gets its own glass capsule,
  an explicit Cancel button on Log Set, and a selection-haptics pass (preset chips, trend
  range, calendar days, Supplements quick-add/delete with explicit save-or-rollback). Unit
  suite is **168 tests**; a new `RestTimerPillUITests` covers the pill end-to-end.
- Previous baseline: **1.9 (build 29)** added a **personal-records (PR)** feature on
  top of build 28: all-time heaviest-weight and most-reps bests per exercise, a celebratory
  trophy badge on every record-setting set in the Journal/quick-log card, and a "Personal
  best" target card + live "New PR!" cue while logging (see `marble/Components/
  PersonalRecords.swift`). `origin/release/1.9` may still point at the older 1.9 build 20
  release baseline unless explicitly updated.
- Builds 27–28 added, on top of build 26: a **performance + iOS 26 pass** (the
  Trends/Calendar/Journal screens memoize their derived data via `RenderMemo` instead of
  re-deriving on every render/scrub; all view models moved to `@Observable`;
  `SupplementEntry.takenAt` is indexed), a **handwritten workout scan** feature under
  `marble/Features/Import/Scan/` (on-device Vision OCR + a deterministic parser, optional
  on-device LLM path, wired into the Import hub), and an iOS 26 polish pass (SF Symbols
  Magic Replace on toggle icons).
- **2.0 (build 34)** shipped the Trends coaching layer; it is the version App Store 2.0
  released under.
- `MarbleWidgets` target is wired into the app build and its `Info.plist` is checked by
  Makefile test targets.

## Run

- Open `marble.xcodeproj` in Xcode (26.x; the target deploys to iOS 26.2).
- Select an iOS Simulator and run the `marble` scheme.

## Architecture

- **SwiftUI + SwiftData, local-only.** Feature folders under `marble/Features/`: `Body`,
  `Calendar`, `Import`, `Journal`, `Notifications`, `Onboarding`, `RestTimer`, `Settings`,
  `Split`, `Supplements`, `Trends`, and `Workout`. Code shared with the widget extension
  lives in `marble/Shared/`; App Intents live in `marble/Intents/`.
- **Models** (`marble/Models/`) are SwiftData `@Model` types plus a rich domain core in
  `Enums.swift` (the configurable per-exercise metric profiles).
- **Versioned schema — currently V5.** `marble/Persistence/MarbleSchema.swift` declares V1,
  additive V2 workout-session storage, additive V3 sprint prescriptions, additive V4 per-rep
  sprint goal snapshots, additive V5 `BodyMetricEntry`, and `MarbleMigrationPlan`. Every
  change so far has been additive, so `MarbleMigrationPlan.stages` is `[]` and must stay that
  way — an explicit stage for an additive change is what crashed build 35 on launch.
  The container **self-recovers** from a failed migration without overwriting older recovery
  copies.
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
| [`SPRINT_WORKOUTS.md`](SPRINT_WORKOUTS.md) | Sprint prescription attributes, logging flow, and persistence |
| [`EXERCISE_LIBRARY.md`](EXERCISE_LIBRARY.md) | Exercise creation, attributes, discovery, editing, and deletion safety |
| [`DAILY_HIGHLIGHTS.md`](DAILY_HIGHLIGHTS.md) | End-of-day celebration rules, time-window semantics, privacy, sharing, and tests |
| [`ROADMAP.md`](ROADMAP.md) | H2 2026 plan: what shipped in 2.2, **known gaps / next up**, and why the Watch app was deferred |
| [`AGENTS.md`](AGENTS.md) | Coding, UI, testing, and release rules for contributors/agents |
| [`RELEASE_HANDOFF.md`](RELEASE_HANDOFF.md) | Dated source of truth for release/version/signing state |
| [`TESTING.md`](TESTING.md) | Test suites, deterministic launch hooks, snapshot rules, on-device checklist |
| [`ASC.md`](ASC.md) | App Store Connect (`asc`) command reference for this app |
| [`MarbleWidgets/SETUP.md`](MarbleWidgets/SETUP.md) | Widget extension target: what's wired, release signing, how to exercise it |
| [`WORKFLOW_PAPERCUTS.md`](WORKFLOW_PAPERCUTS.md) | Running log of tooling friction hit during agent sessions |
| [`AdditionalDocumentation/INDEX.md`](AdditionalDocumentation/INDEX.md) | Apple framework docs to consult per UI area |

## Testing

- `make unit` — unit suite (`MarbleTests`); runs in CI.
- `make test` — unit + snapshots. `make ui` — UI flows. `make audit` — accessibility audits.
- See [`TESTING.md`](TESTING.md) for the full matrix and determinism hooks.

## CI

`.github/workflows/ci.yml` runs `make unit` on PRs and pushes to `main`/`release/**`. It
needs a runner with Xcode 26.x + the iOS 26 simulator runtime. Snapshot/UI suites are
intentionally local-only (sub-pixel sensitive to the rendering host).
