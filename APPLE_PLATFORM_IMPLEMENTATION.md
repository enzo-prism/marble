# Apple platform implementation — November 2026

Authorized by the owner on 2026-11-11, from canonical `main` `e1e1275`.
This branch is an implementation candidate, not a release. No new binary has been uploaded.

## Implemented behavior

| Area | Candidate behavior | Acceptance still required |
|---|---|---|
| Shared commands | Log/repeat/start/finish save before rest, donations and indexing; undo cancels only the originating rest; complete units and sprint tenths | Final unit and migration gates |
| App Intents | Typed set/session results, correction by exact ID, date-filtered workout search, open/share/repeat-review, authenticated data-returning actions, nine App Shortcuts | Final physical system-path run; locked-device behavior |
| System surfaces | One workout-long Live Activity, integrated rest, exact routes, onscreen exercise/session associations, bounded Spotlight session indexing | Physical lock screen, termination/recovery and accessibility |
| Apple Health | Retry checkpoints and stable sync IDs; no inferred workout effort; opt-in native strength session with pause/resume/recovery | Physical authorization, save, cleanup and background recovery |
| Capture | On-device SpeechAnalyzer dictation with editable review; text/file/image Share extension with bounded local OCR and a five-item shared-keychain inbox | Physical speech and cross-process Share handoff |
| History | Text export from session detail; repeats enter review; imported Health workout zones on iOS 27 | Final UI and accessibility suites |
| Watch | Focused phone-connected controller: start, repeat last set, rest/skip, finish and refresh; persistent request IDs prevent repeat duplication after lost acknowledgements | Physical Watch transport, offline retry and rest alerts |
| AI extraction | Live model corpus tests record per-case outcomes and latency attachments | Run on the actual phone with its installed model |
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

- The latest full unit run completed 1,099 cases: 1,089 passed and ten explicitly
  gated cases skipped, with zero failures, after the callback, parser, editor,
  authentication, overnight Health export, model backoff and Progress Details changes.
  It includes the reopened SQLite selection predicate and analytic text/mark contrast
  across light, dark and Increase Contrast. Consistent totals restated as sets now
  reconcile without adding an extra effort; inconsistent totals remain unresolved.
  This is developmental evidence; release still needs an exact committed-source run.
- Physical validation confirmed sprint tenths and start/log/repeat/finish through
  Apple's App Intents system path. The query identity assertion was corrected to compare
  instance IDs, because the framework can omit a returned entity's bundle qualification.
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
  and restated totals have regression coverage; the physical quality gate must be rerun.
  Throttling is distinguished from context overflow and respects Apple's reset deadline
  with a bounded fallback backoff. Fixed token metadata is cached without workout content.
- Snapshot references are being intentionally updated for the pinned stable Xcode 27.0 /
  iOS 27.0 renderer. Recording uses four disjoint shards, each followed by verification;
  artifacts include changed references only. Production evidence forces the full suite.
  The earlier sequential recorder was cancelled after live logs showed only group 13
  at 75 minutes; its partial artifact is not full acceptance.
- Release-tooling Ruby checks passed after signing, authentication-metadata and CI changes.
- The migration gate includes the immutable public 2.6.1 (84) source as well as
  retained 2.5 (77) and 2.4 (61) coverage; the expanded gate must pass before release.

Evidence above is developmental. Production requires clean committed source, the five
release gates, a device signoff for that exact source/build, and an upload receipt.
See `RELEASE_HANDOFF.md`, `TESTING.md` and `SiriAIPreview/README.md`.

## Platform and distribution boundaries

- App deployment remains iOS 26.0; iOS 27-only APIs are availability gated.
- Stable development/CI uses Xcode 27.0 (27A266a), iOS/watchOS 27.0.
- The connected iPhone is on iOS 27.2, with Developer Mode and UI automation enabled.
- Physical tests use `Prism.marble.validation`, isolated URL schemes, keychain groups,
  and a dedicated persistent App Intents test store. Production is not the test target.
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

- [Foundation Models OS/model revision guidance](https://developer.apple.com/documentation/Updates/FoundationModels)
- [Model rate-limit recovery](https://developer.apple.com/documentation/foundationmodels/languagemodelerror/ratelimited(_:))
- [Chart design and accessibility](https://developer.apple.com/design/human-interface-guidelines/charts)
- [Color, appearance and inclusive design](https://developer.apple.com/design/human-interface-guidelines/color)
