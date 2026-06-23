# Marble Release Handoff

**Last verified: 2026-06-22.** This file is the single source of truth for "where the
project is right now." App Store review and ASC build state can change outside git, so
always re-run the **Live state checks** (bottom of this file) before acting.

---

## TL;DR — what "up-to-date" means today (2026-06-22)

- **Code baseline:** `main` has been advanced to **1.9 (build 28)**, adding — on top of
  build 26's import hub, Live Activity, resilience/UX pass, and Trends redesign — a
  **performance + iOS 26 pass** (memoized Trends/Calendar/Journal derivations via a new
  `RenderMemo`, `@Observable` migration of every view model, `#Index` on
  `SupplementEntry.takenAt`), the **handwritten workout scan** feature
  (`marble/Features/Import/Scan/` — on-device Vision OCR + deterministic parser with an
  optional FoundationModels path, wired into the Import hub, `NSCameraUsageDescription`
  added), and an **iOS 26 polish** pass (finished the `@Observable` migration on
  `WorkoutScanViewModel`; SF Symbols Magic Replace on the Journal checklist + Import
  selection toggles). `origin/release/1.9` may still point at the older 1.9 build 20
  baseline unless it is explicitly updated.
- **Latest TestFlight build:** **1.9 (build 28)** was uploaded on 2026-06-23 from `main`
  (`CURRENT_PROJECT_VERSION` 28, build id `54c40cc8-2189-4bf5-bb57-4ec45092bcee`). App
  Store Connect reports processing `VALID`, and `test group A`
  (`514a95e2-28fc-436b-b624-9aaec2963adc`) has access to all builds. (Build 27,
  `b3e36109-7e4e-434e-877d-210219ef3893`, is also `VALID`.) **Note:** Apple's ASC
  *betaGroups* endpoint was intermittently erroring/timing out during the build-28 upload,
  so `make asc-publish-testflight` failed its upfront group precheck several times; the
  upload succeeded on retry against the pre-built IPA once the endpoint recovered.
- **Current working project version:** **1.9 (build 28)** on `main`;
  `MARKETING_VERSION = 1.9`, `CURRENT_PROJECT_VERSION = 28` in
  `marble.xcodeproj/project.pbxproj`.
- **Build/test health:** Xcode 26.5 / iOS 26.5 simulator is installed locally; the
  build 28 unit suite is green: `MarbleTests` (**151 unit tests, 0 failures**), which now
  includes `RenderMemoTests`, `TrendsDerivedDataTests`, and the scan feature's
  `HandwrittenWorkoutParser`/`WorkoutScanImporter`/`WorkoutScanViewModel` tests. (Snapshot
  baselines remain host-sensitive — e.g. `AddSet` mismatches on a non-recording host
  independent of these changes — so they were not used as a release gate.)
- **Live Activity wiring:** `MarbleWidgets` is now a real app-extension target embedded in
  the app, `NSSupportsLiveActivities = YES` is set on the app target, and
  `RestTimerAttributes.swift` is shared into the widget target.
- **Live App Store:** version **1.8 is WAITING_FOR_REVIEW** (build `17` submitted; builds
  `12`–`19` uploaded, all version 1.8). Uploading/distributing 1.9 build 26 did **not**
  change the in-flight App Store review.
- **App Store 1.9 gate:** `asc release stage --confirm` for 1.9 still fails while 1.8 is in review with
  Apple's hard error: "You cannot create a new version of the App in the current state."
  A 1.9 App Store version cannot be created while 1.8 remains in review.
- **Known 1.9 build ID:** `10ab692e-cffb-456b-b312-2c4dede738db` (version 1.9,
  build 26, `VALID`, uploaded 2026-06-22 18:56 PDT).
- **TestFlight:** **1.9 build 26 is valid and available to the internal all-builds group**.
  `buildBetaDetail` reports `internalBuildState = IN_BETA_TESTING`; internal group
  `test group A` (`514a95e2-28fc-436b-b624-9aaec2963adc`) has access to all builds and
  includes the installed Enzo tester record. External TestFlight remains not submitted.
