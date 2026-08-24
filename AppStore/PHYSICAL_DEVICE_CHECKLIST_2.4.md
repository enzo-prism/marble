# Marble 2.4 physical-device acceptance checklist

Prepared 2026-08-21; build-59 Add coverage updated 2026-08-24. This checklist is
not a release or metadata authorization.
Record the exact build installed on each device.

## Session record

- Candidate commit: `eead033f7d454180c61f1e49d7d66a233927c3c8`
- Marketing version / build: 2.4 / 59
- Installation source: TestFlight (`3235fff4-515a-40db-9239-41338ec34ead`)
- iPhone model / iOS / UDID:
- iPad model / iPadOS / UDID:
- Paired Apple Watch model / watchOS (integration source only; no Marble Watch app):
- Tester / date:

Current host discovery on 2026-08-21: `xcrun devicectl list devices` returned
**No devices found**. `xcrun xctrace list devices` showed only the Mac mini and
the iPhone 17 Pro Marble Audit simulator. None of the checks below has physical
hardware evidence yet.

## Accessibility declarations — run on iPhone and iPad separately

| Gate | iPhone | iPad | Pass evidence |
|---|---|---|---|
| VoiceOver + Screen Curtain | [ ] | [ ] | Onboarding; Add composer/Paste/File/Review; Plan and active-workout accessory start/log/rest/finish; nested Add Set; Log create/edit/delete; Calendar/Supplements; all Progress Audio Graphs; Settings/backup. No focus trap, unlabeled control, silent state, sighted assistance, or touch. |
| Voice Control, no touch | [ ] | [ ] | **Show Names** and **Show Numbers** identify every action; visible-name commands work; scrolling, menus, swipe alternatives, dictation/editing, import, and backup are operable by voice. |
| AX5 / maximum Larger Text | [ ] | [ ] | All common tasks work with keyboard shown; no overlap, severe truncation, clipped text, hidden confirmation, or unreachable control. Rotate and test iPad split layouts where supported. |
| Dark Interface | [ ] | [ ] | Cold launch and every app/system sheet remain dark with no bright flash. Repeat permission prompts and Files/Photos handoffs. |
| Grayscale | [ ] | [ ] | Selected states, validation, PRs, sprint hit/miss, charts, imported/skipped status, and destructive actions remain understandable without color. |
| Increase Contrast | [ ] | [ ] | Repeat light and dark common-task paths; text, icons, controls, charts, disabled states, widgets, and Live Activity remain legible. |
| Reduce Motion | [ ] | [ ] | Verify the integrated custom-motion fixes: no press scaling, rotating quote, animated onboarding advance, import timing motion, animated disclosure/scroll, Trends disclosure motion, or Add Set live-badge motion. Meaningful state changes remain understandable. |

## Device-only system surfaces

| Check | Required device | Result / evidence |
|---|---|---|
| Signed install, fresh launch, completed-user relaunch | iPhone + iPad | [ ] Install succeeds; version/build match; no migration/recovery alert or data loss. |
| Weekly Goal Home Screen and Lock Screen widgets | iPhone | [ ] Add each family; state matches app after logging; quick-log link opens Marble. Recheck while device is locked. |
| App-to-widget keychain sharing | iPhone | [ ] Weekly-goal snapshot survives app termination/relaunch and renders outside the app; no neutral-card fallback on signed hardware. |
| Rest Live Activity | Dynamic Island iPhone if available | [ ] Start rest; Lock Screen/Dynamic Island count down; **+30s** and **End** work while locked; app and activity agree after relaunch. |
| Control Center / Lock Screen / Action button | Compatible iPhone | [ ] Quick Log control opens the right surface from locked and unlocked states; Action button assignment works if hardware supports it. |
| Siri, Shortcuts, and Spotlight | iPhone + iPad | [ ] Log/repeat a set, start/finish workout, and open exercise results; confirmations and deep links are correct. |
| Notifications | iPhone + iPad | [ ] Permission denial/recovery, weekly goal reminder, rest-complete alert, tap-through, and disabled-state behavior are correct. |
| Apple Health read/write | iPhone | [ ] Deny then grant; import workout/bodyweight; write one completed strength session; duplicate fetch does not duplicate; source attribution is correct. |
| Apple Watch workout through Health | Paired Watch + iPhone | [ ] Record a workout in Apple Workout, sync to Health, import into Marble, and verify source/title/duration. This does not test a Marble Watch app. |
| Garmin through Apple Health | Garmin-synced iPhone | [ ] Sync a real Garmin workout into Health, import it, and verify source/title/duration without a direct Garmin login. |
| Camera and multi-page OCR | iPhone + iPad | [ ] Deny then grant camera/photos; scan a real multi-page handwritten workout; dated multi-session handoff and review preserve all recognized/unrecognized lines. |
| Files import | iPhone + iPad | [ ] Import real Hevy CSV, Strong CSV, EU semicolon/decimal-comma file, and multi-day Notes text; verify order, units, RPE, notes, duration, duplicates, and weak-match behavior. |
| Backup export and restore | iPhone + iPad | [ ] Export via Files, inspect share completion, restore into a clean install/test dataset, and verify counts/content. Confirm progress media exclusion is explained. |
| Offline behavior | iPhone + iPad | [ ] With Airplane Mode, core logging, history, progress, import parsing, widgets, and backup still work; optional remote/Health states fail clearly. |

## Final sign-off

- [ ] Every failure has a reproducible issue with device/OS/build and evidence.
- [ ] Fixes were re-tested on the same failing hardware and the other device family.
- [ ] App Store accessibility worksheet reflects only features that passed on each family.
- [ ] App Store Connect readback matches the intended draft before any publish request.
- [ ] Separate explicit approval obtained for accessibility draft creation and again for live publish.
- [ ] Separate release approval obtained; this checklist alone does not authorize submission or release.
