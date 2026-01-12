# Marble (iOS) — Agent Instructions (Codex)

## Goals
- Maintain best-in-class mobile UX for fast logging.
- Preserve the “Marble” brand: pure white/black backgrounds, grey accents only.
- Keep Liquid Glass limited to navigation surfaces (tab bars, toolbars, sheets). Avoid glass-on-glass. Keep content layer solid.

## Apple design + dev standards (strict)
Always start with `AdditionalDocumentation/INDEX.md` to identify relevant docs and extract 3–5 actionable rules before coding. If `scripts/design-check.sh` exists, run it after UI changes.

### Liquid Glass
Follow:
- `AdditionalDocumentation/SwiftUI-Implementing-Liquid-Glass-Design.md`
- `AdditionalDocumentation/UIKit-Implementing-Liquid-Glass-Design.md`
- `AdditionalDocumentation/AppKit-Implementing-Liquid-Glass-Design.md`
- `AdditionalDocumentation/WidgetKit-Implementing-Liquid-Glass-Design.md`

Rules:
- Use native Liquid Glass APIs when available (`glassEffect`, `GlassEffectContainer`, `.buttonStyle(.glass)`); fallback to Material only when needed.
- Apply glass after sizing/appearance modifiers; keep shapes consistent and fully clipped (avoid cropped edges).
- Use `GlassEffectContainer` for multiple glass elements; tune spacing intentionally; use `glassEffectUnion` only when elements should blend.
- Make interactive glass elements `.interactive()` where applicable; keep the number of glass layers low for performance.
- Ensure contrast/legibility on glass in light/dark; respect Reduce Transparency.
- In Marble, glass is navigation-only (tab bars, toolbars, sheets) and must never appear on content rows/charts.

### SwiftUI UI patterns
Follow:
- `AdditionalDocumentation/SwiftUI-New-Toolbar-Features.md`
- `AdditionalDocumentation/SwiftUI-Styled-Text-Editing.md`
- `AdditionalDocumentation/Foundation-AttributedString-Updates.md`

Rules:
- Prefer system toolbar placements and `DefaultToolbarItem` where appropriate; use `toolbar(id:)` for user-customizable toolbars.
- For search, favor `.searchToolbarBehavior(.minimize)` on compact layouts and keep toolbar grouping clear.
- Use `AttributedString` + `TextEditor` for rich text; manage `AttributedTextSelection` and `textSelectionAffinity` explicitly when editing.
- Avoid heavy or frequent AttributedString mutations; cache where practical; maintain Dynamic Type and accessibility labels.

### Data + concurrency
Follow:
- `AdditionalDocumentation/SwiftData-Class-Inheritance.md`
- `AdditionalDocumentation/Swift-Concurrency-Updates.md`
- `AdditionalDocumentation/Swift-InlineArray-Span.md`

Rules:
- Use SwiftData inheritance only for true IS-A relationships; keep hierarchies shallow; design for query patterns and migrations.
- Default to main-actor for UI state; avoid mutable global state; use isolated conformances and `@concurrent` for explicit background work.
- Use `InlineArray`/`Span` only for measured hot paths; otherwise prefer standard collections.

### Feature-specific standards (use only when requested)
- App Intents + Visual Intelligence: `AdditionalDocumentation/AppIntents-Updates.md`, `AdditionalDocumentation/Implementing-Visual-Intelligence-in-iOS.md`
  - Provide fast, relevant results; use proper display representations; deep link into the app; use supported intent modes.
- Assistive Access: `AdditionalDocumentation/Implementing-Assistive-Access-in-iOS.md`
  - If supported, provide a simplified scene, large controls, and explicit navigation icons; avoid hidden gestures.
- AlarmKit: `AdditionalDocumentation/SwiftUI-AlarmKit-Integration.md`
  - Request authorization, handle denial, persist alarm IDs, observe updates, and add a widget for countdown UI.
- Widgets + visionOS: `AdditionalDocumentation/WidgetKit-Implementing-Liquid-Glass-Design.md`, `AdditionalDocumentation/Widgets-for-visionOS.md`
  - Support rendering modes, accenting, removable backgrounds, mounting styles, and proximity-aware layout.
- WebKit: `AdditionalDocumentation/SwiftUI-WebKit-Integration.md`
  - Use `WebView`/`WebPage` with explicit navigation policies and JS permissions; prefer nonpersistent stores when privacy matters.
- StoreKit: `AdditionalDocumentation/StoreKit-Updates.md`
  - Follow updated transaction APIs and offer signing; test with StoreKit configs.
- MapKit/GeoToolbox: `AdditionalDocumentation/MapKit-GeoToolbox-PlaceDescriptors.md`
  - Use `PlaceDescriptor` for place identity and consistent geocoding.
- Foundation Models: `AdditionalDocumentation/FoundationModels-Using-on-device-LLM-in-your-app.md`
  - Only if explicitly requested; check availability, use sessions, honor context limits, and prefer on-device privacy.

## Setup
- Required: Xcode 15+ (recommended latest).
- Build: iOS Simulator.

## How to run
Use these commands (preferred):

- Run all fast checks (unit + snapshots):
  `make test`

- Run UI flow tests (slower):
  `make ui`

- Run accessibility audits suite (contrast, Dynamic Type, hit region, labels, clipped text):
  `make audit`

- Record/refresh snapshot baselines intentionally:
  `make snapshot-record`

- Run a single test quickly:
  `make only TEST='MarbleUITests/JournalFlowUITests/testAddEditDuplicateDeleteSet'`

## Testing philosophy (do this every change)
- After any UI change: run `make test`.
- If UI interaction changed: run `make ui`.
- If fonts/layout/theme changed: run `make audit` and `make test`.

## Requirements for new UI
- Every tappable UI element must have an accessibilityIdentifier.
- Text must never be low contrast against background; grey accents must still pass contrast thresholds.
- Support Dynamic Type; avoid clipped/overlapping layouts, especially in sheets and with keyboard visible.

## Snapshot testing rules
- Snapshots must cover:
  - Light + Dark
  - Default text + Accessibility text size
  - Small width device (SE) + regular device
  - Key empty/loaded/error states
- Update baselines only via `make snapshot-record` and with a clear reason.

## Determinism for tests
- The app must support launch arguments / environment variables to force deterministic state:
  - disable animations
  - fixed “now” timestamp
  - seeded fixtures dataset
  - forced color scheme (light/dark)
  - forced Dynamic Type category
- UI tests must NOT rely on real time or prior simulator state.

## Repo structure
- Models/
- Persistence/
- Theme/
- Features/Journal
- Features/Calendar
- Features/Supplements
- Features/Trends
- Tests/
  - Unit/
  - Snapshots/
  - UI/
