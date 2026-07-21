# Marble — H2 2026 Implementation Plan (written 2026-07-20)

> **STATUS 2026-07-20 — Phases 0–3 are implemented and on `main` as 2.2 (build 41).**
> Unit suite green, accessibility audit green, UI suite 43/44 (the one failure,
> `test07TrainingCalendar`, reproduces on clean `origin/main` — see TESTING.md).
>
> | Phase | State |
> |---|---|
> | 0 — ship & tidy | Repo work **done** (version bump, PRs #2/#11 closed). **2.1 still needs its manual App Store release — that is Enzo's button.** |
> | 1 — 2.2 Ambient | **Done.** Weekly Goal widget, interactive rest Live Activity, Control Center control, onboarding, Settings, TipKit defined. |
> | 2 — 2.3 Siri & Spotlight | **Done.** `ExerciseEntity`+`IndexedEntity`, `LogSetIntent`, start/finish workout intents, 5 App Shortcuts. |
> | 3 — 2.4 Body | **Done.** Schema V5 `BodyMetricEntry`, Health bodyweight import, DOTS, Trends section. |
> | 4 — 3.0 Watch | **Not built — deliberately.** See "Why Phase 4 was not built" below. |
>
> **Two portal steps gate archiving** (`RELEASE_HANDOFF.md` has the detail): create the
> App Group `group.Prism.marble` and regenerate both distribution profiles.
>
> Phases 1–3 were collapsed into a single 2.2 train rather than three releases. That was a
> deliberate call to get one TestFlight build covering all of it; the phase structure below
> still describes how the work was sequenced and why.
>
> ## Why Phase 4 was not built
> The watch app is the one item here that cannot be honestly finished in this environment:
> it needs a **new App ID and distribution profile created in the portal** (same blocker
> class as the App Group, but for a target that does not exist yet), and its core —
> `HKWorkoutSession` mirroring, double-tap set logging, water lock — is **device-only** and
> untestable on the simulator. Scaffolding a watch target that cannot be run, signed, or
> verified would add a broken target to `main` and a false sense of progress. The design in
> Phase 4 below is unchanged and remains the right shape; it wants a session with a device
> and portal access, ideally alongside the watchOS 27 GM in September.

Source of truth for the five-workstream roadmap pitched 2026-07-20: Watch app, widget surface,
App Intents depth, body metrics, onboarding/settings. Sequenced into releases 2.2 → 2.3 → 2.4 → 3.0.
Baseline: main = 2.1 build 40; App Store 2.0 LIVE; 2.1 approved, `PENDING_DEVELOPER_RELEASE`.

Conventions: every phase ends with `make unit` green in CI, `make migration-release` when schema
changes, TestFlight via `make asc-*`, PR to main (no direct pushes). Never `git add -A`
(untracked `marketing/`, `work/`). Stage files explicitly.

---

## Phase 0 — Ship & tidy (this week, no build work)

1. **Release 2.1** in App Store Connect (manual release button; consider phased release ON since
   2.1 carries the sessions data-model surface).
2. After release: bump `MARKETING_VERSION` → 2.2, `CURRENT_PROJECT_VERSION` → 41 on main;
   update `RELEASE_HANDOFF.md`; set `ASC_APPSTORE_VERSION` default in Makefile.
3. **Close PR #11** — its fix is already on main as `7d41217` (verify `gh pr diff 11` is empty
   vs main first). **Close PR #2** (the mistitled Empire-removal trap; its one useful commit is
   already on main as `e1ace7b`).
