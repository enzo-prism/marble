# Marble Release Handoff

**Last verified: 2026-06-20.** This file is the single source of truth for "where the
project is right now." App Store review and ASC build state can change outside git, so
always re-run the **Live state checks** (bottom of this file) before acting.

---

## TL;DR — what "up-to-date" means today (2026-06-18)

- **Code baseline:** `origin/main` == `origin/release/1.9` == **1.9 (build 20)**. The
  pushed branches add the **workout import hub** (Apple Health bridge + Strava OAuth +
  Garmin via Health); see "What 1.9 contains" and `INTEGRATIONS.md`.
- **Unpushed local work (2026-06-20):** local `release/1.9` is **ahead of `origin`** with
  import polish (commit `07c546f`) — HealthKit average-HR enrichment, env-configurable
  Strava credentials (`STRAVA_CLIENT_ID`/…→ Info.plist), and import-hub test coverage —
  plus this doc refresh. No version/build bump; not yet pushed.
- **Project version:** **1.9 (build 20)** — `MARKETING_VERSION = 1.9`,
  `CURRENT_PROJECT_VERSION = 20` in `marble.xcodeproj/project.pbxproj`. (Build 20 is the
  intended source build; bump it deliberately only when prepping the next upload.)
- **Build/test health:** app builds clean on Xcode 26.5 / iOS 26.2 simulator; `make unit`
  is green (99 unit tests, 0 failures) at the tip of local `release/1.9`.
- **Live App Store:** version **1.8 is WAITING_FOR_REVIEW** (build `17` submitted; builds
  `12`–`19` uploaded, all version 1.8). **No 1.9 build has been uploaded.**
- **1.9 has NOT reached TestFlight or the App Store** — the upload is blocked on a pending
  Apple agreement + HealthKit signing. See the **BLOCKER** section.

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

What's verified: app + 99 unit tests build green on Xcode 26.5 / iOS 26.2; Strava mapping,
sport-type classification, date parsing, HealthKit origin detection, and Strava credential
resolution (env vars → Info.plist) are unit-tested; `ImportFlowUITests` opens the import hub
from the Journal and checks Apple Health + the Garmin bridge render and dismiss.
What needs a live pass: the Strava OAuth round-trip + real `athlete/activities` JSON (needs
real Strava API keys + account), Garmin→Health labeling against a real Garmin source, and
on-device HealthKit average-HR enrichment.

Note: Apple Health carries workout **summaries** (type, distance, duration, calories, HR —
Marble now reads average HR per workout and adds it to the imported note), not per-set
strength detail (weight×reps). Lift-level data would require Garmin's official Activity API
(FIT files) + a backend — out of scope for this no-backend build.

---

## ⚠️ BLOCKER: 1.9 (20) cannot be uploaded to TestFlight yet

The Release archive fails at **code signing**. Two issues, in order:

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

**Resolution once the PLA is accepted** (all doable via `asc`, no Xcode login needed):

```bash
# Confirm the block has cleared (this currently errors with the PLA message):
asc bundle-ids list --output table

# 1. Enable HealthKit on the Prism.marble App ID
asc bundle-ids capabilities ...        # add HEALTHKIT
# 2. Generate a new App Store distribution profile (now includes HealthKit)
asc profiles create ...
# 3. Install it and point .asc/ExportOptions.plist at the new profile name
asc profiles download ...
# 4. Archive with manual signing + upload as 1.9 build 20:
make asc-publish-testflight \
  ASC_EXPORT_OPTIONS=/absolute/path/to/.asc/ExportOptions.plist \
  ASC_TESTFLIGHT_GROUP="test group A" \
  ASC_TESTFLIGHT_FLAGS="--initial-build-number 20"
```

Notes:
- 1.9 has **no** uploaded builds, so `asc` would otherwise auto-number it `1`.
  `--initial-build-number 20` keeps build numbers monotonic with the 1.8 train (…19 → 20).
- "test group A" is the **internal** TestFlight group (no Beta App Review needed).
- Uploading a 1.9 build does **not** affect the in-flight 1.8 review.

---

## Open release decisions
- Ship 1.9 to TestFlight as build 20 once signing is unblocked (planned).
- Leave the live 1.8 review to complete (default per rules below: do not cancel).
- 1.9 App Store submission would need a 1.9 version record created in ASC (not required for
  TestFlight).

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
- `origin/main` is the canonical code baseline. As of 2026-06-18 it has been advanced to
  **1.9 (build 20)** — which is **unreleased**. The *live* App Store version is still 1.8.
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
