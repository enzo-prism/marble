# Marble 2.5 (80) App Store screenshots

Captured September 19, 2026 from the real iOS app on dedicated iPhone 17 Pro Max and iPad Pro 13-inch (M5) simulators running iOS 26.5. Source af817a1 contains production source 4ea0d05621e511906b2e7ccbc125ef35d8d4f7dc; only screenshot tests and the screenshot composer differ locally.

## Upload-ready images

- `upload/iphone-69`: 9 opaque RGB PNGs, 1320 × 2868, ordered 01–09.
- `upload/ipad-13`: 9 opaque RGB PNGs, 2064 × 2752, ordered 01–09.
- Raw original captures and attachment provenance remain under `raw/`.
- `manifest.json` records captions, scene order, fixture date, and source.
- `checksums.json` records exact upload file hashes and dimensions.

The story is Add → Workout History → Repeat Workout → Review → Log → Progress → Daily Highlights → Calendar → Backups. Headlines describe actual visible capabilities. Daily Highlights and Progress show the new Tom Brady quote selected using the real swipe interaction. No interface was invented or composited into the screenshots. Full screenshots are preserved proportionally inside monochrome caption canvases at their native output dimensions.

## Capture and visual QA

All seven iPhone scenes passed XCUITest. Refined Add and athlete-quote captures also passed. The first iPad pass passed six scenes; its Backup capture failed because the generic app-level swipe left a lazy sheet row outside the tappable area. A screenshot-test-only correction scrolls the actual collection view and taps the actual row. The refined four-scene iPad pass (Add, Progress, Backups, Daily Highlights) passed with zero failures. Seven final iPad scenes are therefore covered by passing captures.

All eighteen final scenes were inspected as contact sheets; Add and Backups and the athlete quote were additionally inspected at large size. No clip, truncated headline, error state, sensitive real data, or invented feature is present. Fictional seeded workout data uses July 15, 2026; system status time is 9:41. Reduce Transparency is enabled for the deterministic capture. iPad preserves its real native top tab bar and centered sheet layout.

No screenshots were uploaded by the screenshot preparation agent. No production code or git commits were changed.

## History and Repeat addition

Added two real-UI scenes per device from a successfully finished seeded workout. Captures navigate Add → active Workout → Finish → dismiss sheet → Log → Workout History. The first capture shows the Workout Sessions list with native search and date-filter controls and one completed 50-minute Leg Day. The second opens the session and Repeat Workout, showing an editable four-set copy before any saving. Both final device tests passed. The fixture clock is 9:30AM PDT for these two scenes to match the seeded 8:40AM session start.

Build80 retains the captured build78 production app source and assets. Differences are release materials, test harnesses and references, and the build number; the exact candidate identity is retained in the upload receipt. These captures represent the candidate UI. Existing seven-scene upload originals remain under archive-seven-scenes-upload. History/Repeat capture tests are included in the build80 source checkout.
