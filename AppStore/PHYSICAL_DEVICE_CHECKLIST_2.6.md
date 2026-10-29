# Marble 2.6 (83) physical-device acceptance

Updated October 4, 2026. **Not run: physical iPhone unavailable; no signoff claimed.**
Build 83 is a local candidate, not an uploaded or production release. All results
below remain pending until a tester installs the exact final candidate. Build 82
TestFlight success and simulator tests are not build 83 hardware acceptance.

## Candidate evidence

- Version/build: 2.6 / 83
- Final full Git SHA: pending
- ASC build UUID, upload receipt and installation source: pending upload
- Complete exact-source release manifest: pending
- Tester and test time: pending
- iPhone model/iOS and confirmed installed version/build: pending
- iPad model/iPadOS and confirmed installed version/build: pending
- Evidence location: pending; exclude private workout data

Preserve an independent backup before an in-place upgrade. Use disposable data
for recovery tests. Never record unavailable hardware or unsupported integrations
as passed. If source or binary changes, rerun affected checks and bind signoff to
the final SHA/build.

## Acceptance checks

| Check | Expected result | Result/evidence |
|---|---|---|
| Upgrade from public 2.5 (77) without uninstalling | Existing sessions, sets, exercises, notes, settings, body measurements, supplements and media remain; new saves survive relaunch | Not run |
| Upgrade an available genuine 2.4 (61) store | Same preservation checks; record old build and store provenance | Not run |
| Fresh install and cold relaunch | Onboarding and logging work on iPhone and iPad | Not run |
| Unitless workout with preferred kg, then lb | Review honors preferred units; explicit units still override | Not run |
| Dictate a workout in sentences | Review preserves exercise names, sets, values and notes; uncertain content remains visible | Not run |
| Paste `Bench 225x5x3` | Plausible sets/reps/load; inspect before saving | Not run |
| Rest durations, including `rest .5min`, seconds and clock notation | Correct durations, no inflation or crash | Not run |
| Stop while reading; quickly retry | Reading cancels, UI recovers, stale results do not replace the new request | Not run |
| Resume edited draft after termination | Dates, matches, sets and notes survive; save once creates exactly one intended workout | Not run |
| Dated/multiple-workout paste | Local days are correct, no future timestamps, sessions appear newest first | Not run |
| History and Repeat | Exercise/set order preserved; opening/canceling creates nothing; repeated save does not duplicate | Not run |
| Apple Health export and auto-import together | Exported Marble workout is not imported back as a duplicate | Not run |
| Delete sprint exercise, then export and restore | No orphaned variants prevent valid restoration; retained data remains correct | Not run |
| Monthly Report opened twice | Same insights for unchanged facts; correct volume unit; provenance visible when applicable | Not run |
| Largest text, Bold Text, light/dark, VoiceOver | Add/Review/Log/History/Progress/Settings controls and content are readable and operable, with no clipping | Not run |
| Real-device responsiveness | Composer typing/cancel, large history, Progress and scrolling remain responsive; record dataset and observations | Not run |
| Recovery using disposable fixture | Original store preserved; retry/recovery controls explain state; no silent empty-store replacement | Not run |

## Machine-readable signoff

Only after genuine device checks pass, record the final candidate identity and
actual tester/device/OS/time in a JSON file passed as `RELEASE_DEVICE_SIGNOFF`.
The verifier requires `git_sha`, `build_number`, `device`, `os`, `tested_at`,
`reviewer`, and `checks` with `launch`, `logging`, `draft_resume`, `history_repeat`,
`accessibility`, and `performance` all equal to `passed`.

This pending checklist is not that signoff file. Do not convert its pending
results into passing values to unblock a release.
