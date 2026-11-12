# Apple platform implementation — November 2026

Authorized by the owner on 2026-11-11, from canonical `main` `e1e1275`.
This branch is an implementation candidate, not a release. No new binary has been uploaded.

## Implemented behavior

| Area | Candidate behavior | Acceptance still required |
|---|---|---|
| Shared commands | Log/repeat/start/finish save before rest, donations and indexing; undo cancels only the originating rest; complete units and sprint tenths | Final unit and migration gates |
| App Intents | Typed set/session results, correction by exact ID, date-filtered workout search, open/share/repeat-review, authenticated data-returning actions, nine App Shortcuts | Final release gates; physical locked-device behavior |
| System surfaces | One workout-long Live Activity, integrated rest, exact routes, onscreen exercise/session associations, bounded Spotlight session indexing | Physical lock screen, termination/recovery and accessibility |
| Apple Health | Retry checkpoints and stable sync IDs; no inferred workout effort; opt-in native strength session with pause/resume/recovery | Physical authorization, save, cleanup and background recovery |
| Capture | On-device SpeechAnalyzer dictation with editable review; text/file/image Share extension with bounded local OCR and a five-item shared-keychain inbox | Physical speech and cross-process Share handoff |
| History | Text export from session detail; repeats enter review; imported Health workout zones on iOS 27 | Final UI and accessibility suites |
| Watch | Focused phone-connected controller: start, repeat last set, rest/skip, finish and refresh; persistent request IDs prevent repeat duplication after lost acknowledgements | Physical Watch transport, offline retry and rest alerts |
| AI extraction | Actual model on the Mac's iOS 27.2 simulator meets unchanged standard/prose/hard quality thresholds | Final release gates; physical iPhone latency remains unverified |
| Progress Details | Semantic metric colors, stable category colors, matching volume symbols/legend, wrapping category values, proper weekly bar intervals, adaptive Increase Contrast, neutral surfaces and preserved data/Audio Graphs | Final visual matrix, accessibility audit and UI checks |
| Siri AI preview | Updated skill text, scenarios and separate development-only project generator; SDK preflight prevents accidental public packaging | Xcode/iOS 27.3, compiled skills, Siri Evaluations and conversational/card acceptance |

The Watch target is a companion controller. It does not yet own a wrist HealthKit
workout, collect Watch heart-rate sensors or provide a Smart Stack widget. Those are
separate from the iPhone native session and must not be advertised as delivered.
The preview scenarios are evaluation inputs, not executed Siri AI evaluations.
Entity-level presentation authentication is a Siri 27.3 preview capability, not a
verified stable-SDK privacy gate. Regular intents returning workout information
explicitly require authentication, verified in Apple's extracted intent metadata
for the development binary. The upload path verifies the archive metadata again.
System redaction can hide the Live Activity's
workout title and exercise label; locked-device acceptance is still required.

## Verification evidence so far

- The latest full unit run completed 1,110 cases: 1,100 passed and ten explicitly
  gated cases skipped, with zero failures, after the callback, parser, editor,
  authentication, overnight Health export, model backoff, Progress Details and dictation lifecycle changes.
  It includes the reopened SQLite selection predicate and analytic text/mark contrast
  across light, dark and Increase Contrast. Consistent totals restated as sets now
  reconcile without adding an extra effort; inconsistent totals remain unresolved.
  This is developmental evidence; release still needs an exact committed-source run.
- A live simulator diagnostic exposed a model assigning pounds to a load explicitly
  written in kilos. Grounding now applies the single unit written beside that exact
  numeric load in its source span, without converting the number. Regressions cover
  mixed units, the same load in separate movements, and both units within one movement.
  The two new failure cases were reproduced before the fix; the full unit suite passed.
  The prior single-unit rejection test now verifies recovery of the exact written load,
  unit and reps instead of discarding an otherwise grounded movement.
- All 96 Progress snapshot variants
  were intentionally recorded and verified, including the production volume component
  and category values at the largest text size. Final release evidence must cover the
  complete snapshot/UI/audit suites on the release source.
- Dictation setup cancellation and audio ownership have seven hardware-free regression
  checks. Audio-session configuration/activation runs away from the UI actor; stale
  Stop/Cancel work cannot deactivate a newer recording. Actual microphone acceptance
  remains unverified; further iPhone automation is not authorized.
- Log sheets use full height at accessibility text sizes, including the exercise picker
  and active-workout logger. Both largest-text exercise-library flows passed after the
  change. The focused onboarding rerun passed both preference/completion flows and the
  updated privacy-copy capture. A gated physical microphone UI check is compiled but
  has not yet run; it uses the synthetic fixture and clears its own draft without saving.
