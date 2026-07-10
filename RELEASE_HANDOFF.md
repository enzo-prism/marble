# Marble Release Handoff

**Last verified: 2026-07-10.** This file is the single source of truth for "where the
project is right now." App Store review and ASC build state can change outside git, so
always re-run the **Live state checks** (bottom of this file) before acting.

---

## TL;DR — what "up-to-date" means today (2026-07-10)

- **Code baseline:** **2.0 (build 36)** fixes the build-35 launch crash for stores created
  by earlier releases. The additive V2 schema now uses SwiftData's automatic lightweight
  migration instead of the redundant explicit stage that resolved both endpoints to the
  V2 checksum. It retains first-class workout sessions, focused Trends, JSON backup/restore,
  safer recovery, visible persistence errors, and true Apple Health session bounds.
- **Build 32 baseline:** a performance pass
  for all supported iPhones (A13 floor): range-scoped Trends `@Query`s (thin `TrendsView`
  shell + `TrendsContentView` init-built predicates — the documented dynamic-query
  pattern; "All" stays unbounded by design), day-scoped `ProgressMediaSection` query,
  one-row `updatedAt` freshness probes (`LatestUpdateQueries` + new `updatedAt` indexes
  on SetEntry/SupplementEntry/ProgressMediaAttachment — additive, lightweight migration)
  replacing the per-frame O(n) signature reduces, and Journal-style memoization for
  Supplements grouping. Equivalence test proves scoping is behavior-identical; 3
  `measure()` tripwires (`DerivationPerformanceTests`) pin the 5k-row derivation costs.
  Unit suite = **182 tests**. Deliberately NOT changed: Journal/Calendar full-history
  queries (behavior), chart mark construction (pre-bucketed small N), launch path
  (already deferred).
- **Build 31 baseline:** a workout-import
  overhaul on top of build 30: enriched `ImportedWorkout` ledger (kind/origin/source app/
  device/distance/duration/calories/avg+max HR/elevation/indoor — all additive optional
  fields, lightweight migration) with `SetEntry.importedWorkout` linkage; provenance
  badges in the journal (`ImportedOriginBadge`) + read-only "Imported Workout" section in
  set detail; `ImportedWorkoutDetailView` (stats grid + live HR sparkline, gated ≥8 points
  because Garmin bridges HR sparsely); `HealthAutoImportService` (opt-in foreground
  auto-import via persisted `HKQueryAnchor`, anchor advances only after save); HealthKit
  authorization fixed to `getRequestStatusForAuthorization` (old code misread write-side
  sharing status); parallel per-workout HR enrichment (was serial), max-HR/elevation/
  indoor/source-app/device captured; expanded `activityKind` mapping; Load menu with
  30/90/365-day lookbacks + zero-result Settings guidance; Garmin card with live bridge
  status, numbered setup steps, `gcm-ciq://` deep link (App Store fallback); import
  history section in the hub. Unit suite = **178 tests** (new
  `HealthAutoImportServiceTests`, importer link/detail tests, metadata-parsing tests);
  `ImportFlowUITests` grew to 3 flows; populated fixture seeds a Garmin run so audits
  walk the new UI. **Gotcha reconfirmed:** container `accessibilityIdentifier` clobbers
  child identifiers (Import.GarminBridge moved off the VStack onto the header row).
- **Build 30 baseline:** an iOS 26 design/UX polish pass on top of build 29: an **in-app rest-timer pill** (`tabViewBottomAccessory`,
  observable `RestActivityController.activeRest`, `RestTimerPillView`, End button) so the
  rest countdown is finally visible *inside* the app (the Live Activity mirrors it as
  before); the Journal Import sheet zoom-morphs out of its toolbar button
  (`matchedTransitionSource` on the ToolbarItem — item-level, NOT on the button, which
  corrupts toolbar accessibility); `ToolbarSpacer(.fixed)` separates the primary "+" into
  its own glass capsule on Journal/Trends/Supplements; Add Set gains a Cancel button
  (`.cancellationAction`, Save is `.confirmationAction`); a haptics pass
  (`MarbleHaptics.selection()` on preset chips / trend range / calendar day; Supplements
  quick-add/delete/undo now haptic + explicit `saveOrRollback` with failure toasts).
  Unit suite = **168 tests** (new `RestActivityControllerTests` state-machine coverage);
  new `RestTimerPillUITests` (launches with a real `now` + `MARBLE_ENABLE_REST_PILL`).
- **Host testing caveat (2026-07-01):** two `JournalFlowUITests` cases
  (`testDualDumbbell…`, `testSprint…`) fail on this Mac **on clean main too** (keyboard
  Return-key AX flake in `dismissKeyboardIfPresent`); environmental, not a release gate.
  Everything else in `make ui` + `make audit` is green.
