# Marble (iOS) — Agent Instructions (Codex)

## Goals
- Maintain best-in-class mobile UX for fast logging.
- Preserve the “Marble” brand: pure white/black backgrounds, grey accents only.
- Keep Liquid Glass limited to navigation surfaces (tab bars, toolbars, sheets). Avoid glass-on-glass. Keep content layer solid.

## Apple design + dev standards (strict)
Always start with `AdditionalDocumentation/INDEX.md` to identify relevant docs and extract 3–5 actionable rules before coding. After UI changes, run `make audit` — it is the mechanical check for contrast, Dynamic Type, hit regions, labels, and clipped text.

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
- Required: **Xcode 26.x with an iOS 26.x platform installed** (the code uses iOS 26 APIs —
  older Xcode cannot build this project). The app target **deploys to iOS 26.0** as of build 49
  (it was 26.2 through build 48, which locked out every device on 26.0/26.1 for no reason:
  only one API in the whole codebase needed a newer OS — `tabViewBottomAccessory(isEnabled:)`,
  now behind `#available(iOS 26.1, *)` in `RestTimerPillView`). If
  `xcodebuild`/`asc` reports "no destinations", install the runtime via Xcode > Settings >
  Components or `xcodebuild -downloadPlatform iOS`.
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
- `marble/Features/` — `Body`, `Calendar`, `Import` (`HealthKit/`, `Strava/`, `OAuth/`),
  `Journal`, `Notifications`, `Onboarding`, `RestTimer`, `Settings`, `Split`, `Supplements`,
  `Trends`, `Workout`. The import feature is a `WorkoutImportProvider` abstraction over Apple
  Health, Garmin (via Health), and Strava (official OAuth). **See `INTEGRATIONS.md` for the
  full design and rationale.**
- **Tab IA (iOS 26):** three tab-bar destinations — **Train** (`AppTab.split`, identifier
  `Tab.Split`), **Log** (`AppTab.journal`, identifier `Tab.Journal`; Calendar and Supplements
  are Log modes via `LogModePicker`, identifiers `Tab.Calendar` / `Tab.Supplements`), and
  **Progress** (`AppTab.trends`, identifier `Tab.Trends`). Deep links `marble://calendar` and
  `marble://supplements` still open those modes. Default tab is Train.
- `marble/Shared/` — code that is a member of **both** the app and widget targets:
  `SharedDefaults.swift` (+ `SharedKeychain`), `WeeklyGoalWidgetState.swift`,
  `WeeklyGoalWidgetViews.swift` (the five Weekly Goal family layouts — they live here so the
  app's snapshot suite can render them; the widget target keeps only the `Widget`, the
  `TimelineProvider`, and the keychain read),
  `MarbleSharedIntents.swift` (the rest-timer `+30s`/`End` and quick-log intents).
- `marble/Intents/` — `ExerciseEntity.swift`, `LogSetIntent.swift`, `MarbleAppIntents.swift`,
  `WorkoutSessionIntents.swift`.
- `marble/Testing/` (`TestHooks`), `marble/PrivacyInfo.xcprivacy`.
- `Tests/` — `Unit/`, `Snapshots/`, `UI/`, `TestSupport/`.
- `.github/workflows/ci.yml` — runs `make unit` on PRs and `main`/`release/**` pushes.

## Current state + gotchas (read first)
- **`RELEASE_HANDOFF.md` is the dated source of truth for release/version/signing state.**
  Read it before any release work; it is kept current (last verified date at the top).
- **`ROADMAP.md` holds the H2 2026 plan** — what 2.2 shipped, the **known gaps** (surfaces
  that exist but are not wired up), and why the Watch app was deliberately deferred. Read it
  before starting new feature work, and before claiming any 2.2 feature is finished.

### 2.2 lessons (2026-07-20 / 07-21) — do not rediscover
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
- **The App Group is gone (2026-07-21) — do not add one back.** `group.Prism.marble` broke
  Release archiving (the two `PROVISIONING_PROFILE_SPECIFIER` strings are pinned by name) and
  could not be created programmatically: the App Store Connect API has no App Groups resource.
  App↔widget sharing now runs through the keychain access group
  `L49MKXGVM4.Prism.marble.shared` (`SharedKeychain` in `marble/Shared/SharedDefaults.swift`),
  which both existing App Store profiles already grant via their `L49MKXGVM4.*` wildcard — so
  no portal capability and no profile regeneration. The literal team prefix in Swift must stay
  in sync with `$(AppIdentifierPrefix)Prism.marble.shared` in **both** entitlement files.
