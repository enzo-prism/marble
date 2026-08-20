# Cloud Agent App Store / TestFlight publishing

Linux Cloud Agents cannot run `xcodebuild`. This repo splits shipping in two:

| Work | Where it runs | What it needs |
|---|---|---|
| Archive, sign, export, upload IPA | GitHub Actions `macos-26` (`release-testflight.yml`) | ASC API key **and** Apple Distribution `.p12` |
| Status, validate, attach, App Review submit, release an approved version | Linux agent **or** GitHub Actions `ubuntu-latest` (`release-appstore.yml`) | ASC API key only |

Agents drive both through `scripts/cloud_release.sh` / `make cloud-*`. They still must not bump builds, upload, submit, or release without explicit user approval.

## One-time setup (human, on the Mac that already ships)

GitHub Actions secrets cannot be written by the Cloud Agent token. Run this **once** on the Mac that archived builds 48–55.

### 1. Export the distribution identity

Keychain Access → **Apple Distribution: Lorenzo Quaid Sison (L49MKXGVM4)** — the cert used for the build-48 profiles (`9M47KCWLU8`) — export as `.p12`.

The two pinned profiles are already in git (`.asc/ExportOptions.plist`):

- `Prism marble App Store build 48 2026-07-24` (`G545NTS973`) → `Prism.marble`
- `Prism marble MarbleWidgets App Store build 48 2026-07-24` (`JF52GQ2SSV`) → `Prism.marble.MarbleWidgets`

Optional: copy those `.mobileprovision` files from `~/Library/Developer/Xcode/UserData/Provisioning Profiles/` (Xcode 16+) or `~/Library/MobileDevice/Provisioning Profiles/`. The TestFlight job downloads them via the ASC API when the API key is present; the files are only a fallback.

### 2. Write GitHub Actions secrets

```bash
P12_PATH=/path/to/AppleDistribution.p12 \
P12_PASSWORD='…' \
ASC_KEY_ID='…' \
ASC_ISSUER_ID='…' \
ASC_P8_PATH=/path/to/AuthKey_XXXXXXXXXX.p8 \
# optional:
# APP_PROFILE_PATH=/path/to/app.mobileprovision \
# WIDGET_PROFILE_PATH=/path/to/widget.mobileprovision \
scripts/bootstrap_github_release_secrets.sh
```

That sets:

| Secret | Used by |
|---|---|
| `ASC_KEY_ID` | TestFlight + App Store workflows |
| `ASC_ISSUER_ID` | TestFlight + App Store workflows |
| `ASC_PRIVATE_KEY_B64` | TestFlight + App Store workflows |
| `APPLE_DISTRIBUTION_P12_B64` | TestFlight archive/export only |
| `APPLE_DISTRIBUTION_P12_PASSWORD` | TestFlight archive/export only |
| `MOBILEPROVISION_APP_B64` | Optional TestFlight fallback |
| `MOBILEPROVISION_WIDGET_B64` | Optional TestFlight fallback |

The App Store Connect key needs **App Manager** (or Admin) so it can upload builds, submit review, and release.

### 3. Cursor Cloud Agent secrets (same ASC key)

Dashboard → Cloud Agents → Secrets, scoped to this repo:

- `ASC_KEY_ID`
- `ASC_ISSUER_ID`
- `ASC_PRIVATE_KEY_B64` (base64 of the `.p8`, same value as the GitHub secret)

Do **not** put the `.p12` in Cursor secrets. Linux VMs never sign.

`.cursor/environment.json` installs `asc` on Builds. After this file lands on `main`, trigger a Cloud Agent environment Build so later agents start with the CLI.

### 4. GitHub Environments (recommended)

The workflows declare `environment: testflight` and `environment: app-store`. GitHub creates them on first run. Then:

- **testflight** — no required reviewers (internal TestFlight is routine).
- **app-store** — add yourself as a required reviewer so submit/release wait for a human click even if an agent dispatches the job.

## Agent commands

```bash
make cloud-preflight          # what this VM can do
make cloud-status             # ASC status if secrets exist, else Actions runs

# TestFlight (always a macos-26 Actions job from Linux)
make cloud-testflight
make cloud-testflight DRY_RUN=1

# App Store API (runs here if ASC_* are in Cursor secrets)
make cloud-appstore-validate VERSION=2.4
make cloud-appstore-submit CONFIRM=submit VERSION=2.4
make cloud-appstore-release CONFIRM=release VERSION=2.3
```

Equivalent:

```bash
scripts/cloud_release.sh preflight
scripts/cloud_release.sh testflight
scripts/cloud_release.sh appstore-submit --version 2.4 --confirm
scripts/cloud_release.sh appstore-release --version 2.3 --confirm
```

Dispatch order:

1. `workflow_dispatch` via the git credential (often 403 for Cloud Agent tokens).
2. Fallback: annotated tag `publish/testflight/<utc>-<sha>` (or `publish/appstore-submit|<release>/<version>/…`) and `git push origin refs/tags/…`.

Do not force-push those tags. Do not upload `.ipa` artifacts from Actions — this repository is public.

## What each job actually runs

**TestFlight** (`scripts/ci_testflight.sh` on `macos-26`):

1. Import `.p12` into an ephemeral keychain; install the two App Store profiles.
2. `make asc-next-build` and refuse to upload if `CURRENT_PROJECT_VERSION` is behind ASC.
3. `make asc-archive`
4. `ASC_EXPORT_OPTIONS=$PWD/.asc/ExportOptions.plist make asc-export`
5. `asc builds upload --ipa .asc/artifacts/marble.ipa --wait`

Internal group **test group A** has `hasAccessToAllBuilds: true`; do not assign the build to it (the API rejects that).

**App Store submit** (`scripts/ci_appstore.sh submit`):

1. `asc validate` / review doctor
2. `asc release stage --build <VALID build> --confirm`
3. Create/submit the review submission

**App Store release** (`scripts/ci_appstore.sh release`):

- `asc versions release --version-id <id> --confirm` for an approved manual-release version (`PENDING_DEVELOPER_RELEASE` / `READY_FOR_DISTRIBUTION`).

## Local Mac path (unchanged)

If the agent is actually on a Mac with Xcode 26, signing identities, and ASC auth:

```bash
make asc-auth && make asc-next-build
make asc-archive
ASC_EXPORT_OPTIONS=$PWD/.asc/ExportOptions.plist make asc-export
asc builds upload --ipa "$PWD/.asc/artifacts/marble.ipa" --app 6757725234 --wait
```

`make cloud-testflight` on that Mac skips Actions and runs the staged local path.

## Safety

- No workflow runs on ordinary `main` pushes.
- Submit and release require `--confirm` / `CONFIRM=submit|release` / a `publish/appstore-*` tag.
- Do not cancel an in-flight review, replace a review build, or ship to customers unless the user asked.
- After a VALID TestFlight build, update `RELEASE_HANDOFF.md` with the build id.