- **Latest build 26 improvement:** the Trends top summary was redesigned into one compact
  stats surface with one-line labels, including "Supplements"; focused UI and snapshot
  coverage now guard against the wrap regression.

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

What's verified: app + 109 unit tests build green on Xcode 26.5 / iOS 26.5; Strava mapping,
sport-type classification, date parsing, HealthKit origin detection, Strava credential
resolution (env vars → Info.plist), import re-entry, failure handling, and duplicate-batch
skipping are unit-tested; `ImportFlowUITests` opens the import hub from the Journal and
checks Apple Health + the Garmin bridge render and dismiss.
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

For the next upload after build 26, re-run `make asc-next-build`; it should report `27`
while build 26 remains the latest processed/uploaded 1.9 build.

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
- Uploading 1.9 build 26 did **not** affect the in-flight 1.8 review.
- Build 26 TestFlight notes should use the phone checklist: launch,
  rest timer Live Activity/widget, Apple Health import, Garmin-via-Health labeling,
  journal/split logging, Trends summary readability, and Strava hidden unless configured.

---

## Open release decisions
- Decide whether/when to submit 1.9 for App Store review. TestFlight build 26 is ready,
  but the App Store version is still 1.8 and still waiting for review.
- **Strava posture for 1.9 (recommended): ship with Strava _unconfigured_.** Leave
  `StravaClientID` / `StravaClientSecret` / `StravaRedirectURI` out of the build so only the
  fully-verified **Apple Health + Garmin-via-Health** paths go out. Strava stays hidden
  unless keys are set, so this is the default — **no code change required**. Promote Strava
  in **1.10** after (a) a live OAuth round-trip with real keys and (b) a decision on the
  in-binary `client_secret` (see "Workout import"). Rationale: Strava is the only import path
  that is network-facing, ships a secret, and is unverified end-to-end.
- Leave the live 1.8 review to complete (default per rules below: do not cancel), or
  explicitly approve canceling submission `9be18cb3-defb-40f2-91eb-8148b2c09dfe` if 1.9
  must replace it immediately.
- 1.9 App Store submission still needs a 1.9 version record created in ASC. Apple blocks
  creating that record until the current 1.8 review leaves `WAITING_FOR_REVIEW` or is
  canceled.

### If explicitly approved to replace 1.8 with 1.9 now

This cancels the active 1.8 App Review submission, then creates/stages 1.9 with build 26.
Do not run the cancel command without explicit approval for submission
`9be18cb3-defb-40f2-91eb-8148b2c09dfe`.

```bash
asc submit cancel \
  --id "9be18cb3-defb-40f2-91eb-8148b2c09dfe" \
  --confirm \
  --output json --pretty

asc release stage \
  --app "6757725234" \
  --version "1.9" \
  --build "10ab692e-cffb-456b-b312-2c4dede738db" \
  --copy-metadata-from "1.8" \
  --confirm \
  --output json --pretty

asc validate \
  --app "6757725234" \
  --version "1.9" \
  --platform IOS \
  --output table
```

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
- `origin/main` is the canonical code baseline. As of 2026-06-22 it has been advanced to
  **1.9 (build 26)**. The latest internal TestFlight build is 1.9 (26), but the *live*
  App Store version is still 1.8.
- Do not bump builds, upload binaries, or submit for review without explicit user approval.
- Never reuse stale `.asc` archives/IPAs — `make asc-publish-*` regenerates them.
- Keep signing/export files and generated artifacts under ignored `.asc/`.

---

## Live state checks — RUN THESE before acting

```bash
git fetch --all --prune
git status --short --branch
git branch -vv
make asc-version      # expect MARKETING_VERSION 1.9
make asc-status
make asc-builds
make asc-next-build
```
