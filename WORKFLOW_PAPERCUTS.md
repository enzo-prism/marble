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
  Suggested fix: Add a low-artifact UI-test wrapper that preflights free space, stores result bundles on PortableSSD when mounted, and disables retained screen recordings for routine focused checks.