- **Previous baseline:** build 29 added the **personal-records (PR)** feature on top of
  build 28. New pure engine
  `marble/Components/PersonalRecords.swift` computes, all-time and weight/reps-only: a trail
  of every record-setting set (each badged in the Journal + quick-log card), the heaviest and
  most-reps bests (each shown as its full weight × reps combo), and the usual working range.
  The logging screen (`AddSetView`) gains a "Personal best" target card and a live "New PR!"
  banner the moment the entry beats a record (`projectedBadge`), plus a celebratory haptic
  (`MarbleHaptics.celebrate()`). Weight records are unit-normalized (lb/kg) before comparison.
  Build 28 (perf/iOS 26 pass, `RenderMemo`, `@Observable` migration, handwritten workout scan)
  remains underneath. `origin/release/1.9` may still point at the older 1.9 build 20 baseline.
- **Latest TestFlight build:** **2.0 (build 36)** uploaded 2026-07-10; processing is
  **`VALID`**, internal state is **`IN_BETA_TESTING`**, and build id is
  `1179329c-c5f5-438d-9bca-52ac05e9aa08`. Internal group `test group A`
  (`514a95e2-28fc-436b-b624-9aaec2963adc`) receives all builds. External beta remains
  `READY_FOR_BETA_SUBMISSION` and was not submitted.
- **Current working project version:** **2.0 (build 36)**;
  `MARKETING_VERSION = 2.0`, `CURRENT_PROJECT_VERSION = 36` in
  `marble.xcodeproj/project.pbxproj`.
- **Build/test health:** Xcode 26.5 / iOS 26.5 simulator; **239 unit tests**, all **35 UI
  flows**, and the default accessibility audit pass. One chart-coordinate UI test needed an
  immediate isolated retry after the full-suite run; it passed unchanged. A dedicated
  Release gate installed build 34, preserved all 40 seeded exercises, overlaid build 36,
  launched without an exception, and verified the new `WorkoutSession` table. The runtime's
  unsupported Dynamic Type audit is an expected skip covered by dedicated XXXL tests. The
  signed app + widget archive/export succeeded. Snapshot baselines remain host-sensitive;
  the unchanged build-35 source reproduces the same Add Set mismatch on this runtime.
- **Live Activity wiring:** `MarbleWidgets` is now a real app-extension target embedded in
  the app, `NSSupportsLiveActivities = YES` is set on the app target, and
  `RestTimerAttributes.swift` is shared into the widget target.
- **Live App Store:** version **2.0 is `WAITING_FOR_REVIEW`** under submission
  `a89a2e97-369e-4f80-a658-2cab40d79b19`. The build 36 TestFlight upload did not alter,
  cancel, or resubmit that App Store review.

---

## What 1.9 contains (vs shipped 1.8)

Features:
- Workout import hub (`marble/Features/Import/`) — Marble as a UI layer over fragmented
  workout sources. **Apple Health** is the universal bridge (Apple Watch, Garmin, and any
  app that syncs to HealthKit), with each workout labeled by its true origin. **Strava** is
  a direct official OAuth 2.0 connector (appears once Strava API keys are set in Info.plist).
  **Garmin** flows in through Apple Health (Garmin Connect → Apple Health), surfaced with a
  "Garmin" badge and an in-app explainer. See "Workout import" below before shipping.
- Progress media crop-editing polish.

Hardening added on top (commit `3612df5`):
- Explicit SwiftData `VersionedSchema` + migration plan (`Persistence/MarbleSchema.swift`).
  The container now self-recovers from a failed migration (backs the store up to
  `*.corrupt`, recreates, in-memory fallback) instead of `fatalError`-crashing on launch.
- `ImportedWorkout` gained a DB-level unique `deduplicationKey`.
- Removed HealthKit force-unwraps; Garmin skips activities with no id/date.
- Swift 6 readiness: value types SwiftData serializes are `nonisolated`
  (the target uses `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`).
- `PrivacyInfo.xcprivacy` added (no tracking/collection; UserDefaults + file-timestamp reasons).
- GitHub Actions CI runs the unit suite on PRs/release pushes (`.github/workflows/ci.yml`).
- New import unit tests (`ImportProviderMappingTests`, `ImportViewModelTests`).
- Workout import hub: Strava OAuth connector (`Strava/StravaClient`, `Strava/StravaProvider`,
  `OAuth/`), Apple Health origin detection (`HealthKitWorkoutProvider.originName`), and a
  Garmin-via-Health explainer. Unit tests in `ImportProviderMappingTests`.

Build 24 hardening:
- Import reliability: source fetch/import re-entry guards, injected import handlers for
  failure tests, batch-level duplicate skipping, and HealthKit sample fetches with no
  artificial 50-workout cap.
- First-run and logging UX: empty Journal start checklist, Add Set "Save + Next",
  split-plan session context, and safer keyboard-visible save controls.
