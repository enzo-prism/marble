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
source_sha="$(git rev-parse HEAD)"
assert_clean_source() {
  [[ "$(git rev-parse HEAD)" == "$source_sha" ]] && git diff --quiet HEAD -- &&
    [[ -z "$(git ls-files --others --exclude-standard)" ]] || {
      echo "error: upload requires an unchanged, committed source checkout" >&2
      exit 1
    }
}
assert_clean_source
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
assert_clean_source
ipa_digest="$(shasum -a 256 "$IPA_PATH" | awk '{print $1}')"
upload_args=(
  builds upload
  --app "$MARBLE_ASC_APP_ID"
  --ipa "$IPA_PATH"
  --output json
  --pretty
)
if [[ "$WAIT" -eq 1 ]]; then
  # asc 4.5 dropped `--timeout` on `builds upload`. `--wait` polls until
  # processing finishes; `--verify-timeout` only watches the post-commit
  # window for immediate upload failures.
  upload_args+=(--wait --poll-interval "${ASC_POLL_INTERVAL:-30s}" --verify-timeout "${ASC_VERIFY_TIMEOUT:-2m}")
fi

asc "${upload_args[@]}"

if [[ "$WAIT" -eq 1 ]]; then
  assert_clean_source
  [[ "$(shasum -a 256 "$IPA_PATH" | awk '{print $1}')" == "$ipa_digest" ]] || {
    echo "error: IPA changed during upload; receipt cannot be generated" >&2
    exit 1
  }
  build_json="$(asc builds list --app "$MARBLE_ASC_APP_ID" --version "$marketing" --build-number "$project_build" --output json)"
  uploaded_id="$(printf '%s' "$build_json" | jq -er --arg number "$project_build" '[.data[] | select(.attributes.version == $number and .attributes.processingState == "VALID")] | if length == 1 then .[0].id else error("Expected exactly one VALID uploaded build") end')"
  ruby scripts/write_upload_receipt.rb "$ROOT/.asc/artifacts/upload-receipts" "$source_sha" "$MARBLE_ASC_APP_ID" "$marketing" "$project_build" "$uploaded_id" "$IPA_PATH"
else
  echo "Upload processing not verified; no production upload receipt was generated."
fi

echo "=== recent builds ==="
asc builds list --app "$MARBLE_ASC_APP_ID" --sort -uploadedDate --limit 5 --output table || true
echo "TestFlight upload complete. Internal group 'test group A' auto-receives VALID builds."
