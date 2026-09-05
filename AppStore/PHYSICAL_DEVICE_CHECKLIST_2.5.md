# Marble 2.5 (66) physical-device acceptance

Updated September 5, 2026 for PR #32. **Status: not run; no device acceptance is claimed.**
Record the final commit and actual installed build before testing. If the candidate
changes, update this record and rerun affected checks; never carry signoff silently
between builds. Simulator results do not satisfy the hardware checks below.

## Candidate and evidence record

- Intended version / build: **2.5 / 66** (reconcile against fresh ASC readback)
- Final candidate full commit: **PENDING: build-66 corrections are in progress**
- Previous build 64 source: `d3364db57ba5e7c9b39ca1ac21e9616735f527d9`;
  uploaded internally as ASC build `9c965892-fc3f-4eb1-bf88-f93826b8436d` by
  workflow `33938114946`. This is not build-66 proof or physical acceptance.
- ASC build ID / installation source / upload receipt:
- Exact-source release-suite run URL and result (unit, snapshots, UI, accessibility, migration):
- Tester / test date:
- iPhone model / iOS / installed version and build:
- iPad model / iPadOS / installed version and build:
- Paired Apple Watch model / watchOS, if tested:
- Evidence location (screenshots, recordings, logs, issue links; exclude private workout data):

Current prerequisites: build 66 has not yet completed full validation or upload.
The paired iPhone's Developer Mode was last confirmed disabled; the owner is
enabling it, with reinspection pending. Every hardware result below remains **Not run**.
Build-64 unit, snapshot, UI, and simulator migration successes do not satisfy these
checks; its accessibility gate failed, with two additional runtime Dynamic Type
skips. Recheck History empty and detail text contrast/wrapping on the corrected build.
No external beta invitations or Beta App Review submission have been made.

Use a dedicated test dataset. Export and independently preserve a backup before
upgrades or recovery tests. Never deliberately corrupt a tester's only real store.
An unavailable device, old binary, or integration is **not run**, not a pass.

## Upgrade and storage preservation

Run each upgrade without uninstalling Marble, so the existing store is retained.
Record before/after counts and representative values for sets, sessions, notes,
exercise identity, body measurements, supplements, settings, and progress media.

| Scenario | Result | Evidence |
|---|---|---|
| Install production **2.4 build 61**, seed/use a representative dataset, then upgrade in place to candidate **2.5 (66)**. Cold launch, inspect history, save another workout, terminate and relaunch. Existing records and new writes persist without duplicates or unexpected recovery. | Not run | |
| Upgrade an available genuine **2.3** installation/store to the candidate. Record the exact old build and provenance. Verify the same records and settings after launch and another save. A fresh candidate install is not a substitute. | Not run | |
| Fresh signed candidate install on both iPhone and iPad; complete onboarding, save, terminate and relaunch. | Not run | |
| Exercise unreadable-store handling with a disposable fixture through the documented test harness. Original store remains available for recovery; UI explains the failure and does not silently substitute an empty or temporary writable store. Record harness/fixture and whether this ran on hardware or only in automation. | Not run | |
| Resume a normal launch after a recoverable failure; verify the expected store and history are restored. | Not run | |

## Review drafts, restore, and repeat

| Scenario | Result | Evidence |
|---|---|---|
| Paste a multi-session workout; edit dates, exercise matches, sets, weights, reps, units and notes in Review. Background/terminate before saving, reopen, and verify the entire edited draft, not only its original text. | Not run | |
| Repeat interruption during a scan/file review and with unresolved lines. Unresolved content remains visible and cannot disappear silently. Cancel/discard clears only the intended draft. | Not run | |
| Save a recovered draft once, then relaunch. Exactly the intended sessions/sets exist and the completed draft is not offered again. | Not run | |
| Export a backup via Files; retain it outside the app. Restore into a disposable dataset and compare counts, dates, units, notes, relationships and settings after relaunch. | Not run | |
| Try malformed/unsupported backup fixtures. Failure is explained, existing records survive, and a later valid restore succeeds. Document whether each failure path was physical or automated. | Not run | |
| Confirm backup messaging explains that actual progress photos/videos are excluded. Do not claim a full media backup or delete originals based on this export. | Not run | |
| Find an existing session in Log/history, open details, and choose Repeat. Review opens with the intended exercises/sets; simply opening or canceling Repeat creates no new saved session. | Not run | |
| Edit a repeated workout and save once. Verify dates and values, one new session, unchanged original, and no duplication after relaunch or repeated taps. | Not run | |
| Confirm the history scope is understandable: individual sets and Health/Strava imported summaries are not silently presented as complete native session history. Check their existing Log paths separately. | Not run | |

## Hardware and accessibility surfaces

Run common Add → Review → Save → Log → Repeat → Progress → Settings/backup tasks
on both device families. Record unsupported hardware surfaces explicitly.

| Check | Device | Result / evidence |
|---|---|---|
| VoiceOver with Screen Curtain and Voice Control without touch; labels, focus, review errors and save confirmations are understandable. | iPhone + iPad | Not run |
| Maximum Larger Text, keyboard visible, light/dark, Increase Contrast, Reduce Transparency, Reduce Motion, grayscale; controls remain reachable and states distinguishable. Rotate and test iPad split layouts. | iPhone + iPad | Not run |
| Weekly Goal Home/Lock Screen widget reflects saved data after app termination; signed app-to-widget keychain sharing works without neutral-card fallback. | iPhone | Not run |
| Rest Live Activity countdown, +30s and End from Lock Screen/Dynamic Island agree with app after relaunch. | Compatible iPhone | Not run |
| Siri/Shortcuts/Spotlight and Quick Log controls open or perform the intended task; no duplicate writes. Action button if supported. | Compatible hardware | Not run |
| Notification denial, enable/recovery, rest completion and reminder tap-through. | iPhone + iPad | Not run |
| Health permissions, real workout/bodyweight import, completed-session write and repeated fetch without duplicates. | iPhone | Not run |
| Apple Watch workout and Garmin workout through Apple Health retain source/title/duration. No Marble Watch app or direct Garmin login is implied. | Connected source hardware | Not run |
| Real camera/Photos permission denial/recovery and multi-page OCR; real Files CSV/text import preserves weak matches and unresolved lines for review. | iPhone + iPad | Not run |
| Airplane Mode: core logging, history, repeats, parsing and backup work; remote dependencies fail clearly. | iPhone + iPad | Not run |
| Strava remains hidden if unconfigured. If enabled, separately verify authorized OAuth and live import; record configuration and evidence without secrets. | Configured test account only | Not run |

## Signoff

- [ ] Every row has pass/fail/not-run plus evidence and actual device/build.
- [ ] Failures have reproducible issues; release-blocking failures are resolved and retested.
- [ ] Missing evidence is explicitly listed; no unsupported accessibility claim is published.
- [ ] Final source commit matches automated results and uploaded binary receipt.
- [ ] Production build-61 upgrade and older-2.3 upgrade have recorded results or explicit unresolved blockers.
- [ ] ASC version/build/review state has been read back immediately before promotion.
- [ ] Release coordinator has checked the existing user authorization and applicable release gates.

Final verdict: **PENDING**

Blocking failures / unavailable prerequisites:

Signer / date / exact source commit / ASC build ID:
