# Marble Testing

## Suites
- Unit tests: `MarbleTests` (logic, seed data, date grouping, contrast, workout-import
  mapping, the handwritten-scan parser/importer + a real Vision-OCR integration test, the
  `RenderMemo` cache, Strava credential resolution, bulk text/CSV import
  (`WorkoutCSVParserTests`, `WorkoutSessionSegmenterTests`, `WorkoutTextEntryViewModelTests`,
  `WorkoutScanViewModelTests`), and the **personal-records engine**
  `PersonalRecordsTests` — PR-badge trail, unit-normalized weight records, all-time bests,
  usual ranges, the live-PR projection, workout sessions, sprint-prescription target
  boundaries, frozen per-rep goal evaluation/persistence/orphan cleanup, V3-to-V4 migration,
  exercise-editor draft/type/validation/impact rules,
  backup/restore validation, and recovery safety). Runs in CI.
- Snapshot tests: `MarbleSnapshotTests` (SwiftUI rendering with SnapshotTesting), **including
  the five Weekly Goal widget families** at real widget point sizes
  (`WeeklyGoalWidgetSnapshotTests`).
- UI tests: `MarbleUITests` (end-to-end flows + screenshots), including first-run onboarding
  (`OnboardingFlowUITests`) and Settings, with the weigh-in log → edit → delete round trip
  (`SettingsFlowUITests`). Tab bar is **Train / Log / Progress** (`Tab.Split` /
  `Tab.Journal` / `Tab.Trends`). Calendar and Supplements are Log modes: `navigateToTab`
  taps Log first, then `Tab.Calendar` / `Tab.Supplements` on `LogModePicker` segments.
  Visible labels are Train / Log / Progress; identifiers stay on the historical names.
- Accessibility audits: `MarbleUITests/AccessibilityAuditUITests` (contrast/labels/targets/clipping).

### Daily Highlights coverage

- `DailyHighlightsTests` pins the default 8:00 PM/midnight boundaries, overnight anchoring,
  equal-time validation, DST gaps/repeated hours, empty/future-day hiding, genuine PR rules,
  mixed-unit weights, matched-distance run bests, Trends filter independence, all 45 sourced
  quote records, three-unique-per-day selection, adjacent-day separation, full-catalog
  schedule coverage, and the rotation-resume rules (a tapped quote holds for at least one
  full interval, then auto-rotation resumes; permanent under VoiceOver/Reduce Motion).
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
  fetch limits used by the Train tab.
- `SeedDataTests.testOrphanMaintenanceRunsOncePerVersion` protects the versioned maintenance
  gate that keeps full-store orphan sweeps off routine launches.
- `DailyHighlightQueriesTests` is the correctness tripwire for the scoped Daily Highlights
  fetch: the day's rows plus the prior history of only that day's exercises must derive a
  summary identical to the full `SetEntry` table it replaced (including the all-time record
  veto a date-margin cut would miss), and exclude rows the builder never consumes.
- `ExercisePickerDerivedDataTests`' window cases pin the bounded picker recents query: an
  unfilled window is used as-is, a saturated window with enough distinct exercises skips
  escalation, and a single-exercise-saturated window escalates until recents match the
  unbounded query it replaced.
- `SprintPrescriptionTests` pins the key-column orphan sweeps (mixed tables delete only the
  orphan) and each backfill skip reason now enforced by the store predicate (missing
  duration, unprescribed exercise, invalid prescription).

## Suite inventory (counted from source, 2026-07-25 — build 49)
- Build 49 additions: `Tests/Snapshots/WeeklyGoalWidgetSnapshotTests.swift` (9 cases × light/dark
  across all five widget families), `Tests/Unit/WeeklyGoalWidgetCopyTests.swift`,
  `Tests/UI/OnboardingFlowUITests.swift`, `Tests/UI/SettingsFlowUITests.swift`,
  `PersistenceRecoveryTests.testMigratesV4StoreToV5WithoutRecoveryOrDataLoss`, the
  `createdExercises` cases in `WorkoutImportMapperTests`, and the bodyweight-facts cases in
  `MonthlyReportTests`.
