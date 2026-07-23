# asc cli reference

This repo is wired for `asc` around Marble's real App Store Connect app and
deterministic local artifact paths, so future Codex sessions should start here
instead of re-discovering the release setup.

## Current Baseline

- Installed CLI checked on 2026-06-18: `asc 1.4.1`
- Install source: Homebrew `homebrew/core/asc`
- Public CLI docs: https://docs.asccli.sh/
- CLI project: https://github.com/rorkai/App-Store-Connect-CLI
- Apple App Store Connect API docs: https://developer.apple.com/documentation/appstoreconnectapi
- Apple upload guidance: https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds

Use `asc --help` and `asc <command> --help` as the source of truth. The CLI
docs explicitly recommend this because command surfaces move faster than
project-local notes.

## Marble Defaults

- App Store Connect app name: `marble.fit`
- App Store Connect app ID: `6757725234`
- Bundle ID: `Prism.marble`
- Widget extension bundle ID: `Prism.marble.MarbleWidgets`
- Xcode project: `marble.xcodeproj`
- Scheme: `marble`
- Team ID: `L49MKXGVM4`
- Archive path: `.asc/artifacts/marble.xcarchive`
- IPA path: `.asc/artifacts/marble.ipa`
- Platform: `IOS`
- Live App Store version: `2.1` (build 40), released 2026-07-21
- Working project version: `2.2` (build 46); version review and validation should use `2.2`

## Release Safety

- Read `RELEASE_HANDOFF.md` before changing review state, build numbers, or
  release branches. It is the dated source of truth; this file is the command reference.
- **State as of 2026-07-22:** `2.1` (build 40) is live on the App Store
  (`READY_FOR_DISTRIBUTION`). `2.2` (build 45, buildId
  `685b7870-70ac-4b5c-b686-e0bd607c9c26`) is on TestFlight, `VALID`,
  `IN_BETA_TESTING`, and **not submitted to App Review**. Build 46 is the prepared candidate.
  There is no in-flight review.
  `origin/release/1.9` may still point at the older `1.9 (build 20)` baseline unless
  explicitly updated.
- Always run `make asc-version` before acting — the CLI can report a blank generated
  marketing version, so the Makefile prints a reliable fallback.
- Do not cancel an in-flight review, upload a replacement build, or submit to
  review without explicit user approval.
- Build numbers must move forward from App Store Connect state. Use
  `make asc-next-build`, not local guesses.
- Regenerate `.asc/artifacts/marble.xcarchive` and `.asc/artifacts/marble.ipa`
  from a clean branch for every release. Do not reuse stale artifacts.
- The 2026-06-22 Live Activity wiring adds the `MarbleWidgets` app-extension target.
  Archive/export now needs an App Store provisioning profile mapping for both
  `Prism.marble` and `Prism.marble.MarbleWidgets`.

## Apple Rules That Matter Here

- App Store Connect API access requires API keys from App Store Connect, and
  Account Holder/Admin roles are needed for team key management.
- API calls use JWT auth; protect `.p8` private keys like any other production
  credential.
- Apple says app binaries are uploaded through Xcode, Transporter, altool, or
  build-upload flows. After upload, builds must finish Apple processing before
  they appear for TestFlight or App Store actions.
- The API affects real production App Store Connect data, so release commands
  should dry-run first when available and require explicit `--confirm` for
  submit/review mutations.
- When Apple reports an expired or missing agreement, CLI/auth can be locally
  healthy while API calls still fail until the Account Holder signs the updated
  agreement in App Store Connect.

## Fast Start

Use the repo shortcuts first:

```bash
make asc-auth
make asc-doctor
make asc-app
make asc-builds
make asc-version
make asc-status
make asc-review
make asc-validate
make asc-next-build
```

Those targets already know the Marble app ID, scheme, project path, artifact
paths, the required archive destination wiring, and the marketing-version
fallback for this Xcode setup. `make asc-review` and `make asc-validate` use
`ASC_APPSTORE_VERSION` (should be `2.2`); `make asc-next-build` and
`make asc-publish-testflight` use `ASC_TESTFLIGHT_VERSION` (defaulting to the local
marketing version, currently `2.2`) for the next upload number.

## New Machine Checklist

1. Upgrade `asc`.
2. Confirm auth storage and network validation.
3. Confirm Xcode has the required iOS platform installed.
4. Confirm `.asc/ExportOptions.plist` is present (it is tracked in git, so a clean clone has it).
5. Confirm Apple agreements are current.
6. Confirm signing/provisioning exists for the containing app and widget extension.

Recommended checks:

