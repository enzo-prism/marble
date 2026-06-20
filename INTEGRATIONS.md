# Marble Workout Import

How Marble pulls workouts in from other services, how each integration works, and **why
it's built this way**. If you only read one file about the import feature, read this one.

---

## The idea

Marble is a workout + supplements journal, but it's also a **thin, beautiful UI layer over
fragmented workout data**. People's training lives in different places — an Apple Watch, a
Garmin watch, Strava — and none of them is a great place to *review* it. Marble lets you
pull the workouts you care about into one calm, consistent journal.

Four principles shape every integration:

1. **ToS-aligned, always.** Every source uses an officially sanctioned path. No
   reverse-engineering, no scraping, no handling of other services' passwords.
2. **No backend.** Marble is local-only. Every integration runs entirely on-device.
3. **User-chosen, not automatic.** You connect a source, load recent workouts, pick the
   ones you want, and they become journal entries. Nothing is silently synced.
4. **Only what helps.** We import workout *summaries* that improve the journal (type, date,
   distance, duration, calories, heart rate) — not GPS tracks, raw streams, or social data.

---

## How it's wired

All sources share one small abstraction so the UI and import logic never depend on a
specific service.

| Piece | File | Role |
|---|---|---|
| `WorkoutImportProvider` | `WorkoutImportProvider.swift` | Protocol: `authorizationStatus()`, `authorize()`, `fetchWorkouts(in:)` |
| `WorkoutImportRecord` | `WorkoutImportRecord.swift` | A normalized workout (source, externalID, date, kind, distance, duration, calories, HR, **originName**, strengthSets) |
| `WorkoutImporter` | `WorkoutImporter.swift` | Dedup + persistence. Skips anything already imported. |
| `WorkoutImportMapper` | `WorkoutImportMapper.swift` | Turns a record into `SetEntry`s (and resolves/creates `Exercise`s) |
| `ImportedWorkout` | `Models/ImportedWorkout.swift` | The dedup ledger. A DB-unique `deduplicationKey` (`"<source>:<externalID>"`) makes re-imports a no-op even under races. |
| `ImportViewModel` / `ImportView` | `ImportViewModel.swift` / `ImportView.swift` | One section per connected source; load, select, import. |

To add a source, you implement `WorkoutImportProvider` and map its activities into
`WorkoutImportRecord` — nothing else needs to change. See **Adding a source** below.

---

## The sources

### 1. Apple Health — the universal bridge (always on)

`HealthKit/HealthKitWorkoutProvider.swift`

Apple Health is the keystone. Garmin, Strava, Wahoo, Peloton, Zwift, and most fitness apps
can write workouts into HealthKit, so a **single** Health connection surfaces all of them.

- Read-only access to `HKWorkout` samples (`NSHealthShareUsageDescription`; we never write).
- Distance and active energy come straight off the workout; **average heart rate** is read
  separately via a discrete-average `HKStatisticsQuery` over each workout's time window (HR
  is stored as standalone samples, not a workout field), so Apple Watch and bridged sources
  alike get a `· NNN bpm avg` note.
- Each workout is labeled with its **true origin**: `originName(...)` inspects the HealthKit
  source name, bundle id, and device manufacturer and returns a recognizable brand
  ("Garmin", "Strava", "Apple Watch", …), falling back to the recording app's own name.
  That origin shows as a badge in the import list and in the saved note.

### 2. Garmin — through Apple Health (sanctioned, no credentials)

There is **no** Garmin code that talks to Garmin's servers, and that's deliberate:

- Garmin's *official* API (the Connect Developer Program: Activity/Health APIs) is a
  server-to-server design — it pushes data to a **webhook backend** and requires program
  approval. A local-only app with no backend can't use it.
- The *only* way to read Garmin directly on-device is to reverse-engineer Garmin's private
  login, which **violates Garmin's Terms of Service**. Marble does not do this.

So Garmin rides the sanctioned bridge: the user turns on **Garmin Connect → Apple Health**
(one time, in Garmin's own app), and their Garmin workouts then appear in Marble's Apple
Health list with a **"Garmin"** badge. The import screen shows a short explainer and an
**Open Garmin Connect** button to help users enable it.

> Trade-off: Apple Health carries workout **summaries**, not per-set strength detail
> (weight × reps). Lift-level Garmin data would require Garmin's official Activity API (FIT
> files) **plus a backend** — out of scope for this no-backend build.