- Opening a planned set now presents its selected exercise as the sheet item. This
  fixes a reproducible empty logger sheet; the existing split edit/log/dismiss/save
  UI flow passed without weakening its assertions.
- The latest full UI sweep completed 81 cases: 77 passed, four explicitly gated cases
  skipped and zero failures. It covers the corrected privacy assertion, accessibility
  sheet layout, planned-set logger and onboarding dismissal. The tab check accepts its
  native visible label when SwiftUI omits the identifier. The import edit flow waits
  up to the same 60 seconds used by other parsing flows, preserving every edit assertion.
  This is development evidence; the final source/version/build still needs its full gate.
- The latest full accessibility sweep completed 13 cases: ten passed, two runtime
  checks skipped and one failed on theoretical native-toolbar clipping. The corrected
  harness captures AX identity/frame atomically and resolves a specific fresh occurrence;
  the editor and both Notes audits pass. Known plain labels measure 8.46–21:1 at the
  unchanged 4.5:1 threshold. Follow-up default audits identified history text sizing;
  card values/timestamps and section headings now explicitly retain their full height.
  The native Cancel/Save titles and Last time heading pass full-word rendered-pixel OCR
  within their bounds at XXXL; Cancel also dismisses the sheet. A theoretical report
  for those exact elements is cleared only when the same fresh render check passes.
  All eight Add Set/history snapshot cases passed without reference changes after the
  card sizing fix. Final full accessibility/snapshot acceptance remains required.
- A simulator background watchdog captured synchronous notification removal waiting
  on service XPC from the UI actor. All app/Watch removal now runs explicitly away from
  that actor, with removal-before-add ordering retained. A regression check verifies
  the executor hop and exact notification identifiers. Watch requests also time out
  after 15 seconds while preserving pending mutation IDs; pausing only the paired
  simulator phone verified that controls recover and later refresh succeeds.
- Physical validation confirmed sprint tenths and start/log/repeat/finish through
  Apple's App Intents system path. The query identity assertion was corrected to compare
  instance IDs, because the framework can omit a returned entity's bundle qualification.
- The matching Xcode/iOS 27.2 simulator passed both opt-in App Intents system-service
  flows, including distinct repeated-set identities, exact units, sprint tenths,
  session completion and entity lookup. Xcode 27.0's AppIntentsTesting library could
  not load against the 27.2 runtime; the matching 27.2 probe resolved that SDK mismatch.
  The regular release gates remain pinned to Xcode/iOS 27.0.
- Both native simulator keychain inbox checks passed: concurrent five-item capacity
  and reopening, plus stale-review protection when a slot is reused. Simulator results
  do not prove physical keychain access-group enforcement or a cross-process Share UI.
- The isolated iOS 27.2 simulator passed the native Health workout lifecycle:
  authorize workout writing, start, pause, resume, return from the Home screen,
  save one workout and remove only that validation-owned workout/session. The iOS 27
  consent sheet uses granular switches; the test now enables workout writing before
  tapping its enabled Allow button. Physical sensors and extended background runtime
  remain unverified.
- Synthetic speech-file acceptance was attempted on both simulator toolchains, but
  the English local speech model was unavailable. Those explicit skips are not speech
  acceptance, and no further phone automation will be used to replace them.
- Four active-session/navigation checks passed on the connected phone. Final whole-suite
  UI, accessibility, snapshots, migration and device acceptance remain pending.
- A paired iOS/watchOS 27.0 simulator run exercised start, rest, skip, repeat and finish.
  Phone-store readback confirmed one completed workout with exactly two sets after one
  phone save and one Watch repeat. A WatchConnectivity callback actor-isolation crash
  found during this run was fixed and rechecked. Physical Watch, offline retry and
  notification/haptic acceptance remain pending.
- An on-device hybrid-parser evaluation passed 41/43 standard cases and 5/7 prose cases,
  but failed the unchanged hard-corpus gate at 36/71 (51%; required 60%). Later paced
  execution was interrupted by the phone relocking and is not a quality result. A later
  completed run reached 42/71 (59%) and still failed; it encountered model throttling
  near the end. The threshold remains unchanged. Explicit lists, weight-first notation
  and restated totals have regression coverage; that prior physical result remains
  below its threshold. Further iPhone automation is no longer authorized.
  Throttling is distinguished from context overflow and respects Apple's reset deadline
  with a bounded fallback backoff. Fixed token metadata is cached without workout content.
- A dedicated local iOS 27.2 simulator initially reported modelNotReady, then became
  ready and exercised the Mac's actual model. The corrected-source quality run passed
  41/43 standard cases, 5/7 prose cases and 45/71 hard cases, with no model-service
  failures. This meets the unchanged 80% / 70% / 60% thresholds. These are simulator
  model results, not physical iPhone latency or microphone acceptance.