```bash
brew update && brew upgrade homebrew/core/asc
asc --version
make asc-auth
make asc-doctor
make asc-version
```

If archive or test commands report "no destinations" or say an iOS platform is
not installed, fix Xcode first:

- Open Xcode
- Go to Settings > Components
- Install the required iOS platform/runtime

CLI equivalent on Xcode 26:

```bash
xcodebuild -downloadPlatform iOS
```

## Repo-Specific Commands

### Check Auth And App Wiring

```bash
make asc-auth
make asc-doctor
make asc-app
```

Direct equivalents:

```bash
asc auth status --validate --output json --pretty
asc auth doctor --output json --pretty
asc apps list --bundle-id "Prism.marble" --output json --pretty
```

`make asc-auth` validates against Apple. If it reports a missing/expired
agreement, the local key can still be complete and valid; the Apple account
holder has to accept the agreement before live API reads, uploads, or releases
can proceed.

### View Recent Marble Builds

```bash
make asc-builds
```

Direct equivalent:

```bash
asc builds list --app "6757725234" --sort -uploadedDate --limit 10 --output table
```

### View Local Project Version And Build

```bash
make asc-version
```

Direct equivalent:

```bash
asc xcode version view --project marble.xcodeproj --target marble --output json --pretty
```

`asc xcode version view` reads the build number correctly here, but it can still
return a blank marketing version because the project uses generated Info.plists.
`make asc-version` prints a `marketingVersionFallback=...` line by reading the
canonical `MARKETING_VERSION` from `marble.xcodeproj/project.pbxproj`.

Use `asc xcode version --help` before editing or bumping versions.

### Release Status And Readiness

```bash
make asc-status
make asc-review
make asc-validate
make asc-next-build
```

Direct equivalents:

```bash
asc status --app "6757725234" --output table
asc review status --app "6757725234" --version "2.2" --platform IOS --output table
asc review doctor --app "6757725234" --version "2.2" --platform IOS --output table
asc validate --app "6757725234" --version "2.2" --platform IOS --output table
asc builds next-build-number --app "6757725234" --version "2.2" --platform IOS --output table
```

`asc validate` is the canonical App Store submission readiness report in the
current CLI. `asc review status` and `asc review doctor` are better for review
state and blocker diagnosis.

For the next TestFlight build on the 2.2 train, use `make asc-next-build`; it reads
`MARKETING_VERSION` from the project and reconciles processed builds plus uploads. Build 45
is already uploaded, so the prepared project uses **46** — but always use the freshly reported number rather
than a local guess.

### Create A Deterministic Archive

```bash
make asc-archive
```

Direct equivalent:

```bash
asc xcode archive \
  --project marble.xcodeproj \
  --scheme marble \
  --configuration Release \
  --archive-path .asc/artifacts/marble.xcarchive \
  --overwrite \
  --xcodebuild-flag=-destination \
  --xcodebuild-flag=generic/platform=iOS \
  --output json --pretty
```

Why the extra destination flags matter:

- This project needs an explicit generic iOS destination for `archive`.
- Without it, `xcodebuild` can fail with "Found no destinations".

## Export, TestFlight, And App Store Publishing

**`.asc/ExportOptions.plist` is tracked in git** (as is `.asc/UploadExportOptions.plist`).
`.gitignore` ignores `.asc/*` and negates those two, because without them `make asc-export`
fails on a fresh clone. Everything else under `.asc/` — archives, IPAs, metadata — stays
ignored.

Use the committed file; do not hand-roll one. It maps both `Prism.marble` and
`Prism.marble.MarbleWidgets` to the two pinned profiles and sets
`signingCertificate = Apple Distribution`. An options file **without** a `provisioningProfiles`
map fails with *"requires a provisioning profile with the HealthKit feature"*, because manual
signing will not infer profiles from the archive.

### Low-Level Export

```bash
ASC_EXPORT_OPTIONS=$PWD/.asc/ExportOptions.plist make asc-export
```

Direct equivalent:

```bash
asc xcode export \
  --archive-path .asc/artifacts/marble.xcarchive \
  --export-options .asc/ExportOptions.plist \
  --ipa-path .asc/artifacts/marble.ipa \
  --overwrite \
  --output json --pretty
```

### The Sequence Used Through Build 44

This is the path that actually works on this project — prefer it over
`make asc-publish-testflight`, whose betaGroups step flaps:

```bash
make asc-archive
ASC_EXPORT_OPTIONS=$PWD/.asc/ExportOptions.plist make asc-export
asc publish testflight \
  --ipa "$PWD/.asc/artifacts/marble.ipa" \
  --app 6757725234 \
  --group "test group A" \
  --wait
```

