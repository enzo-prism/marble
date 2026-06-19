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
- Xcode project: `marble.xcodeproj`
- Scheme: `marble`
- Team ID: `L49MKXGVM4`
- Archive path: `.asc/artifacts/marble.xcarchive`
- IPA path: `.asc/artifacts/marble.ipa`
- Platform: `IOS`

## Release Safety

- Read `RELEASE_HANDOFF.md` before changing review state, build numbers, or
  release branches.
- The project version is now `1.9 (build 20)`; some command examples below still show
  `--version "1.8"` (the in-review App Store version) for illustration. Always run
  `make asc-version` before acting — the CLI can report a blank generated marketing
  version, so the Makefile prints a reliable fallback.
- Do not cancel an in-flight review, upload a replacement build, or submit to
  review without explicit user approval.
- Build numbers must move forward from App Store Connect state. Use
  `make asc-next-build`, not local guesses.
- Regenerate `.asc/artifacts/marble.xcarchive` and `.asc/artifacts/marble.ipa`
  from a clean branch for every release. Do not reuse stale artifacts.

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
fallback for this Xcode setup.

## New Machine Checklist

1. Upgrade `asc`.
2. Confirm auth storage and network validation.
3. Confirm Xcode has the required iOS platform installed.
4. Confirm a usable `ExportOptions.plist` exists before export/upload.
5. Confirm Apple agreements are current.

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
asc builds next-build-number --app "6757725234" --version "1.8" --platform IOS --output table
```

`asc validate` is the canonical App Store submission readiness report in the
current CLI. `asc review status` and `asc review doctor` are better for review
state and blocker diagnosis.

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

For external beta review submission:

```bash
make asc-publish-testflight \
  ASC_EXPORT_OPTIONS=/absolute/path/to/ExportOptions.plist \
  ASC_TESTFLIGHT_GROUP="External Testers" \
  ASC_TESTFLIGHT_FLAGS="--submit --confirm"
```

### Canonical App Store Publish

Dry-run first when possible:

```bash
asc publish appstore \
  --app "6757725234" \
  --project marble.xcodeproj \
  --scheme marble \
  --configuration Release \
  --archive-path .asc/artifacts/marble.xcarchive \
  --export-options /absolute/path/to/ExportOptions.plist \
  --ipa-path .asc/artifacts/marble.ipa \
  --archive-xcodebuild-flag=-destination \
  --archive-xcodebuild-flag=generic/platform=iOS \
  --version "1.8" \
  --dry-run --output json --pretty
```

Build/upload/attach without submission:

```bash
make asc-publish-appstore ASC_EXPORT_OPTIONS=/absolute/path/to/ExportOptions.plist
```

Submit for App Review after validation:

```bash
make asc-publish-appstore \
  ASC_EXPORT_OPTIONS=/absolute/path/to/ExportOptions.plist \
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
asc builds list --app "6757725234" --version "1.8"
asc testflight groups list --app "6757725234"
asc status --app "6757725234"
```
