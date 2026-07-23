# Accessibility Nutrition Labels — declaration worksheet

Labels appear on iOS 26+ App Store product pages. They are voluntary today, but
Apple has said they will become required for new apps and updates, and accuracy
falls under Review Guideline 2.3 (accurate metadata). Declaring early is free
shelf-visible differentiation most fitness apps cannot claim.

Where: App Store Connect → App → App Information → Accessibility. Editable any
time without a new build or review submission. Roles that can edit: Account
Holder, Admin, App Manager, Marketing.

Rule of thumb from Apple's criteria pages: declare a feature only if every
"common task" (first launch, logging a set, reviewing history, settings) can be
completed using it.

## What Marble can declare, and the evidence

| Feature | Declare? | Evidence / caveats |
|---|---|---|
| VoiceOver | Yes, after chart descriptors land | Identifiers and labels across the app, adjustable actions (quote rotator), modal escape supported by system sheets. The VoiceOver criteria explicitly require charts to use "a specific chart API or reasonably complete text alternatives" — that is the `accessibilityChartDescriptor` work on Trends; do not declare before it ships. |
| Larger Text | Yes | Semantic Dynamic Type via `MarbleTypography`, accessibility-size layout swaps (`dynamicTypeSize.isAccessibilitySize`), no `dynamicTypeSize` caps. Before declaring, walk the app at AX5 once and confirm nothing truncates without a full-text alternative. |
| Sufficient Contrast | Yes | `ThemeContrastTests` is the contrast authority; grayscale palette tuned per scheme; Trends charts tuned for ~3:1 graphical contrast. |
| Reduced Motion | Yes | Quote rotation and animations disabled under Reduce Motion; `make audit` covers it. |
| Dark Interface | Yes | Full dark palette in `ThemePalette`; no app-specific appearance override. |
| Differentiate Without Color Alone | Verify first | The two sanctioned accents (sprint goal hit/miss) must be paired with a non-color cue (icon/shape/text) everywhere they appear before declaring. Audit `SprintGoalCardView` and any widget/Live Activity use. |
| Voice Control | Verify first | Likely works via standard controls + labels, but run a manual pass (navigate, log a set, edit an exercise by voice) before claiming. |
| Captions / Audio Descriptions | No | Marble plays no audio/video content; Apple's guidance is to leave media features undeclared when there is no media. |

## Process

1. Land the Trends chart `accessibilityChartDescriptor` work (Audio Graphs).
2. Run the two manual passes above (AX5 walk, Voice Control walk) on device.
3. Declare in App Store Connect; optionally link a public accessibility page.
4. Re-verify the declarations whenever a release adds a new surface — the
   labels are metadata, and stale claims are a 2.3 violation.