### 3. Strava — direct, official OAuth 2.0

`Strava/StravaClient.swift`, `Strava/StravaProvider.swift`, `OAuth/`

Strava (unlike Garmin) has a real, on-device-friendly public API, so Marble connects to it
directly using Strava's official OAuth:

- `ASWebAuthenticationSession` opens Strava's consent screen → authorization code → token
  exchange → bearer token. Access/refresh tokens live in the **Keychain** and refresh
  automatically. Marble pulls `athlete/activities` **summaries** only.
- The redirect URI's scheme is claimed transiently by `ASWebAuthenticationSession`, so it
  needs **no** `CFBundleURLTypes` entry in the app.

**Enabling Strava (developer setup).** Strava stays hidden until its credentials are
present, so a build without keys never shows a dead "Connect" row. `StravaConfiguration.resolve`
reads keys from two sources, **environment first, then Info.plist**:

1. Create a free Strava API application at <https://www.strava.com/settings/api>.
2. Provide the keys one of two ways:
   - **Local development (no secrets in git):** set scheme environment variables
     `STRAVA_CLIENT_ID`, `STRAVA_CLIENT_SECRET`, `STRAVA_REDIRECT_URI`, optional
     `STRAVA_SCOPE` (Xcode ▸ Edit Scheme ▸ Run ▸ Arguments ▸ Environment Variables). These
     are read from `ProcessInfo` and never reach a TestFlight/App Store build.
   - **Release builds:** set the Info.plist keys `StravaClientID`, `StravaClientSecret`,
     `StravaRedirectURI` (e.g. `marblefit://strava-auth`), optional `StravaScope` — fed by an
     ignored `xcconfig` / `INFOPLIST_KEY_*` build setting so the keys stay out of source.
3. In the Strava API app, set **Authorization Callback Domain** to the redirect URI's host
   (e.g. `marblefit`).

Either path satisfies `isConfigured` (all three of client id / secret / redirect URI must be
non-empty); a blank or whitespace-only env var falls through to the Info.plist value.

> Caveat: Strava's token exchange requires `client_secret`. Shipping it in-app is the common
> indie compromise; for a hardened production build, run a tiny token-exchange proxy and
> point the exchange at it.

---

## What gets imported

A `WorkoutImportRecord` maps to one or more `SetEntry`s:

- **Cardio** (run/ride/swim/walk/hike) → a single distance + duration entry under the `Run`
  category, with calories and average HR captured in the note.
- **Strength** → if per-set detail is available, one entry per lift (exercise · weight ·
  reps); otherwise a single duration entry. *(Per-set detail isn't available through Apple
  Health, so today it applies only to sources that expose it.)*
- The note records the true origin, e.g. `Imported from Garmin · 320 kcal · 150 bpm avg`.

We intentionally **don't** import GPS tracks, per-second streams, photos, or social data.

---

## Privacy & security

- **Local-only.** The only network calls are Strava's OAuth/API requests; HealthKit is
  entirely on-device. Nothing is sent to Marble servers (there are none).
- **No credential storage.** For Strava we store only OAuth tokens (Keychain), never the
  password. For Garmin we never see credentials at all — Apple Health is the boundary.
- The privacy manifest (`marble/PrivacyInfo.xcprivacy`) declares no tracking and no data
  collection.

---

## Adding a source

1. Add a case to `ImportSource` (`Models/ImportedWorkout.swift`) with a display name + SF
   Symbol.
2. Implement `WorkoutImportProvider`. For an OAuth service, model it on `StravaProvider` /
   `StravaClient`; for a device/aggregator bridge, model it on `HealthKitWorkoutProvider`.
3. Map its activities to `WorkoutImportRecord` (a pure, unit-testable static function).
4. Register it in `ImportView.default()` — gate it on configuration if it needs credentials,
   so an unconfigured build hides the row.
5. Add mapping tests next to the others in `Tests/Unit/ImportProviderMappingTests.swift`.

Dedup, persistence, selection UI, origin labeling, and the journal mapping all come for free
from the shared spine.
