# Apple platform implementation — November 2026

Authorized by the owner on 2026-11-11, from canonical `main` `e1e1275`.
This branch is an implementation candidate, not a release. No new binary has been uploaded.

## Implemented behavior

| Area | Candidate behavior | Acceptance still required |
|---|---|---|
| Shared commands | Log/repeat/start/finish save before rest, donations and indexing; undo cancels only the originating rest; complete units and sprint tenths | Final unit and migration gates |
| App Intents | Typed set/session results, correction by exact ID, date-filtered workout search, open/share/repeat-review, authenticated private entities, nine App Shortcuts | Final physical system-path run; locked-device behavior |
| System surfaces | One workout-long Live Activity, integrated rest, exact routes, onscreen exercise/session associations, bounded Spotlight session indexing | Physical lock screen, termination/recovery and accessibility |
| Apple Health | Retry checkpoints and stable sync IDs; no inferred workout effort; opt-in native strength session with pause/resume/recovery | Physical authorization, save, cleanup and background recovery |
| Capture | On-device SpeechAnalyzer dictation with editable review; text/file/image Share extension with bounded local OCR and a five-item shared-keychain inbox | Physical speech and cross-process Share handoff |
| History | Text export from session detail; repeats enter review; imported Health workout zones on iOS 27 | Final UI and accessibility suites |
| Watch | Focused phone-connected controller: start, repeat last set, rest/skip, finish and refresh; persistent request IDs prevent repeat duplication after lost acknowledgements | Paired simulator/device transport, offline retry and rest alerts |
| AI extraction | Live model corpus tests record per-case outcomes and latency attachments | Run on the actual phone with its installed model |
| Siri AI preview | Updated skill text, scenarios and separate development-only project generator; SDK preflight prevents accidental public packaging | Xcode/iOS 27.3, compiled skills, Siri Evaluations and conversational/card acceptance |

The Watch target is a companion controller. It does not yet own a wrist HealthKit
workout, collect Watch heart-rate sensors or provide a Smart Stack widget. Those are
separate from the iPhone native session and must not be advertised as delivered.
The preview scenarios are evaluation inputs, not executed Siri AI evaluations.

## Verification evidence so far

- A full intermediate unit run passed 1,077 tests, with eight explicitly gated skips.
  Source changes after that run require another full pass.
- Physical validation confirmed sprint tenths and start/log/repeat/finish through
  Apple's App Intents system path. The query identity assertion was corrected to compare
  instance IDs, because the framework can omit a returned entity's bundle qualification.
- Four active-session/navigation checks passed on the connected phone. Final whole-suite
  UI, accessibility, snapshots, migration and device acceptance remain pending.
- Watch simulator compilation passed. This is not paired transport or physical Watch acceptance.
- Snapshot references are being intentionally updated for the pinned stable Xcode 27.0 /
  iOS 27.0 renderer; final recording and verification must both pass.
- Release-tooling Ruby checks passed after signing and CI configuration changes.

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
2. Preserve explicit units and tenths; never copy a historical measured time as a new performance.
3. Bulk/repeated workouts require editable review before commit.
4. Keep schema V6, existing stable IDs and keychain group order; no App Group.
5. Use navigation-only glass, monochrome content and accessible leaf controls.
6. Preserve users' data during device validation; repair only explicitly identified test records
   through SwiftData, after checking identity, timestamp and emptiness.

## Apple references (checked 2026-11-11)

- [Siri AI developer preview announcement](https://developer.apple.com/news/)
- [Building a workout app for iPhone and iPad](https://developer.apple.com/documentation/healthkit/building-a-workout-app-for-iphone-and-ipad)
- [Running workout sessions](https://developer.apple.com/documentation/healthkit/running-workout-sessions)
- [SpeechAnalyzer introduction](https://developer.apple.com/videos/play/wwdc2025/277/)
- [Speech asset inventory](https://developer.apple.com/documentation/speech/assetinventory)