### Canonical TestFlight Publish

Use the current high-level TestFlight path when you want one command to build,
export, upload, wait for processing, and add the build to a group:

```bash
make asc-publish-testflight \
  ASC_EXPORT_OPTIONS=$PWD/.asc/ExportOptions.plist \
  ASC_TESTFLIGHT_GROUP="test group A"
```

Current phone-test state as of 2026-07-22:

- Build `2.2 (45)` is `VALID` and `IN_BETA_TESTING` in TestFlight:
  `685b7870-70ac-4b5c-b686-e0bd607c9c26`.
- Build `2.2 (46)` is the prepared candidate; `make asc-next-build` currently reports `46`.
- Internal group `test group A` (`514a95e2-28fc-436b-b624-9aaec2963adc`) has
  `hasAccessToAllBuilds = true`, so no explicit per-group add is required.
- External beta remains unsubmitted.

Useful verification commands:

```bash
asc builds build-beta-detail view \
  --build-id "685b7870-70ac-4b5c-b686-e0bd607c9c26" \
  --output json --pretty

asc testflight groups view \
  --id "514a95e2-28fc-436b-b624-9aaec2963adc" \
  --output json --pretty

asc testflight groups links view \
  --group-id "514a95e2-28fc-436b-b624-9aaec2963adc" \
  --type betaTesters \
  --output json --pretty
```

For external beta review submission:

```bash
make asc-publish-testflight \
  ASC_EXPORT_OPTIONS=$PWD/.asc/ExportOptions.plist \
  ASC_TESTFLIGHT_GROUP="External Testers" \
  ASC_TESTFLIGHT_FLAGS="--submit --confirm"
```

### Canonical App Store Publish

Attaching another build or submitting for review is a release mutation. Do not run this
target without explicit approval and a clean release branch. The target intentionally
requires `ASC_APPSTORE_PUBLISH_VERSION` so it cannot silently publish the local marketing
version.

As of 2026-07-22 there is **no in-flight review**. `2.1` (build 40) is released; `2.2`
(build 45) is on TestFlight and has not been submitted. Submitting 2.2 needs explicit
approval — see "Open release decisions" in `RELEASE_HANDOFF.md`.

Dry-run first when possible:

```bash
make asc-publish-appstore \
  ASC_EXPORT_OPTIONS=$PWD/.asc/ExportOptions.plist \
  ASC_APPSTORE_PUBLISH_VERSION=2.2 \
  ASC_APPSTORE_SUBMIT_FLAGS="--dry-run"
```

Build/upload/attach without submission:

```bash
make asc-publish-appstore \
  ASC_EXPORT_OPTIONS=$PWD/.asc/ExportOptions.plist \
  ASC_APPSTORE_PUBLISH_VERSION=2.2
```

Submit for App Review after validation:

```bash
make asc-publish-appstore \
  ASC_EXPORT_OPTIONS=$PWD/.asc/ExportOptions.plist \
  ASC_APPSTORE_PUBLISH_VERSION=2.2 \
  ASC_APPSTORE_SUBMIT_FLAGS="--submit --confirm"
```

`asc publish appstore --submit --confirm` is the canonical full App Store path
for the current CLI. Use `asc release stage` for metadata/build preparation
without submission, and `asc review submit` only when a version is already
prepared and a processed build ID is known.

### Release An Approved Version

Approval is not release. A version that clears review with manual release configured sits at
`PENDING_DEVELOPER_RELEASE` until you push it live:

```bash
asc versions list --app "6757725234" --output json --pretty   # find the version id
asc versions release --version-id <appStoreVersion id> --confirm
```

That is exactly how `2.1` went live on 2026-07-21 (version id
`59f2e4c7-1c4b-49b3-a5d3-265ca6da74b1`), moving it to `READY_FOR_DISTRIBUTION`.

⚠️ **Check for a phased release *before* you run this.** 2.1 had
`appStoreVersionPhasedRelease = null`, so it went to 100% of users instantly. If you want a
staged rollout, create it before releasing — you cannot retrofit one afterwards.

## Helpful Low-Level Commands

Use `--help` instead of memorizing flags:

```bash
asc --help
asc xcode archive --help
asc xcode export --help
asc builds upload --help
asc publish testflight --help
asc publish appstore --help
asc review submit --help
asc versions release --help
asc validate --help
```

Useful direct commands:

```bash
asc builds list --app "6757725234" --version "2.2"
asc testflight groups list --app "6757725234"
asc status --app "6757725234"
```
