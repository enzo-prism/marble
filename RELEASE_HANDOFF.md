# Marble Release Handoff

**Live GitHub, TestFlight, and App Review state verified: 2026-08-30.**
External state can change outside git, so always re-run the **Live state checks** before acting.

---

## Current release snapshot

- **Current candidate:** exact GitHub `main` source
  `cbeb6d2f7131c14ab1327ff07e703f812a6fc754` is uploaded as 2.4 build 63.

- **Public App Store (US storefront verified 2026-08-24):** 2.3 build 56 is live. Its shipped application source is PR #19
  merge `c0cef9e2d19ee8589585bdfe082ab4af8cdec7bb` (Train / Log / Progress IA).
- **App identity:** App Store Connect app `6757725234`, bundle ID `Prism.marble`.
- **Canonical release source:** `origin/main`
  `cbeb6d2f7131c14ab1327ff07e703f812a6fc754` is the exact source uploaded as
  2.4 build 63. PR CI `33344445695` and exact-main CI `33350786978` passed.
- **TestFlight:** 2.4 build 63 (`15fc9492-9fa6-487c-aa8c-271f5aefc867`) is
  `VALID` and `IN_BETA_TESTING` in internal **test group A**. Its external state
  is `READY_FOR_BETA_SUBMISSION`; external beta was not requested. TestFlight workflow
  `33351130547` archived, signed, exported, uploaded, and processed the exact main SHA.
  Strict validation is 0 errors, 0 warnings, 0 blockers, and 0 informational findings.
- **App Review:** 2.4 build 61 is `WAITING_FOR_REVIEW`; submission
  `ce4a0d8a-f5ea-4d1e-9463-03937e467343` was created 2026-08-24 at
  13:16:27 PDT. The superseded build 60 submission
  `5bd874ad-3619-4521-9231-fa45ee18a4b0` was canceled and is `COMPLETE`.
- **Release boundary:** 2.4 uses manual release. Do not cancel the submission,
  upload or attach a replacement, or issue the final public release without the
  required explicit approval and a fresh review-state check. Public App Store 2.3
  remains live; `WAITING_FOR_REVIEW` is not production release.

---

## 2.4 build 63 — current internal TestFlight candidate

**Exact uploaded GitHub `main` source:**
`cbeb6d2f7131c14ab1327ff07e703f812a6fc754`

**App Store Connect build ID / state:**
`15fc9492-9fa6-487c-aa8c-271f5aefc867` — `VALID`, internal
`IN_BETA_TESTING`, external `READY_FOR_BETA_SUBMISSION`

**GitHub evidence:** PR #31 candidate `d14350a4e8b0e5bcd3b4e26bfd24d4cae888df7f`
passed CI `33344445695`; byte-identical merge source `cbeb6d2` passed exact-main
CI `33350786978` with 824 tests executed, 1 intentional skip, and 0 failures.
TestFlight workflow `33351130547` passed.

**TestFlight validation:** 0 errors, 0 warnings, 0 blockers, 0 informational findings.
The en-US What to Test note is attached through localization
`72d21275-c2ea-4d9a-b0c3-cf39f21ec4b5`. Internal **test group A** receives all builds.

**App Review boundary:** 2.4 build 61 remains attached to submission
`ce4a0d8a-f5ea-4d1e-9463-03937e467343`, which is still `WAITING_FOR_REVIEW`
under manual release. Build 63 was not attached, external Beta App Review was not
triggered, and no public release action was taken.

- Keeps the build-62 whitespace-first Progress overview while deferring charts,
  records, reports, body metrics, and supplement analytics until Details opens.
- Debounces live workout preview parsing off the main actor, cooperatively cancels
  stale work, and keeps stable row identity during rapid typing.
- Prevents relative-date prose from creating phantom workouts and keeps unreadable
  multi-workout blocks visible and blocking until reviewed, avoiding silent loss.
- Uses context-save invalidation so deleting older history refreshes Progress caches.
- Local final snapshot/UI/accessibility/migration evidence remains incomplete after
  actual host `ENOSPC`; do not use this internal build as public-release evidence.
  Canonical acceptance copy is `AppStore/testflight/2.4-build-63.md`.

---

## 2.4 build 62 — prior internal TestFlight candidate

**Exact uploaded GitHub `main` source:**
`bfcb9a5b3924e7e4e433c8d9f04c8432d71f9bbe`

**App Store Connect build ID / state:**
`c7bf290e-388d-4761-b7a0-8c1987ecd2d7` — `VALID`, internal
`IN_BETA_TESTING`, external `READY_FOR_BETA_SUBMISSION`

**GitHub evidence:** exact-main CI `33100185442` passed; TestFlight workflow
`33100988181` passed from tag
`publish/testflight/20260827T175640Z-bfcb9a5`.

**TestFlight validation:** 0 errors, 0 warnings, 0 blockers, 0 informational findings.
The en-US What to Test note is attached through localization
`24af7075-656c-4f6a-b3d6-6c3bac08abb4`. Internal **test group A** receives all builds.

**App Review boundary:** the existing 2.4 build 61 submission
`ce4a0d8a-f5ea-4d1e-9463-03937e467343` remains `WAITING_FOR_REVIEW` under manual
release. Build 62 was not attached to App Review, external Beta App Review was not
triggered, and no public release action was taken.

- Replaces the dense default Progress page with a quiet weekly status and a single
  Details action, preserving generous whitespace across iPhone and iPad.
- Organizes weekly goals, daily highlights, training analytics, reports, body metrics,
  habits, supplements, and milestones in the detailed view.
- Adds focused Progress navigation, accessibility, smoke, screenshot, and snapshot
  coverage across light/dark, Larger Text, iPhone SE, regular iPhone, and iPad layouts.
- Automated evidence before release: 812 unit tests passed with 1 intentional skip;
  all 8 focused Progress snapshots, 4 Progress smoke UI tests, accessibility execution,
  and 10 App Store screenshot flows passed. No SwiftData schema change (still V6).