- **Swift 6 note:** the unit and snapshot targets build under the Swift 6 language mode, so
  test classes that touch app types are `@MainActor` (the app defaults to main-actor
  isolation). `MarbleUITests` stays on Swift 5 — XCUITest's `NSPredicate`/`XCUIElement`
  surface is not `Sendable`-annotated. See `AGENTS.md`.

## Prior suite inventory (counted from source, 2026-07-23)
- `Tests/Unit/` — **53 files, 55 classes, 505 test methods**. Added past build 46:
  `WeeklyGoalWidgetStateTests`' Smart Stack relevance cases, pinning the pure
  `WeeklyGoalWidgetState.relevanceScore` the widget wraps in `TimelineEntryRelevance`;
  `TrendsChartDescriptorTests`, covering the Audio Graph descriptor helper behind every
  Trends chart (axis ranges, spoken dates/values, point labels, assembled descriptors);
  `DailyHighlightsTests`' quote-rotation-resume cases for the pure
  `DailyHighlightQuoteRotation` schedule; `DailyHighlightQueriesTests` (scoped highlights
  fetch equivalence); and the picker-window and sprint-maintenance cases in
  `ExercisePickerDerivedDataTests` and `SprintPrescriptionTests`.
- `Tests/UI/` — **17 files, 49 test methods**: **45 flow cases** plus
  `AccessibilityAuditUITests`' 4. `make ui` runs the flows and skips that audit class;
  `make audit` runs the audit cases instead.
- Counts here are derived by counting source, not by hand-editing the previous number
  forward. The long-stale "264" and "254" both came from carrying an old number through a
  docs commit.

## Latest verification (2026-08-20, bulk import honesty)

- Adds coverage for Hevy `set_index` resets, `superset_id` notes, Strong distance
  units, semicolon/`Weight (kg)` CSV, typed `RPE 8`, `Day N` session splits, likely
  matches defaulting to create-new, and scan library matching.
- Linux Cloud Agents cannot run `make unit`; GitHub Actions `CI / unit-tests` on
  `macos-26` is the compile gate for this branch.
- Hub button and journal origin under test are **Paste or Type**; do not look for
  "Typed Workout". File picker accepts `.txt` / `.csv` only.
- No schema change (still V6). Marketing version **2.4**, project build **57**.

## Latest verification (2026-08-20, bulk import fidelity)

- New unit coverage: Hevy/Strong warmup skip, RPE/notes/session clock, multi-page
  OCR join + N>1 scan handoff, OCR weekday punctuation headers, unique
  new-exercise counts, batch match breakdown (library / new / weak).
- GitHub Actions `CI / unit-tests` (`make unit` on macos-26): **green** on PR #23
  (run `32330557151`, SHA `cbd5116`) — **774 tests, 1 skipped, 0 failures**.
- Hub button under test is **Paste or Type** (`Import.TextEntry.Open`); do not
  look for "Typed Workout". File picker accepts `.txt` / `.csv` only.
- No schema change (still V6).

## Latest verification (2026-08-16, Train / Log / Progress IA on main)
- GitHub Actions `CI / unit-tests` (`make unit` on macos-26): **green** on PR #19
  (run `31967686916`) after restoring `WeeklyGoalCopy.progress` and removing
  `marble/AppIcon.icon/` (`actool` nil-object crash).
- Snapshots, UI flows, and `make audit` were not run here (Linux Cloud Agent;
  no Xcode). Re-record widget/Log/Progress snapshots on a Mac before treating
  `make test` as green.
- No schema change (still V6). TestFlight still 2.3 build 55 until a Mac archives
  project version 56.

