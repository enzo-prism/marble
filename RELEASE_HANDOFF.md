# Marble Release Handoff

**Last verified: 2026-07-22.** This file is the single source of truth for "where the
project is right now." App Store review and ASC build state can change outside git, so
always re-run the **Live state checks** (bottom of this file) before acting.

---

## ✅ RESOLVED — the App Group archiving blocker is gone (2026-07-21)

**The two portal steps are no longer required.** 2.2 originally shared the widget snapshot
through an App Group (`group.Prism.marble`), which failed `GatherProvisioningInputs` on both
targets:

```
error: Provisioning profile "Prism marble App Store HealthKit 2026-06-18-2015"
       doesn't support the group.Prism.marble App Group. (in target 'marble')
error: Provisioning profile "Prism marble MarbleWidgets App Store 2026-06-22 build 23"
       doesn't support the group.Prism.marble App Group. (in target 'MarbleWidgets')
```

That group could not be created programmatically — there is no App Groups resource in the
App Store Connect API (`GET /v1/appGroups` → 404 `NOT_FOUND`), `bundleIdCapabilities` has no
setting key for naming a group, and `asc web auth` needs an interactive Apple ID + 2FA.

**The snapshot now travels through a keychain access group instead.** Both existing App Store
profiles already grant a team-wide keychain wildcard — decoded from the live API:

- `Prism marble App Store HealthKit 2026-06-18-2015` → `keychain-access-groups = ['L49MKXGVM4.*', 'com.apple.token']`
- `Prism marble MarbleWidgets App Store 2026-06-22 build 23` → `keychain-access-groups = ['L49MKXGVM4.*', 'com.apple.token']`

So the group `L49MKXGVM4.Prism.marble.shared` is already covered: **no portal capability, no
profile regeneration, no change to the two pinned `PROVISIONING_PROFILE_SPECIFIER` names.**

What changed in the repo:

- `marble.entitlements` — dropped `com.apple.security.application-groups`; HealthKit kept;
  `keychain-access-groups` is a **two-element array whose order is load-bearing**:
  ```xml
  <array>
      <string>$(AppIdentifierPrefix)Prism.marble</string>
      <string>$(AppIdentifierPrefix)Prism.marble.shared</string>
  </array>
  ```
  ⚠️ The **first** entry is the default access group for any keychain write that does not
  name one. `KeychainTokenStore` (Strava OAuth) does not name one, so `Prism.marble` must
  stay first — reordering the array or dropping the first entry silently relocates existing
  users' Strava tokens and logs them out. The `.shared` group carries only the widget
  snapshot, which always names its group explicitly.
- `MarbleWidgets/MarbleWidgets.entitlements` — `keychain-access-groups` is its only content,
  and there it *is* a single entry: `$(AppIdentifierPrefix)Prism.marble.shared`.
- `marble/Shared/SharedDefaults.swift` — `SharedDefaults.suite` is `UserDefaults.standard`
  again, plus a new `SharedKeychain` type that owns the snapshot item
  (`kSecClassGenericPassword`, service `marble.widget.weeklyGoalSnapshot`, accessible
  `AfterFirstUnlockThisDeviceOnly` so Lock Screen families still render).
- `marble/Shared/WeeklyGoalWidgetState.swift` — `publish()` / `loadPublished()` replace
  `save(to:)` / `load(from:)`; staleness and placeholder behaviour are unchanged.

The preferences that used to live in the suite (weekly target, reminder flag, weight unit,
onboarding flag) never needed cross-process sharing: the widget reads only the snapshot, and
the weekly target is baked into that snapshot by `WeeklyGoalWidgetPublisher`. Do not restore
the App Group without a new requirement the keychain snapshot genuinely cannot satisfy.

> ✅ **Verified end to end 2026-07-22: 2.2 (build 42) is on TestFlight, `VALID` and
> `IN_BETA_TESTING`** (buildId `a9acfd24-fae2-4602-b75c-e0c47c036722`, uploaded 15:25).
> `make asc-archive` → **ARCHIVE SUCCEEDED** with the pinned profiles untouched.

### The release sequence used for builds 41 and 42

Use the **existing** `.asc/ExportOptions.plist` — it already maps both bundle IDs to the two
pinned profiles and sets `signingCertificate = Apple Distribution`. A bare export options file
without a `provisioningProfiles` map fails with *"requires a provisioning profile with the
HealthKit feature"*, because manual signing will not infer profiles from the archive.

```sh
make asc-archive
ASC_EXPORT_OPTIONS=$PWD/.asc/ExportOptions.plist make asc-export
asc publish testflight --ipa "$PWD/.asc/artifacts/marble.ipa" --app 6757725234 --group "test group A" --wait
```