- **`marble.entitlements` lists two keychain groups and the order is load-bearing.**
  `$(AppIdentifierPrefix)Prism.marble` is **first**, `$(AppIdentifierPrefix)Prism.marble.shared`
  second. iOS uses the *first* entry as the default access group for any keychain write that
  does not name one, and `KeychainTokenStore` (Strava OAuth) does not name one — reordering or
  dropping the first entry silently moves existing users' Strava tokens into a different group
  and logs them out. `MarbleWidgets/MarbleWidgets.entitlements` is the single-entry one
  (`.shared` only). Do not "simplify" either file.
- On the simulator, keychain access groups are not enforced and `SecItem*` can return
  `errSecMissingEntitlement`; every call degrades to "no snapshot" (neutral widget card),
  which is why Debug/simulator and CI stay green.
- **SwiftData schema is versioned in `Persistence/MarbleSchema.swift` and is currently V6.**
  Never edit a shipped schema version's models in place — add a new `MarbleSchemaVN`, append
  it to `MarbleMigrationPlan.schemas`, and bump the single `Schema(versionedSchema:)` line in
  `ModelContainer.swift`.
  **For an additive change (a new `@Model`, a new optional property) do NOT add a
  `MigrationStage`.** SwiftData's automatic lightweight migration handles it, and an explicit
  stage resolves both endpoints to the same checksum — that is exactly what crashed build 35
  on launch for every existing user. `MarbleMigrationPlan.stages` is `[]` today and must stay
  `[]` unless a change is genuinely destructive (a renamed or removed property, a type change),
  which is the only case that warrants a custom stage.
  Also never convert `SprintPrescription`/`SprintGoalSnapshot` raw-UUID references into
  `@Relationship`s — relationship churn resurrects the same checksum trap.
- **Do not put `@Dependency` in an `AppIntent` here.** It traps unless the access happens
  inside the system's perform flow, and Marble's intent suites call `perform()` directly.
  `AppIntentsSupport.register(container:)` populates `AppDependencyManager` anyway; the intents
  read `AppIntentsSupport.resolvedContainer()`. Tried and reverted 2026-07-25 — see
  `MarbleAppIntents.swift`.
- **The app, widget, unit-test and snapshot-test targets build under the Swift 6 language
  mode (`SWIFT_VERSION = 6.0`) as of build 49.** `MarbleUITests` deliberately stays on 5.0:
  XCUITest's `NSPredicate`/`XCUIElement` surface is not `Sendable`-annotated, and forcing the
  UI target over produced only "sending 'self'/'predicate'" noise in test scaffolding, not
  real findings. Migrate it when Apple annotates those APIs.
- The target sets `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so any Codable value type
  SwiftData serializes (e.g. `ExerciseMetricsProfile`) must be marked `nonisolated` — under
  the Swift 6 language mode this is a hard error, not a warning. The same rule now applies to
  every pure value type a `@Model` accessor touches: `Formatters`, `DateHelper`,
  `AppEnvironment`, `TestHooks`, `LifterAnalytics`, `TrendRange`, the sprint plan types, and
  the enums in `Models/` are all `nonisolated`. Two Swift 6 patterns worth knowing before you
  touch that code:
  - a non-`Sendable` value fetched on the main actor and then `await`ed on (ActivityKit's
    `Activity`, Core Spotlight's `CSSearchableIndex`) is *sent* across isolation. Fix it by
    moving the lookup **and** the await into one `nonisolated` helper — see
    `RestActivityController` and `ExerciseSpotlightIndex`.
  - `static var x = value` at global scope is an error; use a computed property (see
    `MarbleSchema`'s `versionIdentifier`) or `nonisolated(unsafe) static let` where the value
    genuinely is process-wide and immutable (`SharedDefaults.resolvedSuite`).
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
- Use: `make asc-builds`, `make asc-archive`, and
  `ASC_EXPORT_OPTIONS=$PWD/.asc/ExportOptions.plist make asc-export`. That plist **is tracked
  in git** (`.gitignore` ignores `.asc/*` with an explicit negation for it) because it carries
  the `provisioningProfiles` map for both bundle IDs; an options file without that map fails
  export with *"requires a provisioning profile with the HealthKit feature"*.
- Prefer `make asc-version` over raw `asc xcode version view`, because this project uses generated Info.plists and the helper prints a reliable `MARKETING_VERSION` fallback
- `make asc-archive` already bakes in the required `generic/platform=iOS` destination for this project
- The app target deploys to iOS `26.0` and needs an installed iOS 26.x simulator runtime. If `xcodebuild`/`asc` reports “no destinations”, install that platform/runtime from Xcode > Settings > Components before debugging further.

See `ASC.md` for the fuller Marble-specific command reference.
