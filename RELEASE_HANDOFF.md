# Marble Release Handoff

Last verified: 2026-06-17 in this checkout. Refresh live state before acting,
because App Store review and build state can change outside git.

## Current Snapshot

- Canonical release baseline: `origin/main` at `56c5943 Prepare Marble 1.8 build 19`.
- Local `main` should track `origin/main` and stay clean for release work.
- Local project version: `1.8 (19)` via `make asc-version`.
- App Store Connect app: `marble.fit`, app ID `6757725234`, bundle ID `Prism.marble`.
- App Store version `1.8` is `WAITING_FOR_REVIEW`; `make asc-status` reports no blockers.
- Submitted review build: `1.8 (17)`, build ID `19a40282-f054-4280-b805-c260c12c22f8`.
- Latest uploaded valid build: `1.8 (19)`, build ID `6ae54674-728f-4b3e-9e61-efe5b88867bb`.
- Next build number: `20`.
- iPhone simulator runtime was missing on this Mac at last check; install the required Xcode iOS platform before running tests.

## Cleanup Branches

These branches are local to this checkout unless someone later pushes them.

- `backup/empire-gamification-dirty-20260617-105344`
  preserves the full dirty `empire-gamification` worktree as one WIP commit.
  Treat it as a rescue/source branch, not a release branch.
- `backup/main-stale-20260617-105344`
  preserves the old stale local `main` before local `main` was reset to
  `origin/main`.
- `feature/empire-gamification-refresh`
  starts from `origin/main` and cherry-picks the useful Empire gamification
  commits while keeping the release build settings at `1.8 (19)`.
- `feature/progress-media-polish`
  starts from `origin/main` and contains only the progress media crop/editing
  polish extracted from the dirty backup branch.

## Release Rules

- Do not cancel the current App Store review by default.
- If build `17` is approved, ship it unless a confirmed blocker exists.
- If build `17` must be replaced, create `release/1.8-build-20` from clean
  `origin/main` plus only approved fixes, then bump/upload build `20`.
- Never reuse stale local `.asc` archives or IPAs. Regenerate release artifacts
  from a clean release branch.
- Keep signing/export files and generated artifacts under ignored `.asc/` unless
  there is an explicit reason to commit a sanitized template.
- Do not introduce public API or SwiftData model changes during release cleanup
  unless that change is the deliberate fix being released.

## Agent Startup Checklist

Run these before release-sensitive work:

```bash
git fetch --all --prune
git status --short --branch
git branch -vv
make asc-version
make asc-status
make asc-builds
make asc-next-build
```

For code changes, install an available iPhone simulator runtime first, then run:

```bash
make test
```

For UI or feature branches, also run:

```bash
make ui
make audit
```