Shipped entitlements, read back off the signed archive with `codesign -d --entitlements`:
`marble.app` → `['L49MKXGVM4.Prism.marble', 'L49MKXGVM4.Prism.marble.shared']`,
`MarbleWidgets.appex` → `['L49MKXGVM4.Prism.marble.shared']`, no app-groups key anywhere.

On the **simulator**, keychain access groups are not enforced and `SecItem*` can return
`errSecMissingEntitlement`; every call degrades to "no snapshot", so the widget shows its
neutral "Open Marble" card rather than crashing. CI and `make unit` are unaffected — no unit
test touches the real keychain.

## Release state (2026-07-22)

- **2.1 (build 40)** — **LIVE on the App Store**, released 2026-07-21 via
  `asc versions release --version-id 59f2e4c7-1c4b-49b3-a5d3-265ca6da74b1 --confirm`;
  state moved `PENDING_DEVELOPER_RELEASE` → `READY_FOR_SALE` in the API. It carries the
  sessions / sprint-prescription / Exercise-Library / JSON-backup work from builds 35-39.
  **No phased release was configured** (`appStoreVersionPhasedRelease` was null), so it went
  to 100% of users at once — worth creating one *before* releasing next time, since 2.1 was
  the first production build to run the V2→V4 migrations.
- **2.2 (build 42)** — **on TestFlight, `VALID` and `IN_BETA_TESTING`** (buildId
  `a9acfd24-fae2-4602-b75c-e0c47c036722`, uploaded 2026-07-22). The internal group
  `test group A` (`514a95e2-28fc-436b-b624-9aaec2963adc`) has access to all builds.
  **Not submitted to App Review.** Daily Highlights, the single-timer Live Activity fix,
  and Log Again personal-best context are included alongside widgets, Control Center,
  onboarding, Settings, Siri/Spotlight intents, bodyweight + schema **V5**. Not blocked on
  portal work — see the resolved section above. Several surfaces remain incomplete; see
  **Known gaps / next up** in `ROADMAP.md` before writing release notes for it.
- **2.0 (build 34)** — superseded by 2.1. Its review is closed; nothing about it is live
  state any more.
- **Working project version: `MARKETING_VERSION = 2.2`, `CURRENT_PROJECT_VERSION = 42`.**
  The next upload must use `make asc-next-build` (currently expect **43**).

---

## Build history (what each build carried)

- **Build 42:** Daily Highlights adds a local-only, configurable end-of-day celebration in
  Trends with truthful lift/run/PR derivation and a 1080 × 1350 ShareLink export. Rest timer
  reconciliation enforces at most one Live Activity across relaunches and rapid logs. Log
  Again adds subtle best-weight, matched-distance run-time, or bodyweight-rep context.
  Focused logic, performance, snapshots, UI flow, and light/dark accessibility audits pass.
- **Build 39:** Journal and Quick Log show every sprint rep's saved exact/ranged target
  with accessible green check / red x / neutral unscored feedback. Set Details compares the
  recorded result with the frozen per-rep goal and explains the outcome. Additive
  `MarbleSchemaV4`, legacy backfill provenance, backup/restore validation, duplicate/undo/
  intent support, and migration coverage preserve history when an exercise goal changes.
  Commit `3e6d4b6`. Shipped to users in 2.1.
- **Build 38:** the Exercise Library and editor are redesigned end to end. Search, category
  filters, favorites, stable compact summaries, create-from-search, and first-library empty
  states make discovery clear. Explicit tracking types reveal only relevant fields; edits
  remain drafts until Save; validation, dirty-dismissal protection, logged/planned-workout
  impact warnings, and final delete dependency checks protect user data. Sprint is a direct
  type with distance, repeats, exact/ranged target time, and one recovery control.
- **Build 37:** reusable sprint prescriptions add fixed distance, 1–50 repeats,
  an exact or ranged whole-second target time, prescribed recovery, per-rep RPE/rest logging,
  live goal feedback, and summaries across exercise selection and workout planning. The new
  `SprintPrescription` model is additive `MarbleSchemaV3`; backup/restore supports it while
  retaining compatibility with older JSON.
- **Build 36** fixed the build-35 launch crash for stores created
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
- **Why the 2.1 train existed (historical, resolved):** App Store 2.0 was attached to build
  34 and its `whatsNew` described exactly that build's Trends coaching layer, so builds 35–39
  could not ship under the 2.0 string. They shipped as **2.1**, which released 2026-07-21.
  The question is closed; the current train is 2.2.
