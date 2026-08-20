# Marble

A local-only workout + supplements journal for iOS, built with SwiftUI and SwiftData — and
a calm UI layer for pulling in workouts from Apple Health, Garmin, and Strava.

## What it is

The tab bar is three destinations: **Train**, **Log**, and **Progress**. Calendar and
Supplements are modes inside Log (not separate tabs). Deep links `marble://calendar` and
`marble://supplements` still open those modes.

- **Train** — start and finish timed workout sessions, complete a planned set in one tap
  when that exercise already has history, and review recent sessions. The weekly split
  remains the editable plan behind Settings. An active session shows a tab-bar accessory
  (rest timer wins over the session pill).
- **Log** — fast logging of sets (weight, reps, distance, duration, RPE, rest) with
  per-exercise metric profiles, plus Calendar and Supplements as Log modes.
  **Personal-best (PR) badges** celebrate record sets right in the history, and the logging
  screen shows your current PR (heaviest + most reps) and usual range so you can shoot to
  beat it — with a live "New PR!" cue the moment your entry passes your best.
- **Progress** — a focused weekly goal, priority lift, and monthly report first; detailed
  consistency, volume, per-exercise, supplement, and PR charts remain one tap away.
- **Exercise library** — a searchable, category-filterable home for creating, favoriting,
  and safely editing reusable exercises. Explicit tracking types keep standard setup short,
  while Custom exposes every metric requirement. See
  [`EXERCISE_LIBRARY.md`](EXERCISE_LIBRARY.md).
- **Calendar** — month view with workout-day markers, day detail, and progress photos/videos
  (Log → Calendar).
- **Sprint workouts** — create multiple reusable sprint plans per exercise ("60 m speed",
  "150 m tempo") with a repetition count and an exact or ranged target time in **tenths of
  a second**; log every sprint with a built-in stopwatch or typed decimal time, RPE, rest,
  rep progress, and immediate goal feedback, then get a sequence rollup after the final
  rep. Log previews show an accessible green hit, red miss, or neutral unscored state
  plus a "Fastest" PR trail per distance; Progress charts best-time progression and weekly
  goal hit rate, and plans that keep getting beaten earn a progression nudge.
  See [`SPRINT_WORKOUTS.md`](SPRINT_WORKOUTS.md).
- **Daily Highlights** — from 8:00 PM through 11:59 PM by default, Progress celebrates
  that day's genuine PRs in a clean monochrome card with three daily quotes as a quiet
  rotating footer. The window is customizable and the feature remains entirely on-device.
  See [`DAILY_HIGHLIGHTS.md`](DAILY_HIGHLIGHTS.md).
- **Body** — log bodyweight (and body fat) in whichever unit you think in, stored as
  canonical kilograms. Weigh-ins are **editable and deletable** from Progress, Settings, and
  the Calendar day summary, so a typo can't quietly skew your bodyweight trend or your DOTS
  relative-strength score. The monthly report reads the month's first and last weigh-in.
- **Data safety** — export and restore exercises, sets, supplements, sessions, and plans as
  JSON. Progress photos and videos remain on-device and are intentionally excluded.
- **Import** — bring workouts in from Apple Health (Apple Watch, Garmin, …) and Strava, scan
  every page of a handwritten notebook, or **Paste or Type** a workout / week of Notes / a
  Hevy or Strong CSV. Scan and typed paths read on-device (Apple Intelligence when
  available, deterministic parser otherwise), split dated sessions, match the exercise
  library, and wait for review before anything is logged. See
  [`INTEGRATIONS.md`](INTEGRATIONS.md).
- **Rest timer** — after interactive set logging, a tab-bar pill counts the rest down inside
  the app (iOS 26 bottom accessory, with an End button), while a WidgetKit Live Activity
  mirrors it on the Lock Screen / Dynamic Island.

Everything is stored on-device. Nothing is tracked or sent to a server (there is no server).

## Current state (2026-08-20)

- **Bulk import honesty** (2.4 train, project build 57): Hevy same-lift re-logs keep
  order; EU Strong CSV parses; weak matches do not auto-merge into the library; scan
  review matches exercises and shows rest/RPE/notes; **Paste or Type** is the user-facing
  name. **App Store 2.3 stays `READY_FOR_DISTRIBUTION` (IA-only relative to this wave —
  do not release it as a stand-in).** This wave ships as **2.4 TestFlight**. No schema
  change (still V6).
