# Marble (iOS) — Agent Instructions (Codex)

## Goals
- Maintain best-in-class mobile UX for fast logging.
- Preserve the “Marble” brand: pure white/black backgrounds, grey accents only.
- Keep Liquid Glass limited to navigation surfaces (tab bars, toolbars, sheets). Avoid glass-on-glass. Keep content layer solid.

## Liquid Glass design standards (strict)
Follow the guidelines in:
- `AdditionalDocumentation/UIKit-Implementing-Liquid-Glass-Design.md`
- `AdditionalDocumentation/WidgetKit-Implementing-Liquid-Glass-Design.md`
- `AdditionalDocumentation/AppKit-Implementing-Liquid-Glass-Design.md`

Key rules distilled for this app:
- Use native Liquid Glass APIs when available (`glassEffect`, `GlassEffectContainer`, `.buttonStyle(.glass)`); fallback to Material only when needed.
- Apply Liquid Glass to interactive controls and navigation surfaces; never to content rows, charts, or list bodies.
- Keep glass elements lightweight and limited in count; prioritize performance and stability.
- Maintain sufficient spacing between glass elements so they read as intentional, or explicitly merge them with a container when they should blend.
- Ensure text and icons on glass meet contrast requirements and remain legible in light/dark; respect Reduce Transparency.
- Keep shapes consistent and fully clipped (no accidental cropping) and match system-like corner radii.
- If implementing widgets or AppKit/UIKit components, follow the platform-specific guidance in the above docs (rendering modes, accenting, container behavior).

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
