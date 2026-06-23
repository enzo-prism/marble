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
- Current App Store review version: `1.8`

## Release Safety

- Read `RELEASE_HANDOFF.md` before changing review state, build numbers, or
  release branches.
- The working project version is now `1.9 (build 26)` on `main`; `origin/release/1.9`
  may still point at the older `1.9 (build 20)` release baseline unless explicitly
  updated.
- The live App Store version is still `1.8` and is `WAITING_FOR_REVIEW`. No App Store
  version record exists for `1.9` yet, so review/validation checks must use `1.8`
  until that record is created.
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
`ASC_APPSTORE_VERSION` (currently `1.8`); `make asc-next-build` and
`make asc-publish-testflight` use `ASC_TESTFLIGHT_VERSION` (defaulting to the local
marketing version, currently `1.9`) for the next upload number.

## New Machine Checklist

1. Upgrade `asc`.
2. Confirm auth storage and network validation.
3. Confirm Xcode has the required iOS platform installed.
4. Confirm a usable `ExportOptions.plist` exists before export/upload.
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
asc review status --app "6757725234" --version "1.8" --platform IOS --output table
asc review doctor --app "6757725234" --version "1.8" --platform IOS --output table
asc validate --app "6757725234" --version "1.8" --platform IOS --output table
asc builds next-build-number --app "6757725234" --version "1.9" --platform IOS --output table
```

`asc validate` is the canonical App Store submission readiness report in the
current CLI. `asc review status` and `asc review doctor` are better for review
state and blocker diagnosis.

For the next TestFlight build on the 1.9 train, use `make asc-next-build` without
overriding `ASC_APPSTORE_VERSION`; it reads `MARKETING_VERSION` from the project and
currently reports the next 1.9 build number.

As of 2026-06-22 after uploading build `26`, the next 1.9 build number is `27`.
Before uploading another 1.9 TestFlight build, bump `CURRENT_PROJECT_VERSION` from
`26` to the reported next number and re-run `make asc-next-build` to confirm ASC
still agrees.

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

No `ExportOptions.plist` is committed in this repo on purpose. Keep
machine-specific signing/export files under `.asc/`, which is ignored.

### Low-Level Export

```bash
make asc-export ASC_EXPORT_OPTIONS=/absolute/path/to/ExportOptions.plist
```

Direct equivalent:

```bash
asc xcode export \
  --archive-path .asc/artifacts/marble.xcarchive \
  --export-options /absolute/path/to/ExportOptions.plist \
  --ipa-path .asc/artifacts/marble.ipa \
  --overwrite \
  --output json --pretty
```

### Canonical TestFlight Publish

Use the current high-level TestFlight path when you want one command to build,
export, upload, wait for processing, and add the build to a group:

```bash
make asc-publish-testflight \
  ASC_EXPORT_OPTIONS=/absolute/path/to/ExportOptions.plist \
  ASC_TESTFLIGHT_GROUP="Internal Testers"
```

Current phone-test state as of 2026-06-22:

- Build `1.9 (26)` is valid in TestFlight:
  `10ab692e-cffb-456b-b312-2c4dede738db`.
- Build beta detail reports `internalBuildState = IN_BETA_TESTING`.
- Internal group `test group A` (`514a95e2-28fc-436b-b624-9aaec2963adc`) has
  `hasAccessToAllBuilds = true`.
- Build `26` was uploaded with `--notify`, but the group already receives all builds,
  so the publish command skipped an explicit per-group add.

Useful verification commands:

```bash
asc builds build-beta-detail view \
  --build-id "10ab692e-cffb-456b-b312-2c4dede738db" \
  --output json --pretty

asc testflight groups list \
  --app "6757725234" \
  --internal \
  --output json --pretty

asc testflight groups links view \
  --group-id "514a95e2-28fc-436b-b624-9aaec2963adc" \
  --type betaTesters \
  --output json --pretty
```

For external beta review submission:

```bash
make asc-publish-testflight \
  ASC_EXPORT_OPTIONS=/absolute/path/to/ExportOptions.plist \
  ASC_TESTFLIGHT_GROUP="External Testers" \
  ASC_TESTFLIGHT_FLAGS="--submit --confirm"
```

### Canonical App Store Publish

Creating a 1.9 App Store version record, attaching a build, or submitting for review is a
release mutation. Do not run this target without explicit approval and a clean release
branch. The target intentionally requires `ASC_APPSTORE_PUBLISH_VERSION` so it cannot
silently publish the local marketing version.

As of 2026-06-22, App Store version `1.8` is still `WAITING_FOR_REVIEW`, so Apple rejects
creating a `1.9` App Store version with:

```text
You cannot create a new version of the App in the current state.
```

Build `1.9 (26)` is already uploaded and valid (`10ab692e-cffb-456b-b312-2c4dede738db`).
To submit it immediately, the active 1.8 review submission must first be explicitly
canceled:

```bash
asc submit cancel \
  --id "9be18cb3-defb-40f2-91eb-8148b2c09dfe" \
  --confirm \
  --output json --pretty
```

Only run that command after explicit approval to remove 1.8 from review.

Dry-run first when possible:

```bash
make asc-publish-appstore \
  ASC_EXPORT_OPTIONS=/absolute/path/to/ExportOptions.plist \
  ASC_APPSTORE_PUBLISH_VERSION=1.9 \
  ASC_APPSTORE_SUBMIT_FLAGS="--dry-run"
```

Build/upload/attach without submission:

```bash
make asc-publish-appstore \
  ASC_EXPORT_OPTIONS=/absolute/path/to/ExportOptions.plist \
  ASC_APPSTORE_PUBLISH_VERSION=1.9
```

Submit for App Review after validation:

```bash
make asc-publish-appstore \
  ASC_EXPORT_OPTIONS=/absolute/path/to/ExportOptions.plist \
  ASC_APPSTORE_PUBLISH_VERSION=1.9 \
  ASC_APPSTORE_SUBMIT_FLAGS="--submit --confirm"
```

`asc publish appstore --submit --confirm` is the canonical full App Store path
for the current CLI. Use `asc release stage` for metadata/build preparation
without submission, and `asc review submit` only when a version is already
prepared and a processed build ID is known.

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
asc validate --help
```

Useful direct commands:

```bash
asc builds list --app "6757725234" --version "1.9"
asc testflight groups list --app "6757725234"
asc status --app "6757725234"
```
