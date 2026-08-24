# Accessibility Nutrition Labels — declaration worksheet

**Automated evidence updated: 2026-08-24 for 2.4 build 59 feature source
`c8200e2`, uploaded from merge `eead033`. Physical-device declarations remain
unverified.**

## Current verdict

Do not publish a declaration yet. Marble has strong implementation and automated
evidence, but Apple requires every common task to work with the declared feature
on each supported device family. Marble supports both iPhone and iPad
(`TARGETED_DEVICE_FAMILY = "1,2"`), and neither family has completed the physical
device passes below.

The App Store Connect API currently returns **no accessibility declarations** for
app `6757725234` — no draft and no published iPhone, iPad, or Apple Watch record.
The public App Store version remains 2.3; version 2.4 is `WAITING_FOR_REVIEW`.

There is no Apple Watch app target. Do not create an `APPLE_WATCH` declaration
for the iPhone/iPad widget extension or for Apple Health imports from Apple Watch.
The Watch companion remains a separate roadmap item.

Apple's current rule is that all common tasks must be completable with a claimed
feature. Declarations are per device family and can only be published for a family
with a live App Store version. Publishing is immediate, cannot be unpublished,
and may take up to 24 hours to appear. Required roles are Account Holder, Admin,
Finance, App Manager, or Marketing.

Apple references:

