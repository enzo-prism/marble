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

## Agent startup + source of truth
- Read `RELEASE_HANDOFF.md` before release-sensitive work. It records the latest cleanup branches, App Store state snapshot, and release rules.
- Treat `origin/main` as the canonical release baseline unless fresh git/ASC checks prove otherwise.
- Start release-sensitive sessions with `git fetch --all --prune`, `git status --short --branch`, `git branch -vv`, `make asc-version`, `make asc-status`, `make asc-builds`, and `make asc-next-build`.
- Do not delete or rewrite `backup/*` or `feature/*` cleanup branches unless the user explicitly asks; they preserve extracted work from the branch cleanup.
- Do not cancel App Store review, bump builds, upload binaries, or submit review without explicit user approval and a clean release branch.
- If replacing the current review build, create a release branch from clean `origin/main`, use the next ASC build number, and regenerate `.asc` artifacts from scratch.
- Keep release cleanup narrow. Avoid public API or SwiftData model changes unless the approved fix requires them.

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
- `marble/Models/` — SwiftData `@Model` types + enums.
- `marble/Persistence/` — `ModelContainer`, `MarbleSchema` (VersionedSchema + migration
  plan), `SeedData`, `ProgressMediaStore`, `Queries/`.
- `marble/Theme/` — theme + design tokens.
- `marble/Components/` — shared UI components and formatters.
- `marble/Features/` — `Journal`, `Calendar`, `Supplements`, `Trends`, `Split`,
  `Notifications`, `Import` (`HealthKit/`, `Strava/`, `OAuth/`). The import feature is a
  `WorkoutImportProvider` abstraction over Apple Health, Garmin (via Health), and Strava
  (official OAuth). **See `INTEGRATIONS.md` for the full design and rationale.**
- `marble/Intents/`, `marble/Testing/` (`TestHooks`), `marble/PrivacyInfo.xcprivacy`.
- `Tests/` — `Unit/`, `Snapshots/`, `UI/`, `TestSupport/`.
- `.github/workflows/ci.yml` — runs `make unit` on PRs and `main`/`release/**` pushes.

## Current state + gotchas (read first)
- **`RELEASE_HANDOFF.md` is the dated source of truth for release/version/signing state.**
  Read it before any release work; it is kept current (last verified date at the top).
- **`ROADMAP.md` holds the H2 2026 plan** — what 2.2 shipped, what is deliberately deferred,
  and the two portal steps that gate archiving. Read it before starting new feature work.

### 2.2 lessons (2026-07-20) — do not rediscover
- **A container's `.accessibilityIdentifier` overrides its children. This has now bitten
  four times** (`Import.Scan`, `Import.GarminBridge`, and in 2.2 a `Settings.List` on the
  Settings `List` that hid every `Settings.*` row from the tests). Identify leaf controls
  only — never a `VStack`/`List`/`Section`/`Form` wrapper.
- **SwiftUI `List` rows below the fold are not in the accessibility tree.** `waitForIdentifier`
  will time out on a row that simply needs scrolling; use `scrollToElement(_:in:)` first.
- **App/widget shared code:** files needing membership in *both* targets get an explicit
  `PBXFileReference` + `PBXBuildFile` + an entry in the widget's Sources phase (the
  `RestTimerAttributes.swift` precedent). Everything else under `marble/`, `MarbleWidgets/`
  and `Tests/` is picked up automatically by the filesystem-synchronized groups.
  Such files must import Foundation-only frameworks and reference no app type; app-only
  calls go inside `#if !WIDGET_EXTENSION` (that flag is set on the widget target).
- **Never hand-pick a `BEEFC0DE…` object id without checking it is free.** Ids `…0001`
  through `…0010` are taken. A collision produces a project that passes `plutil -lint` but
  that Xcode rejects as *"damaged"* with `-[XCConfigurationList group]: unrecognized selector`.
- **`\.someProperty` key paths do not work on metatype existentials** (`[any VersionedSchema.Type]`).
  Use `.map { $0.versionIdentifier }`. This was the only compile error in the 2.2 test suite
  and `xcodebuild` reports it as an opaque `Command SwiftCompile failed` with no diagnostic
  in the log — bisect by which `.dia` files are missing under `MarbleTests.build/Objects-normal/`.
- Adding the App Group entitlement **breaks Release archiving until the portal work is done**
  (the two `PROVISIONING_PROFILE_SPECIFIER` strings are pinned by name). Debug/simulator and
  CI are unaffected, which is why `make unit` stays green.
- SwiftData schema is versioned in `Persistence/MarbleSchema.swift`. For a breaking model
  change, add a `MarbleSchemaV2` + a `MigrationStage` — do not just edit models.
- The target sets `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so any Codable value type
  SwiftData serializes (e.g. `ExerciseMetricsProfile`) must be marked `nonisolated` or it
  warns (a hard error under the Swift 6 language mode).
- **Workout import is ToS-aligned and backend-free** (`INTEGRATIONS.md`): Apple Health is
  the universal bridge, Garmin comes in *through* Apple Health (no direct Garmin login —
  that would violate Garmin's ToS), and Strava is a direct official OAuth connector that
  stays hidden until its Info.plist keys are set. Do not add reverse-engineered logins.

## asc cli reference

Prefer the repo-level `asc` wiring over ad hoc commands.

- App Store Connect app: `marble.fit` (`Prism.marble`, app ID `6757725234`)
- Xcode project + scheme: `marble.xcodeproj` + `marble`
- Deterministic release artifacts: `.asc/artifacts/marble.xcarchive` and `.asc/artifacts/marble.ipa`
- Start a new machine/session with: `make asc-auth`, `make asc-doctor`, `make asc-version`
- Use: `make asc-builds`, `make asc-archive`, and `make asc-export ASC_EXPORT_OPTIONS=/absolute/path/to/ExportOptions.plist`
- Prefer `make asc-version` over raw `asc xcode version view`, because this project uses generated Info.plists and the helper prints a reliable `MARKETING_VERSION` fallback
- `make asc-archive` already bakes in the required `generic/platform=iOS` destination for this project
- The current app target requires the iOS `26.2` platform. If `xcodebuild`/`asc` reports “no destinations” or says iOS `26.2` is not installed, install that platform/runtime from Xcode > Settings > Components before debugging further.

See `ASC.md` for the fuller Marble-specific command reference.