4. Re-verify the 07-14 defect list against main and fix any survivor in 2.2:
   Focus-card default-state CTA (`TrendsView`), `SeedData` recovery guard
   (`exerciseCount == 0` check nested inside `if !didSeed` — empty library after store recovery),
   sprint-goal stale-freeze on Duplicate/Repeat/Siri paths. (Session cancel + full backup
   round-trip appear already fixed on main — confirm, don't assume.)

---

## Phase 1 — Release 2.2 "Ambient Marble" (~2 weeks)

Widgets, interactive rest timer, Control Center, onboarding, Settings, TipKit.

### 1A. One-time manual portal work (Enzo, ~30 min — blocks everything else)

1. developer.apple.com → Identifiers → App Groups → create **`group.Prism.marble`**.
2. Edit both App IDs (`Prism.marble`, `Prism.marble.MarbleWidgets`): enable App Groups
   capability, assign the group.
3. Regenerate BOTH App Store distribution profiles (regeneration invalidates the pinned ones):
   note the new names — they replace the hardcoded `PROVISIONING_PROFILE_SPECIFIER` strings in
   pbxproj (app Release L731 `Prism marble App Store HealthKit 2026-06-18-2015`; widget Release
   L795 `Prism marble MarbleWidgets App Store 2026-06-22 build 23`). Download/install both.
4. Xcode side (agent can do): add `com.apple.security.application-groups` =
   `[group.Prism.marble]` to `marble.entitlements`; create `MarbleWidgets/MarbleWidgets.entitlements`
   with the same key; set `CODE_SIGN_ENTITLEMENTS` on the widget target; update both Release
   profile specifiers. Debug configs are Automatic and self-heal.

### 1B. Shared state plumbing (no store move — deliberate)

- **Do NOT move the SwiftData store into the App Group container.** The recovery machinery
  (`makeRecoveringContainer`, corrupt-store rename, `PersistenceRecoveryNotice`) is pathed to
  `applicationSupportDirectory/Marble/Marble.store` and a store relocation is pure risk with zero
  2.2 benefit. Widgets consume an **app-pushed snapshot**, not live queries.
- New `marble/Components/SharedDefaults.swift`: `enum SharedDefaults` wrapping
  `UserDefaults(suiteName: "group.Prism.marble")` with a one-time migration (guarded by a
  `didMigrateSharedDefaultsV1` key) of `weeklySessionTarget` + `weeklyGoalReminderEnabled` from
  `.standard`. Keep `@AppStorage` call sites working via
  `@AppStorage("weeklySessionTarget", store: SharedDefaults.suite)`.
- New `marble/Features/Trends/WeeklyGoalWidgetState.swift` (member of BOTH app + widget targets,
  like `RestTimerAttributes`): small `Codable` struct — target, thisWeekSessions, streakWeeks,
  flexTokens, `GoalState` raw value, weekStart date, generatedAt. Pure
  `init(snapshot: TrainingConsistency.Snapshot, weekStart: Date)`.
- Writer: after every successful save that touches `SetEntry` and on `scenePhase` transitions
  (extend the existing `ContentView.swift:73` `.onChange(of: scenePhase)` block), encode state
  JSON into shared defaults + `WidgetCenter.shared.reloadTimelines(ofKind: "WeeklyGoalWidget")`.
  Centralize in a `WeeklyGoalWidgetPublisher` enum; call from `saveOrRollback` success path is
  too hot — hook the same places `WeeklyGoalReminder.sync` already runs.

### 1C. Weekly Goal widget

- `MarbleWidgets/WeeklyGoalWidget.swift`: kind `"WeeklyGoalWidget"`, families
  `.systemSmall/.systemMedium/.accessoryCircular/.accessoryRectangular/.accessoryInline`.
  `TimelineProvider` reads the snapshot; timeline entries at day boundaries + week rollover
  (state degrades gracefully to "Open Marble" placeholder when snapshot is stale >8 days).
  Ring gauge (small/circular), streak + flex tokens + "2 of 3 days" (medium/rectangular).
  Match Liquid Glass content rules: no glass on widget content, standard widget background.
- Deep link: `.widgetURL(URL(string: "marble://trends"))`. App side: register `marble` URL
  scheme in Info plist keys (`INFOPLIST_KEY` route or Info.plist), handle in `ContentView`
  `.onOpenURL` → `tabSelection.selected = .trends`.

### 1D. Interactive rest Live Activity + Control Center

- New intents in the **app target** (LiveActivityIntents execute in the app's process):
  `ExtendRestIntent` (+30 s) and `EndRestIntent` in `marble/Intents/RestIntents.swift`,
  calling `RestActivityController.shared.extend(by: 30)` / `.cancelRest()`.
- `RestActivityController`: add `func extend(by seconds: TimeInterval)` — recompute
  `activeRest.endsAt`, update the Activity content, reschedule `endTask`. Unit tests alongside
  the existing pure helpers (`shouldStart`, `restEndDate`).
- `RestTimerLiveActivity`: `Button(intent:)` pair in the lock-screen view + Dynamic Island
  expanded bottom region. Keep the existing `Text(timerInterval:)` countdown.
- `MarbleWidgetsBundle`: add `ControlWidget` `QuickLogControl` (`ControlWidgetButton` running
  `OpenQuickLogIntent` — it's `openAppWhenRun`, valid from a control) so "Log a set" is mappable
  in Control Center / Lock Screen / Action button.
- **Test-harness guard (learned the hard way in build 30):** anything touching tab-bar or
  lock-screen chrome perturbs the a11y audit. All new surfaces must respect
  `TestHooks.isUITesting` exactly like `marbleRestPillAccessory` does; TipKit (1F) must be
  disabled under UI testing.

### 1E. Onboarding + Settings

- `marble/Features/Onboarding/OnboardingFlow.swift`, gated by shared-defaults key
  `didCompleteOnboarding` (seed to `true` for existing users — gate on
  `didSeedMarbleData == true` at migration time so current users never see it). Three pages:
  1. What Marble is — private, on-device, no account (the brand pitch).
  2. Weekly goal picker → writes `weeklySessionTarget`.
  3. **Default weight unit picker** → new shared key `preferredWeightUnit` (`lb`/`kg`).
- `AddSetView.swift:20`: replace hardcoded `= .lb` with the preference (last-used-per-exercise
  override at L870 stays — it's correct). This shrinks the mixed-unit precondition behind the
  recurring lb/kg bug class at its source. Do the grep sweep of every weight comparison/sum when
  touching this (see AGENTS gotchas).
- `marble/Features/Settings/SettingsView.swift`: units, weekly goal, notifications (embed the
  existing `NotificationsView` route), Health auto-import + session export toggles (reuse the
  service APIs; keep the Import-screen toggles too — same `@AppStorage` keys, no drift),
  Data & Backups (link to `DataManagementView`), privacy explainer, version footer. Entry point:
  replace the Workout-tab toolbar's direct DataManagement gear with Settings (DataManagement one
  level deeper). UI test: settings smoke + onboarding flow (launch with `MARBLE_RESET_DB=1`
  + new `MARBLE_FORCE_ONBOARDING=1` TestHook).
- TipKit: `Tips.configure()` in `marbleApp` (skip when `TestHooks.isUITesting`); three tips —
  scan button (Import), coaching cards (Trends), PR feed. Invalidate each on first interaction.

### 1F. Ship

- New unit tests: shared-defaults migration, `WeeklyGoalWidgetState` mapping, `extend(by:)`,
  onboarding gating, preferred-unit default. Snapshot: widget views through `SnapshotMatrix`
  at widget sizes (new suite; remember baselines are recorded on the canonical host only).
- `make unit` + `make ui` + `make audit` locally; screenshots refresh (widget + onboarding
  frames) via the `MARBLE_FIXTURE_MODE=screenshots` rig; TestFlight
  `make asc-archive asc-export` then `asc publish testflight --ipa … --app 6757725234 --group …`
  retry loop (betaGroups endpoint flaps); App Store 2.2 with whatsNew centered on
  widgets + onboarding.

---

## Phase 2 — Release 2.3 "Siri & Spotlight" (~1–2 weeks)

App Intents depth. All work in `marble/Intents/`, sharing `AppIntentsSupport.resolvedContainer()`.

1. **`ExerciseEntity: AppEntity`** (`ExerciseEntities.swift`): id = Exercise UUID,
   `DisplayRepresentation` = name + category subtitle, `ExerciseQuery: EntityStringQuery`
   (name-contains fetch; `suggestedEntities()` = favorites first, then recent by last
   `performedAt`). Conform to `IndexedEntity` so exercises enter Spotlight's semantic index
   (this is the new-Siri integration path).
2. **`LogSetIntent`** — parameters: exercise (`ExerciseEntity`), reps (Int?), weight (Double?),
   unit (AppEnum over `WeightUnit`?). Defaults resolve from that exercise's latest `SetEntry`
   (same duplication logic as `LogLastSetAgainIntent`, including `SprintGoalSnapshot` copy and
   `saveOrRollback` semantics). Returns dialog + a `SnippetView` (set summary + PR-proximity
   line via `PersonalRecords.projectedBadge`). Respect `ExerciseMetricsProfile.inputWeight`
   (dumbbell-pair doubling) — a raw write would corrupt volume.
3. **`StartWorkoutIntent` / `FinishWorkoutIntent`** — insert/end a `WorkoutSession` (guard: no
   second active session — reuse the ContentView active-session resolution, don't duplicate its
   `?? activeSessions.first` bug class). `openAppWhenRun = true` for Start in 2.3; when the
   iOS 27 SDK lands, adopt `LongRunningIntent` + progress-as-Live-Activity under `#available`.
4. Update `MarbleShortcuts`: phrases for the new intents (≤10 App Shortcuts total),
   `shortcutTileColor`.
5. Optional fast-follow: `systemSmall` "Log again" interactive widget —
   `Button(intent: LogLastSetAgainIntent())` (that intent is headless; move/mark it visible to
   the widget target or route through an `ExecutionTargets` split when on 27).
6. Tests: intent unit tests against in-memory container (`TestHooks.useInMemoryStore` path in
   `AppIntentsSupport.resolvedContainer()` already supports this); entity-query ranking tests;
   dialog-content tests. UI-test one end-to-end path via `MARBLE_OPEN_QUICK_LOG`-style hook.

---

## Phase 3 — Release 2.4 "Body" (~2 weeks; first schema bump since V4)

1. **Schema V5** exactly per the `MarbleSchema.swift` header recipe: new `@Model`
   `BodyMetricEntry` — id (UUID), `measuredAt: Date`, `weightKilograms: Double` (canonical kg,
   ALWAYS — display converts; this model never stores mixed units), `bodyFatPercent: Double?`,
   `source: BodyMetricSource` (manual/healthKit), `healthKitUUID: UUID?` (dedup), notes.
   `MarbleSchemaV5.models = V4.models + [BodyMetricEntry.self]`, `Version(5,0,0)`; append to
   `MarbleMigrationPlan.schemas`, **stages stay `[]`** (additive/lightweight); bump the single
   line `Schema(versionedSchema:)` in `ModelContainer.swift` (~L47). Raw-UUID reference style,
   no `@Relationship` to Exercise/SetEntry (relationship churn is what resurrects the build-35
   checksum crash). Gates: `make migration-release` + the populated-store migration test + a new
   V4→V5 case in `PersistenceRecoveryTests`.
2. **HealthKit read**: `HealthBodyMetricsProvider` modeled on `HealthKitWorkoutProvider` —
   anchored query on `bodyMass` (+ `bodyFatPercentage`), dedup by HK sample UUID, opt-in key
   `marble.health.bodyMetricsEnabled`, synced from the same `scenePhase == .active` block.
   Add the two read types to the authorization set.
3. **UI**: quick weight entry (Settings + Trends bodyweight section header button);
   bodyweight trend chart section in Trends (new `TrendsPalette` accent, memoized through
   `TrendsDerivedData` like everything else); Calendar `DaySummarySheet` shows weight-on-day
   next to progress media.
4. **Relative strength**: DOTS in `LifterAnalytics` — pure function
   `dots(totalKg:bodyweightKg:isFemale:)` with golden-value unit tests; nearest-in-time
   bodyweight lookup (≤14-day window, else omit). Surface on the e1RM section as a secondary
   line only when bodyweight data exists. `MonthlyReport` gains bodyweight delta facts
   (precomputed — the FM model still never does arithmetic).
5. **lb/kg discipline** (4 historical bugs): every new comparison/sum goes through kg
   canonicalization; add a `WeightNormalizationTests` case per new call site; grep sweep
   `weight *` / `+= weight` before merge.

---

## Phase 4 — 3.0 "Marble for Apple Watch" (~4–6 weeks, overlapping; ship with iOS/watchOS 27 GM ~Sept)

**Architecture: live-session companion, phone is the only SwiftData truth. No CloudKit.**

1. **Target setup**: new watchOS app target (SwiftUI, watchOS 26 min → 27 at GM if FM-on-watch
   makes the cut), bundle `Prism.marble.watchkitapp`, team L49MKXGVM4. Debug Automatic;
   Release needs a new watch App ID + distribution profile (same portal session as 1A ideally).
   Watch entitlements: HealthKit. Share pure-logic files by target membership
   (`PersonalRecords`, `TrainingConsistency`, `LifterAnalytics`, enums, `WeeklyGoalWidgetState`);
   no SwiftData store on watch in v1.
2. **Session engine**: watch runs `HKWorkoutSession` (`.traditionalStrengthTraining`, indoor) +
   `HKLiveWorkoutBuilder`; mirror to iPhone via `startMirroringToCompanionDevice`; iPhone
   registers `workoutSessionMirroringStartHandler`. Set logging on watch →
   `sendToRemoteWorkoutSession(data:)` with a small Codable `WatchSetMessage` (exerciseID, reps,
   weightKg, unit, RPE, timestamp); phone decodes → inserts `SetEntry` via the existing
   `saveOrRollback` path → session mirrors state back. Phone-initiated sessions mirror to watch
   the same way. On session end, the existing `HealthSessionExporter` dedup must recognize
   watch-built workouts (session UUID in `healthSessionExportedSessionIDs`) so we don't
   double-write HKWorkouts.
3. **Watch UX**: Start screen (today's split day via `WCSession.updateApplicationContext`
   snapshot: planned sets + recent exercises + preferred unit); active screen = current
   exercise, reps/weight steppers (crown), one big **Complete Set** button carrying
   `.handGestureShortcut(.primaryAction)` (double-tap = complete set → rest starts); rest
   countdown screen (reuses rest-duration logic; the iPhone Live Activity auto-surfaces in the
   watch Smart Stack on 27 — in-session watch UI owns the timer instead); water-lock toggle
   (`WKInterfaceDevice.current().enableWaterLock()`) for bar-brush protection; finish/discard.
4. **Watch widgets**: Smart Stack weekly-goal widget (reuse `WeeklyGoalWidgetState` — needs the
   snapshot mirrored to watch via applicationContext, not App Group), `ControlWidget` for the
   Action button = Start Workout.
5. **iOS 27 pickups (3.0.x / 3.1, post-GM)**: HealthKit workout zones
   (`HKLiveWorkoutBuilderDelegate.didUpdateWorkoutZone`) on watch cardio/sprints — note these
   APIs do not compile on the 26.x SDK, gate on Xcode 27; FoundationModels-on-watch end-of-set
   feedback (availability-gated, deterministic fallback, same TrainingInsights rules);
   `LongRunningIntent` for StartWorkout; extra-large widget family.
6. **Testing reality**: pure logic stays in the iPhone unit suite; watch flows are device-QA
   (HealthKit + FM are device-only per repo docs). Add a `WatchSetMessage` codec round-trip
   unit test and a mirroring state-machine test with a fake session. Manual QA script into
   `TESTING.md`.

---

## Cross-cutting risks (from repo history — read before starting any phase)

- **Profiles are pinned by name in pbxproj** — every capability/target change means portal
  regeneration + updating two (soon four) specifier strings. Batch portal work.
- **Never convert `SprintPrescription`/`SprintGoalSnapshot` UUID refs into relationships**
  (schema checksum trap); V5 additions must be additive-only.
- **Container `.accessibilityIdentifier` clobbers children** (bit twice) — keep ids on leaf
  rows in all new Settings/Onboarding/Widget views.
- **Tab-bar-adjacent chrome breaks the a11y audit** (`tabViewBottomAccessory` precedent) —
  gate every new system surface behind `TestHooks` like the rest pill.
- **Snapshot baselines are host-stale**; gate releases on `make unit` + UI, record baselines
  only on the canonical host.
- **Sims are shared with concurrent agent sessions** — never `simctl shutdown all`, never
  `pkill CoreSimulatorService`; verify UI failures in isolation with `make only TEST=…`.
- **ASC betaGroups endpoint flaps** — prebuild IPA, retry `asc publish testflight` with
  `--app 6757725234`.
- **lb/kg**: canonical-kg for every new stored/compared weight, test per call site.