- Canonical internal acceptance copy is `AppStore/testflight/2.4-build-62.md`.

---

## 2.4 build 61 — current App Review candidate

**Exact uploaded GitHub `main` source:**
`9e8346f6cad4683991a78fbaf223baaf01e9f068`

**App Store Connect build ID / state:**
`bbea8736-b964-4175-8c9c-b140ebcea4c1` — `VALID`, internal
`IN_BETA_TESTING`, external `READY_FOR_BETA_SUBMISSION`

**GitHub evidence:** exact-main CI `32771324947` passed; TestFlight workflow
`32772039189` passed.

**TestFlight validation:** 0 errors, 0 warnings, 0 blockers, 0 informational findings.
The en-US What to Test note is attached. Internal **test group A** receives all builds.

**Current App Review:** submission `ce4a0d8a-f5ea-4d1e-9463-03937e467343` is
`WAITING_FOR_REVIEW` with build 61 attached. Release type is `MANUAL`.

- Refines the AI-first Add task hierarchy while preserving the persistent Start/open workout
  action, deterministic parser fallback, review-before-save, draft recovery, and exact exercise
  identity.
- Uses adaptive monochrome surfaces for light, dark, Increased Contrast, and Reduced
  Transparency appearances; Progress series and status cues no longer depend on color alone.
- Simplifies Calendar and Add Set actions, restores 44-point targets, and keeps controls usable
  at maximum Larger Text.
- Adds iPad portrait and landscape snapshots for Add, Calendar, and populated Progress. Those
  baselines exposed and fixed reused SwiftUI grid identities that hid the first calendar week
  in landscape.
- Adds compact-width iPhone landscape Calendar snapshots and caps height to the readable grid
  width, preventing a wide 852-point proposal from creating a roughly 920-point month view.
- Fixes the adaptive-color actor-isolation runtime trap and the snapshot record path that could
  accept a run without overwriting stale PNGs.
- No SwiftData schema change (still V6). Canonical internal acceptance copy is
  `AppStore/testflight/2.4-build-61.md`.

Replacement completed: build 60 submission `5bd874ad-3619-4521-9231-fa45ee18a4b0`
is `COMPLETE`; build 61 is attached and submitted. Release remains manual; do not issue a
public release command without a separate approval and fresh review-state check.

---

## 2.4 build 60 — fixed internal TestFlight replacement candidate

**Exact uploaded GitHub `main` source:**
`b287d7238494799818db5947524a5cc05b9c8a9c`

**App Store Connect build ID / state:**
`ef651ca3-451f-468b-903a-1239bcf6dc39` — `VALID`, internal
`IN_BETA_TESTING`, external `READY_FOR_BETA_SUBMISSION`

**GitHub evidence:** exact-main CI `32704746418` passed; TestFlight workflow
`32705379775` passed.

**TestFlight validation:** 0 errors, 0 warnings, 0 blockers, 0 informational
findings. Internal **test group A** has all-build access.

**Historical App Review checkpoint:** build 60 submission
`5bd874ad-3619-4521-9231-fa45ee18a4b0` and the earlier build 59 submission
`2233970e-2288-4bf4-a52f-8bc5c47f639a` are both canceled / `COMPLETE` after later
replacements. Neither was publicly released.

- Restores a persistent **Start or open workout** toolbar action on the default
  Add tab. It opens the workout sheet even when no session exists, so starting a
  workout no longer depends on an active-session accessory already being present.
  Existing workout deep links use the same reachable surface.
- PR celebration resolves the exact library exercise UUID approved during review.
  An explicit create-new exercise stays independent even when another exercise has
  the same name, preventing a false personal-record celebration against unrelated
  history.
- Regression coverage and local verification are named in `TESTING.md`.
  Exact-main CI and exact-binary archive/sign/export/upload/processing passed.
  Physical-device acceptance and soak remain separate. No SwiftData schema change
  (still V6).
- `AppStore/testflight/2.4-build-60.md` is the canonical internal test plan.

Build 60 promotion to GitHub `main`, internal TestFlight, and App Review completed.
The old build 59 submission was canceled; build 60 was attached, revalidated, and
submitted under a new review submission. Never describe build 60 as public until
review approval, a later manual release, and storefront readback prove it.

---

## 2.4 AI-first Add — build 59 promotion

**Application feature source:** `c8200e219b47e44d26720d164cd568f395392f6f`

**Exact uploaded main SHA:** `eead033f7d454180c61f1e49d7d66a233927c3c8`

**App Store Connect build ID / state:**
`3235fff4-515a-40db-9239-41338ec34ead` — `VALID`, internal
`IN_BETA_TESTING`, external `READY_FOR_BETA_SUBMISSION`

**GitHub evidence:** PR #27 merge `eead033`; exact-main CI run `32700219443`
passed; TestFlight run `32700683071` passed in 5m48s.

**Historical App Review disposition:** submission
`2233970e-2288-4bf4-a52f-8bc5c47f639a` was canceled and is `COMPLETE`; build 60
now owns the active 2.4 review submission. Release type remains manual.

- Add replaces Train as the default tab: **Add / Log / Progress**.
- Paste/type supports prose, notation, multi-day Notes, TXT, Hevy CSV, and Strong
  CSV. Apple Intelligence structures prose on supported devices; deterministic
  parsing is the notation fast path and fallback.
- Structured review, exact exercise identity, explicit create-new behavior,
  unresolved-line retry, draft recovery, Shortcut handoff, and active-workout
  accessory behavior are covered in `AppStore/testflight/2.4-build-59.md`.
- Automated evidence: 808 unit methods; all 49 snapshot methods passed earlier in
  the feature branch, with all 5 directly affected methods refreshed and replayed;
  55 unaffected UI flows passed plus the corrected Accessibility XXXL Add case;
  final accessibility gate 5 passed / 1 runtime-unsupported skip / 0 failures.
- No SwiftData schema change (still V6).

