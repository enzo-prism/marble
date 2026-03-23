# asc cli reference

This repo is wired for `asc` around Marble's real App Store Connect app and
deterministic local artifact paths, so future Codex sessions should start here
instead of re-discovering the release setup.

## Marble Defaults

- App Store Connect app name: `marble.fit`
- App Store Connect app ID: `6757725234`
- Bundle ID: `Prism.marble`
- Xcode project: `marble.xcodeproj`
- Scheme: `marble`
- Team ID: `L49MKXGVM4`
- Archive path: `.asc/artifacts/marble.xcarchive`
- IPA path: `.asc/artifacts/marble.ipa`

## Fast Start

Use the repo shortcuts first:

```bash
make asc-auth
make asc-doctor
make asc-app
make asc-builds
make asc-version
make asc-archive
make asc-export ASC_EXPORT_OPTIONS=/absolute/path/to/ExportOptions.plist
```

Those targets already know the Marble app ID, scheme, project path, artifact
paths, the required archive destination wiring, and the marketing-version
fallback for this Xcode setup.

## New Machine Checklist

1. Confirm `asc` auth is healthy.
2. Confirm Xcode has the iOS `26.2` platform installed.
3. Confirm a usable `ExportOptions.plist` exists before trying to export/upload.

Recommended checks:

```bash
make asc-auth
make asc-doctor
make asc-version
```

If archive or test commands report "no destinations" or say iOS `26.2` is not
installed, fix Xcode first:

- Open Xcode
- Go to Settings > Components
- Install the iOS `26.2` platform/runtime

## Repo-Specific Commands

### Check auth + app wiring

```bash
make asc-auth
make asc-doctor
make asc-app
```

Direct equivalents:

```bash
asc auth status --output json --pretty
asc doctor --output json --pretty
asc apps --output json --pretty
```

### View recent Marble builds

```bash
make asc-builds
```

Direct equivalent:

```bash
asc builds list --app "6757725234" --sort -uploadedDate --limit 10 --output table
```

### View local project version/build

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

Use `asc xcode version --help` before editing/bumping versions.

### Create a deterministic archive

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

- This project needs an explicit generic iOS destination for `archive`
- Without it, `xcodebuild` can fail with "Found no destinations"

## Export / Upload Notes

No `ExportOptions.plist` is committed in this repo on purpose.

Use:

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

That keeps signing/export decisions explicit per machine instead of hiding them
in repo defaults that may not match the current Apple account or provisioning
setup.

## Helpful Low-Level Commands

Use `--help` instead of memorizing flags:

```bash
asc --help
asc xcode archive --help
asc xcode export --help
asc builds list --help
asc release run --help
asc testflight groups list --help
```

Useful direct commands:

```bash
asc builds list --app "6757725234" --version "1.5"
asc testflight groups list --app "6757725234"
asc status --app "6757725234"
```