## Latest verification (2026-07-30, import review timing wave on main)
- `MarbleTests` (`make unit`): **648 passed (1 skipped), 0 failed** — adds
  `WorkoutScanImporterTimingTests` (workout date stamps all sets, per-set
  `performedAt` override wins, `ImportedWorkout` ledger date = earliest effective
  set date) and extends `WorkoutScanViewModelTests` (addSet template copies the
  per-set override).
- `make audit`: green (both review screens gained the `ImportDateSection`
  pickers/toggle and per-set override affordances).
- `make typecheck-tests`: clean (pre-existing deprecation warnings only).
- No schema change (still V6), so the migration-release gate was not required.

## Verification (2026-07-30, free-form notation wave on main)
- `MarbleTests` (`make unit`): **645 passed (1 skipped), 0 failed** — adds
  `HandwrittenWorkoutParserFreeFormTests` (32 tests: hyphenated units, en-dash rep
  ranges, intensity-% noise, distance B-values, leading-spec lines, "N by M",
  single/double/triple rep words, name-filler stripping, bare-number weight/reps
  threshold, and the verbatim pole-vault user note).
- Live on-device model eval: **25/25 (100%)**, twice consecutively (corpus now
  16 notation + 9 prose after re-tiering cases the deterministic parser learned).
  Arbiter scoring gained colon-duration tokens and a coverage component so
  plausible-but-incomplete drafts can't beat drafts that explain more of the text.