- [Overview and common-task standard](https://developer.apple.com/help/app-store-connect/manage-app-accessibility/overview-of-accessibility-nutrition-labels)
- [Manage and publish declarations](https://developer.apple.com/help/app-store-connect/manage-app-accessibility/manage-accessibility-nutrition-labels)
- [VoiceOver criteria](https://developer.apple.com/help/app-store-connect/manage-app-accessibility/voiceover-evaluation-criteria)
- [Voice Control criteria](https://developer.apple.com/help/app-store-connect/manage-app-accessibility/voice-control-evaluation-criteria)
- [Larger Text criteria](https://developer.apple.com/help/app-store-connect/manage-app-accessibility/larger-text-evaluation-criteria)
- [Differentiate Without Color Alone criteria](https://developer.apple.com/help/app-store-connect/manage-app-accessibility/differentiate-without-color-alone-evaluation-criteria)
- [Sufficient Contrast criteria](https://developer.apple.com/help/app-store-connect/manage-app-accessibility/sufficient-contrast-evaluation-criteria)
- [Reduced Motion criteria](https://developer.apple.com/help/app-store-connect/manage-app-accessibility/reduced-motion-evaluation-criteria)

## Proposed declarations

Use the same decision independently for iPhone and iPad. A pass on one family
does not authorize declaring the other.

| Feature | Proposed answer | Evidence and remaining gate |
|---|---|---|
| VoiceOver | Yes, after device pass | Trends Audio Graph descriptors have landed at all seven chart call sites and `TrendsChartDescriptorTests` cover descriptor structure, ranges, and speech. Complete the screen-curtain pass for every common task on iPhone and iPad. |
| Voice Control | Yes, after device pass | The app predominantly uses standard SwiftUI controls and has leaf-control labels/identifiers. With **Show Names** and **Show Numbers**, complete every task without touching the display, including dictation, scrolling, menus, and swipe alternatives. |
| Larger Text | Yes, after device pass | `MarbleTypography`, accessibility-size layout swaps, the snapshot matrix, dedicated XXXL UI flows, and no app-level Dynamic Type cap provide strong evidence. Verify AX5/maximum system text on both families, including keyboard-visible sheets and long imported text. |
| Dark Interface | Yes, after device pass | `Theme` supplies complete light/dark palettes and the automated matrix covers both appearances. Cold-launch and traverse every system sheet/permission path in Dark Mode with no bright flash. |
| Differentiate Without Color Alone | Yes, after grayscale pass | Marble is monochrome except semantic sprint results. Those results pair color with check/x/minus symbols, explicit hit/missed text, and spoken labels. Complete all common tasks with the Grayscale color filter on iPhone and iPad. |
| Sufficient Contrast | Yes, after device pass | `ThemeContrastTests` enforce 4.5:1 text and 3:1 graphical contrast; build 59's `make audit` selected 6 tests with 5 passes, 1 runtime-unsupported skip, and 0 failures across populated/empty light/dark surfaces. Repeat the common tasks with Increase Contrast in both appearances on both families. |
| Reduced Motion | Yes, after device pass | Daily Highlights stops rotating, and the app suppresses custom button scaling and custom motion in onboarding, import timing, Exercise Editor, Trends disclosure, and the Add Set live badge when Reduce Motion is enabled. Build 59 compiles/tests these paths; complete the physical-device common-task pass before claiming support. |
| Captions | No / not applicable | Marble has no dialog-bearing or instructional audio/video content. User progress media is not part of a common task. |
| Audio Descriptions | No / not applicable | Marble supplies no authored video content that needs an audio-description track. |

## Automated gate

Before any device sign-off or metadata change, record a green result for the exact
candidate commit:

```bash
make unit
make ui
make audit
make snapshot
```

Important limitations:

- `AccessibilityAuditUITests` checks labels, hit regions, contrast, clipping, and
  Dynamic Type across populated/empty light/dark screens, but the iOS 26.5 runtime
  may skip its unsupported Dynamic Type audit. Dedicated XXXL flows and snapshots
  are complementary evidence, not a substitute for the physical AX5 pass.
- `ThemeContrastTests` is the numerical palette authority because simulator
  contrast sampling has produced known false positives on SwiftUI section headers.
- Unit tests prove Audio Graph descriptor data; only VoiceOver on device proves
  discoverability, navigation order, speech quality, and operability.

## Physical-device gate

Run the complete matrix in `AppStore/PHYSICAL_DEVICE_CHECKLIST_2.4.md`. For the
accessibility declaration, the minimum common-task set on **both iPhone and iPad**
is:

1. Complete first launch and onboarding.
2. Use Add to paste/type and review a workout; open Plan, start a workout,
   log/repeat/edit a set through the active-workout accessory, run/end rest, and finish.
3. Use Log to create, inspect, edit, and delete history; switch Calendar and
   Supplements modes.
4. Import and review a pasted Notes workout and a real Hevy or Strong file.
5. Review Progress, including Audio Graph navigation for each chart type and a
   bodyweight edit.
6. Configure units, weekly goal, notifications, Apple Health, and complete one
   backup export/restore path in Settings.

For VoiceOver, repeat with Screen Curtain and sighted assistance unavailable. For
Voice Control, repeat with no touch input. For Larger Text, use AX5/maximum text.
For color and contrast, use Grayscale and Increase Contrast in both light and dark.

## Staged App Store Connect action

The following is a plan, **not authorization to execute it**. Creating the record
mutates App Store Connect; publishing changes the live product page and requires
action-time approval. Run only after all seven proposed features above pass for
that device family.

```bash
asc accessibility create \
  --app 6757725234 \
  --device-family IPHONE \
  --supports-voiceover true \
  --supports-voice-control true \
  --supports-larger-text true \
  --supports-dark-interface true \
  --supports-differentiate-without-color-alone true \
  --supports-sufficient-contrast true \
  --supports-reduced-motion true \
  --supports-captions false \
  --supports-audio-descriptions false \
  --output json --pretty

asc accessibility create \
  --app 6757725234 \
  --device-family IPAD \
  --supports-voiceover true \
  --supports-voice-control true \
  --supports-larger-text true \
  --supports-dark-interface true \
  --supports-differentiate-without-color-alone true \
  --supports-sufficient-contrast true \
  --supports-reduced-motion true \
  --supports-captions false \
  --supports-audio-descriptions false \
  --output json --pretty
```

Read both draft IDs back with `asc accessibility list --app 6757725234
--paginate --output table`, compare every field to this worksheet, and obtain a
second explicit approval before `asc accessibility update --id <ID> --publish
true`. Never create an Apple Watch declaration from this worksheet.

Re-evaluate each published claim whenever a release adds a new common-task
surface. Accessibility metadata can be changed separately from a build, but it
must always describe the live product accurately.