Promotion completed 2026-08-24: docs and application source merged to `main`,
exact-main CI passed, that SHA was uploaded as build 59, ASC processing reached
`VALID`, the en-US TestFlight note was applied, canonical metadata was staged,
build 59 was attached to App Store version 2.4, strict readiness passed with no
blockers, and 2.4 was submitted for review. Public release remains a separate
post-approval action.

---

## 2.4 Bulk import honesty — TestFlight VALID (build 57)

**On `main` (PR #24 merge `df05585`, 2026-08-20).** `MARKETING_VERSION = 2.4`,
`CURRENT_PROJECT_VERSION = 57`. Apple closed the **2.3** train: uploading another
2.3 IPA fails `ITMS-90062` / `ITMS-90186`. Build 57 is the first 2.4 TestFlight.

**2.4 build 57 is `VALID`** (2026-08-20, buildId
`a8f9716a-5b39-4013-a795-181344ff54a6`, Actions run `32335409907`, tag
`publish/testflight/20260820T052323Z-df05585`). Internal **test group A**
auto-receives; do not assign the build to it.

**2.3 has already been publicly released.** Its binary is Train/Log/Progress IA, not
this import wave; do not try to release it again or treat it as proof that 2.4 shipped.
**Do not submit 2.4 App Review** unless the user explicitly asks. The staged 2.4
draft is intentionally stopped at `PREPARE_FOR_SUBMISSION`.

What this wave is (on top of PR #23):

- Hevy `set_index` reset → two exercise blocks (same name, original order).
- EU/Android Strong CSV: `;` delimiter, `Weight (kg)`, decimal commas.
- Strong `Distance` is km or mi from preferred weight unit, not metres.
- `superset_id` tagged onto set notes. Strong `(Barbell)` suffixes stripped
  after grouping, so barbell and dumbbell variants stay two exercises.
- Typed/scanned `RPE 8` / `rpe9` / `@RPE 8`; `Day 1` / `Session 2` paste splits
  and those labels become titles, not phantom exercises.
- Hevy `failure` rows with 0 reps (or no load) stay in the draft.
- Weak library matches default to **create new** (suggestions remain).
- Scan N==1 uses `ExerciseMatcher`; review shows rest / RPE / notes and
  discloses that blank RPE saves as 8. Scan review can reorder exercises.
- Scan re-import copy matches skip behavior. Journal origin **Paste or Type**.
- No schema change (still V6).

CI: `CI / unit-tests` green on merge SHA (`800` tests, 1 skipped, 0 failures;
run `32334810598`).

```bash
make cloud-preflight
make cloud-status
# already uploaded: do not re-run make cloud-testflight unless replacing the binary
# do not: make cloud-appstore-release VERSION=2.3
# do not: make cloud-appstore-submit VERSION=2.4   unless explicitly asked
```

---

## 2.3 Bulk import fidelity — on `main` (PR #23 merge `cbd5116`, 2026-08-20)

**On `main` historically.** Marketing version moved **2.3 → 2.4** after Apple
rejected 2.3/57 (`ITMS-90186`). **2.3 build 56 is now live on the App Store**;
that binary is the Train/Log/Progress IA, **not** the CSV fidelity / honesty waves.

What PR #23 added:

- Hevy CSV: skip warmup sets, map RPE → difficulty, compose notes,
  keep session `endedAt` / ledger `durationSeconds` from `end_time` or Strong `Duration`.
- Multi-page scan OCR; N>1 dated sessions hand off to **Paste or Type**.
- Batch review shows library / new / weak matches; unique new-exercise counts.
- File picker is `.txt` / `.csv` only (no JSON workout schema).
- No schema change (still V6).

CI: `CI / unit-tests` green on merge SHA (`774` tests, 1 skipped, 0 failures;
run `32330557151`).

---

## 2.3 Train / Log / Progress IA — on `main` (PR #19 merge `c0cef9e`, 2026-08-16)

**On `main`.** That wave kept marketing version **2.3**. Working tree is now
**2.4** / build 57 because Apple closed the 2.3 train. This IA first shipped as **2.3
build 56 `VALID`** (2026-08-16, buildId `9d4830c6-e713-40c1-a60a-33c13951a9ce`).
The App Store 2.3 version is now public. It does not include the later bulk-import
fidelity / honesty waves, which remain on the 2.4 train.

What this wave is:

- Tab bar: **Train / Log / Progress**. Calendar and Supplements are Log modes
  (`LogModePicker`, identifiers `Tab.Calendar` / `Tab.Supplements`). Default tab is Train.
- Planned row with history: `SetLogging.repeatLatest` (no sheet). Log Set sheet is
  `.medium` + `.large` and morphs from the primary `+`.
- Session tab-bar accessory when a workout is live; rest pill still wins.
- Lock Screen rectangular widget copy drops the streak at `streakWeeks >= 10`.
- No schema change (still V6). No App Store review submit in this wave.

**Historical note:** this section originally warned against releasing 2.2 as a stand-in.
The decision is closed: the IA shipped publicly as 2.3 build 56.

**Upload from a Cloud Agent** (Linux cannot `xcodebuild`; see `CLOUD_RELEASE.md`):

```bash
make cloud-preflight
make cloud-testflight
# do not submit or release 2.3 unless explicitly asked — that binary is IA-only
# relative to later import waves. Working upload is 2.4 / 57.
```

That dispatches GitHub Actions `macos-26` for archive/export/upload. It needs the
one-time GitHub Actions secrets from `scripts/bootstrap_github_release_secrets.sh`.

**Upload from a Mac with Xcode 26 + iOS 26 runtime + ASC keys:**

```bash
git fetch origin && git checkout main && git pull
make asc-auth && make asc-doctor && make asc-version && make asc-next-build
make asc-archive
ASC_EXPORT_OPTIONS=$PWD/.asc/ExportOptions.plist make asc-export
# then asc builds upload of .asc/artifacts/marble.ipa — staged foreground, do not
# background make asc-publish-testflight. "test group A" auto-receives.
```

After Apple processing (`VALID`), update this file with the buildId.

## Historical build/release chronology (not current state)

### ✅ 2.3 (build 55) VALID on TestFlight (2026-08-05)

**2.3 build 55** (buildId `d4d59691-076e-4663-9084-44475372af1b`, uploaded 2026-08-05,
`VALID`) is the first build on the **2.3 train** and the first TestFlight build carrying
BOTH Typed Workout waves below (the app-export paste wave merged 2026-08-05 morning but
its publish never landed — build 54 was still the latest processed build). Staged
foreground publish (asc-archive → asc-export → builds upload); "test group A"
auto-receives. **2.2 is `READY_FOR_DISTRIBUTION` (approved, manual release pending) —
that closed the 2.2 train: the first build-55 upload failed processing with
ITMS-90186/90062 (new builds must carry a higher version string than the approved one),
so `MARKETING_VERSION` moved 2.2 → 2.3 and `ASC_APPSTORE_VERSION` follows. No schema
change since V6.**

## `main` wave after build 54 (2026-08-05) — Typed Workout order/progress/delight

**On `main` (merge `a4b9451`, PR #16, commit `afc2498`), first shipped in build 55.**
From direct user feedback on the Typed Workout feature:

- **Saved order matches review order** — imported sets all shared one `performedAt`
  and the journal sorts only by it, so tied rows came back scrambled.
  `WorkoutScanImporter` now spaces sets by a millisecond ordinal cascade (first
  reviewed set = newest), so the newest-first journal reproduces the exact review
  order. The cascade steps forward from the effective date (a date-only midnight pick
  never spills into the previous day) and explicit per-set times still win. Scan
  imports gain the same ordering.
- **Staged progress for preview generation** — `WorkoutScanParsing` gained a defaulted
  staged-parse variant reporting `WorkoutParseStage` (notation pass → each Apple
  Intelligence pass → finalizing); the processing step is a determinate bar with stage
  label + percent, timer-eased toward the current stage anchor.
- **UX accelerators + delight** — system `PasteButton` in the input step (no
  paste-permission prompt, no programmatic clipboard reads); exercise reorder controls
  in review (draft order is import order, so they fix saved order too); the imported
  screen shows total volume (Σ weight × reps in the user's preferred unit) and
  celebrates beaten PRs via `PersonalRecords.projectedBadge`, computed pre-import.
- **Parser coverage** — rep ladders/pyramids ("225x5/3/1", "5/3/1 @ 225", "3x10-8-6" →
  one set per rung); tempo notation stripped as noise (fixes the corruption where
  "3x5 tempo 31x1" became sets of 3 lb and 31 lb); round/circuit headers ("3 rounds:",
  "Circuit 1", "three rounds:") consumed as structure, counted headers multiplying the
  following movements' sets. Prose-tier corpus boundary unchanged.

No schema change (still V6). Unit suite **706 tests** green.

## `main` wave after build 54 (2026-08-05) — app-export paste + zero silent loss

**On `main` (merge `2dfd2d8`, PR #15, commit `622bb25`), first shipped in build 55.**
Hevy ("Set 1: 60 kg x 10") and Strong exports paste correctly with weight and reps;
Notes-style blocks (name line, then "185 x 8" per set) import; headers like
"Exercise: Bench Press (Barbell)" clean up. Zero silent loss: every line the parser
can't read is surfaced in review with inline edit + re-parse; "1,025 lb" no longer
becomes 1 lb; AMRAP/failure keep their set count; EMOM expands; prose is flagged for
review instead of mangled; "yesterday" sets the date; emoji/unspaced names parse
clean. The input step marks each line recognized/not per keystroke (live deterministic
feedback), and unitless weights default to the user's preferredWeightUnit instead of
hardcoded lb. 682 unit tests green at merge.

## ✅ 2.2 (build 51) VALID on TestFlight (2026-07-29)

**2.2 build 51** (buildId `23d8691a-09cf-455a-b773-6fce32498ed3`, uploaded 2026-07-29,
`VALID`, `internalBuildState: IN_BETA_TESTING`) is the first build containing the
**free-text workout import wave** (see below) on top of everything in build 50. Published
in stages — `make asc-archive` → `make asc-export` → `asc builds upload` — because the
one-shot `make asc-publish-testflight` was killed when backgrounded (the known harness
quirk); the staged foreground path works. The pinned `.asc/ExportOptions.plist` profiles
still sign fine. "test group A" has `hasAccessToAllBuilds: true`, so internal testers
receive builds automatically — manual group assignment is unnecessary and the API
rejects it ("Builds cannot be assigned to this internal group"). **2.2 (build 48)
remains the build in App Review.** No schema change since V6.

## ✅ 2.2 (build 50) VALID on TestFlight (2026-07-28)

Both waves below shipped to TestFlight as **2.2 build 50** (buildId
`e3bb38dd-9719-4268-8587-59c92f53f3dc`, uploaded 2026-07-28 17:40 PDT, `VALID`,
internal group "test group A" receives it automatically). Published via
`make asc-publish-testflight` with `.asc/ExportOptions.plist` (the pinned build-48
profiles still sign fine). **2.2 (build 48) remains the build in App Review — build 50
does not replace it.** First TestFlight build containing schema V6; the
migration-release gate passed before upload.

## `main` waves in build 50 (2026-07-28)

`main` carries two waves, both in build 50; build 49 on TestFlight has neither:

1. **The sprint V6 feature wave** (commit `7c014a6`) — **this one bumps the SwiftData
   schema to `MarbleSchemaV6`** (purely additive: `SprintVariant` + `SprintRepDetail`, no
   migration stage, same V2–V5 pattern). Tenths-precision sprint timing + stopwatch,
   multiple sprint plans per exercise (legacy `SprintPrescription` kept as a synced
   mirror), sequence rollup, fastest-time PR trail, Trends sprint charts, progression
   nudges. See `SPRINT_WORKOUTS.md`. **Release gates already run on this working tree:**
   `make migration-release` PASSED against the pinned previous Release (`96736a1` store
   opens intact, exercises preserved=40); 560 unit tests green including
   `SchemaV6MigrationTests`; sprint + core AddSet UI flows green. Before the next
   submission also run `make audit` and re-record any Trends snapshot baselines the new
   Sprints section needs (`make snapshot-record`, with the change noted).
2. **A 10-fix reliability pass** (commit `9eea3da`) — full-codebase bug audit: backup
   restore integrity, number-field input corruption, a Set Details delete crash pattern,
   the inert Control Center control, seeding durability, notification races — see README →
   Current state for the full list — plus the `MARBLE_SEED_DEMO_FIXTURES` demo-recording
   seed hook.

## ✅ 2.2 (build 52) VALID on TestFlight (2026-07-30)

**2.2 build 52** (buildId `8551570a-9675-4d19-946f-6badd31458b5`, uploaded 2026-07-30,
`VALID`, `internalBuildState: IN_BETA_TESTING`, auto-notify on) is the first build
containing the **on-device parsing quality overhaul** (next section) on top of build
51's free-text import wave. Published via the staged foreground flow (asc-archive →
asc-export → builds upload); "test group A" auto-receives. **2.2 (build 48) remains
the build in App Review.** No schema change since V6.

## ✅ 2.2 (build 53) VALID on TestFlight (2026-07-30)

**2.2 build 53** (buildId `b3db3359-1645-4081-b229-3cf95b22bf7c`, uploaded 2026-07-30,
`VALID`, `internalBuildState: IN_BETA_TESTING`, auto-notify on) is the first build
containing the **free-form notation parsing wave** (next section) — eval 25/25.
Staged foreground publish; "test group A" auto-receives. **2.2 (build 48) remains the
build in App Review.** No schema change since V6.

## ✅ 2.2 (build 54) VALID on TestFlight (2026-07-30)

**2.2 build 54** (buildId `fe58f7a6-70d4-448a-a3df-b90d7971d338`, uploaded 2026-07-30
12:45 PT, `VALID`) is the first build containing the **import review timing wave**
(next section). Staged foreground publish (asc-archive → asc-export → builds upload);
"test group A" auto-receives. **2.2 (build 48) remains the build in App Review.**
No schema change since V6.

## `main` wave after build 53 (2026-07-30) — import review timing & dismissal protection

**On `main` (commit `18e599a`), first shipped in build 54.** Adds date & time control to both import
review screens (Scan + Typed Workout) plus HIG sheet-dismissal protection:

- **Workout-level date & time** — the inline `DatePicker` row is replaced by a shared
  `ImportDateSection` (`ImportTimingViews.swift`): compact date picker capped at "now",
  an "Include Time" toggle that progressively reveals a compact time picker.
- **Per-set override** — new `ParsedSetDraft.performedAt: Date?` (nil = inherit the
  workout date). `ImportSetTimingRows` wraps each set row: context menu + mirrored
  leading swipe action activate/remove an override, revealing an indented date+time
  sub-row and a timestamp caption on divergent sets. Because `.swipeActions` suppresses
  the `.onDelete`-synthesized Delete, an explicit trailing destructive Delete (and a
  "Delete Set" menu item) is re-added. `addSet` templates copy `performedAt`; the
  importer stamps `SetEntry.performedAt` per set (`set.performedAt ?? workoutDate`) and
  the `ImportedWorkout` ledger date is the earliest *effective* set date. No parser
  populates per-set `performedAt` — it is a manual review-screen affordance only.
- **Discard protection** — both sheets use `.interactiveDismissDisabled` + a
  "Discard this import?" confirmation dialog (`ExerciseEditorView` pattern). Scan guards
  a reviewed draft with content; Typed Workout also guards non-empty typed text in
  input/processing; the imported phase never blocks.

No schema change (still V6). 648 unit tests green, `make audit` green.

## `main` wave after build 52 (2026-07-30) — free-form notation parsing

**On `main` (commit `bc934e6`), first shipped in build 53.** Driven by a real user note (pole-vault
session) that build 52 mangled — "4 × 20-meter accelerations at 85–90%" became 20 reps.
The deterministic parser learned: hyphenated units ("20-meter"/"20-pound"), en/em-dash
rep ranges ("8–10" → lower bound), intensity percentages as noise, distance B-values
("4x20m" → 4 distance sets), spec-first lines (name after the numbers), "N by M",
single/double/triple rep words, word weight units (pound/kilogram), leading name-filler
stripping ("worked up to … on bench" → "Bench"), and a bare-number weight/reps sanity
threshold. `WorkoutDraftArbiter` scoring gained colon-duration tokens ("1:30" → 90) and
a coverage component (a draft must *explain* the text's numbers, not just avoid
inventing any). FM instructions gained distance-vs-reps, intensity, and
session-total-vs-per-set rules; the structured pass now retries once like the rewrite
pass. **Eval: 25/25 (100%), two consecutive runs** (corpus grew to 16 notation + 9
prose; five-by-five, worked-up-to-a-double, and goblet-squats re-tiered to notation now
that the deterministic parser nails them). 645 unit tests green. No schema change.

## `main` wave after build 51 (2026-07-29) — on-device parsing quality overhaul

**On `main` (commit `1468a1a`), first shipped in build 52.** Rebuilds the FoundationModels parsing
pipeline that both Typed Workout and Scan use, after the live eval measured the old
design at 50% on a 24-case corpus (now 88%):

- **Doctrine restored (model reads, code computes):** the `@Generable` schema now emits
  `setCount` + per-exercise values (Optionals, `.anyOf` units, `.range` counts) and code
  expands the sets — the old schema needed N identical array elements for "NxM" and the
  ~3B model reliably emitted one. Date text is extracted by the model but resolved in
  code (relative words + `HandwrittenWorkoutParser.explicitDate`).
- **`WorkoutDraftArbiter`** (new, pure): the deterministic parser always runs; model
  drafts win only when they score higher against the source text (set-count agreement
  with NxM tokens, unit-aware numeric fidelity incl. spelled numbers, distinct-name
  presence). Notation input now always keeps its exact deterministic parse (12/12).
- **Second model pass:** prose is also rewritten into gym notation lines
  (`rewriteInstructions` → `GeneratedNotation`) and parsed deterministically —
  transliteration beats 12-field extraction on the small model.
- **Guardrail refusals:** default guardrails refuse benign gym prose ("May contain
  sensitive content"); sessions now use
  `SystemLanguageModel(guardrails: .permissiveContentTransformations)`, avoid
  copy/verbatim phrasing in instructions (an anti-regurgitation refusal trigger), and
  retry once — refusals are intermittent. Greedy sampling everywhere; prewarm on sheet
  appear.
- **Eval harness:** 24-case corpus (`WorkoutParseEvalCorpus`) with notation cases pinned
  against the deterministic parser in CI, and an opt-in live-model eval
  (`TEST_RUNNER_MARBLE_FM_EVAL=1 make only TEST=MarbleTests/FoundationModelsLiveEvalTests`,
  needs Apple Silicon + Apple Intelligence) asserting ≥80% pass rate — currently 88%,
  remaining failures are ambiguous prose + intermittent refusals.

## `main` wave after build 50 (2026-07-29) — free-text workout import

**On `main` (commit `112afa9`), first shipped in build 51.** Adds the "Typed Workout" bulk-import path:
`ImportSource.textEntry`, `WorkoutTextEntryView`/`ViewModel` (paste free text → on-device
parse via the existing FoundationModels/deterministic parsers → review with per-exercise
library matching → journal), the new pure `ExerciseMatcher` (aliases + typo-tolerant
token matching), rest-notation parsing ("rest 90s", "90s rest", rest-only lines) with
`ParsedSetDraft.restSeconds` flowing into `SetEntry.restAfterSeconds`, and a
source-parameterised `WorkoutScanImporter`. **No schema change** (V6 untouched — new
enum case is a raw string; no new `@Model`). Unit suite green (594 tests incl. new
`ExerciseMatcherTests`, `WorkoutTextEntryViewModelTests`,
`HandwrittenWorkoutParserRestTests`).

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

> ✅ **Verified end to end 2026-07-23: 2.2 (build 47) is on TestFlight and `VALID`**
> (buildId `83f4e8ca-a4cf-41ac-8080-4f8703851a42`, uploaded 08:03 PDT). Archive, export,
> IPA integrity, signing, entitlements (keychain group order verified off the archive), and
> internal distribution passed. Build 47 is the Apple-best-practices build (PR #12).

### The release sequence used for builds 41–47

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

## Archived release state (2026-07-25; not current)

- **2.2 (build 49)** — **on TestFlight, `VALID`**. App Store Connect build ID
  `5fe06de0-fc7a-4829-b4d7-a5f6f15d7f31`, uploaded 2026-07-25 from `main` at
  `4443297` (PR #14). Went to the all-build internal group `test group A` (the group is
  configured to receive every build, so `asc` skipped an explicit assignment).
  **It is NOT attached to the in-review version** — build 48's submission is untouched.
  Archive, export, and processing all passed; the two pinned profiles
  (`Prism marble App Store build 48 2026-07-24` / `… MarbleWidgets …`) were reused unchanged,
  as were both entitlement files.
  Build 49 = build 48 plus: editable/deletable weigh-ins, the Settings **Body** section
  (DOTS picker + quick weight entry), Calendar weight-on-day, monthly-report bodyweight facts,
  immediate Spotlight/Siri refresh for import-created exercises, **deployment target 26.2 →
  26.0**, the **Swift 6 language mode** (app + widget + unit/snapshot targets), `UndoableIntent`,
  and the four closed test gaps (onboarding flow, Settings flow, widget snapshots, V4→V5
  recovery). 519 unit tests, snapshots re-recorded and green, `make audit` green, CI green.
- **2.2 (build 48)** — **submitted and `WAITING_FOR_REVIEW`**. App Store Connect build ID
  `ad513fbe-123e-438c-8030-7982af86e198`; review submission ID
  `0e7f361e-2ac6-484d-b1a3-34ae9869da91`; submitted 2026-07-24 at 15:24 PDT.
  The signed archive and exported IPA passed validation, the processed build is `VALID`,
  and the version remains configured for **manual release** after approval. App Store
  metadata, review notes, and all 30 iPhone/iPad screenshots were synced before submission.
- **2.1 (build 40)** — **LIVE on the App Store**, released 2026-07-21 via
  `asc versions release --version-id 59f2e4c7-1c4b-49b3-a5d3-265ca6da74b1 --confirm`;
  state moved `PENDING_DEVELOPER_RELEASE` → `READY_FOR_SALE` in the API. It carries the
  sessions / sprint-prescription / Exercise-Library / JSON-backup work from builds 35-39.
  **No phased release was configured** (`appStoreVersionPhasedRelease` was null), so it went
  to 100% of users at once — worth creating one *before* releasing next time, since 2.1 was
  the first production build to run the V2→V4 migrations.
- **2.2 (build 47)** — superseded submission candidate; still **on TestFlight, `VALID`** (buildId
  `83f4e8ca-a4cf-41ac-8080-4f8703851a42`, uploaded 2026-07-23 at 08:03 PDT). The internal group
  `test group A` (`514a95e2-28fc-436b-b624-9aaec2963adc`) has access to all builds.
  Build 48 replaced it for App Review. It is build 46 plus the merged Apple-best-practices work
  (PR #12): intents refresh the widget/reminder/Spotlight, complete JSON backup with an
  exhaustiveness guard, Live Activity staleDate + rest-complete notification, TipKit tips
  attached, widget privacy manifest, Audio Graph chart descriptors, Smart Stack relevance +
  quick-log widget link, scoped-query performance pass, and the full `.foregroundStyle`
  migration. Unit suite 505/505, CI green, accessibility audit passed. The 2.2 defect list in
  `ROADMAP.md` is now mostly resolved — re-read it before writing release notes; the on-device
  checklist walk in `TESTING.md` is still the gate before App Review submission.
- **2.0 (build 34)** — superseded by 2.1. Its review is closed; nothing about it is live
  state any more.
- **Working project version: `MARKETING_VERSION = 2.2`, `CURRENT_PROJECT_VERSION = 48`.**
  Build 48 is the submitted candidate. Re-run `make asc-next-build` before any later upload;
  the next valid build number is expected to be 49.

---

## Build history (what each build carried)

- **Build 49:** the known-gap closure build (PR #14, merged 2026-07-25). Five items from a
  source review of build 48. The user-facing one: **a weigh-in can be corrected** —
  `BodyMetricEntryView`'s edit path had exactly one caller and it passed `nil`, so a typo was
  permanent and skewed every DOTS score. Also: DOTS coefficients and quick weight entry in
  Settings, Calendar weight-on-day, monthly-report bodyweight facts, and
  `ExerciseSpotlightIndex.refreshAfterLibraryChange()` from all three import paths (driven by a
  new `WorkoutImporter.Summary.createdExercises`, counted after the save). Engineering:
  deployment target dropped 26.2 → 26.0 (build 48 excluded 26.0/26.1 devices for one API, now
  behind `#available(iOS 26.1, *)`), Swift 6 language mode everywhere except `MarbleUITests`,
  `UndoableIntent` on both set-logging intents, dead glass helpers removed. Tests: onboarding
  and Settings UI flows, a widget snapshot suite for all five families (the layouts moved to
  `marble/Shared/WeeklyGoalWidgetViews.swift`), and a V4→V5 case through the recovery
  container. Two defects were caught by the new tests and fixed in the same build: the widget's
  quick-log Link rendered in system blue, and an unbounded `@Query` for weigh-ins hung the
  Trends render. `@Dependency` for intents was tried and reverted (it traps outside the system
  perform flow).

- **Build 47:** the Apple-best-practices build (PR #12, merged 2026-07-23). Closes the
  "wired up but inert" 2.2 defects: Siri/shortcut-logged sets now refresh the Weekly Goal
  widget, weekly-goal reminder, and Spotlight before the intent returns; backup restore does
  the same; TipKit tips finally present (scan, coaching, PR feed); deleted exercises leave
  Spotlight immediately. Backup JSON now carries ImportedWorkout, ProgressMediaAttachment
  metadata, and CustomNotification with a schema-exhaustiveness guard test. Rest-timer Live
  Activity gained staleDate, a rest-complete local notification (nothing fired at zero
  before), Always-On dimming, a live minimal presentation, and the small activity family.
  New: Audio Graph descriptors on all Trends charts, Smart Stack relevance scoring +
  `PredictableIntent` donation, a quick-log link on the medium widget, `marble://quicklog`,
  the widget extension's own privacy manifest, and the scoped-query performance pass
  (history-token freshness probe, bounded picker query, batched maintenance sweeps).
  Mechanical: `.foregroundColor` fully migrated to `.foregroundStyle`; failure paths use a
  semantic error haptic. Unit suite 505/505 locally and in CI; accessibility audit passed.
- **Build 46:** Daily Highlights motivation is now a quiet footer. The dedicated
  divider, quote icon, “Evening Note” label, serif emphasis, and pagination pills were removed
  in favor of secondary italic copy with a compact author and position line. Rotation, manual
  advancement, the 44-point target, Dynamic Type, VoiceOver, and Reduce Motion behavior remain
  intact. The 460-test unit suite passed locally and in GitHub CI `29976114363`; the focused
  snapshot comparison, quote interaction flow, and focused light/dark accessibility audits
  passed locally. Archive/export, IPA verification, and internal TestFlight processing passed.
- **Build 45:** Daily Highlights now follows Marble's monochrome content system: solid card
  surfaces, gray borders and dividers, compact date treatment, grayscale achievement icons,
  and a stronger result-first hierarchy with no gold or decorative gradients. Quote rotation,
  schedule behavior, screenshot-friendly composition, Dynamic Type, VoiceOver, and Reduce
  Motion behavior are preserved. All **460** unit tests, eight focused snapshots, the time-
  window/quote interaction flow, and both focused accessibility audits passed; GitHub CI
  `29974031009` passed; signed app/widget archive and export passed before TestFlight reached
  `VALID` and `IN_BETA_TESTING`.
- **Build 44:** Performance pass: Trends reuses one full-history PR derivation; Exercise
  Picker derives its recent/favorite/all sections in one memoized pass; launch orphan
  maintenance is gated once per app version; Workout fetches at most one active and five
  completed sessions; and the Daily Highlights minute timeline is isolated to its leaf view.
  All **460** unit tests passed locally and in GitHub CI (`29972031799`); the signed app and
  widget archive/export passed before TestFlight processing reached `VALID` and
  `IN_BETA_TESTING`.
- **Build 43:** Daily Highlights now uses a premium achievement-specific accent treatment,
  removes its Share/export control, and presents three rotating quotes selected from a
  sourced 45-quote public-domain catalog. Automatic quote motion stops under Reduce Motion,
  VoiceOver, and UI testing. All 455 unit tests, the eight focused snapshots, the interaction
  flow, the 5,000-entry benchmark, and both light/dark accessibility audits pass.
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
  The question was closed at the time; the current train is now 2.4.
- **Build/test health (2026-07-22):** Xcode 26.6 / iOS 26.5 simulator. Build 46's full
  **460-test** unit suite, focused Daily Highlights snapshot, quote interaction flow, and
  focused light/dark accessibility audits passed locally; CI `29976114363` passed. Build 46's
  Release archive/export and TestFlight processing also passed.
  The build-42 focused
  logic, performance, snapshot, UI, and light/dark accessibility gates **passed**. The prior
  full-suite baseline remains: `make unit` **passed**
  and `make audit` **passed**. `make ui` was **39 passed / 1 failed**; the failure,
  `AppStoreScreenshotUITests.test07TrainingCalendar`, is **proven pre-existing** — it fails
  identically on a clean `origin/main` worktree on this host (`UICalendarView` render timing)
  and is not a release gate. Suite sizes counted from source: `Tests/Unit/` = 51 files / 53
  classes / **460 test methods**; `Tests/UI/` = 17 files / **49 test methods**. Do not
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

**Build 48 signing refresh (2026-07-24):** the older active profiles above were tied to a
distribution certificate whose private key is not installed on this Mac. Two replacement
App Store profiles were created with the installed Apple Distribution certificate
`9M47KCWLU8` and are now pinned in the project and both export-options files:

- `Prism marble App Store build 48 2026-07-24` (`G545NTS973`)
- `Prism marble MarbleWidgets App Store build 48 2026-07-24` (`JF52GQ2SSV`)

**Resolution used for build 23**:
- ASC Bundle ID `Prism.marble.MarbleWidgets` exists (`4L93LB6CMY`).
- ASC App Store profile `Prism marble MarbleWidgets App Store 2026-06-22 build 23`
  exists (`S668TD2D5G`) and is installed locally.
- `.asc/ExportOptions.plist` maps both `Prism.marble` and `Prism.marble.MarbleWidgets`.
- Release signing is pinned per target in `marble.xcodeproj/project.pbxproj`.

For the next upload, `make asc-next-build` currently reports **48**. Never guess a build
number locally.

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

## Current release decisions (2026-08-24)

- 2.3 build 56 was public at the 2026-08-24 US storefront verification. Do not invoke another
  release operation for it without fresh live checks.
- 2.4 build 61 is `VALID` and `IN_BETA_TESTING` in internal **test group A**.
  Its external state is `READY_FOR_BETA_SUBMISSION`; external beta review was not requested.
- The AI-first Add release replaces Train with Add / Log / Progress. Its feature
  source is `c8200e2`; exact uploaded merge source is `eead033`.
- App Store version 2.4 is `WAITING_FOR_REVIEW` with build 61 under submission
  `ce4a0d8a-...`. Superseded build 60 submission `5bd874ad-...` is `COMPLETE`.
  Do not confuse submitted with approved or publicly live.
- Build 61 is the current App Review candidate. Its exact source is `9e8346f` and ASC
  build is `bbea8736-...`; it replaced build 60 in review, not public production.
- App Review notes, screenshots, privacy, declarations, usage metrics, migration, and
  physical-device evidence remain distinct from binary processing and submission state.
- The user explicitly approved docs, GitHub `main`, production, and TestFlight
  promotion on 2026-08-24. Preserve exact-SHA provenance and complete live readback.
- Keep App Store submission and public release as distinct states even within that approval.

## Historical 2.2 release decisions (archived; not current)

**2.2 build 48 is waiting for App Review; build 49 is on TestFlight only.** Build 49 does
**not** replace the submission — it was uploaded as a normal TestFlight build while 48 sits in
review. Do not attach 49 to the in-review version or cancel the submission unless review finds
a blocker. If review *does* reject 48, 49 is the natural replacement (it is 48 plus the
known-gap closures below, all verified locally).

Before manually releasing an approved build:

- The local App Store submission gate in `TESTING.md` passed using dedicated iPhone and iPad
  simulators, focused integration tests, deep-link checks, archive inspection, and live
  App Store Connect validation. Keep the hardware-only Apple integration pass as an optional
  check before manual public release, not as a submission blocker.
- **The known gaps are closed in build 49** (`ROADMAP.md` → Known gaps / next up): weigh-ins
  are editable and deletable, the DOTS coefficient picker and quick weight entry live in
  Settings, and import-created exercises reach Spotlight and the Siri phrases immediately.
  **Build 48 — the build in review — still has all three defects**, so keep them out of 2.2
  release notes unless 49 becomes the shipped build.
- ~~**Configure a phased release before releasing this time.**~~ **Done** — verified
  `appStoreVersionPhasedRelease.configured = true` on 2026-07-24 (`make asc-status`, progress
  0/7). 2.1 shipped to 100% at once because it was null. 2.2 carries the V5 migration and the first
  widget surface — both are exactly what phased rollout exists for.
- **Strava posture is unchanged: ship with Strava _unconfigured_.** Leave
  `StravaClientID` / `StravaClientSecret` / `StravaRedirectURI` out of the build so only the
  fully-verified **Apple Health + Garmin-via-Health** paths go out. Strava stays hidden
  unless keys are set, so this is the default — **no code change required**. Promote it only
  after (a) a live OAuth round-trip with real keys and (b) a decision on the in-binary
  `client_secret` (see "Workout import"). Rationale: Strava is the only import path that is
  network-facing, ships a secret, and is unverified end-to-end.
- Keep manual public release a separate, explicitly approved step. Re-check review state and
  phased-release configuration before releasing an approved build.

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
- `origin/main` merge `9e8346f` is the exact binary source for 2.4 build 61.
  TestFlight build 61 is `VALID` / `IN_BETA_TESTING` internally and
  `READY_FOR_BETA_SUBMISSION` externally. App Review 2.4 build 61 is `WAITING_FOR_REVIEW`
  with no reported blocking issues. App Privacy publish state and
  Regulations/Permits remain website-only verification coverage gaps, not
  blockers reported by the current submission.
- Active submission `ce4a0d8a-...` contains build 61. Superseded submission
  `5bd874ad-...` is canceled / `COMPLETE`. Manual release and public storefront
  state remain separate from review submission.
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
make asc-version      # expect MARKETING_VERSION 2.4, CURRENT_PROJECT_VERSION 59
make asc-status
make asc-builds
make asc-next-build   # expect 59 before upload; stop and reconcile otherwise
```