## Verification (2026-07-29 late, parsing-quality wave on main)
- `MarbleTests` (`make unit`): **612 passed (1 skipped), 0 failed** — adds
  `WorkoutDraftArbiterTests` and `WorkoutParseCorpusTests` (24-case corpus: notation
  cases pinned against the deterministic parser; prose cases pinned as
  deterministic-parser failures so the model path's reason-to-exist stays visible).
- Live on-device model eval (opt-in, not CI):
  `TEST_RUNNER_MARBLE_FM_EVAL=1 make only TEST=MarbleTests/FoundationModelsLiveEvalTests`
  on an Apple Silicon Mac with Apple Intelligence enabled. Pass rate **21/24 (88%)**
  against the ≥80% threshold; run-to-run jitter of ±1 case is expected (intermittent
  model refusals despite greedy sampling). Baseline before the overhaul: 50%.
- `make audit`: green (prewarm hooks touched Scan/TextEntry sheets).

## Verification (2026-07-29, free-text import wave on main)
- `MarbleTests` (`make unit`): **594 passed, 0 failed** — the 560 below plus the
  free-text import suites: `ExerciseMatcherTests` (normalization, aliases, typo/word-order
  tolerance, ranking), `WorkoutTextEntryViewModelTests` (parse → match → review → commit,
  overrides, dedup), and `HandwrittenWorkoutParserRestTests` (rest notation incl.
  rest-only continuation lines).
- `make audit` (accessibility audit UI tests): green after the Import screen gained the
  Typed Workout section.
- `make typecheck-tests`: clean.

## Verification (2026-07-28, sprint V6 work on main)
- `MarbleTests` (`make unit`): **560 passed, 0 failed** — 519 on build 49 plus the sprint
  V6 suites: `SprintTimingTests` (tenths canon), `SprintVariantTests` (target math, tenths
  evaluation, primary selection, adoption sweep, legacy mirror, orphan sweeps),
  `SprintProgressionTests` + `SprintTrendsBuilderTests` (progression nudges, Trends
  derivation), `SprintTimePRTests` (fastest-time PR trail + stopwatch engine),
  `SchemaV6MigrationTests` (V5→V6 additive migration, multi-variant coexistence), and the
  `SprintVariantDraft` cases in `ExerciseEditorDraftTests`.
- `MarbleUITests/JournalFlowUITests.testSprintExerciseShowsDistanceAndDurationLogging`
  updated for the tenths flow (decimal `AddSet.Sprint.Time` field replaces the h/m/s
  duration menus for sprint exercises; `SetDetail.Sprint.Time` for detailed reps).

## Latest release verification (2026-07-25, 2.2 build 49)
- `MarbleTests` (`make unit`): **519 passed, 0 failed** — 505 on build 48 plus the V4→V5
  recovery case, three `createdExercises` cases, five monthly-report bodyweight cases, and
  `WeeklyGoalWidgetCopyTests`.
- `MarbleSnapshotTests` (`make snapshot`): **all 27 groups green** against baselines
  re-recorded on this build (see the stale-baseline note below).
- `MarbleUITests`: `OnboardingFlowUITests`, `SettingsFlowUITests`, `SmokeNavigationUITests`,
  and `CalendarFlowUITests` — **8 cases passed** (the suites new in or touched by this build).
- `AccessibilityAuditUITests` (`make audit`): **passed** after the Body/Settings/widget changes.
- Everything builds under the **Swift 6 language mode** except `MarbleUITests` (see `AGENTS.md`).
- Signed **build 49** Release archive + export passed; App Store Connect processing is `VALID`
  (buildId `5fe06de0-fc7a-4829-b4d7-a5f6f15d7f31`, uploaded 2026-07-25 to internal
  `test group A`). It is **not** attached to the in-review version.

## Prior release verification (2026-07-23, 2.2 build 47)
- `MarbleTests`: **505 passed, 0 failed** locally and in GitHub CI for the PR #12 merge —
  the counted inventory above (53 files / 55 classes / 505 methods) matches this run.
- `AccessibilityAuditUITests` (`make audit`): **passed** after the best-practices changes.
- Signed **build 47** Release archive/export passed; App Store Connect processing is
  `VALID` (buildId `83f4e8ca-a4cf-41ac-8080-4f8703851a42`, uploaded 08:03 PDT).
- App Review submission uses the Mac-based release gate below. Hardware-only Apple
  integrations remain recommended checks before manual public release, but they do not block
  submission when their logic, routing, packaging, and simulator fallbacks pass locally.

## Prior release verification (2026-07-22, 2.2 build 46)
- `MarbleTests`: **460 passed, 0 failed** locally and in GitHub CI run `29976114363`.
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
- Signed **build 46** Release archive/export passed for `Prism.marble` and
  `Prism.marble.MarbleWidgets`; IPA integrity and embedded versions passed. App Store Connect
  processing is `VALID` and `IN_BETA_TESTING`.

### Daily Highlights subtle quote verification (2026-07-22, 2.2 build 46)

- Removed the dedicated divider, quote icon, “Evening Note” label, serif emphasis, and
  pagination pills; the rotating quote is now secondary italic footer copy with a compact
  author and position line.
- The focused Daily Highlights snapshot comparison passed after intentionally refreshing the
  four changed default-size baselines; the Accessibility XXXL images remained byte-identical.
- The quote interaction/window test and focused light/dark accessibility audits passed.
- Full `MarbleTests`: **460 passed, 0 failed**.
- Rotation, manual advancement, the 44-point target, Dynamic Type, VoiceOver, and Reduce
  Motion behavior remain intact.
- Signed archive/export and TestFlight processing passed. IPA SHA-256 is
  `56e063e773647e7ea32cd6d4cfc3b1ff46052abab9c841972f148b3147b982e8`.
- App Store Connect build `1d775573-47fb-4757-bdbc-0cf600d5edfd` is `VALID` and
  `IN_BETA_TESTING` in internal all-build group `test group A`.

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

## Local App Store submission gate

Physical-device access is not required for App Review submission. Complete this gate on the
release Mac:

1. Confirm the candidate commit, project version, and uploaded build are the intended release.
2. Run `make unit`, `make ui`, `make audit`, `make verify-widget-plist`, and
   `make migration-release` on dedicated simulators.
3. Walk fresh-install onboarding and completed-user relaunch on iPhone. Verify onboarding,
   Settings, and the core layouts on iPad.
4. Exercise `marble://trends` and `marble://quicklog` with `xcrun simctl openurl`, and inspect
   the built app's `CFBundleURLTypes`.
5. Use the focused widget/keychain, Live Activity controller, App Intent, Spotlight entity,
   Health mapping/import, backup/restore, and notification tests as acceptance proof for
   OS-owned integrations.
6. Verify the widget extension is embedded, both targets archive, signed entitlements match
   `RELEASE_HANDOFF.md`, the IPA validates, and App Store Connect reports no blockers.
7. Keep release type manual. Hardware-only checks may be completed after submission and
   before public release when a device is available.

The simulator cannot prove locked-device keychain sharing, physical Action button assignment,
spoken Siri recognition, real Apple Health/Watch/Garmin data, Always-On Display, or real
background suspension. These are explicit residual product risks, not submission blockers.
Their pure behavior, persistence, routing, and failure handling must still pass locally.

## Optional physical-device pass

- Current phone-test build: **2.2 (47)**, build ID
  `83f4e8ca-a4cf-41ac-8080-4f8703851a42`; `VALID`, uploaded
  2026-07-23 at 08:03 PDT (the Apple-best-practices build, PR #12).
- Internal group `test group A` receives all builds; external beta remains unsubmitted.
- This section exercises Apple-owned surfaces beyond the deterministic local gate. It is
  recommended before public release, but is not required before App Review submission.

### 2.2 payload (what's new on this build)
- **Daily Highlights** — after logging today, open Trends during the default 8:00 PM–11:59 PM
  window. Confirm the card shows only truthful progress from that day, uses the clean
  monochrome hierarchy, and cycles among three quotes. Confirm the quote stays visually
  secondary with no heading, icon, divider, or pagination pills, and that there is no Share
  button. Confirm Settings →
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
  - **Build 47 headline fix — Siri now refreshes the widget.** With the app closed, log a
    set via Siri ("Log a set in Marble" / "Log my last set again in Marble") and confirm the
    Weekly Goal widget updates its count **without ever opening the app**. Build 46 and
    earlier left the widget stale here; on 47 a stale widget after a Siri log is a bug.
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
- **Restore from backup** — restore a JSON backup and confirm the data lands. Then check
  the Weekly Goal widget without reopening the app: build 47 refreshes it (plus the
  weekly-goal reminder, Spotlight, and the parameterised Siri phrases) right after a
  successful restore — the old "widget does not refresh after a restore" gap is closed.

### Build 47 additions (Apple best practices — device-only checks)
- **Rest-complete notification** — log a set with rest > 0, background Marble, and let the
  countdown reach `0:00`. A local **"Rest complete"** notification must arrive with the app
  backgrounded (nothing fired at zero before build 47). Then log another rest and end it
  early with the Live Activity's `End` button: the pending notification must be cancelled —
  no alert should arrive at the original end time.
- **Live Activity stale state** — start a rest, force-kill Marble, and leave the phone
  alone. At rest end + 60 seconds the card must flip to the quiet **"Rest over"** state
  instead of a frozen-but-live-looking timer (the controller stamps
  `staleDate = restEndsAt + 60s`; the widget renders `context.isStale`).
- **Always-On Display** — with an AOD-capable phone, let the screen dim during a rest and
  confirm the Live Activity dims with it (reduced-luminance treatment) rather than staying
  full brightness.
- **Widget quick-log button** — on the **medium** Home Screen family, tap the "Log set"
  capsule (not the card body). It must deep-link straight to the quick-log sheet via
  `marble://quicklog`; tapping anywhere else on the card still lands on Trends.
- **Tinted / clear Home Screen rendering** — switch the Home Screen to tinted and clear
  icon modes and check the widget: the progress arc and the quick-log capsule pick up the
  accent (`widgetAccentable` grouping) while the track and copy keep their hierarchy —
  nothing should flatten to one tone.
- **TipKit tips** — on a fresh install, confirm each tip appears exactly once near its
  surface: the scan tip on the Import scan button, the coaching tip on the Focus lift card,
  and the PR-feed tip on the PR feed header. Use each surface, then revisit: no tip may
  ever reappear.
- **Audio Graphs** — with VoiceOver on, focus a Trends chart, open the rotor, choose
  **"Chart Details"**, and play the audio graph. Every Trends chart (consistency, volume,
  e1RM, bodyweight, …) must offer one, with sensible spoken axis ranges and values.
- **Spotlight removal** — delete an unused exercise, then search its name in Spotlight
  immediately: it must be gone without relaunching the app (per-item de-index on delete).

### Carried-forward regression pass (2.1 payload)
- Start and finish a workout session, log planned and repeated sets, review recent workouts,
  check weekly-goal/priority-lift/monthly-report Trends, and export + restore a JSON backup.
  Confirm the backup disclosure that media is excluded. The backup payload now covers every
  schema entity — weigh-ins, the import ledger, progress-media *metadata* (never the photo
  or video binaries themselves), and custom reminders — and a restored reminder should fire
  again without reopening the Notifications screen.
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

## Snapshot baselines re-recorded on build 49 (2026-07-25)

**Every baseline was stale before this build.** `testTrendsPopulated` failed on clean
`main` (verified by stashing the build-49 work and re-running it): the references predate the
Trends 2.0 Focus card, so they showed the detailed-analytics strip where the current screen
shows Focus. Snapshots are **not** in CI — only `make unit` is — so nothing caught the drift.
Baselines were re-recorded with `make snapshot-record` and spot-checked by eye.

If you add a snapshot suite, consider whether it can join CI; a baseline nobody runs is not
coverage.

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
  `AppStoreScreenshotUITests.test09PrivateOnboarding` verifies the first privacy page and
  device-neutral copy on both screenshot simulators.

## Known test gaps
Recorded honestly so nobody assumes coverage that isn't there. Tracked in `ROADMAP.md`
under **Known gaps / next up**.

**Closed in build 49** (all four gaps below were open through build 48):
- ~~No automated end-to-end onboarding completion flow.~~ `Tests/UI/OnboardingFlowUITests.swift`
  walks all three pages, finishes, asserts the app is revealed, and asserts the unit chosen
  during onboarding reaches Settings. It is the first test to drive the
  `MARBLE_FORCE_ONBOARDING` hook (which had zero references in `Tests/` outside the
  screenshot capture).
- ~~Settings has no automated interaction coverage.~~ `Tests/UI/SettingsFlowUITests.swift`
  reveals every row on the screen (scrolling first — `List` rows below the fold are absent
  from the accessibility tree) and drives log-weigh-in → history → swipe-delete.
- ~~No widget snapshot suite.~~ `Tests/Snapshots/WeeklyGoalWidgetSnapshotTests.swift`
  snapshots all five families in light and dark at real widget point sizes, each with a live
  snapshot and in the neutral "no trustworthy data" state. The layouts moved to
  `marble/Shared/WeeklyGoalWidgetViews.swift` (app + widget membership) to make this possible;
  `WeeklyGoalWidgetCopyTests` pins the copy layer, including the unknown-`stateRaw` fallback.
- ~~No V4→V5 case in `PersistenceRecoveryTests`.~~
  `testMigratesV4StoreToV5WithoutRecoveryOrDataLoss` seeds a real V4 store, reopens it through
  `makeRecoveringContainer`, and asserts the rows survive, the new table exists, and **no
  `.corrupt` backup was written** — a V4 store falling into the recovery path would reset a
  shipping user's journal.

Still open:
- No automated coverage of the Live Activity's system presentation (device-only).
- Strava's OAuth round trip is unverified end to end; it ships unconfigured.