- Snapshot references were intentionally updated for the pinned stable Xcode 27.0 /
  iOS 27.0 renderer. All four recording/verification shards completed successfully in
  run `43117948757`. Visual review adopted 214 changed non-Progress references, while
  preserving every newer local Progress reference. Production evidence still requires
  a full latest-source verification on this Mac Studio.
  The earlier sequential recorder was cancelled after live logs showed only group 13
  at 75 minutes; its partial artifact is not full acceptance.
- The later local five-gate development attempt passed unit and part of the snapshot
  matrix before being interrupted to correct the source-unit bug. It is incomplete
  development evidence, not a passing release manifest. Run all five gates again on
  the clean final source/version/build.
- Release-tooling Ruby checks passed after signing, authentication-metadata and CI changes.
- The migration gate includes the immutable public 2.6.1 (84) source as well as
  retained 2.5 (77) and 2.4 (61) coverage. All three passed against `6deb220`, preserving
  each real store's identity, fixtures and 40 exercises. Regenerate the full gate for
  the final release source/build.

Evidence above is developmental. Production requires clean committed source, the five
release gates, a device signoff for that exact source/build, and an upload receipt.
See `RELEASE_HANDOFF.md`, `TESTING.md` and `SiriAIPreview/README.md`.

## Platform and distribution boundaries

- App deployment remains iOS 26.0; iOS 27-only APIs are availability gated.
- The app declares no scheduled `processing` background mode: it registers no
  Background Tasks work. Native workout/background acceptance depends on the Health
  session, Live Activity and recovery lifecycle, not an unrelated Info.plist mode.
- Stable development/CI uses Xcode 27.0 (27A266a), iOS/watchOS 27.0.
- The connected iPhone is on iOS 27.2, with Developer Mode and UI automation enabled.
- Physical tests use `Prism.marble.validation`, isolated URL schemes, keychain groups,
  and a dedicated persistent App Intents test store. Production is not the test target.
- Owner subsequently stopped further iPhone automation. Remaining automated checks run
  on this Mac Studio's simulators; actual microphone, on-device model and physical
  Health/Lock Screen checks are not substituted with simulated results. The first
  microphone attempt stopped at an ambiguous native consent-button query before the
  fixture played; the scoped query was corrected, but no further phone run is authorized.
- Readback 2026-11-11: public 2.6.1 (84); 2.7 (86) is approved and pending manual release.
  Build 86 predates this work. Working source version 2.7 (85) has not been bumped;
  determine the new version/train and next build from fresh ASC state before release.
- Apple's November 3 preview requires iOS 27.3 and supported Apple Intelligence hardware.
  Preview features cannot be distributed through the App Store or external TestFlight.
  Do not equate App Shortcuts/system-path tests with custom Siri AI acceptance.

## Invariants

1. Save before timers, system updates and donations.
2. Preserve explicit units and tenths. New timed logs require an explicit duration;
   they never infer a measured time from history. An explicit Repeat Last Set copies
   its confirmed source; whole-workout repeats remain editable review drafts.
3. Bulk/repeated workouts require editable review before commit.
4. Keep schema V6, existing stable IDs and keychain group order; no App Group.
5. Use navigation-only glass and accessible leaf controls. The owner approved semantic
   color for Progress Details and analytical drilldowns on 2026-11-11; keep neutral
   surfaces, stable meanings, labels/shapes and adaptive contrast.
6. Preserve users' data during device validation; repair only explicitly identified test records
   through SwiftData, after checking identity, timestamp and emptiness.

## Apple references (checked 2026-11-11)

- [Siri AI developer preview announcement](https://developer.apple.com/news/)
- [Building a workout app for iPhone and iPad](https://developer.apple.com/documentation/healthkit/building-a-workout-app-for-iphone-and-ipad)
- [Running workout sessions](https://developer.apple.com/documentation/healthkit/running-workout-sessions)
- [SpeechAnalyzer introduction](https://developer.apple.com/videos/play/wwdc2025/277/)
- [Speech asset inventory](https://developer.apple.com/documentation/speech/assetinventory)
- [Actual Foundation Models execution in Simulator](https://developer.apple.com/videos/play/wwdc2025/259/)
- [Dynamic Type layouts](https://developer.apple.com/videos/play/wwdc2024/10074/)

- [Foundation Models OS/model revision guidance](https://developer.apple.com/documentation/Updates/FoundationModels)
- [Model rate-limit recovery](https://developer.apple.com/documentation/foundationmodels/languagemodelerror/ratelimited(_:))
- [Chart design and accessibility](https://developer.apple.com/design/human-interface-guidelines/charts)
- [Color, appearance and inclusive design](https://developer.apple.com/design/human-interface-guidelines/color)