- **Build/test health (2026-07-22):** Xcode 26.6 / iOS 26.5 simulator. The build-42 focused
  logic, performance, snapshot, UI, and light/dark accessibility gates **passed**. The prior
  full-suite baseline remains: `make unit` **passed**
  and `make audit` **passed**. `make ui` was **39 passed / 1 failed**; the failure,
  `AppStoreScreenshotUITests.test07TrainingCalendar`, is **proven pre-existing** — it fails
  identically on a clean `origin/main` worktree on this host (`UICalendarView` render timing)
  and is not a release gate. Suite sizes counted from source: `Tests/Unit/` = 49 files / 51
  classes / **453 test methods**; `Tests/UI/` = 17 files / **49 test methods**. Do not
  hand-edit these numbers forward — see `TESTING.md`. Snapshot baselines remain
  host-sensitive; the unchanged Journal surface still produces the known local mismatch.
- **Live Activity wiring:** `MarbleWidgets` is now a real app-extension target embedded in
  the app, `NSSupportsLiveActivities = YES` is set on the app target, and
  `RestTimerAttributes.swift` is shared into the widget target.

---

## What 1.9 contained (vs shipped 1.8) — historical

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

What's verified: the app and the full unit suite build green on Xcode 26.5 / iOS 26.5 (see
`TESTING.md` for current counts); Strava mapping,
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

For the next upload, re-run `make asc-next-build`; with build 42 the latest processed upload
it should report **43**. Never guess a build number locally.

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

**The only live decision: when to submit 2.2 to App Review.** Build 42 is on TestFlight,
`VALID`, and `IN_BETA_TESTING`; nothing is submitted. Before submitting, resolve these:

- **Do the device pass first.** Most of 2.2 — widgets, Live Activity buttons, the Control
  Center control, Siri, Spotlight, and the keychain snapshot itself — is untestable on the
  simulator. Walk the 2.2 checklist in `TESTING.md` on a real phone.
- **Decide what to do about the known gaps** (`ROADMAP.md` → Known gaps / next up). Some are
  fine to ship (TipKit inert, no bodyweight edit); others shape the release notes. In
  particular: do **not** advertise Siri set-logging alongside the widget, because a
  Siri-logged set does not refresh the widget or the weekly-goal reminder. Either fix that or
  keep the notes to widgets + onboarding.
- **Configure a phased release before releasing this time.** 2.1 shipped to 100% at once
  because `appStoreVersionPhasedRelease` was null. 2.2 carries the V5 migration and the first
  widget surface — both are exactly what phased rollout exists for.
- **Strava posture is unchanged: ship with Strava _unconfigured_.** Leave
  `StravaClientID` / `StravaClientSecret` / `StravaRedirectURI` out of the build so only the
  fully-verified **Apple Health + Garmin-via-Health** paths go out. Strava stays hidden
  unless keys are set, so this is the default — **no code change required**. Promote it only
  after (a) a live OAuth round-trip with real keys and (b) a decision on the in-binary
  `client_secret` (see "Workout import"). Rationale: Strava is the only import path that is
  network-facing, ships a secret, and is unverified end-to-end.
- Keep App Review submission a separate, explicitly approved step. Before submitting, re-run
  `make asc-review`, `make asc-validate`, and `asc review submit --help` — the installed CLI
  drifts.

To release an **approved** version (the step that was missing from the docs until 2.1):

```sh
asc versions release --version-id <appStoreVersion id> --confirm
```

That is what moved 2.1 from `PENDING_DEVELOPER_RELEASE` to `READY_FOR_SALE` in the API.

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
- Do not cancel an in-flight App Store review by default.
- `origin/main` is the canonical release baseline, now on the **2.2** train. The latest
  TestFlight build is **2.2 (42)**, not submitted for review. Released to users:
  **2.1 (build 40)**.
- **Never delete a branch without pushing it first.** Every local-only branch was archived to
  `origin` on 2026-07-14. Note `feature/empire-gamification-refresh` is the **only** ref that
  holds the Empire source — the branches named `empire-gamification` and
  `backup/empire-gamification-dirty-*` contain **zero** Empire files (commit `4e68df5`
  deleted the feature). A cleanup that keeps the "backup" and drops the "refresh" branch
  destroys the feature while appearing to preserve it.
- Do not bump builds, upload binaries, or submit for review without explicit user approval.
- Never reuse stale `.asc` archives/IPAs — `make asc-publish-*` regenerates them.
- Keep generated artifacts under `.asc/`, which is ignored — **except**
  `.asc/ExportOptions.plist` and `.asc/UploadExportOptions.plist`, which are deliberately
  tracked (`.gitignore` ignores `.asc/*` and negates those two). They carry the
  `provisioningProfiles` map without which export fails on a fresh clone.

---

## Live state checks — RUN THESE before acting

```bash
git fetch --all --prune
git status --short --branch
git branch -vv
make asc-version      # expect MARKETING_VERSION 2.2, CURRENT_PROJECT_VERSION 41
make asc-status
make asc-builds
make asc-next-build   # expect 42
```
