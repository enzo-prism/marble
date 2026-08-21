# Codex workflow papercuts

- Date: 2026-07-09
  Workflow: Marble iOS app and codebase audit
  Papercut: No iOS Simulator device was booted, and the preferred Xcode simulator-control tools were unavailable in this session.
  Impact: The review can verify source, architecture, and generic compilation, but cannot capture a fresh interactive app flow without user-side simulator setup.
  Suggested fix: Keep a named Marble audit simulator available and expose the Xcode simulator-control tools in Codex sessions.

- Date: 2026-07-09
  Workflow: Marble design verification
  Papercut: `AGENTS.md` references `scripts/design-check.sh`, but that script is absent.
  Impact: The documented design check cannot be run.
  Suggested fix: Add the script or remove the stale instruction.

- Date: 2026-07-09
  Workflow: Marble TestFlight publishing
  Papercut: `make asc-publish-testflight` accepted an export plist with `destination=upload`, but the current `asc publish testflight` command requires a plist that produces a local IPA.
  Impact: The first publish attempt stopped before archive/upload and had to be rerun with `.asc/ExportOptions.plist`.
  Suggested fix: Preflight the plist destination in the Make target and explain that `destination=export` is required.

- Date: 2026-07-09
  Workflow: Marble UI release gate
  Papercut: `make ui` also included the five-minute accessibility audit despite a separate `make audit` target, causing iOS 26.5 Simulator responsiveness to degrade late in the combined run.
  Impact: Otherwise-green UI tests produced timeout-only failures after more than 20 minutes.
  Suggested fix: Keep `make ui` scoped to interaction flows and run `make audit` as its own release gate.

- Date: 2026-07-10
  Workflow: Marble SwiftData migration and TestFlight release gate
  Papercut: Migration tests created the old schema with the candidate binary before opening the new schema, which primed SwiftData differently from a real previous-release upgrade; the archived Release app was not installed over build 34 and launch-smoke-tested.
  Impact: Build 35 passed Debug tests and archive validation but crashed before its first frame for users with a build-34 database.
  Suggested fix: Add a Release gate that installs the previous shipped app, seeds its real store, overlays the candidate app, launches it, and fails on any termination or uncaught exception.

- Date: 2026-07-10
  Workflow: Marble TestFlight live-state verification
  Papercut: The installed `asc` release uses `asc builds info`; the initially expected `asc builds get` subcommand no longer exists.
  Impact: The first read-only verification command stopped before the remaining chained checks ran.
  Suggested fix: Keep repo release docs and examples aligned with `asc builds --help`, or add a stable project wrapper for build lookup.

- Date: 2026-07-12
  Workflow: Marble sprint-result UI verification
  Papercut: Xcode UI-test video and result-bundle recording exhausted the nearly full internal disk even for one focused test.
  Impact: The first interaction assertion exposed and fixed an off-screen test navigation issue, but later reruns failed in test-runner artifact creation before they could produce reliable UI evidence.
  Suggested fix: Keep DerivedData and result bundles in ignored checkout-local directories on the FileVault-protected internal disk, allow explicit internal path overrides, and disable retained screen recordings for routine focused checks. PortableSSD is retired.

- Date: 2026-07-25
  Workflow: Marble Swift 6 language-mode migration (build 49)
  Papercut: Each isolation error had to be found by a full `make unit` cycle (~7 minutes), because the app target compiles clean while the test targets fail one file at a time — and the errors are per-file, not batched.
  Impact: Ten build cycles to migrate what was ~15 small annotations; the app + widget were clean after four.
  Suggested fix: Add a `make typecheck-tests` target that builds the test bundles only (`xcodebuild build-for-testing -destination ... -only-testing:MarbleTests`) with no simulator boot, and run it before `make unit` during migrations.

- Date: 2026-07-25
  Workflow: Marble simulator builds
  Papercut: An `xcodebuild` run killed by a tool timeout left `XCBBuildService` in a state where the next invocation hung at `ExecuteExternalTool clang -E -dM` indefinitely, producing no output and no error.
  Impact: Two ~10-minute build slots lost before the cause was clear; `pkill -f xcodebuild` plus a fresh invocation cleared it.
  Suggested fix: Prefer long explicit timeouts over killing xcodebuild mid-run, and if a build produces no compile lines within a minute, kill every `xcodebuild`/`XCBBuildService` process before retrying.

- Date: 2026-07-25
  Workflow: Marble snapshot suite (build 49)
  Papercut: Every snapshot baseline had silently gone stale — `testTrendsPopulated` fails on clean `main` because its reference predates the Trends 2.0 Focus card. CI runs `make unit` only, so nothing noticed.
  Impact: A "green" snapshot suite was in fact unrunnable, and the drift only surfaced when a new suite was added alongside it.
  Suggested fix: Either run `make snapshot` on a schedule (or in CI on a pinned runner image) or drop the suites that cannot be kept honest; a baseline nobody runs is not coverage.

- Date: 2026-07-25
  Workflow: Marble snapshot + record runs
  Papercut: Two `xcodebuild test` runs against the same booted simulator (a verification pass and a record pass started in parallel) killed one group with "Early unexpected exit, operation never finished bootstrapping".
  Impact: One group of an otherwise green 27-group verification had to be re-run, and the failure looked like a product defect rather than contention.
  Suggested fix: Serialise simulator work — `run_snapshot_suite.sh` could take a lock file so a second invocation waits instead of racing.

- Date: 2026-08-17
  Workflow: Cloud Agent TestFlight / App Store publishing
  Papercut: Linux Cloud Agents cannot `xcodebuild` archive, and the Cloud Agent GitHub token cannot list or set Actions secrets (`Resource not accessible by integration`).
  Impact: Agents could not ship 2.3 build 56 even with a green unit CI.
  Suggested fix: Keep archive/export/upload on GitHub Actions `macos-26` (`release-testflight.yml`); keep submit/release as ASC API (`release-appstore.yml` / `scripts/ci_appstore.sh`). A human runs `scripts/bootstrap_github_release_secrets.sh` once on the Mac that already signs. Agents use `make cloud-*` (see `CLOUD_RELEASE.md`).

- Date: 2026-08-16
  Workflow: Cloud Agent docs + iOS CI
  Papercut: Linux Cloud Agents cannot run `xcodebuild`. Putting `marble/AppIcon.icon/` in the filesystem-synchronized `marble/` group crashed CI `actool` (`attempt to insert nil object`).
  Impact: Unit CI failed after compile of the widget target succeeded; TestFlight cannot be uploaded from this VM.
  Suggested fix: Keep Icon Composer packages as explicit Xcode package file refs, not loose files under `marble/`. Archive/upload only on a Mac (`RELEASE_HANDOFF.md`).

- Date: 2026-08-21
  Workflow: Marble release-source reconciliation and local test gate
  Papercut: Release docs still described 2.1 as live and 2.3 as pending after 2.3 had shipped, while Xcode inherited a DerivedData location on the retired PortableSSD.
  Impact: A future release agent could target the wrong App Store version, choose the wrong migration baseline, or fail before tests began.
  Suggested fix: Keep the current release snapshot at the top of `RELEASE_HANDOFF.md`, pin `make migration-release` to the shipped source commit, and route every Make test target through the checkout-local `DERIVED_DATA_PATH` seam.
