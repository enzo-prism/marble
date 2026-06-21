# MarbleWidgets — rest-timer Live Activity setup

The rest-timer Live Activity is **wired in the app and ready to light up** — the only
remaining step is adding the widget-extension target, which must be done in the Xcode UI
(it can't be created safely by hand-editing `project.pbxproj`).

## What's already done (in the app target, on this branch)
- `marble/Features/RestTimer/RestTimerAttributes.swift` — the shared `ActivityAttributes`.
- `marble/Features/RestTimer/RestActivityController.swift` — starts/replaces/ends the
  activity. Already called after every **interactive** set log (AddSet, "Log Again",
  duplicate in Journal + Set detail); bulk import deliberately does not trigger it. Every
  call is a safe no-op until this extension exists, so nothing is broken in the meantime.
- Unit tests: `Tests/Unit/RestActivityControllerTests.swift` (pure start/timing logic).

## Remaining manual steps (Xcode)
1. **Add the target.** File ▸ New ▸ Target… ▸ **Widget Extension**.
   - Product Name: `MarbleWidgets`
   - **Check** "Include Live Activity". (Leave "Include Configuration App Intent" unchecked.)
   - Embed in the `marble` app when prompted. Set its deployment target to match (iOS 26.2).
2. **Use these sources.** Delete the target's auto-generated template files and add the two
   files in this folder to the **MarbleWidgets** target:
   - `RestTimerLiveActivity.swift`
   - `MarbleWidgetsBundle.swift`  (keep exactly one `@main` in the extension)
3. **Share the attributes.** Select `marble/Features/RestTimer/RestTimerAttributes.swift`
   and, in the File Inspector ▸ Target Membership, **also check `MarbleWidgets`**. ActivityKit
   matches the attributes by structure, so both targets compile their own identical copy.
4. **Enable Live Activities on the app target.** Add to the **app** Info.plist (or as a build
   setting `INFOPLIST_KEY_NSSupportsLiveActivities = YES`):
   ```xml
   <key>NSSupportsLiveActivities</key>
   <true/>
   ```
5. **Run.** On a device or simulator (iOS 16.1+), ensure Settings ▸ (Marble) ▸ Live
   Activities is on, then log a set whose rest is > 0 — the countdown appears on the Lock
   Screen and in the Dynamic Island, and auto-dismisses when rest ends. Logging the next set
   replaces the timer.

## Notes
- The Live Activity UI uses monochrome system colors to match the Marble brand. To reuse the
  app's `Theme`/`DesignTokens`, add those files to the extension's membership too (optional).
- `RestActivityController` keeps a single active timer and ends the previous one when a new
  set is logged; `cancelRest()` is available if you later want a "skip rest" affordance.
- Verify: after adding the target, `xcodebuild ... -scheme marble build` should compile both
  targets; the extension's `RestTimerLiveActivity` will resolve `RestTimerAttributes` once the
  shared file is a member of `MarbleWidgets`.