- Visual/test stability: calendar top spacing, refreshed Journal empty + Calendar month
  snapshot baselines, `ExerciseEditor.List` accessibility targeting, max-notification
  footer scrolling, and widget `Info.plist` verification in Makefile test targets.

---

## Workout import — read before shipping

Marble is positioned as a UI layer over fragmented workout sources. All paths are
**ToS-aligned and need no backend**:

- **Apple Health (live, always on):** the universal bridge. One HealthKit query surfaces
  Apple Watch, Garmin, Strava, Wahoo, etc.; `HealthKitWorkoutProvider.originName(...)` reads
  the HK source/device metadata and labels each workout by brand.
- **Garmin (via Apple Health):** the sanctioned route. The user enables Garmin Connect →
  Apple Health (one-time, in Garmin's app); Garmin workouts then appear in the Apple Health
  list with a "Garmin" badge. The Import screen has an explainer + "Open Garmin Connect"
  button. We deliberately **do not** touch Garmin's servers (no reverse-engineered login).
- **Strava (direct, official OAuth 2.0):** `ASWebAuthenticationSession` → code → token
  exchange → bearer, Keychain-stored with auto-refresh; pulls `athlete/activities`
  summaries. Hidden until a developer sets `StravaClientID` / `StravaClientSecret` /
  `StravaRedirectURI` in Info.plist (and an Authorization Callback Domain matching the
  redirect URI's host in the Strava API app). The redirect scheme needs **no**
  `CFBundleURLTypes` entry — `ASWebAuthenticationSession` claims it transiently.
  - Caveat: Strava's token exchange uses `client_secret`. Shipping it in-app is the common
    indie compromise; for production consider a tiny token-exchange proxy and point
    `StravaRedirectURI` / exchange at it.

What's verified: app + 152 unit tests build green on Xcode 26.5 / iOS 26.5; Strava mapping,
sport-type classification, date parsing, HealthKit origin detection, Strava credential
resolution (env vars → Info.plist), import re-entry, failure handling, and duplicate-batch
skipping are unit-tested; the handwritten-scan parser/importer plus a real Vision-OCR
integration test (`WorkoutTextRecognizerIntegrationTests`) cover the photo-scan pipeline;
`ImportFlowUITests` and `ScanFlowUITests` open the import hub from the Journal and check that
Apple Health, the Garmin bridge, and the Scan capture screen render and dismiss.
What needs a live pass: the Strava OAuth round-trip + real `athlete/activities` JSON (needs
real Strava API keys + account), Garmin→Health labeling against a real Garmin source, and
on-device HealthKit average-HR enrichment.

Note: Apple Health carries workout **summaries** (type, distance, duration, calories, HR —
Marble now reads average HR per workout and adds it to the imported note), not per-set
strength detail (weight×reps). Lift-level data would require Garmin's official Activity API
(FIT files) + a backend — out of scope for this no-backend build.

---

## Signing history: HealthKit upload blocker resolved

The earlier Release archive failed at **code signing**. The blocker path was:

1. **Pending Apple Developer Program License Agreement (PLA).** All provisioning operations
   — Xcode automatic signing AND the `asc` / App Store Connect API — are blocked
   account-wide with:
   > "PLA Update available… Account Holder, **Lorenzo Quaid Sison**, must agree to the
   > latest Program License Agreement."

   **No CLI can accept this.** Apple does not expose PLA acceptance through the App Store
   Connect API (verified: `asc agreements` only covers EULA territories; `asc web` has no
   agreements flow). It must be accepted by the Account Holder signing in at
   <https://developer.apple.com/account>. **Do this first** — nothing else can proceed
   until it clears.

2. **HealthKit signing not provisioned.** 1.9 added the `com.apple.developer.healthkit`
   entitlement (`marble.entitlements`), but no provisioning profile includes it, and this
   Mac's Xcode has no Apple ID account configured for automatic signing. The
   "Apple Distribution: Lorenzo Quaid Sison (L49MKXGVM4)" certificate *is* in the keychain.

**Resolution used for build 22**:

```bash
make asc-publish-testflight \
  ASC_EXPORT_OPTIONS=/absolute/path/to/.asc/ExportOptions.plist \
  ASC_TESTFLIGHT_GROUP="test group A" \
  ASC_TESTFLIGHT_FLAGS="--archive-xcodebuild-flag=CODE_SIGN_STYLE=Manual --archive-xcodebuild-flag=DEVELOPMENT_TEAM=L49MKXGVM4 --archive-xcodebuild-flag=CODE_SIGN_IDENTITY=Apple\\ Distribution --archive-xcodebuild-flag=PROVISIONING_PROFILE_SPECIFIER=Prism\\ marble\\ App\\ Store\\ HealthKit\\ 2026-06-18-2015 --notify"
```

The first automatic-signing attempt still tried the stale wildcard profile and failed:

```text
Provisioning profile "iOS Team Provisioning Profile: *" doesn't include the HealthKit capability.
```

Manual archive signing selected:

```text
Signing Identity: Apple Distribution: Lorenzo Quaid Sison (L49MKXGVM4)
Provisioning Profile: Prism marble App Store HealthKit 2026-06-18-2015
```

For the next TestFlight upload, either keep passing the manual signing flags above or pin
Release signing in `marble.xcodeproj/project.pbxproj` before archiving.

Because the Live Activity widget is now embedded, export signing also needs a provisioning
profile for `Prism.marble.MarbleWidgets`.

**Resolution used for build 23**:
- ASC Bundle ID `Prism.marble.MarbleWidgets` exists (`4L93LB6CMY`).
- ASC App Store profile `Prism marble MarbleWidgets App Store 2026-06-22 build 23`
  exists (`S668TD2D5G`) and is installed locally.
- `.asc/ExportOptions.plist` maps both `Prism.marble` and `Prism.marble.MarbleWidgets`.
- Release signing is pinned per target in `marble.xcodeproj/project.pbxproj`.

For the next upload after build 29, re-run `make asc-next-build`; it should report `30`
while build 29 remains the latest processed/uploaded 1.9 build.

Historical planned command, kept for context:

```bash
make asc-publish-testflight \
  ASC_EXPORT_OPTIONS=/absolute/path/to/.asc/ExportOptions.plist \
  ASC_TESTFLIGHT_GROUP="test group A" \
  ASC_TESTFLIGHT_FLAGS="--initial-build-number 20"
```

Notes:
- Before the 2026-06-21 upload, 1.9 had no uploaded builds, so the planned command used
  `--initial-build-number 20` to keep build numbers monotonic with the 1.8 train.
- "test group A" is the **internal** TestFlight group (no Beta App Review needed).
- Uploading 1.9 build 29 did **not** submit App Review.
- Build 29 TestFlight notes should use the phone checklist: Personal Records PR badges,
  "Personal best" add-set card, live "New PR!" cue + haptic, launch, rest timer Live
  Activity/widget, Apple Health import, Garmin-via-Health labeling, journal/split logging,
  Trends summary readability, and Strava hidden unless configured.

---

## Open release decisions
- Decide whether/when to submit the prepared 1.9 App Store review. TestFlight build 29 is
  ready, App Store version 1.9 is `READY_FOR_REVIEW`, and 1.8 is complete / ready for
  distribution. Do not submit 1.9 without explicit approval.
- **Strava posture for 1.9 (recommended): ship with Strava _unconfigured_.** Leave
  `StravaClientID` / `StravaClientSecret` / `StravaRedirectURI` out of the build so only the
  fully-verified **Apple Health + Garmin-via-Health** paths go out. Strava stays hidden
  unless keys are set, so this is the default — **no code change required**. Promote Strava
  in **1.10** after (a) a live OAuth round-trip with real keys and (b) a decision on the
  in-binary `client_secret` (see "Workout import"). Rationale: Strava is the only import path
  that is network-facing, ships a secret, and is unverified end-to-end.
- Keep 1.9 App Review submission as a separate explicit step. Before submitting, re-run:
  `make asc-review`, `make asc-validate`, and `asc review submit --help` with the current
  CLI.

After validation is clean, use the CLI's current submit path for the prepared 1.9
version. Re-check `asc review submit --help` first because the installed CLI can drift.

---

## Cleanup branches (local unless someone pushes them)

- `feature/progress-media-polish` — now **merged into 1.9** (commit `d986bce`); branch kept
  for reference.
- `feature/empire-gamification-refresh` — Empire gamification rework, **not** in 1.9.
- `backup/empire-gamification-dirty-20260617-105344` — full dirty empire worktree as one WIP
  commit; rescue/source branch only.
- `backup/main-stale-20260617-105344` — old stale local `main` before it was reset.

Do not delete/rewrite `backup/*` or `feature/*` branches without an explicit request.

---

## Release rules
- Do not cancel the current App Store review by default.
- `origin/main` is the canonical release baseline for **2.0 (36)**. The latest internal
  TestFlight build is **2.0 (36)**; App Store 2.0 remains `WAITING_FOR_REVIEW` and was not
  mutated.
- Do not bump builds, upload binaries, or submit for review without explicit user approval.
- Never reuse stale `.asc` archives/IPAs — `make asc-publish-*` regenerates them.
- Keep signing/export files and generated artifacts under ignored `.asc/`.

---

## Live state checks — RUN THESE before acting

```bash
git fetch --all --prune
git status --short --branch
git branch -vv
make asc-version      # expect MARKETING_VERSION 2.0
make asc-status
make asc-builds
make asc-next-build
```
