#!/usr/bin/env bash
# Archive, export, and upload Marble to TestFlight from a macOS runner.
# Staged path (archive → export → builds upload --wait). Does not assign
# "test group A" — that internal group already has hasAccessToAllBuilds.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/marble_release.sh
source "${SCRIPT_DIR}/lib/marble_release.sh"

ROOT="$(marble_repo_root)"
cd "$ROOT"

DRY_RUN=0
WAIT=1
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --no-wait) WAIT=0 ;;
    *) echo "unknown argument: $arg" >&2; exit 2 ;;
  esac
done

if ! marble_is_macos; then
  echo "error: ci_testflight.sh must run on macOS with Xcode 26" >&2
  exit 1
fi

marble_require_cmd asc
marble_require_cmd xcodebuild
marble_require_cmd jq
marble_export_asc_ci

if ! marble_asc_env_ready; then
  echo "error: ASC_KEY_ID, ASC_ISSUER_ID, and ASC_PRIVATE_KEY_B64 (or PATH/PEM) are required" >&2
  exit 1
fi

EXPORT_OPTIONS="${ASC_EXPORT_OPTIONS:-${ROOT}/.asc/ExportOptions.plist}"
if [[ ! -f "$EXPORT_OPTIONS" ]]; then
  echo "error: export options not found: $EXPORT_OPTIONS" >&2
  exit 1
fi

marketing="$(marble_marketing_version "$ROOT")"
project_build="$(marble_project_build "$ROOT")"
echo "Local version: ${marketing} (${project_build})"

echo "=== ASC auth ==="
asc auth status --validate --output json --pretty || true

echo "=== next build number for ${marketing} ==="
next_json="$(asc builds next-build-number --app "$MARBLE_ASC_APP_ID" --version "$marketing" --platform "$MARBLE_PLATFORM" --output json --pretty || true)"
printf '%s\n' "$next_json"
next_build="$(printf '%s' "$next_json" | jq -r '
  .nextBuildNumber // .next_build_number // .data.nextBuildNumber // .data // empty
' 2>/dev/null || true)"
if [[ -n "$next_build" && "$next_build" != "null" ]]; then
  if [[ "$project_build" =~ ^[0-9]+$ && "$next_build" =~ ^[0-9]+$ && "$project_build" -lt "$next_build" ]]; then
    echo "error: project CURRENT_PROJECT_VERSION=${project_build} is behind ASC next-build ${next_build}" >&2
    echo "Bump CURRENT_PROJECT_VERSION in marble.xcodeproj before uploading." >&2
    exit 1
  fi
fi

echo "=== archive ==="
make asc-archive

echo "=== export ==="
ASC_EXPORT_OPTIONS="$EXPORT_OPTIONS" make asc-export

IPA_PATH="${ASC_IPA_PATH:-${ROOT}/.asc/artifacts/marble.ipa}"
if [[ ! -f "$IPA_PATH" ]]; then
  echo "error: IPA not produced at $IPA_PATH" >&2
  exit 1
fi
echo "IPA: $IPA_PATH ($(du -h "$IPA_PATH" | awk '{print $1}'))"

if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "dry-run: skipping TestFlight upload"
  exit 0
fi

echo "=== upload ==="
upload_args=(
  builds upload
  --app "$MARBLE_ASC_APP_ID"
  --ipa "$IPA_PATH"
  --output json
  --pretty
)
if [[ "$WAIT" -eq 1 ]]; then
  upload_args+=(--wait --timeout "${ASC_UPLOAD_TIMEOUT:-45m}")
fi

asc "${upload_args[@]}"

echo "=== recent builds ==="
asc builds list --app "$MARBLE_ASC_APP_ID" --sort -uploadedDate --limit 5 --output table || true
echo "TestFlight upload complete. Internal group 'test group A' auto-receives VALID builds."