- **Bulk import fidelity** (on `main`, PR #23 merge `cbd5116`): Hevy/Strong CSV skips warmup
  sets, maps RPE and notes, and keeps the session clock; multi-page scans concatenate OCR
  and hand a dated week to Paste or Type; batch review is honest about library / new /
  weak matches. No schema change (still V6). Linux CI gate is `make unit` on `macos-26`
  (774 tests green on that merge).
- **Train / Log / Progress IA** (on `main`, PR #19 merge `c0cef9e`, 2.3 project build 56,
  pending TestFlight after `make asc-next-build` on a Mac): three tab-bar destinations;
  Calendar and Supplements are Log modes; planned sets with history complete in one tap
  (`SetLogging.repeatLatest`); Log Set is a medium morphing sheet from `+`; session
  accessory when a workout is live; lock-screen widget copy drops two-digit streaks. No
  schema change (still V6). CI `make unit` on `macos-26` is green. Cloud Agents
  ship TestFlight/App Store through `make cloud-*` (see [`CLOUD_RELEASE.md`](CLOUD_RELEASE.md));
  this Linux VM still cannot archive locally. **2.2 stays `READY_FOR_DISTRIBUTION`
  (manual App Store release pending) — this wave is 2.3 TestFlight, not a 2.2 App
  Store push.** See [`RELEASE_HANDOFF.md`](RELEASE_HANDOFF.md).
- **`main` carries the Typed Workout order/progress/delight wave** (shipped in 2.3
  build 55, TestFlight `VALID` 2026-08-05): the journal now lists an imported workout
  in the exact order the review
  screen showed (the importer spaces otherwise-identical set timestamps by a
  millisecond ordinal cascade — newest-first sort reproduces review order, explicit
  per-set times still win); preview generation shows a staged determinate progress
  bar with percent (real pipeline stages, each Apple Intelligence pass reported);
  the input step gains a system Paste button (no clipboard-permission prompt, no
  programmatic clipboard reads); review gains exercise reorder controls (saved order
  follows it); and the imported screen celebrates total volume (Σ weight × reps in
  the user's preferred unit) plus any beaten PRs via the existing records engine.
  The deterministic parser also learned rep ladders/pyramids ("225x5/3/1", "5/3/1 @
  225", "3x10-8-6" — one set per rung), strips tempo notation as noise (fixes the
  corruption where "3x5 tempo 31x1" became sets of 3 lb and 31 lb), and reads
  round/circuit headers ("3 rounds:", "Circuit 1", "three rounds:") as structure —
  counted headers multiply the following movements' sets instead of becoming junk
  exercises. No schema change (still V6). Unit suite **706 tests** green.
- **`main` carries the app-export paste + zero-silent-loss wave** (shipped in 2.3
  build 55, TestFlight `VALID` 2026-08-05): Hevy ("Set 1: 60 kg x 10") and Strong
  exports paste correctly with
  weight and reps; Notes-style blocks (a name line then "185 x 8" per set) import;
  every line the parser can't read is surfaced in review with inline edit +
  re-parse; "1,025 lb" no longer becomes 1 lb; AMRAP/failure keep their set count;
  EMOM expands; prose is flagged for review instead of mangled into fake exercises;
  "yesterday" sets the date; the input step marks each line recognized/not per
  keystroke; and unitless weights default to the user's preferredWeightUnit instead
  of hardcoded lb. Unit suite 682 tests green at merge.
- **`main` carries the import review timing wave** (unreleased, after build 53): both
  import review screens (Scan + Typed Workout) gain workout-level date & time control
  (compact pickers, progressive "Include Time" toggle) and per-set date & time overrides
  (context menu / leading swipe on a set row) so multi-day pages and mixed sessions land
  on the right days; the import-history ledger records the earliest effective set date;
  and both sheets get dismissal protection ("Discard this import?") so a swipe-down
  can't silently throw away a reviewed draft. No schema change (still V6). Unit suite
  **648 tests** green; accessibility audit green.
- **`main` carries the free-form notation parsing wave** (first shipped in build 53):
  driven by a real pole-vault note build 52 mangled — the deterministic parser learned
  hyphenated units, en-dash rep ranges, intensity-% noise, distance sets ("4×20m"),
  spec-first lines, "5 by 5", rep words, and name-filler stripping; the arbiter gained
  coverage scoring. Live eval: **25/25 (100%)** stable (see TESTING.md).
- **`main` carries the on-device parsing quality overhaul** (shipped in build 52):
  the FoundationModels pipeline behind Typed Workout and Scan was rebuilt — the model now
  reports counts/values (`setCount`) and code expands sets; a second model pass rewrites
  prose into gym notation for the deterministic parser; a new `WorkoutDraftArbiter`
  scores every candidate draft against the source text so the deterministic parse always
  wins on notation input; guardrail refusals on benign gym prose are handled with
  Apple's permissive-transformation mode plus one retry. Measured on a 24-case eval
  corpus: 50% → **88%** exact-parse rate (see TESTING.md for the opt-in live eval).
- **`main` carries the free-text workout import wave** (shipped in build 51):
  a "Typed Workout" path on the Import screen — type or paste a workout in plain words
  ("Bench press 3x8 @ 185, rest 90s"), parsed on-device (FoundationModels when Apple
  Intelligence is available, the deterministic notation parser otherwise) into a review
  screen where every exercise shows whether it logs to an existing library exercise or
  creates a new one, adjustable per exercise before committing. Ships with:
  1. **`ExerciseMatcher`** — alias-aware (db/bb/ohp/rdl…), word-order-independent,
     typo-tolerant matching of parsed names to the library, so imports stop silently
     creating near-duplicate exercises.
  2. **Rest-notation parsing** — "rest 90s", "90s rest", "rest 2 min", and rest-only
     lines now land in `SetEntry.restAfterSeconds` (scan flow gains this too).
  3. **`ImportSource.textEntry`** + a source-parameterised `WorkoutScanImporter`; same
     dedup ledger (identical text re-imports warn), **no schema change** (still V6).
  Unit suite **594 tests** green; accessibility audit green.
- **`main` also carries the sprint V6 feature wave** (shipped in build 50): schema V6 adds
  `SprintVariant` + `SprintRepDetail` (pure additive, no migration stage), bringing:
  1. **Tenths-precision sprint timing** — targets and times are canonical tenths
     (`SprintTiming`; 14.8 beats 15), entered as decimal seconds; the shipped whole-second
     column keeps the rounded value for every legacy consumer.
  2. **A built-in stopwatch** in the sprint logger (start/stop fills the time, rolls into
     the rest timer; unit-tested engine, hidden under UI testing).
  3. **Multiple sprint plans per exercise** — "60 m speed" and "150 m tempo" on one
     exercise, with a plan picker in the logger; the legacy single `SprintPrescription`
     lives on as a synced mirror of the primary plan for pre-V6 surfaces and backups.
  4. **A sequence rollup** after Save Final Rep (hits, best, average, per-rep results).
  5. **Sprint analytics** — a "Fastest" PR trail per exercise + distance in the Journal,
     and a Sprints section in Trends (best-time progression, weekly goal hit rate, full
     Audio Graph descriptors), plus **progression nudges** after two ≥80%-hit sessions.
  See [`SPRINT_WORKOUTS.md`](SPRINT_WORKOUTS.md). Unit suite **560 tests** green,
  including `SchemaV6MigrationTests`.
- **Also on `main`: a 10-fix reliability pass** on top of build 49, from a
  full-codebase bug audit (models/persistence, views, widgets/intents/timers). Highlights:
  1. **Number fields no longer corrupt grouped values** — the editing field displayed
     "1,500" but parsed every comma as a decimal point, so touching a 1,000+ value (or any
     grouped value in comma-decimal locales) silently collapsed it to 1.5.
  2. **Deleting a set from Set Details no longer writes to the deleted model** on dismissal
     (the SwiftData destroyed-backing-data crash pattern).
  3. **The Control Center "Log a Set" control actually opens the logger** — it now routes
     through the `marble://quicklog` deep link instead of an in-process notification that the
     widget-extension process compiles out.
  4. **Backup restore** dedups HealthKit weigh-ins by `healthKitUUID` (not just row id) and
     never adopts a set entry into a second workout session.
  5. **First-run seeding** stamps its one-time flags only after a durable save, so a single
     failed save can no longer leave a permanently empty exercise library.
  6. **Calendar backdated sets** no longer attach to today's active workout session.
  7. **Journal undo-delete** restores the entry's imported-workout lineage and
     workout-session membership.
  8. **Weekly-goal reminder** never nags users with zero logged sets; **rest-complete
     notifications** can no longer fire for a rest that was already ended or replaced
     (schedule/cancel are serialized).
  9. **Reps prefill** is no longer silently clamped to 20 (only the slider pins to its track).
  10. Demo-recording seed hook: `MARBLE_SEED_DEMO_FIXTURES` seeds the screenshots fixture on
     a normal (non-UI-testing) launch, and the fixture's Workout-tab session now matches
     whatever split the capture day seeds.
- Unit suite **519 tests** green after the pass; full test-target compile clean.

## Prior state (2026-07-25)

- **On TestFlight: 2.2 (build 49).** Build 48 plus the five items from the build-48 codebase
  review — see [`ROADMAP.md`](ROADMAP.md) → Known gaps / next up, where every closed gap is
  struck through with what closed it:
  1. **Weigh-ins are editable and deletable** (`BodyMetricHistoryView`, reachable from Trends,
     Settings, and the Calendar day summary). Before this, `BodyMetricEntryView`'s edit path had
     no caller, so a typo'd weigh-in was permanent — and it skewed every DOTS score.
  2. **The release-safety test gate is closed**: onboarding flow, Settings flow, a widget
     snapshot suite for all five families, and a V4→V5 case through the *recovery* container.
  3. **Deployment floor 26.2 → 26.0** — build 48 excluded every device on 26.0/26.1 for one API.
  4. **Import-created exercises reach Spotlight and Siri immediately**, plus the three
     unshipped 2.4 Body items (Calendar weight-on-day, monthly-report bodyweight facts, quick
     weight entry from Settings).
  5. **Swift 6 language mode** for app, widget, and the unit/snapshot test targets; `UndoableIntent`
     so a Siri-logged set can be undone.
- Unit suite **519 tests**, snapshots re-recorded and green, `make audit` green.
- **2.2 (build 48) is still the build in App Review** — build 49 does not replace it.

## Prior state (2026-07-23)

- **Live on the App Store: 2.1 (build 40)**, released 2026-07-21
  (`READY_FOR_DISTRIBUTION` in the
  App Store Connect API).
  It carries builds 35–39 — workout sessions, sprint prescriptions, the Exercise Library
  redesign, and JSON backups. No phased release was configured, so it went to 100% at once.
- **On TestFlight: 2.2 (build 47)** — `VALID`, uploaded 2026-07-23 at 08:03 PDT (build id
  `83f4e8ca-a4cf-41ac-8080-4f8703851a42`) to the all-build internal group `test group A`.
  **Not yet submitted to App Review.** Build 47 is build 46 plus the Apple-best-practices
  merge (PR #12): intents refresh the widget/reminder/Spotlight, complete JSON backup,
  Live Activity staleDate + rest-complete alert, TipKit tips live, Audio Graph chart
  descriptors, Smart Stack relevance, the widget quick-log link, the extension privacy
  manifest, and the scoped-query performance pass (505 unit tests, CI green). 2.2 is the "ambient" release,
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
- **Known gaps:** most of the "wired up but inert" 2.2 defects were closed on
  `feature/apple-best-practices` (2026-07-22): TipKit tips now present, Siri-logged sets
  refresh the widget/reminder/Spotlight, backup covers every entity, deleted exercises leave
  Spotlight immediately. Still open: bodyweight entries can't be edited or deleted, and the
  DOTS coefficient picker only lives in the Log Weight sheet. See **Known gaps / next up** in
  [`ROADMAP.md`](ROADMAP.md) before promising anything works.
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

- Open `marble.xcodeproj` in Xcode (26.x; the target deploys to **iOS 26.0**).
- Select an iOS Simulator and run the `marble` scheme.

## Architecture

- **SwiftUI + SwiftData, local-only.** Tab bar: **Train / Log / Progress** (Calendar and
  Supplements are Log modes). Feature folders under `marble/Features/` still use the
  historical names: `Body`, `Calendar`, `Import`, `Journal`, `Notifications`, `Onboarding`,
  `RestTimer`, `Settings`, `Split`, `Supplements`, `Trends`, and `Workout`. Code shared
  with the widget extension lives in `marble/Shared/`; App Intents live in `marble/Intents/`.
- **Models** (`marble/Models/`) are SwiftData `@Model` types plus a rich domain core in
  `Enums.swift` (the configurable per-exercise metric profiles).
- **Versioned schema — currently V6.** `marble/Persistence/MarbleSchema.swift` declares V1,
  additive V2 workout-session storage, additive V3 sprint prescriptions, additive V4 per-rep
  sprint goal snapshots, additive V5 `BodyMetricEntry`, additive V6 `SprintVariant` +
  `SprintRepDetail`, and `MarbleMigrationPlan`. Every change so far has been additive, so
  `MarbleMigrationPlan.stages` is `[]` and must stay that
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
| [`DAILY_HIGHLIGHTS.md`](DAILY_HIGHLIGHTS.md) | End-of-day celebration rules, time-window semantics, privacy, and tests |
| [`ROADMAP.md`](ROADMAP.md) | H2 2026 plan: what shipped in 2.2, **known gaps / next up**, and why the Watch app was deferred |
| [`CLOUD_RELEASE.md`](CLOUD_RELEASE.md) | How Cloud Agents publish to TestFlight and the App Store |
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

TestFlight and App Store publishing are separate manual workflows
(`.github/workflows/release-testflight.yml`, `release-appstore.yml`). See
[`CLOUD_RELEASE.md`](CLOUD_RELEASE.md).
